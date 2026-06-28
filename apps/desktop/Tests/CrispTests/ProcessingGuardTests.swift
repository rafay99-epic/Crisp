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

    func testRefuseIsSafeWithoutWindow() {
        // Headless: no main window and no NSApp, so `refuse()` takes the windowless path
        // and must not crash or raise the in-window sheet flag (it would carry the notice
        // via a standalone alert when a real app is running). Just assert it's a safe no-op.
        guardState.mainWindow = nil
        guardState.showBlockedNotice = false
        guardState.refuse()
        XCTAssertFalse(guardState.showBlockedNotice,
                       "the SwiftUI sheet flag is only set when a window can host it")
    }
}
