import Foundation

/// One video in the clean queue. The app builds a queue of these one file at a
/// time, then cleans several at once (bounded by the resource governor). A plain
/// value type mutated in place inside `CleanModel`'s observable array — so a row's
/// status/progress change publishes to the UI without per-item observation.
public struct QueueItem: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    /// Which saved preset this file uses; `nil` ⇒ the window's default recipe.
    public var presetID: UUID?
    public var status: Status
    /// 0…1 for this file alone, while it's running.
    public var progress: Double
    /// Set once the file finishes cleaning.
    public var result: CleanResult?
    /// A human-readable failure message when `status == .failed`.
    public var error: String?
    /// An explicit keep-list the user approved in the review timeline, as `(start,
    /// end)` seconds on the original timeline. When set, this file is cleaned to
    /// exactly these segments (the engine skips detection/transcription); `nil` ⇒ the
    /// normal recipe-driven clean.
    public var editedKeep: [ClosedRange<Double>]?

    public enum Status: Sendable, Equatable {
        case waiting, running, done, failed, cancelled
    }

    public init(url: URL, presetID: UUID? = nil) {
        self.id = UUID()
        self.url = url
        self.presetID = presetID
        self.status = .waiting
        self.progress = 0
        self.result = nil
        self.error = nil
        self.editedKeep = nil
    }

    /// A waiting item is the only kind the user may reorder or remove — anything
    /// already running/finished stays put.
    public var isWaiting: Bool { status == .waiting }
}
