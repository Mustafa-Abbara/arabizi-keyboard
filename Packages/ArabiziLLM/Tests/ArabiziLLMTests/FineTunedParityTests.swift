import Foundation
import Testing
@testable import ArabiziLLM

/// The fine-tuned Llama (config/models.json `arabizi-llama3.2-1b-v1`) must see its prompt exactly as training did.
/// Its run file (train/runs/) holds a public sample generated at training time; the engine must reproduce it.
/// Skipped when the model file is not in models/ (never committed; not on CI).
struct FineTuned {
    static let id = "arabizi-llama3.2-1b-v1"
    static let sentence = "kifik ya sabiyye? shu hal jamal el yom?"  // a public validation row (run.json samples)

    let path: String
    let template: PromptTemplate
    let expected: String

    static let shared: FineTuned? = {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard let manifest = try? JSONSerialization.jsonObject(
                  with: Data(contentsOf: root.appending(path: "config/models.json"))) as? [String: Any],
              let entry = (manifest["models"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }),
              let file = entry["file"] as? String, let prompt = entry["prompt"] as? [String: String],
              let runPath = entry["run"] as? String,
              let run = try? JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: runPath)))
                  as? [String: Any],
              let sample = (run["public_samples"] as? [[String: String]])?.first(where: { $0["arabizi"] == sentence }),
              let output = sample["output"], let prefix = prompt["prefix"], let suffix = prompt["suffix"]
        else { return nil }
        let path = root.appending(path: "models/\(file)").path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return FineTuned(path: path, template: PromptTemplate(prefix: prefix, suffix: suffix), expected: output)
    }()
}

let fineTunedModel: LlamaModel? = FineTuned.shared.flatMap { try? LlamaModel(path: $0.path) }

@Test(.enabled(if: fineTunedModel != nil, "fine-tuned Llama not in models/"))
func fineTunedPromptStartsWithTwoBOSTokensLikeTraining() throws {
    let model = try #require(fineTunedModel)
    let tokens = try model.tokenize(try #require(FineTuned.shared).template.render(FineTuned.sentence))
    // The prompt text starts with <|begin_of_text|> and the tokenizer adds BOS: training saw both.
    #expect(Array(tokens.prefix(2)) == [model.bosToken, model.bosToken])
    #expect(tokens[2] != model.bosToken)
}

@Test(.enabled(if: fineTunedModel != nil, "fine-tuned Llama not in models/"))
func fineTunedReproducesItsTrainingSample() throws {
    let fineTuned = try #require(FineTuned.shared)
    let result = try #require(fineTunedModel).generate(fineTuned.template.render(FineTuned.sentence),
                                                      maxTokens: 64, timeout: .seconds(30))
    #expect(result.stop == .endOfTurn)
    #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == fineTuned.expected)
}
