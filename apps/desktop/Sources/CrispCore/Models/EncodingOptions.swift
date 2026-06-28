/// Encoder choices for the re-render. Each `rawValue` is exactly the string the
/// engine CLI expects (so the config JSON and `--video-codec`/`--quality`/… line
/// up); `label` is the human name shown in the Settings pickers.

public enum VideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }
}

public enum VideoQuality: String, CaseIterable, Identifiable {
    case maximum, high, balanced, smaller
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .maximum:  return "Maximum"
        case .high:     return "High"
        case .balanced: return "Balanced"
        case .smaller:  return "Smaller file"
        }
    }
}

/// Output bit depth (color depth) of the rendered clean. `auto` matches the source
/// — a 10-bit / HDR / wide-chroma recording is preserved, an 8-bit source stays
/// 8-bit — so footage is never silently downgraded. `force8`/`force10` override that.
/// Each `rawValue` is exactly the string the engine's `--color-depth` flag expects.
public enum ColorDepth: String, CaseIterable, Identifiable {
    case auto, force8 = "8", force10 = "10"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto:    return "Automatic (match source)"
        case .force8:  return "8-bit (SDR)"
        case .force10: return "10-bit"
        }
    }
    public var detail: String {
        switch self {
        case .auto:    return "Matches your footage \u{2014} 10-bit, HDR, and wide-chroma recordings keep their color depth; ordinary 8-bit footage stays 8-bit and fast. Recommended."
        case .force8:  return "Always 8-bit 4:2:0. Smallest and fastest, and can use hardware encoding \u{2014} but crushes a 10-bit/HDR source. Only force this if your editor or upload needs 8-bit."
        case .force10: return "Always a 10-bit encode (software, slower, larger). Keeps a 10-bit source at 10-bit; an 8-bit source is upconverted \u{2014} which adds no real quality, so leave this on Automatic unless a delivery spec demands 10-bit."
        }
    }

    /// True only for the forced-10-bit choice, which upconverts an 8-bit source for no
    /// real gain — the Settings UI confirms before committing to it.
    public var warnsOnSelect: Bool { self == .force10 }
}

public enum AudioCodec: String, CaseIterable, Identifiable {
    case aac, opus
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .aac:  return "AAC"
        case .opus: return "Opus"
        }
    }
}

/// Output container. `auto` matches the input file (an .mkv stays .mkv, an .mp4
/// stays .mp4); the rest force a specific wrapper. Each `rawValue` is exactly the
/// string the engine's `--container` flag expects.
public enum OutputContainer: String, CaseIterable, Identifiable {
    case auto, mp4, mkv, mov, m4v, ts, webm
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto: return "Same as input"
        case .mp4:  return "MP4 (.mp4)"
        case .mkv:  return "Matroska (.mkv)"
        case .mov:  return "QuickTime (.mov)"
        case .m4v:  return "MPEG-4 (.m4v)"
        case .ts:   return "MPEG-TS (.ts)"
        case .webm: return "WebM (VP9 · .webm)"
        }
    }

    /// WebM is its own codec world (VP9 video + Opus audio), so the video/audio/
    /// hardware choices don't apply when it's selected — the UI disables them.
    public var forcesOwnCodecs: Bool { self == .webm }
}

/// How Crisp handles the source's frame rate on render. Screen recorders (OBS,
/// macOS screen capture) emit variable-frame-rate (VFR) video, which the
/// trim→concat render can drift audio/video apart on; normalizing to a constant
/// rate fixes it. Each `rawValue` is exactly the engine's `--fps-mode` value.
public enum FrameRateMode: String, CaseIterable, Identifiable {
    case auto, passthrough, constant
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto:        return "Automatic"
        case .passthrough: return "Keep source timing"
        case .constant:    return "Constant rate"
        }
    }
    public var detail: String {
        switch self {
        case .auto:        return "Detects variable-frame-rate recordings (screen captures, OBS) and normalizes them to a constant rate so audio and video stay in sync. Leaves normal footage untouched. Recommended."
        case .passthrough: return "Never changes frame timing. Fastest, but a variable-frame-rate source may drift out of sync after cutting."
        case .constant:    return "Always re-times the output to the exact rate you choose below — for matching a specific delivery spec."
        }
    }
    /// The chosen rate only applies in `.constant` mode; the other modes ignore it.
    public var usesValue: Bool { self == .constant }
}

/// Common constant frame rates offered in Settings when "Constant rate" is picked.
/// Editors and delivery specs cluster on these; a power user can still hand-edit
/// `settings.json` to anything the engine's `--fps` accepts.
public let commonFrameRates: [Double] = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60]

/// Subtitle sidecars to write beside the cleaned video, re-timed onto the cut
/// timeline. `none` writes nothing; `srt` is SubRip (the universal format every
/// editor and YouTube accepts); `vtt` is WebVTT (the web/HTML5 `<track>` format);
/// `both` writes the pair. Each `rawValue` is exactly the string the engine's
/// `--captions` flag expects.
public enum CaptionFormat: String, CaseIterable, Identifiable {
    case none, srt, vtt, both
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "Off"
        case .srt:  return "SubRip (.srt)"
        case .vtt:  return "WebVTT (.vtt)"
        case .both: return "Both (.srt + .vtt)"
        }
    }

    /// Captions are transcribed from speech, so any choice but `none` needs the
    /// speech model — same gate as filler removal.
    public var needsTranscript: Bool { self != .none }
}

/// How eagerly to remove repeated takes (a phrase you flubbed and redid). Lower
/// sensitivity requires a longer matched run before cutting — fewer, safer cuts;
/// higher catches shorter redos. Each `rawValue` is the engine's `--retake-sensitivity`
/// value. (On/off is the separate "Remove repeated takes" toggle.)
public enum RetakeSensitivity: String, CaseIterable, Identifiable {
    case gentle, balanced, aggressive
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .gentle:     return "Gentle"
        case .balanced:   return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }
    public var detail: String {
        switch self {
        case .gentle:     return "Only long redos that begin after a clear pause. Safest — least likely to cut intentional repetition."
        case .balanced:   return "The sweet spot for most recordings."
        case .aggressive: return "Also catches mid-sentence restarts with no pause — for heavy retakers. May cut a repeated phrase you meant."
        }
    }
}

/// Format for the separate audio track when "split tracks" is on. `match` copies
/// the cleaned audio stream as-is (lossless, no re-encode — `.m4a` for AAC, Ogg
/// `.opus` for Opus); `wav` re-encodes it to uncompressed PCM, the format most
/// editors prefer. Each `rawValue` is the string the engine's `--split-audio`
/// flag expects.
public enum SplitAudioFormat: String, CaseIterable, Identifiable {
    case match, wav
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .match: return "Same as the video"
        case .wav:   return "WAV (uncompressed)"
        }
    }
}
