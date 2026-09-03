import Foundation

/// Frame-rate policy, ported from `crisp/framerate.py`.
///
/// Screen recorders (OBS, ScreenCaptureKit, QuickTime) emit a new frame only when the
/// picture changes, so their *average* rate falls below their nominal *base* rate:
/// the file is VFR. A trim-and-concat render assumes steady timing, so on a VFR source
/// the cut video drifts out of sync with the constant-rate audio over a long timeline.
/// Normalizing the render to a constant rate fixes that.
///
/// These are pure decisions. The probe that supplies the rates is the media layer's job,
/// which is exactly why this survives the move off ffmpeg unchanged.
public enum FrameRate {
    /// A source counts as VFR when its average rate sits meaningfully below its base
    /// rate. A true CFR file has avg == r; the tolerance absorbs container rounding
    /// (a base reported as 30/1 with an average of 30000/1001).
    public static let vfrRelativeTolerance = 0.005

    /// Rates outside this are treated as implausible metadata, since some containers
    /// report a huge timebase-derived base rate. We never normalize to them.
    public static let maxPlausibleFPS = 240.0

    /// Parse an ffprobe rate string (`num/den`, e.g. `30000/1001`). Returns nil for
    /// `0/0`, `N/A`, empty or malformed input.
    public static func parseFraction(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "N/A" else { return nil }

        guard let slash = trimmed.firstIndex(of: "/") else { return Double(trimmed) }
        guard let numerator = Double(trimmed[trimmed.startIndex..<slash]),
              let denominator = Double(trimmed[trimmed.index(after: slash)...]),
              denominator != 0
        else { return nil }
        return numerator / denominator
    }

    static func isPlausible(_ fps: Double?) -> Bool {
        guard let fps else { return false }
        return fps > 0 && fps <= maxPlausibleFPS
    }

    /// True when the average rate falls below the base rate by more than `tolerance`
    /// (relative). Unknown or zero rates are not VFR: we never normalize what we
    /// cannot read, so a good CFR file is left untouched.
    public static func isVFR(base: Double?, average: Double?,
                             tolerance: Double = vfrRelativeTolerance) -> Bool {
        guard let base, base > 0, let average, average > 0 else { return false }
        return (base - average) / base > tolerance
    }

    /// Format a rate the way ffmpeg's `-r` wants it: `30`, not `30.0`.
    static func format(_ fps: Double) -> String {
        fps == fps.rounded() && abs(fps) < 1e15
            ? String(Int(fps))
            : String(format: "%g", fps)
    }

    /// The constant frame rate to force, or nil to leave the source's timing alone.
    ///
    /// In `.auto`, only a VFR source is normalized, and it goes to its nominal base
    /// rate (the clean CFR value editors expect) or to `requestedFPS` when the caller
    /// supplied one, falling back to the measured average if the base looks implausible.
    ///
    /// The return stays a `String` rather than a `Double` because the exact base
    /// *fraction* is what gets forwarded (`30000/1001`, not `29.97`); rounding it here
    /// would reintroduce the drift this whole path exists to prevent.
    public static func resolveTarget(mode: FPSMode,
                                     requestedFPS: Double?,
                                     baseRateText: String?,
                                     averageRateText: String?) -> String? {
        switch mode {
        case .passthrough:
            return nil
        case .constant:
            guard let requestedFPS, isPlausible(requestedFPS) else { return nil }
            return format(requestedFPS)
        case .auto:
            break
        }

        let base = parseFraction(baseRateText)
        let average = parseFraction(averageRateText)
        guard isVFR(base: base, average: average) else { return nil }

        if let requestedFPS, isPlausible(requestedFPS) { return format(requestedFPS) }
        if isPlausible(base) {
            return baseRateText?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isPlausible(average) {
            return averageRateText?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
