import ArabiziContracts
import ArabiziCore
import ArabiziLLM
import Foundation
import Testing
@testable import ArabiziEngine

let repoRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let configDirectory = repoRoot.appending(path: "config")
let rulesDirectory = repoRoot.appending(path: "data/rules")
let modelsDirectory = repoRoot.appending(path: "models")
let rules = try! RuleConverter(rulesDirectory: rulesDirectory)  // swiftlint:disable:this force_try
let template = PromptTemplate(prefix: "<P>", suffix: "</P>")

/// A stand-in model: answers from a script and records the prompts it was given.
final class ScriptedModel: TextGenerator, @unchecked Sendable {
    let answer: @Sendable (String) throws -> Generation
    private let lock = NSLock()
    private var _prompts: [String] = []
    var prompts: [String] { lock.withLock { _prompts } }

    init(_ answer: @escaping @Sendable (String) throws -> Generation) { self.answer = answer }

    func generate(_ prompt: String, maxTokens: Int, timeout: Duration) throws -> Generation {
        lock.withLock { _prompts.append(prompt) }
        return try answer(prompt)
    }
}

func finished(_ text: String, _ stop: Generation.Stop = .endOfTurn) -> Generation {
    Generation(text: text, stop: stop, promptTokens: 10, generatedTokens: 5, elapsed: .milliseconds(5))
}

func engine(_ model: ScriptedModel?, maxInputChars: Int? = nil) throws -> Engine {
    var json = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: configDirectory.appending(path: "engine.json"))) as? [String: Any])
    if let maxInputChars { json["max_input_chars"] = maxInputChars }
    let config = try EngineConfig(engine: JSONSerialization.data(withJSONObject: json),
                                  models: Data(contentsOf: configDirectory.appending(path: "models.json")))
    return Engine(config: config, rules: rules, generator: model, template: model == nil ? nil : template,
                  modelState: model == nil ? .off : .ready(id: "scripted"))
}

func request(_ text: String) -> ConvertRequest { ConvertRequest(text: text, deadlineMs: 1500) }

@Test func textWithoutLatinLettersPassesThrough() throws {
    let model = ScriptedModel { _ in finished("x") }
    let response = try engine(model).convert(request("١٢٣ 😂"))
    #expect(response.outcome == .passthrough && response.text == "١٢٣ 😂")
    #expect(model.prompts.isEmpty)
}

@Test func withoutAModelTheRulesAnswer() throws {
    let response = try engine(nil).convert(request("kifak, shu 3am ta3mel?"))
    #expect(response.outcome == .fallbackModelUnavailable)
    #expect(response.text == rules.convert("kifak, shu 3am ta3mel?"))
}

@Test func theModelsCheckedAnswerIsUsed() throws {
    let model = ScriptedModel { _ in finished("\"كيفك، شو عم تعمل؟\"\nignored second line") }
    let response = try engine(model).convert(request("kifak, shu 3am ta3mel?"))
    #expect(response.outcome == .model && response.text == "كيفك، شو عم تعمل؟")
    #expect(model.prompts == ["<P>kifak, shu 3am ta3mel?</P>"])  // the saved prompt, nothing else around it
}

@Test func protectedSpansGoBackIntoTheAnswer() throws {
    let model = ScriptedModel { _ in finished("بعت ⟦0⟧ ع ⟦1⟧") }
    let response = try engine(model).convert(request("b3at 100$ 3a www.lau.edu"))
    #expect(model.prompts == ["<P>b3at ⟦0⟧ 3a ⟦1⟧</P>"])
    #expect(response.outcome == .model && response.text == "بعت 100$ ع www.lau.edu")
}

@Test(arguments: [
    (finished("كيفك", .deadline), Outcome.fallbackTimeout),
    (finished("كيفك كيفك كيفك", .maxTokens), .fallbackCheckFailed),
    (finished("كيفك how are you"), .fallbackCheckFailed),  // new Latin words
    (finished("بعت"), .fallbackCheckFailed),  // the placeholder was lost
])
func badAnswersGiveTheRules(answer: Generation, outcome: Outcome) throws {
    let model = ScriptedModel { _ in answer }
    let text = answer.text == "بعت" ? "b3at 100$" : "kifak"
    let (response, reason) = try engine(model).convertExplained(request(text))
    #expect(response.outcome == outcome && response.text == rules.convert(text))
    #expect(reason.map { !$0.contains("how") } ?? false)  // reasons never carry the text
}

@Test func aFailingModelGivesTheRules() throws {
    let model = ScriptedModel { _ in throw LlamaError.decodeFailed(-1) }
    let response = try engine(model).convert(request("kifak"))
    #expect(response.outcome == .fallbackModelUnavailable && response.text == rules.convert("kifak"))
}

@Test func tooLongInputSkipsTheModel() throws {
    let model = ScriptedModel { _ in finished("x") }
    let response = try engine(model, maxInputChars: 10).convert(request("kifak, shu 3am ta3mel?"))
    #expect(response.outcome == .fallbackModelUnavailable && model.prompts.isEmpty)
}

@Test(arguments: [
    ("<think>\nplanning\n</think>\n\nكيفك", "كيفك"),
    ("  \n«كيفك»  \nsecond", "كيفك"),
    ("", ""),
])
func cleanKeepsTheFirstLineWithoutQuotesOrThinking(raw: String, clean: String) {
    #expect(Engine.clean(raw) == clean)
}

@Test func aModelFileWithTheWrongHashIsNotUsed() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not a model".utf8).write(to: folder.appending(path: "arabizi-llama3.2-1b-v1-Q4_K_M.gguf"))
    var json = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: configDirectory.appending(path: "engine.json"))) as? [String: Any])
    json["model"] = "arabizi-llama3.2-1b-v1"
    json["features"] = ["use_model": true]
    let config = try EngineConfig(engine: JSONSerialization.data(withJSONObject: json),
                                  models: Data(contentsOf: configDirectory.appending(path: "models.json")))
    let loaded = try Engine.load(config: config, rulesDirectory: rulesDirectory, modelsDirectory: folder)
    guard case .unavailable(let id, let reason) = loaded.modelState else {
        Issue.record("expected unavailable, got \(loaded.modelState)")
        return
    }
    #expect(id == "arabizi-llama3.2-1b-v1" && reason.contains("SHA-256"))
    #expect(loaded.convert(request("kifak")).outcome == .fallbackModelUnavailable)
}

// MARK: - the real fine-tuned model (skipped when models/ does not have it, as on CI)

let realModelPresent = FileManager.default.fileExists(
    atPath: modelsDirectory.appending(path: "arabizi-llama3.2-1b-v1-Q4_K_M.gguf").path)

@Test(.enabled(if: realModelPresent, "fine-tuned Llama not in models/"))
func realEngineConvertsWithTheFineTunedModel() throws {
    var json = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: configDirectory.appending(path: "engine.json"))) as? [String: Any])
    json["model"] = "arabizi-llama3.2-1b-v1"
    json["features"] = ["use_model": true]
    let config = try EngineConfig(engine: JSONSerialization.data(withJSONObject: json),
                                  models: Data(contentsOf: configDirectory.appending(path: "models.json")))
    let real = try Engine.load(config: config, rulesDirectory: rulesDirectory, modelsDirectory: modelsDirectory,
                               verifyModelHash: false)  // the SHA-256 path is tested above; reading 0.8 GB is slow
    #expect(real.modelState == .ready(id: "arabizi-llama3.2-1b-v1"))
    // A public validation row; the run's training-time sample is the reference (FineTunedParityTests).
    let response = real.convert(ConvertRequest(text: "kifik ya sabiyye? shu hal jamal el yom?", deadlineMs: 10_000))
    #expect(response.outcome == .model)
    #expect(response.text == "كيفك يا سبيقة؟ شو هالجمال اليوم؟")
}
