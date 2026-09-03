import Foundation

/// Ratcliff-Obershelp similarity, matching Python's `difflib.SequenceMatcher.ratio()`.
///
/// Retake detection tunes its token threshold (`retakeTokenSimilarity = 0.85`) against
/// difflib's specific numbers, so an approximation is not good enough: a Levenshtein or
/// LCS ratio scores the same pair differently and would silently shift which words
/// count as "the same word" between takes. This reproduces difflib's algorithm instead.
///
/// difflib's `autojunk` heuristic (which treats elements appearing in more than 1% of a
/// sequence as junk) only engages for sequences of 200 or more elements. Callers here
/// compare single word tokens, so it can never apply; `ratio` asserts that rather than
/// implementing a branch it cannot reach.
enum SequenceRatio {
    /// 2 * (matched characters) / (total characters), in `0...1`. Two empty strings
    /// score 1.0, matching difflib.
    static func ratio(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        let total = x.count + y.count
        guard total > 0 else { return 1.0 }
        precondition(y.count < 200, "SequenceRatio does not implement difflib autojunk")
        let matches = matchCount(x, y, 0, x.count, 0, y.count)
        return 2.0 * Double(matches) / Double(total)
    }

    /// difflib's recursion: take the longest contiguous match, then recurse into the
    /// regions to its left and right and sum what they contribute.
    private static func matchCount(_ a: [Character], _ b: [Character],
                                   _ alo: Int, _ ahi: Int,
                                   _ blo: Int, _ bhi: Int) -> Int {
        let (i, j, k) = longestMatch(a, b, alo, ahi, blo, bhi)
        guard k > 0 else { return 0 }
        return k
            + matchCount(a, b, alo, i, blo, j)
            + matchCount(a, b, i + k, ahi, j + k, bhi)
    }

    /// The longest contiguous matching block in `a[alo..<ahi]` / `b[blo..<bhi]`,
    /// returned as `(indexInA, indexInB, length)`. Ties resolve to the earliest `i`
    /// then the earliest `j`, which is what difflib guarantees and what makes the
    /// recursion above deterministic.
    private static func longestMatch(_ a: [Character], _ b: [Character],
                                     _ alo: Int, _ ahi: Int,
                                     _ blo: Int, _ bhi: Int) -> (Int, Int, Int) {
        // b2j: every position each character occupies in b, so the inner loop walks
        // only real candidates instead of rescanning b. Same structure as difflib.
        var b2j: [Character: [Int]] = [:]
        for index in blo..<bhi { b2j[b[index], default: []].append(index) }

        var bestI = alo, bestJ = blo, bestSize = 0
        // j2len[j] = length of the match ending at a[i-1]/b[j-1]; rebuilt per row.
        var j2len: [Int: Int] = [:]

        for i in alo..<ahi {
            var newJ2len: [Int: Int] = [:]
            for j in b2j[a[i], default: []] {
                if j < blo { continue }
                if j >= bhi { break }
                let k = (j2len[j - 1] ?? 0) + 1
                newJ2len[j] = k
                if k > bestSize {
                    bestI = i - k + 1
                    bestJ = j - k + 1
                    bestSize = k
                }
            }
            j2len = newJ2len
        }
        return (bestI, bestJ, bestSize)
    }
}
