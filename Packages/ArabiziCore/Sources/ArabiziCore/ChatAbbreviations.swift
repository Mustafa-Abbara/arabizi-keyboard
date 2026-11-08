import Foundation

/// Chat abbreviations and short English words kept exactly as typed inside an Arabizi message (ADR 0035):
/// `idk`, `tbh`, `mins`, `pdf` (`data/rules/chat_abbreviations.json`).
///
/// Most never appear in the training data, so the model reads them as Arabizi and writes them in Arabic letters
/// (`idk` → إيدك, `tho` → شو, `mins` → مين on real WhatsApp rows, 8 Nov 2026). The rules get them as placeholders
/// (ProtectedSpans), put back afterwards. The model sees them as typed: placeholders cost it 400–500 ms each and
/// pushed short messages past their deadline; instead, the word of its answer that comes from an abbreviation
/// (WordAlignment) is put back as typed. A word matches whole, ignoring case and the punctuation around it (`idk,`
/// and `IDK?` match; `idkk` does not).
public struct ChatAbbreviations: Sendable {
    public static let fileName = "chat_abbreviations.json"

    /// Lower case.
    public let words: Set<String>

    public init(words: Set<String>) {
        self.words = Set(words.map { $0.lowercased() })
    }

    /// Reads the list from the rules folder; nil when the file is missing or unreadable (nothing is kept then).
    public init?(rulesDirectory: URL) {
        struct File: Decodable { let words: [String] }
        guard let data = try? Data(contentsOf: rulesDirectory.appending(path: Self.fileName)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        self.init(words: Set(file.words))
    }

    /// Where each abbreviation of `text` is: the word itself, without the punctuation around it.
    func ranges(in text: String) -> [Range<String.Index>] {
        guard !words.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
            let token = text[start..<index]
            guard let first = token.firstIndex(where: Self.isWordCharacter),
                  let last = token.lastIndex(where: Self.isWordCharacter) else { continue }
            let core = token[first...last]
            if words.contains(core.lowercased()) { found.append(first..<token.index(after: last)) }
        }
        return found
    }

    /// The rules' conversion with every abbreviation kept as typed.
    public func convert(_ text: String, with rules: RuleConverter) -> String {
        let protected = ProtectedSpans.mask(text, ranges: ranges(in: text))
        guard !protected.spans.isEmpty else { return rules.convert(text) }
        return ProtectedSpans.restore(rules.convert(protected.masked), spans: protected.spans) ?? rules.convert(text)
    }

    /// The model's `answer` for `typed` with each word that comes from an abbreviation written as typed (its
    /// punctuation kept). A second word from the same abbreviation (`yea` → يا ياه) is dropped: one the alignment
    /// gives to it, or an untraced one right after it when the next traced word comes from the next typed word (no
    /// typed word is left for it). Other untraced words are left alone.
    public func restore(in answer: String, typed: String, rules: RuleConverter) -> String {
        let latin = typed.split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = latin.map { words.contains(Self.core($0).lowercased()) }
        guard kept.contains(true) else { return answer }
        let shown = answer.split(whereSeparator: \.isWhitespace).map(String.init)
        let sources = WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) })
        var out: [String] = []
        var done = Set<Int>()
        var after: Int?  // the abbreviation the last kept word came from, while untraced words follow it
        for (j, word) in shown.enumerated() {
            guard let source = sources[j] else {
                let next = sources[(j + 1)...].lazy.compactMap { $0 }.first?.lowerBound ?? latin.count
                if let abbreviation = after, next == abbreviation + 1 { continue }
                out.append(word)
                after = nil
                continue
            }
            after = nil
            guard source.count == 1, kept[source.lowerBound] else {
                out.append(word)
                continue
            }
            if done.insert(source.lowerBound).inserted {
                out.append(WordParts(word).with(Self.core(latin[source.lowerBound])))
            }
            after = source.lowerBound
        }
        return out.joined(separator: " ")
    }

    /// The word without the punctuation around it.
    static func core(_ token: String) -> String {
        guard let first = token.firstIndex(where: isWordCharacter),
              let last = token.lastIndex(where: isWordCharacter) else { return "" }
        return String(token[first...last])
    }

    private static func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber }
}
