using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.ViewModels;

public enum AppState { Empty, Ready, Running, Done }

public partial class MainWindowViewModel : ViewModelBase
{
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsEmpty), nameof(IsReady), nameof(IsRunning), nameof(IsDone))]
    private AppState _state = AppState.Empty;

    public bool IsEmpty => State == AppState.Empty;
    public bool IsReady => State == AppState.Ready;
    public bool IsRunning => State == AppState.Running;
    public bool IsDone => State == AppState.Done;

    [ObservableProperty] private string? _videoPath;
    [ObservableProperty] private string _fileName = "";
    [ObservableProperty] private double _progress;
    [ObservableProperty] private string _status = "";
    [ObservableProperty] private string _resultSummary = "";
    [ObservableProperty] private string? _outputPath;
    [ObservableProperty] private bool _isDropTargeted;

    // Strength picker. Filler/retake removal needs the speech model (a later
    // iteration), so it's surfaced disabled in the view — pauses-only runs today.
    public IReadOnlyList<StrengthPreset> StrengthOptions { get; } = Strengths.All;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedStrengthDetail))]
    private StrengthPreset _selectedStrength = Strengths.Of(Strength.Aggressive);
    public string SelectedStrengthDetail => SelectedStrength.Detail;

    public ObservableCollection<string> Log { get; } = new();

    // Filler-word removal needs the whisper speech model. The store derives its
    // state from disk; the toggle + Clean gate on it.
    public ModelStore Models { get; } = new();
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(NeedsModel), nameof(CanClean))]
    private bool _removeFillers;

    /// Fillers requested but the model isn't downloaded yet — show the install control.
    public bool NeedsModel => RemoveFillers && !Models.IsReady;
    public bool CanClean => !NeedsModel;

    private readonly CrispEngine _engine;
    private CancellationTokenSource? _cts;

    public MainWindowViewModel()
    {
        _engine = new CrispEngine { ScriptPath = ResolveEngineScript() };
        Models.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(ModelStore.State) or nameof(ModelStore.IsReady))
            {
                OnPropertyChanged(nameof(NeedsModel));
                OnPropertyChanged(nameof(CanClean));
            }
        };
        _ = Models.RefreshAsync(); // derive model state from disk at launch
    }

    [RelayCommand]
    private Task DownloadModel() => Models.DownloadAsync();

    [RelayCommand]
    private void CancelModel() => Models.Cancel();

    /// Drag-drop / picker entry point. One file for now (queue is a later iteration).
    public void SetFile(string path)
    {
        if (IsRunning) return;
        VideoPath = path;
        FileName = Path.GetFileName(path);
        Log.Clear();
        Progress = 0;
        ResultSummary = "";
        OutputPath = null;
        Status = "";
        State = AppState.Ready;
    }

    [RelayCommand]
    private void Reset() => State = AppState.Empty;

    [RelayCommand]
    private async Task Clean()
    {
        if (VideoPath is null || !File.Exists(VideoPath)) { State = AppState.Empty; return; }

        State = AppState.Running;
        Progress = 0;
        Log.Clear();
        Status = "Starting…";
        _cts = new CancellationTokenSource();
        var progress = new Progress<EngineEvent>(OnEvent); // captures UI thread

        var args = new List<string>(Strengths.ToArgs(SelectedStrength.Value));
        if (RemoveFillers && Models.ReadyModelPath is { } modelPath)
        {
            // Fillers on: whisper transcribes via this model. Retakes stay off — a
            // distinct toggle in a later iteration.
            args.Add("--model"); args.Add(modelPath);
            args.Add("--no-retakes");
        }
        else
        {
            args.Add("--no-fillers"); args.Add("--no-retakes"); // pauses-only
        }
        args.Add("--no-backup");

        try
        {
            var code = await _engine.RunAsync(VideoPath, args, progress, _cts.Token);
            State = code == 0 ? AppState.Done : AppState.Ready;
            if (code != 0) Status = $"Engine exited {code}.";
        }
        catch (OperationCanceledException) { State = AppState.Ready; Status = "Cancelled."; }
        catch (Exception ex) { State = AppState.Ready; Status = "Failed to launch engine."; Log.Add("EXC: " + ex.Message); }
        finally { _cts = null; }
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
            case "result": ApplyResult(ev.Raw); Progress = 100; break;
            case "error": Log.Add("⛔️ " + (ev.Message ?? ev.Raw)); Status = "Error."; break;
        }
    }

    private void ApplyResult(string rawJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var r = doc.RootElement;
            OutputPath = r.TryGetProperty("output", out var o) ? o.GetString() : null;
            double orig = Num(r, "orig_seconds"), neu = Num(r, "new_seconds"), saved = Num(r, "saved_seconds");
            int pauses = (int)Num(r, "pauses");
            ResultSummary = $"{Fmt(orig)} → {Fmt(neu)}   ·   saved {Fmt(saved)}   ·   {pauses} pauses cut";
            Status = "Done.";
        }
        catch (JsonException) { ResultSummary = "Done."; }
    }

    private static double Num(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : 0;

    private static string Fmt(double seconds)
    {
        var t = TimeSpan.FromSeconds(seconds);
        return t.TotalMinutes >= 1
            ? $"{(int)t.TotalMinutes}m {t.Seconds}s"
            : seconds.ToString("0.#", CultureInfo.InvariantCulture) + "s";
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
        return "clean_video.py";
    }
}
