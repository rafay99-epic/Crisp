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
    /// Path of the config sitting beside a model file.
    public static func sidecar(for modelPath: String) -> URL {
        URL(fileURLWithPath: modelPath).deletingPathExtension().appendingPathExtension("config.json")
    }

    public static func fetchIfNeeded(modelURL: URL, modelPath: String, force: Bool = false) async {
        let dest = sidecar(for: modelPath)
        if !force, FileManager.default.fileExists(atPath: dest.path) { return }

        let configURL = modelURL.deletingPathExtension().appendingPathExtension("config.json")
        guard let (data, response) = try? await URLSession.shared.data(from: configURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        try? data.write(to: dest, options: .atomic)
    }

    /// The version of the model currently installed (read from its config sidecar), or
    /// nil if not installed / no config yet.
    public static func installedVersion(modelPath: String) -> String? {
        guard let data = try? Data(contentsOf: sidecar(for: modelPath)),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return j["version"] as? String
    }
}
