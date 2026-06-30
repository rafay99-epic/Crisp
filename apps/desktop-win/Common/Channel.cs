using System;
using System.IO;

namespace Crisp;

/// Which build channel this app is — the Windows port of CrispCore/Common/Channel.swift.
/// Identity comes from the CRISP_CHANNEL env var (the packaging step bakes it in);
/// defaults to stable for a plain `dotnet run`. The three channels install side by side
/// because their data homes differ (~/.crisp, ~/.crisp-nightly, ~/.crisp-dev):
///   • stable  — daily driver, updates from the latest GitHub release.
///   • nightly — integration channel, updates from the newest pre-release.
///   • dev     — whatever you built locally: separate data, distinct name, no updater.
///
/// This is also the single place the data-home env overrides
/// (CRISP_DATA_DIR / CRISP_CONFIG_DIR / CRISP_MODELS_DIR) are resolved, so every
/// service lands in the same per-channel tree.
public enum Channel
{
    Stable,
    Nightly,
    Dev,
}

public static class Channels
{
    public static Channel Current { get; } = Resolve();

    private static Channel Resolve()
    {
        var raw = Environment.GetEnvironmentVariable("CRISP_CHANNEL")?.Trim().ToLowerInvariant();
        return raw switch
        {
            "nightly" => Channel.Nightly,
            "dev" => Channel.Dev,
            _ => Channel.Stable,
        };
    }

    /// Human-facing app name — also the window title.
    public static string DisplayName(this Channel c) => c switch
    {
        Channel.Nightly => "Crisp Nightly",
        Channel.Dev => "Crisp Dev",
        _ => "Crisp",
    };

    /// Short corner tag; null on stable.
    public static string? Badge(this Channel c) => c switch
    {
        Channel.Nightly => "NIGHTLY",
        Channel.Dev => "DEV",
        _ => null,
    };

    /// Hidden data-home directory name under the user profile.
    public static string DataDirSuffix(this Channel c) => c switch
    {
        Channel.Nightly => ".crisp-nightly",
        Channel.Dev => ".crisp-dev",
        _ => ".crisp",
    };

    /// The published installer asset for this channel; null for dev (never published).
    public static string? AssetName(this Channel c) => c switch
    {
        Channel.Nightly => "Crisp-Nightly-Setup.exe",
        Channel.Dev => null,
        _ => "Crisp-Setup.exe",
    };

    public static bool IsPrerelease(this Channel c) => c == Channel.Nightly;

    /// Dev has no updater; stable + nightly update from their feeds.
    public static bool UpdatesEnabled(this Channel c) => c != Channel.Dev;

    // --- Per-channel data home (env overrides win, then ~/.crisp{suffix}) ---

    private static string Home =>
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// `~/.crisp{suffix}` unless CRISP_DATA_DIR overrides (test/dev harnesses set it).
    public static string DataDirectory
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("CRISP_DATA_DIR");
            return !string.IsNullOrWhiteSpace(dir) ? dir : Path.Combine(Home, Current.DataDirSuffix());
        }
    }

    public static string ConfigDirectory
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("CRISP_CONFIG_DIR");
            return !string.IsNullOrWhiteSpace(dir) ? dir : Path.Combine(DataDirectory, "config");
        }
    }

    public static string ModelsDirectory
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("CRISP_MODELS_DIR");
            return !string.IsNullOrWhiteSpace(dir) ? dir : Path.Combine(DataDirectory, "models");
        }
    }

    public static string LogsDirectory => Path.Combine(DataDirectory, "logs");

    public static string OriginalsDirectory => Path.Combine(DataDirectory, "Originals");
}
