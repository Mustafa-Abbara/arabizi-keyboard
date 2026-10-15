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
func promptLongerThanTheContextIsRejected() throws {
    let long = template.render(String(repeating: "kifak ", count: 600))
    #expect(throws: LlamaError.self) { try #require(model).generate(long, timeout: .seconds(30)) }
}
