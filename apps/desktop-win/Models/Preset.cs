using System;
using System.Text.Json.Serialization;

namespace Crisp.Models;

/// A named, reusable clean recipe — a full set of cut + encode + output + backup
/// choices the user applies to individual queue rows instead of the one global
/// setting. Port of macOS CrispCore/Models/Preset.swift; the JSON field names match
/// exactly so a preset created on either platform round-trips through the shared
/// settings.json (`EngineConfig.Presets`).
public sealed class Preset
{
    [JsonPropertyName("id")] public string Id { get; set; } = Guid.NewGuid().ToString();
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("strength")] public string Strength { get; set; } = "aggressive"; // Strength.rawValue

    // Cutting (used when strength is Custom)
    [JsonPropertyName("pauseThreshold")] public double PauseThreshold { get; set; } = 0.6;
    [JsonPropertyName("silenceFloorDB")] public double SilenceFloorDB { get; set; } = -30;
    [JsonPropertyName("breathingRoom")] public double BreathingRoom { get; set; } = 0.15;
    [JsonPropertyName("minKeep")] public double MinKeep { get; set; } = 0.05;

    // Encoding
    [JsonPropertyName("videoCodec")] public string VideoCodec { get; set; } = "hevc";
    [JsonPropertyName("hardwareEncoding")] public bool HardwareEncoding { get; set; } = true;
    [JsonPropertyName("videoQuality")] public string VideoQuality { get; set; } = "high";
    [JsonPropertyName("audioCodec")] public string AudioCodec { get; set; } = "aac";
    [JsonPropertyName("audioBitrateKbps")] public int AudioBitrateKbps { get; set; } = 192;
    [JsonPropertyName("outputContainer")] public string OutputContainer { get; set; } = "auto";
    [JsonPropertyName("colorDepth")] public string ColorDepth { get; set; } = "auto";

    // Output + backup. outputDirectory is carried for round-trip parity with the Mac
    // (the Windows clean path writes "<name>_cleaned" beside the source today).
    [JsonPropertyName("outputDirectory")] public string OutputDirectory { get; set; } = "";
    [JsonPropertyName("backupOriginal")] public bool BackupOriginal { get; set; } = true;
}
