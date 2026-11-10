import ArabiziContracts
import ArabiziCore
import ArabiziLLM
import Foundation
import Testing
@testable import ArabiziEngine

/// A stand-in model that can also guess words: answers from a script and records what it was asked.
final class GuessingModel: TextGenerator, WordGuessing, @unchecked Sendable {
    let guesses: @Sendable (String, String) throws -> [(word: String, logProbability: Double)]
    let delay: Duration
    private let lock = NSLock()
    private var _asked: [(prompt: String, before: String, count: Int)] = []
    var asked: [(prompt: String, before: String, count: Int)] { lock.withLock { _asked } }

    init(delay: Duration = .zero,
         _ guesses: @escaping @Sendable (String, String) throws -> [(word: String, logProbability: Double)]) {
        self.delay = delay
        self.guesses = guesses
    }

    func generate(_ prompt: String, maxTokens: Int, timeout: Duration) throws -> Generation { finished("") }

    func wordGuesses(_ prompt: String, answerSoFar: String, count: Int, timeout: Duration) throws
        -> [(word: String, logProbability: Double)] {
        lock.withLock { _asked.append((prompt, answerSoFar, count)) }
        if delay > .zero { Thread.sleep(forTimeInterval: Double(delay.components.attoseconds) / 1e18
                                          + Double(delay.components.seconds)) }
        return try guesses(prompt, answerSoFar)
    }
}

func guessEngine(_ model: (any TextGenerator)?) throws -> Engine {
    let config = try EngineConfig(configDirectory: configDirectory)
    return Engine(config: config, rules: rules, generator: model, template: model == nil ? nil : template,
                  modelState: model == nil ? .off : .ready(id: "scripted"))
}

@Suite struct WordGuessesTests {
    @Test func theModelsGuessesComeBackCleanAndBestFirst() throws {
        let model = GuessingModel { _, _ in
            [(" عم", -0.1), ("عَم", -0.2), ("عام", -1.5), ("ع-م", -2), ("lol", -2.5), ("عامل", -3)]
        }
        let response = try guessEngine(model).wordGuesses(WordGuessRequest(text: "shu 3am ta3mel", before: "شو",
                                                                           count: 3, deadlineMs: 400))
        #expect(response.outcome == .model)
        #expect(response.guesses.map(\.word) == ["عم", "عام", "عامل"])  // spaces and diacritics gone; non-words dropped
        #expect(response.guesses.allSatisfy { $0.logProbability <= 0 })
        #expect(model.asked.first?.prompt == "<P>shu 3am ta3mel</P>" && model.asked.first?.before == "شو")
    }

    @Test func maskedSpansAreMaskedInTheAnswerSoFarToo() throws {
        let model = GuessingModel { _, _ in [("دولار", -0.5)] }
        _ = try guessEngine(model).wordGuesses(WordGuessRequest(text: "b3at 100 dolar", before: "بعت 100",
                                                                deadlineMs: 400))
        #expect(model.asked.first?.prompt == "<P>b3at ⟦0⟧ dolar</P>")
        #expect(model.asked.first?.before == "بعت ⟦0⟧")
    }

    @Test func withoutAModelThereAreNoGuesses() throws {
        let response = try guessEngine(nil).wordGuesses(WordGuessRequest(text: "shu", before: "", deadlineMs: 400))
        #expect(response.outcome == .fallbackModelUnavailable && response.guesses.isEmpty)
    }

    @Test func aGeneratorThatCannotGuessGivesNoGuesses() throws {
        let response = try guessEngine(ScriptedModel { _ in finished("x") })
            .wordGuesses(WordGuessRequest(text: "shu", before: "", deadlineMs: 400))
        #expect(response.outcome == .fallbackModelUnavailable && response.guesses.isEmpty)
    }

    @Test func aSlowModelWithNothingToOfferIsATimeout() throws {
        let model = GuessingModel(delay: .milliseconds(30)) { _, _ in [] }
        let response = try guessEngine(model).wordGuesses(WordGuessRequest(text: "shu", before: "", deadlineMs: 10))
        #expect(response.outcome == .fallbackTimeout && response.guesses.isEmpty)
    }

    @Test func anErrorIsNeverThrown() throws {
        struct Broken: Error {}
        let model = GuessingModel { _, _ in throw Broken() }
        let (response, reason) = try guessEngine(model)
            .wordGuessesExplained(WordGuessRequest(text: "shu", before: "", deadlineMs: 400))
        #expect(response.outcome == .fallbackModelUnavailable && response.guesses.isEmpty)
        #expect(reason?.hasPrefix("guess error") == true)
    }

    // As the Python reference (model_guesses.py): anything but Arabic letters is trimmed from the ends (شوx -> شو);
    // a word with anything else inside is dropped.
    @Test(arguments: [("  عَمّ ", "عم"), ("الـبيت", "البيت"), ("«شو»", "شو"), ("ab", nil), ("ع م", "عم"),
                      ("شوx", "شو"), ("شxو", nil)] as [(String, String?)])
    func guessedWordsAreCleaned(raw: String, clean: String?) {
        #expect(Engine.arabicWord(raw) == clean)
    }
}
