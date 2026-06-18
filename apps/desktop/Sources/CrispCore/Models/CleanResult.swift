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

    public init(output: String, origSeconds: Double, newSeconds: Double,
                savedSeconds: Double, pauses: Int, fillers: Int,
                peaks: [Double] = [], removed: [Bool] = []) {
        self.output = output
        self.origSeconds = origSeconds
        self.newSeconds = newSeconds
        self.savedSeconds = savedSeconds
        self.pauses = pauses
        self.fillers = fillers
        self.peaks = peaks
        self.removed = removed
    }
}
