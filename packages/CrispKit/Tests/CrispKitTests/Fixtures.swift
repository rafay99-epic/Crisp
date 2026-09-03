import Foundation
import CrispKit
import XCTest

/// Loader for the golden fixtures in `Fixtures/`, which are generated from the Python
/// engine by `Tools/generate-fixtures.py`.
///
/// The point of these tests is parity, not plausibility: CrispKit is replacing a
/// working implementation, so "looks right" is not the bar. Every case here was
/// produced by running the Python code, so a Swift result that differs is a port bug
/// by definition.
enum Fixture {
    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
                ?? Bundle.module.url(forResource: name, withExtension: "json",
                                     subdirectory: "Fixtures")
        else {
            throw XCTSkip("fixture \(name).json not found in the test bundle")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

// MARK: - Fixture shapes

struct FillerCase: Decodable {
    let token: String
    let normalized: String
    let isFiller: Bool
}

struct RatioCase: Decodable {
    let a: String
    let b: String
    let ratio: Double
}

struct RawWord: Decodable {
    let text: String
    let start: Double
    let end: Double

    var word: Word { Word(text: text, start: start, end: end) }
}

struct RetakeCase: Decodable {
    struct Options: Decodable {
        let sensitivity: String?
        let silences: [[Double]]?
        let stutter: Bool?
    }
    let name: String
    let words: [RawWord]
    let options: Options
    let expected: [[Double]]

    var sensitivity: RetakeSensitivity {
        RetakeSensitivity(rawValue: options.sensitivity ?? "aggressive") ?? .aggressive
    }

    /// `nil` (no silence data at all) and `[]` (silence detection ran and found none)
    /// are different inputs to the detector, and the fixtures cover both.
    var silences: [TimeSpan]? {
        options.silences.map { $0.map { TimeSpan(start: $0[0], end: $0[1]) } }
    }

    var expectedSpans: [TimeSpan] {
        expected.map { TimeSpan(start: $0[0], end: $0[1]) }
    }
}

struct FrameRateCase: Decodable {
    let mode: String
    let requestedFPS: Double
    let base: String
    let average: String
    let expected: String?
}

struct CaptionCase: Decodable {
    struct Expected: Decodable {
        struct Cue: Decodable {
            let start: Double
            let end: Double
            let lines: [String]
        }
        let cues: [Cue]
        let srt: String
        let vtt: String
    }
    let name: String
    let words: [RawWord]
    let keep: [[Double]]
    let expected: Expected

    var keepSpans: [TimeSpan] { keep.map { TimeSpan(start: $0[0], end: $0[1]) } }
}

struct WaveformFixture: Decodable {
    struct PeakCase: Decodable {
        let name: String
        let samples: [Int]
        let buckets: Int
        let expected: [Double]
    }
    struct RemovedCase: Decodable {
        let name: String
        let buckets: Int
        let duration: Double
        let keep: [[Double]]
        let expected: [Bool]

        var keepSpans: [TimeSpan] { keep.map { TimeSpan(start: $0[0], end: $0[1]) } }
    }
    let peaks: [PeakCase]
    let removed: [RemovedCase]
}

struct ConfigFixture: Decodable {
    struct Sensitivity: Decodable {
        let min_run: Int
        let require_pause: Bool
        let min_run_no_pause: Int?
        let sem_min: Double
    }
    struct CaptionConsts: Decodable {
        let maxCharsPerLine: Int
        let maxLines: Int
        let minCueDur: Double
        let maxCueDur: Double
        let cueSplitGap: Double
        let minGap: Double
    }
    struct FrameRateConsts: Decodable {
        let vfrRelTol: Double
        let maxPlausibleFPS: Double
    }

    let maxPause: Double
    let noiseDB: Double
    let keepPause: Double
    let minKeep: Double
    let tightPause: Double
    let fadeMS: Int
    let crossfadeMS: Int
    let snapMS: Int
    let audioBitrateKbps: Int
    let fillerMinSolo: Double
    let fillerPausePad: Double
    let retakeMaxGap: Double
    let retakeMaxAbandon: Int
    let retakeTokenSimilarity: Double
    let retakeAnchorPause: Double
    let retakePausePad: Double
    let retakeStutterMaxGap: Double
    let defaultSensitivity: String
    let sensitivities: [String: Sensitivity]
    let fillerVocabulary: [String]
    let captions: CaptionConsts
    let framerate: FrameRateConsts
}
