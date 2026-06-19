import SwiftUI
import CrispCore

/// One highlight shown in the "What's New" sheet.
struct WhatsNewItem: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
}

/// Shows a one-time "What's New" sheet after the app updates to a release that added
/// user-facing highlights — so people discover new features instead of them shipping
/// silently. Remembers the last release announced (per channel, via that channel's
/// `UserDefaults`, since each channel has its own bundle id).
@MainActor
@Observable
final class WhatsNewController {
    var isPresented = false

    /// Bump `version` and refresh `items` whenever a release adds something worth
    /// announcing. The string is opaque — it just has to change when there's news.
    static let version = "2026.06-ux"
    static let items: [WhatsNewItem] = [
        WhatsNewItem(symbol: "number",
                     title: "See what got cut",
                     detail: "Every cleaned video now shows how many filler words and pauses were removed."),
        WhatsNewItem(symbol: "waveform",
                     title: "Preview cuts before you clean",
                     detail: "Click Preview on a queued video to see the exact cuts — and tune the strength live."),
        WhatsNewItem(symbol: "clock.arrow.circlepath",
                     title: "History",
                     detail: "Find every clean — from the queue, the menu bar, Shortcuts, or the watch folder — in History (⌘Y)."),
        WhatsNewItem(symbol: "menubar.rectangle",
                     title: "Menu-bar quick-drop",
                     detail: "Drop a video on the menu bar to clean it with your default recipe without opening the window. Turn it on in Settings.")
    ]

    private let seenKey = "lastWhatsNewVersion"

    /// Show the sheet once per release with new highlights. No-op while onboarding is
    /// up (it already introduces everything). A brand-new user who just finished the
    /// welcome tour this launch gets the version recorded silently — they've seen it
    /// all — but an existing user who *updated* (the tour didn't run this launch) sees
    /// the sheet, including on the first release that ever shipped this feature.
    func presentIfNeeded(onboardingActive: Bool, onboardingAppearedOnLaunch: Bool) {
        guard !onboardingActive, !Self.items.isEmpty else { return }
        let lastSeen = UserDefaults.standard.string(forKey: seenKey)
        guard lastSeen != Self.version else { return }
        markSeen()
        if !onboardingAppearedOnLaunch { isPresented = true }
    }

    func markSeen() {
        UserDefaults.standard.set(Self.version, forKey: seenKey)
    }
}
