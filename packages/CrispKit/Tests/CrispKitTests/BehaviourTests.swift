import XCTest
@testable import CrispKit

/// Properties and edge cases the golden fixtures do not reach.
///
/// The parity suite proves CrispKit matches Python on a corpus. These cover the
/// contracts a future refactor could break without any fixture noticing: the semantics
/// of the new value types, degenerate inputs, and the invariants the media layer will
/// rely on once it stops going through Python.
final class BehaviourTests: XCTestCase {

    // MARK: TimeSpan

    func testDurationNeverGoesNegative() {
        XCTAssertEqual(TimeSpan(start: 1, end: 4).duration, 3)
        // Callers should never build an inverted span, but a negative duration
        // silently corrupts every downstream offset, so it clamps.
        XCTAssertEqual(TimeSpan(start: 4, end: 1).duration, 0)
    }

    func testTouchingSpansDoNotOverlap() {
        let a = TimeSpan(start: 0, end: 1)
        let b = TimeSpan(start: 1, end: 2)
        XCTAssertFalse(a.overlaps(b))
        XCTAssertFalse(b.overlaps(a))
        XCTAssertTrue(a.overlaps(TimeSpan(start: 0.5, end: 1.5)))
    }

    func testSpansSortChronologically() {
        let spans = [TimeSpan(start: 3, end: 4),
                     TimeSpan(start: 1, end: 9),
                     TimeSpan(start: 1, end: 2)]
        XCTAssertEqual(spans.sorted(), [TimeSpan(start: 1, end: 2),
                                        TimeSpan(start: 1, end: 9),
                                        TimeSpan(start: 3, end: 4)])
    }

    // MARK: Filler

    func testRealWordsContainingFillerShapesAreNotFillers() {
        // The whole-token anchoring is the only thing standing between Crisp and
        // deleting real speech, so it gets its own test rather than living only in
        // the fixture corpus.
        for word in ["human", "away", "hum", "summer", "error", "ahead", "although"] {
            XCTAssertFalse(Filler.isFiller(word), word)
        }
    }

    func testNormalizeStripsSurroundingPunctuationOnly() {
        XCTAssertEqual(Filler.normalize("  Um, "), "um")
        XCTAssertEqual(Filler.normalize("—uh—"), "uh")
        // Internal punctuation is part of the token and must survive.
        XCTAssertEqual(Filler.normalize("uh-huh"), "uh-huh")
        XCTAssertEqual(Filler.normalize("we're"), "we're")
    }

    // MARK: SequenceRatio

    func testRatioIsBounded() {
        let samples = ["parser", "parse", "we're", "were", "", "a", "interface"]
        for a in samples {
            for b in samples {
                let ratio = SequenceRatio.ratio(a, b)
                XCTAssertGreaterThanOrEqual(ratio, 0, "\(a)/\(b)")
                XCTAssertLessThanOrEqual(ratio, 1, "\(a)/\(b)")
            }
        }
        XCTAssertEqual(SequenceRatio.ratio("", ""), 1.0)
        XCTAssertEqual(SequenceRatio.ratio("same", "same"), 1.0)
    }

    func testRatioIsAsymmetricJustLikeDifflib() {
        // Surprising but correct: difflib's ratio depends on argument order, because
        // the longest-match search indexes positions in the SECOND sequence and breaks
        // ties toward the earliest one. Reproducing that is the whole point of
        // SequenceRatio, so it is pinned here rather than "fixed" into symmetry.
        //
        // Retake matching is unaffected: `commonRun` always passes the earlier
        // (flubbed) token first, so the order is fixed and matches Python's.
        XCTAssertEqual(SequenceRatio.ratio("parse", "were"), 0.4444444444444444,
                       accuracy: 1e-12)
        XCTAssertEqual(SequenceRatio.ratio("were", "parse"), 0.2222222222222222,
                       accuracy: 1e-12)
    }

    // MARK: Retake

    func testShortTokensRequireAnExactMatch() {
        // "the"/"they" clear a 0.85 ratio yet are different words; merging them
        // would forge runs out of ordinary function words.
        XCTAssertFalse(Retake.tokensMatch("the", "they", similarity: 0.85))
        XCTAssertTrue(Retake.tokensMatch("the", "the", similarity: 0.85))
        XCTAssertTrue(Retake.tokensMatch("interface", "interfaces", similarity: 0.85))
    }

    func testEmptyTokensNeverMatch() {
        XCTAssertFalse(Retake.tokensMatch("", "", similarity: 0.85))
        XCTAssertFalse(Retake.tokensMatch("word", "", similarity: 0.85))
    }

    func testRemovalsAreOrderedAndNonOverlapping() {
        // Chained retakes are the case where a bug would produce overlapping spans,
        // and an overlapping cut list silently corrupts the keep-list the renderer
        // derives from it.
        var words: [Word] = []
        var t = 0.0
        for _ in 0..<3 {
            for token in ["let", "me", "start", "over", "again"] {
                words.append(Word(text: token, start: t, end: t + 0.25))
                t += 0.3
            }
            t += 0.5
        }
        let result = Retake.detect(words: words, policy: RetakeSensitivity.aggressive.policy)
        for (earlier, later) in zip(result.removals, result.removals.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.end, later.start, "spans overlap")
        }
    }

    func testDecisionsAreRecordedForRejectedCandidates() {
        // The tuning log is the only visibility into why a retake was skipped, so a
        // candidate that reaches the decision table must leave a record even when it
        // is rejected. A 3-word repeat clears aggressive's run floor, so it becomes a
        // candidate, then fails the pause-less bar (3 < minRunNoPause of 5).
        var words: [Word] = []
        var t = 0.0
        for token in ["we", "ship", "it", "we", "ship", "it", "tomorrow"] {
            words.append(Word(text: token, start: t, end: t + 0.25))
            t += 0.3
        }
        let result = Retake.detect(words: words,
                                   policy: RetakeSensitivity.aggressive.policy,
                                   silences: [])
        XCTAssertTrue(result.removals.isEmpty)
        XCTAssertFalse(result.decisions.isEmpty)
        XCTAssertTrue(result.decisions.allSatisfy { !$0.accepted })
        XCTAssertTrue(result.decisions.contains { $0.reason.hasPrefix("short-run-no-pause") })
    }

    func testJudgeNeverVetoesAPauseAnchoredMatch() {
        // A low semantic score must not block a cut the pause anchor already earned:
        // Apple's short-phrase embedding scores real redos and parallel lists alike.
        var words: [Word] = []
        var t = 0.0
        for token in ["the", "api", "is", "really", "slow",
                      "the", "api", "is", "really", "fast"] {
            words.append(Word(text: token, start: t, end: t + 0.25))
            t += 0.3
        }
        let anchor = words[5].start
        let silences = [TimeSpan(start: anchor - 0.4, end: anchor - 0.05)]
        let withoutJudge = Retake.detect(words: words,
                                         policy: RetakeSensitivity.aggressive.policy,
                                         silences: silences)
        let withHostileJudge = Retake.detect(words: words,
                                             policy: RetakeSensitivity.aggressive.policy,
                                             silences: silences,
                                             judge: { _, _ in 0.0 })
        XCTAssertEqual(withoutJudge.removals, withHostileJudge.removals)
    }

    func testNilSilencesDiffersFromEmptySilences() {
        // "no silence data" (bare library call) and "detection ran, found nothing"
        // must not be conflated: the first skips the anchor, the second enforces it.
        // Five matching words, so gentle's run floor is cleared and the ONLY thing
        // separating the two calls is the pause anchor.
        var words: [Word] = []
        var t = 0.0
        for token in ["let", "me", "start", "over", "again", "now",
                      "let", "me", "start", "over", "again", "later"] {
            words.append(Word(text: token, start: t, end: t + 0.25))
            t += 0.3
        }
        let unknown = Retake.detect(words: words,
                                    policy: RetakeSensitivity.gentle.policy,
                                    silences: nil)
        let noneFound = Retake.detect(words: words,
                                      policy: RetakeSensitivity.gentle.policy,
                                      silences: [])
        XCTAssertFalse(unknown.removals.isEmpty, "bare call should fall back to run+gap")
        XCTAssertTrue(noneFound.removals.isEmpty, "gentle requires a pause anchor")
    }

    // MARK: FrameRate

    func testMalformedRateStringsAreNil() {
        for text in ["", "  ", "N/A", "n/a", "0/0", "30/0", "abc", "1/x", "/", "3/"] {
            XCTAssertNil(FrameRate.parseFraction(text), text.debugDescription)
        }
        XCTAssertEqual(FrameRate.parseFraction("30/1"), 30)
        XCTAssertEqual(FrameRate.parseFraction("25"), 25)
        XCTAssertEqual(FrameRate.parseFraction(" 30000/1001 ")!, 29.97, accuracy: 0.01)
    }

    func testAutoLeavesConstantFrameRateSourcesAlone() {
        XCTAssertNil(FrameRate.resolveTarget(mode: .auto, requestedFPS: 0,
                                             baseRateText: "30/1", averageRateText: "30/1"))
        // A VFR source keeps its exact base FRACTION, never a rounded decimal, or the
        // drift this path exists to prevent comes back in.
        XCTAssertEqual(FrameRate.resolveTarget(mode: .auto, requestedFPS: 0,
                                               baseRateText: "30000/1001",
                                               averageRateText: "24/1"),
                       "30000/1001")
    }

    // MARK: Captions

    func testWrapNeverSplitsAWord() {
        let long = String(repeating: "x", count: 60)
        XCTAssertEqual(Captions.wrapLines(long), [long])
        let lines = Captions.wrapLines("alpha beta gamma delta epsilon zeta eta theta iota",
                                       maxChars: 20)
        XCTAssertTrue(lines.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        XCTAssertEqual(lines.joined(separator: " ").split(separator: " ").count, 9)
    }

    func testTimestampFormatting() {
        XCTAssertEqual(Captions.formatTimestamp(0, separator: ","), "00:00:00,000")
        XCTAssertEqual(Captions.formatTimestamp(3661.5, separator: ","), "01:01:01,500")
        XCTAssertEqual(Captions.formatTimestamp(3661.5, separator: "."), "01:01:01.500")
        // Negative times clamp rather than formatting as garbage.
        XCTAssertEqual(Captions.formatTimestamp(-5, separator: ","), "00:00:00,000")
    }

    func testCaptionPathsSitBesideTheOutput() {
        let out = URL(fileURLWithPath: "/videos/talk_cleaned.mp4")
        let (srt, vtt) = Captions.captionPaths(for: out)
        XCTAssertEqual(srt.path, "/videos/talk_cleaned.srt")
        XCTAssertEqual(vtt.path, "/videos/talk_cleaned.vtt")
    }

    func testEmptyCuesProduceEmptySRT() {
        XCTAssertEqual(Captions.toSRT([]), "")
        // WebVTT still needs its header to be a valid file.
        XCTAssertEqual(Captions.toVTT([]), "WEBVTT\n\n")
    }

    // MARK: Waveform

    func testPeaksHandleFullScaleNegativeWithoutTrapping() {
        // Int16.min has no positive counterpart; a naive abs() traps here.
        let peaks = Waveform.peaks(from: [Int16.min, 0, Int16.max], buckets: 3)
        XCTAssertEqual(peaks.count, 3)
        XCTAssertEqual(peaks[0], 1.0, accuracy: 1e-9)
    }

    func testDegenerateWaveformInputsReturnEmpty() {
        XCTAssertEqual(Waveform.peaks(from: [], buckets: 8), [])
        XCTAssertEqual(Waveform.peaks(from: [1, 2, 3], buckets: 0), [])
        XCTAssertEqual(Waveform.removedFlags(buckets: 0, duration: 5, keep: []), [])
        XCTAssertEqual(Waveform.removedFlags(buckets: 5, duration: 0, keep: []), [])
    }

    func testEveryBucketIsRemovedWhenNothingIsKept() {
        let flags = Waveform.removedFlags(buckets: 6, duration: 6, keep: [])
        XCTAssertEqual(flags, Array(repeating: true, count: 6))
    }
}
