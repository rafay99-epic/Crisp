import XCTest
@testable import CrispCore

/// Unit tests for the licensing entitlement logic. These exercise the **pure**
/// `LicenseGate.entitlement(...)` (no Keychain / network) plus the flag-off safety
/// guarantee, so they're deterministic under `swift test`.
final class LicensingTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let trialDays = PolarConfig.trialDays   // 14

    private func entitlement(revoked: Bool = false,
                             key: Bool = false,
                             trialStart: Date? = nil,
                             lastSeen: Date? = nil,
                             now: Date) -> Entitlement {
        LicenseGate.entitlement(isRevoked: revoked, hasLicenseKey: key,
                                trialStartedAt: trialStart, lastSeenAt: lastSeen,
                                now: now, trialDays: trialDays)
    }

    // MARK: - State derivation

    func testUnlicensedWhenNothingStored() {
        XCTAssertEqual(entitlement(now: Date()), .unlicensed)
    }

    func testLicensedWhenKeyPresent() {
        XCTAssertEqual(entitlement(key: true, now: Date()), .licensed)
    }

    func testRevokedTakesPrecedenceOverKey() {
        // A revoked flag wins even if a key is still stored.
        XCTAssertEqual(entitlement(revoked: true, key: true, now: Date()), .revoked)
    }

    func testTrialFullOnDayZero() {
        let start = Date()
        XCTAssertEqual(entitlement(trialStart: start, now: start), .trial(daysLeft: trialDays))
    }

    func testTrialCountsDown() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(3 * day)   // 3 days in
        XCTAssertEqual(entitlement(trialStart: start, now: now), .trial(daysLeft: trialDays - 3))
    }

    func testTrialExpiresExactlyAtTrialDays() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(Double(trialDays) * day)
        XCTAssertEqual(entitlement(trialStart: start, now: now), .trialExpired)
    }

    // MARK: - Clock-rollback resistance

    func testClockRollbackCannotExtendTrial() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // The app has previously been seen 13 days in…
        let lastSeen = start.addingTimeInterval(13 * day)
        // …and the user winds the clock back to day 1. Effective elapsed should still
        // be measured from the high-watermark (13 days), not the rolled-back `now`.
        let rolledBackNow = start.addingTimeInterval(1 * day)
        XCTAssertEqual(entitlement(trialStart: start, lastSeen: lastSeen, now: rolledBackNow),
                       .trial(daysLeft: trialDays - 13))
    }

    func testRollbackPastExpiryStaysExpired() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let lastSeen = start.addingTimeInterval(Double(trialDays + 5) * day)
        let rolledBackNow = start.addingTimeInterval(2 * day)
        XCTAssertEqual(entitlement(trialStart: start, lastSeen: lastSeen, now: rolledBackNow),
                       .trialExpired)
    }

    // MARK: - Entitlement → clean permission

    func testAllowsCleanByState() {
        XCTAssertTrue(Entitlement.licensed.allowsClean)
        XCTAssertTrue(Entitlement.trial(daysLeft: 1).allowsClean)
        XCTAssertFalse(Entitlement.trialExpired.allowsClean)
        XCTAssertFalse(Entitlement.unlicensed.allowsClean)
        XCTAssertFalse(Entitlement.revoked.allowsClean)
    }

    // MARK: - Feature-flag safety

    func testFeatureShipsDarkByDefault() {
        // No CrispLicensingEnabled Info.plist key under `swift test` ⇒ off.
        XCTAssertFalse(Channel.licensingEnabled)
    }

    func testGateAllowsEverythingWhenDisabled() {
        // With the flag off, the gate must never block — regardless of stored state.
        XCTAssertTrue(LicenseGate.allowsClean())
        XCTAssertNil(LicenseGate.blockReason())
        XCTAssertNoThrow(try LicenseGate.checkClean())
    }

    func testDarkShipBypassesEvenBlockedEntitlement() {
        // The stronger guarantee: with the feature disabled, cleaning is allowed for
        // ANY entitlement — including the blocked ones. Tested via the pure rule so it
        // needs no Keychain (and can't pollute the real Stable keychain on the runner).
        for blocked in [Entitlement.unlicensed, .trialExpired, .revoked] {
            XCTAssertTrue(LicenseGate.cleanAllowed(enabled: false, entitlement: blocked),
                          "disabled gate must allow \(blocked)")
            XCTAssertFalse(LicenseGate.cleanAllowed(enabled: true, entitlement: blocked),
                           "enabled gate must block \(blocked)")
        }
        XCTAssertTrue(LicenseGate.cleanAllowed(enabled: true, entitlement: .licensed))
        XCTAssertTrue(LicenseGate.cleanAllowed(enabled: true, entitlement: .trial(daysLeft: 1)))
    }

    // MARK: - Product contract

    func testTrialLengthContractIsFourteenDays() {
        // Literal pin so changing the production constant trips this test (CodeRabbit).
        XCTAssertEqual(PolarConfig.trialDays, 14)
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LicenseGate.entitlement(isRevoked: false, hasLicenseKey: false,
                                               trialStartedAt: start, lastSeenAt: nil,
                                               now: start, trialDays: 14),
                       .trial(daysLeft: 14))
        XCTAssertEqual(LicenseGate.entitlement(isRevoked: false, hasLicenseKey: false,
                                               trialStartedAt: start, lastSeenAt: nil,
                                               now: start.addingTimeInterval(14 * 86_400), trialDays: 14),
                       .trialExpired)
    }
}
