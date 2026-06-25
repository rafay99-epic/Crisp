import Foundation

// Mirrors the JSON emitted by `python -m filler_classifier.report`.
// Decoded with `.convertFromSnakeCase`, so snake_case keys map to these camelCase
// properties. Unknown keys (e.g. "checkpoint") are ignored.

struct Report: Codable {
    let dataset: String
    let split: String
    let nExamples: Int
    let nFiller: Int
    let nNonfiller: Int
    let speed: Speed
    let bestF1Threshold: SweepPoint
    let sweep: [SweepPoint]
    let falsePositivesByClass: [FPClass]
    let recallByFiller: [RecallPoint]
}

struct Speed: Codable {
    let chunksPerSec: Double
    let realtimeFactor: Double
}

struct SweepPoint: Codable, Identifiable {
    let threshold: Double
    let precision: Double
    let recall: Double
    let f1: Double
    var id: Double { threshold }
}

struct FPClass: Codable, Identifiable {
    let label: String
    let fp: Int
    let total: Int
    let pct: Double
    var id: String { label }
}

struct RecallPoint: Codable, Identifiable {
    let label: String
    let recall: Double
    let n: Int
    var id: String { label }
}
