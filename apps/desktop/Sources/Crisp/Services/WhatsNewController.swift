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

    /// Clean, user-facing highlight titles parsed from the release notes; empty → the
    /// view shows the curated fallback.
    private(set) var highlights: [String] = []

    /// Areas worth showing a user in a "What's New" splash: the app itself and the
    /// engine. Website / CI / Docs changes belong on the release page, not here.
    private static let userFacingAreas: Set<String> = ["desktop", "backend"]

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
                let parsed = Self.parse(raw)
                guard !parsed.isEmpty else { return }   // notes fetched, nothing user-facing → don't pop
                highlights = parsed
                isPresented = true
            } else {
                // Offline / dev build (no release to fetch) → curated fallback.
                isPresented = true
            }
        }
    }

    func markSeen() {
        UserDefaults.standard.set(releaseID, forKey: seenKey)
    }

    /// Extract the user-facing highlights from the release notes. Prefers the curated
    /// `## Highlights` section (written by GitHub Models — already friendly prose); if
    /// a release has none (the model step was skipped/failed), falls back to clean,
    /// deduped titles from the user-facing changelog areas. Pure (nonisolated) —
    /// unit-tested.
    nonisolated static func parse(_ raw: String) -> [String] {
        let lines = raw.components(separatedBy: "\n")

        // 1) Curated "## Highlights" section — already user-facing, use verbatim.
        var inHighlights = false
        var curated: [String] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inHighlights = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "highlights"
            } else if inHighlights, line.hasPrefix("- ") {
                let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { curated.append(title) }
            }
        }
        if !curated.isEmpty { return curated }

        // 2) Fallback: clean, deduped titles from the user-facing changelog areas.
        var highlights: [String] = []
        var seen: Set<String> = []
        var include = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                let area = line.dropFirst(4)
                    .replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                include = userFacingAreas.contains(area.lowercased())
            } else if include, line.hasPrefix("- ") {
                var b = String(line.dropFirst(2))
                b = b.replacingOccurrences(of: #"^#\d+\s+"#, with: "", options: .regularExpression)
                b = b.replacingOccurrences(of: #"\s+[—-]\s+@\S+.*$"#, with: "", options: .regularExpression)
                let title = b.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, seen.insert(title.lowercased()).inserted {
                    highlights.append(title)
                }
            }
        }
        return highlights
    }
}
