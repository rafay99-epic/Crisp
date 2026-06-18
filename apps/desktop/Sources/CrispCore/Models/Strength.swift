/// How aggressively to cut. Each preset maps to the engine's pause threshold and
/// the breathing room kept around every cut.
public enum Strength: String, CaseIterable, Identifiable {
    case gentle = "Gentle"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
    case veryAggressive = "Very aggressive"
    case custom = "Custom"

    public var id: String { rawValue }

    /// Shorter label for the segmented picker, where "Very aggressive" + "Custom"
    /// won't both fit. `rawValue` stays the full name everywhere else.
    public var pickerLabel: String { self == .veryAggressive ? "Very" : rawValue }

    public var detail: String {
        switch self {
        case .gentle:         return "Cuts only clearly long pauses. Most natural."
        case .balanced:       return "A safe middle ground."
        case .aggressive:     return "Cuts short \u{201C}thinking\u{201D} gaps too. Recommended."
        case .veryAggressive: return "Tightest possible. Can feel fast-paced."
        case .custom:         return "Your own settings \u{2014} adjust them in Settings (\u{2318},)."
        }
    }
    // `pause`/`keepPause` are the fixed presets. `.custom` falls back to the
    // Aggressive values for exhaustiveness; its real values come from
    // `EngineSettings` via `Strength.parameters(using:)`.
    public var pause: Double {
        switch self {
        case .gentle: return 0.80
        case .balanced: return 0.60
        case .aggressive, .custom: return 0.35
        case .veryAggressive: return 0.25
        }
    }
    public var keepPause: Double {
        switch self {
        case .gentle: return 0.18
        case .balanced: return 0.15
        case .aggressive, .custom: return 0.10
        case .veryAggressive: return 0.08
        }
    }
}
