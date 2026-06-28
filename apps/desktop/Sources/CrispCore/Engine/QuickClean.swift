import Foundation

/// One-shot, headless clean of a single file using the user's saved settings — the
/// path the Shortcuts App Intent and the background watch-folder agent share. (The
/// in-app flow uses `CleanModel` for its richer window UI.) Loads `EngineConfig`,
/// brings the speech model online if fillers are requested (auto-download), then
/// runs the engine via `CleanRunner` — so every surface produces identical output.
public struct QuickClean {
    public init() {}

    /// Clean `input` and return the result. `strength`/`removeFillers` come from the
    /// caller (the Intent's parameters, or the watch-folder settings); the encoder +
    /// backup + caption choices always come from the saved config. When a transcript
    /// is needed (filler removal *or* caption export) and the model isn't present
    /// yet, it's downloaded + verified first via `provisioner`.
    @discardableResult
    public func clean(_ input: URL,
                      strength: Strength,
                      removeFillers: Bool,
                      removeRetakes: Bool = true,
                      allowDownload: Bool = true,
                      provisioner: ModelProvisioner = .forSelectedModel(),
                      onEvent: (@Sendable (CleanRunner.Progress) -> Void)? = nil) async throws -> CleanResult {
        var config = EngineConfigStore.load()
        // Anything that reads the transcript needs the speech model online first: filler
        // removal, caption export, *and* retake detection (which matches the words).
        let needsTranscript = removeFillers || removeRetakes || config.captionsFormat != "none"
        // `allowDownload == false` (the Finder Quick Action) must never kick off a
        // background fetch — use only an already-verified model, falling back to nil.
        let modelPath: String?
        if needsTranscript {
            modelPath = allowDownload ? try await provisioner.ensureModel()
                                      : await provisioner.existingVerifiedPath()
        } else {
            modelPath = nil
        }
        // No usable model (and no download): drop every transcript-dependent step rather
        // than fail — pauses are still cut. Captions especially must be cleared, since
        // they'd otherwise reach the engine without a model and error.
        var removeFillers = removeFillers, removeRetakes = removeRetakes
        if needsTranscript && modelPath == nil {
            removeFillers = false
            removeRetakes = false
            config.captionsFormat = "none"
        }
        // Editor handoff is an interactive main-window action (it pops an editor
        // picker). QuickClean's callers — the watch folder, the App Intent, the
        // menu-bar drop — are headless/one-shot and can't present that, and a watch
        // run that produced only an .fcpxml would never write the `_cleaned` marker the
        // watcher uses to avoid reprocessing. So these paths always render a video.
        config.exportToEditor = false
        let params = strength.parameters(using: config)
        let backupDir = params.backupOriginal ? CleanRunner.backupDirectory() : nil
        let options = CleanRunner.Options(modelPath: modelPath,
                                          removeFillers: removeFillers,
                                          removeRetakes: removeRetakes,
                                          backupDirectory: backupDir)
        return try await CleanRunner().run(input: input, parameters: params,
                                           options: options, onEvent: onEvent ?? { _ in })
    }
}
