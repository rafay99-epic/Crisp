import Foundation

/// Downloads a filler model's `config.json` (framing + normalization + recommended
/// threshold/min-length) to sit **beside the model file**, so the engine can pass it
/// to the `crisp-filler` helper and nothing is hardcoded per-model.
///
/// Best-effort and non-critical: the helper falls back to its built-in defaults if
/// the config is missing, so any failure here is silently ignored. The config URL is
/// derived from the model URL (`…/Wren.mlmodel` → `…/Wren.config.json`), and the
/// destination from the model path (`…/models/Wren.mlmodel` → `…/models/Wren.config.json`).
public enum FillerModelConfig {
    public static func fetchIfNeeded(modelURL: URL, modelPath: String) async {
        let dest = URL(fileURLWithPath: modelPath)
            .deletingPathExtension().appendingPathExtension("config.json")
        if FileManager.default.fileExists(atPath: dest.path) { return }

        let configURL = modelURL.deletingPathExtension().appendingPathExtension("config.json")
        guard let (data, response) = try? await URLSession.shared.data(from: configURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        try? data.write(to: dest, options: .atomic)
    }
}
