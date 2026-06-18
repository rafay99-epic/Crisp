/// Everything the engine needs for one clean: the four cut knobs plus the encoder
/// choices. Cut knobs are strength-derived (`.custom` pulls them from the saved
/// config; presets use their own values + engine defaults). Encoder choices are
/// always taken from the config — they apply to every clean regardless of strength.
public struct CleanParameters: Equatable, Sendable {
    public let pause: Double
    public let noiseDB: Double
    public let keepPause: Double
    public let minKeep: Double
    public let videoCodec: String
    public let hardwareEncoding: Bool
    public let videoQuality: String
    public let audioCodec: String
    public let audioBitrateKbps: Int
    public let outputContainer: String
    public let outputDirectory: String   // "" ⇒ beside the source
    public let splitTracks: Bool         // also write separate video/audio files
    public let splitAudioFormat: String  // "match" | "wav" — audio stem format
    public let backupOriginal: Bool

    public init(pause: Double, noiseDB: Double, keepPause: Double, minKeep: Double,
                videoCodec: String, hardwareEncoding: Bool, videoQuality: String,
                audioCodec: String, audioBitrateKbps: Int, outputContainer: String,
                outputDirectory: String, splitTracks: Bool, splitAudioFormat: String,
                backupOriginal: Bool) {
        self.pause = pause
        self.noiseDB = noiseDB
        self.keepPause = keepPause
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
            videoCodec: config.videoCodec,
            hardwareEncoding: config.hardwareEncoding,
            videoQuality: config.videoQuality,
            audioCodec: config.audioCodec,
            audioBitrateKbps: config.audioBitrateKbps,
            outputContainer: config.outputContainer,
            outputDirectory: config.outputDirectory,
            splitTracks: config.splitTracks,
            splitAudioFormat: config.splitAudioFormat,
            backupOriginal: config.backupOriginal)
    }
}
