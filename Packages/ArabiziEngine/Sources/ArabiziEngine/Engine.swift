import ArabiziContracts
import ArabiziCore
import ArabiziLLM
import CryptoKit
import Foundation

/// The conversion engine (roadmap P5): one request in, one response out, never an error.
///
/// 1. Text with no Latin letter is returned unchanged (`passthrough`).
/// 2. No usable model (switched off, file missing, wrong SHA-256, failed to load) or input longer than
///    `max_input_chars`: the rule converter answers (`fallbackModelUnavailable`).
/// 3. Otherwise links, emails, mentions, emoji and standalone numbers become placeholders (ProtectedSpans), the
///    fine-tuned model converts the masked text with its saved prompt and the request's deadline, and its answer is
///    cleaned (first line, no wrapping quotes) and checked (OutputChecks). A finished, passing answer is the result
///    (`model`); a deadline gives the rules (`fallbackTimeout`); a token limit or a failed check gives the rules
///    (`fallbackCheckFailed`).
///
/// Never logs the text it converts.
public final class Engine: @unchecked Sendable {  // immutable after init; the generator serialises its own calls
    public enum ModelState: Equatable, Sendable {
        /// No model configured (`use_model` false): rules only.
        case off
        case ready(id: String)
        /// A model is configured but cannot be used; the reason is safe to log (no user text).
        case unavailable(id: String, reason: String)
    }

    public let config: EngineConfig
    public let modelState: ModelState
    private let rules: RuleConverter
    private let generator: (any TextGenerator)?
    private let template: PromptTemplate?

    /// For tests and hosts that build the parts themselves.
    public init(config: EngineConfig, rules: RuleConverter, generator: (any TextGenerator)?,
                template: PromptTemplate?, modelState: ModelState) {
        self.config = config
        self.rules = rules
        self.generator = generator
        self.template = template
        self.modelState = modelState
    }

    /// Loads config/engine.json + config/models.json, the rule files and (when switched on) the model, whose SHA-256
    /// is checked first. A model problem never stops the engine: it runs on the rules and says why in `modelState`.
    public static func load(configDirectory: URL, rulesDirectory: URL, modelsDirectory: URL,
                            verifyModelHash: Bool = true) throws -> Engine {
        try load(config: EngineConfig(configDirectory: configDirectory), rulesDirectory: rulesDirectory,
                 modelsDirectory: modelsDirectory, verifyModelHash: verifyModelHash)
    }

    /// The same with a config already built (arabizi-cli's --model / --no-model overrides).
    public static func load(config: EngineConfig, rulesDirectory: URL, modelsDirectory: URL,
                            verifyModelHash: Bool = true) throws -> Engine {
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        guard let model = config.model else {
            return Engine(config: config, rules: rules, generator: nil, template: nil, modelState: .off)
        }
        let path = modelsDirectory.appending(path: model.file)
        func unavailable(_ reason: String) -> Engine {
            Engine(config: config, rules: rules, generator: nil, template: nil,
                   modelState: .unavailable(id: model.id, reason: reason))
        }
        guard FileManager.default.fileExists(atPath: path.path) else {
            return unavailable("model file not found: \(model.file)")
        }
        if verifyModelHash {
            guard let digest = try? sha256(of: path), digest == model.sha256 else {
                return unavailable("model file does not match its SHA-256 in config/models.json")
            }
        }
        var settings = LlamaModel.Settings()
        settings.contextLength = Int32(config.contextLength)
        do {
            let generator = try LlamaModel(path: path.path, settings: settings)
            return Engine(config: config, rules: rules, generator: generator,
                          template: PromptTemplate(prefix: model.promptPrefix, suffix: model.promptSuffix),
                          modelState: .ready(id: model.id))
        } catch {
            return unavailable("model failed to load: \(error)")
        }
    }

    public func convert(_ request: ConvertRequest) -> ConvertResponse {
        convertExplained(request).response
    }

    /// The response and, for a fallback, why: a short reason with counts only, never user text (for logs and
    /// arabizi-cli --explain).
    public func convertExplained(_ request: ConvertRequest) -> (response: ConvertResponse, reason: String?) {
        let started = ContinuousClock.now
        var reason: String?
        func respond(_ text: String, _ outcome: Outcome) -> (response: ConvertResponse, reason: String?) {
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            return (ConvertResponse(id: request.id, text: text, outcome: outcome, latencyMs: ms), reason)
        }
        let text = request.text
        guard text.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) else {
            return respond(text, .passthrough)
        }
        guard let generator, let template else {
            reason = "no model"
            return respond(rules.convert(text), .fallbackModelUnavailable)
        }
        guard text.count <= config.maxInputChars else {
            reason = "input longer than max_input_chars"
            return respond(rules.convert(text), .fallbackModelUnavailable)
        }
        let protected = ProtectedSpans.protect(text)
        let words = protected.masked.split(whereSeparator: \.isWhitespace).count
        let limit = min(10 * words + 32, config.maxOutputTokens)
        let generation: Generation
        do {
            generation = try generator.generate(template.render(protected.masked), maxTokens: limit,
                                                timeout: .milliseconds(request.deadlineMs))
        } catch {
            reason = "generation error: \(error)"
            return respond(rules.convert(text), .fallbackModelUnavailable)
        }
        switch generation.stop {
        case .deadline:
            reason = "deadline after \(generation.generatedTokens) tokens"
            return respond(rules.convert(text), .fallbackTimeout)
        case .maxTokens:
            reason = "token limit \(limit)"
            return respond(rules.convert(text), .fallbackCheckFailed)
        case .endOfTurn:
            switch config.outputChecks.check(Self.clean(generation.text), for: protected) {
            case .success(let converted):
                return respond(converted, .model)
            case .failure(let failure):
                reason = Self.describe(failure)
                return respond(rules.convert(text), .fallbackCheckFailed)
            }
        }
    }

    /// The model's answer as the evaluation harness reads it (eval `b1.clean`): `<think>` blocks removed, the first
    /// non-empty line, without wrapping quotes.
    public static func clean(_ text: String) -> String {
        let withoutThinking = text.replacing(/(?s)<think>.*?(?:<\/think>|$)/, with: "")
        let line = withoutThinking.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»")).trimmingCharacters(in: .whitespaces)
    }

    /// A check failure without the words themselves.
    static func describe(_ failure: OutputChecks.Failure) -> String {
        switch failure {
        case .empty: "check: empty"
        case .placeholders: "check: placeholders"
        case .newLatin(let words): "check: new Latin words (\(words.count))"
        case .wordCount(let output, let input): "check: word count \(output) for \(input) input words"
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 1 << 22), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
