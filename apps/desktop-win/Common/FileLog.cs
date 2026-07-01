using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace Crisp;

/// App-side file logging — the Windows port of the macOS FileLog/CrispLog system.
/// Writes to the same per-channel, per-day file the Python engine appends to
/// (~/.crisp*/logs/<yyyy-MM-dd>.log, told to the engine via CRISP_LOG_DIR), with the
/// same line format, so the app and the engine read as one merged timeline:
///
///   2026-07-02 14:03:07.123  INFO    [app:model#1234]  downloading base.en …
///
/// Writes are lock-serialized and append-only; a logging failure is swallowed —
/// logging must never break the app.
public static class FileLog
{
    private static readonly object Gate = new();
    private static readonly int Pid = Environment.ProcessId;

    public static void Debug(string category, string message) => Write("DEBUG", category, message);
    public static void Info(string category, string message) => Write("INFO", category, message);
    public static void Notice(string category, string message) => Write("NOTICE", category, message);
    public static void Error(string category, string message) => Write("ERROR", category, message);

    private static void Write(string level, string category, string message)
    {
        try
        {
            var dir = Channels.LogsDirectory;
            Directory.CreateDirectory(dir);
            var now = DateTime.Now;
            var stamp = now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture);
            var prefix = $"{stamp}  {level,-6}  [app:{category}#{Pid}]  ";
            // One prefixed physical line per record line (multi-line messages stay
            // greppable), appended as a single write — same shape as the engine logger.
            var sb = new StringBuilder();
            foreach (var line in message.Split('\n'))
                sb.Append(prefix).Append(line.TrimEnd('\r')).Append('\n');
            var path = Path.Combine(dir, now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".log");
            lock (Gate) File.AppendAllText(path, sb.ToString());
        }
        catch
        {
            // best effort — never let logging surface as an app failure
        }
    }

    /// Delete log files older than 30 days (same housekeeping the macOS app does on
    /// launch). Best effort.
    public static void PruneOldLogs()
    {
        try
        {
            var dir = Channels.LogsDirectory;
            if (!Directory.Exists(dir)) return;
            var cutoff = DateTime.Now.AddDays(-30);
            foreach (var f in Directory.EnumerateFiles(dir, "*.log"))
                if (File.GetLastWriteTime(f) < cutoff)
                    try { File.Delete(f); } catch { /* best effort */ }
        }
        catch { /* best effort */ }
    }
}
