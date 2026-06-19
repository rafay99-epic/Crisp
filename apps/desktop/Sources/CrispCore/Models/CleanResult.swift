import Foundation

/// The outcome of cleaning one video — surfaced in the result card.
public struct CleanResult: Identifiable, Sendable {
    public let id = UUID()
    public let output: String
    public let origSeconds: Double
    public let newSeconds: Double
    public let savedSeconds: Double
    public let pauses: Int
    public let fillers: Int
    /// Compact audio waveform for the UI: normalized peak per bucket over the
    /// original audio, and a parallel flag for whether that slice was cut. Empty
    /// unless the engine was asked for it (`--waveform N`).
    public let peaks: [Double]
    public let removed: [Bool]
    /// Separate video-only / audio-only files, when "split tracks" was on (else "").
    public let videoOutput: String
    public let audioOutput: String
    /// Where the pristine original was backed up (`~/.crisp*/Originals/<date>/…`),
    /// or "" when backup was off. Lets the UI offer "Restore Original".
    public let backup: String

    public init(output: String, origSeconds: Double, newSeconds: Double,
                savedSeconds: Double, pauses: Int, fillers: Int,
                peaks: [Double] = [], removed: [Bool] = [],
                videoOutput: String = "", audioOutput: String = "", backup: String = "") {
        self.output = output
        self.origSeconds = origSeconds
        self.newSeconds = newSeconds
        self.savedSeconds = savedSeconds
        self.pauses = pauses
        self.fillers = fillers
        self.peaks = peaks
        self.removed = removed
        self.videoOutput = videoOutput
        self.audioOutput = audioOutput
        self.backup = backup
    }

    /// What was cut, as "12 fillers · 47 pauses" — only the non-zero parts, properly
    /// pluralized, or `nil` when nothing was removed. Used in the queue row, its
    /// context menu, and (summed) the bottom bar so the phrasing stays in one place.
    public var cutsSummary: String? {
        Self.cutsSummary(fillers: fillers, pauses: pauses)
    }

    public static func cutsSummary(fillers: Int, pauses: Int) -> String? {
        var parts: [String] = []
        if fillers > 0 { parts.append("\(fillers) filler\(fillers == 1 ? "" : "s")") }
        if pauses > 0 { parts.append("\(pauses) pause\(pauses == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
