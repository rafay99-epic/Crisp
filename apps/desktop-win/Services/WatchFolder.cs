using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

namespace Crisp.Services;

/// Watches a folder and reports new video files (in-app port of the macOS watch
/// agent). Waits for each file to finish writing before reporting it. The full
/// background-when-closed agent is a Windows-service follow-up.
public sealed class WatchFolder : IDisposable
{
    private static readonly HashSet<string> VideoExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".mkv", ".m4v", ".webm", ".avi", ".flv", ".ts", ".mpg", ".mpeg", ".wmv", ".m2ts",
    };

    private readonly Action<string> _onVideo;
    private readonly HashSet<string> _seen = new(StringComparer.OrdinalIgnoreCase); // reported
    private readonly HashSet<string> _pending = new(StringComparer.OrdinalIgnoreCase); // stabilizing
    private FileSystemWatcher? _watcher;

    public WatchFolder(Action<string> onVideo) => _onVideo = onVideo;

    public bool IsWatching => _watcher is not null;

    public void Start(string folder)
    {
        Stop();
        if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder)) return;
        _watcher = new FileSystemWatcher(folder)
        {
            IncludeSubdirectories = false,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size,
            EnableRaisingEvents = true,
        };
        // Changed (alongside Created/Renamed) is what retries a file whose copy outlasted
        // the stabilize budget: the dedup guards below make the event spam harmless.
        _watcher.Created += (_, e) => OnAppeared(e.FullPath);
        _watcher.Renamed += (_, e) => OnAppeared(e.FullPath);
        _watcher.Changed += (_, e) => OnAppeared(e.FullPath);
    }

    private async void OnAppeared(string path)
    {
        if (!VideoExts.Contains(Path.GetExtension(path))) return;
        lock (_seen)
        {
            if (_seen.Contains(path)) return;   // already reported
            if (!_pending.Add(path)) return;    // a stabilizer is already running for it
        }
        var ok = await WaitStableAsync(path);
        lock (_seen)
        {
            _pending.Remove(path);
            if (ok) _seen.Add(path); // only now is it "seen"; a failed wait can retry on the next event
        }
        if (ok) _onVideo(path);
    }

    /// True once the file has stopped growing and can be opened for reading (i.e. the
    /// copy/recording finished). A still-growing file keeps resetting the patience budget,
    /// so a long copy is waited out rather than abandoned; only ~30s of genuine no-progress
    /// gives up (and a later write event re-runs this via the Changed subscription).
    private static async Task<bool> WaitStableAsync(string path)
    {
        long last = -1;
        var stalls = 0;
        while (stalls < 60)
        {
            try
            {
                var len = new FileInfo(path).Length;
                if (len > 0 && len == last)
                {
                    using var f = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                    return true;
                }
                if (len != last) { last = len; stalls = 0; } else stalls++;
            }
            catch (IOException) { stalls = 0; /* still being written/locked — keep waiting */ }
            catch (UnauthorizedAccessException) { stalls = 0; }
            await Task.Delay(500);
        }
        return false;
    }

    public void Stop()
    {
        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
            _watcher = null;
        }
        lock (_seen) { _seen.Clear(); _pending.Clear(); }
    }

    public void Dispose() => Stop();
}
