import Foundation
import Testing
@testable import ArabiziLLM

/// A model from models/ (never committed): ARABIZI_TEST_MODEL, or the smallest pinned one. Tests that need it are
/// skipped when it is missing, as in CI, which has no model weights.
let testModelPath: String? = {
    let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let path = ProcessInfo.processInfo.environment["ARABIZI_TEST_MODEL"]
        ?? repoRoot.appending(path: "models/Qwen3-0.6B-Q4_K_M.gguf").path
    return FileManager.default.fileExists(atPath: path) ? path : nil
}()
let model: LlamaModel? = testModelPath.flatMap { try? LlamaModel(path: $0) }

// ChatML with Qwen3's empty think block, as the training tokenizer renders it with thinking off.
let template = PromptTemplate(
    prefix: "<|im_start|>system\nConvert this Lebanese Arabizi text to Arabic script.<|im_end|>\n<|im_start|>user\n",
    suffix: "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")

@Test func templateWrapsTheArabizi() {
    #expect(PromptTemplate(prefix: "<", suffix: ">").render("kifak") == "<kifak>")
}

@Test func missingModelFileThrows() {
    #expect(throws: LlamaError.modelNotFound("/nonexistent.gguf")) { try LlamaModel(path: "/nonexistent.gguf") }
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func generatesUntilTheEndOfTurn() throws {
    let result = try #require(model).generate(template.render("kifak, shu 3am ta3mel?"), timeout: .seconds(30))
    #expect(result.stop == .endOfTurn)
    #expect(!result.text.isEmpty && result.promptTokens > 0 && result.generatedTokens > 0)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func greedyGenerationIsRepeatable() throws {
    // Same prompt, same answer: the KV cache and sampler are reset between calls.
    let model = try #require(model)
    let first = try model.generate(template.render("bade ruh 3al beit"), timeout: .seconds(30))
    let second = try model.generate(template.render("bade ruh 3al beit"), timeout: .seconds(30))
    #expect(first.text == second.text)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func stopsAtTheTokenLimit() throws {
    let result = try #require(model).generate(template.render("kifak, shu 3am ta3mel?"), maxTokens: 2,
                                              timeout: .seconds(30))
    #expect(result.generatedTokens <= 2)
    #expect(result.stop != .deadline)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func stopsAtTheDeadline() throws {
    let result = try #require(model).generate(template.render("kifak, shu 3am ta3mel?"), timeout: .milliseconds(1))
    #expect(result.stop == .deadline)
    #expect(result.generatedTokens <= 1)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func wordGuessesAreRepeatableAndBestFirst() throws {
    let model = try #require(model)
    let prompt = template.render("shu 3am ta3mel?")
    let first = try model.wordGuesses(prompt, answerSoFar: "", count: 5, timeout: .seconds(30))
    let second = try model.wordGuesses(prompt, answerSoFar: "", count: 5, timeout: .seconds(30))
    // The second call reuses the cache the first left, and llama.cpp computes a lone token and a batch with
    // different kernels, so the scores move a little (up to ~0.1) and near-equal weak guesses may swap; the best
    // guess and most of the list stay. (Conversions always start from an empty cache, so they never change.)
    #expect(!first.isEmpty && first.first?.word == second.first?.word)
    #expect(Set(first.prefix(5).map(\.word)).intersection(second.prefix(5).map(\.word)).count >= 3)
    #expect(zip(first, first.dropFirst()).allSatisfy { $0.logProbability >= $1.logProbability })
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func aConversionIsTheSameBeforeAndAfterWordGuesses() throws {
    // Guesses reuse the cache the conversion left; a conversion always starts from an empty one.
    let model = try #require(model)
    let prompt = template.render("bade ruh 3al beit")
    let before = try model.generate(prompt, timeout: .seconds(30))
    _ = try model.wordGuesses(prompt, answerSoFar: String(before.text.split(separator: " ").first ?? ""), count: 5,
                              timeout: .seconds(30))
    _ = try model.wordGuesses(template.render("kifak"), answerSoFar: "", count: 3, timeout: .seconds(30))
    #expect(try model.generate(prompt, timeout: .seconds(30)).text == before.text)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func wordGuessesPastTheDeadlineAreEmpty() throws {
    let guesses = try #require(model).wordGuesses(template.render(String(repeating: "kifak ", count: 40)),
                                                  answerSoFar: "", count: 5, timeout: .milliseconds(1))
    #expect(guesses.isEmpty)
}

@Test(.enabled(if: model != nil, "no model file in models/"))
func promptLongerThanTheContextIsRejected() throws {
    let long = template.render(String(repeating: "kifak ", count: 600))
    #expect(throws: LlamaError.self) { try #require(model).generate(long, timeout: .seconds(30)) }
}

// The pinned instruction and incremental conversion (ADR 0037). One more model, shared by these tests: `pin` changes
// how every later prompt is decoded, so it cannot be the model above; each test runs alone on it (`onPinned`) and
// starts with `pin`, which also forgets the last conversion.
let pinnedModel: LlamaModel? = testModelPath.flatMap { try? LlamaModel(path: $0) }
private let pinnedLock = NSLock()

private func onPinned<T>(incremental: Bool, _ body: (LlamaModel) throws -> T) throws -> T {
    let model = try #require(pinnedModel)
    return try pinnedLock.withLock {
        try model.pin(template.prefix, incrementalSuffix: incremental ? template.suffix : nil)
        return try body(model)
    }
}

private func answer(_ model: LlamaModel, _ text: String, reuseLast: Bool = true) throws -> String {
    try model.generate(template.render(text), maxTokens: 24, timeout: .seconds(120), reuseLast: reuseLast).text
}

/// The answers to `texts`, converted one after the other from a fresh start.
private func typed(_ texts: [String], incremental: Bool = true) throws -> [String] {
    try onPinned(incremental: incremental) { model in try texts.map { try answer(model, $0) } }
}

@Test(.enabled(if: pinnedModel != nil, "no model file in models/"))
func withThePinnedInstructionAnAnswerDependsOnlyOnItsText() throws {
    try onPinned(incremental: false) { model in
        let first = try answer(model, "bade ruh 3al beit")
        #expect(!first.isEmpty)
        // The same after another text, after word guesses, and after a prompt without the instruction.
        _ = try answer(model, "kifak ya zalame shu akhbarak")
        #expect(try answer(model, "bade ruh 3al beit") == first)
        _ = try model.wordGuesses(template.render("kifak"), answerSoFar: "", count: 3, timeout: .seconds(120))
        #expect(try answer(model, "bade ruh 3al beit") == first)
        _ = try model.generate("marhaba", maxTokens: 4, timeout: .seconds(120))
        #expect(try answer(model, "bade ruh 3al beit") == first)
    }
}

@Test(.enabled(if: pinnedModel != nil, "no model file in models/"))
func aDeadlineWhileThePinnedInstructionIsDecodedIsRecoveredFrom() throws {
    try onPinned(incremental: false) { model in
        let prompt = template.render("bade ruh 3al beit")
        let whole = try answer(model, "bade ruh 3al beit")
        #expect(try model.generate(prompt, maxTokens: 24, timeout: .zero).stop == .deadline)
        #expect(try answer(model, "bade ruh 3al beit") == whole)
    }
}

// An answer made incrementally can differ by a word from the same text converted on its own (rounding), so these
// tests check what is exact.

@Test(.enabled(if: pinnedModel != nil, "no model file in models/"))
func incrementalConversionIsRepeatableAndLeavesOtherTextsAlone() throws {
    let typing = ["bade", "bade ruh", "bade ruh 3al", "bade ruh 3al beit"]
    let first = try typed(typing)
    #expect(first.allSatisfy { !$0.isEmpty })
    #expect(try typed(typing) == first)  // the same typing, the same answers
    // A text that does not continue the last one is converted on its own, whatever came before it.
    let other = "kifak ya zalame"
    let alone = try typed([other])
    #expect(try typed(typing + [other]).last == alone.last)
    // The same text again is not a draft of itself: it is converted on its own too.
    #expect(try typed([other, other]) == alone + alone)
}

@Test(.enabled(if: pinnedModel != nil, "no model file in models/"))
func aDeadlineLeavesNoDraftBehind() throws {
    let alone = try typed(["bade ruh 3al beit"])
    let after = try onPinned(incremental: true) { model in
        #expect(try model.generate(template.render("bade ruh"), maxTokens: 24, timeout: .zero).stop == .deadline)
        return try answer(model, "bade ruh 3al beit")
    }
    #expect([after] == alone)
}

@Test(.enabled(if: pinnedModel != nil, "no model file in models/"))
func aConversionToldNotToReuseTheLastOneIsTheSameAsOnItsOwn() throws {
    // "Faster preview" switched off: the text continues the last one, and is still converted on its own.
    let alone = try typed(["bade ruh 3al beit"], incremental: false)
    let off = try onPinned(incremental: true) { model in
        _ = try answer(model, "bade ruh 3al")
        return try answer(model, "bade ruh 3al beit", reuseLast: false)
    }
    #expect([off] == alone)
}

@Test func theMostLikelyTokenAndItsLogProbability() {
    var logits: [Float] = [0, 2, 1]
    let (token, logProbability) = logits.withUnsafeMutableBufferPointer {
        LlamaModel.top($0.baseAddress!, vocabularySize: 3)
    }
    #expect(token == 1)
    #expect(abs(logProbability - (2 - log(exp(0.0) + exp(2.0) + exp(1.0)))) < 1e-9)
}
