import Foundation

/// The Arabic letters each Arabizi key can stand for (data/rules/spelling_options.json), with the letter rules'
/// own choice for each key (arabizi_to_arabic.json), for spelling a word letter by letter (ADR 0027 #7).
public struct SpellingOptions: Equatable, Sendable {
    public static let fileName = "spelling_options.json"

    let options: [String: [String]]
    let sequences: [String: String]
    let consonants: [Character: String]
    let initial: [Character: String]
    let medial: [Character: String]

    /// Reads the options file; `rules` gives the default letters, so both files must cover the same keys.
    public init(options data: Data, rules: RuleConverter) throws {
        let file = try JSONDecoder().decode(OptionsFile.self, from: data)
        guard file.version == 1 else {
            throw RuleConverter.FileError(description: "unsupported spelling options version \(file.version)")
        }
        let letters = rules.letterRules
        options = file.options
        sequences = letters.sequences
        consonants = letters.consonants
        initial = letters.initial
        medial = letters.medial
        let keys = Set(sequences.keys).union(consonants.keys.map(String.init)).union(medial.keys.map(String.init))
        if let missing = keys.subtracting(options.keys).sorted().first {
            throw RuleConverter.FileError(description: "spelling options have no entry for '\(missing)'")
        }
    }

    /// Reads spelling_options.json and the rules from one folder (data/rules in the repo, Resources in the app).
    public init(rulesDirectory: URL, rules: RuleConverter) throws {
        try self.init(options: Data(contentsOf: rulesDirectory.appending(path: Self.fileName)), rules: rules)
    }

    private struct OptionsFile: Decodable {
        let version: Int
        let options: [String: [String]]
    }
}

/// Spells one word letter by letter: each typed key becomes its most likely Arabic letter at once, and the
/// other letters it can stand for are offered for the last key (ADR 0027 #7).
///
/// What is shown is what is accepted: a letter does not change once the next key is typed, except that two keys
/// that are one sound (`s` + `h` → ش) join while the first is still the default. `'` separates keys that would
/// join (`s'h` → سه). Defaults follow the letter rules: a first vowel takes the alif with hamza, a later short
/// vowel is not written, and a doubled consonant is written once.
public struct Speller: Equatable, Sendable {
    /// The label shown for "this key writes nothing" in the candidate window.
    public static let nothingLabel = "∅"

    struct Piece: Equatable, Sendable {
        let key: String
        let options: [String]
        var choice = 0
        var touched = false

        var arabic: String { options[choice] }
    }

    private let spelling: SpellingOptions
    private var pieces: [Piece] = []
    private var history: [[Piece]] = []
    /// Off in `keystrokes(toSpell:with:)`, which never presses Backspace.
    private var keepsHistory = true

    public init(_ spelling: SpellingOptions) {
        self.spelling = spelling
    }

    /// The word as spelled so far.
    public var arabic: String { pieces.map(\.arabic).joined() }
    /// The Latin keys typed so far.
    public var latin: String { pieces.map(\.key).joined() }
    public var isEmpty: Bool { pieces.isEmpty }
    /// The letters the last key can stand for (empty when it has only one), "" shown as `nothingLabel`.
    public var labels: [String] {
        guard let last = pieces.last, last.options.count > 1 else { return [] }
        return last.options.map { $0.isEmpty ? Self.nothingLabel : $0 }
    }
    /// Which of `labels` is chosen now.
    public var choice: Int? { labels.isEmpty ? nil : pieces.last?.choice }

    /// Adds one typed character; false (nothing changes) for a character that does not spell a letter.
    @discardableResult
    public mutating func type(_ text: String) -> Bool {
        let key = text.lowercased()
        guard key.count == 1, let char = key.first else { return false }
        if let last = pieces.last, !last.touched, last.key.count == 1, spelling.sequences[last.key + key] != nil {
            if keepsHistory { history.append(pieces) }
            pieces[pieces.count - 1] = piece(last.key + key, first: pieces.count == 1, after: pieces.dropLast().last)
            return true
        }
        if key == "'" {
            if keepsHistory { history.append(pieces) }
            pieces.append(Piece(key: key, options: [""]))
            return true
        }
        guard spelling.options[key] != nil, spelling.consonants[char] != nil || spelling.medial[char] != nil else {
            return false
        }
        if keepsHistory { history.append(pieces) }
        pieces.append(piece(key, first: pieces.isEmpty, after: pieces.last))
        return true
    }

    /// Removes the last typed character, with any choice made for it.
    public mutating func backspace() {
        if let previous = history.popLast() {
            pieces = previous
        }
    }

    /// The next (+1) or previous (-1) letter for the last key.
    public mutating func cycle(_ step: Int) {
        guard let last = pieces.last, last.options.count > 1 else { return }
        let count = last.options.count
        pieces[pieces.count - 1].choice = ((last.choice + step) % count + count) % count
        pieces[pieces.count - 1].touched = true
    }

    /// Picks one of `labels` for the last key (a click in the candidate window).
    @discardableResult
    public mutating func choose(_ label: String) -> Bool {
        guard let index = labels.firstIndex(of: label) else { return false }
        pieces[pieces.count - 1].choice = index
        pieces[pieces.count - 1].touched = true
        return true
    }

    private func piece(_ key: String, first: Bool, after previous: Piece?) -> Piece {
        let char = key.first!
        let preferred: String
        var extra: [String] = []
        if let sequence = spelling.sequences[key] {
            // As in the rules: a first long vowel is the alif with hamza, then the vowel (ou -> أو, aa -> أ).
            preferred = first ? spelling.initial[char].map { $0 + (sequence == "ا" ? "" : sequence) } ?? sequence : sequence
            // Two consonant keys that joined (sh -> ش) also offer their letters apart (سه), last, so ⇧Tab reaches it.
            if let letter = spelling.consonants[char], let second = key.dropFirst().first {
                extra = [letter + (spelling.consonants[second] ?? spelling.medial[second] ?? "")]
            }
        } else if let vowel = spelling.medial[char] {
            preferred = first ? spelling.initial[char] ?? vowel : vowel
        } else {
            let letter = spelling.consonants[char] ?? ""
            let doubled = previous.map { $0.key == key && !$0.touched } ?? false
            preferred = doubled ? "" : letter
            extra = [letter]
        }
        var options = [preferred]
        for option in spelling.options[key, default: []] + extra where !options.contains(option) {
            options.append(option)
        }
        return Piece(key: key, options: options)
    }
}

extension Speller {
    /// The keys that can be typed while spelling, for `keystrokes(toSpell:with:)`.
    static let keys = "abcdefghijklmnopqrstuvwxyz2356789'".map(String.init)

    /// The fewest presses (keys and Tabs) that spell `word` exactly, or nil if it cannot be spelled: a check that
    /// every Arabic word can be written, and a measure of how much work a fix is.
    public static func keystrokes(toSpell word: String, with spelling: SpellingOptions) -> Int? {
        let target = Array(word.unicodeScalars)
        guard !target.isEmpty else { return nil }
        func fits(_ text: String) -> Bool {
            let scalars = Array(text.unicodeScalars)
            return scalars.count <= target.count && scalars.elementsEqual(target.prefix(scalars.count))
        }
        func state(_ speller: Speller) -> String {
            let last = speller.pieces.last
            let frozen = speller.pieces.dropLast().map(\.arabic).joined()
            return "\(frozen)|\(last?.key ?? "")|\(last?.choice ?? -1)|\(last?.touched ?? false)|\(min(speller.pieces.count, 2))"
        }
        let joinable = Set(spelling.sequences.keys.map { String($0.prefix(1)) })  // keys that may join the next one
        // Keys worth trying next: one that can write a next letter, write nothing, or join with a key before or after.
        func useful(_ key: String, after last: Piece?, _ wanted: Set<Unicode.Scalar>) -> Bool {
            let options = spelling.options[key, default: []]
            if let last, !last.touched, spelling.sequences[last.key + key] != nil { return true }
            return key == "'" || joinable.contains(key) || options.contains("")
                || options.contains { $0.unicodeScalars.first.map(wanted.contains) ?? false }
        }
        var start = Speller(spelling)
        start.keepsHistory = false
        var frontier = [start]
        var seen: Set<String> = [state(frontier[0])]
        for presses in 1...(3 * target.count + 4) {
            var next: [Speller] = []
            for speller in frontier {
                var moves: [Speller] = []
                // The next letter after the whole word so far, or after its fixed part (the last key may still change).
                let positions = [speller.arabic.unicodeScalars.count,
                                 speller.pieces.dropLast().map(\.arabic).joined().unicodeScalars.count]
                let wanted = Set(positions.filter { $0 < target.count }.map { target[$0] })
                for key in keys where useful(key, after: speller.pieces.last, wanted) {
                    var typed = speller
                    if typed.type(key) { moves.append(typed) }
                }
                for step in [1, -1] {
                    var cycled = speller
                    cycled.cycle(step)
                    moves.append(cycled)
                }
                for move in moves {
                    let frozen = move.pieces.dropLast().map(\.arabic).joined()
                    // Keep only states that can still become the word: what is fixed must match, and the last key
                    // must have a letter that continues it.
                    guard fits(frozen), move.pieces.last.map({ last in
                              last.options.contains { fits(frozen + $0) } || (!last.touched && joinable.contains(last.key))
                          }) ?? true,
                          seen.insert(state(move)).inserted else { continue }
                    if move.arabic.unicodeScalars.elementsEqual(target) { return presses }
                    next.append(move)
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return nil
    }
}
