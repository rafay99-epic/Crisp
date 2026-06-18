import XCTest
import CrispCore
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

    func testOutputContainerDefaultsToAutoAndCarriesThrough() {
        // Default is "auto" (match the input's container); whatever's chosen reaches
        // the engine parameters for every strength.
        XCTAssertEqual(EngineConfig.defaults.outputContainer, "auto")
        var cfg = EngineConfig.defaults
        cfg.outputContainer = "mkv"
        for strength in [Strength.gentle, .aggressive, .custom] {
            XCTAssertEqual(strength.parameters(using: cfg).outputContainer, "mkv")
        }
    }

    func testWebMForcesItsOwnCodecs() {
        // WebM's own codec rule drives the Settings UI (it disables the codec
        // controls); the other containers leave them alone.
        XCTAssertTrue(OutputContainer.webm.forcesOwnCodecs)
        for c in [OutputContainer.auto, .mp4, .mkv, .mov, .m4v, .ts] {
            XCTAssertFalse(c.forcesOwnCodecs, "\(c.rawValue) should not force codecs")
        }
    }

    func testOutputContainerRawValuesMatchEngineFlag() {
        // The enum rawValues must be exactly the strings the engine's --container
        // flag accepts, since the picker tags feed straight into the CLI.
        XCTAssertEqual(OutputContainer.allCases.map(\.rawValue),
                       ["auto", "mp4", "mkv", "mov", "m4v", "ts", "webm"])
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
        let dir = CleanRunner.backupDirectory(for: date)
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
        XCTAssertEqual(cfg.outputContainer, EngineConfig.defaults.outputContainer)  // new key → default
        XCTAssertEqual(cfg.backupOriginal, EngineConfig.defaults.backupOriginal)  // new key → default

        // An empty object decodes to all defaults (not a failure).
        let empty = try JSONDecoder().decode(EngineConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, EngineConfig.defaults)
    }

    // MARK: - Watch folder config

    func testWatchFieldsDefaultOffAndRoundTrip() throws {
        // Opt-in by default: watching is off, no folder, fillers on (matches the UI).
        XCTAssertFalse(EngineConfig.defaults.watchEnabled)
        XCTAssertEqual(EngineConfig.defaults.watchFolderPath, "")
        XCTAssertTrue(EngineConfig.defaults.watchRemoveFillers)

        var cfg = EngineConfig.defaults
        cfg.watchEnabled = true
        cfg.watchFolderPath = "/Users/me/Recordings"
        cfg.watchRemoveFillers = false
        let round = try JSONDecoder().decode(EngineConfig.self,
                                             from: JSONEncoder().encode(cfg))
        XCTAssertEqual(round, cfg)

        // A file predating the watch keys fills them with defaults (forward-compat).
        let legacy = Data(#"{ "version": 2, "pauseThreshold": 0.4 }"#.utf8)
        let decoded = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertFalse(decoded.watchEnabled)
        XCTAssertEqual(decoded.watchFolderPath, "")
        XCTAssertTrue(decoded.watchRemoveFillers)
    }

    func testCustomConfigIsDistinguishableFromDefaults() {
        // Onboarding's "your settings were detected" gate is config != defaults:
        // a brand-new/default config must compare equal, a customized one must not.
        XCTAssertEqual(EngineConfig.defaults, EngineConfig.defaults)
        var custom = EngineConfig.defaults
        custom.videoQuality = "maximum"
        XCTAssertNotEqual(custom, EngineConfig.defaults)
    }

    // MARK: - CleanRunner argument mapping

    func testCleanRunnerArgumentsForFillerRun() {
        let params = Strength.aggressive.parameters(using: .defaults)
        let opts = CleanRunner.Options(modelPath: "/models/ggml.bin",
                                       removeFillers: true,
                                       backupDirectory: URL(fileURLWithPath: "/tmp/orig"))
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params, options: opts)
        XCTAssertEqual(args.first, "/eng/clean_video.py")
        XCTAssertEqual(args[1], "/v/in.mp4")
        XCTAssertTrue(args.contains("--ndjson"))
        XCTAssertTrue(args.contains("--hardware"))                 // defaults enable HW
        XCTAssertEqual(valueAfter("--model", in: args), "/models/ggml.bin")
        XCTAssertEqual(valueAfter("--backup-dir", in: args), "/tmp/orig")
        XCTAssertFalse(args.contains("--no-fillers"))
        XCTAssertFalse(args.contains("--no-backup"))
        XCTAssertEqual(valueAfter("--pause", in: args), String(Strength.aggressive.pause))
    }

    func testCleanRunnerArgumentsForPausesOnlyNoBackup() {
        let params = Strength.gentle.parameters(using: .defaults)
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false, backupDirectory: nil)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mov"),
                                         parameters: params, options: opts)
        XCTAssertTrue(args.contains("--no-fillers"))               // fillers off
        XCTAssertFalse(args.contains("--model"))                   // ⇒ no model flag
        XCTAssertTrue(args.contains("--no-backup"))                // no backup dir
        XCTAssertFalse(args.contains("--backup-dir"))
    }

    // MARK: - Video filtering (drop zone / Finder Service / watch folder)

    func testVideoExtensionsCoverContainersNotOthers() {
        for ext in ["mov", "mp4", "mkv", "m4v", "avi", "webm", "flv"] {
            XCTAssertTrue(CleanRunner.videoExtensions.contains(ext), "\(ext) should be cleanable")
        }
        for ext in ["txt", "png", "mp3", "pdf", ""] {
            XCTAssertFalse(CleanRunner.videoExtensions.contains(ext), "\(ext) should be ignored")
        }
    }

    // MARK: - Shortcuts intent strength mapping

    func testIntentStrengthChoiceMapsToPreset() {
        XCTAssertEqual(CleanStrengthChoice.gentle.strength, .gentle)
        XCTAssertEqual(CleanStrengthChoice.balanced.strength, .balanced)
        XCTAssertEqual(CleanStrengthChoice.aggressive.strength, .aggressive)
        XCTAssertEqual(CleanStrengthChoice.veryAggressive.strength, .veryAggressive)
    }

    /// The argument value immediately following `flag`, or nil if absent.
    private func valueAfter(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
