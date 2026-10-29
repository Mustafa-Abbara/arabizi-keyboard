import Foundation

/// Recognises text that is plain English, so the engine leaves it alone instead of converting it (ADR 0031).
///
/// Latin letters are all the keyboard sees, so an English sentence looks like Arabizi. It is English when it is made
/// mostly of common English function words (`data/rules/english_stopwords.json`) and holds nothing that looks
/// like Arabizi: no digit inside a word (`3am`, `ba7ebak`) and no word of the rule dictionary that is not itself a
/// function word. A sentence with any Arabizi in it goes to the model as before, which keeps English words by itself.
public struct EnglishGuard: Sendable {
    public static let fileName = "english_stopwords.json"
    /// At least this many function words, and at least this share of the words.
    static let minimumFunctionWords = 2
    static let minimumShare = 0.4
    static let minimumWords = 3

    let functionWords: Set<String>
    let arabizi: Set<String>

    public init(functionWords: Set<String>, arabizi: Set<String>) {
        self.functionWords = functionWords
        self.arabizi = arabizi
    }

    /// Reads the function words from the rules folder; nil when the file is missing or unreadable (the guard is off).
    public init?(rulesDirectory: URL, rules: RuleConverter) {
        struct File: Decodable { let words: [String] }
        guard let data = try? Data(contentsOf: rulesDirectory.appending(path: Self.fileName)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        self.init(functionWords: Set(file.words.map(Self.bare)), arabizi: rules.arabiziWords)
    }

    /// True when `text` is plain English.
    public func isEnglish(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF }) { return false }
        var words = 0, function = 0
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = Self.bare(String(token))
            guard word.unicodeScalars.count > 1,  // a lone letter (a, I, w, b) says nothing
                  word.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) else { continue }
            if RuleConverter.isUntouchedToken(String(token)) { continue }  // links, emails, @mentions, #tags
            words += 1
            if functionWords.contains(word) {
                function += 1
            } else if Self.hasDigitInside(word) || arabizi.contains(word) {
                return false
            }
        }
        return words >= Self.minimumWords && function >= Self.minimumFunctionWords
            && Double(function) / Double(words) >= Self.minimumShare
    }

    /// Lower case, without apostrophes or the punctuation around the word.
    static func bare(_ token: String) -> String {
        let scalars = token.lowercased().unicodeScalars.filter { $0 != "'" && $0 != "’" }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: scalars)
        return String(text).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    /// A digit next to a letter, as Arabizi writes ع and ح (`3am`, `ba7r`); a bare number is not.
    static func hasDigitInside(_ word: String) -> Bool {
        let letters = word.unicodeScalars.contains { $0.properties.isAlphabetic }
        return letters && word.unicodeScalars.contains { ("2"..."9").contains($0) }
    }
}
