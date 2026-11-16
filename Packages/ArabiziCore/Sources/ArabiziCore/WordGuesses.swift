import Foundation

/// One word of a conversion the model is asked about for the ↑ list (ADR 0036 #5): the message as typed, the
/// answer up to that word, and the word as shown with the typed word(s) it came from.
public struct GuessQuery: Hashable, Sendable {
    /// The message as typed (the engine's `text`).
    public let text: String
    /// The words shown before this one, joined by single spaces (the engine's `before`); empty for the first word.
    public let before: String
    /// The word as shown, with any punctuation around it.
    public let shown: String
    /// The typed word(s) it came from, nil when they cannot be traced.
    public let latin: String?

    public init(text: String, before: String, shown: String, latin: String?) {
        self.text = text
        self.before = before
        self.shown = shown
        self.latin = latin
    }
}

/// The model's guesses for words of a conversion (ADR 0036 #5), asked in the background and kept for the ↑ list.
/// The list shows at once without them; when they arrive the keyboard re-ranks it (`Composer.guessesArrived`).
/// Late or missing guesses (no engine, no model, the deadline passed) are never retried for that word: the
/// instant list stays. One request runs at a time, and only the newest waits for it, so the model is never asked
/// twice at once and a word the user has moved past is not waited for. Kept in memory only, the last few words; never logged.
public final class WordGuesses: @unchecked Sendable {  // everything mutable is behind `lock`
    /// How many guesses to ask for (ADR 0039 #5: 10 add 118 ms and nothing measurable).
    public static let count = 5
    /// The engine's deadline for them. On the Windows laptop 5 guesses take p95 484 ms and at most 635 ms, under 1%
    /// past this (docs/EVAL.md); past it the engine answers with none and the instant list stays.
    public static let deadlineMs = 600
    /// How many words' guesses are kept.
    static let kept = 16

    public typealias Guesses = [(word: String, logProbability: Double)]

    private let lock = NSLock()
    /// Asks the engine and waits for its answer: the guesses best first, or nil when there are none in time.
    private let ask: @Sendable (GuessQuery) -> Guesses?
    /// Runs the asking off the keyboard's thread (a new thread by default; tests run it in place).
    private let run: @Sendable (@escaping @Sendable () -> Void) -> Void
    private var ready: [(query: GuessQuery, guesses: Guesses)] = []
    private var missed: [GuessQuery] = []
    /// Asked for and not answered yet, newest last; `then` is called (on the asking thread) once each is answered.
    private var waiting: [(query: GuessQuery, then: (@Sendable (GuessQuery) -> Void)?)] = []
    private var asking: GuessQuery?

    public init(ask: @escaping @Sendable (GuessQuery) -> Guesses?,
                run: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { work in
                    Thread.detachNewThread { work() }
                }) {
        self.ask = ask
        self.run = run
    }

    /// The guesses for `query`, when they have arrived (possibly none: the model offered no Arabic word).
    public func guesses(for query: GuessQuery) -> Guesses? {
        lock.withLock { ready.last { $0.query == query }?.guesses }
    }

    /// True while `query` is asked for or waiting to be.
    public func isPending(_ query: GuessQuery) -> Bool {
        lock.withLock { asking == query || waiting.contains { $0.query == query } }
    }

    /// Asks for `query` in the background unless its guesses are here, were missed, or are already coming. `then`
    /// (on the asking thread) once they are here or missed, as well as any `then` given before for the same word (a
    /// word asked ahead, then opened). Returns true while they are coming.
    @discardableResult
    public func request(_ query: GuessQuery, then: (@Sendable (GuessQuery) -> Void)? = nil) -> Bool {
        let start = lock.withLock { () -> Bool? in
            if ready.contains(where: { $0.query == query }) || missed.contains(query) { return nil }
            let earlier = waiting.last { $0.query == query }?.then
            var both = then ?? earlier
            if let earlier, let then { both = { earlier($0); then($0) } }
            waiting.removeAll { $0.query == query }
            waiting.append((query, both))  // the newest, so it is asked next
            if asking != nil { return false }
            asking = query
            return true
        }
        guard let start else { return false }
        if start { run { [self] in work() } }
        return true
    }

    /// Asks for the word being asked for, then the newest one asked for meanwhile, until none is left.
    private func work() {
        while let query = lock.withLock({ asking }) {
            let answer = ask(query)
            let then = lock.withLock { () -> (@Sendable (GuessQuery) -> Void)? in
                if let answer {
                    ready.removeAll { $0.query == query }
                    ready.append((query, answer))
                    if ready.count > Self.kept { ready.removeFirst() }
                } else {
                    missed.append(query)
                    if missed.count > Self.kept * 4 { missed.removeFirst() }
                }
                let then = waiting.last { $0.query == query }?.then
                waiting.removeAll { $0.query == query }
                // Only the newest word asked for meanwhile is asked next: the user has left the older ones behind
                // (they are asked again if the user comes back to them).
                waiting = Array(waiting.suffix(1))
                asking = waiting.last?.query
                return then
            }
            then?(query)
        }
    }

    /// The instant list re-ranked with the model's guesses, without moving what the user has already seen: the
    /// first `keeping` places of `instant` stay (the highlighted spelling and those above it, ADR 0036 #4), the
    /// rest come from `reranked`, and the typed word keeps the last place. Never longer than either list.
    public static func merged(instant: [String], reranked: [String], keeping: Int) -> [String] {
        let keeping = min(max(keeping, 0), instant.count)
        let kept = Array(instant.prefix(keeping))
        let limit = max(instant.count, reranked.count)
        // The typed word (the Latin, last in both lists) keeps the last place.
        let typed = instant.last.flatMap { last in reranked.last == last && !kept.contains(last) ? last : nil }
        var out = kept
        for word in reranked where word != typed && !out.contains(word) { out.append(word) }
        if let typed {
            out = Array(out.prefix(limit - 1)) + [typed]
        } else {
            out = Array(out.prefix(limit))
        }
        return out
    }
}
