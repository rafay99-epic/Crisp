import Foundation
import os

/// Severity of a log line. The raw value is what gets written to the file, so it
/// stays in sync with what the Python engine writes (`crisp/enginelog.py`) — one
/// daily file holds both sides of a clean, in one vocabulary.
public enum CrispLogLevel: String, Sendable {
    case debug  = "DEBUG"
    case info   = "INFO"
    case notice = "NOTICE"
    case error  = "ERROR"
}

/// Mirrors the `privacy:` annotation our call sites pass to `os.Logger`, so a
/// message written for unified logging routes through `CrispLog` **unchanged**.
/// Crisp's file log lives only on the user's own machine, so the value is always
/// recorded in full — the annotation is accepted to keep call sites identical,
/// and ignored for the file.
public enum CrispLogPrivacy: Sendable { case `public`, `private`, auto, sensitive }

/// A log message built from a string literal or interpolation. The interpolation
/// accepts the same `\(value, privacy: …)` form `os.Logger` uses, so existing
/// `logger.error("… \(x, privacy: .public)")` call sites compile verbatim once
/// `AppInfo.logger` returns a `CrispLog`.
public struct CrispLogMessage: ExpressibleByStringInterpolation, Sendable {
    public let text: String
    public init(stringLiteral value: String) { self.text = value }
    public init(stringInterpolation: Interpolation) { self.text = stringInterpolation.text }

    public struct Interpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation<T>(_ value: @autoclosure () -> T,
                                                    privacy: CrispLogPrivacy = .public) {
            text += String(describing: value())
        }
    }
}

/// A logger for one `category` that tees every line to **both** Apple's unified
/// logging (so `Console.app` / `log stream` keep working) **and** Crisp's own
/// daily file (so there's a persistent record to debug from after the fact).
/// Obtained from `AppInfo.logger(_:)`.
public struct CrispLog: Sendable {
    public let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: AppInfo.bundleIdentifier, category: category)
    }

    public func debug(_ message: CrispLogMessage) { emit(.debug, message.text) }
    public func info(_ message: CrispLogMessage) { emit(.info, message.text) }
    public func notice(_ message: CrispLogMessage) { emit(.notice, message.text) }
    public func error(_ message: CrispLogMessage) { emit(.error, message.text) }

    private func emit(_ level: CrispLogLevel, _ message: String) {
        switch level {
        case .debug:  osLogger.debug("\(message, privacy: .public)")
        case .info:   osLogger.info("\(message, privacy: .public)")
        case .notice: osLogger.notice("\(message, privacy: .public)")
        case .error:  osLogger.error("\(message, privacy: .public)")
        }
        FileLog.shared.write(level: level, category: category, message: message)
    }
}

/// The file sink behind every `CrispLog`: an append-only, daily-rotating log under
/// `~/.crisp*/logs/<yyyy-MM-dd>.log` (per channel, beside `Originals/` and
/// `models/`). Writes go through a private serial queue and use `O_APPEND`, so the
/// app, the watch-folder agent, the Finder helper, and several parallel engine
/// subprocesses can all append to the same day's file without a lock or torn
/// lines (POSIX makes line-sized `O_APPEND` writes atomic). The Python engine
/// writes to the very same file (`crisp/enginelog.py`), so one timeline shows the
/// UI and the engine together.
public final class FileLog: @unchecked Sendable {
    public static let shared = FileLog()

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).filelog")
    private let fm = FileManager.default
    private var fd: Int32 = -1
    private var openDay: String?

    private init() {}

    /// `~/.crisp*/logs/` for the running channel.
    public var directory: URL { Channel.current.logsDirectory }

    /// Today's log file (the one currently being appended to). Uses a throwaway
    /// formatter rather than the write queue, so a UI caller (e.g. "Reveal in
    /// Finder") never blocks behind a backlog of queued writes.
    public func currentLogFileURL() -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return directory.appendingPathComponent("\(f.string(from: Date())).log")
    }

    /// Append one line. The timestamp is captured now; the actual write is async on
    /// the serial queue so logging never blocks the caller.
    public func write(level: CrispLogLevel, category: String, message: String) {
        let now = Date()
        queue.async {
            let stamp = Self.lineFormatter.string(from: now)
            let lvl = level.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)
            let prefix = "\(stamp)  \(lvl)  [\(category)]  "
            // One prefixed physical line per record line, so a multi-line message
            // stays self-describing and matches the engine's file format.
            for sub in message.split(separator: "\n", omittingEmptySubsequences: false) {
                self.append("\(prefix)\(sub)\n", on: now)
            }
        }
    }

    /// Drop log files older than `days` so the folder doesn't grow without bound.
    /// Called once at launch.
    public func pruneOldLogs(keepingDays days: Int = 30) {
        queue.async {
            guard let items = try? self.fm.contentsOfDirectory(
                at: self.directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for url in items where url.pathExtension == "log" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
                if modified < cutoff { try? self.fm.removeItem(at: url) }
            }
        }
    }

    // MARK: - Private (serial queue only)

    private func append(_ line: String, on date: Date) {
        let day = Self.dayFormatter.string(from: date)
        if day != openDay { rotate(to: day) }
        guard fd >= 0 else { return }
        // One `write()` syscall for the whole line: with O_APPEND that makes the
        // append atomic against the other processes sharing this daily file (the
        // engine, the watcher, parallel cleans), so lines never interleave. A
        // `FileHandle.write` could split into several syscalls and break that.
        let bytes = Array(line.utf8)
        bytes.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            _ = Darwin.write(fd, base, buf.count)
        }
    }

    private func rotate(to day: String) {
        if fd >= 0 { close(fd); fd = -1 }
        openDay = nil
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(day).log")
        // O_APPEND so concurrent writers (parallel cleans, the watcher, the engine)
        // each land at end-of-file atomically rather than clobbering one another.
        // 0o600: the log holds file paths and tool diagnostics — user-only.
        let newFd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard newFd >= 0 else { return }
        fd = newFd
        openDay = day
    }

    /// `2026-06-19 14:03:22.123` — fixed locale so it never shifts with the user's
    /// region; matches the format the Python engine writes for one merged timeline.
    private static let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// `2026-06-19` — the per-day file name, in local time so a "day" matches the
    /// user's calendar.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
