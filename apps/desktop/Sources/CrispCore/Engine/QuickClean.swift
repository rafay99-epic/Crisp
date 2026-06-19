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
    /// backup choices always come from the saved config. When fillers are on and the
    /// model isn't present yet, it's downloaded + verified first via `provisioner`.
    @discardableResult
    public func clean(_ input: URL,
                      strength: Strength,
                      removeFillers: Bool,
                      provisioner: ModelProvisioner = .forSelectedModel(),
                      onEvent: (@Sendable (CleanRunner.Progress) -> Void)? = nil) async throws -> CleanResult {
        let config = EngineConfigStore.load()
        let modelPath: String? = removeFillers ? try await provisioner.ensureModel() : nil
        let params = strength.parameters(using: config)
        let backupDir = params.backupOriginal ? CleanRunner.backupDirectory() : nil
        let options = CleanRunner.Options(modelPath: modelPath,
                                          removeFillers: removeFillers,
                                          backupDirectory: backupDir)
        return try await CleanRunner().run(input: input, parameters: params,
                                           options: options, onEvent: onEvent ?? { _ in })
    }
}
