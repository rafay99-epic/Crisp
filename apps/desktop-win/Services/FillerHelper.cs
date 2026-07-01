using System;
using System.IO;

namespace Crisp.Services;

/// Whether the crisp-filler inference helper — the binary that actually runs the Wren
/// model (macOS ships a Swift/Core ML one, resolved from CRISP_FILLER) — exists on
/// this machine. Windows doesn't bundle one yet, so the Wren option surfaces as
/// "coming soon" until a crisp-filler.exe ships; the moment one is present (bundled
/// under engine/bin, or pointed at via CRISP_FILLER) the feature lights up with no
/// further code change.
public static class FillerHelper
{
    /// Resolve the helper binary: the CRISP_FILLER env override first (must exist on
    /// disk), then the bundled engine/bin/crisp-filler.exe beside the app.
    public static string? Resolve()
    {
        var env = Environment.GetEnvironmentVariable("CRISP_FILLER");
        if (!string.IsNullOrEmpty(env) && File.Exists(env)) return env;
        var bundled = Path.Combine(AppContext.BaseDirectory, "engine", "bin",
            OperatingSystem.IsWindows() ? "crisp-filler.exe" : "crisp-filler");
        return File.Exists(bundled) ? bundled : null;
    }

    public static bool Available => Resolve() is not null;
}
