using System.Collections.Generic;
using Avalonia.Data.Converters;

namespace Crisp.ViewModels;

public static class Converters
{
    public static readonly IValueConverter DropText =
        new FuncValueConverter<bool, string>(targeted => targeted ? "Drop to add" : "Drop videos here");

    /// Display casing for the raw engine option tokens shown in Settings dropdowns.
    /// The underlying values ("hevc", "auto", …) are the engine's CLI vocabulary and
    /// are persisted to settings.json, so only the *presentation* is cased here.
    private static readonly Dictionary<string, string> OptionNames = new()
    {
        // codecs
        ["h264"] = "H.264",
        ["hevc"] = "HEVC",
        ["aac"] = "AAC",
        ["opus"] = "Opus",
        // containers
        ["mp4"] = "MP4",
        ["mkv"] = "MKV",
        ["mov"] = "MOV",
        ["m4v"] = "M4V",
        ["ts"] = "TS",
        ["webm"] = "WebM",
        // colour depth
        ["8"] = "8-bit",
        ["10"] = "10-bit",
        // captions / split audio
        ["srt"] = "SRT",
        ["vtt"] = "VTT",
        ["both"] = "SRT + VTT",
        ["wav"] = "WAV",
        ["match"] = "Match video",
    };

    public static readonly IValueConverter OptionDisplay =
        new FuncValueConverter<string?, string>(raw =>
        {
            if (string.IsNullOrEmpty(raw)) return "";
            if (OptionNames.TryGetValue(raw, out var name)) return name;
            // Fallback: capitalize the first letter (auto → Auto, gentle → Gentle…).
            return char.ToUpperInvariant(raw[0]) + raw[1..];
        });
}
