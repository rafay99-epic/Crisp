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

    /// Launch `editor` (optionally handing it `fileURL`). Note: Resolve won't
    /// auto-import a passed FCPXML, so callers generally pair this with `reveal`
    /// and a "File ▸ Import ▸ Timeline" hint.
    public static func launch(_ editor: VideoEditor, opening fileURL: URL? = nil) {
        let cfg = NSWorkspace.OpenConfiguration()
        if let fileURL {
            NSWorkspace.shared.open([fileURL], withApplicationAt: editor.appURL,
                                    configuration: cfg, completionHandler: nil)
        } else {
            NSWorkspace.shared.openApplication(at: editor.appURL, configuration: cfg,
                                               completionHandler: nil)
        }
    }

    /// Reveal a file/folder in Finder (the project the user then imports).
    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}
