import Foundation
import CrispCore

// The background watch-folder agent. Launched by launchd as a login-item
// LaunchAgent (registered via SMAppService from the app's Settings), it lives
// inside the app bundle at Contents/MacOS/CrispWatcher and auto-cleans recordings
// dropped into the user's chosen folder — even when the main window is closed.

// Resolve the bundled engine relative to the app bundle. This executable sits at
// Contents/MacOS/CrispWatcher, so the engine is ../Resources/engine. We set an
// explicit override rather than trust Bundle.main, which isn't a dependable
// resource root when launched by launchd.
let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let resources = exe                     // …/Contents/MacOS/CrispWatcher
    .deletingLastPathComponent()        // …/Contents/MacOS
    .deletingLastPathComponent()        // …/Contents
    .appendingPathComponent("Resources", isDirectory: true)
CleanEngine.engineRootOverride = resources
AppInfo.logger("watcher").info("Engine root: \(resources.path, privacy: .public)")

// Held in a binding (not a temporary) so it stays alive for the process — `run()`
// blocks on the run loop and never returns.
let controller = WatchController()
controller.run()
