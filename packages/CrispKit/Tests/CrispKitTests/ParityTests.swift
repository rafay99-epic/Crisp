import XCTest
@testable import CrispKit

/// Every assertion here compares CrispKit against output captured from the Python
/// engine. A failure means the port changed behaviour, which is the one thing this
/// migration must not do.
final class ParityTests: XCTestCase {

    // MARK: Config

    func testDefaultsMatchPython() throws {
        let f: ConfigFixture = try Fixture.load("config")

        XCTAssertEqual(CrispDefaults.maxPause, f.maxPause)
        XCTAssertEqual(CrispDefaults.noiseDB, f.noiseDB)
        XCTAssertEqual(CrispDefaults.keepPause, f.keepPause)
        XCTAssertEqual(CrispDefaults.minKeep, f.minKeep)
        XCTAssertEqual(CrispDefaults.tightPause, f.tightPause)
        XCTAssertEqual(CrispDefaults.fadeMS, f.fadeMS)
        XCTAssertEqual(CrispDefaults.crossfadeMS, f.crossfadeMS)
        XCTAssertEqual(CrispDefaults.snapMS, f.snapMS)
        XCTAssertEqual(CrispDefaults.audioBitrateKbps, f.audioBitrateKbps)
        XCTAssertEqual(CrispDefaults.fillerMinSolo, f.fillerMinSolo)
        XCTAssertEqual(CrispDefaults.fillerPausePad, f.fillerPausePad)
        XCTAssertEqual(CrispDefaults.retakeMaxGap, f.retakeMaxGap)
        XCTAssertEqual(CrispDefaults.retakeMaxAbandon, f.retakeMaxAbandon)
        XCTAssertEqual(CrispDefaults.retakeTokenSimilarity, f.retakeTokenSimilarity)
        XCTAssertEqual(CrispDefaults.retakeAnchorPause, f.retakeAnchorPause)
        XCTAssertEqual(CrispDefaults.retakePausePad, f.retakePausePad)
        XCTAssertEqual(CrispDefaults.retakeStutterMaxGap, f.retakeStutterMaxGap)

        XCTAssertEqual(CrispDefaults.retakeSensitivity.rawValue, f.defaultSensitivity)
        XCTAssertEqual(Captions.maxCharsPerLine, f.captions.maxCharsPerLine)
        XCTAssertEqual(Captions.maxLines, f.captions.maxLines)
        XCTAssertEqual(Captions.minCueDuration, f.captions.minCueDur)
        XCTAssertEqual(Captions.maxCueDuration, f.captions.maxCueDur)
        XCTAssertEqual(Captions.cueSplitGap, f.captions.cueSplitGap)
        XCTAssertEqual(Captions.minGap, f.captions.minGap)
        XCTAssertEqual(FrameRate.vfrRelativeTolerance, f.framerate.vfrRelTol)
        XCTAssertEqual(FrameRate.maxPlausibleFPS, f.framerate.maxPlausibleFPS)
    }

    func testRetakePresetsMatchPython() throws {
        let f: ConfigFixture = try Fixture.load("config")
        XCTAssertEqual(Set(f.sensitivities.keys),
                       Set(RetakeSensitivity.allCases.map(\.rawValue)),
                       "a preset was added or removed on one side only")

        for sensitivity in RetakeSensitivity.allCases {
            let expected = try XCTUnwrap(f.sensitivities[sensitivity.rawValue])
            let policy = sensitivity.policy
            XCTAssertEqual(policy.minRun, expected.min_run, sensitivity.rawValue)
            XCTAssertEqual(policy.requirePause, expected.require_pause, sensitivity.rawValue)
            XCTAssertEqual(policy.minRunNoPause, expected.min_run_no_pause, sensitivity.rawValue)
            XCTAssertEqual(policy.semanticMin, expected.sem_min, sensitivity.rawValue)
        }
    }

    func testFillerVocabularyMatchesPython() throws {
        let f: ConfigFixture = try Fixture.load("config")
        XCTAssertEqual(Filler.vocabulary, Set(f.fillerVocabulary))
    }

    // MARK: Fillers

    func testFillerClassificationMatchesPython() throws {
        let cases: [FillerCase] = try Fixture.load("fillers")
        XCTAssertGreaterThan(cases.count, 60, "fixture corpus shrank unexpectedly")

        for c in cases {
            XCTAssertEqual(Filler.normalize(c.token), c.normalized,
                           "normalize(\(c.token.debugDescription))")
            XCTAssertEqual(Filler.isFiller(c.token), c.isFiller,
                           "isFiller(\(c.token.debugDescription))")
        }
    }

    // MARK: Token similarity

    func testSequenceRatioMatchesDifflib() throws {
        let cases: [RatioCase] = try Fixture.load("ratios")
        for c in cases {
            XCTAssertEqual(SequenceRatio.ratio(c.a, c.b), c.ratio, accuracy: 1e-12,
                           "ratio(\(c.a.debugDescription), \(c.b.debugDescription))")
        }
    }

    // MARK: Retakes

    func testRetakeDetectionMatchesPython() throws {
        let cases: [RetakeCase] = try Fixture.load("retakes")
        XCTAssertGreaterThan(cases.count, 15, "fixture corpus shrank unexpectedly")

        for c in cases {
            let result = Retake.detect(
                words: c.words.map(\.word),
                policy: c.sensitivity.policy,
                stutter: c.options.stutter ?? CrispDefaults.retakeStutter,
                silences: c.silences
            )
            XCTAssertEqual(result.removals.count, c.expectedSpans.count,
                           "\(c.name): span count")
            for (got, want) in zip(result.removals, c.expectedSpans) {
                XCTAssertEqual(got.start, want.start, accuracy: 1e-6, "\(c.name): start")
                XCTAssertEqual(got.end, want.end, accuracy: 1e-6, "\(c.name): end")
            }
        }
    }

    /// The fixture corpus is only meaningful if it actually exercises both outcomes.
    func testRetakeFixturesCoverBothOutcomes() throws {
        let cases: [RetakeCase] = try Fixture.load("retakes")
        XCTAssertTrue(cases.contains { !$0.expected.isEmpty }, "no case cuts anything")
        XCTAssertTrue(cases.contains { $0.expected.isEmpty }, "no case rejects anything")
        XCTAssertTrue(cases.contains { $0.expected.count > 1 }, "no chained-retake case")
    }

    // MARK: Frame rate

    func testFrameRateResolutionMatchesPython() throws {
        let cases: [FrameRateCase] = try Fixture.load("framerate")
        for c in cases {
            let mode = try XCTUnwrap(FPSMode(rawValue: c.mode))
            let got = FrameRate.resolveTarget(mode: mode,
                                              requestedFPS: c.requestedFPS,
                                              baseRateText: c.base,
                                              averageRateText: c.average)
            XCTAssertEqual(got, c.expected,
                           "\(c.mode) fps=\(c.requestedFPS) r=\(c.base) avg=\(c.average)")
        }
    }

    // MARK: Captions

    func testCaptionsMatchPython() throws {
        let cases: [CaptionCase] = try Fixture.load("captions")
        for c in cases {
            let cues = Captions.build(words: c.words.map(\.word), keep: c.keepSpans)
            XCTAssertEqual(cues.count, c.expected.cues.count, "\(c.name): cue count")

            for (got, want) in zip(cues, c.expected.cues) {
                XCTAssertEqual(got.start, want.start, accuracy: 1e-6, "\(c.name): cue start")
                XCTAssertEqual(got.end, want.end, accuracy: 1e-6, "\(c.name): cue end")
                XCTAssertEqual(got.lines, want.lines, "\(c.name): cue lines")
            }
            // Byte-for-byte, including CRLF in SubRip: a player is picky about both.
            XCTAssertEqual(Captions.toSRT(cues), c.expected.srt, "\(c.name): srt")
            XCTAssertEqual(Captions.toVTT(cues), c.expected.vtt, "\(c.name): vtt")
        }
    }

    // MARK: Waveform

    func testWaveformMatchesPython() throws {
        let f: WaveformFixture = try Fixture.load("waveform")

        for c in f.peaks {
            let samples = c.samples.map { Int16(clamping: $0) }
            let got = Waveform.peaks(from: samples, buckets: c.buckets)
            XCTAssertEqual(got.count, c.expected.count, "\(c.name): bucket count")
            for (g, w) in zip(got, c.expected) {
                XCTAssertEqual(g, w, accuracy: 1e-9, "\(c.name): peak")
            }
        }

        for c in f.removed {
            XCTAssertEqual(Waveform.removedFlags(buckets: c.buckets,
                                                 duration: c.duration,
                                                 keep: c.keepSpans),
                           c.expected, c.name)
        }
    }
}
