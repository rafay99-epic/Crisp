import XCTest
@testable import Crisp

/// The quit/close guard's decision logic: `busy` must mirror the live run-flag probe so
/// the AppDelegate refuses termination exactly while a render is in flight, and the
/// explanatory notice is raised on a refusal.
@MainActor
final class ProcessingGuardTests: XCTestCase {
    private let guardState = ProcessingGuard.shared

    override func tearDown() {
        // Leave the shared singleton inert for any other test.
        guardState.isBusyProbe = { false }
        guardState.showBlockedNotice = false
        super.tearDown()
    }

    func testNotBusyByDefault() {
        guardState.isBusyProbe = { false }
        XCTAssertFalse(guardState.busy)
    }

    func testBusyReadsLiveProbe() {
        var running = false
        guardState.isBusyProbe = { running }
        XCTAssertFalse(guardState.busy)
        running = true
        XCTAssertTrue(guardState.busy, "busy must reflect the probe live, not a cached snapshot")
        running = false
        XCTAssertFalse(guardState.busy)
    }

    func testRefuseRaisesNotice() {
        guardState.showBlockedNotice = false
        guardState.refuse()
        XCTAssertTrue(guardState.showBlockedNotice)
    }
}
