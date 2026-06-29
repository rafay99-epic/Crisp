using System.Text.Json;
using System.Text.Json.Serialization;

namespace Crisp.Models;

/// One line of the engine's --ndjson stream. The engine emits one JSON object
/// per line: {"event": "log"|"progress"|"result"|"error"|"analysis", ...}.
/// This mirrors the contract Swift's CleanRunner decodes on macOS.
public sealed class EngineEvent
{
    [JsonPropertyName("event")] public string Event { get; init; } = "";
    [JsonPropertyName("message")] public string? Message { get; init; }
    [JsonPropertyName("fraction")] public double? Fraction { get; init; }
    [JsonPropertyName("label")] public string? Label { get; init; }

    /// The raw line, kept verbatim for result/analysis events whose payload
    /// is open-ended (we don't model every field for the proof).
    [JsonIgnore] public string Raw { get; init; } = "";

    private static readonly JsonSerializerOptions Opts = new() { PropertyNameCaseInsensitive = true };

    /// Returns null for non-JSON lines (the engine only emits JSON in --ndjson mode,
    /// but a stray print shouldn't crash the reader).
    public static EngineEvent? Parse(string line)
    {
        if (string.IsNullOrWhiteSpace(line) || line[0] != '{') return null;
        try
        {
            var ev = JsonSerializer.Deserialize<EngineEvent>(line, Opts);
            return ev is null ? null : new EngineEvent
            {
                Event = ev.Event, Message = ev.Message, Fraction = ev.Fraction, Label = ev.Label, Raw = line,
            };
        }
        catch (JsonException) { return null; }
    }
}
