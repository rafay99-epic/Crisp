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
    private readonly ModelSpec _spec = ModelCatalog.Base;
    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };
    private CancellationTokenSource? _cts;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsReady), nameof(IsBusy))]
    private ModelState _state = ModelState.Checking;

    [ObservableProperty] private double _progress; // 0..1
    [ObservableProperty] private string _message = "";

    public bool IsReady => State == ModelState.Ready;
    public bool IsBusy => State is ModelState.Checking or ModelState.Downloading or ModelState.Verifying;

    // ponytail: CRISP_MODELS_DIR override (tests/CI); default is the channel data home.
    // Channel-specific dirs (~/.crisp-nightly etc.) come with the Channel port later.
    public string ModelsDir => Environment.GetEnvironmentVariable("CRISP_MODELS_DIR")
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".crisp", "models");
    public string ModelPath => Path.Combine(ModelsDir, _spec.FileName);
    private string PartPath => ModelPath + ".part";

    /// Absolute path the engine should load, or null until verified.
    public string? ReadyModelPath => IsReady ? ModelPath : null;
    public string SizeText => _spec.ApproxSizeText;

    /// Recompute state from disk. Hashes a present file to confirm it's intact;
    /// a missing/partial/corrupt file resolves to Absent.
    public async Task RefreshAsync()
    {
        if (IsBusy && State != ModelState.Checking) return; // a download owns the state
        State = ModelState.Checking;
        State = File.Exists(ModelPath) && await VerifyAsync(ModelPath, CancellationToken.None)
            ? ModelState.Ready
            : ModelState.Absent;
    }

    public void Cancel() => _cts?.Cancel(); // keeps the .part for resume

    /// Download (resumable) → verify → atomic publish.
    public async Task DownloadAsync()
    {
        if (State == ModelState.Downloading) return;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        Directory.CreateDirectory(ModelsDir);

        try
        {
            State = ModelState.Downloading;
            Progress = 0;
            await StreamToPartAsync(ct);

            State = ModelState.Verifying;
            if (!await VerifyAsync(PartPath, ct))
            {
                File.Delete(PartPath); // corrupt — don't resume onto bad bytes
                Fail("Downloaded file failed verification. Please try again.");
                return;
            }

            File.Move(PartPath, ModelPath, overwrite: true); // atomic publish
            State = ModelState.Ready;
        }
        catch (OperationCanceledException) { State = ModelState.Absent; } // .part kept for resume
        catch (Exception ex) { Fail(ex is HttpRequestException ? "Download failed. Check your connection and try again." : ex.Message); }
        finally { _cts = null; }
    }

    private async Task StreamToPartAsync(CancellationToken ct)
    {
        long have = File.Exists(PartPath) ? new FileInfo(PartPath).Length : 0;

        using var req = new HttpRequestMessage(HttpMethod.Get, _spec.Url);
        if (have > 0) req.Headers.Range = new RangeHeaderValue(have, null);

        using var resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
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
        int read;
        var lastReport = 0L;
        while ((read = await net.ReadAsync(buffer, ct)) > 0)
        {
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

    private void Fail(string message) { Message = message; State = ModelState.Failed; }
}
