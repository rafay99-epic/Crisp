using System.Collections.Generic;
using System.Text.Json;

namespace Crisp.Models;

/// The engine's --probe-hardware answer: the machine's GPU names and the verified
/// hardware encoder each codec would use (null = that codec encodes in software).
/// {"event":"hardware","gpus":["Radeon (TM) 520"],"encoders":{"h264":"h264_amf","hevc":null}}
public sealed class HardwareInfo
{
    public IReadOnlyList<string> Gpus { get; init; } = [];
    public string? H264Encoder { get; init; }
    public string? HevcEncoder { get; init; }

    public bool Accelerates(string codec) =>
        codec == "hevc" ? HevcEncoder is not null : codec == "h264" && H264Encoder is not null;

    /// The user-facing name of the hardware family an encoder belongs to.
    public static string VendorLabel(string encoder) => encoder switch
    {
        _ when encoder.EndsWith("_nvenc") => "NVIDIA NVENC",
        _ when encoder.EndsWith("_qsv") => "Intel Quick Sync",
        _ when encoder.EndsWith("_amf") => "AMD AMF",
        _ when encoder.EndsWith("_videotoolbox") => "Apple VideoToolbox",
        _ => encoder,
    };

    /// Parse the raw NDJSON line; null on any shape mismatch (a probe answer we
    /// can't read is the same as no answer).
    public static HardwareInfo? Parse(string rawJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var root = doc.RootElement;
            var gpus = new List<string>();
            if (root.TryGetProperty("gpus", out var g) && g.ValueKind == JsonValueKind.Array)
                foreach (var item in g.EnumerateArray())
                    if (item.ValueKind == JsonValueKind.String) gpus.Add(item.GetString()!);

            string? h264 = null, hevc = null;
            if (root.TryGetProperty("encoders", out var e) && e.ValueKind == JsonValueKind.Object)
            {
                if (e.TryGetProperty("h264", out var v) && v.ValueKind == JsonValueKind.String) h264 = v.GetString();
                if (e.TryGetProperty("hevc", out var v2) && v2.ValueKind == JsonValueKind.String) hevc = v2.GetString();
            }
            return new HardwareInfo { Gpus = gpus, H264Encoder = h264, HevcEncoder = hevc };
        }
        catch (JsonException) { return null; }
    }
}
