import Foundation

/// A spelling the user has taught the keyboard (ADR 0027 step 2, ADR 0033): this typed word is written this way.
public struct Habit: Codable, Hashable, Sendable {
    /// The typed word (or run of small words and a word, `el shr`), lower case, without the punctuation around it.
    public let latin: String
    /// The Arabic the user chose for it.
    public let spelling: String

    public init(latin: String, spelling: String) {
        self.latin = WordParts(latin).core.lowercased()
        self.spelling = spelling
    }
}

/// Turns repeated corrections into habits and applies them after the model (ADR 0027 #6, ADR 0033).
public enum Habits {
    /// A typed word becomes a habit after this many picks of the same spelling...
    public static let minimumPicks = 3
    /// ...on at least this many different days.
    public static let minimumDays = 2

    /// The habits the record supports. Each typed word's corrections are replayed in order: only the picks since the
    /// last time the user chose a different spelling count, so a spelling the user has changed their mind about is
    /// never a habit, and a new one forms from the new picks alone.
    public static func learned(from past: [Correction], calendar: Calendar = .current) -> [Habit] {
        var byWord: [String: [Correction]] = [:]
        for fix in past { byWord[WordParts(fix.latin).core.lowercased(), default: []].append(fix) }
        var habits: [Habit] = []
        for (latin, fixes) in byWord {
            let ordered = fixes.sorted { $0.date < $1.date }
            guard let last = ordered.last else { continue }
            let agreeing = ordered.reversed().prefix { $0.chosen == last.chosen }
            let days = Set(agreeing.map { calendar.startOfDay(for: $0.date) })
            if agreeing.count >= minimumPicks, days.count >= minimumDays {
                habits.append(Habit(latin: latin, spelling: last.chosen))
            }
        }
        return habits.sorted { $0.latin < $1.latin }
    }

    /// `converted` (the Arabic for `latin`) with each word whose typed word has a habit written the user's way.
    /// Which typed words a shown word came from is `align` (WordAlignment, as for suggestions); punctuation around a
    /// word is kept. Nothing changes without habits.
    public static func apply(_ habits: [Habit], latin: String, converted: String,
                             align: ([String], [String]) -> [Range<Int>?]) -> String {
        guard !habits.isEmpty else { return converted }
        let spellings = Dictionary(habits.map { ($0.latin, $0.spelling) }, uniquingKeysWith: { first, _ in first })
        let typed = latin.split(whereSeparator: \.isWhitespace).map(String.init)
        var shown = converted.components(separatedBy: " ")
        let alignment = align(typed, shown)
        var changed = false
        for i in shown.indices where i < alignment.count {
            guard let run = alignment[i], run.upperBound <= typed.count else { continue }
            let word = WordParts(typed[run].joined(separator: " ")).core.lowercased()
            guard let spelling = spellings[word] else { continue }
            let parts = WordParts(shown[i])
            if parts.core != spelling {
                shown[i] = parts.with(spelling)
                changed = true
            }
        }
        return changed ? shown.joined(separator: " ") : converted
    }
}
