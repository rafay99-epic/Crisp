import AppKit

/// One shared single-folder chooser for every "pick a folder" control — the watch
/// folder and the output folder, in both Settings and onboarding. One component
/// instead of a copy per call site ("one system, not two").
enum FolderPicker {
    /// Present an open panel for a single directory. Returns the chosen path, or
    /// nil if the user cancelled.
    static func choosePath(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
