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
                .frame(minWidth: 520, minHeight: 460)
                .task { updater.checkOnLaunch() }
                .task { await modelStore.refresh() }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 540)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
            }
        }

        Settings {
            SettingsView(settings: settings)
        }
    }
}
