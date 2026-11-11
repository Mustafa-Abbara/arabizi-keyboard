import Foundation

/// What a settings window shows under "Your words" (ADR 0033): the spellings the user has taught the keyboard, the
/// habits it writes by itself now, and the habits the user refused. Built from the encrypted record each time the
/// window opens; single words only, as the record holds them.
public struct YourWords: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public let latin: String
        public let arabic: String
        public let times: Int
    }

    /// How many fixes are recorded (the last 30 days).
    public let fixes: Int
    /// Habits in force, by typed word.
    public let habits: [Habit]
    /// Habits the user said no to, by typed word.
    public let refused: [Habit]
    /// Each spelling picked, the most picked first.
    public let words: [Word]

    public init(corrections: [Correction], refused no: Set<Habit>) {
        fixes = corrections.count
        var counts: [String: Word] = [:]
        for fix in corrections {
            let latin = fix.latin.lowercased()
            let key = latin + "\u{0}" + fix.chosen
            counts[key] = Word(latin: latin, arabic: fix.chosen, times: (counts[key]?.times ?? 0) + 1)
        }
        words = counts.values.sorted { ($0.times, $1.latin, $1.arabic) > ($1.times, $0.latin, $0.arabic) }
        habits = Habits.learned(from: corrections).filter { !no.contains($0) }.sorted { $0.latin < $1.latin }
        refused = no.sorted { ($0.latin, $0.spelling) < ($1.latin, $1.spelling) }
    }

    /// For the Windows settings window, which reads it through the C interface: one line each, fields separated by
    /// tabs. `fixes N`, then `habit LATIN ARABIC`, `refused LATIN ARABIC` and `word LATIN ARABIC TIMES` lines.
    public var lines: String {
        func field(_ text: String) -> String {
            text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var out = ["fixes\t\(fixes)"]
        out += habits.map { "habit\t\(field($0.latin))\t\(field($0.spelling))" }
        out += refused.map { "refused\t\(field($0.latin))\t\(field($0.spelling))" }
        out += words.map { "word\t\(field($0.latin))\t\(field($0.arabic))\t\($0.times)" }
        return out.joined(separator: "\n")
    }
}
