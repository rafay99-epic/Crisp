using System.Collections.Generic;

namespace Crisp.Models;

/// How aggressively to cut. Port of macOS CrispCore/Models/Strength.swift — each
/// preset maps to the engine's --pause threshold and the --keep-pause breathing
/// room kept around every cut. (Custom's real values live in settings; until the
/// Settings screen is ported it falls back to Aggressive, same as Swift.)
public enum Strength
{
    Gentle,
    Balanced,
    Aggressive,
    VeryAggressive,
    Custom,
}

public sealed record StrengthPreset(Strength Value, string Name, string PickerLabel, string Detail, double Pause, double KeepPause);

public static class Strengths
{
    public static readonly IReadOnlyList<StrengthPreset> All = new[]
    {
        new StrengthPreset(Strength.Gentle, "Gentle", "Gentle",
            "Cuts only clearly long pauses. Most natural.", 0.80, 0.18),
        new StrengthPreset(Strength.Balanced, "Balanced", "Balanced",
            "A safe middle ground.", 0.60, 0.15),
        new StrengthPreset(Strength.Aggressive, "Aggressive", "Aggressive",
            "Cuts short “thinking” gaps too. Recommended.", 0.35, 0.10),
        new StrengthPreset(Strength.VeryAggressive, "Very aggressive", "Very",
            "Tightest possible. Can feel fast-paced.", 0.25, 0.08),
        new StrengthPreset(Strength.Custom, "Custom", "Custom",
            "Your own settings — adjust them in Settings.", 0.35, 0.10),
    };

    public static StrengthPreset Of(Strength s)
    {
        foreach (var p in All) if (p.Value == s) return p;
        return All[2]; // Aggressive
    }

    /// The engine flags this strength implies (pauses-only knobs).
    public static IEnumerable<string> ToArgs(Strength s)
    {
        var p = Of(s);
        yield return "--pause"; yield return p.Pause.ToString(System.Globalization.CultureInfo.InvariantCulture);
        yield return "--keep-pause"; yield return p.KeepPause.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }
}
