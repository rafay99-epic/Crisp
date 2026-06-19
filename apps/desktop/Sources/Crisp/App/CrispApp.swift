import SwiftUI
import CrispCore

@main
struct CrispApp: App {
    @State private var model = CleanModel()
    @State private var updater = Updater()
    @State private var modelStore = ModelStore()
    @State private var settings = EngineSettings()
    @State private var watchAgent = WatchAgentController()
    @State private var onboarding = OnboardingController()
    @State private var player = PreviewPlayer()

    var body: some Scene {
        Window(Channel.current.displayName, id: "main") {
            ContentView(model: model, updater: updater, modelStore: modelStore,
                        settings: settings, watchAgent: watchAgent, onboarding: onboarding,
                        player: player)
                .task { updater.checkOnLaunch() }
                .task { await modelStore.refresh() }
                .task { QuickActionInstaller.install() }
                .task { reconcileWatchAgent() }
                .task { Notifier.requestAuthorization() }
        }
        // The queue is a list, so the window is resizable (macOS restores its size
        // and position between launches): the queue takes the slack while the
        // toolbar and the bottom action bar stay pinned. A default that's roomy on
        // first run, with a sensible floor enforced by the content's min frame.
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
            }
            // Replace the (unused) default Help book with a way back into the tour.
            CommandGroup(replacing: .help) {
                Button("Welcome to \(Channel.current.displayName)") { onboarding.present() }
            }
        }

        Settings {
            SettingsView(settings: settings, updater: updater, watchAgent: watchAgent,
                         modelStore: modelStore, model: model)
        }
    }

    /// Keep the registered background agent in sync with the saved preference, in
    /// both directions: if watching is on, make sure the LaunchAgent is registered
    /// (it can be dropped by the system, or the config can arrive already enabled);
    /// if it's off, make sure no stale agent lingers.
    private func reconcileWatchAgent() {
        watchAgent.refresh()
        if settings.watchEnabled {
            if watchAgent.status != .enabled { watchAgent.setEnabled(true) }
        } else if watchAgent.status != .notRegistered {
            watchAgent.setEnabled(false)
        }
    }
}
