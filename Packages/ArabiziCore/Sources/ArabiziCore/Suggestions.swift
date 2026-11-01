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

/// Spellings to offer for one word of a conversion (ADR 0027), at most `listLength`, the shown word never offered back:
/// 1. the rules' spelling of the typed Arabizi word;
/// 2. the Arabic of dictionary words typed one letter differently (`sabiyeh`, `sabiyi` for `sabiye`), when that
///    Arabic looks like the shown word (at least half the letters in common), closest first;
/// 3. one-letter and long-vowel variants of the shown word that are known words (the dictionary's Arabic, or a
///    word written in the training sentences): the common error kinds first, then any other one-letter change,
///    the more often written first;
/// 4. the typed word itself, to keep it in Latin.
public struct Suggestions: Sendable {
    /// How many spellings are offered (keys 1–7): 7 holds the right word for 50% and 42% of wrong words on the two
    /// dev sets, 5 for 41% and 40% (model v3, 1 Nov 2026).
    public static let listLength = 7
    /// The rule dictionary: Arabizi word -> Arabic spelling.
    let dictionary: [String: String]
    /// The dictionary's Arabizi words by length, so neighbours are looked up among similar lengths only.
    let byLength: [Int: [(key: [Character], arabic: String)]]
    /// Arabic spellings the dictionary knows or the training sentences write; a variant is offered only if it is
    /// one of them.
    let knownArabic: Set<String>
    /// How often the training sentences write each Arabic word, to order the other one-letter changes.
    let arabicWords: [String: Int]
    let rules: @Sendable (String) -> String

    public init(dictionary: [String: String], arabicWords: [String: Int] = [:],
                rules: @escaping @Sendable (String) -> String) {
        self.dictionary = dictionary
        self.arabicWords = arabicWords
        self.knownArabic = Set(dictionary.values).union(arabicWords.keys)
        self.byLength = Dictionary(grouping: dictionary.map { (key: Array($0.key), arabic: $0.value) },
                                   by: { $0.key.count })
        self.rules = rules
    }

    /// The words of a rule dictionary file (data/rules/arabizi_lexicon.json).
    public static func dictionary(lexicon: Data) -> [String: String] {
        (try? JSONDecoder().decode(LexiconWords.self, from: lexicon))?.words ?? [:]
    }

    /// The Arabic words of the training sentences with their counts (the same file's `arabic_words`).
    public static func arabicWords(lexicon: Data) -> [String: Int] {
        (try? JSONDecoder().decode(LexiconArabic.self, from: lexicon))?.arabicWords ?? [:]
    }

    /// The user's own earlier fixes for the same typed word come first (most often chosen, then most recent),
    /// then `candidates`; the word already shown is never offered.
    public static func pastFixesFirst(_ past: [Correction], latin: String?, shown: String, candidates: [String],
                                      limit: Int = listLength) -> [String] {
        let word = WordParts(shown).core
        var fixes: [String: (count: Int, last: Date)] = [:]
        if let latin {
            let typed = WordParts(latin).core.lowercased()
            for fix in past where fix.latin.lowercased() == typed && fix.chosen != word {
                let seen = fixes[fix.chosen]
                fixes[fix.chosen] = ((seen?.count ?? 0) + 1, max(seen?.last ?? fix.date, fix.date))
            }
        }
        let own = fixes.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count
                                                                   : $0.value.last > $1.value.last }.map(\.key)
        var out: [String] = []
        for candidate in own + candidates where candidate != word && !out.contains(candidate) {
            out.append(candidate)
        }
        return Array(out.prefix(limit))
    }

    public func candidates(for shown: String, latin: String?, limit: Int = listLength) -> [String] {
        let word = WordParts(shown).core
        var out: [String] = []
        func add(_ candidate: String) {
            if !candidate.isEmpty, candidate != word, !out.contains(candidate) { out.append(candidate) }
        }
        let latinCore = latin.map { WordParts($0).core }
        // A word written from a run of typed words (el shr -> الشر): the spellings of its last, main word, with the
        // small words' Arabic in front (الشار), first.
        if let typedWords = latinCore?.split(separator: " ").map(String.init), typedWords.count > 1,
           let main = typedWords.last {
            let mainRuled = WordParts(rules(main)).core, runRuled = WordParts(rules(typedWords.joined(separator: " "))).core
            if runRuled.hasSuffix(mainRuled), !mainRuled.isEmpty {
                let prefix = String(runRuled.dropLast(mainRuled.count))
                if !prefix.isEmpty, word.hasPrefix(prefix) {
                    let stem = String(word.dropFirst(prefix.count))
                    for candidate in candidates(for: stem, latin: main, limit: limit)
                    where candidate.unicodeScalars.contains(where: Self.isArabicLetter) {
                        add(prefix + candidate)
                    }
                }
            }
        }
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
        let others = Set(Self.oneLetterChanges(of: word)).filter(knownArabic.contains)
        for other in others.sorted(by: { (arabicWords[$0] ?? 0, $1) > (arabicWords[$1] ?? 0, $0) }) { add(other) }
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

    static let arabicLetters: [Character] = (0x0621...0x064A).filter { $0 != 0x0640 }  // not the tatweel
        .compactMap { Unicode.Scalar($0).map(Character.init) }

    /// Every word one Arabic letter away from an Arabic `word`: a letter dropped, changed or added.
    static func oneLetterChanges(of word: String) -> [String] {
        let letters = Array(word)
        guard !letters.isEmpty, word.unicodeScalars.allSatisfy(isArabicLetter) else { return [] }
        var out: [String] = []
        for i in letters.indices {
            var dropped = letters
            dropped.remove(at: i)
            out.append(String(dropped))
            for letter in arabicLetters where letter != letters[i] {
                var changed = letters
                changed[i] = letter
                out.append(String(changed))
            }
        }
        for i in 0...letters.count {
            for letter in arabicLetters {
                var added = letters
                added.insert(letter, at: i)
                out.append(String(added))
            }
        }
        return out
    }

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
    /// The longest run of typed words one shown word can come from (`w el bet` -> والبيت).
    static let maxRun = 3

    /// For each word of `shown` (Arabic), the typed (Latin) words it came from, or nil. Same counts: one by one,
    /// by position. Otherwise the best in-order matching by how close the rules' spelling is, where a shown word
    /// may come from a run of typed words that the rules write as one word (`el shr` -> الشر).
    public static func align(latin: [String], shown: [String], rules: (String) -> String) -> [Range<Int>?] {
        if latin.count == shown.count { return latin.indices.map { $0..<($0 + 1) } }
        let typed = latin.map { WordParts($0).core.lowercased() }
        let cores = shown.map { WordParts($0).core }
        let n = latin.count, m = shown.count
        // ruled[i][k]: the rules' spelling of latin[i ..< i+k+1], or nil when it is not one word.
        let ruled: [[String?]] = latin.indices.map { i in
            (1...maxRun).map { length in
                guard i + length <= n else { return nil }
                let out = WordParts(rules(latin[i..<(i + length)].map { WordParts($0).core }.joined(separator: " "))).core
                return length == 1 || !out.contains(" ") ? out : nil
            }
        }
        func score(_ i: Int, _ length: Int, _ j: Int) -> Double {
            if length == 1 && cores[j].lowercased() == typed[i] { return 1 }  // kept in Latin
            guard let out = ruled[i][length - 1] else { return 0 }
            return similarity(out, cores[j])
        }
        var best = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                var value = max(best[i + 1][j], best[i][j + 1])
                for length in 1...maxRun where i + length <= n {
                    let s = score(i, length, j)
                    if s >= 0.4 { value = max(value, s + best[i + length][j + 1]) }
                }
                best[i][j] = value
            }
        }
        var result = [Range<Int>?](repeating: nil, count: m)
        var i = 0, j = 0
        walk: while i < n && j < m {
            for length in (1...maxRun).reversed() where i + length <= n {  // the longer run when equal
                let s = score(i, length, j)
                if s >= 0.4 && best[i][j] == s + best[i + length][j + 1] {
                    result[j] = i..<(i + length)
                    i += length
                    j += 1
                    continue walk
                }
            }
            if best[i][j] == best[i + 1][j] {
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

private struct LexiconArabic: Decodable {
    let arabicWords: [String: Int]
    enum CodingKeys: String, CodingKey { case arabicWords = "arabic_words" }
}
