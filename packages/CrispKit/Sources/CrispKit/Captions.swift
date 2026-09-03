import Foundation

/// Subtitle export, ported from `crisp/captions.py`.
///
/// The engine already has per-word timestamps from transcription, so captions cost
/// almost nothing extra: re-time those words onto the *cleaned* (jump-cut) timeline and
/// group them into cues. Cue shaping follows broadcast norms (Netflix/BBC): at most two
/// lines of 42 characters, a readable minimum duration, and a forced break at sentence
/// ends and pauses.
///
/// Pure string and number math, so it ports unchanged and stays fully testable.
public enum Captions {
    public static let maxCharsPerLine = 42
    public static let maxLines = 2
    /// Seconds. Roughly Netflix's 5/6 s floor.
    public static let minCueDuration = 0.85
    /// Seconds. Under Netflix's 7 s ceiling.
    public static let maxCueDuration = 6.0
    /// A gap at least this long between words forces a new cue.
    public static let cueSplitGap = 0.5
    /// Roughly two frames kept between adjacent cues.
    public static let minGap = 0.08

    public struct Cue: Hashable, Sendable {
        public var start: Double
        public var end: Double
        public var lines: [String]

        public init(start: Double, end: Double, lines: [String]) {
            self.start = start
            self.end = end
            self.lines = lines
        }

        public var text: String { lines.joined(separator: "\n") }
    }

    /// Map a time on the original timeline to the cleaned one. A time inside a removed
    /// gap clamps to the start of the next kept segment.
    public static func originalToCleaned(_ t: Double, keep: [TimeSpan]) -> Double {
        var offset = 0.0
        for segment in keep {
            if t < segment.start { return offset }
            if t <= segment.end { return offset + (t - segment.start) }
            offset += segment.end - segment.start
        }
        return offset
    }

    /// Re-time spoken words onto the cleaned timeline. Drops fillers (they were cut)
    /// and words that fall entirely inside a removed region; clamps a word straddling a
    /// cut to the kept segment it overlaps.
    public static func retimeWords(_ words: [Word], keep: [TimeSpan]) -> [Word] {
        var out: [Word] = []
        for word in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Filler.isFiller(word.text) else { continue }
            guard let segment = keep.first(where: { word.end > $0.start && word.start < $0.end })
            else { continue }   // lives entirely in a removed gap

            let start = originalToCleaned(max(word.start, segment.start), keep: keep)
            var end = originalToCleaned(min(word.end, segment.end), keep: keep)
            if end <= start { end = start + 0.04 }
            out.append(Word(text: text, start: start, end: end))
        }
        return out
    }

    /// Greedy word wrap into lines of at most `maxChars`. Never splits a word.
    static func wrapLines(_ text: String, maxChars: Int = maxCharsPerLine) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= maxChars {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.isEmpty ? [text] : lines
    }

    static func makeCue(_ words: [Word]) -> Cue {
        let text = words.map(\.text).joined(separator: " ")
        return Cue(start: words[0].start, end: words[words.count - 1].end, lines: wrapLines(text))
    }

    /// Pack re-timed words into cues: break at a sentence end, at a pause, or when the
    /// running cue would exceed the line-count or duration limit. Then nudge too-short
    /// cues up to `minCueDuration` so a quick word still stays readable.
    public static func groupIntoCues(_ words: [Word]) -> [Cue] {
        var cues: [Cue] = []
        var current: [Word] = []

        func wouldOverflow(_ next: Word) -> Bool {
            let text = (current + [next]).map(\.text).joined(separator: " ")
            let duration = next.end - current[0].start
            return wrapLines(text).count > maxLines || duration > maxCueDuration
        }

        for word in words {
            if let last = current.last {
                let gap = word.start - last.end
                let trimmed = last.text.trimmingCharacters(in: .whitespaces)
                let endsSentence = trimmed.hasSuffix(".") || trimmed.hasSuffix("!")
                    || trimmed.hasSuffix("?") || trimmed.hasSuffix("…")
                if gap >= cueSplitGap || endsSentence || wouldOverflow(word) {
                    cues.append(makeCue(current))
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { cues.append(makeCue(current)) }

        for index in cues.indices where cues[index].end - cues[index].start < minCueDuration {
            let ceiling = index + 1 < cues.count
                ? cues[index + 1].start - minGap
                : cues[index].start + minCueDuration
            cues[index].end = max(cues[index].end,
                                  min(cues[index].start + minCueDuration,
                                      max(ceiling, cues[index].end)))
        }
        return cues
    }

    /// `HH:MM:SS<sep>mmm`, where `sep` is "," for SubRip and "." for WebVTT.
    static func formatTimestamp(_ seconds: Double, separator: String) -> String {
        var ms = Int((max(0, seconds) * 1000).rounded())
        let hours = ms / 3_600_000; ms %= 3_600_000
        let minutes = ms / 60_000;  ms %= 60_000
        let secs = ms / 1000;       ms %= 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, ms)
    }

    /// SubRip: numbered cues, comma-separated milliseconds, CRLF line endings.
    public static func toSRT(_ cues: [Cue]) -> String {
        guard !cues.isEmpty else { return "" }
        let blocks = cues.enumerated().map { index, cue -> String in
            var body = [String(index + 1),
                        "\(formatTimestamp(cue.start, separator: ",")) --> "
                            + formatTimestamp(cue.end, separator: ",")]
            body.append(contentsOf: cue.lines)
            body.append("")
            return body.joined(separator: "\r\n")
        }
        return blocks.joined(separator: "\r\n") + "\r\n"
    }

    static func escapeVTT(_ line: String) -> String {
        line.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// WebVTT: header, dot-separated milliseconds, escaped cue text.
    public static func toVTT(_ cues: [Cue]) -> String {
        var out = ["WEBVTT", ""]
        for cue in cues {
            out.append("\(formatTimestamp(cue.start, separator: ".")) --> "
                        + formatTimestamp(cue.end, separator: "."))
            out.append(contentsOf: cue.lines.map(escapeVTT))
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Sidecar paths beside the cleaned output: `clip_cleaned.mp4` gives
    /// `clip_cleaned.srt` and `clip_cleaned.vtt`. Pure path arithmetic, no I/O.
    public static func captionPaths(for output: URL) -> (srt: URL, vtt: URL) {
        (output.deletingPathExtension().appendingPathExtension("srt"),
         output.deletingPathExtension().appendingPathExtension("vtt"))
    }

    /// Words on the original timeline plus the kept segments, giving cues on the
    /// cleaned timeline.
    public static func build(words: [Word], keep: [TimeSpan]) -> [Cue] {
        groupIntoCues(retimeWords(words, keep: keep))
    }
}
