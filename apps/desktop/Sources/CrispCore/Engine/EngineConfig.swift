import Foundation

/// On-disk shape of the user's custom cutting + encoding settings.
///
/// Forward-compatible by design: every field decodes with `decodeIfPresent` and
/// falls back to a default, so a file written by an older version (missing a key
/// a newer version added) still loads — the user keeps every value they set, and
/// new keys simply appear at their default. `version` is reserved for any future
/// migration. Mirrors the engine defaults in `crisp/config.py`.
public struct EngineConfig: Codable, Equatable, Sendable {
    public var version: Int
    // Cutting
    public var pauseThreshold: Double
    public var silenceFloorDB: Double
    public var breathingRoom: Double
    public var minKeep: Double
    // Encoding
    public var videoCodec: String        // "h264" | "hevc"
    public var hardwareEncoding: Bool    // Apple VideoToolbox
    public var videoQuality: String      // "maximum" | "high" | "balanced" | "smaller"
    public var audioCodec: String        // "aac" | "opus"
    public var audioBitrateKbps: Int
    public var outputContainer: String   // "auto" | "mp4" | "mkv" | "mov" | "m4v" | "ts" | "webm"
    // Output location — folder to write the cleaned file into ("" ⇒ beside the
    // source, the default). Lets users send cleaned files to e.g. a NAS.
    public var outputDirectory: String
    // Also write separate video-only + audio-only files beside the cleaned output,
    // for editing the picture and the voiceover apart.
    public var splitTracks: Bool
    public var splitAudioFormat: String  // "match" (copy) | "wav" (uncompressed)
    // Backup
    public var backupOriginal: Bool      // copy the source aside before cutting
    // Watch folder — auto-clean recordings dropped into a chosen folder. Driven by
    // the background agent (CrispWatcher); empty/false by default so it's opt-in.
    public var watchEnabled: Bool        // background watcher active
    public var watchFolderPath: String   // folder to watch ("" ⇒ none chosen)
    public var watchRemoveFillers: Bool  // strip fillers on auto-clean (needs model)
    // Presets — named, reusable clean recipes a queue row can pick instead of the
    // global recipe. `defaultPresetID` (a Preset.id UUID string, "" ⇒ none) is the
    // recipe newly added files use until the user picks another.
    public var presets: [Preset]
    public var defaultPresetID: String
    // Parallelism — how many videos to clean at once. "auto" lets the resource
    // governor pick a safe number; "manual" uses `manualConcurrency` (clamped to the
    // machine's ceiling); "ultra" pushes to the ceiling with a free-resource
    // preflight. `perJobMemoryBudgetMB` is the governor's per-clean RAM estimate.
    public var concurrencyMode: String   // "auto" | "manual" | "ultra"
    public var manualConcurrency: Int
    public var perJobMemoryBudgetMB: Int
    // Speech model — which catalog model (ModelCatalog) the engine loads for
    // filler detection. App-side state: it picks the `--model <path>` the engine
    // is run with; the Python engine never reads it.
    public var selectedModelID: String

    public static let defaults = EngineConfig(
        version: 3,
        pauseThreshold: 0.35, silenceFloorDB: -30, breathingRoom: 0.10, minKeep: 0.05,
        videoCodec: "hevc", hardwareEncoding: true, videoQuality: "high",
        audioCodec: "aac", audioBitrateKbps: 192, outputContainer: "auto", outputDirectory: "",
        splitTracks: false, splitAudioFormat: "match",
        backupOriginal: true,
        watchEnabled: false, watchFolderPath: "", watchRemoveFillers: true,
        presets: [], defaultPresetID: "",
        concurrencyMode: "auto", manualConcurrency: 2, perJobMemoryBudgetMB: 2048,
        selectedModelID: ModelCatalog.defaultID)

    enum CodingKeys: String, CodingKey {
        case version, pauseThreshold, silenceFloorDB, breathingRoom, minKeep
        case videoCodec, hardwareEncoding, videoQuality, audioCodec, audioBitrateKbps
        case outputContainer, outputDirectory, splitTracks, splitAudioFormat, backupOriginal
        case watchEnabled, watchFolderPath, watchRemoveFillers
        case presets, defaultPresetID
        case concurrencyMode, manualConcurrency, perJobMemoryBudgetMB
        case selectedModelID
    }

    public init(version: Int, pauseThreshold: Double, silenceFloorDB: Double, breathingRoom: Double,
                minKeep: Double, videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
                audioCodec: String, audioBitrateKbps: Int, outputContainer: String, outputDirectory: String,
                splitTracks: Bool, splitAudioFormat: String,
                backupOriginal: Bool,
                watchEnabled: Bool, watchFolderPath: String, watchRemoveFillers: Bool,
                presets: [Preset], defaultPresetID: String,
                concurrencyMode: String, manualConcurrency: Int, perJobMemoryBudgetMB: Int,
                selectedModelID: String = ModelCatalog.defaultID) {
        self.version = version
        self.pauseThreshold = pauseThreshold
        self.silenceFloorDB = silenceFloorDB
        self.breathingRoom = breathingRoom
        self.minKeep = minKeep
        self.videoCodec = videoCodec
        self.hardwareEncoding = hardwareEncoding
        self.videoQuality = videoQuality
        self.audioCodec = audioCodec
        self.audioBitrateKbps = audioBitrateKbps
        self.outputContainer = outputContainer
        self.outputDirectory = outputDirectory
        self.splitTracks = splitTracks
        self.splitAudioFormat = splitAudioFormat
        self.backupOriginal = backupOriginal
        self.watchEnabled = watchEnabled
        self.watchFolderPath = watchFolderPath
        self.watchRemoveFillers = watchRemoveFillers
        self.presets = presets
        self.defaultPresetID = defaultPresetID
        self.concurrencyMode = concurrencyMode
        self.manualConcurrency = manualConcurrency
        self.perJobMemoryBudgetMB = perJobMemoryBudgetMB
        self.selectedModelID = selectedModelID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineConfig.defaults
        version            = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        pauseThreshold     = try c.decodeIfPresent(Double.self, forKey: .pauseThreshold) ?? d.pauseThreshold
        silenceFloorDB     = try c.decodeIfPresent(Double.self, forKey: .silenceFloorDB) ?? d.silenceFloorDB
        breathingRoom      = try c.decodeIfPresent(Double.self, forKey: .breathingRoom) ?? d.breathingRoom
        minKeep            = try c.decodeIfPresent(Double.self, forKey: .minKeep) ?? d.minKeep
        videoCodec         = try c.decodeIfPresent(String.self, forKey: .videoCodec) ?? d.videoCodec
        hardwareEncoding   = try c.decodeIfPresent(Bool.self, forKey: .hardwareEncoding) ?? d.hardwareEncoding
        videoQuality       = try c.decodeIfPresent(String.self, forKey: .videoQuality) ?? d.videoQuality
        audioCodec         = try c.decodeIfPresent(String.self, forKey: .audioCodec) ?? d.audioCodec
        audioBitrateKbps   = try c.decodeIfPresent(Int.self, forKey: .audioBitrateKbps) ?? d.audioBitrateKbps
        outputContainer    = try c.decodeIfPresent(String.self, forKey: .outputContainer) ?? d.outputContainer
        outputDirectory    = try c.decodeIfPresent(String.self, forKey: .outputDirectory) ?? d.outputDirectory
        splitTracks        = try c.decodeIfPresent(Bool.self, forKey: .splitTracks) ?? d.splitTracks
        splitAudioFormat   = try c.decodeIfPresent(String.self, forKey: .splitAudioFormat) ?? d.splitAudioFormat
        backupOriginal     = try c.decodeIfPresent(Bool.self, forKey: .backupOriginal) ?? d.backupOriginal
        watchEnabled       = try c.decodeIfPresent(Bool.self, forKey: .watchEnabled) ?? d.watchEnabled
        watchFolderPath    = try c.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? d.watchFolderPath
        watchRemoveFillers = try c.decodeIfPresent(Bool.self, forKey: .watchRemoveFillers) ?? d.watchRemoveFillers
        presets            = try c.decodeIfPresent([Preset].self, forKey: .presets) ?? d.presets
        defaultPresetID    = try c.decodeIfPresent(String.self, forKey: .defaultPresetID) ?? d.defaultPresetID
        concurrencyMode    = try c.decodeIfPresent(String.self, forKey: .concurrencyMode) ?? d.concurrencyMode
        manualConcurrency  = try c.decodeIfPresent(Int.self, forKey: .manualConcurrency) ?? d.manualConcurrency
        perJobMemoryBudgetMB = try c.decodeIfPresent(Int.self, forKey: .perJobMemoryBudgetMB) ?? d.perJobMemoryBudgetMB
        selectedModelID    = try c.decodeIfPresent(String.self, forKey: .selectedModelID) ?? d.selectedModelID
    }
}

/// Reads and writes `EngineConfig` to the channel's `settings.json`, headlessly —
/// no UI, no `@Observable`. The app's `EngineSettings` wraps this for live editing;
/// the background agent and App Intents load it directly. Single source of truth
/// for the file location so the app and helper never disagree.
public enum EngineConfigStore {
    /// `~/.crisp*/config/settings.json` — beside the downloaded model. In the
    /// user's home, not the bundle, so an update never disturbs it.
    public static var fileURL: URL {
        Channel.current.dataDirectory
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Load the saved config, or defaults if the file is missing/unreadable
    /// (missing keys are filled by `EngineConfig`'s forward-compatible decode).
    public static func load() -> EngineConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(EngineConfig.self, from: data) else {
            return .defaults
        }
        return cfg
    }

    /// Write atomically (pretty + sorted keys), creating the config dir as needed.
    public static func save(_ cfg: EngineConfig) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(cfg).write(to: fileURL, options: .atomic)
        } catch {
            AppInfo.logger("settings").error("Couldn't save settings: \(error.localizedDescription)")
        }
    }
}
