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

    // MARK: - Custom settings

    func testCustomStrengthUsesConfigValues() {
        let cfg = EngineConfig(version: 1, pauseThreshold: 1.25, silenceFloorDB: -22,
                               breathingRoom: 0.2, minKeep: 0.3)
        let p = Strength.custom.parameters(using: cfg)
        XCTAssertEqual(p.pause, 1.25)
        XCTAssertEqual(p.noiseDB, -22)
        XCTAssertEqual(p.keepPause, 0.2)
        XCTAssertEqual(p.minKeep, 0.3)
    }

    func testPresetStrengthIgnoresCustomConfig() {
        // A preset must use its own pause/keep + the engine defaults for the rest,
        // regardless of what the user saved for Custom.
        let cfg = EngineConfig(version: 1, pauseThreshold: 9, silenceFloorDB: 0,
                               breathingRoom: 9, minKeep: 9)
        let p = Strength.aggressive.parameters(using: cfg)
        XCTAssertEqual(p.pause, Strength.aggressive.pause)
        XCTAssertEqual(p.keepPause, Strength.aggressive.keepPause)
        XCTAssertEqual(p.noiseDB, EngineConfig.defaults.silenceFloorDB)
        XCTAssertEqual(p.minKeep, EngineConfig.defaults.minKeep)
    }

    func testEngineConfigForwardCompatFillsMissingKeys() throws {
        // A file from an older version is missing `minKeep`: it should default,
        // while every key that IS present is preserved (the update-safety guarantee).
        let json = Data("""
        { "version": 1, "pauseThreshold": 0.9, "silenceFloorDB": -25, "breathingRoom": 0.07 }
        """.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: json)
        XCTAssertEqual(cfg.pauseThreshold, 0.9)         // preserved
        XCTAssertEqual(cfg.silenceFloorDB, -25)         // preserved
        XCTAssertEqual(cfg.breathingRoom, 0.07)         // preserved
        XCTAssertEqual(cfg.minKeep, EngineConfig.defaults.minKeep)  // missing → default

        // An empty object decodes to all defaults (not a failure).
        let empty = try JSONDecoder().decode(EngineConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, EngineConfig.defaults)
    }
}
