using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.ViewModels;

public partial class MainWindowViewModel : ViewModelBase
{
    [ObservableProperty] private string _videoPath = "";
    [ObservableProperty] private double _progress;
    [ObservableProperty] private string _status = "Drop a video, then Clean.";
    [ObservableProperty] private bool _isRunning;

    public ObservableCollection<string> Log { get; } = new();

    private readonly CrispEngine _engine;
    private CancellationTokenSource? _cts;

    public MainWindowViewModel()
    {
        _engine = new CrispEngine { ScriptPath = ResolveEngineScript() };
    }

    [RelayCommand]
    private async Task Clean()
    {
        if (string.IsNullOrWhiteSpace(VideoPath) || !File.Exists(VideoPath))
        {
            Status = "Pick a real video file first.";
            return;
        }

        IsRunning = true;
        Progress = 0;
        Log.Clear();
        Status = "Cleaning…";
        _cts = new CancellationTokenSource();
        var progress = new Progress<EngineEvent>(OnEvent); // captures UI thread

        try
        {
            // Pauses-only for the proof: --no-fillers/--no-retakes skip whisper, so this
            // runs on ffmpeg alone (no speech model needed in dev).
            var code = await _engine.RunAsync(
                VideoPath,
                new[] { "--no-fillers", "--no-retakes", "--no-backup" },
                progress, _cts.Token);
            if (Status is "Cleaning…") Status = code == 0 ? "Done." : $"Engine exited {code}.";
        }
        catch (OperationCanceledException) { Status = "Cancelled."; }
        catch (Exception ex) { Status = "Failed to launch engine."; Log.Add("EXC: " + ex.Message); }
        finally { IsRunning = false; _cts = null; }
    }

    [RelayCommand]
    private void Cancel() => _cts?.Cancel();

    private void OnEvent(EngineEvent ev)
    {
        switch (ev.Event)
        {
            case "progress":
                if (ev.Fraction is { } f) Progress = Math.Clamp(f * 100, 0, 100);
                if (!string.IsNullOrWhiteSpace(ev.Label)) Status = ev.Label!;
                break;
            case "log": Log.Add(ev.Message ?? ""); break;
            case "result": Log.Add("✅ result: " + ev.Raw); Progress = 100; Status = "Done."; break;
            case "error": Log.Add("⛔️ error: " + (ev.Message ?? ev.Raw)); Status = "Error."; break;
        }
    }

    // ponytail: dev-only path resolution. Walk up to the shared engine; override with
    // CRISP_ENGINE_SCRIPT. The shipped Windows build will bundle the engine beside the .exe.
    private static string ResolveEngineScript()
    {
        var env = Environment.GetEnvironmentVariable("CRISP_ENGINE_SCRIPT");
        if (!string.IsNullOrEmpty(env)) return env;

        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "apps", "desktop", "Resources", "engine", "clean_video.py");
            if (File.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        return "clean_video.py"; // last resort; will fail loudly at launch
    }
}
