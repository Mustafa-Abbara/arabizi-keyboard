import Foundation

/// Words the model wrote that were never written in the training sentences: "unsure" (ADR 0034). On the v3 dev runs
/// (7 Nov 2026) such a word is wrong 54% of the time, against 6% for a known word, and holds 56% of the wrong words.
/// Replacing it with the rules' word or the nearest known word breaks more right words than it fixes; replacing it
/// with the rule dictionary's spelling of the typed word fixes four for every one it breaks. So the keyboard makes
/// that one swap, and points at the unsure words that remain instead of guessing.
public struct UnsureWords: Sendable {
    /// The Arabic words of the training sentences (the lexicon's `arabic_words`).
    let known: Set<String>
    /// The rule dictionary: typed word → its spelling in the training sentences (the lexicon's `words`).
    let dictionary: [String: String]

    public init(known: some Sequence<String>, dictionary: [String: String]) {
        self.known = Set(known)
        self.dictionary = Dictionary(dictionary.map { (WordParts($0.key).core.lowercased(), $0.value) },
                                     uniquingKeysWith: { first, _ in first })
    }

    /// Whether `word` (punctuation around it ignored) has Arabic letters and was never written in training.
    public func isUnsure(_ word: String) -> Bool {
        let core = WordParts(word).core
        guard core.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) else { return false }
        return !known.contains(core)
    }

    /// `converted` (the model's Arabic for `latin`) with each unsure word that came from one typed word in the
    /// dictionary written the dictionary's way; punctuation around it kept. Which typed word a shown word came from
    /// is `align` (WordAlignment).
    public func swap(latin: String, converted: String, align: ([String], [String]) -> [Range<Int>?]) -> String {
        let typed = latin.split(whereSeparator: \.isWhitespace).map(String.init)
        var shown = converted.components(separatedBy: " ")
        guard shown.contains(where: isUnsure) else { return converted }
        let alignment = align(typed, shown)
        var changed = false
        for i in shown.indices where i < alignment.count && isUnsure(shown[i]) {
            guard let run = alignment[i], run.count == 1, run.upperBound <= typed.count,
                  let spelling = dictionary[WordParts(typed[run.lowerBound]).core.lowercased()],
                  spelling != WordParts(shown[i]).core else { continue }
            shown[i] = WordParts(shown[i]).with(spelling)
            changed = true
        }
        return changed ? shown.joined(separator: " ") : converted
    }

    /// The unsure words of `text`, in order, without the punctuation around them.
    public func unsure(in text: String) -> [String] {
        text.components(separatedBy: " ").filter(isUnsure).map { WordParts($0).core }
    }
}
