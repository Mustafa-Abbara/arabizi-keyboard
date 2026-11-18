import Foundation

/// Checks on the model's answer before it is used (roadmap P5 step 3). Any failure means the rule fallback
/// answers instead (`fallbackCheckFailed`). The limits come from config/engine.json (`EngineConfig`).
public struct OutputChecks: Equatable, Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// Nothing but whitespace.
        case empty
        /// A placeholder was lost, repeated, invented or malformed (ProtectedSpans.restore).
        case placeholders
        /// Latin words that were not in the input: an English word the model made up, or half-converted Arabizi.
        case newLatin([String])
        /// Too few or too many words for the input.
        case wordCount(output: Int, input: Int)
        /// An emoji was lost, added or changed (emoji are not placeholders, ADR 0025).
        case emoji
        /// Letters of another script (Chinese, Cyrillic, Hebrew…) that were not in the input: a multilingual model
        /// slipping into another language mid-word (`الم模型`, size study 18 Nov 2026).
        case otherScript
    }

    /// The output may have between `minWordRatio × n − wordSlack` and `maxWordRatio × n + wordSlack` words for
    /// an input of n words. The slack is for short messages: "w el bet" (3 words) is "والبيت" (1 word).
    public var minWordRatio: Double
    public var maxWordRatio: Double
    public var wordSlack: Int
    /// Words the training data keeps in Latin (the rule dictionary's keep-Latin list): a short glued word must be
    /// one of them to count as typed (`btv` -> `tv`), so a misread Arabizi word does not (`3ajen` -> `jen`).
    public var keptLatin: Set<String> = []

    public init(minWordRatio: Double = 0.5, maxWordRatio: Double = 2.0, wordSlack: Int = 1) {
        self.minWordRatio = minWordRatio
        self.maxWordRatio = maxWordRatio
        self.wordSlack = wordSlack
    }

    /// Check the model's answer to `input` (the masked text it was given) and return it with the protected
    /// spans put back, or why it cannot be used.
    public func check(_ output: String, for input: ProtectedText) -> Result<String, Failure> {
        let answer = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return .failure(.empty) }
        guard let restored = ProtectedSpans.restore(answer, spans: input.spans) else { return .failure(.placeholders) }
        guard Self.emoji(in: answer) == Self.emoji(in: input.masked) else { return .failure(.emoji) }
        let typed = Set(input.masked.unicodeScalars.filter(Self.isOtherScript))
        guard answer.unicodeScalars.allSatisfy({ !Self.isOtherScript($0) || typed.contains($0) }) else {
            return .failure(.otherScript)
        }
        // Both sides still masked: links and emails are placeholders here, so they never count as Latin words.
        let allowed = Set(Self.words(input.masked).map { Token($0).core.lowercased() })
        let invented = Self.words(answer).map { Token($0).core }.filter { core in
            core.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }
                && !Self.isInputWord(core, allowed, keptLatin: keptLatin)
        }
        guard invented.isEmpty else { return .failure(.newLatin(invented)) }
        let inputWords = Self.words(input.masked).count
        let outputWords = Self.words(answer).count
        let lowest = minWordRatio * Double(inputWords) - Double(wordSlack)
        let highest = maxWordRatio * Double(inputWords) + Double(wordSlack)
        guard Double(outputWords) >= lowest && Double(outputWords) <= highest else {
            return .failure(.wordCount(output: outputWords, input: inputWords))
        }
        return .success(restored)
    }

    /// Arabizi prefixes that can be glued to an English word (`lvideo`, `bel meeting`, `3alfacebook`); the Arabic
    /// answer writes them apart (SPELLING.md 4), so `video` counts as typed when the input has `lvideo` (ADR 0023).
    public static let gluedPrefixes = ["l", "el", "il", "al", "b", "bi", "be", "bel", "bil", "w", "wel", "wil",
                                       "3a", "3al", "hal", "la", "lal"]

    /// Whether a Latin word of the answer was typed: an input word itself, or one glued to an Arabizi prefix
    /// that is at least 4 letters long or kept in Latin by the training data. `inputWords` are lowercased.
    public static func isInputWord(_ word: String, _ inputWords: Set<String>, keptLatin: Set<String> = []) -> Bool {
        let word = word.lowercased()
        if inputWords.contains(word) { return true }
        guard word.count >= 4 || keptLatin.contains(word) else { return false }
        return gluedPrefixes.contains { inputWords.contains($0 + word) }
    }

    /// A letter that is neither Arabic nor Latin: what a Lebanese conversion never writes unless it was typed.
    static func isOtherScript(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.isAlphabetic else { return false }
        switch scalar.value {
        case 0x0000...0x024F, 0x1E00...0x1EFF: return false  // Latin, with accents
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return false  // Arabic
        default: return true
        }
    }

    /// The emoji of a text in order, as typed (skin tones and flags kept whole).
    static func emoji(in text: String) -> [Character] {
        text.filter(ProtectedSpans.isEmoji).map { $0 }
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
