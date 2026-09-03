import Foundation

/// Retake detection, ported from `crisp/retake.py`.
///
/// When you misspeak and say a phrase again, the corrected take is the keeper and the
/// first attempt is dead weight. In the transcript that shows up as a repeated run of
/// words, back to back in time:
///
///     "the API is slow — the API is fast"      (full restart)
///     "so today we're— so today we're going"   (false start)
///     "the the the parser"                      (single-word stutter)
///
/// The rule is the same for all three: find the longest run of words at position `i`
/// that repeats at a later position `j`, and remove `[start[i], start[j])`. The kept
/// boundary is always the corrected take's first-word onset, which whisper's DTW gives
/// accurately, so the splice lands on a real word start.
///
/// This is pure transcript matching. No audio, no model, no I/O, which is why it is the
/// first thing to move off Python.
public enum Retake {

    /// Signals gathered for one candidate, and the call that was made on them. The
    /// pipeline logs these so thresholds can be tuned against real footage; they are
    /// returned rather than printed so this stays a pure function.
    public struct Decision: Sendable {
        public var onset: Double
        public var run: Int
        public var hasPause: Bool
        public var similarity: Double?
        public var accepted: Bool
        public var reason: String
        public var text: String
    }

    public struct Result: Sendable {
        /// Spans to remove, in order and non-overlapping.
        public var removals: [TimeSpan]
        /// Every candidate considered, accepted or not.
        public var decisions: [Decision]

        public init(removals: [TimeSpan], decisions: [Decision]) {
            self.removals = removals
            self.decisions = decisions
        }
    }

    /// Scores how alike the flubbed and corrected takes are in *meaning*, 0...1.
    /// Backed by Apple's on-device sentence embeddings. Returning nil means "not
    /// scored", which is not the same as "scored low".
    public typealias Judge = @Sendable (_ flubbed: String, _ corrected: String) -> Double?

    /// Tokens shorter than this must match exactly. A similarity ratio is unreliable
    /// on short function words: "the"/"they", "is"/"it", "in"/"on" all clear a high
    /// bar yet are different words, and merging them would forge spurious runs.
    static let fuzzyMinLength = 4

    /// Are these two normalized tokens the same word, allowing for the minor spelling
    /// variance whisper emits between takes ("we're"/"were", "open"/"opens")?
    static func tokensMatch(_ a: String, _ b: String, similarity: Double) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        guard min(a.count, b.count) >= fuzzyMinLength else { return false }
        return SequenceRatio.ratio(a, b) >= similarity
    }

    /// Length of the longest run of matching tokens starting at `i` and `j`.
    ///
    /// Capped so the first run stays inside the abandoned span `[i, j)`: without that,
    /// a periodic phrase like "very very very" reports a bogus long match by overlapping
    /// itself.
    static func commonRun(_ normalized: [String], _ i: Int, _ j: Int,
                          _ n: Int, similarity: Double) -> Int {
        var length = 0
        while i + length < j, j + length < n,
              tokensMatch(normalized[i + length], normalized[j + length], similarity: similarity) {
            length += 1
        }
        return length
    }

    /// Accept or skip a candidate, with a short reason for the log.
    ///
    /// `similarity` can only ever *rescue* a shorter pause-less repeat. It never vetoes:
    /// Apple's short-phrase embedding scores a real redo and an intentional parallel list
    /// about the same, so a low score is not evidence of a non-redo.
    static func decide(anchored: Bool, hasPause: Bool, run: Int,
                       policy: RetakePolicy, similarity: Double?) -> (Bool, String) {
        if hasPause {
            if let similarity {
                return (true, String(format: "pause(sim=%.2f)", similarity))
            }
            return (true, "pause")
        }
        // Bare library call with no silence data: run length and gap are all we have.
        if !anchored { return (true, "no-silence-data") }

        // No pause before the redo. Only a preset that opts into a pause-less path may
        // cut here, so a pause-required preset like gentle stays pause-required even
        // when a judge is available: the judge can add precision, never remove it.
        if let minRunNoPause = policy.minRunNoPause {
            if run >= minRunNoPause {
                return (true, "long-run-no-pause(\(run)>=\(minRunNoPause))")
            }
            if let similarity, similarity >= policy.semanticMin {
                return (true, String(format: "semantic-no-pause(%.2f>=%.2f)",
                                     similarity, policy.semanticMin))
            }
        }
        return (false, policy.requirePause ? "no-pause" : "short-run-no-pause(run=\(run))")
    }

    /// Spans to remove, each a flubbed take the speaker redid.
    ///
    /// - Parameters:
    ///   - words: the transcript, in order.
    ///   - policy: run floors and the pause/semantic gates. Defaults to the app's default preset.
    ///   - maxGap: seconds between the abandoned take's end and the retake's start.
    ///   - maxAbandon: words in the abandoned take; bounds the search so a phrase that
    ///     simply recurs later in the video is never read as a retake.
    ///   - stutter: also catch a single word repeated back to back.
    ///   - silences: detected pause spans. Supplying them enables the pause anchor;
    ///     `nil` means no silence data at all, which is not the same as "no pauses found".
    ///   - judge: optional semantic scorer. A high score can rescue a shorter pause-less
    ///     repeat; it never vetoes one.
    public static func detect(
        words: [Word],
        policy: RetakePolicy = CrispDefaults.retakePolicy,
        maxGap: Double = CrispDefaults.retakeMaxGap,
        maxAbandon: Int = CrispDefaults.retakeMaxAbandon,
        stutter: Bool = CrispDefaults.retakeStutter,
        stutterMaxGap: Double = CrispDefaults.retakeStutterMaxGap,
        silences: [TimeSpan]? = nil,
        pausePad: Double = CrispDefaults.retakePausePad,
        tokenSimilarity: Double = CrispDefaults.retakeTokenSimilarity,
        judge: Judge? = nil
    ) -> Result {
        let normalized = words.map { Filler.normalize($0.text) }
        let n = words.count
        let anchored = silences != nil
        // A pause is mandatory unless the preset opted into a pause-less path. The
        // judge does not relax this.
        let pauseIsMandatory = policy.requirePause && policy.minRunNoPause == nil
        let silenceEnds = (silences ?? []).map(\.end).sorted()

        // Is there a silence whose END lands within +/- pausePad of this word onset?
        func beginsAfterPause(_ onset: Double) -> Bool {
            let k = lowerBound(silenceEnds, onset - pausePad)
            return k < silenceEnds.count && silenceEnds[k] <= onset + pausePad
        }

        var removals: [TimeSpan] = []
        var decisions: [Decision] = []
        var i = 0

        while i < n {
            guard !normalized[i].isEmpty else { i += 1; continue }

            var bestJ: Int?
            var bestLen = 0
            var bestPause = false
            let jMax = min(n, i + 1 + maxAbandon)

            for j in (i + 1)..<max(i + 1, jMax) {
                guard !normalized[j].isEmpty else { continue }
                let run = commonRun(normalized, i, j, n, similarity: tokenSimilarity)
                guard run >= 1 else { continue }

                // Time from the end of the first matched run to the start of the
                // second. Measuring the abandoned take's own tail instead would let a
                // phrase recurring much later slip through, since its second
                // occurrence is internally contiguous.
                let gap = words[j].start - words[i + run - 1].end
                let isStutter = (j == i + 1 && run == 1)
                let need = (stutter && isStutter) ? 1 : policy.minRun
                let limit = (stutter && isStutter) ? stutterMaxGap : maxGap
                guard run >= need, gap <= limit else { continue }

                let hasPause = anchored && beginsAfterPause(words[j].start)
                // When a pause is mandatory an un-anchored repeat cannot win, so skip
                // it during selection rather than letting it shadow a better candidate.
                if pauseIsMandatory && anchored && !hasPause { continue }

                if run > bestLen {
                    bestJ = j
                    bestLen = run
                    bestPause = hasPause
                }
            }

            guard let bestJ else { i += 1; continue }

            // Score the winner's meaning. Single-word stutters are skipped because
            // embeddings need a phrase to say anything useful.
            var similarity: Double?
            if let judge, bestLen >= 2 {
                let flubbed = joined(words[i..<bestJ])
                let end = min(n, bestJ + (bestJ - i))
                similarity = judge(flubbed, joined(words[bestJ..<end]))
            }

            let (accept, reason) = decide(anchored: anchored, hasPause: bestPause,
                                          run: bestLen, policy: policy, similarity: similarity)
            decisions.append(Decision(onset: words[i].start, run: bestLen,
                                      hasPause: bestPause, similarity: similarity,
                                      accepted: accept, reason: reason,
                                      text: joined(words[i..<bestJ])))
            if accept {
                removals.append(TimeSpan(start: words[i].start, end: words[bestJ].start))
                i = bestJ    // resume at the kept take; it may itself be redone again
            } else {
                i += 1
            }
        }
        return Result(removals: removals, decisions: decisions)
    }

    /// Readable text of a word slice, for the semantic judge and the log.
    static func joined(_ words: ArraySlice<Word>) -> String {
        words.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Index of the first element >= `value`, i.e. Python's `bisect.bisect_left`.
    static func lowerBound(_ sorted: [Double], _ value: Double) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
