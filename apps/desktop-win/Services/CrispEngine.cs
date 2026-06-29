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
            WorkingDirectory = engineDir,
        };
        psi.ArgumentList.Add(ScriptPath);
        psi.ArgumentList.Add(videoPath);
        foreach (var a in extraArgs) psi.ArgumentList.Add(a);
        psi.ArgumentList.Add("--ndjson");

        // Point the engine at the bundled tools when present (shipped build); otherwise it
        // falls back to PATH so a dev's Homebrew install / the bare CLI still work.
        SetIfExists(psi, "CRISP_FFMPEG", Path.Combine(binDir, "ffmpeg" + exe));
        SetIfExists(psi, "CRISP_FFPROBE", Path.Combine(binDir, "ffprobe" + exe));
        SetIfExists(psi, "CRISP_WHISPER", Path.Combine(binDir, "whisper-cli" + exe));
        // Tell the engine where to log (same per-day file convention as the app).
        var logDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".crisp", "logs");
        try { Directory.CreateDirectory(logDir); psi.Environment["CRISP_LOG_DIR"] = logDir; } catch { /* best effort */ }

        using var proc = new Process { StartInfo = psi };
        proc.Start();

        // Drain stderr with a single reader (engine logs ffmpeg failures / tracebacks here).
        // ponytail: stdout=ReadLineAsync + stderr=ReadToEndAsync is the standard non-deadlocking
        // pair — never two line-readers on one stream (the macOS stderr-contention bug).
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

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
            throw;
        }

        // Only surface raw stderr when the engine didn't already emit a clean error event,
        // so a friendly NDJSON message isn't clobbered by a Python traceback. Cap the
        // surfaced text — full stderr is already on disk via CRISP_LOG_DIR.
        var stderr = await stderrTask;
        if (proc.ExitCode != 0 && !sawError && !string.IsNullOrWhiteSpace(stderr))
        {
            var trimmed = stderr.Trim();
            if (trimmed.Length > 2000) trimmed = "…" + trimmed[^2000..];
            progress.Report(new EngineEvent { Event = "error", Message = trimmed, Raw = stderr });
        }
        return proc.ExitCode;
    }

    private string ResolvePython(string binDir, string exe)
    {
        if (!string.IsNullOrEmpty(PythonPath)) return PythonPath!;
        var env = Environment.GetEnvironmentVariable("CRISP_PYTHON");
        if (!string.IsNullOrEmpty(env)) return env;
        var bundled = Path.Combine(binDir, "python" + exe);
        if (File.Exists(bundled)) return bundled;
        return OperatingSystem.IsWindows() ? "python" : "python3";
    }

    private static void SetIfExists(ProcessStartInfo psi, string key, string path)
    {
        if (File.Exists(path)) psi.Environment[key] = path;
    }
}
