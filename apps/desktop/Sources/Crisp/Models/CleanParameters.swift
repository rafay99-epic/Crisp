/// Everything the engine needs for one clean: the four cut knobs plus the encoder
/// choices. Cut knobs are strength-derived (`.custom` pulls them from the saved
/// config; presets use their own values + engine defaults). Encoder choices are
/// always taken from the config — they apply to every clean regardless of strength.
struct CleanParameters: Equatable {
    let pause: Double
    let noiseDB: Double
    let keepPause: Double
    let minKeep: Double
    let videoCodec: String
    let hardwareEncoding: Bool
    let videoQuality: String
    let audioCodec: String
    let audioBitrateKbps: Int
    let outputContainer: String
    let backupOriginal: Bool
}

extension Strength {
    func parameters(using config: EngineConfig) -> CleanParameters {
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
            backupOriginal: config.backupOriginal)
    }
}
