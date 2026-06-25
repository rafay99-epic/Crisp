import SwiftUI
import AppKit

// SwiftPM executables launch with a "prohibited" activation policy, so the window
// wouldn't show/focus. Promote to a regular app and activate on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct FillerBenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var bench = Bench()

    var body: some Scene {
        Window("FillerBench", id: "main") {
            ContentView(bench: bench)
                .frame(minWidth: 760, minHeight: 600)
        }
    }
}
