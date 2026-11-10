import Foundation

/// How typists write each Arabizi unit in Arabic, and the spellings of a typed word that follow from it (ADR 0036).
/// The Swift port of `eval/src/arabizi_eval/candidates.py` (units, options, odds, spellings, typing likelihood),
/// checked against `Fixtures/candidates_parity.json`. Odds: `data/rules/spelling_odds.json`, from public training
/// pairs only (`pairs spelling-odds`).
///
/// Text is handled as Unicode scalars, as Python counts characters, so positions and lengths match the reference.
public struct SpellingOdds: Sendable {
    public static let fileName = "spelling_odds.json"

    /// For "unit|position": how often each option was used by the training pairs.
    let odds: [String: [String: Int]]
    /// Typed words the training data wrote more than one way: spelling -> count.
    let typedSpellings: [String: [String: Int]]

    public init(data: Data) throws {
        struct File: Decodable {
            let version: Int
            let odds: [String: [String: Int]]
            let typedSpellings: [String: [String: Int]]
            enum CodingKeys: String, CodingKey { case version, odds, typedSpellings = "typed_spellings" }
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1 else { throw RuleConverter.FileError(description: "unsupported odds version") }
        odds = file.odds
        typedSpellings = file.typedSpellings
    }

    // MARK: Options

    static let hamza = ["ء", "أ", "ئ", "ؤ", "إ"]
    static let consonants: [String: [String]] = [
        "sh": ["ش"], "ch": ["ش"], "kh": ["خ"], "gh": ["غ"], "th": ["ت", "ث", "ذ"], "dh": ["ذ", "ض", "ظ"],
        "3'": ["غ"], "7'": ["خ"],
        "b": ["ب"], "p": ["ب"], "t": ["ت", "ط"], "j": ["ج"], "g": ["ج", "غ", "ق"], "d": ["د", "ض"], "r": ["ر"],
        "z": ["ز", "ظ", "ذ"], "s": ["س", "ص"], "f": ["ف"], "v": ["ف"], "q": ["ق", "ك"], "k": ["ك", "ق"],
        "c": ["ك", "س", "ش"], "l": ["ل"], "m": ["م"], "n": ["ن"], "h": ["ه", "ح", "ة"], "w": ["و"], "y": ["ي"],
        "x": ["كس"], "2": ["ق"] + hamza, "3": ["ع"], "5": ["خ"], "6": ["ط"], "7": ["ح"], "8": ["غ", "ق"],
        "9": ["ص", "ق"],
    ]
    static let vowels: [String: [String: [String]]] = [
        "initial": ["a": ["ا", "أ", "ع", "آ", "إ"], "aa": ["ع", "ا", "آ"], "e": ["إ", "ا", "أ", "ع", "ي"],
                    "i": ["إ", "ا", "ي"], "o": ["أ", "ا", "و", "ع"], "u": ["أ", "ا", "و"], "ee": ["إي", "ي"],
                    "oo": ["أو", "و"], "ou": ["أو", "و"], "ai": ["أي", "عي"], "ay": ["أي", "عي"], "ei": ["إي", "أي"]],
        "medial": ["a": ["", "ا", "ع"], "aa": ["ا", "ع", "اع"], "e": ["", "ي", "ا"], "i": ["ي", ""],
                   "o": ["و", ""], "u": ["و", ""], "ee": ["ي"], "ei": ["ي", "اي"], "ai": ["ي", "اي"],
                   "ay": ["ي", "اي"], "oo": ["و"], "ou": ["و"]],
        "final": ["a": ["ا", "ة", "ى", "ه", "", "ع"], "aa": ["ا", "اء", "ع"], "e": ["ة", "ي", "ه", "ا", ""],
                  "i": ["ي"], "o": ["و", "ه"], "u": ["و"], "ee": ["ي"], "ei": ["ي"], "ai": ["ي", "اي"],
                  "ay": ["ي", "اي"], "oo": ["و"], "ou": ["و"]],
    ]
    /// Written after a consonant the typist left them out after (kfk -> كيفك).
    static let longVowels = ["ي", "و", "ا"]
    static let pairs: Set<String> = Set(consonants.keys.filter { $0.count == 2 })
        .union(vowels.values.flatMap { $0.keys.filter { $0.count == 2 } })
    static let smooth = 0.5

    static func isVowel(_ unit: String) -> Bool { unit.first.map { "aeiou".contains($0) } ?? false }

    /// A lowercase Arabizi word in units: two-letter units first (sh, kh, aa, ee…), else one character.
    public static func units(_ word: String) -> [String] {
        let chars = Array(word.unicodeScalars)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count {
                let pair = String(String.UnicodeScalarView(chars[i...i + 1]))
                if pairs.contains(pair), consonants[pair] != nil || isVowel(pair) {
                    out.append(pair)
                    i += 2
                    continue
                }
            }
            out.append(String(chars[i]))
            i += 1
        }
        return out
    }

    static func position(_ k: Int, _ n: Int) -> String { k == 0 ? "initial" : k == n - 1 ? "final" : "medial" }

    /// What `unit` may be written as at `position`: a doubled consonant may be written once; a consonant followed by
    /// a consonant may get a long vowel the typist left out.
    static func options(_ unit: String, _ position: String, previous: String, following: String?) -> [String] {
        if isVowel(unit) { return vowels[position]?[unit] ?? [""] }
        guard let letters = consonants[unit] else {
            return unit.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil }
                ? [] : [""]
        }
        var out = letters + (unit == previous ? [""] : [])
        if let following, !isVowel(following), consonants[following] != nil {
            out += letters.flatMap { letter in longVowels.map { letter + $0 } }
        }
        return out
    }

    func probability(_ unit: String, _ position: String, _ letters: String, previous: String, following: String?)
        -> Double {
        let choices = Self.options(unit, position, previous: previous, following: following)
        let seen = odds["\(unit)|\(position)"] ?? [:]
        let total = Double(choices.reduce(0) { $0 + (seen[$1] ?? 0) }) + Self.smooth * Double(choices.count)
        guard total > 0 else { return 1.0 / Double(max(choices.count, 1)) }
        return (Double(seen[letters] ?? 0) + Self.smooth) / total
    }

    // MARK: Spellings

    /// Spellings of a typed word, best first, with log-scores; a known word gets a bonus of log 4.
    func spellings(_ typed: String, known: Set<String>, keep: Int = 30, beam: Int = 200) -> [(String, Double)] {
        let parts = Self.units(typed.lowercased())
        guard !parts.isEmpty else { return [] }
        var beams: [(lp: Double, written: String, previous: String)] = [(0, "", "")]
        for (k, unit) in parts.enumerated() {
            let position = Self.position(k, parts.count)
            let following = k + 1 < parts.count ? parts[k + 1] : nil
            var grown: [(lp: Double, written: String, previous: String)] = []
            for (lp, written, previous) in beams {
                for letters in Self.options(unit, position, previous: previous, following: following) {
                    let p = probability(unit, position, letters, previous: previous, following: following)
                    grown.append((lp + Foundation.log(p), written + letters, unit))
                }
            }
            beams = Array(grown.sorted { $0.lp != $1.lp ? $0.lp > $1.lp : Self.less($0.written, $1.written) }
                .prefix(beam))
        }
        var best: [String: Double] = [:]
        for (lp, written, _) in beams where Self.isArabicWord(written) {
            let score = lp + (known.contains(written) ? Foundation.log(4.0) : 0)
            best[written] = max(best[written] ?? -1e9, score)
        }
        return Array(best.sorted { $0.value != $1.value ? $0.value > $1.value : Self.less($0.key, $1.key) }
            .prefix(keep)).map { ($0.key, $0.value) }
    }

    /// Every known word the options can write from `typed`, most often written first.
    func knownSpellings(_ typed: String, trie: TrieNode, frequency: [String: Int], cap: Int = 400) -> [String] {
        let parts = Self.units(typed.lowercased())
        var found = Set<String>()
        func walk(_ k: Int, _ node: TrieNode, _ written: String, _ previous: String) {
            if found.count >= cap { return }
            if k == parts.count {
                if node.isWord && !written.isEmpty { found.insert(written) }
                return
            }
            let position = Self.position(k, parts.count)
            let following = k + 1 < parts.count ? parts[k + 1] : nil
            for letters in Self.options(parts[k], position, previous: previous, following: following) {
                var n: TrieNode? = node
                for scalar in letters.unicodeScalars { n = n?.children[scalar] }
                if let n { walk(k + 1, n, written + letters, parts[k]) }
            }
        }
        if !parts.isEmpty { walk(0, trie, "", "") }
        return found.sorted {
            let (a, b) = (frequency[$0] ?? 0, frequency[$1] ?? 0)
            return a != b ? a > b : Self.less($0, $1)
        }
    }

    /// log P(word | typed) along the best path of options that writes `word` exactly; -60 when none does.
    func typingLogProbability(_ typed: String, _ word: String) -> Double {
        let parts = Self.units(typed.lowercased())
        let target = Array(word.unicodeScalars)
        let n = parts.count
        var memo: [String: Double] = [:]
        func best(_ k: Int, _ at: Int, _ previous: String) -> Double {
            if k == n { return at == target.count ? 0 : -1e9 }
            let key = "\(k)|\(at)|\(previous)"
            if let value = memo[key] { return value }
            let position = Self.position(k, n)
            let following = k + 1 < n ? parts[k + 1] : nil
            var top = -1e9
            for letters in Self.options(parts[k], position, previous: previous, following: following) {
                let scalars = Array(letters.unicodeScalars)
                guard at + scalars.count <= target.count, Array(target[at..<(at + scalars.count)]) == scalars else {
                    continue
                }
                let rest = best(k + 1, at + scalars.count, parts[k])
                if rest > -1e9 {
                    let p = probability(parts[k], position, letters, previous: previous, following: following)
                    top = max(top, Foundation.log(p) + rest)
                }
            }
            memo[key] = top
            return top
        }
        let value = n > 0 ? best(0, 0, "") : -1e9
        return value > -1e9 ? value : -60
    }

    // MARK: Helpers

    /// Python's string order: by code point.
    static func less(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
    }

    /// Only Arabic letters (ء to ي), at least one.
    static func isArabicWord(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { (0x0621...0x064A).contains($0.value) }
    }
}

/// Known words as a prefix tree, so only spellings that lead to a real word are followed.
final class TrieNode: @unchecked Sendable {
    var children: [Unicode.Scalar: TrieNode] = [:]
    var isWord = false

    init(words: some Sequence<String> = []) {
        for word in words { insert(word) }
    }

    func insert(_ word: String) {
        var node = self
        for scalar in word.unicodeScalars {
            if let next = node.children[scalar] {
                node = next
            } else {
                let next = TrieNode()
                node.children[scalar] = next
                node = next
            }
        }
        node.isWord = true
    }
}
