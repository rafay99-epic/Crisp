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
    ///   - pauseMode: "remove" cuts each pause entirely; "tighten" keeps `tightPause`
    ///     extra seconds of silence at the pause start (mirrors `build_keep_segments`).
    ///   - tightPause: seconds kept at each pause in tighten mode.
    public static func compute(silences: [(Double, Double)], duration: Double,
                               pause: Double, keepPause: Double, minKeep: Double,
                               pauseMode: String = "remove", tightPause: Double = 0.3) -> Result {
        guard duration > 0 else { return Result(keep: [], pauseCount: 0, removedSeconds: 0) }

        // Long pauses → trim the middle, leaving keepPause on each side. Count a
        // pause exactly as the engine does: per qualifying silence with a positive
        // inner span (before merging).
        var remove: [(Double, Double)] = []
        var pauseCount = 0
        for (s, e) in silences where (e - s) >= pause {
            var innerS = s + keepPause
            let innerE = e - keepPause
            if pauseMode == PauseMode.tighten.rawValue { innerS += tightPause }
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

    /// One removable region on the review timeline — a stretch the cut would drop.
    /// `enabled` means it will be removed; the user toggles it off to keep that
    /// stretch. `id` is the stable position in the original detected order.
    public struct CutRegion: Identifiable, Equatable, Sendable {
        public let id: Int
        public let start: Double
        public let end: Double
        public var enabled: Bool
        public init(id: Int, start: Double, end: Double, enabled: Bool = true) {
            self.id = id
            self.start = start
            self.end = end
            self.enabled = enabled
        }
        public var duration: Double { max(0, end - start) }
    }

    /// The removed regions implied by a keep-list over `[0, duration]`: the gaps
    /// between kept ranges plus any leading/trailing trim. These become the editable
    /// cuts in the review timeline.
    public static func removedRegions(keep: [ClosedRange<Double>],
                                      duration: Double) -> [(Double, Double)] {
        guard duration > 0 else { return [] }
        let sorted = keep.sorted { $0.lowerBound < $1.lowerBound }
        var cuts: [(Double, Double)] = []
        var cursor = 0.0
        for r in sorted {
            if r.lowerBound - cursor > 0.01 { cuts.append((cursor, r.lowerBound)) }
            cursor = max(cursor, r.upperBound)
        }
        if duration - cursor > 0.01 { cuts.append((cursor, duration)) }
        return cuts
    }

    /// Build the editable cut regions (all enabled) from an initial keep-list.
    public static func cutRegions(keep: [ClosedRange<Double>], duration: Double) -> [CutRegion] {
        removedRegions(keep: keep, duration: duration).enumerated().map { i, r in
            CutRegion(id: i, start: r.0, end: r.1)
        }
    }

    /// Recompute the keep-list from the current cut toggles: `[0, duration]` minus
    /// every *enabled* region (disabled cuts are kept), dropping empty fragments.
    /// This is exactly what the engine renders via `--keep-file`.
    public static func keep(forCuts cuts: [CutRegion], duration: Double) -> [ClosedRange<Double>] {
        guard duration > 0 else { return [] }
        let active = cuts.filter { $0.enabled && $0.end - $0.start > 0.01 }
            .map { (max(0, $0.start), min(duration, $0.end)) }
            .sorted { $0.0 < $1.0 }
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for (s, e) in active {
            if s - cursor > 0.01 { keep.append(cursor...s) }
            cursor = max(cursor, e)
        }
        if duration - cursor > 0.01 { keep.append(cursor...duration) }
        return keep
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
