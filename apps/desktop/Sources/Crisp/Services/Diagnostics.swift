import AppKit
import CrispCore

/// Diagnostics actions the UI can trigger. Keeps the filesystem / `NSWorkspace`
/// side effects out of the views (which only display) — the Settings "Logs" row
/// calls in here.
enum Diagnostics {
    /// Reveal today's log in Finder, or the logs folder itself if nothing's been
    /// written yet this run. Creates the folder first so the action always lands
    /// somewhere.
    static func revealLogs() {
        let dir = Channel.current.logsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let today = FileLog.shared.currentLogFileURL()
        if FileManager.default.fileExists(atPath: today.path) {
            NSWorkspace.shared.activateFileViewerSelecting([today])
        } else {
            NSWorkspace.shared.open(dir)
        }
    }
}
