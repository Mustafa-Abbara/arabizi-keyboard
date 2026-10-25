import Foundation

/// A word as typed in a sentence: leading punctuation, the word itself, trailing punctuation or emoji.
public struct WordParts: Equatable, Sendable {
    public let lead: String
    public let core: String
    public let trail: String

    public init(_ word: String) {
        let isWord = { (s: Unicode.Scalar) in s.properties.isAlphabetic || s.properties.numericType != nil }
        let scalars = Array(word.unicodeScalars)
        guard let start = scalars.firstIndex(where: isWord), let end = scalars.lastIndex(where: isWord) else {
            (lead, core, trail) = ("", word, "")
            return
        }
        func text(_ range: some RangeExpression<Int>) -> String { String(String.UnicodeScalarView(scalars[range])) }
        (lead, core, trail) = (text(..<start), text(start...end), text((end + 1)...))
    }

    /// The same punctuation around another word.
    public func with(_ newCore: String) -> String { lead + newCore + trail }
}

/// Spellings to offer for one word of a conversion (ADR 0027), at most 5, the shown word never offered back:
/// 1. the rules' spelling of the typed Arabizi word;
/// 2. the Arabic of dictionary words typed one letter differently (`sabiyeh`, `sabiyi` for `sabiye`), when that
///    Arabic looks like the shown word (at least half the letters in common), closest first;
/// 3. one-letter and long-vowel variants of the shown word that the dictionary knows as words;
/// 4. the typed word itself, to keep it in Latin.
public struct Suggestions: Sendable {
    /// The rule dictionary: Arabizi word -> Arabic spelling.
    let dictionary: [String: String]
    /// The dictionary's Arabizi words by length, so neighbours are looked up among similar lengths only.
    let byLength: [Int: [(key: [Character], arabic: String)]]
    /// Arabic spellings the dictionary knows; a variant is offered only if it is one of them.
    let knownArabic: Set<String>
    let rules: @Sendable (String) -> String

    public init(dictionary: [String: String], rules: @escaping @Sendable (String) -> String) {
        self.dictionary = dictionary
        self.knownArabic = Set(dictionary.values)
        self.byLength = Dictionary(grouping: dictionary.map { (key: Array($0.key), arabic: $0.value) },
                                   by: { $0.key.count })
        self.rules = rules
    }

    /// The words of a rule dictionary file (data/rules/arabizi_lexicon.json).
    public static func dictionary(lexicon: Data) -> [String: String] {
        (try? JSONDecoder().decode(LexiconWords.self, from: lexicon))?.words ?? [:]
    }

    public func candidates(for shown: String, latin: String?, limit: Int = 5) -> [String] {
        let word = WordParts(shown).core
        var out: [String] = []
        func add(_ candidate: String) {
            if !candidate.isEmpty, candidate != word, !out.contains(candidate) { out.append(candidate) }
        }
        let latinCore = latin.map { WordParts($0).core }
        if let latinCore, !latinCore.isEmpty {
            let ruled = WordParts(rules(latinCore)).core
            if ruled.unicodeScalars.contains(where: Self.isArabicLetter) { add(ruled) }
        }
        if let typed = latinCore?.lowercased(), !typed.isEmpty {
            let letters = Array(typed)
            let candidates = (letters.count - 1...letters.count + 1).flatMap { byLength[$0] ?? [] }
            let neighbours = candidates.compactMap { entry -> (Double, String)? in
                guard entry.key != letters, Self.oneEditApart(entry.key, letters) else { return nil }
                let close = WordAlignment.similarity(entry.arabic, word)
                return close >= 0.5 ? (close, entry.arabic) : nil
            }
            for (_, arabic) in neighbours.sorted(by: { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }) { add(arabic) }
        }
        for variant in Self.variants(of: word) where knownArabic.contains(variant) {
            add(variant)
        }
        out = Array(out.prefix(limit - (latinCore == nil ? 0 : 1)))
        if let latinCore, !latinCore.isEmpty, latinCore.unicodeScalars.contains(where: \.properties.isAlphabetic) {
            add(latinCore)
        }
        return Array(out.prefix(limit))
    }

    // The error kinds measured on dev (17 Oct 2026): a long vowel added or dropped, an emphatic letter, the ending.
    static let longVowels: [Character] = ["ا", "و", "ي"]
    static let swaps: [(Character, Character)] = [
        ("ت", "ط"), ("س", "ص"), ("د", "ض"), ("ز", "ظ"), ("ذ", "ز"), ("ذ", "د"), ("ث", "ت"), ("ث", "س"), ("ك", "ق"),
    ]
    static let endings: [(Character, Character)] = [("ه", "ة"), ("ة", "ا"), ("ى", "ي"), ("ا", "ى")]
    static let starts: [Character] = ["ا", "أ", "إ"]

    /// One-edit variants, most likely first: long vowels, then letter swaps, then endings and the first alif.
    static func variants(of word: String) -> [String] {
        let letters = Array(word)
        guard !letters.isEmpty else { return [] }
        var out: [String] = []
        for (i, letter) in letters.enumerated() where longVowels.contains(letter) && i > 0 {
            var copy = letters
            copy.remove(at: i)
            out.append(String(copy))
        }
        for i in 1..<max(letters.count, 1) {
            for vowel in longVowels {
                var copy = letters
                copy.insert(vowel, at: i)
                out.append(String(copy))
            }
        }
        for (i, letter) in letters.enumerated() {
            for (a, b) in swaps where letter == a || letter == b {
                var copy = letters
                copy[i] = letter == a ? b : a
                out.append(String(copy))
            }
        }
        if let last = letters.last {
            for (a, b) in endings where last == a || last == b {
                var copy = letters
                copy[copy.count - 1] = last == a ? b : a
                out.append(String(copy))
            }
        }
        if let first = letters.first, starts.contains(first) {
            for other in starts where other != first {
                var copy = letters
                copy[0] = other
                out.append(String(copy))
            }
        }
        return out
    }

    static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool { (0x0621...0x064A).contains(scalar.value) }

    /// Exactly one letter added, dropped or changed (linear time).
    static func oneEditApart(_ a: [Character], _ b: [Character]) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard long.count - short.count <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < short.count && j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if short.count == long.count { i += 1 }
            j += 1
        }
        return edits + (long.count - j) + (short.count - i) == 1
    }
}

/// Which typed word each shown word came from, so a correction is recorded against the right Arabizi word.
public enum WordAlignment {
    /// For each word of `shown` (Arabic), the index of the Latin word it came from, or nil. Same counts: by
    /// position. Otherwise the best in-order matching by how close the rules' spelling of each Latin word is.
    public static func align(latin: [String], shown: [String], rules: (String) -> String) -> [Int?] {
        if latin.count == shown.count { return Array(latin.indices) }
        let ruled = latin.map { WordParts(rules(WordParts($0).core)).core }
        let typed = latin.map { WordParts($0).core.lowercased() }
        let cores = shown.map { WordParts($0).core }
        let n = latin.count, m = shown.count
        func score(_ i: Int, _ j: Int) -> Double {
            if cores[j].lowercased() == typed[i] { return 1 }  // kept in Latin
            return similarity(ruled[i], cores[j])
        }
        var best = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                let s = score(i, j)
                best[i][j] = max(best[i + 1][j], best[i][j + 1], s >= 0.4 ? s + best[i + 1][j + 1] : 0)
            }
        }
        var result = [Int?](repeating: nil, count: m)
        var i = 0, j = 0
        while i < n && j < m {
            let s = score(i, j)
            if s >= 0.4 && best[i][j] == s + best[i + 1][j + 1] {
                result[j] = i
                i += 1
                j += 1
            } else if best[i][j] == best[i + 1][j] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    /// 1 − edit distance ÷ the longer length, by character.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var previous = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in stride(from: 1, through: y.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        let distance = x.isEmpty ? y.count : previous[y.count]
        return 1 - Double(distance) / Double(max(x.count, y.count))
    }
}

private struct LexiconWords: Decodable {
    let words: [String: String]
}
