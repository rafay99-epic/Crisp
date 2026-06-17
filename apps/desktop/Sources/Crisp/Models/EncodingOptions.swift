/// Encoder choices for the re-render. Each `rawValue` is exactly the string the
/// engine CLI expects (so the config JSON and `--video-codec`/`--quality`/… line
/// up); `label` is the human name shown in the Settings pickers.

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case maximum, high, balanced, smaller
    var id: String { rawValue }
    var label: String {
        switch self {
        case .maximum:  return "Maximum"
        case .high:     return "High"
        case .balanced: return "Balanced"
        case .smaller:  return "Smaller file"
        }
    }
}

enum AudioCodec: String, CaseIterable, Identifiable {
    case aac, opus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aac:  return "AAC"
        case .opus: return "Opus"
        }
    }
}

/// Output container. `auto` matches the input file (an .mkv stays .mkv, an .mp4
/// stays .mp4); the rest force a specific wrapper. Each `rawValue` is exactly the
/// string the engine's `--container` flag expects.
enum OutputContainer: String, CaseIterable, Identifiable {
    case auto, mp4, mkv, mov, m4v, ts, webm
    var id: String { rawValue }
    var label: String {
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
    var forcesOwnCodecs: Bool { self == .webm }
}
