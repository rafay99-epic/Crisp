import Foundation
import CrispCore
import UserNotifications

// Headless CLI behind the Finder "Clean with Crisp" Quick Action. The installed
// Automator workflow passes the selected file paths as arguments; we clean each
// through the shared QuickClean path (same engine + settings as the app) and post
// a notification. Lives at Contents/MacOS/CrispClean inside the app bundle.

// Resolve the bundled engine relative to the app bundle (../Resources/engine),
// since Bundle.main isn't a dependable resource root for a bare executable.
let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let resources = exe
    .deletingLastPathComponent()        // …/Contents/MacOS
    .deletingLastPathComponent()        // …/Contents
    .appendingPathComponent("Resources", isDirectory: true)
CleanEngine.engineRootOverride = resources

let log = AppInfo.logger("quickaction")

let inputs = CommandLine.arguments.dropFirst()
    .map { URL(fileURLWithPath: $0) }
    .filter { CleanRunner.videoExtensions.contains($0.pathExtension.lowercased()) }

guard !inputs.isEmpty else { exit(0) }

let center = UNUserNotificationCenter.current()
center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

func notify(_ title: String, _ body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
}

Task {
    // Use fillers / retakes only if the model is already downloaded — a right-click
    // shouldn't silently kick off a 148 MB download (both read the transcript). Open
    // the app once to get the model.
    let provisioner = ModelProvisioner.forSelectedModel()
    let modelReady = await provisioner.existingVerifiedPath() != nil
    let removeFillers = modelReady
    let removeRetakes = modelReady
    let quick = QuickClean()

    notify(inputs.count == 1 ? "Cleaning \(inputs[0].lastPathComponent)…"
                             : "Cleaning \(inputs.count) videos…",
           "Crisp is removing pauses\(removeFillers ? " and filler words" : "").")

    var cleaned = 0
    for input in inputs {
        do {
            let result = try await quick.clean(input, strength: .aggressive,
                                               removeFillers: removeFillers,
                                               removeRetakes: removeRetakes,
                                               allowDownload: false, provisioner: provisioner)
            cleaned += 1
            log.info("Cleaned \(input.lastPathComponent, privacy: .public)")
            if inputs.count == 1 {
                notify("Cleaned \(input.lastPathComponent)",
                       "Saved \(URL(fileURLWithPath: result.output).lastPathComponent) beside the original.")
            }
        } catch {
            log.error("Failed to clean \(input.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            notify("Couldn’t clean \(input.lastPathComponent)", error.localizedDescription)
        }
    }
    if inputs.count > 1 {
        notify("Cleaned \(cleaned) of \(inputs.count) videos", "Tight cuts saved beside each original.")
    }

    // Give the notification center a moment to deliver before the process exits.
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    exit(0)
}

RunLoop.main.run()
