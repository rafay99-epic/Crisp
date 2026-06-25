import Foundation

/// The filler-detection models Crisp can run as a fast, on-device alternative to
/// whisper — an **opt-in, experimental** feature.
///
/// Data-driven like `ModelCatalog`: **adding a model is one entry here; disabling
/// it is removing the entry** — no `if model == …` branching anywhere. Reuses
/// `ModelSpec`, so the whole download / verify / resume stack (`ModelProvisioner`,
/// `ModelStore`) and the install UI (`ModelInstallControl`) work unchanged.
///
/// Models live at huggingface.co/rafay99-epic/crisp-models, pinned by version tag
/// and verified by content hash. Named after birds (Wren, then Kestrel…).
public enum FillerModelCatalog {
    /// Wren — the fast, lightweight model. The context-aware temporal model (v2,
    /// `sequence`) at the current Stable version. Fast on-device, English only.
    ///
    /// Pinned to the version promoted to Stable on Hugging Face (`main`). When a new
    /// model is promoted (`promote_model.py`), bump this url + sha256 + approxBytes so
    /// FRESH installs fetch the current model directly instead of an old one + an
    /// immediate update. (Existing installs update via the manifest regardless.)
    public static let wren = ModelSpec(
        id: "wren",
        fileName: "Wren.mlmodel",
        url: URL(string: "https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.10/Wren.mlmodel")!,
        sha256: "f2cacdff9165a945c47da0634e6cf847e082754094f4c2838fc90956b38a1035",
        approxBytes: 514_188,
        displayName: "Wren",
        summary: "Fast on-device filler detection. English, experimental.",
        recommended: true)

    /// Every filler model, in display order (recommended first). Add an entry to
    /// offer a new model; remove one to retire it.
    public static let all: [ModelSpec] = [wren]

    /// The model used when the feature is on but nothing is chosen.
    public static let defaultID = wren.id

    /// The spec for an id, falling back to the default for nil/unknown ids (so a
    /// settings file naming a model we no longer ship still resolves to a real one).
    public static func spec(id: String?) -> ModelSpec {
        guard let id else { return wren }
        return all.first { $0.id == id } ?? wren
    }

    /// The model architectures this build's `crisp-filler` helper can actually run.
    /// `chunk` = the original per-window classifier (v0.0.8); `sequence` = the
    /// context-aware temporal model (Wren v2). Keep in sync with the helper's
    /// `Spec.modelType` branches.
    public static let supportedModelTypes: Set<String> = ["chunk", "sequence"]

    /// Whether this app can run a model of the given `model_type` (from its
    /// config.json manifest). A missing type means the original chunk model. Used to
    /// **skip** a remote model this build can't execute — so an older app never
    /// downloads a newer architecture it would mis-run.
    public static func canRun(modelType: String?) -> Bool {
        supportedModelTypes.contains(modelType ?? "chunk")
    }
}
