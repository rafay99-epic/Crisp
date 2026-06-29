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
        case failed(String)

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
        LicenseGate.recordSeen()
        state = mappedEntitlement()
        guard Channel.licensingEnabled else { return }
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
        LicenseGate.startTrialIfNeeded()
        state = mappedEntitlement()
    }

    // MARK: - Activation

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "Enter your license key."; return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let result = try await polar.validate(key: key)
            guard result.granted else {
                message = "That license has been revoked or disabled. Contact support if that’s unexpected."
                return
            }
            if result.requiresActivation {
                try await bindDevice(key: key)
            } else {
                LicenseStorage.activationID = nil
                LicenseStorage.requiresActivation = false
            }
            LicenseStorage.licenseKey = key
            LicenseStorage.isRevoked = false
            LicenseStorage.lastValidatedAt = Date()
            message = "License activated — thank you!"
            state = mappedEntitlement()
        } catch let error as PolarError {
            message = error.errorDescription
            Self.log.error("activation failed: \(error.localizedDescription, privacy: .public)")
        } catch let urlError as URLError {
            message = urlError.code == .notConnectedToInternet
                ? "No internet connection. Connect and try again."
                : "Couldn’t reach the license server. Please try again."
        } catch {
            message = "Something went wrong activating your license. Please try again."
        }
    }

    /// Bind a device-locked key to this Mac — reusing a prior activation if it still
    /// validates, otherwise activating fresh.
    private func bindDevice(key: String) async throws {
        if let activationID = LicenseStorage.activationID,
           (try? await polar.validate(key: key, activationID: activationID)) == true {
            LicenseStorage.requiresActivation = true
            return
        }
        let label = Host.current().localizedName ?? "Mac"
        let result = try await polar.activate(key: key, label: label, deviceID: LicenseStorage.deviceID)
        LicenseStorage.activationID = result.activationID
        LicenseStorage.requiresActivation = true
    }

    // MARK: - Deactivation

    func deactivate() async {
        isWorking = true
        defer { isWorking = false }
        // Best-effort: free this device's Polar seat so it isn't orphaned.
        if LicenseStorage.requiresActivation,
           let key = LicenseStorage.licenseKey,
           let activationID = LicenseStorage.activationID {
            try? await polar.deactivate(key: key, activationID: activationID)
        }
        LicenseStorage.clearLicense()
        message = nil
        state = mappedEntitlement()
    }

    // MARK: - Periodic re-validation

    /// Re-validate a stored license when it's been a week, so a refunded/revoked
    /// license stops working once the user is next online. A network/server failure is
    /// tolerated (offline grace) — only an explicit not-granted revokes.
    private func revalidateIfDue() async {
        guard let key = LicenseStorage.licenseKey, !LicenseStorage.isRevoked else { return }
        if let last = LicenseStorage.lastValidatedAt,
           Date().timeIntervalSince(last) < Self.revalidationInterval { return }
        do {
            let granted: Bool
            if LicenseStorage.requiresActivation, let activationID = LicenseStorage.activationID {
                granted = try await polar.validate(key: key, activationID: activationID)
            } else {
                granted = try await polar.validate(key: key).granted
            }
            if granted {
                LicenseStorage.lastValidatedAt = Date()
            } else {
                LicenseStorage.isRevoked = true
                state = .revoked
            }
        } catch {
            Self.log.info("license re-validation deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Links & display

    func openCheckout() { NSWorkspace.shared.open(PolarConfig.checkoutURL) }
    func openPortal() { NSWorkspace.shared.open(PolarConfig.portalURL) }

    /// Masked form of the stored key for display, e.g. "•••• •••• 1A2B".
    var maskedKey: String? {
        guard let key = LicenseStorage.licenseKey, key.count >= 4 else { return nil }
        return "•••• •••• " + key.suffix(4)
    }
}
