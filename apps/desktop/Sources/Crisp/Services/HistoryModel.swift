import AppKit
import CrispCore

/// Owns the History window's data and the filesystem side effects behind it
/// (load/clear/reveal), so `HistoryView` stays display-only. Backed by the
/// append-only `HistoryStore`.
@MainActor
@Observable
final class HistoryModel {
    private(set) var entries: [HistoryEntry] = []

    /// Reload the list. The read + JSON-decode happen off the main actor (the file
    /// can be large and this runs on every clean completion while the window is open).
    func reload() {
        Task { entries = await HistoryStore.shared.loadAsync() }
    }

    func clear() {
        HistoryStore.shared.clear()
        entries = []
    }

    /// Whether the original source still exists (gates "Clean Again").
    func sourceExists(_ entry: HistoryEntry) -> Bool {
        FileManager.default.fileExists(atPath: entry.inputPath)
    }

    /// Reveal the cleaned output in Finder, or the source if the output is gone.
    func reveal(_ entry: HistoryEntry) {
        if let out = entry.outputURL, FileManager.default.fileExists(atPath: out.path) {
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } else if sourceExists(entry) {
            NSWorkspace.shared.activateFileViewerSelecting([entry.inputURL])
        }
    }
}
