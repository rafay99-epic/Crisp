import SwiftUI

/// Owns whether the welcome / onboarding sheet is showing, and remembers (per
/// channel, via that channel's `UserDefaults`) whether the user has already seen
/// it. Shown automatically on first launch and re-openable from Help ▸ Welcome to
/// Crisp.
@MainActor
@Observable
final class OnboardingController {
    var isPresented: Bool

    private let seenKey = "hasCompletedOnboarding"

    private var hasSeen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    init() {
        // Decide synchronously at startup so the main UI never flashes before the
        // welcome flow takes over the window on first launch.
        isPresented = !UserDefaults.standard.bool(forKey: seenKey)
    }

    /// Re-open it on demand (Help menu).
    func present() { isPresented = true }

    /// Mark complete and dismiss.
    func finish() {
        hasSeen = true
        isPresented = false
    }
}
