import Foundation
import AppKit
import CrispCore

/// UI-facing licensing store — the app analogue of `ModelStore`. It maps the stored
/// entitlement (`LicenseGate` / `LicenseStorage` in CrispCore) onto an `@Observable`
/// `State` the views bind to, and owns the network operations (activate, deactivate,
/// periodic re-validation) against `PolarService`.
///
/// State is derived from stored facts each `refresh()`; the network is touched only to
/// activate a key the user enters, to free a seat on deactivate, or to re-validate a
/// stored license at most weekly. Everything no-ops while `Channel.licensingEnabled`
/// is false, so with the feature dark this store just reports `.unlicensed`/trial for
/// display and never reaches the network.
@MainActor
@Observable
final class LicenseStore {
    enum State: Equatable {
        case checking
        case licensed
        case trial(daysLeft: Int)
        case trialExpired
        case unlicensed
        case revoked

        /// Licensed and in-trial may clean; everything else can't. (The real gate is
        /// `LicenseGate`; this mirrors it for the UI.)
        var canClean: Bool {
            switch self {
            case .licensed, .trial: return true
            default:                return false
            }
        }
    }

    private(set) var state: State = .checking
    /// A network operation (activate / re-validate / deactivate) is in flight.
    private(set) var isWorking = false
    /// Last user-facing message from an activation attempt (success or failure).
    private(set) var message: String?

    private let polar = PolarService()
    private static let log = AppInfo.logger("license")
    /// Re-validate a stored license at most this often.
    private static let revalidationInterval: TimeInterval = 7 * 86_400

    // MARK: - Derivation

    /// Recompute state from stored entitlement; if licensed and due, re-validate online.
    /// Called from the launch `.task`, mirroring `ModelStore.refresh()`.
    func refresh() async {
        // When dark, only read state for display — never write the rollback watermark
        // (that would mutate stored state, breaking the "behaves as today" contract).
        guard Channel.licensingEnabled else { state = mappedEntitlement(); return }
        LicenseGate.recordSeen()
        state = mappedEntitlement()
        Self.log.info("license: launch state — \(Self.label(state), privacy: .public)")
        await revalidateIfDue()
    }

    private func mappedEntitlement() -> State {
        switch LicenseGate.currentEntitlement() {
        case .licensed:      return .licensed
        case .trial(let d):  return .trial(daysLeft: d)
        case .trialExpired:  return .trialExpired
        case .unlicensed:    return .unlicensed
        case .revoked:       return .revoked
        }
    }

    // MARK: - Trial

    func startTrial() {
        guard Channel.licensingEnabled else { return }
        LicenseGate.startTrialIfNeeded()
        state = mappedEntitlement()
        Self.log.info("license: trial started — \(Self.label(state), privacy: .public)")
    }

    // MARK: - Activation

    func activate(key rawKey: String) async {
        // Honour the dark-ship contract, and guard against re-entry so rapid taps
        // can't enqueue overlapping activations (which would burn extra Polar seats).
        guard Channel.licensingEnabled, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        Self.log.info("license: manual activation requested")
        await performActivation(key: rawKey)
    }

    /// Finish a purchase automatically after the `crisp://activate?checkout_id=…` deep
    /// link: resolve the key from the serverless lookup, then activate it — no copy-paste.
    func activateFromCheckout(checkoutID: String) async {
        guard Channel.licensingEnabled, !isWorking else { return }
        isWorking = true
        message = "Finishing your purchase…"
        defer { isWorking = false }
        Self.log.info("license: auto-activation from checkout \(checkoutID.prefix(14), privacy: .public)…")
        do {
            let key = try await LicenseLookup().key(forCheckout: checkoutID)
            await performActivation(key: key)
        } catch {
            // Lookup not ready/configured — fall back to manual entry rather than fail hard.
            message = "We couldn’t finish automatically — paste the key from your confirmation email below."
            Self.log.error("checkout lookup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The shared activate core (validate → bind device → persist). Assumes the caller
    /// owns the `isWorking`/re-entry guard.
    private func performActivation(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "Enter your license key."; return }
        do {
            let result = try await polar.validate(key: key)
            guard result.granted else {
                message = "That license has been revoked or disabled. Contact support if that’s unexpected."
                Self.log.error("license: key not granted (revoked/disabled)")
                return
            }
            if result.requiresActivation {
                try await bindDevice(key: key)
            } else {
                LicenseStorage.activationID = nil
                LicenseStorage.requiresActivation = false
            }
            LicenseStorage.licenseKey = key
            // Confirm it actually persisted — a dropped Keychain write must not be
            // reported as a successful activation (the gate would later see no key).
            guard LicenseStorage.licenseKey == key else {
                message = "Couldn’t save your license on this Mac (Keychain write failed). Please try again."
                Self.log.error("license: keychain write failed — activation not persisted")
                return
            }
            LicenseStorage.isRevoked = false
            LicenseStorage.lastValidatedAt = Date()
            message = "License activated — thank you!"
            state = mappedEntitlement()
            Self.log.info("license: activated — \(result.requiresActivation ? "device-bound" : "unlimited", privacy: .public)")
        } catch let error as PolarError {
            message = error.errorDescription
            Self.log.error("license: activation failed — \(error.localizedDescription, privacy: .public)")
        } catch let urlError as URLError {
            message = urlError.code == .notConnectedToInternet
                ? "No internet connection. Connect and try again."
                : "Couldn’t reach the license server. Please try again."
            Self.log.error("license: activation network error — URLError \(urlError.code.rawValue, privacy: .public)")
        } catch {
            message = "Something went wrong activating your license. Please try again."
            Self.log.error("license: activation failed — unexpected error")
        }
    }

    /// Bind a device-locked key to this Mac — reusing a prior activation if it still
    /// validates, otherwise activating fresh.
    private func bindDevice(key: String) async throws {
        if let activationID = LicenseStorage.activationID,
           (try? await polar.validate(key: key, activationID: activationID)) == true {
            LicenseStorage.requiresActivation = true
            Self.log.info("license: reused existing device activation")
            return
        }
        // A non-PII label: the user's computer name often contains their real name, so
        // we send a generic label disambiguated by a short slice of the random device id.
        let label = "Mac · \(LicenseStorage.deviceID.prefix(8))"
        let result = try await polar.activate(key: key, label: label, deviceID: LicenseStorage.deviceID)
        LicenseStorage.activationID = result.activationID
        LicenseStorage.requiresActivation = true
        Self.log.info("license: device activated — \(result.activationID, privacy: .public)")
    }

    // MARK: - Deactivation

    func deactivate() async {
        guard Channel.licensingEnabled, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        Self.log.info("license: deactivating this Mac")
        // Free this device's Polar seat first. If that fails (e.g. offline), keep the
        // stored key + activation id so the user can retry — clearing them now would
        // both orphan the seat and discard the data needed to release it later.
        if LicenseStorage.requiresActivation,
           let key = LicenseStorage.licenseKey,
           let activationID = LicenseStorage.activationID {
            do {
                try await polar.deactivate(key: key, activationID: activationID)
            } catch {
                message = "Couldn’t reach the license server to release this Mac. Try again when you’re online."
                Self.log.error("license: deactivation failed — seat not released, keeping local license")
                return
            }
        }
        LicenseStorage.clearLicense()
        message = nil
        state = mappedEntitlement()
        Self.log.info("license: deactivated and cleared on this Mac")
    }

    // MARK: - Periodic re-validation

    /// Re-validate a stored license when it's been a week, so a refunded/revoked
    /// license stops working once the user is next online. A network/server failure is
    /// tolerated (offline grace) — only an explicit not-granted revokes.
    private func revalidateIfDue() async {
        guard let key = LicenseStorage.licenseKey, !LicenseStorage.isRevoked else { return }
        if let last = LicenseStorage.lastValidatedAt,
           Date().timeIntervalSince(last) < Self.revalidationInterval { return }
        Self.log.info("license: weekly re-validation with Polar")
        do {
            let granted: Bool
            if LicenseStorage.requiresActivation, let activationID = LicenseStorage.activationID {
                granted = try await polar.validate(key: key, activationID: activationID)
            } else {
                granted = try await polar.validate(key: key).granted
            }
            // The key may have been changed/removed (deactivate, re-activate) while this
            // request was in flight — don't apply a stale verdict to a different key.
            guard LicenseStorage.licenseKey == key else {
                Self.log.info("license: re-validation result discarded — key changed mid-flight")
                return
            }
            if granted {
                LicenseStorage.lastValidatedAt = Date()
                Self.log.info("license: re-validation ok — still active")
            } else {
                LicenseStorage.isRevoked = true
                state = .revoked
                Self.log.error("license: revoked by Polar — locking the app")
            }
        } catch {
            Self.log.info("license: re-validation deferred (offline grace) — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Links & display

    func openCheckout() {
        guard Channel.licensingEnabled, let url = PolarConfig.checkoutURL else { return }
        NSWorkspace.shared.open(url)
    }
    func openPortal() {
        guard Channel.licensingEnabled, let url = PolarConfig.portalURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Masked form of the stored key for display, e.g. "•••• •••• 1A2B".
    var maskedKey: String? {
        guard let key = LicenseStorage.licenseKey, key.count >= 4 else { return nil }
        return "•••• •••• " + key.suffix(4)
    }

    /// Short, log-safe description of a state (never includes the key).
    private static func label(_ state: State) -> String {
        switch state {
        case .checking:      return "checking"
        case .licensed:      return "licensed"
        case .trial(let d):  return "trial (\(d)d left)"
        case .trialExpired:  return "trial expired"
        case .unlicensed:    return "unlicensed"
        case .revoked:       return "revoked"
        }
    }
}
