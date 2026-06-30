using System;
using System.Collections.Generic;
using System.IO;

namespace Crisp;

/// The one canonical set of video file types Crisp accepts. The queue, the watch folder,
/// the Explorer right-click verb, and the file picker all read it from here so the lists
/// can't drift apart (mirrors the macOS CleanRunner allow-list).
public static class VideoTypes
{
    public static readonly IReadOnlyList<string> Extensions = new[]
    {
        ".mp4", ".mov", ".mkv", ".m4v", ".webm", ".avi", ".flv", ".ts",
        ".mpg", ".mpeg", ".wmv", ".m2ts", ".3gp", ".mts",
    };

    private static readonly HashSet<string> Set = new(Extensions, StringComparer.OrdinalIgnoreCase);

    public static bool IsVideo(string path) => Set.Contains(Path.GetExtension(path));
}
