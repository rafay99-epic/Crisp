namespace Crisp.Models;

/// A whisper speech model the engine loads via --model for filler-word detection,
/// pinned by content hash. Port of CrispCore/Model/ModelCatalog.swift (base model).
public sealed record ModelSpec(
    string Id,
    string FileName,
    string Url,
    string Sha256,
    long ApproxBytes,
    string DisplayName)
{
    public string ApproxSizeText => $"{ApproxBytes / 1_000_000} MB";
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
        DisplayName: "Base (English)");
}
