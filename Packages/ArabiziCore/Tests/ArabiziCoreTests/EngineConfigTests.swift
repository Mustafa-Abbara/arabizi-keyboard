import Foundation
import Testing
@testable import ArabiziCore

let configDirectory = repoRoot.appending(path: "config")
let engineData = try! Data(contentsOf: configDirectory.appending(path: EngineConfig.fileName))  // swiftlint:disable:this force_try
let modelsData = try! Data(contentsOf: configDirectory.appending(path: EngineConfig.modelsFileName))  // swiftlint:disable:this force_try

/// config/engine.json with some settings changed.
func engine(_ changes: [String: Any]) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: engineData) as? [String: Any])
    json.merge(changes) { _, new in new }
    return try JSONSerialization.data(withJSONObject: json)
}

/// config/models.json plus a fine-tuned model with a prompt, as P4 will add it.
let modelsWithFineTuned = try! JSONSerialization.data(withJSONObject: [  // swiftlint:disable:this force_try
    "models": [["id": "arabizi-test-v1", "file": "arabizi-test-v1-Q4_K_M.gguf", "sha256": String(repeating: "AB", count: 32),
                "prompt": ["prefix": "<|im_start|>user\n", "suffix": "<|im_end|>\n<|im_start|>assistant\n"]]],
])

@Test func committedConfigLoads() throws {
    let config = try EngineConfig(configDirectory: configDirectory)
    let model = try #require(config.model)  // the fine-tuned Llama v2 is switched on (ADR 0022)
    #expect(model.id == "arabizi-llama3.2-1b-v2" && model.file == "arabizi-llama3.2-1b-v2-Q4_K_M.gguf")
    #expect(model.promptPrefix.hasPrefix("<|begin_of_text|>") && model.promptSuffix.hasSuffix("assistant<|end_header_id|>\n\n"))
    #expect(config.deadlineMs == 1500 && config.contextLength > config.maxOutputTokens)
    #expect(config.outputChecks == OutputChecks(minWordRatio: 0.5, maxWordRatio: 2.0, wordSlack: 1))
}

@Test func fineTunedModelIsResolvedFromTheManifest() throws {
    let config = try EngineConfig(engine: engine(["model": "arabizi-test-v1", "features": ["use_model": true]]),
                                  models: modelsWithFineTuned)
    let model = try #require(config.model)
    #expect(model.file == "arabizi-test-v1-Q4_K_M.gguf" && model.sha256 == String(repeating: "ab", count: 32))
    #expect(model.promptSuffix.hasSuffix("assistant\n"))
}

@Test func modelSwitchedOffIsNotUsedButStillChecked() throws {
    let off = try EngineConfig(engine: engine(["model": "arabizi-test-v1", "features": ["use_model": false]]),
                               models: modelsWithFineTuned)
    #expect(off.model == nil)
    #expect(throws: EngineConfig.InvalidError.self) {
        try EngineConfig(engine: engine(["model": "arabizi-typo-v1", "features": ["use_model": false]]),
                         models: modelsWithFineTuned)
    }
}

@Test(arguments: [
    #"{"version": 2}"#,
    #"{"deadline_ms": 0}"#,
    #"{"deadline_ms": 60000}"#,
    #"{"max_input_chars": 0}"#,
    #"{"max_output_tokens": 600}"#,  // more than context_length
    #"{"output_checks": {"min_word_ratio": 1.5, "max_word_ratio": 2.0, "word_slack": 1}}"#,
    #"{"output_checks": {"min_word_ratio": 0.5, "max_word_ratio": 2.0, "word_slack": -1}}"#,
    #"{"model": null, "features": {"use_model": true}}"#,  // on, but no model
    #"{"model": "qwen3-0.6b", "features": {"use_model": true}}"#,  // a base model: no prompt
    #"{"model": "not-in-the-manifest", "features": {"use_model": true}}"#,
])
func badSettingsAreRejected(changes: String) throws {
    let parsed = try #require(JSONSerialization.jsonObject(with: Data(changes.utf8)) as? [String: Any])
    let data = try engine(parsed)
    #expect(throws: EngineConfig.InvalidError.self) { try EngineConfig(engine: data, models: modelsData) }
}
