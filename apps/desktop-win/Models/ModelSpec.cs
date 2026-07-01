using System.Collections.Generic;
using System.Linq;

namespace Crisp.Models;

/// A whisper speech model the engine loads via --model for filler-word detection,
/// pinned by content hash. Port of CrispCore/Model/ModelCatalog.swift.
public sealed record ModelSpec(
    string Id,
    string FileName,
    string Url,
    string Sha256,
    long ApproxBytes,
    string DisplayName,
    string Summary,
    bool Recommended = false)
{
    public string ApproxSizeText => ApproxBytes >= 1_000_000_000
        ? $"{ApproxBytes / 1_000_000_000.0:0.#} GB"
        : ApproxBytes >= 1_000_000
            ? $"{ApproxBytes / 1_000_000} MB"
            : $"{ApproxBytes / 1_000} KB";
    public string DisplayWithSize => $"{DisplayName} · {ApproxSizeText}";

    /// The model's optional config sidecar (framing/threshold metadata published
    /// beside it): "…/Wren.mlmodel" → "…/Wren.config.json". Same derivation as
    /// macOS FillerModelConfig.
    public string SidecarFileName => System.IO.Path.GetFileNameWithoutExtension(FileName) + ".config.json";
    public string SidecarUrl => Url[..(Url.Length - FileName.Length)] + SidecarFileName;
}

public static class ModelCatalog
{
    /// Fast, lightweight default — the model new users get. Hash + URL match the
    /// macOS catalog so both platforms verify against the same content.
    public static readonly ModelSpec Base = new(
        Id: "base.en",
        FileName: "ggml-base.en.bin",
        Url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
        Sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
        ApproxBytes: 147_964_211,
        DisplayName: "Base (English)",
        Summary: "Fast and light. Great for clear speech and quick cleans.",
        Recommended: true);

    /// High-accuracy option — catches more fillers, places them more precisely;
    /// larger to download and slower to run.
    public static readonly ModelSpec Turbo = new(
        Id: "large-v3-turbo",
        FileName: "ggml-large-v3-turbo-q5_0.bin",
        Url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
        Sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        ApproxBytes: 574_041_195,
        DisplayName: "Large v3 Turbo",
        Summary: "Highest accuracy — catches more fillers. Larger and slower.");

    public static readonly IReadOnlyList<ModelSpec> All = new[] { Base, Turbo };
    public const string DefaultId = "base.en";

    /// The spec for an id, falling back to the default for null/unknown ids (so a
    /// settings file naming a model we no longer ship still resolves).
    public static ModelSpec Spec(string? id) => All.FirstOrDefault(m => m.Id == id) ?? Base;
}

/// Crisp's own filler classifier — the "custom model" alternative to the whisper
/// catalog. Port of macOS FillerModelCatalog.swift: same Hugging Face repo
/// (rafay99-epic/crisp-models), same pinned version tag + content hash, so both
/// platforms verify against identical bytes. It detects fillers only (no transcript),
/// so repeated-take removal and captions still use whisper. The engine runs it via
/// the crisp-filler helper (CRISP_FILLER) — see FillerHelper for availability.
public static class FillerModelCatalog
{
    public static readonly ModelSpec Wren = new(
        Id: "wren",
        FileName: "Wren.mlmodel",
        Url: "https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.10/Wren.mlmodel",
        Sha256: "f2cacdff9165a945c47da0634e6cf847e082754094f4c2838fc90956b38a1035",
        ApproxBytes: 514_188,
        DisplayName: "Wren",
        Summary: "Crisp's own model — much faster than Whisper at catching fillers. Repeated takes and captions still use Whisper.");
}
