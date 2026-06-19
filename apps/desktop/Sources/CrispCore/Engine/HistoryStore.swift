import Foundation

/// Persists a record of every completed clean to `~/.crisp*/history.jsonl` and reads
/// it back for the History window. Append-only, one JSON object per line, written
/// with a single `O_APPEND` `write()` — the same process-safe pattern as the logs.
/// That matters because the background watch-folder agent is a *separate process*
/// from the app: both can finish a clean at the same moment, and append-only with
/// `O_APPEND` lets them share one file without a read-modify-write race that would
/// drop entries. `CleanRunner` records here on success, so the queue, the watcher,
/// the App Intent, and the menu-bar drop all show up automatically.
public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).history")
    private let fm = FileManager.default

    private init() {}

    /// `~/.crisp*/history.jsonl`, beside `logs/`, `models/`, `Originals/`.
    public var fileURL: URL {
        Channel.current.dataDirectory.appendingPathComponent("history.jsonl")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Serialize one entry to its newline-terminated JSON line. Pure (no I/O) so the
    /// round-trip can be unit-tested without touching the data home.
    public static func encodeLine(_ entry: HistoryEntry) -> Data? {
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }

    /// Parse newline-delimited entries, newest first, up to `limit`. Malformed lines
    /// are skipped so a partial last write (or a future schema) never breaks the
    /// list. Pure (no I/O).
    public static func parse(_ text: String, limit: Int = 500) -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            if entries.count >= limit { break }
            if let data = line.data(using: .utf8),
               let entry = try? decoder.decode(HistoryEntry.self, from: data) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Append one entry (best-effort, off the caller's thread). One whole-line
    /// `O_APPEND` write keeps it atomic against the watcher process.
    public func record(_ entry: HistoryEntry) {
        queue.async {
            guard let data = Self.encodeLine(entry) else { return }
            try? self.fm.createDirectory(at: self.fileURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
            // 0o600: history holds file paths — keep it readable only by the owner.
            let fd = open(self.fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
            guard fd >= 0 else { return }
            defer { close(fd) }
            data.withUnsafeBytes { buf in
                guard let base = buf.baseAddress else { return }
                // Deliberately one write() — for a line-sized append to a local file
                // it's all-or-nothing, and O_APPEND makes that single call atomic
                // against the watcher process. A short-write retry loop would split
                // the record across two appends, which a concurrent process could
                // interleave; a truncated line on the (practically impossible) short
                // write is preferable, and parse() skips it.
                _ = Darwin.write(fd, base, buf.count)
            }
        }
    }

    /// The most recent entries first, up to `limit`. Malformed lines are skipped.
    public func load(limit: Int = 500) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Self.parse(text, limit: limit)
    }

    /// Same as `load`, but the file read + JSON decode run on the store's serial queue
    /// instead of the caller's thread — so the History window can refresh without
    /// blocking the main actor (it reloads on every clean completion).
    public func loadAsync(limit: Int = 500) async -> [HistoryEntry] {
        await withCheckedContinuation { continuation in
            queue.async {
                let text = (try? String(contentsOf: self.fileURL, encoding: .utf8)) ?? ""
                continuation.resume(returning: Self.parse(text, limit: limit))
            }
        }
    }

    /// Trim the file to its most recent `keeping` lines so it can't grow forever.
    /// Run at launch. (A rare race with a concurrent watcher append at the exact
    /// trim instant could drop one just-written entry — acceptable for a history
    /// log, and only possible when already over the cap.)
    public func prune(keeping: Int = 2000) {
        queue.async {
            guard let text = try? String(contentsOf: self.fileURL, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            guard lines.count > keeping else { return }
            let kept = lines.suffix(keeping).joined(separator: "\n") + "\n"
            try? kept.data(using: .utf8)?.write(to: self.fileURL, options: .atomic)
        }
    }

    /// Forget all history.
    public func clear() {
        queue.async { try? self.fm.removeItem(at: self.fileURL) }
    }
}
