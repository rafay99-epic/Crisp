using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Crisp.Models;

/// On-disk shape of ~/.crisp/config/settings.json — the SAME schema the macOS app
/// uses (CrispCore/Engine/EngineConfig.swift), camelCase keys, version 3. Only the
/// engine-affecting fields the Windows Settings window edits are modeled; every other
/// key (presets, watch folder, concurrency, …) rides through [JsonExtensionData] so
/// a file shared with / written by the Mac keeps all its values. Defaults mirror
/// crisp/config.py, so a missing key reads as its engine default.
public sealed class EngineConfig
{
    public int Version { get; set; } = 3;

    // Cutting (the "Custom" strength edits these; noise/minKeep apply to every clean)
    public double PauseThreshold { get; set; } = 0.6;
    public double SilenceFloorDB { get; set; } = -30;
    public double BreathingRoom { get; set; } = 0.15;
    public double MinKeep { get; set; } = 0.05;

    // Cut smoothing (every clean)
    public double FadeMs { get; set; } = 10;
    public double CrossfadeMs { get; set; }
    public double SnapMs { get; set; } = 12;

    // Encoding (every clean)
    public string VideoCodec { get; set; } = "hevc";
    public bool HardwareEncoding { get; set; } = true;
    public string VideoQuality { get; set; } = "high";
    public string AudioCodec { get; set; } = "aac";
    public int AudioBitrateKbps { get; set; } = 192;
    public string OutputContainer { get; set; } = "auto";
    public string ColorDepth { get; set; } = "auto";
    public string FrameRateMode { get; set; } = "auto";
    public double FrameRateValue { get; set; }

    public string CaptionsFormat { get; set; } = "none";
    public string RetakeSensitivity { get; set; } = "aggressive";
    public bool BackupOriginal { get; set; } = true;

    /// Every other key in the file (presets, watch, concurrency, model ids, …) —
    /// preserved verbatim on round-trip so the Windows app never drops them.
    [JsonExtensionData] public Dictionary<string, JsonElement> Extra { get; set; } = new();

    private static readonly JsonSerializerOptions Opts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public static string FilePath => Path.Combine(
        Environment.GetEnvironmentVariable("CRISP_CONFIG_DIR")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".crisp", "config"),
        "settings.json");

    /// True when a present settings.json couldn't be read (transient I/O). The caller
    /// then runs on defaults but must NOT save over the existing file.
    [JsonIgnore] public bool LoadFailed { get; private set; }

    /// Load, filling any missing key with its default. Missing file → defaults. A
    /// corrupt file is quarantined to settings.json.corrupt (never silently overwritten,
    /// so unmodeled keys aren't lost). A transient read error returns defaults flagged
    /// LoadFailed so the caller leaves the file untouched.
    public static EngineConfig Load()
    {
        if (!File.Exists(FilePath)) return new EngineConfig();
        try
        {
            return JsonSerializer.Deserialize<EngineConfig>(File.ReadAllText(FilePath), Opts) ?? new EngineConfig();
        }
        catch (JsonException)
        {
            try { File.Move(FilePath, FilePath + ".corrupt", overwrite: true); } catch { /* best effort */ }
            return new EngineConfig();
        }
        catch (IOException)
        {
            return new EngineConfig { LoadFailed = true }; // don't overwrite a file we couldn't read
        }
    }

    /// Atomic write (temp + move), preserving unmodeled keys.
    public void Save()
    {
        var dir = Path.GetDirectoryName(FilePath)!;
        Directory.CreateDirectory(dir);
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(this, Opts));
        File.Move(tmp, FilePath, overwrite: true);
    }
}
