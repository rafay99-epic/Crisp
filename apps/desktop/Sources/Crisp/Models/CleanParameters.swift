/// The four numeric knobs the engine takes for one clean. Derived from the
/// chosen `Strength`: a preset supplies pause/keep-pause (with the engine
/// defaults for the rest); `.custom` pulls all four from `EngineSettings`.
struct CleanParameters: Equatable {
    let pause: Double
    let noiseDB: Double
    let keepPause: Double
    let minKeep: Double
}

extension Strength {
    /// `.custom` takes all four from the user's saved `config`; any preset takes
    /// pause/keep-pause from itself and the engine defaults for the rest.
    func parameters(using config: EngineConfig) -> CleanParameters {
        switch self {
        case .custom:
            return CleanParameters(pause: config.pauseThreshold,
                                   noiseDB: config.silenceFloorDB,
                                   keepPause: config.breathingRoom,
                                   minKeep: config.minKeep)
        default:
            return CleanParameters(pause: pause,
                                   noiseDB: EngineConfig.defaults.silenceFloorDB,
                                   keepPause: keepPause,
                                   minKeep: EngineConfig.defaults.minKeep)
        }
    }
}
