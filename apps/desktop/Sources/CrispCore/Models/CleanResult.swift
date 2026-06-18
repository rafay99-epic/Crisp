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

    public init(output: String, origSeconds: Double, newSeconds: Double,
                savedSeconds: Double, pauses: Int, fillers: Int) {
        self.output = output
        self.origSeconds = origSeconds
        self.newSeconds = newSeconds
        self.savedSeconds = savedSeconds
        self.pauses = pauses
        self.fillers = fillers
    }
}
