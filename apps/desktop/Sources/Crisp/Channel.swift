import Foundation

/// Which build channel this app is. Baked into Info.plist (`CrispChannel`) by
/// `build.sh`; defaults to `.stable` when the key is absent (e.g. a plain
/// `swift run`). The three channels install side by side because their bundle
/// ids differ:
///   • Stable — your daily driver, auto-updates from the latest GitHub release.
///   • Nightly — the integration channel testers ride, auto-updates from the
///     newest pre-release (ordered by CI build number).
///   • Dev — whatever branch you built locally with `./dev.sh`: separate data,
///     distinct icon, and **no updater** (rebuild to change it).
enum Channel: String {
    case stable
    case nightly
    case dev

    static let current: Channel = {
        let raw = Bundle.main.infoDictionary?["CrispChannel"] as? String
        return raw.flatMap(Channel.init(rawValue:)) ?? .stable
    }()

    /// Human-facing app name — matches `CFBundleName` and the `.app` on disk.
    /// `Updater.bundleInImage` derives the in-DMG bundle name from this, so it
    /// must stay exactly what `build.sh` writes.
    var displayName: String {
        switch self {
        case .stable:  return "Crisp"
        case .nightly: return "Crisp Nightly"
        case .dev:     return "Crisp Dev"
        }
    }

    /// Short corner-of-the-UI tag, nil on Stable.
    var badge: String? {
        switch self {
        case .stable:  return nil
        case .nightly: return "NIGHTLY"
        case .dev:     return "DEV"
        }
    }

    /// Suffix appended to `com.syntaxlabtechnology.crisp` to form the bundle id.
    var bundleSuffix: String {
        switch self {
        case .stable:  return ""
        case .nightly: return ".nightly"
        case .dev:     return ".dev"
        }
    }

    /// The published DMG asset name for this channel, and the `.app` inside it.
    /// nil for Dev, which never publishes a release.
    var assetName: String? {
        switch self {
        case .stable:  return "Crisp.dmg"
        case .nightly: return "Crisp-Nightly.dmg"
        case .dev:     return nil
        }
    }

    /// Hidden data-home directory name under `~/`.
    var dataDirSuffix: String {
        switch self {
        case .stable:  return ".crisp"
        case .nightly: return ".crisp-nightly"
        case .dev:     return ".crisp-dev"
        }
    }

    /// Per-channel data home (`~/.crisp`, `~/.crisp-nightly`, …). Channels stay
    /// isolated here — e.g. each keeps its own downloaded speech model — so they
    /// can run side by side without stepping on each other.
    var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(dataDirSuffix, isDirectory: true)
    }

    /// Stable tracks the latest full release; Nightly tracks the newest
    /// pre-release. (Dev tracks nothing — see `updatesEnabled`.)
    var isPrerelease: Bool { self == .nightly }

    /// Dev has no updater at all. Stable and Nightly both update from their feeds.
    var updatesEnabled: Bool { self != .dev }

    /// Nightly orders builds by the monotonic CI build number (its pre-release
    /// tag is reused, so the version string can't order them). Stable orders by
    /// the numeric version.
    var ordersByBuildNumber: Bool { self == .nightly }

    /// Extra build detail (branch@sha), baked in for Nightly and Dev so the
    /// About screen can show exactly what's running. nil on Stable.
    static var buildInfo: String? {
        Bundle.main.infoDictionary?["CrispBuildInfo"] as? String
    }
}
