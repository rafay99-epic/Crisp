import SwiftUI
import CrispCore

@main
struct CrispApp: App {
    @State private var model = CleanModel()
    @State private var updater = Updater()
    @State private var modelStore = ModelStore()
    // The opt-in on-device filler model (Wren), downloaded separately from whisper.
    @State private var fillerModelStore = ModelStore(spec: FillerModelCatalog.wren)
    @State private var fillerUpdater = FillerModelUpdater()
    @State private var settings = EngineSettings()
    @State private var watchAgent = WatchAgentController()
    @State private var onboarding = OnboardingController()
    @State private var player = PreviewPlayer()
    @State private var quickDrop = QuickDropModel()
    @State private var whatsNew = WhatsNewController()

    var body: some Scene {
        Window(Channel.current.displayName, id: "main") {
            ContentView(model: model, updater: updater, modelStore: modelStore,
                        fillerModelStore: fillerModelStore, fillerUpdater: fillerUpdater,
                        settings: settings, watchAgent: watchAgent, onboarding: onboarding,
                        player: player, whatsNew: whatsNew)
                .task { logLaunch() }
                .task { updater.checkOnLaunch() }
                .task { await modelStore.refresh() }
                .task {
                    if settings.fillerModelEnabled {
                        // Apply the persisted selection (the store inits to the default),
                        // then check disk so it's ready if already installed.
                        fillerModelStore.use(FillerModelCatalog.spec(id: settings.selectedFillerModelID))
                        await fillerModelStore.refresh()
                    }
                }
                // When the filler model is ready: grab its config.json sibling (so the
                // helper reads per-model values), then check Hugging Face for a newer
                // model version (the in-app model updater).
                .task(id: fillerModelStore.readyModelPath) {
                    guard let path = fillerModelStore.readyModelPath else { return }
                    await FillerModelConfig.fetchIfNeeded(modelURL: fillerModelStore.spec.url, modelPath: path)
                    await fillerUpdater.check(
                        baseSpec: FillerModelCatalog.spec(id: settings.selectedFillerModelID),
                        installedVersion: FillerModelConfig.installedVersion(modelPath: path))
                }
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
                         modelStore: modelStore, fillerModelStore: fillerModelStore,
                         fillerUpdater: fillerUpdater, model: model)
        }

        // A library of past cleans (every surface records to it). Opened from the
        // main window's toolbar; a single reusable window.
        Window("History", id: "history") {
            HistoryView(model: model, quickDrop: quickDrop)
        }
        .defaultSize(width: 540, height: 480)
        .keyboardShortcut("y", modifiers: .command)

        // Opt-in menu-bar item: a quick-drop zone to clean a video with the default
        // recipe without opening the main window. Hidden unless enabled in Settings.
        MenuBarExtra("Quick Clean", systemImage: "scissors", isInserted: menuBarBinding) {
            MenuBarPanel(quickDrop: quickDrop, settings: settings)
        }
        .menuBarExtraStyle(.window)
    }

    /// Drives `MenuBarExtra`'s visibility from the saved preference.
    private var menuBarBinding: Binding<Bool> {
        Binding(get: { settings.menuBarEnabled }, set: { settings.menuBarEnabled = $0 })
    }

    /// Open the day's log with a launch marker and trim old files, so the log has a
    /// clear "app started" boundary and the folder can't grow without bound.
    private func logLaunch() {
        FileLog.shared.pruneOldLogs()
        HistoryStore.shared.prune()
        let version = Updater.currentBuildNumber > 0
            ? "\(Updater.currentVersion) (build \(Updater.currentBuildNumber))"
            : Updater.currentVersion
        AppInfo.logger("app").info(
            "\(Channel.current.displayName) \(version) launched — logs at \(Channel.current.logsDirectory.path)")
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
