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

    /// Raised when a batch finishes with at least one cleaned file — the window shows a
    /// toast. Carries the summary line ("Cleaned N · saved X").
    public event Action<string>? BatchCompleted;

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

    // Channel identity (stable/nightly/dev) is carried by the window title
    // ("Crisp Nightly" / "Crisp Dev") and the Settings ▸ About row.

    // Global recipe (applies to every file in the batch) — lives in the bottom bar.
    public IReadOnlyList<StrengthPreset> StrengthOptions { get; } = Strengths.All;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedStrengthDetail))]
    private StrengthPreset _selectedStrength = Strengths.Of(Strength.Aggressive);
    public string SelectedStrengthDetail => SelectedStrength.Detail;
    partial void OnSelectedStrengthChanged(StrengthPreset value)
    {
        if (_previewSilences is not null) RecomputeCutPreview(); // live update as strength changes
    }

    public ModelStore Models { get; } = new();
    public EngineSettings Settings { get; } = new();

    /// Per-row preset picker choices: a "Global recipe" sentinel (Id "") + the saved
    /// presets, kept in sync as the user adds/removes them in Settings.
    public ObservableCollection<Preset> PresetChoices { get; } = new();
    public bool HasPresets => Settings.Presets.Count > 0;
    public Updater Updater { get; } = new();
    public HistoryStore History { get; } = new();
    public OnboardingController Onboarding { get; } = new();
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

    // Accepted video types live in the shared VideoTypes (one source of truth for the
    // queue, watch folder, Explorer verb, and picker) — use VideoTypes.IsVideo / .Extensions.

    // A user-supplied model satisfies the gate without any download.
    public bool NeedsModel => (RemoveFillers || RemoveRetakes) && !Settings.HasCustomModel && !Models.IsReady;
    public bool CanClean => !NeedsModel;

    /// The model path handed to the engine: a custom .bin if set, else the selected
    /// catalog model once downloaded.
    private string? ActiveModelPath => Settings.HasCustomModel ? Settings.CustomModelPath : Models.ReadyModelPath;

    // Bottom-bar mode: recipe shown when there are waiting files and we're idle.
    public int PendingCount => Queue.Count(q => q.Status == QueueStatus.Waiting);
    public int DoneCount => Queue.Count(q => q.Status == QueueStatus.Done);
    public bool BottomShowsRecipe => !IsRunning && PendingCount > 0;
    public bool BottomShowsSummary => !IsRunning && PendingCount == 0 && DoneCount > 0;
    public string CleanButtonLabel => Settings.ExportToEditor
        ? (PendingCount == 1 ? "Prepare for Editor" : $"Prepare {PendingCount} for Editor")
        : (PendingCount == 1 ? "Clean Video" : $"Clean {PendingCount} Videos");
    public string CountLabel => IsRunning ? $"{DoneCount} of {Queue.Count} done"
        : PendingCount == Queue.Count ? $"{Queue.Count} video{(Queue.Count == 1 ? "" : "s")}"
        : $"{DoneCount} done · {PendingCount} waiting";

    private readonly CrispEngine _engine;
    private readonly WatchFolder _watch;
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
        // Track the user's selected model; switch + recheck when it (or the custom path) changes.
        Settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(EngineSettings.SelectedModelId))
                _ = Models.UseAsync(Settings.SelectedModelId);
            if (e.PropertyName is nameof(EngineSettings.SelectedModelId) or nameof(EngineSettings.CustomModelPath))
            {
                OnPropertyChanged(nameof(NeedsModel));
                OnPropertyChanged(nameof(CanClean));
                CleanAllCommand.NotifyCanExecuteChanged();
            }
            if (e.PropertyName == nameof(EngineSettings.ExportToEditor))
                OnPropertyChanged(nameof(CleanButtonLabel));
            if (e.PropertyName is nameof(EngineSettings.WatchEnabled) or nameof(EngineSettings.WatchFolderPath))
                ApplyWatchSettings();
        };
        RebuildPresetChoices();
        Settings.Presets.CollectionChanged += (_, _) =>
        {
            RebuildPresetChoices();
            OnPropertyChanged(nameof(HasPresets));
        };
        _watch = new WatchFolder(OnWatchedVideo);
        ApplyWatchSettings();
        Queue.CollectionChanged += (_, _) => RefreshCounts();
        if (Settings.SelectedModelId != Models.Spec.Id) _ = Models.UseAsync(Settings.SelectedModelId);
        else _ = Models.RefreshAsync();
        _ = Updater.CheckAsync(); // check for a newer release on launch (banner if found)
    }

    [RelayCommand]
    private void DownloadUpdate() => Updater.OpenDownload();

    [RelayCommand]
    private void FinishOnboarding() => Onboarding.Complete();

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
        UpdateOverall(); // keep the batch bar in sync when rows change state, not just on progress
    }

    private void RebuildPresetChoices()
    {
        PresetChoices.Clear();
        PresetChoices.Add(new Preset { Id = "", Name = "Global recipe" });
        foreach (var p in Settings.Presets) PresetChoices.Add(p);
    }

    private void ApplyWatchSettings()
    {
        if (Settings.WatchEnabled && Directory.Exists(Settings.WatchFolderPath))
            _watch.Start(Settings.WatchFolderPath);
        else
            _watch.Stop();
    }

    /// A new video appeared in the watch folder (on a watcher thread) — queue it and,
    /// if idle, start cleaning. Marshalled to the UI thread.
    private void OnWatchedVideo(string path)
    {
        Avalonia.Threading.Dispatcher.UIThread.Post(() =>
        {
            AddFiles(new[] { path });
            if (!IsRunning && CanCleanAll()) _ = CleanAllCommand.ExecuteAsync(null);
        });
    }

    /// Append one or more videos as waiting rows (drag-drop / picker / open-with).
    /// Ignores non-video files and de-dupes case-insensitively (Windows paths).
    public void AddFiles(IEnumerable<string> paths)
    {
        foreach (var p in paths)
            if (File.Exists(p)
                && VideoTypes.IsVideo(p)
                && !Queue.Any(q => string.Equals(q.Path, p, StringComparison.OrdinalIgnoreCase)))
                Queue.Add(new QueueItem(p) { PresetId = Settings.DefaultPresetId });
        EstimateText = ""; // queue changed → any estimate is stale
        ClearCutPreview(); // …and the cut preview (it was for the previous first file)
    }

    [RelayCommand]
    private void Remove(QueueItem item)
    {
        if (item.Status != QueueStatus.Running) Queue.Remove(item);
    }

    [RelayCommand]
    private void Retry(QueueItem item)
    {
        // Reset every result/progress field so a retried row starts clean — a stale
        // OutputPath/summary from the failed attempt must not linger.
        item.Status = QueueStatus.Waiting;
        item.Error = null;
        item.Progress = 0;
        item.Stage = "";
        item.CutsSummary = "";
        item.OutputPath = null;
        item.BackupPath = null;
        item.IsEditorExport = false;
        item.CanOpenInEditor = false;
        item.KeepFilePath = null;
        item.OrigSeconds = 0;
        item.SavedSeconds = 0;
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

        var doneBefore = DoneCount; // so the toast fires only if THIS batch cleaned something
        IsRunning = true;
        RefreshCounts();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        using var slot = new SemaphoreSlim(Settings.Concurrency);

        try
        {
            // Clean up to Settings.Concurrency files at once; the semaphore bounds how many
            // heavy ffmpeg/whisper runs overlap.
            var tasks = waiting.Select(async item =>
            {
                try
                {
                    await slot.WaitAsync(ct);
                    try { await CleanItem(item, ct); }
                    finally { slot.Release(); }
                }
                catch (OperationCanceledException) { item.Status = QueueStatus.Cancelled; }
                // A failure to even launch the engine (e.g. Python missing) fails that row,
                // never escaping to wedge IsRunning stuck true.
                catch (Exception ex) { item.Status = QueueStatus.Failed; item.Error = LaunchError(ex); }
                RefreshCounts();
            });
            await Task.WhenAll(tasks);
        }
        finally
        {
            IsRunning = false;
            _cts = null;
            UpdateOverall();
            RefreshCounts();
            if (DoneCount > doneBefore) BatchCompleted?.Invoke(SummaryText);
        }
    }

    private static string LaunchError(Exception ex) =>
        ex is System.ComponentModel.Win32Exception
            ? "Couldn't start the engine — Python wasn't found."
            : ex.Message;

    [RelayCommand]
    private void Cancel() => _cts?.Cancel();

    [ObservableProperty] private string _estimateText = "";
    [ObservableProperty] private bool _isEstimating;

    /// Pre-flight "≈ X saved" — runs the engine's fast analyze pass on the waiting files
    /// and applies the pause-cut math (pauses only; fillers/retakes are counted while
    /// cleaning since they need transcription).
    [RelayCommand]
    private async Task Estimate()
    {
        var waiting = Queue.Where(q => q.Status == QueueStatus.Waiting).ToList();
        if (waiting.Count == 0 || IsRunning || IsEstimating) return;
        IsEstimating = true;
        EstimateText = "Estimating…";

        var custom = SelectedStrength.Value == Strength.Custom;
        double pause = custom ? Settings.PauseThreshold : SelectedStrength.Pause;
        double keep = custom ? Settings.BreathingRoom : SelectedStrength.KeepPause;
        double totalDur = 0, removed = 0;
        int pauses = 0, failed = 0;

        foreach (var item in waiting)
        {
            var raw = await _engine.AnalyzeAsync(item.Path, CancellationToken.None);
            if (raw is null) { failed++; continue; }
            try
            {
                using var doc = JsonDocument.Parse(raw);
                var r = doc.RootElement;
                totalDur += r.TryGetProperty("duration", out var d) ? d.GetDouble() : 0;
                if (r.TryGetProperty("silences", out var sil) && sil.ValueKind == JsonValueKind.Array)
                    foreach (var s in sil.EnumerateArray())
                    {
                        if (s.ValueKind != JsonValueKind.Array || s.GetArrayLength() < 2) continue;
                        double len = s[1].GetDouble() - s[0].GetDouble();
                        if (len > pause) { removed += Math.Max(0, len - 2 * keep); pauses++; }
                    }
            }
            catch (JsonException) { failed++; }
        }

        var pct = totalDur > 0 ? (int)(removed / totalDur * 100) : 0;
        EstimateText = $"≈ {Formatting.Duration(removed)} saved · {pauses} pause{(pauses == 1 ? "" : "s")} ({pct}% shorter)"
            + (failed > 0 ? " · some files couldn't be read" : "")
            + " · fillers & retakes counted while cleaning";
        IsEstimating = false;
    }

    // --- Review & edit cuts ---
    /// Build a review session for a row, seeded with the current strength's cut thresholds.
    public ReviewModel CreateReview(QueueItem item)
    {
        var custom = SelectedStrength.Value == Strength.Custom;
        double pause = custom ? Settings.PauseThreshold : SelectedStrength.Pause;
        double keep = custom ? Settings.BreathingRoom : SelectedStrength.KeepPause;
        return new ReviewModel(_engine, item, pause, keep);
    }

    /// Apply the reviewed cuts: write the keep-file onto the row and clean just it.
    public async Task ApplyReviewAndCleanAsync(QueueItem item, ReviewModel review)
    {
        // A batch is already running (or the row isn't waiting) — CleanOneAsync would no-op,
        // so don't write a keep-file we'd then orphan in TEMP.
        if (IsRunning || item.Status != QueueStatus.Waiting) return;
        item.KeepFilePath = review.WriteKeepFile();
        await CleanOneAsync(item);
    }

    /// Clean a single waiting row (used by the review flow); mirrors CleanAll for one item.
    private async Task CleanOneAsync(QueueItem item)
    {
        if (IsRunning || item.Status != QueueStatus.Waiting) return;
        var doneBefore = DoneCount;
        IsRunning = true;
        RefreshCounts();
        _cts = new CancellationTokenSource();
        try { await CleanItem(item, _cts.Token); }
        catch (OperationCanceledException) { item.Status = QueueStatus.Cancelled; }
        catch (Exception ex) { item.Status = QueueStatus.Failed; item.Error = LaunchError(ex); }
        finally
        {
            IsRunning = false;
            _cts = null;
            UpdateOverall();
            RefreshCounts();
            if (DoneCount > doneBefore) BatchCompleted?.Invoke(SummaryText);
        }
    }

    // --- Cut preview (waveform of what will be removed) ---
    [ObservableProperty] private CutPreview? _cutPreview;
    [ObservableProperty] private bool _isPreviewingCuts;
    // Cached analysis so dragging the strength recomputes cut regions without re-analyzing.
    private double _previewDuration;
    private List<double>? _previewPeaks;
    private List<(double Start, double End)>? _previewSilences;

    /// Analyze the first waiting file and show its waveform with the cut regions shaded
    /// (pauses only — fillers/retakes need transcription). Reuses the engine `--analyze`.
    [RelayCommand]
    private async Task PreviewCuts()
    {
        var first = Queue.FirstOrDefault(q => q.Status == QueueStatus.Waiting);
        if (first is null || IsPreviewingCuts || IsRunning) return;
        IsPreviewingCuts = true;
        try
        {
            var raw = await _engine.AnalyzeAsync(first.Path, CancellationToken.None);
            if (raw is null) { CutPreview = null; return; }
            using var doc = JsonDocument.Parse(raw);
            var r = doc.RootElement;
            _previewDuration = r.TryGetProperty("duration", out var d) ? d.GetDouble() : 0;
            _previewPeaks = new List<double>();
            if (r.TryGetProperty("peaks", out var pk) && pk.ValueKind == JsonValueKind.Array)
                foreach (var v in pk.EnumerateArray()) _previewPeaks.Add(v.GetDouble());
            _previewSilences = new List<(double, double)>();
            if (r.TryGetProperty("silences", out var sil) && sil.ValueKind == JsonValueKind.Array)
                foreach (var s in sil.EnumerateArray())
                    if (s.ValueKind == JsonValueKind.Array && s.GetArrayLength() >= 2)
                        _previewSilences.Add((s[0].GetDouble(), s[1].GetDouble()));
            RecomputeCutPreview();
        }
        catch (JsonException) { CutPreview = null; }
        finally { IsPreviewingCuts = false; }
    }

    /// Rebuild the shaded cut ranges from the cached silences at the current strength —
    /// a silence longer than the pause threshold is cut, keeping breathing room each side.
    private void RecomputeCutPreview()
    {
        if (_previewPeaks is null || _previewSilences is null) return;
        var custom = SelectedStrength.Value == Strength.Custom;
        double pause = custom ? Settings.PauseThreshold : SelectedStrength.Pause;
        double keep = custom ? Settings.BreathingRoom : SelectedStrength.KeepPause;
        var removed = new List<CutRange>();
        foreach (var (a, b) in _previewSilences)
            if (b - a > pause)
            {
                double rs = a + keep, re = b - keep;
                if (re > rs) removed.Add(new CutRange(rs, re));
            }
        CutPreview = new CutPreview { Duration = _previewDuration, Peaks = _previewPeaks, Removed = removed };
    }

    private void ClearCutPreview()
    {
        CutPreview = null;
        _previewPeaks = null;
        _previewSilences = null;
    }

    private async Task CleanItem(QueueItem item, CancellationToken ct)
    {
        item.Status = QueueStatus.Running;
        item.Progress = 0;
        item.Stage = "Starting…";
        item.Error = null;
        // Clear any result metadata from a prior attempt so a re-clean (e.g. after the
        // engine emitted a result then failed) never shows stale output/summary.
        item.CutsSummary = "";
        item.OutputPath = null;
        item.BackupPath = null;
        item.IsEditorExport = false;
        item.CanOpenInEditor = false;
        item.OrigSeconds = 0;
        item.SavedSeconds = 0;
        // Per-row recipe: a row's preset (if any) overrides the global recipe knobs; a
        // reviewed row renders its approved keep-file instead of auto-detected cuts.
        var args = BuildArgs(Settings.PresetById(item.PresetId), item.KeepFilePath);
        var progress = new Progress<EngineEvent>(ev => OnItemEvent(item, ev));

        try
        {
            var code = await _engine.RunAsync(item.Path, args, progress, ct);
            if (item.Status == QueueStatus.Running)
            {
                item.Status = code == 0 ? QueueStatus.Done : QueueStatus.Failed;
                if (code != 0 && item.Error is null) item.Error = $"Engine exited {code}.";
            }
        }
        finally
        {
            // The reviewed keep-file is a one-shot temp; the engine has read it by now.
            if (item.KeepFilePath is { } kf)
            {
                try { if (File.Exists(kf)) File.Delete(kf); } catch { /* best effort */ }
                item.KeepFilePath = null;
            }
        }
    }

    private IReadOnlyList<string> BuildArgs(Preset? preset = null, string? keepFile = null)
    {
        // The recipe (cutting + smoothing + encoding + backup + captions) comes from
        // Settings (or the row's preset, which overrides the recipe knobs); the VM only
        // adds the filler/retake/model flags.
        var args = new List<string>(Settings.RecipeArgs(SelectedStrength.Value, preset));

        // Reviewed render: the engine renders exactly the approved keep segments and skips
        // detection/transcription/model, so the encode flags above apply but the cutting/
        // filler/retake flags don't matter.
        if (keepFile is not null)
        {
            args.Add("--keep-file"); args.Add(keepFile);
            return args;
        }

        // Both fillers and retakes need whisper to transcribe; pauses-only needs no model.
        if ((RemoveFillers || RemoveRetakes) && ActiveModelPath is { } modelPath)
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

            // Editor handoff: the result is a project folder (FCPXML + media copy), not a
            // rendered video — point Reveal at the project and tag the row.
            if (r.TryGetProperty("export_timeline", out var et) && et.GetString() == "fcpxml")
            {
                item.IsEditorExport = true;
                item.CanOpenInEditor = DetectedEditor is not null; // show "Open in <editor>" only if one exists
                if (r.TryGetProperty("project_dir", out var pd) && pd.GetString() is { Length: > 0 } proj)
                    item.OutputPath = proj;
            }
            if (r.TryGetProperty("backup", out var bk) && bk.GetString() is { Length: > 0 } backup)
                item.BackupPath = backup;
            item.OrigSeconds = Num(r, "orig_seconds");
            item.SavedSeconds = Num(r, "saved_seconds");
            int pauses = (int)Num(r, "pauses"), fillers = (int)Num(r, "fillers"), retakes = (int)Num(r, "retakes");
            var parts = new List<string>();
            if (fillers > 0) parts.Add($"{fillers} filler{(fillers == 1 ? "" : "s")}");
            if (retakes > 0) parts.Add($"{retakes} retake{(retakes == 1 ? "" : "s")}");
            if (pauses > 0) parts.Add($"{pauses} pause{(pauses == 1 ? "" : "s")}");
            var summary = parts.Count > 0 ? string.Join(" · ", parts) : "";
            if (item.IsEditorExport)
                summary = string.IsNullOrEmpty(summary) ? "Editor timeline (FCPXML)" : summary + " · editor timeline";
            item.CutsSummary = summary;

            History.Record(new HistoryEntry
            {
                Date = DateTime.UtcNow,
                InputPath = item.Path,
                OutputPath = item.OutputPath ?? "",
                OrigSeconds = item.OrigSeconds,
                SavedSeconds = item.SavedSeconds,
                Fillers = fillers, Pauses = pauses, Retakes = retakes,
            });
        }
        // JsonException for malformed JSON; InvalidOperationException if a value is the
        // wrong kind (e.g. GetString on a non-string) — either way, leave the row's result
        // fields as-is rather than letting it escape the Progress callback on the UI thread.
        catch (Exception ex) when (ex is JsonException or InvalidOperationException) { /* leave summary empty */ }
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

    // The detected editor for the handoff (first installed), resolved once at launch.
    public VideoEditor? DetectedEditor { get; } = EditorDetector.First();
    public string OpenInEditorLabel => DetectedEditor is { } e ? $"Open in {e.Name}" : "Open project";

    /// Editor handoff: open the detected editor and reveal the project so the user does
    /// the one manual File ▸ Import ▸ Timeline step (free editors can't auto-import).
    [RelayCommand]
    private void OpenInEditor(QueueItem item)
    {
        if (DetectedEditor is { } e) EditorDetector.Launch(e);
        RevealInOS(item.OutputPath);
    }

    [RelayCommand]
    private void Reveal(QueueItem item) => RevealInOS(item.OutputPath);

    [RelayCommand]
    private void RevealBackup(QueueItem item) => RevealInOS(item.BackupPath);

    /// Copy the backed-up pristine original into a folder the user picked, never
    /// overwriting (dedupe the name), then reveal it. Port of macOS Restore.restoreOriginal.
    public void RestoreOriginal(QueueItem item, string destDir)
    {
        if (item.BackupPath is not { } backup || !File.Exists(backup) || !Directory.Exists(destDir)) return;
        var name = Path.GetFileName(backup);
        var target = Path.Combine(destDir, name);
        for (var i = 1; File.Exists(target); i++)
            target = Path.Combine(destDir, $"{Path.GetFileNameWithoutExtension(name)}_{i}{Path.GetExtension(name)}");
        try { File.Copy(backup, target); RevealInOS(target); }
        catch { /* best effort — never throws into the UI */ }
    }

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

    /// Play the cleaned output in the system's default video player. (Parity with the
    /// macOS in-app preview; an embedded player would need a native video dependency.)
    [RelayCommand]
    private void Play(QueueItem item) => OpenInDefaultApp(item.OutputPath);

    private static void OpenInDefaultApp(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        try
        {
            if (OperatingSystem.IsWindows())
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
            else if (OperatingSystem.IsMacOS())
                System.Diagnostics.Process.Start("open", new[] { path });
            else
                System.Diagnostics.Process.Start("xdg-open", new[] { path });
        }
        catch { /* best effort */ }
    }

    // Reveal a file (or a project folder, for editor exports) in the OS browser.
    private static void RevealInOS(string? path)
    {
        if (string.IsNullOrEmpty(path) || (!File.Exists(path) && !Directory.Exists(path))) return;
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
