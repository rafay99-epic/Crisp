import Foundation

/// A speech model the engine can use for filler-word detection, pinned by content
/// hash. The catalog is the single source of truth for every model's identity;
/// `ModelProvisioner` downloads and verifies one, and the engine loads it via
/// `--model <path>` (inferring its whisper.cpp DTW alias from the file name).
public struct ModelSpec: Identifiable, Sendable, Equatable, Hashable {
    /// Stable selection id — also the value stored in `EngineConfig.selectedModelID`.
    public let id: String
    /// The ggml file the engine loads. Its stem also drives the engine's DTW alias.
    public let fileName: String
    public let url: URL
    public let sha256: String
    /// Approximate download size — used for a sensible progress bar before the
    /// server reports a length, and to label the model in the UI.
    public let approxBytes: Int64
    public let displayName: String
    /// One-line description for the picker (quality vs. speed tradeoff).
    public let summary: String
    /// The model new users should pick — surfaced first / preselected.
    public let recommended: Bool

    public init(id: String, fileName: String, url: URL, sha256: String,
                approxBytes: Int64, displayName: String, summary: String, recommended: Bool) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256
        self.approxBytes = approxBytes
        self.displayName = displayName
        self.summary = summary
        self.recommended = recommended
    }

    /// Human-readable size, e.g. "148 MB" — for the install UI.
    public var approxSizeText: String {
        ByteCountFormatter.string(fromByteCount: approxBytes, countStyle: .file)
    }
}

/// The fixed set of speech models Crisp offers. Hashes come from the whisper.cpp
/// model repo's git-LFS pointers (verified by content on download).
public enum ModelCatalog {
    /// Fast, lightweight default. Catches the common fillers; ships as the model
    /// new users get unless they choose otherwise.
    public static let base = ModelSpec(
        id: "base.en",
        fileName: "ggml-base.en.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
        sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
        approxBytes: 147_964_211,
        displayName: "Base (English)",
        summary: "Fast and light. Great for clear speech and quick cleans.",
        recommended: true)

    /// High-accuracy option (Large v3 Turbo, q5_0). Catches more fillers and places
    /// them more precisely; larger to download and slower to run.
    public static let turbo = ModelSpec(
        id: "large-v3-turbo",
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        approxBytes: 574_041_195,
        displayName: "Large v3 Turbo",
        summary: "Highest accuracy — catches more fillers. Larger and slower.",
        recommended: false)

    /// Every model, in display order (recommended first).
    public static let all: [ModelSpec] = [base, turbo]

    /// The model used when none is chosen.
    public static let defaultID = base.id

    /// The spec for an id, falling back to the default model for nil/unknown ids
    /// (so a settings file naming a model we no longer ship still resolves).
    public static func spec(id: String?) -> ModelSpec {
        guard let id else { return base }
        return all.first { $0.id == id } ?? base
    }
}
