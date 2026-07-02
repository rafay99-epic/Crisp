using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Crisp.Models;

namespace Crisp.Services;

/// Drives the shared Python engine as a subprocess and streams its NDJSON.
/// This is the Windows counterpart of macOS's CrispCore/Engine/CleanRunner.swift —
/// same env-var contract (CRISP_FFMPEG/FFPROBE/WHISPER + CRISP_LOG_DIR), same NDJSON stream.
public sealed class CrispEngine
{
    /// Explicit python; null → resolve (CRISP_PYTHON, bundled, then PATH per-platform).
    public string? PythonPath { get; init; }
    public required string ScriptPath { get; init; } // path to clean_video.py

    /// Runs a clean, reporting each NDJSON event. `progress` should be created on
    /// the UI thread (Progress<T> marshals callbacks back to it).
    public async Task<int> RunAsync(
        string videoPath, IReadOnlyList<string> extraArgs,
        IProgress<EngineEvent> progress, CancellationToken ct)
    {
        var engineDir = Path.GetDirectoryName(ScriptPath) ?? ".";
        var binDir = Path.Combine(engineDir, "bin");
        var exe = OperatingSystem.IsWindows() ? ".exe" : "";

        var psi = new ProcessStartInfo
        {
            FileName = ResolvePython(binDir, exe),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            // No console window for python — and since the ffmpeg/whisper children it
            // spawns inherit its (hidden) console, none of them flash a cmd window either.
            CreateNoWindow = true,
            WorkingDirectory = engineDir,
        };
        psi.ArgumentList.Add(ScriptPath);
        if (videoPath.Length > 0) psi.ArgumentList.Add(videoPath); // "" = video-less mode (--probe-hardware)
        foreach (var a in extraArgs) psi.ArgumentList.Add(a);
        psi.ArgumentList.Add("--ndjson");

        // Point the engine at the bundled tools when present (shipped build); otherwise it
        // falls back to PATH so a dev's Homebrew install / the bare CLI still work.
        SetIfExists(psi, "CRISP_FFMPEG", Path.Combine(binDir, "ffmpeg" + exe));
        SetIfExists(psi, "CRISP_FFPROBE", Path.Combine(binDir, "ffprobe" + exe));
        SetIfExists(psi, "CRISP_WHISPER", Path.Combine(binDir, "whisper-cli" + exe));
        SetIfExists(psi, "CRISP_FILLER", Path.Combine(binDir, "crisp-filler" + exe));
        // Tell the engine where to log (same per-day file convention as the app).
        var logDir = Channels.LogsDirectory;
        try { Directory.CreateDirectory(logDir); psi.Environment["CRISP_LOG_DIR"] = logDir; } catch { /* best effort */ }

        using var proc = new Process { StartInfo = psi };
        proc.Start();

        // Drain stderr with a single reader, keeping only the tail so a verbose tool can't
        // balloon memory (full text is on disk via CRISP_LOG_DIR). ponytail: stdout=ReadLine +
        // stderr=single-reader is the standard non-deadlocking pair (macOS stderr-contention bug).
        var stderrTask = DrainTailAsync(proc.StandardError, 8000, ct);

        var sawError = false;
        try
        {
            string? line;
            while ((line = await proc.StandardOutput.ReadLineAsync(ct)) is not null)
            {
                var ev = EngineEvent.Parse(line);
                if (ev is null) continue;
                if (ev.Event == "error") sawError = true; // the engine's own structured error
                progress.Report(ev);
            }
            await proc.WaitForExitAsync(ct);
        }
        catch (OperationCanceledException)
        {
            // Kill the whole tree so child ffmpeg/whisper die too — this is the
            // cross-platform replacement for the Unix os.killpg path in clean_video.py.
            if (!proc.HasExited) proc.Kill(entireProcessTree: true);
            try { await stderrTask; } catch { /* observe the drain task so its OCE isn't unhandled */ }
            throw;
        }

        // Only surface raw stderr when the engine didn't already emit a clean error event,
        // so a friendly NDJSON message isn't clobbered by a Python traceback. Cap the
        // surfaced text — full stderr is already on disk via CRISP_LOG_DIR.
        var stderr = await stderrTask;
        if (proc.ExitCode != 0 && !sawError && !string.IsNullOrWhiteSpace(stderr))
            progress.Report(new EngineEvent { Event = "error", Message = stderr.Trim(), Raw = stderr });
        return proc.ExitCode;
    }

    /// Fast pre-flight analysis (no transcription/render) — returns the raw "analysis"
    /// NDJSON ({duration, silences}) for a savings estimate, or null if it failed.
    public async Task<string?> AnalyzeAsync(string videoPath, CancellationToken ct)
    {
        string? raw = null;
        var capture = new ActionProgress(ev => { if (ev.Event == "analysis") raw = ev.Raw; });
        int code;
        try { code = await RunAsync(videoPath, new[] { "--analyze" }, capture, ct); }
        catch (OperationCanceledException) { throw; }
        catch { return null; }
        return code == 0 ? raw : null; // a captured payload from a failed run is not trustworthy
    }

    /// Ask the engine which GPUs exist and which hardware encoder each codec would
    /// actually use (functionally verified engine-side) — null if the probe failed.
    /// One implementation for the answer (the engine's); the app only displays it.
    public async Task<HardwareInfo?> ProbeHardwareAsync(CancellationToken ct)
    {
        string? raw = null;
        var capture = new ActionProgress(ev => { if (ev.Event == "hardware") raw = ev.Raw; });
        int code;
        try { code = await RunAsync("", new[] { "--probe-hardware" }, capture, ct); }
        catch (OperationCanceledException) { throw; }
        catch { return null; }
        return code == 0 && raw is not null ? HardwareInfo.Parse(raw) : null;
    }

    private sealed class ActionProgress : IProgress<EngineEvent>
    {
        private readonly Action<EngineEvent> _on;
        public ActionProgress(Action<EngineEvent> on) => _on = on;
        public void Report(EngineEvent value) => _on(value); // synchronous capture
    }

    private string ResolvePython(string binDir, string exe)
    {
        if (!string.IsNullOrEmpty(PythonPath)) return PythonPath!;
        var env = Environment.GetEnvironmentVariable("CRISP_PYTHON");
        if (!string.IsNullOrEmpty(env)) return env;
        // The vendored python-build-standalone runtime lands in a `python/` subdir with a
        // platform-specific layout (Windows: python.exe at the root; Unix: bin/python3).
        var candidates = OperatingSystem.IsWindows()
            ? new[] { Path.Combine(binDir, "python.exe"), Path.Combine(binDir, "python", "python.exe") }
            : new[] { Path.Combine(binDir, "python3"), Path.Combine(binDir, "python", "bin", "python3") };
        foreach (var c in candidates)
            if (File.Exists(c)) return c;
        return OperatingSystem.IsWindows() ? "python" : "python3";
    }

    private static void SetIfExists(ProcessStartInfo psi, string key, string path)
    {
        if (File.Exists(path)) psi.Environment[key] = path;
    }

    /// Read a stream to EOF keeping only the last `cap` chars — bounded memory for a
    /// potentially-verbose stderr.
    private static async Task<string> DrainTailAsync(StreamReader reader, int cap, CancellationToken ct)
    {
        var buf = new char[8192];
        var sb = new System.Text.StringBuilder();
        int n;
        while ((n = await reader.ReadAsync(buf.AsMemory(), ct)) > 0)
        {
            sb.Append(buf, 0, n);
            if (sb.Length > cap * 2) sb.Remove(0, sb.Length - cap);
        }
        return sb.Length > cap ? sb.ToString(sb.Length - cap, cap) : sb.ToString();
    }
}
