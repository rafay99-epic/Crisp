import Foundation

/// A half-open span of the timeline in seconds. The engine speaks in these
/// throughout: detected silences, filler ranges, retake removals, and the kept
/// segments the renderer concatenates are all `TimeSpan`s.
///
/// Python passes these around as bare `(start, end)` tuples, which makes it easy to
/// hand a keep-list where a cut-list was wanted. A named type costs nothing and the
/// compiler catches the swap.
public struct TimeSpan: Hashable, Sendable, Codable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    /// Length in seconds. Negative spans (which callers should never build) report 0.
    public var duration: Double { max(0, end - start) }

    public func contains(_ t: Double) -> Bool { t >= start && t <= end }

    /// Do the two spans share any time at all? Touching endpoints do not overlap.
    public func overlaps(_ other: TimeSpan) -> Bool {
        other.end > start && other.start < end
    }
}

extension TimeSpan: CustomStringConvertible {
    public var description: String { String(format: "[%.3f, %.3f]", start, end) }
}

extension TimeSpan: Comparable {
    /// Chronological: by start, then by end. Lets a cut list be `sorted()` directly.
    public static func < (lhs: TimeSpan, rhs: TimeSpan) -> Bool {
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }
}

/// One transcribed word with the onset/offset whisper's DTW gives us.
public struct Word: Hashable, Sendable, Codable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }

    public var span: TimeSpan { TimeSpan(start: start, end: end) }
}
