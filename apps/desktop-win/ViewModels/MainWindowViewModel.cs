using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
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

public partial class MainWindowViewModel : ViewModelBase
{
    public ObservableCollection<QueueItem> Queue { get; } = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsEmpty))]
    private bool _hasItems;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(BottomShowsRecipe), nameof(BottomShowsSummary))]
    private bool _isRunning;

    [ObservableProperty] private double _overallProgress; // 0…1
    [ObservableProperty] private string _status = "";
    [ObservableProperty] private bool _isDropTargeted;

    public bool IsEmpty => !HasItems;

    // Global recipe (applies to every file in the batch) — lives in the bottom bar.
    public IReadOnlyList<StrengthPreset> StrengthOptions { get; } = Strengths.All;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedStrengthDetail))]
    private StrengthPreset _selectedStrength = Strengths.Of(Strength.Aggressive);
    public string SelectedStrengthDetail => SelectedStrength.Detail;

    public ModelStore Models { get; } = new();
    public EngineSettings Settings { get; } = new();
    public Updater Updater { get; } = new();
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(NeedsModel), nameof(CanClean))]
    [NotifyCanExecuteChangedFor(nameof(CleanAllCommand))]
    private bool _removeFillers;

    // Repeated-take removal also needs the speech model (it transcribes to find a
    // flubbed-then-repeated take), so it shares the model gate with fillers.
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(NeedsModel), nameof(CanClean))]
    [NotifyCanExecuteChangedFor(nameof(CleanAllCommand))]
    private bool _removeRetakes;

    // Accepted video types (mirrors the Mac CleanRunner allow-list) — a dropped
    // non-video is ignored rather than queued and failed.
    private static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".mkv", ".m4v", ".webm", ".avi", ".flv", ".ts",
        ".mpg", ".mpeg", ".wmv", ".m2ts", ".3gp", ".mts",
    };

    public bool NeedsModel => (RemoveFillers || RemoveRetakes) && !Models.IsReady;
    public bool CanClean => !NeedsModel;

    // Bottom-bar mode: recipe shown when there are waiting files and we're idle.
    public int PendingCount => Queue.Count(q => q.Status == QueueStatus.Waiting);
    public int DoneCount => Queue.Count(q => q.Status == QueueStatus.Done);
    public bool BottomShowsRecipe => !IsRunning && PendingCount > 0;
    public bool BottomShowsSummary => !IsRunning && PendingCount == 0 && DoneCount > 0;
    public string CleanButtonLabel => PendingCount == 1 ? "Clean Video" : $"Clean {PendingCount} Videos";
    public string CountLabel => IsRunning ? $"{DoneCount} of {Queue.Count} done"
        : PendingCount == Queue.Count ? $"{Queue.Count} video{(Queue.Count == 1 ? "" : "s")}"
        : $"{DoneCount} done · {PendingCount} waiting";

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
                CleanAllCommand.NotifyCanExecuteChanged();
            }
        };
        Queue.CollectionChanged += (_, _) => RefreshCounts();
        _ = Models.RefreshAsync();
        _ = Updater.CheckAsync(); // check for a newer release on launch (banner if found)
    }

    [RelayCommand]
    private void DownloadUpdate() => Updater.OpenDownload();

    private void RefreshCounts()
    {
        HasItems = Queue.Count > 0;
        OnPropertyChanged(nameof(PendingCount));
        OnPropertyChanged(nameof(DoneCount));
        OnPropertyChanged(nameof(BottomShowsRecipe));
        OnPropertyChanged(nameof(BottomShowsSummary));
        OnPropertyChanged(nameof(CleanButtonLabel));
        OnPropertyChanged(nameof(CountLabel));
        OnPropertyChanged(nameof(SummaryText));
        CleanAllCommand.NotifyCanExecuteChanged();
    }

    /// Append one or more videos as waiting rows (drag-drop / picker / open-with).
    /// Ignores non-video files and de-dupes case-insensitively (Windows paths).
    public void AddFiles(IEnumerable<string> paths)
    {
        foreach (var p in paths)
            if (File.Exists(p)
                && VideoExtensions.Contains(Path.GetExtension(p))
                && !Queue.Any(q => string.Equals(q.Path, p, StringComparison.OrdinalIgnoreCase)))
                Queue.Add(new QueueItem(p));
    }

    [RelayCommand]
    private void Remove(QueueItem item)
    {
        if (item.Status != QueueStatus.Running) Queue.Remove(item);
    }

    [RelayCommand]
    private void Retry(QueueItem item)
    {
        item.Status = QueueStatus.Waiting;
        item.Error = null;
        item.Progress = 0;
        RefreshCounts();
    }

    [RelayCommand]
    private void Clear()
    {
        if (IsRunning) return;
        for (var i = Queue.Count - 1; i >= 0; i--)
            if (Queue[i].Status != QueueStatus.Running) Queue.RemoveAt(i);
    }

    private bool CanCleanAll() => !IsRunning && PendingCount > 0 && CanClean;

    [RelayCommand(CanExecute = nameof(CanCleanAll))]
    private async Task CleanAll()
    {
        var waiting = Queue.Where(q => q.Status == QueueStatus.Waiting).ToList();
        if (waiting.Count == 0) return;

        IsRunning = true;
        RefreshCounts();
        _cts = new CancellationTokenSource();
        var args = BuildArgs();

        try
        {
            foreach (var item in waiting)
            {
                if (_cts.IsCancellationRequested) break;
                try { await CleanItem(item, args, _cts.Token); }
                catch (OperationCanceledException) { item.Status = QueueStatus.Cancelled; break; }
                // A failure to even launch the engine (e.g. Python missing) must fail the
                // row and move on — never escape the loop and wedge IsRunning stuck true.
                catch (Exception ex) { item.Status = QueueStatus.Failed; item.Error = LaunchError(ex); }
                RefreshCounts();
            }
        }
        finally
        {
            IsRunning = false;
            _cts = null;
            UpdateOverall();
            RefreshCounts();
        }
    }

    private static string LaunchError(Exception ex) =>
        ex is System.ComponentModel.Win32Exception
            ? "Couldn't start the engine — Python wasn't found."
            : ex.Message;

    [RelayCommand]
    private void Cancel() => _cts?.Cancel();

    private async Task CleanItem(QueueItem item, IReadOnlyList<string> args, CancellationToken ct)
    {
        item.Status = QueueStatus.Running;
        item.Progress = 0;
        item.Stage = "Starting…";
        item.Error = null;
        var progress = new Progress<EngineEvent>(ev => OnItemEvent(item, ev));

        var code = await _engine.RunAsync(item.Path, args, progress, ct);
        if (item.Status == QueueStatus.Running)
        {
            item.Status = code == 0 ? QueueStatus.Done : QueueStatus.Failed;
            if (code != 0 && item.Error is null) item.Error = $"Engine exited {code}.";
        }
    }

    private IReadOnlyList<string> BuildArgs()
    {
        // The recipe (cutting + smoothing + encoding + backup + captions) comes from
        // Settings; the VM only adds the filler/retake/model flags.
        var args = new List<string>(Settings.RecipeArgs(SelectedStrength.Value));

        // Both fillers and retakes need whisper to transcribe; pauses-only needs no model.
        if ((RemoveFillers || RemoveRetakes) && Models.ReadyModelPath is { } modelPath)
        {
            args.Add("--model"); args.Add(modelPath);
            if (!RemoveFillers) { args.Add("--no-fillers"); }
            if (RemoveRetakes) { args.Add("--retake-sensitivity"); args.Add(Settings.RetakeSensitivity); }
            else { args.Add("--no-retakes"); }
        }
        else
        {
            args.Add("--no-fillers"); args.Add("--no-retakes");
        }
        return args;
    }

    private void OnItemEvent(QueueItem item, EngineEvent ev)
    {
        switch (ev.Event)
        {
            case "progress":
                if (ev.Fraction is { } f) item.Progress = Math.Clamp(f, 0, 1);
                if (!string.IsNullOrWhiteSpace(ev.Label)) item.Stage = ev.Label!;
                UpdateOverall();
                break;
            case "result": ApplyResult(item, ev.Raw); break;
            case "error": item.Error = ev.Message ?? ev.Raw; break;
        }
    }

    private void UpdateOverall()
    {
        if (Queue.Count == 0) { OverallProgress = 0; return; }
        double sum = 0;
        foreach (var q in Queue)
            sum += q.Status == QueueStatus.Done ? 1 : q.Status == QueueStatus.Running ? q.Progress : 0;
        OverallProgress = sum / Queue.Count;
        Status = Queue.FirstOrDefault(q => q.Status == QueueStatus.Running)?.Stage ?? "";
    }

    private void ApplyResult(QueueItem item, string rawJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var r = doc.RootElement;
            item.OutputPath = r.TryGetProperty("output", out var o) ? o.GetString() : null;
            item.OrigSeconds = Num(r, "orig_seconds");
            item.SavedSeconds = Num(r, "saved_seconds");
            int pauses = (int)Num(r, "pauses"), fillers = (int)Num(r, "fillers"), retakes = (int)Num(r, "retakes");
            var parts = new List<string>();
            if (fillers > 0) parts.Add($"{fillers} filler{(fillers == 1 ? "" : "s")}");
            if (retakes > 0) parts.Add($"{retakes} retake{(retakes == 1 ? "" : "s")}");
            if (pauses > 0) parts.Add($"{pauses} pause{(pauses == 1 ? "" : "s")}");
            item.CutsSummary = parts.Count > 0 ? string.Join(" · ", parts) : "";
        }
        catch (JsonException) { /* leave summary empty */ }
    }

    /// Batch summary for the bottom bar once everything finishes.
    public string SummaryText
    {
        get
        {
            var done = Queue.Where(q => q.Status == QueueStatus.Done).ToList();
            if (done.Count == 0) return "";
            var saved = done.Sum(q => q.SavedSeconds);
            return $"Cleaned {done.Count} · saved {Formatting.Duration(saved)}";
        }
    }

    private static double Num(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : 0;

    [RelayCommand]
    private Task DownloadModel() => Models.DownloadAsync();

    [RelayCommand]
    private void CancelModel() => Models.Cancel();

    [RelayCommand]
    private void Reveal(QueueItem item) => RevealInOS(item.OutputPath);

    [RelayCommand]
    private void RevealAll()
    {
        // Reveal one file per distinct folder (cleaned files may span folders) — don't
        // open N Explorer/Finder windows for N files that share a directory.
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in Queue.Where(q => q.IsDone).Select(q => q.OutputPath))
            if (path is not null && seen.Add(Path.GetDirectoryName(path) ?? path))
                RevealInOS(path);
    }

    // Reveal a file in the OS browser. ponytail: per-OS one-liners, no library.
    private static void RevealInOS(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        try
        {
            if (OperatingSystem.IsWindows())
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                    "explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            else if (OperatingSystem.IsMacOS())
                System.Diagnostics.Process.Start("open", new[] { "-R", path });
            else
                System.Diagnostics.Process.Start("xdg-open", new[] { Path.GetDirectoryName(path) ?? "." });
        }
        catch { /* reveal is best-effort */ }
    }

    // ponytail: dev-only path resolution; override with CRISP_ENGINE_SCRIPT. The shipped
    // Windows build bundles the engine beside the .exe.
    private static string ResolveEngineScript()
    {
        var env = Environment.GetEnvironmentVariable("CRISP_ENGINE_SCRIPT");
        if (!string.IsNullOrEmpty(env)) return env;

        // Shipped layout: the engine is bundled beside the .exe.
        var bundled = Path.Combine(AppContext.BaseDirectory, "engine", "clean_video.py");
        if (File.Exists(bundled)) return bundled;

        // Dev layout: walk up to the shared engine in the repo.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "apps", "desktop", "Resources", "engine", "clean_video.py");
            if (File.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        // Last resort: the absolute bundled path (so CrispEngine's working dir isn't ".").
        return bundled;
    }
}
