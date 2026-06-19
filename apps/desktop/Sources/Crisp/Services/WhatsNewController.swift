import SwiftUI
import CrispCore

/// One curated highlight — the fallback shown when the release notes can't be
/// fetched (offline, or a dev build with no release).
struct WhatsNewItem: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
}

/// A parsed section of release notes: an optional area heading + its bullet titles,
/// cleaned of the `#NN … — @author` decoration for a user-facing read.
struct WhatsNewSection: Identifiable {
    let id = UUID()
    let title: String?
    let bullets: [String]
}

/// Shows a one-time "What's New" sheet after the app updates — populated from the
/// running version's GitHub release notes (the same PR-derived list the release page
/// shows), so there's nothing to hand-maintain in the app. Remembers the last
/// release announced per channel (each channel has its own bundle id, so
/// `UserDefaults.standard` is already per-channel). Stays silent during onboarding
/// and for brand-new users (the tour covered everything); appears on a real update.
@MainActor
@Observable
final class WhatsNewController {
    var isPresented = false

    /// Sections parsed from the fetched release notes; empty → show the fallback.
    private(set) var sections: [WhatsNewSection] = []

    /// Identity of the running release — changes on every update. Nightly reuses one
    /// rolling tag, so key on the monotonic build number there.
    private var releaseID: String {
        Updater.currentBuildNumber > 0 ? "build \(Updater.currentBuildNumber)" : Updater.currentVersion
    }

    private let seenKey = "lastWhatsNewRelease"

    /// Curated fallback for when release notes aren't available (offline / dev build).
    static let fallback: [WhatsNewItem] = [
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
                     detail: "Drop a video on the menu bar to clean it with your default recipe without opening the window.")
    ]

    func presentIfNeeded(onboardingActive: Bool, onboardingAppearedOnLaunch: Bool) {
        guard !onboardingActive else { return }
        let lastSeen = UserDefaults.standard.string(forKey: seenKey)
        guard lastSeen != releaseID else { return }
        markSeen()
        // Brand-new user (the welcome tour ran this launch) just saw everything —
        // record silently. An existing user who updated sees the sheet.
        guard !onboardingAppearedOnLaunch else { return }
        Task {
            if let raw = await Updater.currentReleaseNotes() {
                sections = Self.parse(raw)
            }
            isPresented = true
        }
    }

    func markSeen() {
        UserDefaults.standard.set(releaseID, forKey: seenKey)
    }

    /// Turn the release-notes markdown (grouped `### Area (N)` + `- #NN title — @user`)
    /// into clean, user-facing sections: area headings without the count, bullet
    /// titles without the PR number or author. Pure (nonisolated) — unit-tested.
    nonisolated static func parse(_ raw: String) -> [WhatsNewSection] {
        var sections: [WhatsNewSection] = []
        var title: String?
        var bullets: [String] = []

        func flush() {
            if !bullets.isEmpty { sections.append(WhatsNewSection(title: title, bullets: bullets)) }
            bullets = []
        }

        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                flush()
                title = line.dropFirst(4)
                    .replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
            } else if line.hasPrefix("- ") {
                var b = String(line.dropFirst(2))
                b = b.replacingOccurrences(of: #"^#\d+\s+"#, with: "", options: .regularExpression)
                b = b.replacingOccurrences(of: #"\s+[—-]\s+@\S+.*$"#, with: "", options: .regularExpression)
                let trimmed = b.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { bullets.append(trimmed) }
            }
            // Ignore the top-level "## What's changed", blank lines, and code fences.
        }
        flush()
        return sections
    }
}
