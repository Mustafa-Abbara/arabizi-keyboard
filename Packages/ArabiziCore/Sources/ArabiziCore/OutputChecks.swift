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
    }

    /// The output may have between `minWordRatio × n − wordSlack` and `maxWordRatio × n + wordSlack` words for
    /// an input of n words. The slack is for short messages: "w el bet" (3 words) is "والبيت" (1 word).
    public var minWordRatio: Double
    public var maxWordRatio: Double
    public var wordSlack: Int

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
        // Both sides still masked: links and emails are placeholders here, so they never count as Latin words.
        let allowed = Set(Self.words(input.masked).map { Token($0).core.lowercased() })
        let invented = Self.words(answer).map { Token($0).core }.filter { core in
            core.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic } && !allowed.contains(core.lowercased())
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

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
