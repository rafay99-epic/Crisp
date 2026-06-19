import Foundation

/// Pure, no-I/O computation of which parts of a video the pause-cutting would
/// remove, given the engine's raw candidate silences and the cut knobs. Mirrors the
/// engine's `build_keep_segments` pause path (`crisp/edit.py`) so the live preview
/// matches what cleaning actually does — minus filler words, which need
/// transcription and aren't previewed. Kept separate and pure so it can recompute
/// instantly as the user drags a knob, and be unit-tested.
public enum CutPreview {
    public struct Result: Equatable, Sendable {
        /// Time ranges that survive (what the cleaned video keeps).
        public let keep: [ClosedRange<Double>]
        /// Number of pauses that would be cut.
        public let pauseCount: Int
        /// Seconds removed.
        public let removedSeconds: Double
    }

    /// - Parameters:
    ///   - silences: raw candidate silence intervals `(start, end)` from the engine's
    ///     analyze pass (detected down to a small floor, so the threshold is applied
    ///     here).
    ///   - duration: total media duration in seconds.
    ///   - pause: only silences at least this long are cut.
    ///   - keepPause: breathing room left on each side of a cut.
    ///   - minKeep: kept fragments shorter than this are dropped (folded into the cut).
    public static func compute(silences: [(Double, Double)], duration: Double,
                               pause: Double, keepPause: Double, minKeep: Double) -> Result {
        guard duration > 0 else { return Result(keep: [], pauseCount: 0, removedSeconds: 0) }

        // Long pauses → trim the middle, leaving keepPause on each side. Count a
        // pause exactly as the engine does: per qualifying silence with a positive
        // inner span (before merging).
        var remove: [(Double, Double)] = []
        var pauseCount = 0
        for (s, e) in silences where (e - s) >= pause {
            let innerS = s + keepPause
            let innerE = e - keepPause
            if innerE - innerS > 0.01 {
                remove.append((max(0, innerS), min(duration, innerE)))
                pauseCount += 1
            }
        }

        // Clamp, sort, merge overlaps.
        let cleaned = remove.map { (max(0, $0.0), min(duration, $0.1)) }
            .filter { $0.1 - $0.0 > 0.01 }
            .sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for seg in cleaned {
            if let last = merged.last, seg.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, seg.1))
            } else {
                merged.append(seg)
            }
        }

        // Keep = the gaps between removals, dropping any fragment shorter than minKeep.
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for (s, e) in merged {
            if s - cursor >= minKeep { keep.append(cursor...s) }
            cursor = max(cursor, e)
        }
        if duration - cursor >= minKeep { keep.append(cursor...duration) }

        let kept = keep.reduce(0.0) { $0 + ($1.upperBound - $1.lowerBound) }
        let removed = max(0, duration - kept)
        return Result(keep: keep, pauseCount: pauseCount, removedSeconds: removed)
    }

    /// A per-bucket "removed" mask aligned to a waveform's `bucketCount` peaks: a
    /// bucket is removed when its center time falls outside every kept range. Mirrors
    /// `crisp/waveform.py:_removed_flags` so the preview waveform dims exactly the
    /// slices that would be cut.
    public static func removedMask(keep: [ClosedRange<Double>], duration: Double,
                                   bucketCount: Int) -> [Bool] {
        guard bucketCount > 0, duration > 0 else { return [] }
        return (0..<bucketCount).map { i in
            let t = (Double(i) + 0.5) * duration / Double(bucketCount)
            return !keep.contains { $0.lowerBound <= t && t <= $0.upperBound }
        }
    }
}
