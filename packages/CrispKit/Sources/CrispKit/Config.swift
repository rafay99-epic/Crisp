import Foundation

/// Tunable defaults, ported from `packages/engine/crisp/config.py`.
///
/// This is the single source of truth once the Python engine is gone. Until then the
/// values must stay in lockstep with `config.py`; `ConfigParityTests` pins every one
/// of them against a fixture generated from the Python side so drift fails CI rather
/// than shipping two different "defaults".
public enum CrispDefaults {
    // MARK: Cutting

    /// Copy the original aside before cutting (the safety net).
    public static let backup = true
    /// Cut silences longer than this, in seconds.
    public static let maxPause = 0.6
    /// Audio below this loudness (dB) counts as silence.
    public static let noiseDB = -30.0
    /// Breathing room left around each cut, in seconds.
    public static let keepPause = 0.15
    /// Kept fragments shorter than this are dropped, in seconds.
    public static let minKeep = 0.05
    /// Extra silence kept at each pause in `tighten` mode, on top of `keepPause`.
    public static let tightPause = 0.3

    // MARK: Cut smoothing

    /// Audio fade in/out on each kept segment so joins do not click, in milliseconds.
    public static let fadeMS = 10
    /// Above 0, consecutive segments dissolve instead of hard-cutting, in milliseconds.
    public static let crossfadeMS = 0
    /// Snap each cut boundary to the nearest zero crossing within this window, in milliseconds.
    public static let snapMS = 12

    // MARK: Encoding

    public static let videoCodec = VideoCodec.hevc
    public static let hardware = true
    public static let quality = QualityLevel.high
    public static let audioCodec = AudioCodec.aac
    public static let audioBitrateKbps = 192
    public static let colorDepth = ColorDepth.auto

    // MARK: Frame rate

    public static let fpsMode = FPSMode.auto
    /// Frames per second for `.constant`; 0 is unset.
    public static let fps = 0.0

    // MARK: Filler gating (Core ML backend)

    /// Cut a filler that is not at a pause only when it is at least this long, in seconds.
    public static let fillerMinSolo = 0.5
    /// A filler within this distance of a silence edge counts as "at a pause", in seconds.
    public static let fillerPausePad = 0.2
}

// MARK: - Enumerated options
//
// Python carries these as bare strings validated at the argparse boundary. Modelling
// them as enums moves that validation to compile time and makes the switch statements
// in the encoder and renderer exhaustive.

public enum PauseMode: String, CaseIterable, Sendable, Codable {
    /// Remove the pause entirely.
    case remove
    /// Keep a short natural gap instead of closing the cut completely.
    case tighten

    public static let `default` = PauseMode.remove
}

public enum VideoCodec: String, CaseIterable, Sendable, Codable {
    case h264
    case hevc
    case vp9
}

public enum AudioCodec: String, CaseIterable, Sendable, Codable {
    case aac
    case opus
}

public enum QualityLevel: String, CaseIterable, Sendable, Codable {
    case maximum
    case high
    case balanced
    case smaller
}

public enum ColorDepth: String, CaseIterable, Sendable, Codable {
    /// Match the source, so footage is never silently downgraded.
    case auto
    case eight = "8"
    case ten = "10"
}

public enum FPSMode: String, CaseIterable, Sendable, Codable {
    /// Normalize a detected VFR source to a constant rate; leave a CFR source alone.
    case auto
    /// Never touch timing.
    case passthrough
    /// Always force the requested rate.
    case constant
}

public enum CaptionFormat: String, CaseIterable, Sendable, Codable {
    case none
    case srt
    case vtt
    case both
}

// MARK: - Retake policy

/// The full policy behind a retake sensitivity, not just a word count.
///
/// `minRunNoPause` is the load-bearing precision signal for pause-less restarts: a
/// verbatim repeat that long is hard to produce by accident, so it is trusted without
/// a silence anchor. `semanticMin` can only ever *rescue* a shorter repeat, never veto
/// one, because Apple's short-phrase embedding scores real redos and intentional
/// parallel structure about the same.
public struct RetakePolicy: Hashable, Sendable {
    /// Matched words needed to treat a pause-anchored repeat as a redo.
    public var minRun: Int
    /// Must a short repeat begin right after a silence?
    public var requirePause: Bool
    /// Accept a pause-less repeat once the run reaches this. `nil` means a pause is always required.
    public var minRunNoPause: Int?
    /// Semantic-similarity bar that can rescue a shorter pause-less repeat.
    public var semanticMin: Double

    public init(minRun: Int, requirePause: Bool, minRunNoPause: Int?, semanticMin: Double) {
        self.minRun = minRun
        self.requirePause = requirePause
        self.minRunNoPause = minRunNoPause
        self.semanticMin = semanticMin
    }
}

public enum RetakeSensitivity: String, CaseIterable, Sendable, Codable {
    case gentle
    case balanced
    case aggressive

    /// Validated on real talking-head footage: catches the natural mid-sentence
    /// restarts most speakers make (no pause, no marker) while the run-length floor
    /// holds precision. The gentler presets stay available for list-heavy content,
    /// where a shorter run over-cuts intentional parallel structure.
    public static let `default` = RetakeSensitivity.aggressive

    public var policy: RetakePolicy {
        switch self {
        case .gentle:
            RetakePolicy(minRun: 5, requirePause: true, minRunNoPause: nil, semanticMin: 0.78)
        case .balanced:
            RetakePolicy(minRun: 4, requirePause: true, minRunNoPause: 7, semanticMin: 0.78)
        case .aggressive:
            RetakePolicy(minRun: 3, requirePause: false, minRunNoPause: 5, semanticMin: 0.70)
        }
    }
}

public extension CrispDefaults {
    static let removeRetakes = true
    static let retakeSensitivity = RetakeSensitivity.default
    /// The bare-call policy mirrors the whole default preset, not just its run floor,
    /// so a direct library call behaves exactly like the app's default.
    static let retakePolicy = RetakeSensitivity.default.policy

    /// Seconds: a retake follows its flubbed take within this gap.
    static let retakeMaxGap = 2.0
    /// Words: longest abandoned take to look across, which bounds the search.
    static let retakeMaxAbandon = 12
    /// Two takes of the same line rarely transcribe identically, so tokens this
    /// similar count as the same word. Kept high, and short tokens still need an
    /// exact match, so genuinely different words never merge.
    static let retakeTokenSimilarity = 0.85
    /// A redo pause is brief (~0.3 s), so anchors are detected at their own threshold
    /// rather than the much longer cut threshold, which would miss them entirely.
    static let retakeAnchorPause = 0.3
    /// Seconds: how close the retake onset must sit to a silence edge.
    static let retakePausePad = 0.35
    /// Single-word stutter trimming is off by default: a back-to-back repeat is
    /// ambiguous, since intentional emphasis ("very very") looks identical to a stumble.
    static let retakeStutter = false
    /// Seconds: how close the repeated single word must be, when stutter trimming is on.
    static let retakeStutterMaxGap = 1.0
}
