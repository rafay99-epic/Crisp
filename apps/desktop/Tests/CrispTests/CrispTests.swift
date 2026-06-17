import XCTest
@testable import Crisp

final class CrispTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isVersion("0.11", newerThan: "0.10"))
        XCTAssertTrue(Updater.isVersion("1.0", newerThan: "0.99"))
        XCTAssertFalse(Updater.isVersion("0.10", newerThan: "0.10"))
        XCTAssertFalse(Updater.isVersion("0.9", newerThan: "0.10"))
    }

    func testBuildNumberParsing() {
        XCTAssertEqual(Updater.buildNumber(in: "Crisp Nightly · build 42"), 42)
        XCTAssertEqual(Updater.buildNumber(in: "Crisp 0.10"), 0)
        XCTAssertEqual(Updater.buildNumber(in: nil), 0)
    }

    func testStrengthPresetsAreOrdered() {
        // More aggressive presets must cut shorter pauses than gentler ones.
        XCTAssertGreaterThan(Strength.gentle.pause, Strength.balanced.pause)
        XCTAssertGreaterThan(Strength.balanced.pause, Strength.aggressive.pause)
        XCTAssertGreaterThan(Strength.aggressive.pause, Strength.veryAggressive.pause)
    }

    func testChannelDefaultsToStable() {
        // With no CrispChannel key in the test bundle, current resolves to stable.
        XCTAssertEqual(Channel.stable.bundleSuffix, "")
        XCTAssertNil(Channel.stable.badge)
        XCTAssertFalse(Channel.dev.updatesEnabled)
        XCTAssertTrue(Channel.nightly.isPrerelease)
    }

    func testTimeFormatting() {
        XCTAssertEqual(formatTime(0), "0:00")
        XCTAssertEqual(formatTime(65), "1:05")
        XCTAssertEqual(formatTime(600), "10:00")
    }

    func testChannelDataDirIsolatedPerChannel() {
        // Each channel keeps its downloaded model in its own home dir, so the
        // three installs never share (or clobber) one another's data.
        XCTAssertTrue(Channel.stable.dataDirectory.path.hasSuffix("/.crisp"))
        XCTAssertTrue(Channel.nightly.dataDirectory.path.hasSuffix("/.crisp-nightly"))
        XCTAssertTrue(Channel.dev.dataDirectory.path.hasSuffix("/.crisp-dev"))
        XCTAssertNotEqual(Channel.stable.dataDirectory, Channel.dev.dataDirectory)
    }
}
