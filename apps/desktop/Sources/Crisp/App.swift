import SwiftUI

@main
struct CrispApp: App {
    @State private var model = CleanModel()
    @State private var updater = Updater()
    @State private var modelStore = ModelStore()

    var body: some Scene {
        Window(Channel.current.displayName, id: "main") {
            ContentView(model: model, updater: updater, modelStore: modelStore)
                .frame(minWidth: 540, minHeight: 600)
                .task { updater.checkOnLaunch() }
                .task { await modelStore.refresh() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
            }
        }
    }
}
