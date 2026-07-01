/// Everything the engine needs for one clean: the four cut knobs plus the encoder
/// choices. Cut knobs are strength-derived (`.custom` pulls them from the saved
/// config; presets use their own values + engine defaults). Encoder choices are
/// always taken from the config — they apply to every clean regardless of strength.
public struct CleanParameters: Equatable, Sendable {
    public let pause: Double
    public let noiseDB: Double
    public let keepPause: Double
    public let minKeep: Double
    // Pause handling — taken from the config for every clean (like the encoder
    // choices): "remove" cuts a pause entirely; "tighten" keeps `tightPause` extra
    // seconds of silence at it so pacing stays natural.
    public let pauseMode: String     // "remove" | "tighten"
    public let tightPause: Double    // seconds kept at each pause in tighten mode
    // Cut smoothing — taken from the config for every clean (like the encoder choices)
    public let fadeMs: Double
    public let crossfadeMs: Double
    public let snapMs: Double
    public let videoCodec: String
    public let hardwareEncoding: Bool
    public let videoQuality: String
    public let audioCodec: String
    public let audioBitrateKbps: Int
    public let outputContainer: String
    public let colorDepth: String        // "auto" | "8" | "10" — output bit depth
    public let frameRateMode: String     // "auto" | "passthrough" | "constant"
    public let frameRateValue: Double    // fps used when mode == "constant"
    public let exportTimeline: String    // "none" (render) | "fcpxml" (editor handoff)
    public let outputDirectory: String   // "" ⇒ beside the source
    public let splitTracks: Bool         // also write separate video/audio files
    public let splitAudioFormat: String  // "match" | "wav" — audio stem format
    public let captionsFormat: String    // "none" | "srt" | "vtt" | "both"
    public let retakeSensitivity: String // "gentle" | "balanced" | "aggressive"
    public let backupOriginal: Bool

    public init(pause: Double, noiseDB: Double, keepPause: Double, minKeep: Double,
                pauseMode: String = "remove", tightPause: Double = 0.3,
                fadeMs: Double = 10, crossfadeMs: Double = 0, snapMs: Double = 12,
                videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
                audioCodec: String, audioBitrateKbps: Int, outputContainer: String,
                colorDepth: String = "auto",
                frameRateMode: String = "auto", frameRateValue: Double = 30,
                exportTimeline: String = "none",
                outputDirectory: String, splitTracks: Bool, splitAudioFormat: String,
                captionsFormat: String = "none", retakeSensitivity: String = "aggressive",
                backupOriginal: Bool) {
        self.pause = pause
        self.noiseDB = noiseDB
        self.keepPause = keepPause
        self.minKeep = minKeep
        self.pauseMode = pauseMode
        self.tightPause = tightPause
        self.fadeMs = fadeMs
        self.crossfadeMs = crossfadeMs
        self.snapMs = snapMs
        self.videoCodec = videoCodec
        self.hardwareEncoding = hardwareEncoding
        self.videoQuality = videoQuality
        self.audioCodec = audioCodec
        self.audioBitrateKbps = audioBitrateKbps
        self.outputContainer = outputContainer
        self.colorDepth = colorDepth
        self.frameRateMode = frameRateMode
        self.frameRateValue = frameRateValue
        self.exportTimeline = exportTimeline
        self.outputDirectory = outputDirectory
        self.splitTracks = splitTracks
        self.splitAudioFormat = splitAudioFormat
        self.captionsFormat = captionsFormat
        self.retakeSensitivity = retakeSensitivity
        self.backupOriginal = backupOriginal
    }
}

extension Strength {
    public func parameters(using config: EngineConfig) -> CleanParameters {
        let isCustom = self == .custom
        return CleanParameters(
            pause: isCustom ? config.pauseThreshold : pause,
            noiseDB: isCustom ? config.silenceFloorDB : EngineConfig.defaults.silenceFloorDB,
            keepPause: isCustom ? config.breathingRoom : keepPause,
            minKeep: isCustom ? config.minKeep : EngineConfig.defaults.minKeep,
            // Clamp a hand-edited/corrupt value to the default so the engine's
            // --pause-mode (which has fixed choices) never hard-fails a clean.
            pauseMode: PauseMode(rawValue: config.pauseMode)?.rawValue
                ?? PauseMode.remove.rawValue,
            // Clamp to the Settings slider bounds here — the one mapping every render
            // path shares (incl. the headless watcher/App Intent, which never pass
            // through EngineSettings' init clamp). A negative value would start each
            // pause cut inside speech; huge values would disable pause cutting.
            tightPause: min(max(config.tightPause, 0), 0.5),
            fadeMs: config.fadeMs,
            crossfadeMs: config.crossfadeMs,
            snapMs: config.snapMs,
            videoCodec: config.videoCodec,
            hardwareEncoding: config.hardwareEncoding,
            videoQuality: config.videoQuality,
            audioCodec: config.audioCodec,
            audioBitrateKbps: config.audioBitrateKbps,
            outputContainer: config.outputContainer,
            // Clamp a hand-edited/corrupt value to the default so the engine's
            // --color-depth (fixed choices) never hard-fails a clean.
            colorDepth: ColorDepth(rawValue: config.colorDepth)?.rawValue
                ?? ColorDepth.auto.rawValue,
            frameRateMode: FrameRateMode(rawValue: config.frameRateMode)?.rawValue
                ?? FrameRateMode.auto.rawValue,
            frameRateValue: config.frameRateValue,
            exportTimeline: config.exportToEditor ? "fcpxml" : "none",
            outputDirectory: config.outputDirectory,
            splitTracks: config.splitTracks,
            splitAudioFormat: config.splitAudioFormat,
            captionsFormat: config.captionsFormat,
            // Clamp a hand-edited/corrupt value to the default preset so the engine's
            // --retake-sensitivity (which has fixed choices) never hard-fails a clean.
            retakeSensitivity: RetakeSensitivity(rawValue: config.retakeSensitivity)?.rawValue
                ?? RetakeSensitivity.aggressive.rawValue,
            backupOriginal: config.backupOriginal)
    }
}
