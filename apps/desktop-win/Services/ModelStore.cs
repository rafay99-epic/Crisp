using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using Crisp.Models;

namespace Crisp.Services;

public enum ModelState { Checking, Ready, Absent, Downloading, Verifying, Failed }

/// Owns the whisper speech model the engine needs for filler-word detection, as
/// UI-facing state. Port of macOS ModelStore + ChunkedDownloader + ModelProvisioner:
/// state is derived from disk + SHA-256 (no bookkeeping file), the download is
/// resumable (HTTP Range), verified by hash, and published atomically.
public partial class ModelStore : ObservableObject
{
    private ModelSpec _spec;
    private readonly bool _fetchSidecar;
    private readonly string _log;
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };
    private CancellationTokenSource? _cts;

    /// The whisper store (tracks the catalog selection).
    public ModelStore() : this(ModelCatalog.Base, fetchSidecar: false, logLabel: "model") { }

    /// A store pinned to one spec (the Wren filler model). `fetchSidecar` also pulls
    /// the model's config.json beside it after publish (framing/threshold metadata the
    /// engine passes to the helper) — best effort, like macOS FillerModelConfig.
    public ModelStore(ModelSpec spec, bool fetchSidecar, string logLabel)
    {
        _spec = spec;
        _fetchSidecar = fetchSidecar;
        _log = logLabel;
    }

    /// The catalog model this store currently tracks (the user's selection). Each model
    /// has its own file, so switching just re-points and re-checks disk.
    public ModelSpec Spec => _spec;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsReady), nameof(IsBusy), nameof(IsAbsent), nameof(IsFailed), nameof(IsVerifying))]
    private ModelState _state = ModelState.Checking;

    [ObservableProperty] private double _progress; // 0..1
    [ObservableProperty] private string _message = "";

    public bool IsReady => State == ModelState.Ready;
    public bool IsBusy => State is ModelState.Checking or ModelState.Downloading or ModelState.Verifying;
    // Per-state flags for the onboarding install control (XAML can't compare enums).
    public bool IsAbsent => State == ModelState.Absent;
    public bool IsFailed => State == ModelState.Failed;
    public bool IsVerifying => State == ModelState.Verifying;

    // CRISP_MODELS_DIR override (tests/CI), else the per-channel data home — nightly/dev
    // keep their own model so the channels stay isolated.
    public string ModelsDir => Channels.ModelsDirectory;
    public string ModelPath => Path.Combine(ModelsDir, _spec.FileName);
    private string PartPath => ModelPath + ".part";

    /// Absolute path the engine should load, or null until verified.
    public string? ReadyModelPath => IsReady ? ModelPath : null;
    public string SizeText => _spec.ApproxSizeText;
    public string DisplayName => _spec.DisplayName;

    /// Point the store at a different catalog model and recheck its state on disk.
    /// No-op while a download is in flight.
    public async Task UseAsync(string modelId)
    {
        var spec = ModelCatalog.Spec(modelId);
        // Block while Downloading OR Verifying: PartPath/ModelPath read _spec live, so
        // swapping it mid-verify would hash the downloaded bytes against the wrong
        // model's SHA-256 and orphan the finished .part file.
        if (spec.Id == _spec.Id || (IsBusy && State != ModelState.Checking)) return;
        FileLog.Info(_log, $"switching to {spec.Id}");
        _spec = spec;
        OnPropertyChanged(nameof(Spec));
        OnPropertyChanged(nameof(SizeText));
        OnPropertyChanged(nameof(DisplayName));
        await RefreshAsync();
    }

    /// Recompute state from disk. Hashes a present file to confirm it's intact; a
    /// complete-but-wrong file is removed (so it can't linger / re-hash every launch),
    /// a missing/partial/corrupt file resolves to Absent.
    public async Task RefreshAsync()
    {
        if (IsBusy && State != ModelState.Checking) return; // a download owns the state
        State = ModelState.Checking;
        if (File.Exists(ModelPath))
        {
            if (await VerifyAsync(ModelPath, CancellationToken.None)) { State = ModelState.Ready; return; }
            FileLog.Error(_log, $"{_spec.FileName} on disk failed its hash check — removing");
            TryDelete(ModelPath); // mismatched → remove, next launch resolves Absent instantly
        }
        State = ModelState.Absent;
    }

    public void Cancel()
    {
        FileLog.Info(_log, $"download of {_spec.Id} cancelled (.part kept for resume)");
        _cts?.Cancel(); // keeps the .part for resume
    }

    /// Download (resumable) → verify → atomic publish.
    public async Task DownloadAsync()
    {
        if (State == ModelState.Downloading) return;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        Directory.CreateDirectory(ModelsDir);

        try
        {
            var resuming = File.Exists(PartPath) ? $" (resuming from {new FileInfo(PartPath).Length / 1_000_000} MB)" : "";
            FileLog.Info(_log, $"downloading {_spec.Id} from {_spec.Url}{resuming}");
            State = ModelState.Downloading;
            Progress = 0;

            // A leftover .part that's already full-size (e.g. quit during verify) — verify
            // and publish it, never request a range at/past EOF (HF answers that with 416).
            if (File.Exists(PartPath) && new FileInfo(PartPath).Length >= _spec.ApproxBytes)
            {
                State = ModelState.Verifying;
                if (await VerifyAsync(PartPath, ct)) { Publish(); return; }
                TryDelete(PartPath); // wrong content/size → start clean
                State = ModelState.Downloading;
            }

            await StreamToPartAsync(ct);

            State = ModelState.Verifying;
            if (!await VerifyAsync(PartPath, ct))
            {
                TryDelete(PartPath); // corrupt — don't resume onto bad bytes
                Fail("Downloaded file failed verification. Please try again.");
                return;
            }
            Publish();
        }
        catch (OperationCanceledException) { State = ModelState.Absent; } // .part kept for resume
        catch (TimeoutException) { Fail("The download stalled. Please try again."); }
        catch (HttpRequestException ex) { FileLog.Error(_log, $"download of {_spec.Id} failed: {ex.Message}"); Fail("Download failed. Check your connection and try again."); }
        catch (Exception ex) { Fail(ex.Message); }
        finally { _cts = null; }
    }

    private void Publish()
    {
        File.Move(PartPath, ModelPath, overwrite: true); // atomic publish
        FileLog.Info(_log, $"{_spec.FileName} verified and installed → {ModelPath}");
        if (_fetchSidecar) _ = FetchSidecarAsync();
        State = ModelState.Ready;
    }

    /// Pull the model's config.json beside it (thresholds/framing the engine hands to
    /// the filler helper). Best effort — the helper has built-in defaults without it.
    private async Task FetchSidecarAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            var bytes = await Http.GetByteArrayAsync(_spec.SidecarUrl, cts.Token);
            var dst = Path.Combine(ModelsDir, _spec.SidecarFileName);
            await File.WriteAllBytesAsync(dst, bytes, cts.Token);
            FileLog.Info(_log, $"config sidecar fetched → {dst}");
        }
        catch (Exception ex) { FileLog.Info(_log, $"config sidecar skipped: {ex.Message}"); }
    }

    private static void TryDelete(string path) { try { File.Delete(path); } catch { /* best effort */ } }

    private async Task StreamToPartAsync(CancellationToken ct)
    {
        long have = File.Exists(PartPath) ? new FileInfo(PartPath).Length : 0;
        // ApproxBytes is only a heuristic to skip an obviously-complete .part — the 416
        // handler below and the SHA-256 verify are the authoritative correctness checks.
        if (have >= _spec.ApproxBytes) { TryDelete(PartPath); have = 0; }

        using var req = new HttpRequestMessage(HttpMethod.Get, _spec.Url);
        if (have > 0) req.Headers.Range = new RangeHeaderValue(have, null);

        // The 60s idle watchdog only covers reading the body; bound the connect/headers too,
        // so a stalled handshake fails instead of hanging forever (Http.Timeout is infinite).
        HttpResponseMessage resp;
        using (var headerCts = CancellationTokenSource.CreateLinkedTokenSource(ct))
        {
            headerCts.CancelAfter(TimeSpan.FromSeconds(30));
            try { resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, headerCts.Token); }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested) { throw new TimeoutException("The download stalled."); }
        }
        using var _response = resp;
        // A stale .part the server rejects as out-of-range → discard and restart from 0.
        if (resp.StatusCode == System.Net.HttpStatusCode.RequestedRangeNotSatisfiable && have > 0)
        {
            TryDelete(PartPath);
            await StreamToPartAsync(ct);
            return;
        }
        resp.EnsureSuccessStatusCode();

        // 206 → server honored the range, append; 200 → it ignored it, restart.
        bool resuming = resp.StatusCode == System.Net.HttpStatusCode.PartialContent;
        if (!resuming) have = 0;

        long total = (resp.Content.Headers.ContentLength ?? 0) + have;
        if (total <= 0) total = _spec.ApproxBytes;

        await using var part = new FileStream(PartPath, resuming ? FileMode.Append : FileMode.Create,
            FileAccess.Write, FileShare.None);
        await using var net = await resp.Content.ReadAsStreamAsync(ct);

        var buffer = new byte[81920];
        long received = have;
        var lastReport = 0L;
        while (true)
        {
            // 60s idle timeout: a stalled connection (bytes stop without the socket closing)
            // fails instead of hanging on "Downloading…" forever — while still honoring cancel.
            using var idle = CancellationTokenSource.CreateLinkedTokenSource(ct);
            idle.CancelAfter(TimeSpan.FromSeconds(60));
            int read;
            try { read = await net.ReadAsync(buffer, idle.Token); }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            { throw new TimeoutException("The download stalled."); }

            if (read <= 0) break;
            await part.WriteAsync(buffer.AsMemory(0, read), ct);
            received += read;
            if (received - lastReport > 1_000_000) // throttle UI updates (~1 MB)
            {
                lastReport = received;
                Progress = total > 0 ? Math.Clamp((double)received / total, 0, 1) : 0;
            }
        }
        Progress = 1;
    }

    private async Task<bool> VerifyAsync(string path, CancellationToken ct)
    {
        try
        {
            await using var fs = File.OpenRead(path);
            var hash = await SHA256.HashDataAsync(fs, ct);
            return Convert.ToHexString(hash).Equals(_spec.Sha256, StringComparison.OrdinalIgnoreCase);
        }
        catch (OperationCanceledException) { throw; }
        catch { return false; }
    }

    private void Fail(string message)
    {
        FileLog.Error(_log, $"{_spec.Id}: {message}");
        Message = message;
        State = ModelState.Failed;
    }
}
