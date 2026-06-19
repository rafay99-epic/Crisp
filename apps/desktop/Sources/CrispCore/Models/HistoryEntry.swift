import Foundation

/// One past clean, recorded for the History window. A plain value type persisted as
/// one JSON line in `~/.crisp*/history.jsonl` (see `HistoryStore`).
public struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let inputPath: String
    public let outputPath: String
    public let origSeconds: Double
    public let newSeconds: Double
    public let savedSeconds: Double
    public let fillers: Int
    public let pauses: Int

    public init(id: UUID = UUID(), date: Date, inputPath: String, outputPath: String,
                origSeconds: Double, newSeconds: Double, savedSeconds: Double,
                fillers: Int, pauses: Int) {
        self.id = id
        self.date = date
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.origSeconds = origSeconds
        self.newSeconds = newSeconds
        self.savedSeconds = savedSeconds
        self.fillers = fillers
        self.pauses = pauses
    }

    /// Build from a finished clean.
    public init(input: URL, result: CleanResult, date: Date) {
        self.init(date: date, inputPath: input.path, outputPath: result.output,
                  origSeconds: result.origSeconds, newSeconds: result.newSeconds,
                  savedSeconds: result.savedSeconds, fillers: result.fillers, pauses: result.pauses)
    }

    public var inputURL: URL { URL(fileURLWithPath: inputPath) }
    public var outputURL: URL? { outputPath.isEmpty ? nil : URL(fileURLWithPath: outputPath) }
    public var inputName: String { inputURL.lastPathComponent }

    /// "12 fillers · 47 pauses" (or nil) — same phrasing as the result row.
    public var cutsSummary: String? { CleanResult.cutsSummary(fillers: fillers, pauses: pauses) }
}
