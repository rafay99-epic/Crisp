import Foundation

/// A named, reusable clean recipe — a full set of cut + encode + output + backup
/// choices the user can apply to individual files in the queue, instead of the one
/// global setting. Stored in `settings.json` (`EngineConfig.presets`).
///
/// Mirrors the recipe fields of `EngineConfig` plus a `strength`. `parameters()`
/// reuses the existing `Strength.parameters(using:)` mapping so a preset resolves
/// exactly like the global path — no second copy of the cut/encode logic.
public struct Preset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var strength: String          // Strength.rawValue
    // Cutting (used when `strength` is Custom)
    public var pauseThreshold: Double
    public var silenceFloorDB: Double
    public var breathingRoom: Double
    public var minKeep: Double
    // Encoding
    public var videoCodec: String
    public var hardwareEncoding: Bool
    public var videoQuality: String
    public var audioCodec: String
    public var audioBitrateKbps: Int
    public var outputContainer: String
    // Output + backup
    public var outputDirectory: String
    public var backupOriginal: Bool

    public init(id: UUID = UUID(), name: String, strength: String,
                pauseThreshold: Double, silenceFloorDB: Double, breathingRoom: Double, minKeep: Double,
                videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
                audioCodec: String, audioBitrateKbps: Int, outputContainer: String,
                outputDirectory: String, backupOriginal: Bool) {
        self.id = id
        self.name = name
        self.strength = strength
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
        self.backupOriginal = backupOriginal
    }

    /// Snapshot the current global recipe into a new preset under `name`.
    public init(name: String, strength: Strength, config: EngineConfig, id: UUID = UUID()) {
        self.init(id: id, name: name, strength: strength.rawValue,
                  pauseThreshold: config.pauseThreshold, silenceFloorDB: config.silenceFloorDB,
                  breathingRoom: config.breathingRoom, minKeep: config.minKeep,
                  videoCodec: config.videoCodec, hardwareEncoding: config.hardwareEncoding,
                  videoQuality: config.videoQuality, audioCodec: config.audioCodec,
                  audioBitrateKbps: config.audioBitrateKbps, outputContainer: config.outputContainer,
                  outputDirectory: config.outputDirectory, backupOriginal: config.backupOriginal)
    }

    /// Resolve this preset to engine parameters, reusing the global mapping: build
    /// a throwaway `EngineConfig` from the preset's fields and run it through the
    /// existing `Strength.parameters(using:)`.
    ///
    /// `exportToEditor` is a global *output mode* (editor handoff), not a per-preset
    /// recipe knob, so the live setting is threaded in — otherwise a preset-backed row
    /// would silently render a video even while "Send to editor" is on. No default:
    /// callers must pass the live setting (or an intentional `false`) so the
    /// silent-render failure mode can't sneak back in.
    public func parameters(exportToEditor: Bool) -> CleanParameters {
        var cfg = EngineConfig.defaults
        cfg.pauseThreshold = pauseThreshold
        cfg.silenceFloorDB = silenceFloorDB
        cfg.breathingRoom = breathingRoom
        cfg.minKeep = minKeep
        cfg.videoCodec = videoCodec
        cfg.hardwareEncoding = hardwareEncoding
        cfg.videoQuality = videoQuality
        cfg.audioCodec = audioCodec
        cfg.audioBitrateKbps = audioBitrateKbps
        cfg.outputContainer = outputContainer
        cfg.outputDirectory = outputDirectory
        cfg.backupOriginal = backupOriginal
        cfg.exportToEditor = exportToEditor
        return (Strength(rawValue: strength) ?? .custom).parameters(using: cfg)
    }
}
