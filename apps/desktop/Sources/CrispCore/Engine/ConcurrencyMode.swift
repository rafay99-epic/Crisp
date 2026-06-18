/// How Crisp decides how many videos to clean at the same time.
public enum ConcurrencyMode: String, CaseIterable, Identifiable, Sendable {
    /// The resource governor picks a safe count from current free RAM/CPU/thermal.
    case auto
    /// A fixed count the user chose, clamped to the machine's sustainable ceiling.
    case manual
    /// Push to the machine's ceiling, but only after a free-resource preflight that
    /// hard-blocks (with a recheck) when there isn't enough headroom right now.
    case ultra

    public var id: String { rawValue }

    /// Tolerant decode from the stored string (unknown ⇒ `.auto`).
    public init(storage: String) {
        self = ConcurrencyMode(rawValue: storage) ?? .auto
    }

    public var label: String {
        switch self {
        case .auto:   return "Automatic"
        case .manual: return "Manual"
        case .ultra:  return "Ultra"
        }
    }

    public var detail: String {
        switch self {
        case .auto:   return "Crisp picks a safe number based on this Mac's free memory and cores."
        case .manual: return "You choose how many run at once (capped to what this Mac can sustain)."
        case .ultra:  return "Run as many as this Mac can handle. Crisp checks you have enough free memory first \u{2014} if not, it asks you to close some apps."
        }
    }
}
