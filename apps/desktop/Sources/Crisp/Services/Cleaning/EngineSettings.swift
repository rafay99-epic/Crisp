import Foundation
import CrispCore

/// The live, editable settings, persisted to a JSON file in the channel's data
/// home (`~/.crisp*/config/settings.json`) — outside the app bundle, so an update
/// never disturbs them. Loads on launch (defaults fill any missing keys); every
/// change is written back atomically. The on-disk shape (`EngineConfig`) and the
/// read/write (`EngineConfigStore`) live in CrispCore so the background agent and
/// App Intents share the exact same file and format.
@MainActor
@Observable
final class EngineSettings {
    // Cutting (used by the "Custom" strength)
    var pauseThreshold: Double { didSet { save() } }
    var silenceFloorDB: Double { didSet { save() } }
    var breathingRoom: Double { didSet { save() } }
    var minKeep: Double { didSet { save() } }
    // Encoding (applied to every clean)
    var videoCodec: String { didSet { save() } }
    var hardwareEncoding: Bool { didSet { save() } }
    var videoQuality: String { didSet { save() } }
    var audioCodec: String { didSet { save() } }
    var audioBitrateKbps: Int { didSet { save() } }
    var outputContainer: String { didSet { save() } }
    // Backup (applied to every clean)
    var backupOriginal: Bool { didSet { save() } }
    // Watch folder (drives the background agent)
    var watchEnabled: Bool { didSet { save() } }
    var watchFolderPath: String { didSet { save() } }
    var watchRemoveFillers: Bool { didSet { save() } }

    /// Whether the user arrived with a real saved configuration — a `settings.json`
    /// that differs from the defaults. Captured once at launch (so it stays stable
    /// while onboarding edits settings). Onboarding uses it to show a "we detected
    /// your settings" note for returning/updating users, and to stay silent for
    /// brand-new users or anyone still on the defaults.
    let hasExistingConfig: Bool

    /// A plain-value snapshot of the live settings.
    var config: EngineConfig {
        EngineConfig(version: EngineConfig.defaults.version,
                     pauseThreshold: pauseThreshold, silenceFloorDB: silenceFloorDB,
                     breathingRoom: breathingRoom, minKeep: minKeep,
                     videoCodec: videoCodec, hardwareEncoding: hardwareEncoding,
                     videoQuality: videoQuality, audioCodec: audioCodec,
                     audioBitrateKbps: audioBitrateKbps, outputContainer: outputContainer,
                     backupOriginal: backupOriginal,
                     watchEnabled: watchEnabled, watchFolderPath: watchFolderPath,
                     watchRemoveFillers: watchRemoveFillers)
    }

    init() {
        let url = EngineConfigStore.fileURL
        let existed = FileManager.default.fileExists(atPath: url.path)
        let cfg = EngineConfigStore.load()
        // "Has a real config" = the file existed at launch and holds non-default
        // values. A freshly materialized defaults file (or no file) doesn't count.
        hasExistingConfig = existed && cfg != .defaults
        // Property observers don't fire for assignments in init, so no save here.
        pauseThreshold = cfg.pauseThreshold
        silenceFloorDB = cfg.silenceFloorDB
        breathingRoom = cfg.breathingRoom
        minKeep = cfg.minKeep
        videoCodec = cfg.videoCodec
        hardwareEncoding = cfg.hardwareEncoding
        videoQuality = cfg.videoQuality
        audioCodec = cfg.audioCodec
        audioBitrateKbps = cfg.audioBitrateKbps
        outputContainer = cfg.outputContainer
        backupOriginal = cfg.backupOriginal
        watchEnabled = cfg.watchEnabled
        watchFolderPath = cfg.watchFolderPath
        watchRemoveFillers = cfg.watchRemoveFillers
        if !existed { EngineConfigStore.save(config) }  // materialize the file on first launch
    }

    /// Resets the cutting + encoding + backup knobs to defaults. The watch-folder
    /// settings are intentionally left alone — they have their own section and
    /// resetting them would silently disable the user's watcher.
    func restoreDefaults() {
        let d = EngineConfig.defaults
        pauseThreshold = d.pauseThreshold
        silenceFloorDB = d.silenceFloorDB
        breathingRoom = d.breathingRoom
        minKeep = d.minKeep
        videoCodec = d.videoCodec
        hardwareEncoding = d.hardwareEncoding
        videoQuality = d.videoQuality
        audioCodec = d.audioCodec
        audioBitrateKbps = d.audioBitrateKbps
        outputContainer = d.outputContainer
        backupOriginal = d.backupOriginal
    }

    private func save() { EngineConfigStore.save(config) }
}
