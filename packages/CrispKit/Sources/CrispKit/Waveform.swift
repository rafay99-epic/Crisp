import Foundation

/// The compact waveform summary the UI renders, ported from `crisp/waveform.py`:
/// a few dozen peak buckets over the original audio, plus a flag per bucket for
/// whether that slice was cut, so the user *sees* what Crisp removed.
///
/// Python read these from the analysis WAV it had already written to disk. On iOS
/// there is no such file, so this takes the PCM samples directly: the media layer
/// hands over the same 16 kHz mono buffer it decoded for silence detection, and the
/// waveform costs nothing extra.
public enum Waveform {
    /// Cap samples scanned per bucket so a long recording stays fast. Peaks over a
    /// strided scan look identical at UI resolution.
    static let maxScanPerBucket = 300

    public struct Summary: Hashable, Sendable, Codable {
        /// Normalized 0...1 peak amplitude per bucket.
        public var peaks: [Double]
        /// True for a bucket whose centre falls outside every kept segment.
        public var removed: [Bool]

        public init(peaks: [Double] = [], removed: [Bool] = []) {
            self.peaks = peaks
            self.removed = removed
        }

        public static let empty = Summary()
    }

    /// Normalized peak amplitude for each of `buckets` equal slices of `samples`.
    ///
    /// Samples are signed 16-bit, so the divisor is 32768 and the result is rounded to
    /// four places, matching the Python output byte for byte in the NDJSON payload.
    public static func peaks(from samples: [Int16], buckets: Int) -> [Double] {
        let n = samples.count
        guard n > 0, buckets > 0 else { return [] }

        return (0..<buckets).map { index in
            let lo = (index * n) / buckets
            let hi = max(lo + 1, ((index + 1) * n) / buckets)
            let step = max(1, (hi - lo) / maxScanPerBucket)
            var peak = 0
            var j = lo
            while j < hi {
                // Negate rather than use magnitude: Int16.min has no positive
                // counterpart, so abs() would trap on a full-scale negative sample.
                let sample = Int(samples[j])
                let amplitude = sample < 0 ? -sample : sample
                if amplitude > peak { peak = amplitude }
                j += step
            }
            return (Double(peak) / 32768.0 * 10000).rounded() / 10000
        }
    }

    /// True for each bucket whose centre time falls outside every kept segment, i.e.
    /// the slices Crisp cut out.
    public static func removedFlags(buckets: Int, duration: Double,
                                    keep: [TimeSpan]) -> [Bool] {
        guard buckets > 0, duration > 0 else { return [] }
        return (0..<buckets).map { index in
            let t = (Double(index) + 0.5) * duration / Double(buckets)
            return !keep.contains { $0.contains(t) }
        }
    }

    /// Build the full summary. Non-essential by design: a caller that cannot supply
    /// samples passes an empty array and gets `.empty` rather than an error, because a
    /// missing waveform must never fail a clean.
    public static func summary(samples: [Int16], duration: Double,
                               keep: [TimeSpan], buckets: Int = 120) -> Summary {
        Summary(peaks: peaks(from: samples, buckets: buckets),
                removed: removedFlags(buckets: buckets, duration: duration, keep: keep))
    }
}
