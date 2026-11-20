import Foundation

/// Merge and split entries for the ↑ list (ADR 0041): the model wrote two words where one was meant (ع سطح for
/// عالسطح) or one where two were meant (وانا for و انا). The list offers at most one such entry, in its last Arabic
/// place, only when the typed words point to it. The Swift port of the "merge and split" part of
/// `eval/src/arabizi_eval/candidates.py`, checked against `Fixtures/candidates_parity.json`.
extension CandidateList {
    /// One-letter prefixes written joined to the next word.
    static let splitPrefixes: Set<String> = ["و", "ب", "ل", "ع", "ف", "ك"]
    /// Small words that are usually joined to the next one (never عم، شو، بس، مش، لا، في، ما، يا).
    static let mergeWords: Set<String> = ["ع", "ب", "ل", "و", "ف", "ك", "ح", "رح", "راح", "عال", "بال", "هال", "لل", "ال",
                                          "وال", "فال"]
    /// The future particle: رح شوف is written حشوف.
    static let futureWords: Set<String> = ["رح", "راح", "ح", "ها"]
    /// How those small words are typed.
    static let mergeTyped: Set<String> = ["w", "wa", "b", "bi", "l", "la", "li", "3a", "3", "f", "fa", "ka", "el", "il",
                                          "al", "bel", "bil", "3al", "lal", "hal", "bhal", "7a", "ra7", "ha", "lel", "lil"]

    /// An entry that fixes a merge or a split: `text` replaces word `index` (`step` 0: a split, the text holds a
    /// space), word `index` and the next (`step` +1), or the previous word and word `index` (`step` -1).
    public struct SpanEntry: Equatable, Sendable {
        public let text: String
        public let step: Int
    }

    /// The one merge/split entry for the list on word `index` of `words` (the converted text's words, punctuation
    /// included), if any. `latins`: the typed words each word came from (`Composer`'s alignment), nil when unknown.
    public func spanEntry(words: [String], index: Int, latins: [String?]) -> SpanEntry? {
        let cores = words.map { WordParts($0).core }
        let typed = latins.map { latin in
            latin.map { $0.split(whereSeparator: \.isWhitespace).map { WordParts(String($0)).core.lowercased() }
                .filter { !$0.isEmpty } } ?? []
        }
        return spanEntry(words: cores, index: index, typedOf: { typed.indices.contains($0) ? typed[$0] : [] })
    }

    func spanEntry(words: [String], index i: Int, typedOf: (Int) -> [String]) -> SpanEntry? {
        let shown = words[i]
        if Self.wantsSplit(shown: shown, typedWords: typedOf(i)), let text = splitOptions(shown: shown, typedWords: typedOf(i)).first {
            return SpanEntry(text: text, step: 0)
        }
        for (j, step) in [(i + 1, 1), (i - 1, -1)] where words.indices.contains(j) {
            let (a, b) = step == 1 ? (shown, words[j]) : (words[j], shown)
            let (ta, tb) = step == 1 ? (typedOf(i), typedOf(j)) : (typedOf(j), typedOf(i))
            if Self.wantsMerge(first: a, second: b, typedFirst: ta, typedSecond: tb),
               let text = mergeOptions(first: a, second: b, typedWords: ta + tb.filter { !ta.contains($0) }).first {
                return SpanEntry(text: text, step: step)
            }
        }
        return nil
    }

    /// A typed word's best single spellings with a score (higher is better): letter odds, the training data's, the
    /// dictionary's and the rules'. A word not typed in Latin letters is kept as it is.
    func wordOptions(_ typed: String, keep: Int = 4) -> [(String, Double)] {
        guard !typed.isEmpty else { return [] }
        guard typed.unicodeScalars.allSatisfy(\.isASCII), typed.unicodeScalars.contains(where: \.properties.isAlphabetic)
        else { return [(typed, 0)] }
        var out: [String: Double] = [:]
        func add(_ word: String, _ score: Double) { out[word] = max(out[word] ?? -1e9, score) }
        for (word, lp) in odds.spellings(typed, known: known, keep: keep) { add(word, lp) }
        let trained = (odds.typedSpellings[typed] ?? [:])
            .sorted { $0.value != $1.value ? $0.value > $1.value : SpellingOdds.less($0.key, $1.key) }.prefix(3)
        for (word, _) in trained { add(word, max(odds.typingLogProbability(typed, word), -3)) }
        if let word = dictionary[typed] { add(word, -1) }
        let ruled = Self.arabicCore(rules.convert(typed))
        if Self.hasArabicLetter(ruled), !ruled.contains(" ") { add(ruled, odds.typingLogProbability(typed, ruled)) }
        return Array(Self.best(out).prefix(keep))
    }

    /// Offer a split only when the word came from two or more typed words.
    static func wantsSplit(shown: String, typedWords: [String]) -> Bool {
        hasArabicLetter(shown) && shown.unicodeScalars.count >= 3 && typedWords.count >= 2
    }

    /// The shown word as two words: its own letters with the space put back first (cut where the first part is a
    /// spelling of the first typed word, or after a one-letter prefix), then each typed word spelled on its own.
    func splitOptions(shown: String, typedWords: [String], keep: Int = 1) -> [String] {
        var scored: [String: Double] = [:]
        func add(_ a: String, _ b: String, _ score: Double) {
            guard !a.isEmpty, b.unicodeScalars.count >= 2 else { return }
            scored["\(a) \(b)"] = max(scored["\(a) \(b)"] ?? -1e9, score)
        }
        let first = typedWords.count >= 2 ? Dictionary(wordOptions(typedWords[0]), uniquingKeysWith: max) : [:]
        let letters = Array(shown.unicodeScalars)
        if letters.count > 2 {
            for j in 1..<(letters.count - 1) {
                let a = String(String.UnicodeScalarView(letters[..<j])), b = String(String.UnicodeScalarView(letters[j...]))
                if first[a] != nil || (j == 1 && Self.splitPrefixes.contains(a)) { add(a, b, 0.5 * knownBonus(b)) }
            }
        }
        if typedWords.count >= 2 {
            for (a, la) in wordOptions(typedWords[0], keep: 3) {
                for (b, lb) in wordOptions(typedWords.dropFirst().joined(), keep: 3) {
                    add(a, b, -1.5 + la + lb + knownBonus(a) + knownBonus(b))
                }
            }
        }
        return Array(Self.best(scored).prefix(keep).map(\.0))
    }

    /// Offer a merge only when both words came from the same typed word(s), or the first was typed as a small word
    /// that is usually joined (3a, b, l, 7a, bhal…) and written as one (ع، ب، رح، بهال…).
    static func wantsMerge(first: String, second: String, typedFirst: [String], typedSecond: [String]) -> Bool {
        guard hasArabicLetter(first), hasArabicLetter(second) else { return false }
        if !typedFirst.isEmpty, typedFirst == typedSecond { return true }
        let prefixLike = mergeWords.contains(first)
            || (first.unicodeScalars.reversed().starts(with: "لا".unicodeScalars) && first.unicodeScalars.count <= 4)
        guard typedFirst.count == 1, prefixLike else { return false }
        let typed = typedFirst[0]
        return mergeTyped.contains(typed) || typed.hasSuffix("al") || typed.hasSuffix("el") || typed.hasSuffix("il")
    }

    /// The two shown words as one: their own letters joined first (رح + verb as ح + verb, a prefix joined with its
    /// article), then ال put in after a one-letter prefix, then the typed words spelled as one word.
    func mergeOptions(first: String, second: String, typedWords: [String], keep: Int = 1) -> [String] {
        guard Self.hasArabicLetter(first), Self.hasArabicLetter(second) else { return [] }
        var scored: [String: Double] = [:]
        func add(_ word: String, _ score: Double) {
            guard !word.isEmpty, !word.contains(" "), Self.hasArabicLetter(word) else { return }
            scored[word] = max(scored[word] ?? -1e9, score)
        }
        if Self.futureWords.contains(first) { add("ح" + second, 0.2 + 0.5 * knownBonus("ح" + second)) }
        let joined = RuleConverter.joinClitic(first, second)
        add(joined, 0.5 * knownBonus(joined))
        add(first + second, -0.1 + 0.5 * knownBonus(first + second))
        if Self.splitPrefixes.contains(first), !second.unicodeScalars.starts(with: "ال".unicodeScalars) {
            let word = first == "ل" ? "لل" + second : first + "ال" + second
            add(word, -0.6 + knownBonus(word))
        }
        let typed = typedWords.joined()
        if !typed.isEmpty, typed.unicodeScalars.allSatisfy(\.isASCII) {
            for (word, lp) in wordOptions(typed, keep: 4) { add(word, -1.5 + lp + knownBonus(word)) }
            for (word, lp) in cliticSpellings(typed, keep: 4).pairs { add(word, -1.5 + lp + knownBonus(word)) }
        }
        return Array(Self.best(scored).prefix(keep).map(\.0))
    }

    private func knownBonus(_ word: String) -> Double {
        known.contains(word) || !Self.hasArabicLetter(word) ? 0 : -2
    }

    static func hasArabicLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) }
    }

    /// Best score first, then by code point (Python's sort on (-score, word)).
    static func best(_ scored: [String: Double]) -> [(String, Double)] {
        scored.sorted { $0.value != $1.value ? $0.value > $1.value : SpellingOdds.less($0.key, $1.key) }.map { ($0.key, $0.value) }
    }
}
