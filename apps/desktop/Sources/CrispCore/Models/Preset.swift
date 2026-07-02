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
    // Pause handling (applied to every clean)
    public var pauseMode: String         // "remove" | "tighten"
    public var tightPause: Double        // seconds kept at each pause in tighten mode
    // Encoding
    public var videoCodec: String
    public var hardwareEncoding: Bool
    public var videoQuality: String
    public var audioCodec: String
    public var audioBitrateKbps: Int
    public var outputContainer: String
    public var colorDepth: String        // "auto" | "8" | "10" — output bit depth
    // Output + backup
    public var outputDirectory: String
    public var backupOriginal: Bool

    public init(id: UUID = UUID(), name: String, strength: String,
                pauseThreshold: Double, silenceFloorDB: Double, breathingRoom: Double, minKeep: Double,
                pauseMode: String = "remove", tightPause: Double = 0.3,
                videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
                audioCodec: String, audioBitrateKbps: Int, outputContainer: String,
                colorDepth: String = "auto",
                outputDirectory: String, backupOriginal: Bool) {
        self.id = id
        self.name = name
        self.strength = strength
        self.pauseThreshold = pauseThreshold
        self.silenceFloorDB = silenceFloorDB
        self.breathingRoom = breathingRoom
        self.minKeep = minKeep
        self.pauseMode = pauseMode
        self.tightPause = tightPause
        self.videoCodec = videoCodec
        self.hardwareEncoding = hardwareEncoding
        self.videoQuality = videoQuality
        self.audioCodec = audioCodec
        self.audioBitrateKbps = audioBitrateKbps
        self.outputContainer = outputContainer
        self.colorDepth = colorDepth
        self.outputDirectory = outputDirectory
        self.backupOriginal = backupOriginal
    }

    // Custom CodingKeys + decoder so a NEW field (colorDepth) added to presets already
    // saved in settings.json stays forward-compatible: synthesized Codable would fail to
    // decode an older preset missing the key — and because EngineConfig decodes its whole
    // `presets` array under one `try`, a single failed preset would throw away ALL the
    // user's settings (load() falls back to defaults). decodeIfPresent prevents that.
    //
    // MAINTENANCE: a recipe field added here must be threaded through every spot below, or
    // it's silently dropped on save, load, or use:
    //   • the stored property + memberwise `init`
    //   • `CodingKeys` below + `init(from:)` — use `decodeIfPresent(…) ?? <default>` (like
    //     colorDepth) so a preset saved before the field still decodes (forward-compat)
    //   • the snapshot `init(name:strength:config:)` — copy it from the `EngineConfig`
    //   • `parameters(using:)` — overlay it onto the live `EngineConfig`
    // The first two keep it on disk; the last two keep it flowing config → preset → clean, so
    // a preset saved at e.g. colorDepth "10" actually renders at "10" instead of the default.
    enum CodingKeys: String, CodingKey {
        case id, name, strength, pauseThreshold, silenceFloorDB, breathingRoom, minKeep
        case pauseMode, tightPause
        case videoCodec, hardwareEncoding, videoQuality, audioCodec, audioBitrateKbps
        case outputContainer, colorDepth, outputDirectory, backupOriginal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        strength = try c.decode(String.self, forKey: .strength)
        pauseThreshold = try c.decode(Double.self, forKey: .pauseThreshold)
        silenceFloorDB = try c.decode(Double.self, forKey: .silenceFloorDB)
        breathingRoom = try c.decode(Double.self, forKey: .breathingRoom)
        minKeep = try c.decode(Double.self, forKey: .minKeep)
        pauseMode = try c.decodeIfPresent(String.self, forKey: .pauseMode) ?? "remove"
        tightPause = try c.decodeIfPresent(Double.self, forKey: .tightPause) ?? 0.3
        videoCodec = try c.decode(String.self, forKey: .videoCodec)
        hardwareEncoding = try c.decode(Bool.self, forKey: .hardwareEncoding)
        videoQuality = try c.decode(String.self, forKey: .videoQuality)
        audioCodec = try c.decode(String.self, forKey: .audioCodec)
        audioBitrateKbps = try c.decode(Int.self, forKey: .audioBitrateKbps)
        outputContainer = try c.decode(String.self, forKey: .outputContainer)
        colorDepth = try c.decodeIfPresent(String.self, forKey: .colorDepth) ?? "auto"
        outputDirectory = try c.decode(String.self, forKey: .outputDirectory)
        backupOriginal = try c.decode(Bool.self, forKey: .backupOriginal)
    }

    /// Snapshot the current global recipe into a new preset under `name`.
    public init(name: String, strength: Strength, config: EngineConfig, id: UUID = UUID()) {
        self.init(id: id, name: name, strength: strength.rawValue,
                  pauseThreshold: config.pauseThreshold, silenceFloorDB: config.silenceFloorDB,
                  breathingRoom: config.breathingRoom, minKeep: config.minKeep,
                  pauseMode: config.pauseMode, tightPause: config.tightPause,
                  videoCodec: config.videoCodec, hardwareEncoding: config.hardwareEncoding,
                  videoQuality: config.videoQuality, audioCodec: config.audioCodec,
                  audioBitrateKbps: config.audioBitrateKbps, outputContainer: config.outputContainer,
                  colorDepth: config.colorDepth,
                  outputDirectory: config.outputDirectory, backupOriginal: config.backupOriginal)
    }

    /// Resolve this preset to engine parameters, reusing the global mapping: start
    /// from the *live* `EngineConfig`, overlay only the recipe fields this preset
    /// stores, and run it through the existing `Strength.parameters(using:)`.
    ///
    /// Starting from the live config (not `EngineConfig.defaults`) is deliberate: a
    /// preset stores only its cut/encode/output/backup recipe, so every other global
    /// knob — `exportToEditor`, `captionsFormat`, `retakeSensitivity`, frame-rate,
    /// `splitTracks`, fades/snap, … — flows in from the live setting instead of being
    /// silently reset to a default. This keeps preset-backed rows in step with the
    /// non-preset path (`strength.parameters(using: settings.config)`).
    public func parameters(using config: EngineConfig) -> CleanParameters {
        var cfg = config
        cfg.pauseThreshold = pauseThreshold
        cfg.silenceFloorDB = silenceFloorDB
        cfg.breathingRoom = breathingRoom
        cfg.minKeep = minKeep
        cfg.pauseMode = pauseMode
        cfg.tightPause = tightPause
        cfg.videoCodec = videoCodec
        cfg.hardwareEncoding = hardwareEncoding
        cfg.videoQuality = videoQuality
        cfg.audioCodec = audioCodec
        cfg.audioBitrateKbps = audioBitrateKbps
        cfg.outputContainer = outputContainer
        cfg.colorDepth = colorDepth
        cfg.outputDirectory = outputDirectory
        cfg.backupOriginal = backupOriginal
        return (Strength(rawValue: strength) ?? .custom).parameters(using: cfg)
    }
}
