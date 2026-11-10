import Foundation
import Testing
@testable import ArabiziCore

/// Word suggestions v2 (ADR 0036): the Swift port against the Python reference, and its behaviour.
@Suite struct CandidateListTests {
    static let list = Result { try CandidateList(rulesDirectory: rulesDirectory) }

    struct Fixture: Decodable {
        struct Case: Decodable {
            let shown: String
            let typedWords: [String]
            let guesses: [[Guess]]
            let candidates: [String: [Double]]
            let order: [String]
            enum CodingKeys: String, CodingKey { case shown, typedWords = "typed_words", guesses, candidates, order }
        }
        enum Guess: Decodable {
            case word(String), score(Double)
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let word = try? value.decode(String.self) { self = .word(word) } else { self = .score(try value.decode(Double.self)) }
            }
        }
        let features: [String]
        let cases: [Case]
        let spellings: [String: [[Guess]]]
        let typing: [[Guess]]
        let units: [String: [String]]
    }

    static let fixture = Result {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(filePath: #filePath)
            .deletingLastPathComponent().appending(path: "Fixtures/candidates_parity.json")))
    }

    static func pair(_ guess: [Fixture.Guess]) -> (String, Double) {
        guard case let .word(word) = guess[0], case let .score(score) = guess[1] else { fatalError("bad fixture") }
        return (word, score)
    }

    @Test func theSignalsAreTheReferenceSignals() throws {
        #expect(try Self.fixture.get().features == CandidateList.features)
    }

    @Test func everyCaseHasTheReferenceCandidatesSignalsAndOrder() throws {
        let list = try Self.list.get()
        for c in try Self.fixture.get().cases {
            let pool = list.pool(shown: c.shown, typedWords: c.typedWords, guesses: c.guesses.map(Self.pair))
            let mine = Dictionary(uniqueKeysWithValues: pool.map { ($0.word, $0.signals) })
            #expect(Set(mine.keys) == Set(c.candidates.keys), "candidates for \(c.typedWords)")
            for (word, expected) in c.candidates {
                guard let signals = mine[word] else { continue }
                for (i, value) in expected.enumerated() where abs(signals[i] - value) > 1e-6 {
                    Issue.record("\(c.typedWords) \(word): \(CandidateList.features[i]) \(signals[i]) != \(value)")
                }
            }
            #expect(list.order(pool) == c.order, "order for \(c.typedWords)")
        }
    }

    @Test func spellingsTypingAndUnitsMatchTheReference() throws {
        let list = try Self.list.get()
        let fixture = try Self.fixture.get()
        for (typed, expected) in fixture.spellings {
            let mine = list.odds.spellings(typed, known: list.known)
            #expect(mine.map(\.0) == expected.map { Self.pair($0).0 }, "spellings of \(typed)")
            for (a, b) in zip(mine, expected.map(Self.pair)) { #expect(abs(a.1 - b.1) < 1e-6, "score of \(a.0)") }
        }
        for row in fixture.typing {
            guard case let .word(typed) = row[0], case let .word(word) = row[1], case let .score(lp) = row[2] else {
                Issue.record("bad typing row")
                continue
            }
            #expect(abs(list.odds.typingLogProbability(typed, word) - lp) < 1e-6, "\(typed) -> \(word)")
        }
        for (typed, units) in fixture.units { #expect(SpellingOdds.units(typed) == units) }
    }

    @Test func aMissingVowelIsOffered() throws {
        let list = try Self.list.get()
        #expect(list.odds.spellings("kfk", known: list.known).map(\.0).contains("كيفك"))
    }

    @Test func theListNeverOffersTheShownWordAndEndsWithTheTypedWord() throws {
        let list = try Self.list.get()
        let out = list.suggestions(shown: "سوانة", typedWords: ["sawene"], guesses: [("ثواني", -1.0), ("سوانة", -0.2)])
        #expect(!out.contains("سوانة"))
        #expect(out.count <= CandidateList.listLength && out.last == "sawene")
        #expect(out.contains("ثواني"))
    }

    @Test func aModelGuessTheTypingSupportsComesFirst() throws {
        let list = try Self.list.get()
        let out = list.suggestions(shown: "كفك", typedWords: ["kfk"], guesses: [("كيفك", -0.4), ("كفوك", -3)])
        #expect(out.first == "كيفك")
    }

    @Test func withoutARankerTheCandidatesKeepTheirBuiltOrder() throws {
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        let list = try CandidateList(rules: rules,
                                     lexicon: Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName)),
                                     odds: Data(contentsOf: rulesDirectory.appending(path: SpellingOdds.fileName)),
                                     ranker: nil)
        let pool = list.pool(shown: "فوتا", typedWords: ["fota"], guesses: [("فوطة", -1)])
        #expect(list.order(pool) == pool.map(\.word))
        #expect(pool.first?.word == "فوطة")  // the model's guesses come first in the pool
    }

    @Test func aRankerForOtherSignalsIsRefused() throws {
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        let ranker = Data(#"{"features": ["model_lp"], "mean": [0], "scale": [1], "weights": [1], "bias": 0}"#.utf8)
        #expect(throws: (any Error).self) {
            try CandidateList(rules: rules,
                              lexicon: Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName)),
                              odds: Data(contentsOf: rulesDirectory.appending(path: SpellingOdds.fileName)),
                              ranker: ranker)
        }
    }

    @Test func theUsersOwnFixComesFirstAndTheTypedWordLast() throws {
        let list = try Self.list.get()
        let past = [Correction(latin: "sawene", chosen: "ثواني", rejected: "سوانة", date: Date())]
        let out = list.personalized(for: "سوانة،", latin: "sawene,", past: past)
        #expect(out.first == "ثواني")
        #expect(out.last == "sawene" && out.count <= CandidateList.listLength)
        #expect(!out.contains("سوانة"))
    }

    @Test func theTypedWordKeepsItsPlaceWhenFixesFillTheList() throws {
        let list = try Self.list.get()
        let past = ["صوني", "سوني", "صواني", "سواني", "ساوني", "سويني", "صويني"].map {
            Correction(latin: "sawene", chosen: $0, rejected: "سوانة", date: Date())
        }
        let out = list.personalized(for: "سوانة", latin: "sawene", past: past)
        #expect(out.count == CandidateList.listLength && out.last == "sawene")
    }

    @Test func aRunOfTypedWordsIsOneTypedWord() throws {
        let out = try Self.list.get().personalized(for: "وانا", latin: "w ana", past: [])
        #expect(out.last == "w ana" && out.count <= CandidateList.listLength)
    }

    @Test func theListLoadsInTheBackground() throws {
        let loader = BackgroundCandidateList(rulesDirectory: rulesDirectory)
        let start = Date()
        while !loader.isFinished && Date().timeIntervalSince(start) < 30 { Thread.sleep(forTimeInterval: 0.05) }
        #expect(loader.list != nil)
    }

    @Test func withoutItsFilesTheFirstListStays() throws {
        let loader = BackgroundCandidateList(rulesDirectory: URL(filePath: "/nonexistent/rules"))
        let start = Date()
        while !loader.isFinished && Date().timeIntervalSince(start) < 30 { Thread.sleep(forTimeInterval: 0.05) }
        #expect(loader.isFinished && loader.list == nil)
    }
}
