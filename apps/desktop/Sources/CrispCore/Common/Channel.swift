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
public enum Channel: String {
    case stable
    case nightly
    case dev

    public static let current: Channel = {
        let raw = Bundle.main.infoDictionary?["CrispChannel"] as? String
        return raw.flatMap(Channel.init(rawValue:)) ?? .stable
    }()

    /// Human-facing app name — matches `CFBundleName` and the `.app` on disk.
    /// `Updater.bundleInImage` derives the in-DMG bundle name from this, so it
    /// must stay exactly what `build.sh` writes.
    public var displayName: String {
        switch self {
        case .stable:  return "Crisp"
        case .nightly: return "Crisp Nightly"
        case .dev:     return "Crisp Dev"
        }
    }

    /// Short corner-of-the-UI tag, nil on Stable.
    public var badge: String? {
        switch self {
        case .stable:  return nil
        case .nightly: return "NIGHTLY"
        case .dev:     return "DEV"
        }
    }

    /// Suffix appended to `com.syntaxlabtechnology.crisp` to form the bundle id.
    public var bundleSuffix: String {
        switch self {
        case .stable:  return ""
        case .nightly: return ".nightly"
        case .dev:     return ".dev"
        }
    }

    /// The published DMG asset name for this channel, and the `.app` inside it.
    /// nil for Dev, which never publishes a release.
    public var assetName: String? {
        switch self {
        case .stable:  return "Crisp.dmg"
        case .nightly: return "Crisp-Nightly.dmg"
        case .dev:     return nil
        }
    }

    /// Hidden data-home directory name under `~/`.
    public var dataDirSuffix: String {
        switch self {
        case .stable:  return ".crisp"
        case .nightly: return ".crisp-nightly"
        case .dev:     return ".crisp-dev"
        }
    }

    /// Per-channel data home (`~/.crisp`, `~/.crisp-nightly`, …). Channels stay
    /// isolated here — e.g. each keeps its own downloaded speech model — so they
    /// can run side by side without stepping on each other.
    public var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(dataDirSuffix, isDirectory: true)
    }

    /// Where the daily log files live (`~/.crisp*/logs/`). Both the Swift app and
    /// the Python engine write here, so one timeline covers a whole clean.
    public var logsDirectory: URL {
        dataDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// Stable tracks the latest full release; Nightly tracks the newest
    /// pre-release. (Dev tracks nothing — see `updatesEnabled`.)
    public var isPrerelease: Bool { self == .nightly }

    /// Dev has no updater at all. Stable and Nightly both update from their feeds.
    public var updatesEnabled: Bool { self != .dev }

    /// Which branch of the Hugging Face model repo this channel pulls **model**
    /// updates from — the model analogue of the app's release channels. Stable
    /// rides the promoted `main` manifest; Nightly and Dev ride the `nightly`
    /// staging manifest, so they see (and test) a new model before it's promoted to
    /// Stable. A model published to nightly is fetched by its global `v0.0.N` tag,
    /// so only the manifest the channel polls differs — not the model bytes.
    public var modelChannelRef: String { self == .stable ? "main" : "nightly" }

    /// Dev gets the model-history + local-sideload affordances in Settings — the
    /// "see / A-B old models" and "test a freshly trained model before publishing"
    /// tools. Hidden on Stable/Nightly, which only pick the recommended model.
    public var showsModelDevTools: Bool { self == .dev }

    /// Nightly orders builds by the monotonic CI build number (its pre-release
    /// tag is reused, so the version string can't order them). Stable orders by
    /// the numeric version.
    public var ordersByBuildNumber: Bool { self == .nightly }

    /// Extra build detail (branch@sha), baked in for Nightly and Dev so the
    /// About screen can show exactly what's running. nil on Stable.
    public static var buildInfo: String? {
        Bundle.main.infoDictionary?["CrispBuildInfo"] as? String
    }

    /// Master kill-switch for the Polar.sh licensing / paywall system. **Defaults to
    /// `false`** so the feature ships *dark*: with it off, the gate (`LicenseGate`)
    /// always allows cleaning, the onboarding license step is skipped, and the app
    /// behaves exactly as it did before licensing existed.
    ///
    /// Baked per channel via the `CrispLicensingEnabled` Info.plist key (set by
    /// `build.sh`). On **Dev and Nightly only**, a runtime override lets it be flipped
    /// without a rebuild for dogfooding — the `CRISP_LICENSING` env var (`1`/`0`) or a
    /// `CrispLicensingOverride` UserDefaults bool. Stable honours only the baked value,
    /// so the gate can't be switched off by an end user.
    public static var licensingEnabled: Bool {
        if current != .stable {
            if let env = ProcessInfo.processInfo.environment["CRISP_LICENSING"] {
                return truthy(env)
            }
            if let override = UserDefaults.standard.object(forKey: "CrispLicensingOverride") as? Bool {
                return override
            }
        }
        guard let raw = Bundle.main.infoDictionary?["CrispLicensingEnabled"] as? String else { return false }
        return truthy(raw)
    }

    private static func truthy(_ value: String) -> Bool {
        ["1", "true", "yes"].contains(value.lowercased())
    }
}
