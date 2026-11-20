import Foundation
import Testing
@testable import ArabiziCore

/// Merge and split entries (ADR 0041): the Swift port against the Python reference, and how the composer applies them.
@Suite struct MergeSplitTests {
    struct Fixture: Decodable {
        struct Span: Decodable {
            let words: [String]
            let index: Int
            let typed: [[String]]
            let entry: [Value]?
            let split: [String]
            let mergeNext: [String]
            enum CodingKeys: String, CodingKey { case words, index, typed, entry, split, mergeNext = "merge_next" }
        }
        enum Value: Decodable {
            case text(String), number(Double)
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let text = try? value.decode(String.self) { self = .text(text) } else { self = .number(try value.decode(Double.self)) }
            }
        }
        let spans: [Span]
        let wordOptions: [String: [[Value]]]
        enum CodingKeys: String, CodingKey { case spans, wordOptions = "word_options" }
    }

    static let fixture = Result {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: #filePath)
            .deletingLastPathComponent().appending(path: "Fixtures/candidates_parity.json")))
    }

    @Test func everySpanCaseMatchesTheReference() throws {
        let list = try CandidateListTests.list.get()
        for c in try Self.fixture.get().spans {
            let entry = list.spanEntry(words: c.words, index: c.index, typedOf: { c.typed[$0] })
            var expected: CandidateList.SpanEntry?
            if let e = c.entry, case let .text(text) = e[0], case let .number(step) = e[1] {
                expected = CandidateList.SpanEntry(text: text, step: Int(step))
            }
            #expect(entry == expected, "entry for \(c.words) at \(c.index)")
            #expect(list.splitOptions(shown: c.words[c.index], typedWords: c.typed[c.index], keep: 3) == c.split,
                    "splits of \(c.words[c.index])")
            if c.index + 1 < c.words.count {
                let merged = list.mergeOptions(first: c.words[c.index], second: c.words[c.index + 1],
                                               typedWords: c.typed[c.index] + c.typed[c.index + 1], keep: 3)
                #expect(merged == c.mergeNext, "merges of \(c.words)")
            }
        }
    }

    @Test func wordOptionsMatchTheReference() throws {
        let list = try CandidateListTests.list.get()
        for (typed, expected) in try Self.fixture.get().wordOptions {
            let mine = list.wordOptions(typed)
            #expect(mine.map(\.0) == expected.compactMap { if case let .text(t) = $0[0] { t } else { nil } }, "options of \(typed)")
            for (a, b) in zip(mine, expected) {
                if case let .number(score) = b[1] { #expect(abs(a.1 - score) < 1e-6, "score of \(a.0)") }
            }
        }
    }

    @Test func wordsAlwaysWrittenApartAreNeverMerged() {
        #expect(!CandidateList.wantsMerge(first: "عم", second: "تعمل", typedFirst: ["3am"], typedSecond: ["ta3mel"]))
        #expect(CandidateList.wantsMerge(first: "ع", second: "سطح", typedFirst: ["3a"], typedSecond: ["sate7"]))
        #expect(!CandidateList.wantsSplit(shown: "كيفك", typedWords: ["kifak"]))  // one typed word: no split
    }
}

// MARK: The composer

private func type(_ text: String, into composer: inout Composer) {
    for character in text { _ = composer.handle(.text(String(character))) }
}

/// A composer whose conversion is `converted`, one typed word per shown word, a list of `list` for every word and
/// `entry` as the merge/split entry on word `on`.
private func composer(_ converted: String, list: [String], entry: CandidateList.SpanEntry, on: Int,
                      recorded: @escaping @Sendable (Correction) -> Void = { _ in }) -> Composer {
    let suggester = Suggester(candidates: { _, _ in list },
                              align: { latin, shown in latin.count == shown.count ? latin.indices.map { $0..<($0 + 1) } : [] },
                              record: recorded,
                              spanEntry: { _, index, _ in index == on ? entry : nil })
    return Composer(convert: { _ in converted }, suggester: suggester)
}

@Test func aMergeWithThePreviousWordReplacesBothWords() {
    var c = composer("ع سطح كبير", list: ["سطوح"], entry: .init(text: "عالسطح", step: -1), on: 1)
    type("3a sate7 kbir", into: &c)
    _ = c.handle(.arrowUp)                       // on the last word, كبير
    #expect(c.handle(.arrowRight) == .suggest(marked: "ع سطح كبير", selected: 2..<5, candidates: ["سطوح", "عالسطح"],
                                              replacingLength: nil))
    // Moving to the entry shows the merged word, selected, in place of both words.
    #expect(c.handle(.arrowDown) == .suggest(marked: "ع سطوح كبير", selected: 2..<6, candidates: ["سطوح", "عالسطح"],
                                             replacingLength: nil))
    #expect(c.handle(.arrowDown) == .suggest(marked: "عالسطح كبير", selected: 0..<6, candidates: ["سطوح", "عالسطح"],
                                             replacingLength: nil))
    #expect(c.handle(.enter) == .commit(DirectionMarks.marked("عالسطح كبير")))
}

@Test func aMergeWithTheNextWordByNumber() {
    var c = composer("رح شوف", list: [], entry: .init(text: "حشوف", step: 1), on: 0)
    type("7a shof", into: &c)
    _ = c.handle(.arrowUp)
    _ = c.handle(.arrowRight)                    // from شوف to رح
    #expect(c.currentCandidates == ["حشوف"])
    #expect(c.handle(.text("1")) == .commit(DirectionMarks.marked("حشوف")))
}

@Test func aSplitPutsTheSpaceBackAndRecordsNothing() {
    final class Log: @unchecked Sendable { var corrections: [Correction] = [] }
    let log = Log()
    var c = composer("وانا", list: ["وانه"], entry: .init(text: "و انا", step: 0), on: 0,
                     recorded: { log.corrections.append($0) })
    type("w", into: &c)
    #expect(c.handle(.arrowUp) == .suggest(marked: "وانا", selected: 0..<4, candidates: ["وانه", "و انا"],
                                           replacingLength: nil))
    #expect(c.handle(.text("2")) == .commit(DirectionMarks.marked("و انا")))
    #expect(log.corrections.isEmpty)             // not a spelling of one typed word: not learned
}

@Test func theEntryTakesTheLastArabicPlaceAndTheTypedWordStaysLast() {
    let full = ["ا", "ب", "ت", "ث", "ج", "ح", "w"]  // six spellings, then the typed word
    var c = composer("وانا", list: full, entry: .init(text: "و انا", step: 0), on: 0)
    type("w", into: &c)
    _ = c.handle(.arrowUp)
    #expect(c.currentCandidates == ["ا", "ب", "ت", "ث", "ج", "و انا", "w"])
}
