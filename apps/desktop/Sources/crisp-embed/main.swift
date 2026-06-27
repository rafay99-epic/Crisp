// crisp-embed — the semantic-similarity helper the engine shells out to (CRISP_EMBED).
//
// Reads JSON {"pairs": [["a", "b"], …]} on stdin and prints
// {"similarities": [0.87, …]} on stdout — one cosine similarity (−1…1, higher = more
// alike in meaning) per pair, from Apple's on-device NaturalLanguage SENTENCE
// embeddings. No network, no bundled model file: the embedding ships with macOS.
//
// Retake detection uses this to tell a genuine redo (the corrected take means the
// same as the flubbed one) from intentional parallel structure that merely repeats
// words. Standalone — no CrispCore dependency — and resolved exactly like
// ffmpeg/whisper/crisp-filler. Exits non-zero with a stderr message when the
// embedding isn't available (older macOS / missing asset) so the engine falls back to
// word-matching + the pause anchor.
//
// Usage:  echo '{"pairs":[["hi there","hi there"]]}' | crisp-embed

import Foundation
import NaturalLanguage

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("crisp-embed: \(message)\n".utf8))
    exit(1)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let rawPairs = root["pairs"] as? [[Any]] else {
    fail(#"expected JSON {"pairs": [["a","b"], …]} on stdin"#)
}

guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
    fail("English sentence embedding is unavailable on this system")
}

var similarities: [Double] = []
similarities.reserveCapacity(rawPairs.count)
for raw in rawPairs {
    // Fail fast on a malformed pair rather than silently dropping non-string elements.
    guard raw.count == 2, let a = raw[0] as? String, let b = raw[1] as? String else {
        fail("each pair needs exactly two strings")
    }
    if a.isEmpty || b.isEmpty {
        similarities.append(0)
        continue
    }
    // NLEmbedding cosine *distance* runs 0 (identical) … 2 (opposite); similarity is
    // 1 − distance. A non-finite distance (e.g. no vector for the text) → 0 (neutral).
    let distance = embedding.distance(between: a, and: b, distanceType: .cosine)
    let similarity = 1.0 - distance
    similarities.append(similarity.isFinite ? similarity : 0)
}

guard let out = try? JSONSerialization.data(withJSONObject: ["similarities": similarities]) else {
    fail("failed to encode result")
}
FileHandle.standardOutput.write(out)
