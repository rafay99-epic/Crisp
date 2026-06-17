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
        var cfg = EngineConfig.defaults
        cfg.pauseThreshold = 1.25; cfg.silenceFloorDB = -22; cfg.breathingRoom = 0.2; cfg.minKeep = 0.3
        let p = Strength.custom.parameters(using: cfg)
        XCTAssertEqual(p.pause, 1.25)
        XCTAssertEqual(p.noiseDB, -22)
        XCTAssertEqual(p.keepPause, 0.2)
        XCTAssertEqual(p.minKeep, 0.3)
    }

    func testPresetStrengthIgnoresCustomConfig() {
        // A preset must use its own pause/keep + the engine defaults for the rest,
        // regardless of what the user saved for Custom.
        var cfg = EngineConfig.defaults
        cfg.pauseThreshold = 9; cfg.silenceFloorDB = 0; cfg.breathingRoom = 9; cfg.minKeep = 9
        let p = Strength.aggressive.parameters(using: cfg)
        XCTAssertEqual(p.pause, Strength.aggressive.pause)
        XCTAssertEqual(p.keepPause, Strength.aggressive.keepPause)
        XCTAssertEqual(p.noiseDB, EngineConfig.defaults.silenceFloorDB)
        XCTAssertEqual(p.minKeep, EngineConfig.defaults.minKeep)
    }

    func testDefaultEncoderIsHardwareHEVC() {
        // Every Apple-Silicon Mac has a HEVC media engine, so hardware HEVC is the
        // fast default (the pipeline falls back to software if it ever fails).
        XCTAssertEqual(EngineConfig.defaults.videoCodec, "hevc")
        XCTAssertTrue(EngineConfig.defaults.hardwareEncoding)
        XCTAssertEqual(EngineConfig.defaults.videoQuality, "high")
    }

    func testEncoderChoicesCarryThroughRegardlessOfStrength() {
        // Encoder settings apply to every clean, independent of the cut strength.
        var cfg = EngineConfig.defaults
        cfg.videoCodec = "hevc"; cfg.hardwareEncoding = true
        cfg.videoQuality = "maximum"; cfg.audioCodec = "opus"; cfg.audioBitrateKbps = 256
        for strength in [Strength.gentle, .aggressive, .custom] {
            let p = strength.parameters(using: cfg)
            XCTAssertEqual(p.videoCodec, "hevc")
            XCTAssertTrue(p.hardwareEncoding)
            XCTAssertEqual(p.videoQuality, "maximum")
            XCTAssertEqual(p.audioCodec, "opus")
            XCTAssertEqual(p.audioBitrateKbps, 256)
        }
    }

    func testBackupOriginalDefaultsOnAndCarriesThrough() {
        // Backing up the original is on by default (the safety net), and the choice
        // reaches the engine parameters for every strength.
        XCTAssertTrue(EngineConfig.defaults.backupOriginal)
        var cfg = EngineConfig.defaults
        cfg.backupOriginal = false
        for strength in [Strength.gentle, .aggressive, .custom] {
            XCTAssertFalse(strength.parameters(using: cfg).backupOriginal)
        }
    }

    func testBackupDirectoryIsDatedUnderChannelHome() {
        // Originals land in a date-stamped folder under the channel's data home.
        let date = Date(timeIntervalSince1970: 1_750_000_000)  // 2025-06-15 UTC-ish
        let dir = CleanModel.backupDirectory(for: date)
        XCTAssertTrue(dir.deletingLastPathComponent().path.hasSuffix("/Originals"))
        XCTAssertTrue(dir.path.hasPrefix(Channel.current.dataDirectory.path))
        // The leaf is a yyyy-MM-dd day folder.
        XCTAssertNotNil(dir.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression))
    }

    func testEngineConfigForwardCompatFillsMissingKeys() throws {
        // A file from an older version (only the v1 cutting keys, no encoder keys):
        // present keys are preserved, every missing key defaults — so an update
        // never disturbs the user's saved values.
        let json = Data("""
        { "version": 1, "pauseThreshold": 0.9, "silenceFloorDB": -25, "breathingRoom": 0.07 }
        """.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: json)
        XCTAssertEqual(cfg.pauseThreshold, 0.9)         // preserved
        XCTAssertEqual(cfg.breathingRoom, 0.07)         // preserved
        XCTAssertEqual(cfg.minKeep, EngineConfig.defaults.minKeep)        // missing → default
        XCTAssertEqual(cfg.videoCodec, EngineConfig.defaults.videoCodec)  // new key → default
        XCTAssertEqual(cfg.audioCodec, EngineConfig.defaults.audioCodec)  // new key → default
        XCTAssertEqual(cfg.audioBitrateKbps, EngineConfig.defaults.audioBitrateKbps)
        XCTAssertEqual(cfg.backupOriginal, EngineConfig.defaults.backupOriginal)  // new key → default

        // An empty object decodes to all defaults (not a failure).
        let empty = try JSONDecoder().decode(EngineConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, EngineConfig.defaults)
    }
}
