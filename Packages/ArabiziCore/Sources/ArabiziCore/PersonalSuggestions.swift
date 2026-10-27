import Foundation

/// What kind of change a fix made to the shown word (ADR 0027 #9): used to put the kinds of spelling the user
/// picks most often first, and counted in the corrections report.
public enum FixKind: String, CaseIterable, Sendable {
    /// The letter rules' spelling of the typed word.
    case rules
    /// A long vowel (ا و ي) added or dropped.
    case longVowel = "long vowel"
    /// One letter swapped for a similar one (ت/ط, س/ص, ك/ق…).
    case letter
    /// The last letter (ه/ة, ى/ي…).
    case ending
    /// The first alif (ا/أ/إ).
    case alif
    /// The typed word kept in Latin.
    case latin
    /// Anything else (a word spelled by hand, a dictionary word typed differently).
    case other
}

extension Suggestions {
    /// The kind of change from `shown` to `chosen` for the typed word `latin`.
    public func kind(of chosen: String, replacing shown: String, latin: String?) -> FixKind {
        let new = WordParts(chosen).core, old = WordParts(shown).core
        if let latin {
            let typed = WordParts(latin).core
            if new.lowercased() == typed.lowercased() { return .latin }
            if WordParts(rules(typed)).core == new { return .rules }
        }
        let a = Array(old), b = Array(new)
        if a.count == b.count {
            let differing = a.indices.filter { a[$0] != b[$0] }
            guard differing.count == 1, let i = differing.first else { return .other }
            let pair = (a[i], b[i])
            func listed(_ table: [(Character, Character)]) -> Bool {
                table.contains { ($0.0 == pair.0 && $0.1 == pair.1) || ($0.0 == pair.1 && $0.1 == pair.0) }
            }
            if i == a.count - 1 && listed(Self.endings) { return .ending }
            if i == 0 && Self.starts.contains(pair.0) && Self.starts.contains(pair.1) { return .alif }
            return listed(Self.swaps) ? .letter : .other
        }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        guard long.count == short.count + 1 else { return .other }
        let i = short.indices.first { short[$0] != long[$0] } ?? short.count
        return Self.longVowels.contains(long[i]) && Array(long[..<i] + long[(i + 1)...]) == short ? .longVowel : .other
    }

    /// The ⌥Tab list personalised with the user's own fixes (ADR 0027 #8–#9), at most `limit`, never `shown`:
    /// 1. earlier fixes of the same typed word (most often chosen, then most recent);
    /// 2. fixes of typed words one letter apart (`shar` for `shr`) whose spelling looks like the shown word;
    /// 3. the usual candidates, the kinds of change the user picks most often first.
    public func personalized(for shown: String, latin: String?, past: [Correction], limit: Int = 5) -> [String] {
        let word = WordParts(shown).core
        let own = Self.pastFixesFirst(past, latin: latin, shown: shown, candidates: [], limit: limit)
        var similar: [String: Int] = [:]
        if let latin {
            let typed = Array(WordParts(latin).core.lowercased())
            for fix in past where fix.chosen != word && fix.latin.lowercased() != String(typed)
                && Self.oneEditApart(Array(fix.latin.lowercased()), typed)
                && WordAlignment.similarity(fix.chosen, word) >= 0.5 {
                similar[fix.chosen, default: 0] += 1
            }
        }
        let fromSimilar = similar.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let usual = ordered(candidates(for: shown, latin: latin, limit: limit + 3), shown: shown, latin: latin, by: past)
        var out: [String] = []
        for candidate in own + fromSimilar + usual where candidate != word && !out.contains(candidate) {
            out.append(candidate)
        }
        return Array(out.prefix(limit))
    }

    /// `candidates` with the kinds of change the user has picked most often first (stable: equal counts keep
    /// their order). Unchanged until the user has made at least `minimumPicks` fixes.
    func ordered(_ candidates: [String], shown: String, latin: String?, by past: [Correction],
                 minimumPicks: Int = 3) -> [String] {
        guard past.count >= minimumPicks else { return candidates }
        var picks: [FixKind: Int] = [:]
        for fix in past {
            picks[kind(of: fix.chosen, replacing: fix.rejected, latin: fix.latin), default: 0] += 1
        }
        return candidates.enumerated().sorted { x, y in
            let a = picks[kind(of: x.element, replacing: shown, latin: latin), default: 0]
            let b = picks[kind(of: y.element, replacing: shown, latin: latin), default: 0]
            return a != b ? a > b : x.offset < y.offset
        }.map(\.element)
    }
}

/// Counts over the user's corrections, never their text (the corrections report, ADR 0027 #10).
public struct CorrectionSummary: Equatable, Sendable {
    public let fixes: Int
    public let days: Int
    public let typedWords: Int
    /// Fixes that repeat an earlier fix exactly (same typed word, same spelling chosen).
    public let repeats: Int
    /// Typed words fixed the same way on two or more days (what a learned habit would need).
    public let repeatedOnTwoDays: Int
    public let byKind: [FixKind: Int]

    public init(_ past: [Correction], kind: (Correction) -> FixKind, calendar: Calendar = .current) {
        let sorted = past.sorted { $0.date < $1.date }
        fixes = sorted.count
        days = Set(sorted.map { calendar.startOfDay(for: $0.date) }).count
        typedWords = Set(sorted.map { $0.latin.lowercased() }).count
        var seen: Set<String> = []
        var daysPerFix: [String: Set<Date>] = [:]
        var repeated = 0
        for fix in sorted {
            let key = fix.latin.lowercased() + "\u{0}" + fix.chosen
            if !seen.insert(key).inserted { repeated += 1 }
            daysPerFix[key, default: []].insert(calendar.startOfDay(for: fix.date))
        }
        repeats = repeated
        repeatedOnTwoDays = daysPerFix.values.filter { $0.count >= 2 }.count
        byKind = sorted.reduce(into: [:]) { $0[kind($1), default: 0] += 1 }
    }
}
