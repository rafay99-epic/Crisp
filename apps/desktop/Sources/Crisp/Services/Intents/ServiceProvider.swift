import AppKit
import CrispCore

/// Backs the Finder right-click **"Clean with Crisp"** Service (declared in
/// Info.plist's `NSServices`). macOS hands us the selected files on the
/// pasteboard; we bring the window forward, load them, and start cleaning —
/// auto-downloading the speech model first if filler removal is on. Reuses the
/// normal `CleanModel` flow so the user sees the usual progress + result.
///
/// `NSApplication.servicesProvider` is an `assign` (non-retained) reference, so
/// `CrispApp` holds this instance for the app's lifetime via `@State`.
@MainActor
final class ServiceProvider: NSObject {
    private weak var model: CleanModel?
    private weak var modelStore: ModelStore?
    private weak var settings: EngineSettings?

    /// Wire this provider into the Services system. Called once at launch.
    func register(model: CleanModel, modelStore: ModelStore, settings: EngineSettings) {
        self.model = model
        self.modelStore = modelStore
        self.settings = settings
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// `NSMessage` in Info.plist is `cleanWithCrisp`, so the selector must be
    /// exactly `cleanWithCrisp:userData:error:`.
    @objc func cleanWithCrisp(_ pboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { CleanRunner.videoExtensions.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else {
            error.pointee = "Select one or more video files to clean." as NSString
            return
        }
        guard let model, let modelStore, let settings else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            guard !model.isRunning else { return }
            model.addFiles(urls)
            let params = model.strength.parameters(using: settings.config)
            // No ready modelPath ⇒ start() auto-downloads via the shared provisioner
            // when fillers are on; otherwise it uses the verified model immediately.
            await model.start(modelPath: modelStore.readyModelPath,
                              parameters: params,
                              provisioner: modelStore.provisioner)
            await modelStore.refresh()   // reflect a model fetched during this run
        }
    }
}
