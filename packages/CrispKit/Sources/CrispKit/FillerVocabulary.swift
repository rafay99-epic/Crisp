import Foundation

/// Filler-word matching, ported from `crisp/text.py` + the vocabulary in `config.py`.
///
/// Matching is anchored (whole token only), so ordinary words such as "away", "him",
/// "human", or the verb "hum" are never treated as fillers.
public enum Filler {
    /// The common short forms, compared after lower-casing and stripping punctuation.
    /// The shape patterns below catch the endless elongated variants whisper emits.
    public static let vocabulary: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "uhmm", "umh", "ummh",
        "er", "err", "erm", "errm",
        "hm", "hmm", "huh", "hu", "humm",
        "mm", "mmm", "mhm", "mhmm", "mmhmm",
        "ah", "ahh", "ahem", "aw", "aww",
        "uh-huh", "mm-hmm",
    ]

    /// Hesitation sounds appear in countless spellings, so these match their *shape*
    /// rather than enumerating them. Applied as whole-token matches.
    static let patternSources = [
        "u+m+h*",             // um, umm, ummm, umh, ummh
        "u+h+m*",             // uh, uhh, uhhh, uhm, uhmm
        "h+u+h+",             // huh, huhh
        "h+u+m{2,}",          // humm, hummm (2+ m's so the verb "hum" is left alone)
        "h+m+",               // hm, hmm, hmmm
        "e+r+m*",             // er, err, erm, errm
        "a+h+",               // ah, ahh, aah
        "a+w+",               // aw, aww, awww
        "m{2,}",              // mm, mmm
        "m+h+m*",             // mhm, mmhm, mhmm
        "u+h+[-\\s]?h+u+h+",  // uh-huh, uhhuh
        "m+h?[-\\s]?h+m+",    // mm-hmm, mhmm
    ]

    /// Compiled once, each wrapped in `^(?:…)$` so it can only match a WHOLE token.
    /// That mirrors Python's `re.fullmatch` exactly: relying on a greedy match to
    /// happen to consume the whole string would quietly misclassify any token where
    /// the engine backtracks to a shorter alternative. The sources are literals under
    /// our control, so a failure here is a programming error, not a runtime condition.
    static let patterns: [NSRegularExpression] = patternSources.map { source in
        guard let re = try? NSRegularExpression(pattern: "^(?:\(source))$") else {
            preconditionFailure("CrispKit: malformed filler pattern \(source)")
        }
        return re
    }

    /// Characters Python's `str.strip(...)` peels off both ends of a token before
    /// matching. Kept identical to `text.py` so tokenization cannot drift.
    static let trimmed = CharacterSet(charactersIn: ".,!?;:\"'()[]…-–—")
        .union(.whitespacesAndNewlines)

    /// Lower-cased, punctuation-stripped form of a transcript token.
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: trimmed).lowercased()
    }

    /// Is this token a hesitation sound (um / uh / hmm / aww / huh and their many
    /// elongated spellings) rather than real speech?
    public static func isFiller(_ text: String) -> Bool {
        let word = normalize(text)
        guard !word.isEmpty else { return false }
        if vocabulary.contains(word) { return true }
        let range = NSRange(word.startIndex..<word.endIndex, in: word)
        return patterns.contains { $0.firstMatch(in: word, options: [], range: range) != nil }
    }
}
