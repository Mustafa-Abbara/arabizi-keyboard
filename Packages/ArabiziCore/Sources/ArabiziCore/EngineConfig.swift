import Foundation

/// config/engine.json, typed and checked when the engine starts (roadmap P5 step 8). A bad file stops the
/// start-up with a message saying which setting is wrong, instead of the engine running on a guess.
public struct EngineConfig: Equatable, Sendable {
    public struct InvalidError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// The model to run, resolved from config/models.json. nil: no model, every request gets the rule fallback.
    public struct Model: Equatable, Sendable {
        public let id: String
        public let file: String
        public let sha256: String
        /// The prompt around the Arabizi, exactly as rendered at training time (ADR 0017 #3).
        public let promptPrefix: String
        public let promptSuffix: String
    }

    public static let fileName = "engine.json"
    public static let modelsFileName = "models.json"

    public let model: Model?
    public let deadlineMs: Int
    public let maxInputChars: Int
    public let maxOutputTokens: Int
    public let contextLength: Int
    public let outputChecks: OutputChecks

    /// Reads engine.json and models.json from one folder (config/ in the repo).
    public init(configDirectory: URL) throws {
        try self.init(engine: Data(contentsOf: configDirectory.appending(path: Self.fileName)),
                      models: Data(contentsOf: configDirectory.appending(path: Self.modelsFileName)))
    }

    public init(engine engineData: Data, models modelsData: Data) throws {
        let file = try JSONDecoder().decode(EngineFile.self, from: engineData)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw InvalidError(description: "config/engine.json: \(message)") }
        }
        try require(file.version == 1, "unsupported version \(file.version)")
        try require((1...10_000).contains(file.deadlineMs), "deadline_ms must be 1–10000, not \(file.deadlineMs)")
        try require((1...10_000).contains(file.maxInputChars), "max_input_chars must be 1–10000")
        try require(file.maxOutputTokens >= 1, "max_output_tokens must be at least 1")
        try require(file.contextLength > file.maxOutputTokens, "context_length must be larger than max_output_tokens")
        let checks = file.outputChecks
        try require(checks.minWordRatio > 0 && checks.minWordRatio < 1 && checks.maxWordRatio > 1,
                    "output_checks needs 0 < min_word_ratio < 1 < max_word_ratio")
        try require(checks.wordSlack >= 0, "output_checks.word_slack cannot be negative")
        try require(!file.features.useModel || file.model != nil, "features.use_model is true but model is null")

        // A model id is checked even while use_model is false, so a typo shows up before it is switched on.
        if let id = file.model {
            let manifest = try JSONDecoder().decode(ModelsFile.self, from: modelsData)
            guard let entry = manifest.models.first(where: { $0.id == id }) else {
                throw InvalidError(description: "config/engine.json: model '\(id)' is not in config/models.json")
            }
            try require(entry.sha256.count == 64 && entry.sha256.allSatisfy(\.isHexDigit),
                        "model '\(id)' has no valid sha256 in config/models.json")
            guard let prompt = entry.prompt else {
                throw InvalidError(description: "config/engine.json: model '\(id)' has no prompt in config/models.json "
                                   + "(only fine-tuned models have one; ADR 0017)")
            }
            let resolved = Model(id: id, file: entry.file, sha256: entry.sha256.lowercased(),
                                 promptPrefix: prompt.prefix, promptSuffix: prompt.suffix)
            model = file.features.useModel ? resolved : nil
        } else {
            model = nil
        }
        deadlineMs = file.deadlineMs
        maxInputChars = file.maxInputChars
        maxOutputTokens = file.maxOutputTokens
        contextLength = file.contextLength
        outputChecks = OutputChecks(minWordRatio: checks.minWordRatio, maxWordRatio: checks.maxWordRatio,
                                    wordSlack: checks.wordSlack)
    }
}

// MARK: - file formats

struct EngineFile: Decodable {
    struct Features: Decodable {
        let useModel: Bool
        enum CodingKeys: String, CodingKey { case useModel = "use_model" }
    }
    struct Checks: Decodable {
        let minWordRatio: Double
        let maxWordRatio: Double
        let wordSlack: Int
        enum CodingKeys: String, CodingKey {
            case minWordRatio = "min_word_ratio", maxWordRatio = "max_word_ratio", wordSlack = "word_slack"
        }
    }
    let version: Int
    let model: String?
    let features: Features
    let deadlineMs: Int
    let maxInputChars: Int
    let maxOutputTokens: Int
    let contextLength: Int
    let outputChecks: Checks

    enum CodingKeys: String, CodingKey {
        case version, model, features
        case deadlineMs = "deadline_ms", maxInputChars = "max_input_chars", maxOutputTokens = "max_output_tokens"
        case contextLength = "context_length", outputChecks = "output_checks"
    }
}

/// The part of config/models.json the engine needs.
struct ModelsFile: Decodable {
    struct Entry: Decodable {
        struct Prompt: Decodable {
            let prefix: String
            let suffix: String
        }
        let id: String
        let file: String
        let sha256: String
        let prompt: Prompt?
    }
    let models: [Entry]
}
