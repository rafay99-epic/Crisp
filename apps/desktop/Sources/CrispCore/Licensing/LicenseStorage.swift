import Foundation

/// Device-local persistence for the licensing state, backed by the `Keychain`.
/// Shared by the app's `LicenseStore` (which does the networking + UI state) and the
/// headless `LicenseGate` (which the watch-folder agent and the Shortcuts intent read),
/// so every entry point sees one source of truth.
///
/// Nothing here touches the network — it's pure read/write of stored facts.
public enum LicenseStorage {
    private enum Account {
        static let licenseKey = "key"
        static let activationID = "activationID"
        static let trialStarted = "trialStartedAt"
        static let lastSeen = "lastSeenAt"
        static let lastValidated = "lastValidatedAt"
        static let requiresActivation = "requiresActivation"
        static let revoked = "revoked"
        static let deviceID = "deviceID"
    }

    public static var licenseKey: String? {
        get { Keychain.string(for: Account.licenseKey) }
        set { Keychain.set(newValue, for: Account.licenseKey) }
    }

    public static var activationID: String? {
        get { Keychain.string(for: Account.activationID) }
        set { Keychain.set(newValue, for: Account.activationID) }
    }

    /// When the free trial began (nil ⇒ never started).
    public static var trialStartedAt: Date? {
        get { date(for: Account.trialStarted) }
        set { setDate(newValue, for: Account.trialStarted) }
    }

    /// High-watermark of the latest time the app has ever observed. Bumped on every
    /// launch/refresh and never moved backwards — so winding the system clock back
    /// can't extend a trial (see `LicenseGate.trialElapsedDays`).
    public static var lastSeenAt: Date? {
        get { date(for: Account.lastSeen) }
        set { setDate(newValue, for: Account.lastSeen) }
    }

    /// Last successful online re-validation of a stored license (throttles the
    /// weekly re-check).
    public static var lastValidatedAt: Date? {
        get { date(for: Account.lastValidated) }
        set { setDate(newValue, for: Account.lastValidated) }
    }

    /// Whether the active license is device-bound (Polar `limit_activations > 0`).
    public static var requiresActivation: Bool {
        get { Keychain.string(for: Account.requiresActivation) == "1" }
        set { Keychain.set(newValue ? "1" : "0", for: Account.requiresActivation) }
    }

    /// Set only when Polar explicitly reports the key is no longer granted
    /// (refunded / revoked / subscription lapsed) — never on a mere network failure.
    public static var isRevoked: Bool {
        get { Keychain.string(for: Account.revoked) == "1" }
        set { Keychain.set(newValue ? "1" : "0", for: Account.revoked) }
    }

    /// Stable per-device id used for Polar activation. A random UUID minted once and
    /// persisted; it survives app reinstalls via the Keychain. (We deliberately don't
    /// read the hardware serial — a stored id is enough for binding and avoids IOKit.)
    ///
    /// If the Keychain write fails, we still cache the minted id in-process so the
    /// identity stays **stable for this session** — otherwise each access would mint a
    /// different UUID and break the activate↔validate device match.
    private static var cachedDeviceID: String?
    public static var deviceID: String {
        if let existing = Keychain.string(for: Account.deviceID) { return existing }
        if let cached = cachedDeviceID { return cached }
        let id = UUID().uuidString
        cachedDeviceID = id
        Keychain.set(id, for: Account.deviceID)
        return id
    }

    /// Forget the license on this Mac but **keep the trial history** — so "Deactivate"
    /// can't be used to mint a fresh trial.
    public static func clearLicense() {
        licenseKey = nil
        activationID = nil
        requiresActivation = false
        isRevoked = false
        lastValidatedAt = nil
    }

    /// Wipe license + trial. Keeps `lastSeenAt` and `deviceID` so the rollback
    /// watermark and device identity survive (used by tests / a hard reset).
    public static func clearAll() {
        clearLicense()
        trialStartedAt = nil
    }

    // MARK: - Date helpers (stored as epoch-seconds strings)

    private static func date(for account: String) -> Date? {
        guard let raw = Keychain.string(for: account), let secs = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    private static func setDate(_ date: Date?, for account: String) {
        Keychain.set(date.map { String($0.timeIntervalSince1970) }, for: account)
    }
}
