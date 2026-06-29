import Foundation

/// Thrown by `LicenseGate.checkClean()` when a headless clean is refused.
public struct LicenseBlockedError: LocalizedError, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The entitlement a Crisp install currently holds. Derived purely from stored
/// state (no network) so every entry point can read it cheaply.
public enum Entitlement: Equatable, Sendable {
    case licensed
    case trial(daysLeft: Int)
    case trialExpired
    case unlicensed
    case revoked

    /// May this install run a clean? Licensed and in-trial may; everything else can't.
    public var allowsClean: Bool {
        switch self {
        case .licensed, .trial: return true
        case .trialExpired, .unlicensed, .revoked: return false
        }
    }
}

/// The single, headless source of truth for "may this install clean?". Read by the
/// GUI (to disable the Clean button) **and** by the shared `QuickClean` path (the
/// watch-folder agent, the Shortcuts intent, the menu-bar drop) so no entry point
/// slips past the gate.
///
/// Crucially, when the feature flag is off (`Channel.licensingEnabled == false`)
/// `allowsClean` is always `true` and `blockReason` always `nil` — the app behaves
/// exactly as it did before licensing existed. That's the safety guarantee for
/// shipping this dark.
public enum LicenseGate {
    private static let log = AppInfo.logger("license")

    public static var isEnabled: Bool { Channel.licensingEnabled }

    /// Record that the app is running *now*, advancing the rollback watermark.
    /// Call once per launch / refresh.
    public static func recordSeen(now: Date = Date()) {
        let previous = LicenseStorage.lastSeenAt ?? .distantPast
        if now > previous { LicenseStorage.lastSeenAt = now }
    }

    /// Begin the free trial if it hasn't started yet (idempotent). Returns whether a
    /// trial is now active.
    @discardableResult
    public static func startTrialIfNeeded(now: Date = Date()) -> Bool {
        if LicenseStorage.trialStartedAt == nil {
            LicenseStorage.trialStartedAt = now
            recordSeen(now: now)
        }
        return currentEntitlement(now: now).allowsClean
    }

    /// Pure entitlement computation from explicit inputs — no storage, no network — so
    /// it can be unit-tested in isolation. A stored key is trusted as `.licensed` here
    /// (the GUI `LicenseStore` is what re-validates online and sets `isRevoked`).
    /// Trial elapsed time is measured against `max(now, lastSeenAt)`, so winding the
    /// clock back can't buy more trial.
    static func entitlement(isRevoked: Bool,
                            hasLicenseKey: Bool,
                            trialStartedAt: Date?,
                            lastSeenAt: Date?,
                            now: Date,
                            trialDays: Int = PolarConfig.trialDays) -> Entitlement {
        if isRevoked { return .revoked }
        if hasLicenseKey { return .licensed }
        guard let start = trialStartedAt else { return .unlicensed }
        let effectiveNow = max(now, lastSeenAt ?? now)
        let elapsed = Int(effectiveNow.timeIntervalSince(start) / 86_400)
        let daysLeft = trialDays - elapsed
        return daysLeft > 0 ? .trial(daysLeft: daysLeft) : .trialExpired
    }

    /// The current entitlement, derived from stored state only — keeping the headless
    /// path offline-safe.
    public static func currentEntitlement(now: Date = Date()) -> Entitlement {
        entitlement(isRevoked: LicenseStorage.isRevoked,
                    hasLicenseKey: LicenseStorage.licenseKey != nil,
                    trialStartedAt: LicenseStorage.trialStartedAt,
                    lastSeenAt: LicenseStorage.lastSeenAt,
                    now: now)
    }

    /// May this install clean right now? Always `true` when the feature is disabled.
    public static func allowsClean(now: Date = Date()) -> Bool {
        cleanAllowed(enabled: isEnabled, entitlement: currentEntitlement(now: now))
    }

    /// Throw if cleaning is blocked — used by the headless `QuickClean` path so the
    /// watch folder, the Shortcuts intent, and the menu-bar drop all refuse with a
    /// clear message instead of silently producing output. A no-op when allowed.
    ///
    /// Also advances the rollback watermark: these headless surfaces may be the *only*
    /// way the app runs (watch-folder-only usage), so without this a stale `lastSeenAt`
    /// would let a clock rollback recover trial days.
    public static func checkClean(now: Date = Date()) throws {
        if isEnabled { recordSeen(now: now) }
        if let reason = blockReason(now: now) {
            log.error("license: clean blocked — \(reason, privacy: .public)")
            throw LicenseBlockedError(message: reason)
        }
    }

    /// Pure clean-permission rule, exposed for testing: cleaning is always allowed when
    /// the feature is disabled, regardless of entitlement.
    static func cleanAllowed(enabled: Bool, entitlement: Entitlement) -> Bool {
        !enabled || entitlement.allowsClean
    }

    /// A user-facing reason cleaning is blocked, or `nil` when it's allowed (and
    /// always `nil` when the feature is disabled).
    public static func blockReason(now: Date = Date()) -> String? {
        guard isEnabled else { return nil }
        switch currentEntitlement(now: now) {
        case .licensed, .trial:
            return nil
        case .trialExpired:
            return "Your Crisp trial has ended. Enter a license in Settings to keep cleaning."
        case .unlicensed:
            return "Start your free trial or enter a license in Settings to clean videos."
        case .revoked:
            return "This Crisp license is no longer active. Enter a valid license in Settings."
        }
    }
}
