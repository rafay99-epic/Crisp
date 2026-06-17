/// How aggressively to cut. Each preset maps to the engine's pause threshold and
/// the breathing room kept around every cut.
enum Strength: String, CaseIterable, Identifiable {
    case gentle = "Gentle"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
    case veryAggressive = "Very aggressive"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .gentle:         return "Cuts only clearly long pauses. Most natural."
        case .balanced:       return "A safe middle ground."
        case .aggressive:     return "Cuts short \u{201C}thinking\u{201D} gaps too. Recommended."
        case .veryAggressive: return "Tightest possible. Can feel fast-paced."
        }
    }
    var pause: Double {
        switch self {
        case .gentle: return 0.80
        case .balanced: return 0.60
        case .aggressive: return 0.35
        case .veryAggressive: return 0.25
        }
    }
    var keepPause: Double {
        switch self {
        case .gentle: return 0.18
        case .balanced: return 0.15
        case .aggressive: return 0.10
        case .veryAggressive: return 0.08
        }
    }
}
