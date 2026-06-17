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
