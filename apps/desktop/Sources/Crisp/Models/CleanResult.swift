import Foundation

/// The outcome of cleaning one video — surfaced in the result card.
struct CleanResult: Identifiable {
    let id = UUID()
    let output: String
    let origSeconds: Double
    let newSeconds: Double
    let savedSeconds: Double
    let pauses: Int
    let fillers: Int
}
