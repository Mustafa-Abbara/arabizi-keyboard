import Foundation

/// Text the model must never change (roadmap P5 step 2, Claude's recommendation): links, emails, @mentions and
/// #hashtags, emoji and standalone numbers are swapped for placeholders ⟦0⟧, ⟦1⟧… before the model runs and put
/// back afterwards. A digit inside a word (3am, 7elo, 2pm is a number but 3am is not) is a letter and stays.
public struct ProtectedText: Equatable, Sendable {
    /// The text with every protected span replaced by its placeholder.
    public let masked: String
    /// The original text of each placeholder, in order: spans[0] is ⟦0⟧.
    public let spans: [String]
}

public enum ProtectedSpans {
    // The same number pattern as B0 (eval/src/arabizi_eval/pairs.py NUMBER), so "standalone number" means one thing.
    private static let patterns: [NSRegularExpression] = [
        #"https?://\S+|www\.\S+"#,
        #"[\w.+-]+@[\w-]+\.[\w.]+"#,
        #"(?<![\w@#])[@#]\w+"#,
        #"(?<![A-Za-z0-9])[$€£]?\d+(?:[.,:]\d+)*(?:[$€£%]|k|K|pm|PM)?(?![A-Za-z0-9])"#,
        // The placeholder brackets themselves, so the masked text holds no bracket that is not ours.
        #"[⟦⟧]+"#,
    ].map { try! NSRegularExpression(pattern: $0) }  // swiftlint:disable:this force_try

    /// Punctuation that ends a sentence rather than a link: "shuf www.lau.edu." keeps the last dot outside.
    private static let trailingPunctuation = Set(".,;:!?)]}\"'»؟،؛")

    public static func protect(_ text: String) -> ProtectedText {
        let whole = NSRange(text.startIndex..., in: text)
        var ranges: [Range<String.Index>] = patterns.flatMap { pattern in
            pattern.matches(in: text, range: whole).compactMap { match in
                // A match that cuts a character in two (the 1 of the keycap 1️⃣) is not a span of its own.
                guard let range = Range(match.range, in: text), range.lowerBound.samePosition(in: text) != nil,
                      range.upperBound.samePosition(in: text) != nil else { return nil }
                return trimmed(range, in: text)
            }
        }
        ranges += emojiRuns(in: text)
        // Earliest first, the longest of those first; drop anything inside a span already taken.
        ranges.sort { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }
        var masked = ""
        var spans: [String] = []
        var cursor = text.startIndex
        for range in ranges where range.lowerBound >= cursor && !range.isEmpty {
            masked += text[cursor..<range.lowerBound] + "⟦\(spans.count)⟧"
            spans.append(String(text[range]))
            cursor = range.upperBound
        }
        masked += text[cursor...]
        return ProtectedText(masked: masked, spans: spans)
    }

    /// Put the spans back. nil when the model lost, repeated or invented a placeholder, or left a stray bracket:
    /// the caller then uses the rule fallback (P5 step 3).
    public static func restore(_ output: String, spans: [String]) -> String? {
        var result = ""
        var seen = Set<Int>()
        var rest = Substring(output)
        while let open = rest.firstIndex(where: { $0 == "⟦" || $0 == "⟧" }) {
            guard rest[open] == "⟦", let close = rest[open...].firstIndex(of: "⟧") else { return nil }
            let number = rest[rest.index(after: open)..<close]
            guard let index = Int(number), String(index) == number, spans.indices.contains(index),
                  seen.insert(index).inserted else { return nil }
            result += rest[..<open] + spans[index]
            rest = rest[rest.index(after: close)...]
        }
        guard seen.count == spans.count else { return nil }
        return result + rest
    }

    private static func trimmed(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var upper = range.upperBound
        while upper > range.lowerBound, trailingPunctuation.contains(text[text.index(before: upper)]) {
            upper = text.index(before: upper)
        }
        return range.lowerBound..<upper
    }

    /// Consecutive emoji (😂😂😂, 👍🏽, 🇱🇧, ❤️, 1️⃣) form one span.
    private static func emojiRuns(in text: String) -> [Range<String.Index>] {
        var runs: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if isEmoji(text[index]) {
                start = start ?? index
            } else if let begin = start {
                runs.append(begin..<index)
                start = nil
            }
        }
        if let begin = start {
            runs.append(begin..<text.endIndex)
        }
        return runs
    }

    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        // Emoji presentation selector or keycap: 1️⃣ starts with an ASCII digit but is an emoji.
        if scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 }) {
            return true
        }
        // ASCII digits, # and * have the Emoji property too; on their own they are text.
        return scalars.contains { !$0.isASCII && $0.properties.isEmoji }
    }
}
