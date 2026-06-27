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

    func testHistoryRoundTripNewestFirstAndLimit() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = (0..<5).map { i in
            HistoryEntry(date: base.addingTimeInterval(Double(i)),
                         inputPath: "/in/clip\(i).mp4", outputPath: "/out/clip\(i)_cleaned.mp4",
                         origSeconds: 100, newSeconds: 70, savedSeconds: 30,
                         fillers: i, pauses: i * 2)
        }
        // Lines are appended in chronological order.
        let text = entries.compactMap { HistoryStore.encodeLine($0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined()
        let parsed = HistoryStore.parse(text, limit: 3)
        // Newest first, capped at the limit.
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed.map(\.inputPath), ["/in/clip4.mp4", "/in/clip3.mp4", "/in/clip2.mp4"])
        // Fields survive the round trip (incl. the ISO-8601 date).
        XCTAssertEqual(parsed.first?.fillers, 4)
        XCTAssertEqual(parsed.first?.pauses, 8)
        XCTAssertEqual(parsed.first?.date, base.addingTimeInterval(4))
    }

    func testHistoryParseSkipsMalformedLines() {
        let good = HistoryEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                                inputPath: "/in/a.mp4", outputPath: "/out/a.mp4",
                                origSeconds: 10, newSeconds: 8, savedSeconds: 2, fillers: 1, pauses: 1)
        let line = String(data: HistoryStore.encodeLine(good)!, encoding: .utf8)!
        let text = "not json\n" + line + "{ partial\n"
        let parsed = HistoryStore.parse(text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.inputPath, "/in/a.mp4")
    }

    func testHistoryDecodesLinesWrittenBeforeBackupField() {
        // A history.jsonl line from before the `backup` field was added must still
        // decode (Optional → missing key is nil), or every old entry would vanish.
        let old = #"{"id":"\#(UUID().uuidString)","date":"2026-06-19T12:00:00Z","inputPath":"/in/a.mp4","outputPath":"/out/a.mp4","origSeconds":10,"newSeconds":8,"savedSeconds":2,"fillers":1,"pauses":1}"#
        let parsed = HistoryStore.parse(old + "\n")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNil(parsed.first?.backup)
        XCTAssertNil(parsed.first?.backupURL)
        XCTAssertEqual(parsed.first?.inputPath, "/in/a.mp4")
    }

    func testHistoryRoundTripsBackupPath() {
        let entry = HistoryEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                                 inputPath: "/in/a.mp4", outputPath: "/out/a.mp4",
                                 origSeconds: 10, newSeconds: 8, savedSeconds: 2,
                                 fillers: 1, pauses: 1, backup: "/Originals/2026-06-19/a.mp4")
        let line = String(data: HistoryStore.encodeLine(entry)!, encoding: .utf8)!
        let parsed = HistoryStore.parse(line)
        XCTAssertEqual(parsed.first?.backup, "/Originals/2026-06-19/a.mp4")
        XCTAssertEqual(parsed.first?.backupURL?.lastPathComponent, "a.mp4")
    }

    func testCleanResultCarriesBackupViaHistoryEntry() {
        let result = CleanResult(output: "/out/a.mp4", origSeconds: 10, newSeconds: 8,
                                 savedSeconds: 2, pauses: 1, fillers: 0,
                                 backup: "/Originals/2026-06-19/a.mp4")
        let entry = HistoryEntry(input: URL(fileURLWithPath: "/in/a.mp4"), result: result,
                                 date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(entry.backup, "/Originals/2026-06-19/a.mp4")
        // An empty backup (backup off) becomes nil, not "".
        let noBackup = CleanResult(output: "/o", origSeconds: 1, newSeconds: 1,
                                   savedSeconds: 0, pauses: 0, fillers: 0)
        XCTAssertNil(HistoryEntry(input: URL(fileURLWithPath: "/i"), result: noBackup,
                                  date: Date()).backup)
    }

    func testCutPreviewBasicPause() {
        // One 3s silence in a 10s clip; cut its middle leaving 0.15s on each side.
        let r = CutPreview.compute(silences: [(3, 6)], duration: 10,
                                   pause: 0.6, keepPause: 0.15, minKeep: 0.05)
        XCTAssertEqual(r.pauseCount, 1)
        XCTAssertEqual(r.removedSeconds, 2.7, accuracy: 0.0001)   // (6-0.15) - (3+0.15)
        XCTAssertEqual(r.keep.count, 2)
    }

    func testCutPreviewIgnoresShortSilences() {
        // A 0.3s gap is shorter than the 0.6s threshold → nothing is cut.
        let r = CutPreview.compute(silences: [(1, 1.3)], duration: 10,
                                   pause: 0.6, keepPause: 0.15, minKeep: 0.05)
        XCTAssertEqual(r.pauseCount, 0)
        XCTAssertEqual(r.removedSeconds, 0, accuracy: 0.0001)
        XCTAssertEqual(r.keep, [0...10])
    }

    func testCutPreviewMinKeepDropsTinyFragments() {
        // Two pauses leave sub-minKeep fragments at the head/middle → folded into the cut.
        let r = CutPreview.compute(silences: [(0, 2.9), (3.0, 6.0)], duration: 10,
                                   pause: 0.6, keepPause: 0.15, minKeep: 0.5)
        XCTAssertEqual(r.pauseCount, 2)
        XCTAssertEqual(r.keep.count, 1)                          // only the final tail survives
        XCTAssertEqual(r.removedSeconds, 5.85, accuracy: 0.0001) // 10 - (10 - 5.85)
    }

    func testCutPreviewRemovedMask() {
        let r = CutPreview.compute(silences: [(3, 6)], duration: 10,
                                   pause: 0.6, keepPause: 0.15, minKeep: 0.05)
        let mask = CutPreview.removedMask(keep: r.keep, duration: 10, bucketCount: 10)
        // Bucket centers 3.5/4.5/5.5 fall in the removed middle; the rest are kept.
        XCTAssertEqual(mask, [false, false, false, true, true, true, false, false, false, false])
    }

    // MARK: - Review timeline (cut regions ⇄ keep-list)

    func testRemovedRegionsAreGapsAndTrims() {
        // keep [0–2],[5–8] in a 10s clip → cuts are the 2–5 gap and the 8–10 tail.
        let cuts = CutPreview.removedRegions(keep: [0...2, 5...8], duration: 10)
        XCTAssertEqual(cuts.count, 2)
        XCTAssertEqual(cuts[0].0, 2, accuracy: 0.0001)
        XCTAssertEqual(cuts[0].1, 5, accuracy: 0.0001)
        XCTAssertEqual(cuts[1].0, 8, accuracy: 0.0001)
        XCTAssertEqual(cuts[1].1, 10, accuracy: 0.0001)
    }

    func testCutRegionsRoundTripToSameKeep() {
        // Building cuts from a keep-list and turning them back (all enabled) reproduces it.
        let keep: [ClosedRange<Double>] = [0...2, 5...8]
        let cuts = CutPreview.cutRegions(keep: keep, duration: 10)
        XCTAssertTrue(cuts.allSatisfy(\.enabled))
        XCTAssertEqual(CutPreview.keep(forCuts: cuts, duration: 10), keep)
    }

    func testDisablingACutKeepsThatStretch() {
        // Disable the first cut (the 2–5 gap) → it merges back into the kept span.
        var cuts = CutPreview.cutRegions(keep: [0...2, 5...8], duration: 10)
        cuts[0].enabled = false
        XCTAssertEqual(CutPreview.keep(forCuts: cuts, duration: 10), [0...8])
    }

    func testDisablingAllCutsKeepsWholeVideo() {
        var cuts = CutPreview.cutRegions(keep: [0...2, 5...8], duration: 10)
        for i in cuts.indices { cuts[i].enabled = false }
        XCTAssertEqual(CutPreview.keep(forCuts: cuts, duration: 10), [0...10])
    }

    func testWhatsNewPrefersHighlightsSection() {
        // When the LLM "## Highlights" section is present, it's used verbatim and the
        // detailed "## What's changed" list is ignored.
        let raw = """
        ## Highlights

        - Choose where your cleaned videos are saved.
        - Preview the exact cuts before you clean.

        ## What's changed

        ### Desktop (1)

        - #27 Split tracks: export separate video + audio files — @rafay99-epic
        """
        XCTAssertEqual(WhatsNewController.parse(raw), [
            "Choose where your cleaned videos are saved.",
            "Preview the exact cuts before you clean."
        ])
    }

    func testWhatsNewFallsBackToCleanedTitles() {
        // No Highlights section → clean, deduped titles from user-facing areas only.
        let raw = """
        ## What's changed

        ### Desktop (2)

        - #27 Split tracks: export separate video + audio files — @rafay99-epic
        - #37 Add a unified daily logging system — @rafay99-epic

        ### Backend (1)

        - #35 Speech engine: multi-model + accurate DTW timestamps — @rafay99-epic

        ### Docs (1)

        - #37 Add a unified daily logging system — @rafay99-epic

        ### CI (1)

        - #22 Add website CI — @rafay99-epic
        """
        // Desktop + Backend only (Docs/CI dropped), deduped (#37 once), decoration stripped.
        XCTAssertEqual(WhatsNewController.parse(raw), [
            "Split tracks: export separate video + audio files",
            "Add a unified daily logging system",
            "Speech engine: multi-model + accurate DTW timestamps"
        ])
    }

    func testCutsSummary() {
        // Both parts, pluralized.
        XCTAssertEqual(CleanResult.cutsSummary(fillers: 12, pauses: 47), "12 fillers \u{00B7} 47 pauses")
        // Singular forms.
        XCTAssertEqual(CleanResult.cutsSummary(fillers: 1, pauses: 1), "1 filler \u{00B7} 1 pause")
        // Only the non-zero part shows.
        XCTAssertEqual(CleanResult.cutsSummary(fillers: 0, pauses: 3), "3 pauses")
        XCTAssertEqual(CleanResult.cutsSummary(fillers: 5, pauses: 0), "5 fillers")
        // Nothing cut → nil (caller hides the line).
        XCTAssertNil(CleanResult.cutsSummary(fillers: 0, pauses: 0))
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
        // Pauses only: both detection passes off, so neither needs the transcript.
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false,
                                       removeRetakes: false, backupDirectory: nil)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mov"),
                                         parameters: params, options: opts)
        XCTAssertTrue(args.contains("--no-fillers"))               // fillers off
        XCTAssertTrue(args.contains("--no-retakes"))               // retakes off
        XCTAssertFalse(args.contains("--model"))                   // ⇒ no model flag
        XCTAssertTrue(args.contains("--no-backup"))                // no backup dir
        XCTAssertFalse(args.contains("--backup-dir"))
        XCTAssertFalse(args.contains("--out-dir"))                 // default ⇒ beside source
    }

    func testCleanRunnerEmitsFrameRateModeAutoByDefault() {
        let params = Strength.balanced.parameters(using: .defaults)
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false, removeRetakes: false)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params, options: opts)
        XCTAssertEqual(valueAfter("--fps-mode", in: args), "auto")
        XCTAssertFalse(args.contains("--fps"))                     // auto lets the engine pick
    }

    func testCleanRunnerEmitsConstantFrameRate() {
        var cfg = EngineConfig.defaults
        cfg.frameRateMode = "constant"
        cfg.frameRateValue = 60
        let params = Strength.balanced.parameters(using: cfg)
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false, removeRetakes: false)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params, options: opts)
        XCTAssertEqual(valueAfter("--fps-mode", in: args), "constant")
        XCTAssertEqual(valueAfter("--fps", in: args), String(60.0))
    }

    func testFrameRateConfigDefaultsAndForwardCompat() throws {
        XCTAssertEqual(EngineConfig.defaults.frameRateMode, "auto")
        XCTAssertEqual(EngineConfig.defaults.frameRateValue, 30)
        // A file predating the frame-rate keys fills them with defaults (forward-compat).
        let legacy = Data(#"{ "version": 2 }"#.utf8)
        let decoded = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertEqual(decoded.frameRateMode, "auto")
        XCTAssertEqual(decoded.frameRateValue, 30)
    }

    func testRetakeRemovalFlagMapping() {
        let params = Strength.aggressive.parameters(using: .defaults)
        // Retakes on (default) with fillers off: no --no-retakes, and the transcript
        // model is still required (retake detection matches the whisper transcript).
        let on = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: false)
        let onArgs = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                           input: URL(fileURLWithPath: "/v/in.mp4"),
                                           parameters: params, options: on)
        XCTAssertFalse(onArgs.contains("--no-retakes"))
        XCTAssertEqual(valueAfter("--model", in: onArgs), "/models/ggml.bin")
        // …and the sensitivity (from config, default aggressive) is forwarded.
        XCTAssertEqual(valueAfter("--retake-sensitivity", in: onArgs), "aggressive")

        // Retakes off: --no-retakes is passed and no sensitivity flag.
        let off = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: true,
                                      removeRetakes: false)
        let offArgs = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                            input: URL(fileURLWithPath: "/v/in.mp4"),
                                            parameters: params, options: off)
        XCTAssertTrue(offArgs.contains("--no-retakes"))
        XCTAssertFalse(offArgs.contains("--retake-sensitivity"))
    }

    func testRetakeSensitivityCarriesThrough() {
        var cfg = EngineConfig.defaults
        cfg.retakeSensitivity = "aggressive"
        let params = Strength.aggressive.parameters(using: cfg)
        let opts = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: true)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params, options: opts)
        XCTAssertEqual(valueAfter("--retake-sensitivity", in: args), "aggressive")
    }

    func testRetakeSensitivityForwardCompatDefaultsToAggressive() throws {
        // A config predating the key decodes with the default (now aggressive).
        let legacy = Data(#"{ "version": 3, "pauseThreshold": 0.4 }"#.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertEqual(cfg.retakeSensitivity, "aggressive")
    }

    func testCorruptRetakeSensitivityIsClampedNotForwarded() {
        // A hand-edited/garbage value must not reach the engine's fixed --choices and
        // hard-fail the clean; it's clamped to the default preset when building parameters.
        var cfg = EngineConfig.defaults
        cfg.retakeSensitivity = "ludicrous"
        let params = Strength.aggressive.parameters(using: cfg)
        XCTAssertEqual(params.retakeSensitivity, "aggressive")
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params,
                                         options: CleanRunner.Options(modelPath: "/m.bin", removeFillers: true))
        XCTAssertEqual(valueAfter("--retake-sensitivity", in: args), "aggressive")
    }

    func testSplitFlagOnlyWhenEnabled() {
        // Off by default → no --split; on → the flag is passed for every strength.
        XCTAssertFalse(EngineConfig.defaults.splitTracks)
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false)
        let off = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                        input: URL(fileURLWithPath: "/v/in.mp4"),
                                        parameters: Strength.aggressive.parameters(using: .defaults),
                                        options: opts)
        XCTAssertFalse(off.contains("--split"))

        var cfg = EngineConfig.defaults
        cfg.splitTracks = true
        let on = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                       input: URL(fileURLWithPath: "/v/in.mp4"),
                                       parameters: Strength.aggressive.parameters(using: cfg),
                                       options: opts)
        XCTAssertTrue(on.contains("--split"))
        XCTAssertEqual(valueAfter("--split-audio", in: on), "match")   // default format
    }

    func testSplitAudioFormatCarriesThrough() {
        // The chosen audio-stem format reaches the engine; off ⇒ no --split-audio.
        var cfg = EngineConfig.defaults
        cfg.splitTracks = true
        cfg.splitAudioFormat = "wav"
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false)
        let on = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                       input: URL(fileURLWithPath: "/v/in.mp4"),
                                       parameters: Strength.aggressive.parameters(using: cfg), options: opts)
        XCTAssertEqual(valueAfter("--split-audio", in: on), "wav")

        let off = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                        input: URL(fileURLWithPath: "/v/in.mp4"),
                                        parameters: Strength.aggressive.parameters(using: .defaults),
                                        options: opts)
        XCTAssertFalse(off.contains("--split-audio"))
    }

    func testSplitTracksForwardCompatDefaultsOff() throws {
        // A config predating the key decodes with split off.
        let legacy = Data(#"{ "version": 3, "pauseThreshold": 0.4 }"#.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertFalse(cfg.splitTracks)
    }

    func testKeepFileBypassesDetectionFlags() {
        // A reviewed keep-list renders exactly those segments: --keep-file is passed,
        // and no model / no waveform pass / no --no-fillers detection flags.
        let opts = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: true,
                                       backupDirectory: nil, waveformBuckets: 120,
                                       keepFilePath: "/tmp/keep.json")
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: Strength.aggressive.parameters(using: .defaults),
                                         options: opts)
        XCTAssertEqual(valueAfter("--keep-file", in: args), "/tmp/keep.json")
        XCTAssertFalse(args.contains("--model"))
        XCTAssertFalse(args.contains("--waveform"))
        XCTAssertFalse(args.contains("--no-fillers"))
        XCTAssertFalse(args.contains("--captions"))
        // Encoder choices still apply (the reviewed cut is still re-encoded).
        XCTAssertTrue(args.contains("--hardware"))
    }

    func testNoKeepFileKeepsNormalFlags() {
        let opts = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: true,
                                       backupDirectory: nil, waveformBuckets: 120)
        let args = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: Strength.aggressive.parameters(using: .defaults),
                                         options: opts)
        XCTAssertFalse(args.contains("--keep-file"))
        XCTAssertEqual(valueAfter("--model", in: args), "/models/ggml.bin")
        XCTAssertEqual(valueAfter("--waveform", in: args), "120")
    }

    func testCaptionsFlagAndModelGating() {
        // Off by default → no --captions; and pauses-only with captions off needs
        // no model.
        XCTAssertEqual(EngineConfig.defaults.captionsFormat, "none")
        let noModel = CleanRunner.Options(modelPath: nil, removeFillers: false)
        let off = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                        input: URL(fileURLWithPath: "/v/in.mp4"),
                                        parameters: Strength.aggressive.parameters(using: .defaults),
                                        options: noModel)
        XCTAssertFalse(off.contains("--captions"))

        // Captions on, fillers OFF: the flag is passed, fillers stay off, and the
        // model is still required (captions are transcribed from speech).
        var cfg = EngineConfig.defaults
        cfg.captionsFormat = "both"
        let withModel = CleanRunner.Options(modelPath: "/models/ggml.bin", removeFillers: false)
        let on = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                       input: URL(fileURLWithPath: "/v/in.mp4"),
                                       parameters: Strength.aggressive.parameters(using: cfg),
                                       options: withModel)
        XCTAssertEqual(valueAfter("--captions", in: on), "both")
        XCTAssertTrue(on.contains("--no-fillers"))
        XCTAssertEqual(valueAfter("--model", in: on), "/models/ggml.bin")
    }

    func testCaptionsForwardCompatDefaultsToNone() throws {
        // A config predating the key decodes with captions off.
        let legacy = Data(#"{ "version": 3, "pauseThreshold": 0.4 }"#.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertEqual(cfg.captionsFormat, "none")
    }

    func testWaveformFlagOnlyWhenRequested() {
        // The app asks for a waveform (N buckets); the bare CLI / watcher leave it
        // off so they don't pay for data nothing renders.
        let params = Strength.aggressive.parameters(using: .defaults)
        let withWave = CleanRunner.Options(modelPath: nil, removeFillers: false,
                                           backupDirectory: nil, waveformBuckets: 120)
        let on = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                       input: URL(fileURLWithPath: "/v/in.mp4"),
                                       parameters: params, options: withWave)
        XCTAssertEqual(valueAfter("--waveform", in: on), "120")

        let off = CleanRunner.Options(modelPath: nil, removeFillers: false)
        let none = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                         input: URL(fileURLWithPath: "/v/in.mp4"),
                                         parameters: params, options: off)
        XCTAssertFalse(none.contains("--waveform"))
    }

    func testCleanRunnerArgumentsCarryOutputDirectory() {
        // A chosen output folder (e.g. a NAS) reaches the engine as --out-dir;
        // the default empty value is omitted (engine writes beside the source).
        var cfg = EngineConfig.defaults
        cfg.outputDirectory = "/Volumes/NAS/clean"
        let opts = CleanRunner.Options(modelPath: nil, removeFillers: false, backupDirectory: nil)
        let withDir = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                            input: URL(fileURLWithPath: "/v/in.mp4"),
                                            parameters: Strength.aggressive.parameters(using: cfg),
                                            options: opts)
        XCTAssertEqual(valueAfter("--out-dir", in: withDir), "/Volumes/NAS/clean")

        let withoutDir = CleanRunner.arguments(scriptPath: "/eng/clean_video.py",
                                               input: URL(fileURLWithPath: "/v/in.mp4"),
                                               parameters: Strength.aggressive.parameters(using: .defaults),
                                               options: opts)
        XCTAssertFalse(withoutDir.contains("--out-dir"))
    }

    func testOutputTagRoundTrips() throws {
        // OutputTag must read back the same `user.crisp.source` xattr the engine
        // writes (cross-language compatibility for the watch-folder dedup).
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("crisp-tag-\(UUID().uuidString).mov")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let value = "/videos/talk.mov"
        let set = value.withCString { setxattr(file.path, OutputTag.key, $0, strlen($0), 0, 0) }
        try XCTSkipIf(set != 0, "filesystem doesn't support extended attributes")

        XCTAssertEqual(OutputTag.source(ofFileAt: file.path), value)
        XCTAssertNil(OutputTag.source(ofFileAt: dir.appendingPathComponent("nope").path))
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

    // MARK: - Presets

    func testPresetDefaultsAndConcurrencyForwardCompat() throws {
        // A v2 file (no preset/parallelism keys) fills the new keys with defaults —
        // presets empty, no default preset, Automatic parallelism.
        let legacy = Data(#"{ "version": 2, "pauseThreshold": 0.4, "backupOriginal": false }"#.utf8)
        let cfg = try JSONDecoder().decode(EngineConfig.self, from: legacy)
        XCTAssertEqual(cfg.pauseThreshold, 0.4)        // preserved
        XCTAssertFalse(cfg.backupOriginal)             // preserved
        XCTAssertEqual(cfg.presets, [])                // new → default
        XCTAssertEqual(cfg.defaultPresetID, "")
        XCTAssertEqual(cfg.concurrencyMode, "auto")
        XCTAssertEqual(cfg.manualConcurrency, 2)
        XCTAssertEqual(cfg.perJobMemoryBudgetMB, 2048)
    }

    func testPresetResolvesLikeGlobalPath() {
        // A preset must resolve to exactly the same parameters as taking its
        // strength through the global config it was built from.
        var cfg = EngineConfig.defaults
        cfg.pauseThreshold = 1.1; cfg.breathingRoom = 0.22; cfg.silenceFloorDB = -24; cfg.minKeep = 0.15
        cfg.videoCodec = "h264"; cfg.audioCodec = "opus"; cfg.outputContainer = "mkv"
        cfg.outputDirectory = "/Volumes/NAS"; cfg.backupOriginal = false
        for strength in [Strength.gentle, .aggressive, .custom] {
            let preset = Preset(name: "P", strength: strength, config: cfg)
            XCTAssertEqual(preset.parameters(), strength.parameters(using: cfg),
                           "\(strength.rawValue) preset should match the global path")
        }
    }

    func testPresetRoundTripsThroughConfig() throws {
        var cfg = EngineConfig.defaults
        cfg.presets = [Preset(name: "YouTube", strength: .custom, config: cfg)]
        cfg.defaultPresetID = cfg.presets[0].id.uuidString
        let round = try JSONDecoder().decode(EngineConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(round, cfg)
    }

    // MARK: - Resource governor

    private func snap(physGB: Double, availGB: Double, pCores: Int,
                      thermal: ProcessInfo.ThermalState = .nominal) -> SystemSnapshot {
        let gb = { (v: Double) in UInt64(v * 1024 * 1024 * 1024) }
        return SystemSnapshot(physicalMemory: gb(physGB), availableMemory: gb(availGB),
                              performanceCoreCount: pCores, thermalState: thermal)
    }

    func testGovernorNeverGoesBelowSerial() {
        // Almost no free memory still allows one clean (serial is always safe).
        let s = snap(physGB: 8, availGB: 0.5, pCores: 4)
        XCTAssertEqual(ResourceGovernor.recommended(snapshot: s, config: .defaults), 1)
    }

    func testGovernorCappedByMediaEngineForHardware() {
        // A big machine with hardware encoding is bounded by the shared media engine.
        let s = snap(physGB: 64, availGB: 32, pCores: 10)
        XCTAssertEqual(ResourceGovernor.recommended(snapshot: s, config: .defaults),
                       ResourceGovernor.mediaEngineCap)
    }

    func testGovernorSoftwareEncodeLiftsMediaCap() {
        // Software encoding has no media-engine contention, so the CPU cap governs.
        var cfg = EngineConfig.defaults
        cfg.hardwareEncoding = false
        let s = snap(physGB: 64, availGB: 32, pCores: 10)   // cpuCap = 10/2 = 5
        XCTAssertEqual(ResourceGovernor.recommended(snapshot: s, config: cfg), 5)
    }

    func testGovernorThermalPressureForcesSerial() {
        let hot = snap(physGB: 64, availGB: 32, pCores: 10, thermal: .serious)
        XCTAssertEqual(ResourceGovernor.recommended(snapshot: hot, config: .defaults), 1)
    }

    func testGovernorMemoryBoundsConcurrency() {
        // ~6 GB free, 2 GB reserve, 2 GB per job ⇒ (6-2)/2 = 2 fit, even with cores
        // to spare and software encoding (so the cap is purely memory).
        var cfg = EngineConfig.defaults
        cfg.hardwareEncoding = false
        let s = snap(physGB: 16, availGB: 6, pCores: 10)
        XCTAssertEqual(ResourceGovernor.recommended(snapshot: s, config: cfg), 2)
    }

    func testManualConcurrencyClampedToCeiling() {
        var cfg = EngineConfig.defaults
        cfg.manualConcurrency = 10
        let s = snap(physGB: 64, availGB: 64, pCores: 10)   // ceiling = mediaEngineCap (3)
        XCTAssertEqual(ResourceGovernor.plannedConcurrency(mode: .manual, snapshot: s, config: cfg),
                       ResourceGovernor.mediaEngineCap)
    }

    func testUltraPreflightFitsAndFails() {
        let cfg = EngineConfig.defaults                      // 2 GB/job + 2 GB reserve
        // Requesting 3 needs 3*2 + 2 = 8 GB free.
        let enough = snap(physGB: 64, availGB: 10, pCores: 10)
        XCTAssertTrue(ResourceGovernor.preflight(requested: 3, snapshot: enough, config: cfg).fits)
        let tooLittle = snap(physGB: 64, availGB: 6, pCores: 10)
        let verdict = ResourceGovernor.preflight(requested: 3, snapshot: tooLittle, config: cfg)
        XCTAssertFalse(verdict.fits)
        XCTAssertFalse(verdict.thermalBlocked)
    }

    func testUltraPreflightBlocksWhenHot() {
        let hot = snap(physGB: 64, availGB: 64, pCores: 10, thermal: .critical)
        let verdict = ResourceGovernor.preflight(requested: 2, snapshot: hot, config: .defaults)
        XCTAssertFalse(verdict.fits)
        XCTAssertTrue(verdict.thermalBlocked)
    }

    /// The argument value immediately following `flag`, or nil if absent.
    private func valueAfter(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
