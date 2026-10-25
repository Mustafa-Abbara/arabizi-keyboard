import Foundation

/// The rule fallback (roadmap P5): a Swift port of B0, the rule baseline in eval/src/arabizi_eval/b0.py.
///
/// Both read data/rules/arabizi_to_arabic.json and data/rules/arabizi_lexicon.json and must give exactly the
/// same output; Tests/ArabiziCoreTests/Fixtures/b0_parity.json (written by Python) checks it. Each Arabizi word is
/// converted by, in order:
/// 1. small attached words (clitics: w, bel, la, 3al…) joined to the converted next word;
/// 2. words the Arabic keeps in Latin (English, names), kept exactly as typed;
/// 3. the word dictionary learned from the training split;
/// 4. letter rules.
/// Numbers, links, mentions and emoji are never changed; ? , ; become ؟ ، ؛.
///
/// Text is handled as Unicode scalars, like Python's code points, never as Swift Characters: a Character can
/// merge a space or a letter with the mark after it, and Characters compare by canonical equivalence.
public struct RuleConverter: Sendable {
    public struct FileError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static let rulesFileName = "arabizi_to_arabic.json"
    public static let lexiconFileName = "arabizi_lexicon.json"

    let clitics: [String: String]
    let punctuation: [Unicode.Scalar: String]
    let letterRules: LetterRules
    let words: [String: String]
    let keepLatin: Set<String>

    /// Reads the two rule files from a folder (data/rules in the repo, Resources in the app). A missing
    /// dictionary means letter rules only, as in Python.
    public init(rulesDirectory: URL) throws {
        let lexiconURL = rulesDirectory.appending(path: Self.lexiconFileName)
        let lexicon = FileManager.default.fileExists(atPath: lexiconURL.path) ? try Data(contentsOf: lexiconURL) : nil
        try self.init(rules: Data(contentsOf: rulesDirectory.appending(path: Self.rulesFileName)), lexicon: lexicon)
    }

    public init(rules rulesData: Data, lexicon lexiconData: Data?) throws {
        let decoder = JSONDecoder()
        let rules = try decoder.decode(RulesFile.self, from: rulesData)
        guard rules.version == 1 else { throw FileError(description: "unsupported rules version \(rules.version)") }
        clitics = rules.clitics.withoutComments
        punctuation = try Dictionary(uniqueKeysWithValues: rules.punctuation.map { key, value in
            guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else {
                throw FileError(description: "punctuation key '\(key)' is not one character")
            }
            return (scalar, value)
        })
        letterRules = try LetterRules(rules.letters)
        if let lexiconData {
            let lexicon = try decoder.decode(LexiconFile.self, from: lexiconData)
            words = lexicon.words
            keepLatin = Set(lexicon.keepLatin)
        } else {
            words = [:]
            keepLatin = []
        }
    }

    // MARK: - conversion

    public func convert(_ text: String) -> String {
        let tokens = text.unicodeScalars.split(separator: " ", omittingEmptySubsequences: false)
            .map { Token(String(Substring($0))) }
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if isUntouched(token) {
                let keepWhole = token.core.isEmpty || Self.isUntouchedToken(token.raw)
                out.append(keepWhole ? token.raw : punct(token.lead) + token.core + punct(token.trail))
                i += 1
                continue
            }
            if clitics[token.core.lowercased()] != nil && token.trail.isEmpty {
                // Collect a run of clitics (w el bet: و + ال) and attach them to the next real word.
                var prefixes: [String] = []
                var j = i
                while j < tokens.count, let prefix = clitics[tokens[j].core.lowercased()],
                      j == i || tokens[j].lead.isEmpty, tokens[j].trail.isEmpty {
                    prefixes.append(prefix)
                    j += 1
                }
                if j < tokens.count {
                    let next = tokens[j]
                    if next.lead.isEmpty && !next.core.isEmpty && !isUntouched(next) && !isLatinKept(next.core) {
                        var attached = word(next.core)
                        for prefix in prefixes.reversed() {
                            attached = Self.joinClitic(prefix, attached)
                        }
                        out.append(punct(token.lead) + attached + punct(next.trail))
                        i = j + 1
                        continue
                    }
                }
                // Before an English word, a number or the end of the text, the clitics stay a separate word.
                var joined = ""
                for prefix in prefixes.reversed() {
                    joined = joined.isEmpty ? prefix : Self.joinClitic(prefix, joined)
                }
                out.append(punct(token.lead) + joined)
                i = j
                continue
            }
            out.append(punct(token.lead) + word(token.core) + punct(token.trail))
            i += 1
        }
        return out.joined(separator: " ")
    }

    func word(_ core: String) -> String {
        if isLatinKept(core) {
            return core
        }
        let lower = core.lowercased()
        if let known = words[lower] {
            return known
        }
        return Self.isLetterWord(lower) ? letters(lower) : core
    }

    /// Convert one lowercase word letter by letter (used only for words not in the dictionary).
    func letters(_ word: String) -> String {
        let rules = letterRules
        // The rules file is checked to have no ending inside another, so the order does not matter.
        for (ending, arabic) in rules.wordEndings where word.hasSuffix(ending) && word.count > ending.count + 2 {
            return letters(String(word.dropLast(ending.count))) + arabic
        }
        let chars = Array(word)  // ASCII only (isLetterWord), so Characters are code points here
        let short = chars.count <= rules.shortWordMaxLen
        var out = ""
        var previous: Character?  // the last single consonant written, for collapsing doubles (not one inside "sh")
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count, let sequence = rules.sequences[String(chars[i...i + 1])] {
                if i == 0, let initial = rules.initial[chars[0]] {  // initial long vowel: alif with hamza, then the vowel
                    out += initial + (sequence == "ا" ? "" : sequence)
                } else {
                    out += sequence
                }
                previous = nil
                i += 2
                continue
            }
            let char = chars[i]
            if let medial = rules.medial[char] {
                if i == 0 {
                    out += rules.initial[char, default: ""]
                } else if i == chars.count - 1 {
                    out += char == "e" && short ? rules.finalEShortWord : rules.final[char, default: ""]
                } else {
                    out += medial
                }
            } else if let consonant = rules.consonants[char] {
                let doubled = rules.collapseDoubledConsonants && previous == char
                out += doubled ? "" : consonant
                previous = char
                i += 1
                continue
            } else if char != "'" {
                out.append(char)
            }
            previous = nil
            i += 1
        }
        return out
    }

    /// Attach a clitic without doubling the article: بال + البيت = بالبيت, ل + البيت = للبيت, لل + بيت = للبيت.
    static func joinClitic(_ prefix: String, _ word: String) -> String {
        let article = Array("ال".unicodeScalars)
        let prefixScalars = Array(prefix.unicodeScalars)
        if word.unicodeScalars.starts(with: article) {
            if prefixScalars.suffix(2).elementsEqual(article) || prefixScalars.elementsEqual("لل".unicodeScalars) {
                return prefix + String(Substring(word.unicodeScalars.dropFirst(2)))
            }
            if prefixScalars.elementsEqual("ل".unicodeScalars) {
                return prefix + String(Substring(word.unicodeScalars.dropFirst(1)))
            }
        }
        return prefix + word
    }

    private func punct(_ text: String) -> String {
        text.unicodeScalars.map { punctuation[$0] ?? String($0) }.joined()
    }

    private func isUntouched(_ token: Token) -> Bool {
        token.core.isEmpty || Self.isNumber(token.core) || Self.isUntouchedToken(token.raw) || !token.core.isPythonASCII
    }

    private func isLatinKept(_ core: String) -> Bool {
        keepLatin.contains(core.lowercased())
            && !core.unicodeScalars.contains { [.decimal, .digit].contains($0.properties.numericType) }
    }

    // MARK: - patterns (hand-written equivalents of the Python regexes, so they match code point for code point)

    /// Python `^[a-z0-9']+$`: only these words go through the letter rules.
    static func isLetterWord(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "'" }
    }

    /// `pairs.NUMBER.fullmatch`: `[$€£]?\d+(?:[.,:]\d+)*(?:[$€£%]|k|K|pm|PM)?`.
    static func isNumber(_ text: String) -> Bool {
        let c = Array(text.unicodeScalars)
        func isDigit(_ index: Int) -> Bool { index < c.count && c[index].properties.numericType == .decimal }
        var i = 0
        if i < c.count && "$€£".unicodeScalars.contains(c[i]) {
            i += 1
        }
        guard isDigit(i) else { return false }
        while isDigit(i) { i += 1 }
        while i < c.count && ".,:".unicodeScalars.contains(c[i]) && isDigit(i + 1) {
            i += 1
            while isDigit(i) { i += 1 }
        }
        let suffix = Array(c[i...])
        return ["", "$", "€", "£", "%", "k", "K", "pm", "PM"].contains { suffix.elementsEqual($0.unicodeScalars) }
    }

    /// `pairs.UNTOUCHED.fullmatch`: `https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.]+|[@#]\w+` on the whole token.
    static func isUntouchedToken(_ token: String) -> Bool {
        let c = Array(token.unicodeScalars)
        for start in ["http://", "https://", "www."] {
            let prefix = Array(start.unicodeScalars)
            if c.count > prefix.count && c.starts(with: prefix) && !c[prefix.count...].contains(where: \.isPythonSpace) {
                return true
            }
        }
        if let first = c.first, first == "@" || first == "#", c.count > 1, c.dropFirst().allSatisfy(\.isPythonWord) {
            return true
        }
        // An email: none of the three parts can hold an @, and the domain cannot hold a dot, so the split is unique.
        guard let at = c.firstIndex(of: "@") else { return false }
        let user = c[..<at], rest = c[(at + 1)...]
        guard let dot = rest.firstIndex(of: ".") else { return false }
        let domain = rest[..<dot], top = rest[(dot + 1)...]
        return !user.isEmpty && user.allSatisfy { $0.isPythonWord || ".+-".unicodeScalars.contains($0) }
            && !domain.isEmpty && domain.allSatisfy { $0.isPythonWord || $0 == "-" }
            && !top.isEmpty && top.allSatisfy { $0.isPythonWord || $0 == "." }
    }
}

/// One space-separated token split like Python's `^(\W*)(.*?)(\W*)$`: leading and trailing non-word characters
/// around the core.
struct Token {
    let raw: String
    let lead: String
    let core: String
    let trail: String

    init(_ raw: String) {
        let c = Array(raw.unicodeScalars)
        var start = 0
        while start < c.count && !c[start].isPythonWord { start += 1 }
        var end = c.count
        while end > start && !c[end - 1].isPythonWord { end -= 1 }
        func text(_ range: Range<Int>) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: c[range])
            return String(view)
        }
        self.raw = raw
        lead = text(0..<start)
        core = text(start..<end)
        trail = text(end..<c.count)
    }
}

/// The letter rules, checked when loaded so that conversion never meets a missing entry.
struct LetterRules: Sendable {
    let sequences: [String: String]
    let consonants: [Character: String]
    let initial: [Character: String]
    let medial: [Character: String]
    let final: [Character: String]
    let finalEShortWord: String
    let wordEndings: [String: String]
    let shortWordMaxLen: Int
    let collapseDoubledConsonants: Bool

    init(_ file: LettersFile) throws {
        func characterKeys(_ table: [String: String], _ name: String) throws -> [Character: String] {
            try Dictionary(uniqueKeysWithValues: table.map { key, value in
                guard key.unicodeScalars.count == 1, key.isPythonASCII, let char = key.first else {
                    throw RuleConverter.FileError(description: "\(name) key '\(key)' is not one ASCII character")
                }
                return (char, value)
            })
        }
        sequences = file.sequences
        if let bad = sequences.keys.first(where: { $0.unicodeScalars.count != 2 || !$0.isPythonASCII }) {
            throw RuleConverter.FileError(description: "sequence '\(bad)' is not two ASCII characters")
        }
        consonants = try characterKeys(file.consonants, "consonant")
        initial = try characterKeys(file.vowels.initial, "initial vowel")
        medial = try characterKeys(file.vowels.medial, "medial vowel")
        final = try characterKeys(file.vowels.final, "final vowel")
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        for (name, table) in [("initial", initial), ("medial", medial), ("final", final)] where Set(table.keys) != vowels {
            throw RuleConverter.FileError(description: "\(name) vowels must be exactly a, e, i, o, u")
        }
        finalEShortWord = file.vowels.finalEShortWord
        wordEndings = (file.wordEndings ?? [:]).withoutComments
        for a in wordEndings.keys {
            for b in wordEndings.keys where a != b && a.hasSuffix(b) {
                throw RuleConverter.FileError(description: "word ending '\(b)' is inside '\(a)': the order would matter")
            }
        }
        shortWordMaxLen = file.shortWordMaxLen
        collapseDoubledConsonants = file.collapseDoubledConsonants
    }
}

// MARK: - file formats

struct RulesFile: Decodable {
    let version: Int
    let clitics: [String: String]
    let punctuation: [String: String]
    let letters: LettersFile
}

struct LettersFile: Decodable {
    let sequences: [String: String]
    let consonants: [String: String]
    let vowels: VowelsFile
    let wordEndings: [String: String]?
    let shortWordMaxLen: Int
    let collapseDoubledConsonants: Bool

    enum CodingKeys: String, CodingKey {
        case sequences, consonants, vowels
        case wordEndings = "word_endings"
        case shortWordMaxLen = "short_word_max_len"
        case collapseDoubledConsonants = "collapse_doubled_consonants"
    }
}

struct VowelsFile: Decodable {
    let initial: [String: String]
    let medial: [String: String]
    let final: [String: String]
    let finalEShortWord: String

    enum CodingKeys: String, CodingKey {
        case initial, medial, final
        case finalEShortWord = "final_e_short_word"
    }
}

struct LexiconFile: Decodable {
    let words: [String: String]
    let keepLatin: [String]

    enum CodingKeys: String, CodingKey {
        case words
        case keepLatin = "keep_latin"
    }
}

extension Dictionary where Key == String, Value == String {
    /// Python `_clean`: keys starting with "_" are comments.
    var withoutComments: [String: String] { filter { !$0.key.hasPrefix("_") } }
}
