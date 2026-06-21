import Foundation

/// Opt-in, anonymous, **on-device** feedback to help improve the filler model.
///
/// When the user turns it on, each clean that used the filler classifier appends a
/// tiny JSON record to `~/.crisp*/feedback/<yyyy-MM-dd>.jsonl`. It records only
/// **counts and durations + the model version** — never audio, never filenames,
/// never any content, and no precise timestamp (the day is the filename). Nothing
/// is uploaded; the file stays on the user's Mac. A future opt-in step could offer
/// to share it, but that's a separate, explicit choice.
public enum FillerFeedback {
    public static var directory: URL {
        Channel.current.dataDirectory.appendingPathComponent("feedback", isDirectory: true)
    }

    /// Append one anonymous record for a filler-model clean. Best-effort: any I/O
    /// failure is silently ignored (feedback must never disrupt a clean).
    public static func record(modelID: String, fillers: Int, origSeconds: Double, savedSeconds: Double) {
        let rec: [String: Any] = [
            "model": modelID,
            "fillers": fillers,
            "orig_seconds": (origSeconds * 100).rounded() / 100,
            "saved_seconds": (savedSeconds * 100).rounded() / 100
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: rec) else { return }
        line.append(0x0A)   // newline → JSONL

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let file = directory.appendingPathComponent("\(df.string(from: Date())).jsonl")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let fh = try? FileHandle(forWritingTo: file) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: line)
        } else {
            try? line.write(to: file, options: .atomic)
        }
    }
}
