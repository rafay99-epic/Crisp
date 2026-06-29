using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Crisp.Models;

namespace Crisp.Services;

/// Turns a reviewed set of cut regions into the engine's `--keep-file` — the inverse of
/// the cuts: the keep segments are the timeline minus every region the user left checked
/// for removal. The engine then renders exactly those segments (no detection/model).
public static class ReviewPlan
{
    /// Keep segments (seconds, on the original timeline) = the complement of the regions
    /// still marked Remove. Overlapping cuts merge; disabled cuts stay in the output.
    public static List<double[]> KeepSegments(double duration, IEnumerable<CutRegion> regions)
    {
        var cuts = regions
            .Where(r => r.Remove)
            .Select(r => (Start: Math.Max(0, r.Start), End: Math.Min(duration, r.End)))
            .Where(c => c.End > c.Start)
            .OrderBy(c => c.Start)
            .ToList();

        var keeps = new List<double[]>();
        double cursor = 0;
        foreach (var (start, end) in cuts)
        {
            if (start > cursor) keeps.Add(new[] { cursor, start });
            cursor = Math.Max(cursor, end); // max → overlapping cuts merge
        }
        if (cursor < duration) keeps.Add(new[] { cursor, duration });
        return keeps;
    }

    /// Write a temp `{"keep": [[start, end], ...]}` file for `--keep-file` and return its path.
    public static string WriteKeepFile(double duration, IEnumerable<CutRegion> regions)
    {
        var keeps = KeepSegments(duration, regions);
        var path = Path.Combine(Path.GetTempPath(), $"crisp-keep-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(new { keep = keeps }));
        return path;
    }
}
