import AppKit
import CrispCore

/// Recovering the pristine original from Crisp's dated backup folder. Crisp never
/// touches the source, but the backup lives tucked away under `~/.crisp*/Originals/`,
/// so these give a one-click way to find it or copy it back somewhere handy. Kept
/// out of the views (which only display).
enum Restore {
    private static let log = AppInfo.logger("restore")

    /// Reveal the backed-up original in Finder.
    static func revealBackup(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copy the backed-up original into a folder the user picks (defaulting beside the
    /// source). Never overwrites — dedupes the name — then reveals the restored file.
    static func restoreOriginal(backupPath: String, sourcePath: String?) {
        let backup = URL(fileURLWithPath: backupPath)
        guard FileManager.default.fileExists(atPath: backup.path) else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Restore Here"
        panel.message = "Choose where to restore the original \u{201C}\(backup.lastPathComponent)\u{201D}."
        if let sourcePath {
            panel.directoryURL = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        let dest = uniqueDestination(in: dir, name: backup.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: backup, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            log.error("Couldn't restore original: \(error.localizedDescription)")
        }
    }

    /// A path in `dir` for `name` that doesn't already exist (`foo.mov` → `foo_1.mov`),
    /// so restoring never clobbers an existing file.
    private static func uniqueDestination(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        let first = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: first.path) else { return first }
        let base = first.deletingPathExtension().lastPathComponent
        let ext = first.pathExtension
        var i = 1
        while true {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
