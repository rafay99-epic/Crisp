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
    // Pause handling (applied to every clean) — "remove" cuts pauses entirely;
    // "tighten" keeps a short natural gap so pacing stays natural
    var pauseMode: String { didSet { save() } }         // "remove" | "tighten"
    var tightPause: Double { didSet { save() } }        // seconds kept at each pause
    // Cut smoothing (applied to every clean) — soften the splice so cuts don't click
    var fadeMs: Double { didSet { save() } }
    var crossfadeMs: Double { didSet { save() } }
    var snapMs: Double { didSet { save() } }
    // Encoding (applied to every clean)
    var videoCodec: String { didSet { save() } }
    var hardwareEncoding: Bool { didSet { save() } }
    var videoQuality: String { didSet { save() } }
    var audioCodec: String { didSet { save() } }
    var audioBitrateKbps: Int { didSet { save() } }
    var outputContainer: String { didSet { save() } }
    var colorDepth: String { didSet { save() } }        // "auto" | "8" | "10"
    var frameRateMode: String { didSet { save() } }     // "auto" | "passthrough" | "constant"
    var frameRateValue: Double { didSet { save() } }    // fps used when mode == "constant"
    var exportToEditor: Bool { didSet { save() } }      // write an editor project instead of rendering
    var outputDirectory: String { didSet { save() } }   // "" ⇒ beside the source
    var splitTracks: Bool { didSet { save() } }          // also write separate video/audio files
    var splitAudioFormat: String { didSet { save() } }   // "match" | "wav"
    var captionsFormat: String { didSet { save() } }     // "none" | "srt" | "vtt" | "both"
    var retakeSensitivity: String { didSet { save() } }  // "gentle" | "balanced" | "aggressive"
    // Backup (applied to every clean)
    var backupOriginal: Bool { didSet { save() } }
    // Watch folder (drives the background agent)
    var watchEnabled: Bool { didSet { save() } }
    var watchFolderPath: String { didSet { save() } }
    var watchRemoveFillers: Bool { didSet { save() } }
    // Presets (named recipes a queue row can pick) + which one new files default to
    var presets: [Preset] { didSet { save() } }
    var defaultPresetID: String { didSet { save() } }
    // Parallelism (drives the resource governor)
    var concurrencyMode: String { didSet { save() } }
    var manualConcurrency: Int { didSet { save() } }
    var perJobMemoryBudgetMB: Int { didSet { save() } }
    // Speech model — which catalog model the engine loads for filler detection
    var selectedModelID: String { didSet { save() } }
    // Menu bar — show a quick-drop menu-bar item (opt-in)
    var menuBarEnabled: Bool { didSet { save() } }
    // Filler model — experimental, opt-in fast on-device backend for filler
    // detection (off by default; whisper stays the default when off)
    var fillerModelEnabled: Bool { didSet { save() } }
    var selectedFillerModelID: String { didSet { save() } }
    // Opt-in: record anonymous local feedback to help improve the filler model
    var shareFillerData: Bool { didSet { save() } }

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
                     pauseMode: pauseMode, tightPause: tightPause,
                     fadeMs: fadeMs, crossfadeMs: crossfadeMs, snapMs: snapMs,
                     videoCodec: videoCodec, hardwareEncoding: hardwareEncoding,
                     videoQuality: videoQuality, audioCodec: audioCodec,
                     audioBitrateKbps: audioBitrateKbps, outputContainer: outputContainer,
                     colorDepth: colorDepth,
                     frameRateMode: frameRateMode, frameRateValue: frameRateValue,
                     exportToEditor: exportToEditor,
                     outputDirectory: outputDirectory,
                     splitTracks: splitTracks, splitAudioFormat: splitAudioFormat,
                     captionsFormat: captionsFormat,
                     retakeSensitivity: retakeSensitivity,
                     backupOriginal: backupOriginal,
                     watchEnabled: watchEnabled, watchFolderPath: watchFolderPath,
                     watchRemoveFillers: watchRemoveFillers,
                     presets: presets, defaultPresetID: defaultPresetID,
                     concurrencyMode: concurrencyMode, manualConcurrency: manualConcurrency,
                     perJobMemoryBudgetMB: perJobMemoryBudgetMB,
                     selectedModelID: selectedModelID, menuBarEnabled: menuBarEnabled,
                     fillerModelEnabled: fillerModelEnabled,
                     selectedFillerModelID: selectedFillerModelID,
                     shareFillerData: shareFillerData)
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
        // Clamp a hand-edited/unknown pause mode to the default so the Settings picker
        // always has a valid selection (and the engine a legal --pause-mode); clamp the
        // gap to the slider bounds like the smoothing values below.
        pauseMode = PauseMode(rawValue: cfg.pauseMode)?.rawValue ?? EngineConfig.defaults.pauseMode
        tightPause = min(max(cfg.tightPause, 0.05), 0.5)
        // Clamp persisted smoothing values to the Settings slider bounds, so a stale
        // or hand-edited config can't drive the engine past the UI limits.
        fadeMs = min(max(cfg.fadeMs, 0), 50)
        crossfadeMs = min(max(cfg.crossfadeMs, 0), 500)
        snapMs = min(max(cfg.snapMs, 0), 30)
        videoCodec = cfg.videoCodec
        hardwareEncoding = cfg.hardwareEncoding
        videoQuality = cfg.videoQuality
        audioCodec = cfg.audioCodec
        audioBitrateKbps = cfg.audioBitrateKbps
        outputContainer = cfg.outputContainer
        // Clamp a hand-edited/unknown depth to the default so the Settings picker always
        // has a valid selection (and the engine a legal --color-depth value).
        colorDepth = ColorDepth(rawValue: cfg.colorDepth)?.rawValue ?? EngineConfig.defaults.colorDepth
        // Normalize a hand-edited/unknown mode to the default so the Settings picker
        // always has a valid selection (and the engine a legal --fps-mode).
        frameRateMode = FrameRateMode(rawValue: cfg.frameRateMode)?.rawValue
            ?? EngineConfig.defaults.frameRateMode
        frameRateValue = cfg.frameRateValue
        exportToEditor = cfg.exportToEditor
        outputDirectory = cfg.outputDirectory
        splitTracks = cfg.splitTracks
        splitAudioFormat = cfg.splitAudioFormat
        // Clamp a hand-edited/corrupt value to a known one, so the Settings picker
        // always has a valid selection and the engine never gets a bogus --captions.
        captionsFormat = CaptionFormat(rawValue: cfg.captionsFormat)?.rawValue
            ?? EngineConfig.defaults.captionsFormat
        retakeSensitivity = RetakeSensitivity(rawValue: cfg.retakeSensitivity)?.rawValue
            ?? EngineConfig.defaults.retakeSensitivity
        backupOriginal = cfg.backupOriginal
        watchEnabled = cfg.watchEnabled
        watchFolderPath = cfg.watchFolderPath
        watchRemoveFillers = cfg.watchRemoveFillers
        presets = cfg.presets
        defaultPresetID = cfg.defaultPresetID
        concurrencyMode = cfg.concurrencyMode
        manualConcurrency = cfg.manualConcurrency
        perJobMemoryBudgetMB = cfg.perJobMemoryBudgetMB
        // Normalize a removed/unknown model id to the catalog fallback, so the
        // Settings picker always has a valid selection (and the engine a real model).
        selectedModelID = ModelCatalog.spec(id: cfg.selectedModelID).id
        menuBarEnabled = cfg.menuBarEnabled
        fillerModelEnabled = cfg.fillerModelEnabled
        // Clamp a removed/unknown filler-model id to the catalog fallback, so the
        // Settings picker always has a valid selection.
        selectedFillerModelID = FillerModelCatalog.spec(id: cfg.selectedFillerModelID).id
        shareFillerData = cfg.shareFillerData
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
        pauseMode = d.pauseMode
        tightPause = d.tightPause
        fadeMs = d.fadeMs
        crossfadeMs = d.crossfadeMs
        snapMs = d.snapMs
        videoCodec = d.videoCodec
        hardwareEncoding = d.hardwareEncoding
        videoQuality = d.videoQuality
        audioCodec = d.audioCodec
        audioBitrateKbps = d.audioBitrateKbps
        outputContainer = d.outputContainer
        colorDepth = d.colorDepth
        frameRateMode = d.frameRateMode
        frameRateValue = d.frameRateValue
        exportToEditor = d.exportToEditor
        outputDirectory = d.outputDirectory
        splitTracks = d.splitTracks
        splitAudioFormat = d.splitAudioFormat
        captionsFormat = d.captionsFormat
        retakeSensitivity = d.retakeSensitivity
        backupOriginal = d.backupOriginal
    }

    // MARK: - Presets

    /// The preset newly added files should use, if a valid default is set.
    var defaultPreset: Preset? {
        guard let id = UUID(uuidString: defaultPresetID) else { return nil }
        return presets.first { $0.id == id }
    }

    func preset(withID id: UUID?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    /// Snapshot the current global recipe (cut + encode + output + backup, plus the
    /// given strength) into a new preset and return it.
    @discardableResult
    func addPreset(named name: String, strength: Strength) -> Preset {
        let preset = Preset(name: name, strength: strength, config: config)
        presets.append(preset)
        return preset
    }

    func renamePreset(_ id: UUID, to name: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = name
    }

    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if defaultPresetID == id.uuidString { defaultPresetID = "" }
    }

    func setDefaultPreset(_ id: UUID?) {
        defaultPresetID = id?.uuidString ?? ""
    }

    private func save() { EngineConfigStore.save(config) }
}
