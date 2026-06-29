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
/// same env-var contract (CRISP_FFMPEG/FFPROBE/WHISPER), same NDJSON stream.
public sealed class CrispEngine
{
    public string PythonPath { get; init; } = "python3";
    public required string ScriptPath { get; init; } // path to clean_video.py

    /// Runs a clean, reporting each NDJSON event. `progress` should be created on
    /// the UI thread (Progress<T> marshals callbacks back to it).
    public async Task<int> RunAsync(
        string videoPath, IReadOnlyList<string> extraArgs,
        IProgress<EngineEvent> progress, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = PythonPath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(ScriptPath) ?? ".",
        };
        psi.ArgumentList.Add(ScriptPath);
        psi.ArgumentList.Add(videoPath);
        foreach (var a in extraArgs) psi.ArgumentList.Add(a);
        psi.ArgumentList.Add("--ndjson");

        using var proc = new Process { StartInfo = psi };
        proc.Start();

        // Drain stderr with a single reader (engine logs ffmpeg failures / tracebacks here).
        // ponytail: stdout=ReadLineAsync + stderr=ReadToEndAsync is the standard non-deadlocking
        // pair — never two line-readers on one stream (the macOS stderr-contention bug).
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

        try
        {
            string? line;
            while ((line = await proc.StandardOutput.ReadLineAsync(ct)) is not null)
            {
                var ev = EngineEvent.Parse(line);
                if (ev is not null) progress.Report(ev);
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

        var stderr = await stderrTask;
        if (proc.ExitCode != 0 && !string.IsNullOrWhiteSpace(stderr))
            progress.Report(new EngineEvent { Event = "error", Message = stderr.Trim(), Raw = stderr });
        return proc.ExitCode;
    }
}
