using System;
using System.Globalization;

namespace Crisp;

/// Small shared formatters (port of macOS Common/Formatting).
public static class Formatting
{
    /// "3:21" for a minute or more, else "4.2s" — for time-saved labels.
    public static string Duration(double seconds)
    {
        if (seconds <= 0) return "0s";
        // Round before deciding the format so 59.6s reads "1:00", not "59.6s".
        if (Math.Round(seconds) < 60) return seconds.ToString("0.#", CultureInfo.InvariantCulture) + "s";
        var t = TimeSpan.FromSeconds(Math.Round(seconds));
        return t.TotalHours >= 1
            ? $"{(int)t.TotalHours}:{t.Minutes:00}:{t.Seconds:00}" // TotalHours preserves >24h
            : $"{t.Minutes}:{t.Seconds:00}";
    }
}
