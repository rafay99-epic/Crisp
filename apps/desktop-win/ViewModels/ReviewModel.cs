using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.ViewModels;

/// Drives the review-&-edit-cuts window: analyzes a file (peaks + silences), lists the
/// pauses it proposes to remove, and lets the user toggle each one. The waveform updates
/// live as toggles change. On apply it writes the engine's --keep-file and the queue
/// renders exactly those segments.
public partial class ReviewModel : ObservableObject
{
    private readonly CrispEngine _engine;
    private readonly double _pause, _keep;
    public QueueItem Item { get; }
    public string FileName => Item.FileName;

    public ObservableCollection<CutRegion> Regions { get; } = new();
    [ObservableProperty] private CutPreview? _preview;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool _isAnalyzing = true;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    private bool _failed;
    [ObservableProperty] private string _status = "Analyzing…";

    private double _duration;
    private List<double>? _peaks;

    public ReviewModel(CrispEngine engine, QueueItem item, double pause, double keep)
    {
        _engine = engine;
        Item = item;
        _pause = pause;
        _keep = keep;
    }

    /// Run the engine's fast analyze pass and build the toggleable cut list.
    public async Task LoadAsync()
    {
        IsAnalyzing = true;
        Failed = false; // clear any prior failure if this is a re-analyze
        var raw = await _engine.AnalyzeAsync(Item.Path, CancellationToken.None);
        if (raw is null) { Fail("Couldn't analyze this file."); return; }
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var r = doc.RootElement;
            _duration = r.TryGetProperty("duration", out var d) ? d.GetDouble() : 0;
            _peaks = new List<double>();
            if (r.TryGetProperty("peaks", out var pk) && pk.ValueKind == JsonValueKind.Array)
                foreach (var v in pk.EnumerateArray()) _peaks.Add(v.GetDouble());

            Regions.Clear();
            if (r.TryGetProperty("silences", out var sil) && sil.ValueKind == JsonValueKind.Array)
                foreach (var s in sil.EnumerateArray())
                {
                    if (s.ValueKind != JsonValueKind.Array || s.GetArrayLength() < 2) continue;
                    double a = s[0].GetDouble(), b = s[1].GetDouble();
                    if (b - a <= _pause) continue;               // shorter than the threshold → not cut
                    double rs = a + _keep, re = b - _keep;       // keep breathing room each side
                    if (re <= rs) continue;
                    var region = new CutRegion { Start = rs, End = re };
                    region.PropertyChanged += OnRegionChanged;
                    Regions.Add(region);
                }
            Rebuild();
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            Fail("Couldn't read the analysis."); return;
        }
        IsAnalyzing = false;
    }

    private void OnRegionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(CutRegion.Remove)) Rebuild();
    }

    /// Rebuild the waveform shading + the summary from the currently-enabled cuts.
    private void Rebuild()
    {
        if (_peaks is null) return;
        var removed = Regions.Where(r => r.Remove).Select(r => new CutRange(r.Start, r.End)).ToList();
        Preview = new CutPreview { Duration = _duration, Peaks = _peaks, Removed = removed };
        var saved = removed.Sum(x => x.End - x.Start);
        Status = Regions.Count == 0
            ? "No pauses to trim — nothing to review."
            : $"Removing {Regions.Count(r => r.Remove)} of {Regions.Count} pauses · saving {Formatting.Duration(saved)}";
    }

    private void Fail(string why)
    {
        Failed = true;
        IsAnalyzing = false;
        Status = why;
    }

    public bool CanApply => !IsAnalyzing && !Failed && Regions.Count > 0;

    /// Write the approved keep-list and hand its path back for a --keep-file render.
    public string WriteKeepFile() => ReviewPlan.WriteKeepFile(_duration, Regions);
}
