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
    /// Wren — the fast, lightweight model. A tiny CNN; ~0.94 precision at ~600×
    /// real-time. English only.
    public static let wren = ModelSpec(
        id: "wren",
        fileName: "Wren.mlmodel",
        url: URL(string: "https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.8/Wren.mlmodel")!,
        sha256: "548c8b09689eb4e2d8d2220a9be89f141c1a8f5591f81504c2f88267fa72a51d",
        approxBytes: 94_395,
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
}
