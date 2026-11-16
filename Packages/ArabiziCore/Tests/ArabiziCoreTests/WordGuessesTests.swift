import Foundation
import Testing
@testable import ArabiziCore

// The model's guesses in the ↑ list (ADR 0036 #5): the instant list at once, re-ranked when the guesses arrive,
// unchanged when they are late or the user has moved on.

/// Background work held until the test runs it, so a test decides when the guesses "arrive".
private final class Later: @unchecked Sendable {
    private let lock = NSLock()
    private var work: [@Sendable () -> Void] = []
    var count: Int { lock.withLock { work.count } }
    func add(_ item: @escaping @Sendable () -> Void) { lock.withLock { work.append(item) } }
    func runAll() {
        while let next = lock.withLock({ work.isEmpty ? nil : work.removeFirst() }) { next() }
    }
}

/// What the fake engine was asked, and its answers by shown word (nil: no answer in time).
private final class FakeEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [GuessQuery] = []
    let answers: [String: WordGuesses.Guesses?]
    init(_ answers: [String: WordGuesses.Guesses?]) { self.answers = answers }
    var asked: [GuessQuery] { lock.withLock { queries } }
    func ask(_ query: GuessQuery) -> WordGuesses.Guesses? {
        lock.withLock { queries.append(query) }
        return answers[query.shown] ?? nil
    }
}

private let instant = ["صبيه", "سابية", "صبايا", "sabiye"]

/// A composer whose list for سبية is `instant`, and with the model's guesses the guessed words first (as the ranker
/// would put a confident guess), the typed word last.
private func guessingComposer(_ engine: FakeEngine, _ later: Later) -> (Composer, WordGuesses) {
    let guesses = WordGuesses(ask: { engine.ask($0) }, run: { later.add($0) })
    let suggester = Suggester(
        candidates: { shown, latin in shown == "سبية" ? instant : ["x", latin ?? ""] },
        align: { latin, shown in latin.count == shown.count ? latin.indices.map { $0..<($0 + 1) } : [] },
        record: { _ in },
        doubtful: { shown, _ in shown == "سبية" },
        guesses: guesses,
        candidatesWithGuesses: { shown, latin, guesses in
            let base = shown == "سبية" ? instant : ["x", latin ?? ""]
            let guessed = guesses.map(\.word).filter { !base.contains($0) }
            return Array((guessed + base.dropLast()).prefix(base.count - 1)) + [base.last!]
        })
    let converted = ["kifak ya sabiye": "كيفك يا سبية"]
    return (Composer(convert: { converted[$0] ?? $0 }, suggester: suggester), guesses)
}

private func typeAndOpen(_ composer: inout Composer) -> Effect {
    for character in "kifak ya sabiye" { _ = composer.handle(.text(String(character))) }
    _ = composer.handle(.enter)
    return composer.handle(.arrowUp, context: Context(cursorAtLastConversion: true))
}

@Test func theInstantListShowsFirstAndTheGuessesReRankIt() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2), ("صبيه", -1.1)]])
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    let opened = typeAndOpen(&c)
    #expect(opened == .suggest(marked: "كيفك يا سبية", selected: 8..<12, candidates: instant,
                               replacingLength: "كيفك يا سبية".utf16.count))
    let query = try #require(c.guessQuery)
    #expect(query == GuessQuery(text: "kifak ya sabiye", before: "كيفك يا", shown: "سبية", latin: "sabiye"))
    #expect(c.guessesArrived() == nil)             // asked, not here yet: nothing changes
    #expect(guesses.request(query))                // coming
    #expect(guesses.isPending(query))
    later.runAll()                                  // the engine answers
    #expect(engine.asked == [query])
    #expect(c.guessesArrived() == .suggest(marked: "كيفك يا سبية", selected: 8..<12,
                                           candidates: ["صبية", "صبيه", "سابية", "sabiye"], replacingLength: nil))
    #expect(c.currentCandidates == ["صبية", "صبيه", "سابية", "sabiye"])
    #expect(c.guessQuery == nil)                    // this word has its guesses
    #expect(c.guessesArrived() == nil)
    #expect(c.handle(.text("1")) == .commit("كيفك يا صبية"))
}

@Test func lateGuessesKeepTheInstantList() throws {
    let engine = FakeEngine(["سبية": WordGuesses.Guesses?.none])  // the deadline passed: no guesses
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    _ = typeAndOpen(&c)
    let query = try #require(c.guessQuery)
    #expect(guesses.request(query))
    later.runAll()
    #expect(guesses.guesses(for: query)?.count == nil)
    #expect(!guesses.isPending(query))
    #expect(c.guessesArrived() == nil)
    #expect(c.currentCandidates == instant)
    #expect(!guesses.request(query))                // missed: not asked again for this word
    #expect(later.count == 0)
    #expect(engine.asked.count == 1)
}

@Test func guessesForAWordTheUserLeftChangeNothing() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2)]])
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    _ = typeAndOpen(&c)
    let query = try #require(c.guessQuery)
    guesses.request(query)
    _ = c.handle(.arrowRight)                       // to يا, before the guesses for سبية come
    let other = try #require(c.guessQuery)
    #expect(other.shown == "يا")
    later.runAll()
    #expect(c.guessesArrived() == nil)              // they are for سبية, not the word shown now
    #expect(c.currentCandidates == ["x", "ya"])
    _ = c.handle(.arrowLeft)                        // back to سبية: its guesses are already here
    #expect(c.currentCandidates == ["صبية", "صبيه", "سابية", "sabiye"])
    #expect(c.guessQuery == nil)
}

@Test func guessesAfterTheListClosedChangeNothing() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2)]])
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    _ = typeAndOpen(&c)
    guesses.request(try #require(c.guessQuery))
    _ = c.handle(.escape)
    later.runAll()
    #expect(c.guessesArrived() == nil)
    #expect(!c.isSuggesting)
}

@Test func guessesNeverMoveTheHighlightedSpelling() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2), ("سبيه", -0.9)]])
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    _ = typeAndOpen(&c)
    guesses.request(try #require(c.guessQuery))
    _ = c.handle(.arrowDown)                        // صبيه highlighted and shown in the text
    later.runAll()
    let arrived = c.guessesArrived()
    let effect = try #require(arrived)
    #expect(effect == .suggest(marked: "كيفك يا صبيه", selected: 8..<12,
                               candidates: ["صبيه", "صبية", "سبيه", "sabiye"], replacingLength: nil))
    #expect(c.currentChoice == 0)
    #expect(c.handle(.enter) == .commit("كيفك يا صبيه"))
}

@Test func guessesWaitWhileAWordIsSpelled() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2)]])
    let later = Later()
    let guesses = WordGuesses(ask: { engine.ask($0) }, run: { later.add($0) })
    let spelling = try SpellingOptions(rulesDirectory: rulesDirectory, rules: RuleConverter(rulesDirectory: rulesDirectory))
    let suggester = Suggester(candidates: { _, _ in instant },
                              align: { latin, shown in latin.indices.map { $0..<($0 + 1) } },
                              record: { _ in }, spelling: spelling, guesses: guesses,
                              candidatesWithGuesses: { _, _, _ in ["صبية"] + instant })
    var c = Composer(convert: { _ in "كيفك يا سبية" }, suggester: suggester)
    _ = typeAndOpen(&c)
    guesses.request(try #require(c.guessQuery))
    _ = c.handle(.suggest)                          // ⌥Tab again: spelling letter by letter
    #expect(c.guessQuery == nil)
    later.runAll()
    #expect(c.guessesArrived() == nil)
    #expect(c.isSpelling)
}

@Test func aDoubtfulWordIsAskedAheadAndTheListOpensWithItsGuesses() throws {
    let engine = FakeEngine(["سبية": [("صبية", -0.2)]])
    let later = Later()
    var (c, guesses) = guessingComposer(engine, later)
    for character in "kifak ya sabiye" { _ = c.handle(.text(String(character))) }
    #expect(c.prefetchQuery == nil)                 // nothing converted yet
    _ = c.handle(.enter)
    let ahead = try #require(c.prefetchQuery)       // سبية looks wrong: ↑ opens on it
    #expect(ahead == GuessQuery(text: "kifak ya sabiye", before: "كيفك يا", shown: "سبية", latin: "sabiye"))
    guesses.request(ahead)
    later.runAll()
    #expect(c.handle(.arrowUp, context: Context(cursorAtLastConversion: true))
            == .suggest(marked: "كيفك يا سبية", selected: 8..<12, candidates: ["صبية", "صبيه", "سابية", "sabiye"],
                        replacingLength: "كيفك يا سبية".utf16.count))
    #expect(c.guessQuery == nil)
    #expect(engine.asked.count == 1)
}

@Test func aWordThatLooksRightIsNotAskedAhead() {
    let later = Later()
    var (c, _) = guessingComposer(FakeEngine([:]), later)
    for character in "kifak ya" { _ = c.handle(.text(String(character))) }
    _ = c.handle(.enter)
    #expect(c.prefetchQuery == nil)
}

@Test func withoutGuessesNothingIsAsked() {
    let suggester = Suggester(candidates: { _, _ in ["x"] }, align: { latin, _ in latin.indices.map { $0..<($0 + 1) } },
                              record: { _ in }, doubtful: { _, _ in true })
    var c = Composer(convert: { $0.uppercased() }, suggester: suggester)
    for character in "shu" { _ = c.handle(.text(String(character))) }
    _ = c.handle(.enter)
    #expect(c.prefetchQuery == nil)
    _ = c.handle(.arrowUp, context: Context(cursorAtLastConversion: true))
    #expect(c.guessQuery == nil)
}

@Test func onlyTheNewestWordWaitsForTheModel() {
    let engine = FakeEngine(["a": [("أ", -0.1)], "b": [("ب", -0.1)], "c": [("ت", -0.1)]])
    let later = Later()
    let guesses = WordGuesses(ask: { engine.ask($0) }, run: { later.add($0) })
    func query(_ word: String) -> GuessQuery { GuessQuery(text: "x", before: "", shown: word, latin: word) }
    #expect(guesses.request(query("a")))
    #expect(guesses.request(query("b")))            // waits behind a
    #expect(guesses.request(query("c")))            // replaces b: the user has moved on
    #expect(guesses.request(query("a")))            // already being asked: still coming, not asked twice
    #expect(later.count == 1)                       // one worker
    later.runAll()
    #expect(engine.asked.map(\.shown) == ["a", "c"])
    #expect(guesses.guesses(for: query("b"))?.count == nil)
    #expect(!guesses.isPending(query("b")))
    #expect(guesses.request(query("b")))            // asked again when the user comes back to it
}

@Test func theCallbackComesOnceTheGuessesAreHereOrMissed() {
    let engine = FakeEngine(["a": [("أ", -0.1)], "b": WordGuesses.Guesses?.none])
    let later = Later()
    let guesses = WordGuesses(ask: { engine.ask($0) }, run: { later.add($0) })
    let called = Later()
    let a = GuessQuery(text: "x", before: "", shown: "a", latin: "a")
    let b = GuessQuery(text: "x", before: "", shown: "b", latin: "b")
    guesses.request(a) { query in called.add { _ = query } }
    later.runAll()
    #expect(called.count == 1)
    guesses.request(b) { query in called.add { _ = query } }
    later.runAll()
    #expect(called.count == 2)
}

@Test func mergingKeepsWhatTheUserHasSeen() {
    let instant = ["a", "b", "c", "d", "typed"]
    let reranked = ["g", "c", "a", "h", "typed"]
    #expect(WordGuesses.merged(instant: instant, reranked: reranked, keeping: 0) == reranked)
    #expect(WordGuesses.merged(instant: instant, reranked: reranked, keeping: 1) == ["a", "g", "c", "h", "typed"])
    #expect(WordGuesses.merged(instant: instant, reranked: reranked, keeping: 2) == ["a", "b", "g", "c", "typed"])
    #expect(WordGuesses.merged(instant: instant, reranked: reranked, keeping: 5) == instant)  // the typed word chosen
    // A list without the typed word (no Latin traced) is never longer than before.
    #expect(WordGuesses.merged(instant: ["a", "b"], reranked: ["g", "a"], keeping: 1) == ["a", "g"])
    #expect(WordGuesses.merged(instant: [], reranked: ["g", "typed"], keeping: 0) == ["g", "typed"])
}

@Test func aWordAskedAheadStillTellsTheListThatOpensOnIt() {
    let engine = FakeEngine(["a": [("أ", -0.1)]])
    let later = Later()
    let guesses = WordGuesses(ask: { engine.ask($0) }, run: { later.add($0) })
    let a = GuessQuery(text: "x", before: "", shown: "a", latin: "a")
    let called = Later()
    #expect(guesses.request(a))                     // asked ahead, right after the conversion: nobody to tell
    #expect(guesses.request(a) { _ in called.add {} })  // ↑ opened on it before the answer: tell the keyboard
    later.runAll()
    #expect(called.count == 1)
    #expect(engine.asked.count == 1)
}
