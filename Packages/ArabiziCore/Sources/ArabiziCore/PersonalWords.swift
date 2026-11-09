import Foundation

/// The user's own words for this keyboard (ADR 0027, ADR 0033): every pick is recorded in the encrypted
/// CorrectionStore, and the habits it supports (Habits.learned, less the ones the user refused) are applied after
/// the model. The habits are kept in memory and read again only when the store changed (another app may have recorded
/// a pick), so applying them costs nothing on each key. Never logs or sends a word.
public final class PersonalWords: @unchecked Sendable {  // `habits`, `seen` and `learned` are behind `lock`
    public let store: CorrectionStore
    private let lock = NSLock()
    private var habits: [Habit] = []
    private var seen: Date?
    private var loaded = false
    /// A habit that formed with the last pick, for the keyboard to tell the user (once).
    private var learned: Habit?

    public init(store: CorrectionStore) { self.store = store }

    /// The habits in force now.
    public func current() -> [Habit] {
        lock.withLock {
            let changed = store.changed
            if !loaded || changed != seen {
                let refused = store.refused()
                habits = Habits.learned(from: store.all()).filter { !refused.contains($0) }
                seen = changed
                loaded = true
            }
            return habits
        }
    }

    /// Records a pick; when it completes a habit (that the user has not refused), remembers it to be announced.
    public func record(_ correction: Correction) {
        let before = Set(current())
        try? store.record(correction)
        if let new = current().first(where: { !before.contains($0) }) {
            lock.withLock { learned = new }
        }
    }

    /// The habit that formed with the last pick, once.
    public func takeLearned() -> Habit? {
        lock.withLock {
            defer { learned = nil }
            return learned
        }
    }

    /// The user said no to a habit: it is never applied or announced again (until allowed again in Your words or with harfi-words).
    public func refuse(_ habit: Habit) {
        try? store.refuse(habit)
    }
}

/// Words already pointed out in this app (in memory only).
public final class PointedOut: @unchecked Sendable {  // `words` is behind `lock`
    private let lock = NSLock()
    public init() {}
    private var words: Set<String> = []

    /// The first of `candidates` not pointed out yet, now marked as pointed out.
    public func first(of candidates: [String]) -> String? {
        lock.withLock {
            guard let word = candidates.first(where: { !words.contains($0) }) else { return nil }
            words.insert(word)
            return word
        }
    }
}
