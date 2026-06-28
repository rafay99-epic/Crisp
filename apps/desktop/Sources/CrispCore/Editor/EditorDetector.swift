import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A video editor Crisp can hand a cut timeline to.
public struct VideoEditor: Identifiable, Equatable, Sendable {
    public let id: String        // bundle identifier that matched
    public let name: String      // display name, e.g. "DaVinci Resolve"
    public let appURL: URL       // where the app is installed
    public init(id: String, name: String, appURL: URL) {
        self.id = id; self.name = name; self.appURL = appURL
    }
}

/// Detects installed video editors and opens handoff artifacts in them.
///
/// v1 targets **DaVinci Resolve** (the only editor whose free edition can import a
/// timeline without a paid scripting API). Resolve ships under several bundle ids
/// depending on how it was installed — the direct download, the App Store free
/// "Lite" build, and the App Store Studio build — so we look up each known id rather
/// than guess a path. (Confirmed on a real machine: the App Store free edition is
/// `com.blackmagic-design.DaVinciResolveLite`, which a path/name guess would miss.)
public enum EditorDetector {
    /// Known DaVinci Resolve bundle identifiers, most-specific first.
    public static let resolveBundleIDs = [
        "com.blackmagic-design.DaVinciResolve",        // direct download (free or Studio)
        "com.blackmagic-design.DaVinciResolveLite",    // App Store, free edition
        "com.blackmagic-design.DaVinciResolveAppStore"  // App Store, Studio
    ]

    /// The installed DaVinci Resolve, or nil. Pure core (testable) — `lookup` maps a
    /// bundle id to the app URL if installed.
    public static func firstInstalled(name: String, ids: [String],
                                      lookup: (String) -> URL?) -> VideoEditor? {
        for id in ids {
            if let url = lookup(id) {
                return VideoEditor(id: id, name: name, appURL: url)
            }
        }
        return nil
    }

    #if canImport(AppKit)
    /// The installed DaVinci Resolve via LaunchServices (location-independent).
    public static func resolve() -> VideoEditor? {
        firstInstalled(name: "DaVinci Resolve", ids: resolveBundleIDs) { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
    }

    /// Every supported editor that's installed — the list shown in the "open in
    /// editor" picker. Only DaVinci Resolve today; Final Cut / Premiere can be added
    /// here later without touching the UI.
    public static func installed() -> [VideoEditor] {
        [resolve()].compactMap { $0 }
    }

    /// Launch `editor` (no document — Resolve won't auto-import a passed FCPXML, so the
    /// handoff opens the app and reveals the timeline file separately, see `openForImport`).
    public static func launch(_ editor: VideoEditor) {
        NSWorkspace.shared.openApplication(at: editor.appURL,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }

    /// Reveal a file/folder in Finder (the project the user then imports).
    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Hand a finished handoff off for the (manual) import: launch the editor *and*, when
    /// the result is an editor export, reveal its `.fcpxml` in Finder (selected) — so by
    /// the time the editor is up the file is right there to drag in or pick via File ▸
    /// Import ▸ Timeline. With nothing to surface (no timeline file) it just opens the
    /// editor. This is the single open policy every call site shares (picker, row button,
    /// context menu) so they can't drift. Free Resolve can't auto-import (no external
    /// scripting API — verified on a real machine), so this is the tightest honest loop.
    public static func openForImport(_ editor: VideoEditor, result: CleanResult?) {
        launch(editor)
        if let timeline = timelineFile(for: result) { reveal(timeline) }
    }

    /// Reveal a handoff's project folder in Finder (the folder the user imports from).
    public static func revealProject(for result: CleanResult?) {
        if let folder = projectFolder(for: result) { reveal(folder) }
    }
    #endif

    /// The timeline file to surface for a finished handoff, or nil when there's nothing to
    /// reveal (not an editor export, or no path recorded). Pure, so the open policy is
    /// testable without driving Finder.
    public static func timelineFile(for result: CleanResult?) -> URL? {
        guard let result, result.exportTimeline == "fcpxml", !result.output.isEmpty else { return nil }
        return URL(fileURLWithPath: result.output)
    }

    /// The project folder for an editor handoff (its `<name> (Crisp)` dir), falling back to
    /// the timeline file's location, or nil when this isn't an editor export or neither is
    /// recorded. Gated on `exportTimeline == "fcpxml"` (like `timelineFile`) so it never
    /// returns a *rendered* clip's path — keeps "editor handoff only" honest. Pure/testable.
    public static func projectFolder(for result: CleanResult?) -> URL? {
        guard let result, result.exportTimeline == "fcpxml" else { return nil }
        if !result.projectDir.isEmpty { return URL(fileURLWithPath: result.projectDir) }
        if !result.output.isEmpty { return URL(fileURLWithPath: result.output) }
        return nil
    }
}
