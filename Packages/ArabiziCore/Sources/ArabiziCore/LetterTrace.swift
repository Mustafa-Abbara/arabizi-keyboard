import Foundation

extension SpellingOptions {
    /// Whether every letter of `arabic` can come from a key of the typed word `latin`, using the letters each key
    /// may stand for (spelling_options.json): `yj7sh` can write يجحش but not يجهش (no key writes ه). A doubled key
    /// may write one letter (`sakkar`: سكر); apostrophes, hyphens and other marks write nothing.
    public func canWrite(_ arabic: String, from latin: String) -> Bool {
        let typed = Array(latin.lowercased()), target = Array(arabic)
        let keys = options.keys.sorted { $0.count > $1.count }.map { (key: Array($0), letters: options[$0] ?? []) }
        var memo: [Int: Bool] = [:]
        func walk(_ i: Int, _ j: Int) -> Bool {
            if i == typed.count { return j == target.count }
            let id = i * (target.count + 1) + j
            if let known = memo[id] { return known }
            var found = false
            let character = typed[i]
            if !character.isLetter && !character.isNumber {
                found = walk(i + 1, j)
            } else {
                if i > 0, typed[i - 1] == character { found = walk(i + 1, j) }
                for (key, letters) in keys where !found && typed[i...].starts(with: key) {
                    for letter in letters where !found {
                        let written = Array(letter)
                        if target[j...].starts(with: written) { found = walk(i + key.count, j + written.count) }
                    }
                }
            }
            memo[id] = found
            return found
        }
        return walk(0, 0)
    }
}

extension Suggestions {
    /// A converted word that is likely wrong: it holds a letter no typed key can write, and it is not a word the
    /// dictionary or the training sentences know (`waraye` -> ورايق). On the v3 dev outputs, 20 of the 27 words
    /// this flags were wrong (1 Nov 2026). Only used to point at the word; the conversion is never changed.
    public func isDoubtful(_ shown: String, latin: String?, spelling: SpellingOptions) -> Bool {
        let word = WordParts(shown).core
        guard let latin, case let typed = WordParts(latin).core, !typed.isEmpty, !word.isEmpty,
              typed.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)
                                                               || $0 == "'") }),
              word.unicodeScalars.allSatisfy(Self.isArabicLetter), !knownArabic.contains(word) else { return false }
        return !spelling.canWrite(word, from: typed)
    }
}
