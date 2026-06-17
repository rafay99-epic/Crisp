import SwiftUI

@main
struct CrispApp: App {
    @State private var model = CleanModel()
    @State private var updater = Updater()
    @State private var modelStore = ModelStore()
    @State private var settings = EngineSettings()

    var body: some Scene {
        Window(Channel.current.displayName, id: "main") {
            ContentView(model: model, updater: updater, modelStore: modelStore, settings: settings)
                .task { updater.checkOnLaunch() }
                .task { await modelStore.refresh() }
        }
        // Content has a fixed width and natural height, so the window sizes itself
        // to fit — it grows when a result appears and shrinks back, with no scroll
        // and no dead space.
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
            }
        }

        Settings {
            SettingsView(settings: settings, updater: updater)
        }
    }
}
