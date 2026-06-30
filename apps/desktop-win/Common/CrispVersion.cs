using System;

namespace Crisp;

/// The running app's version. CI stamps CRISP_VERSION (0.<commit count on main>, like
/// the macOS build); dev defaults low so any published release reads as newer.
public static class CrispVersion
{
    public static string Current
    {
        get
        {
            var v = Environment.GetEnvironmentVariable("CRISP_VERSION");
            return string.IsNullOrWhiteSpace(v) ? "0.0" : v;
        }
    }

    /// Monotonic CI build number baked for the nightly channel (the Windows analogue of
    /// macOS CrispBuildNumber). Nightly reuses a rolling tag, so its updater orders by
    /// this, not the version string. 0 when unset (e.g. a dev build) → never auto-updates.
    public static int BuildNumber =>
        int.TryParse(Environment.GetEnvironmentVariable("CRISP_BUILD_NUMBER"), out var n) ? n : 0;
}
