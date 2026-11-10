import ArabiziContracts
import ArabiziCore
import ArabiziLLM
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto: CryptoKit's API on Windows (ADR 0032)
#endif
import Foundation

/// The conversion engine (roadmap P5): one request in, one response out, never an error.
///
/// 1. Text with no Latin letter, and text that is plain English (EnglishGuard, ADR 0031), is returned unchanged
///    (`passthrough`).
/// 2. No usable model (switched off, file missing, wrong SHA-256, failed to load) or input longer than
///    `max_input_chars`: the rule converter answers (`fallbackModelUnavailable`).
/// 3. Otherwise links, emails, mentions and standalone numbers become placeholders (ProtectedSpans), the
///    fine-tuned model converts the masked text with its saved prompt and the request's deadline, and its answer is
///    cleaned (first line, no wrapping quotes) and checked (OutputChecks). A finished, passing answer is the result
///    (`model`); a deadline gives the rules (`fallbackTimeout`); a token limit or a failed check gives the rules
///    (`fallbackCheckFailed`).
/// 4. When the only failure is Latin the input did not have, the answer is first repaired token by token (ADR 0023):
///    a mixed token such as `الvideo` is split (`ال video`, SPELLING.md 4), any other is replaced by the rule
///    conversion of the one input word it came from. A repaired answer that passes every check is the result
///    (`model`); otherwise the rules answer. A word that cannot be traced to one input word is replaced by the rule
///    conversion of the input word in the same position, when the answer has as many words as the input.
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
    /// The configured checks with the training data's kept-Latin words.
    private let checks: OutputChecks
    private let generator: (any TextGenerator)?
    /// The model's word-guess search (ADR 0036): the generator itself when it can search.
    private var guesser: (any WordGuessing)? { generator as? any WordGuessing }
    private let template: PromptTemplate?
    private let englishGuard: EnglishGuard?
    /// Chat abbreviations kept as typed, by the model and the rules (ADR 0035); nil without the file.
    private let abbreviations: ChatAbbreviations?
    /// Step 4 (token repair, ADR 0023); off only to measure what it adds (arabizi-cli --no-repair).
    public let repairTokens: Bool

    /// For tests and hosts that build the parts themselves.
    public init(config: EngineConfig, rules: RuleConverter, generator: (any TextGenerator)?,
                template: PromptTemplate?, modelState: ModelState, repairTokens: Bool = true,
                englishGuard: EnglishGuard? = nil, abbreviations: ChatAbbreviations? = nil) {
        self.config = config
        self.englishGuard = englishGuard
        self.abbreviations = abbreviations
        self.rules = rules
        var checks = config.outputChecks
        checks.keptLatin = rules.keptLatinWords
        self.checks = checks
        self.generator = generator
        self.template = template
        self.modelState = modelState
        self.repairTokens = repairTokens
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
                            verifyModelHash: Bool = true, repairTokens: Bool = true) throws -> Engine {
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        let english = EnglishGuard(rulesDirectory: rulesDirectory, rules: rules)
        let abbreviations = ChatAbbreviations(rulesDirectory: rulesDirectory)
        guard let model = config.model else {
            return Engine(config: config, rules: rules, generator: nil, template: nil, modelState: .off,
                          englishGuard: english, abbreviations: abbreviations)
        }
        let path = modelsDirectory.appending(path: model.file)
        func unavailable(_ reason: String) -> Engine {
            Engine(config: config, rules: rules, generator: nil, template: nil,
                   modelState: .unavailable(id: model.id, reason: reason), englishGuard: english, abbreviations: abbreviations)
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
                          modelState: .ready(id: model.id), repairTokens: repairTokens, englishGuard: english, abbreviations: abbreviations)
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
        func respond(_ text: String, _ outcome: Outcome, confidence: [Double]? = nil)
            -> (response: ConvertResponse, reason: String?) {
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            return (ConvertResponse(id: request.id, text: text, outcome: outcome, latencyMs: ms,
                                    wordConfidence: confidence), reason)
        }
        /// The model's confidence per word, when the answer still has as many words as the model wrote.
        func confidence(_ answer: String, _ generation: Generation) -> [Double]? {
            let words = answer.split(separator: " ", omittingEmptySubsequences: true).count
            guard words > 0, generation.wordConfidence.count == words else { return nil }
            return generation.wordConfidence.map { min(1, max(0, $0)) }
        }
        let text = request.text
        guard text.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) else {
            return respond(text, .passthrough)
        }
        if let englishGuard, englishGuard.isEnglish(text) {
            reason = "english"
            return respond(text, .passthrough)
        }
        guard let generator, let template else {
            reason = "no model"
            return respond(ruled(text), .fallbackModelUnavailable)
        }
        guard text.count <= config.maxInputChars else {
            reason = "input longer than max_input_chars"
            return respond(ruled(text), .fallbackModelUnavailable)
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
            return respond(ruled(text), .fallbackModelUnavailable)
        }
        switch generation.stop {
        case .deadline:
            reason = "deadline after \(generation.generatedTokens) tokens"
            return respond(ruled(text), .fallbackTimeout)
        case .maxTokens:
            reason = "token limit \(limit)"
            return respond(ruled(text), .fallbackCheckFailed)
        case .endOfTurn:
            switch checks.check(Self.clean(generation.text), for: protected) {
            case .success(let converted):
                let answer = kept(converted, typed: text)
                return respond(answer, .model, confidence: confidence(answer, generation))
            case .failure(.newLatin(let invented)):
                let answer = Self.clean(generation.text)
                if repairTokens, let (repaired, count) = Self.repair(answer, input: protected.masked, rules: rules),
                   case .success(let converted) = checks.check(repaired, for: protected) {
                    reason = "repaired: \(count) token(s)"
                    let final = kept(converted, typed: text)
                    return respond(final, .model, confidence: confidence(final, generation))
                }
                reason = Self.describe(.newLatin(invented))
                return respond(ruled(text), .fallbackCheckFailed)
            case .failure(let failure):
                reason = Self.describe(failure)
                return respond(ruled(text), .fallbackCheckFailed)
            }
        }
    }

    /// The model's other spellings for the word after `before` in its answer to `text` (ADR 0036): never an error.
    /// No model: no guesses (`fallbackModelUnavailable`); past the deadline: none (`fallbackTimeout`). The text is
    /// masked as for a conversion, and the spans it masked are masked in `before` too, so the model continues the
    /// answer it wrote. Only whole Arabic words are returned, without diacritics, best first.
    public func wordGuesses(_ request: WordGuessRequest) -> WordGuessResponse {
        wordGuessesExplained(request).response
    }

    /// The response and, when there are no guesses, why (counts only, never text).
    public func wordGuessesExplained(_ request: WordGuessRequest) -> (response: WordGuessResponse, reason: String?) {
        let started = ContinuousClock.now
        func respond(_ guesses: [WordGuessResponse.Guess], _ outcome: Outcome, _ reason: String? = nil)
            -> (response: WordGuessResponse, reason: String?) {
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            return (WordGuessResponse(id: request.id, guesses: guesses, outcome: outcome, latencyMs: ms), reason)
        }
        guard let guesser, let template else { return respond([], .fallbackModelUnavailable, "no model") }
        guard request.text.count <= config.maxInputChars else {
            return respond([], .fallbackModelUnavailable, "input longer than max_input_chars")
        }
        let protected = ProtectedSpans.protect(request.text)
        var before = request.before
        for (i, span) in protected.spans.enumerated() {
            if let range = before.range(of: span) { before.replaceSubrange(range, with: "⟦\(i)⟧") }
        }
        let raw: [(word: String, logProbability: Double)]
        do {
            raw = try guesser.wordGuesses(template.render(protected.masked), answerSoFar: before,
                                          count: request.count, timeout: .milliseconds(request.deadlineMs))
        } catch {
            return respond([], .fallbackModelUnavailable, "guess error: \(error)")
        }
        var guesses: [WordGuessResponse.Guess] = []
        for (word, logProbability) in raw {
            guard let clean = Self.arabicWord(word), !guesses.contains(where: { $0.word == clean }) else { continue }
            guesses.append(WordGuessResponse.Guess(word: clean, logProbability: min(0, logProbability)))
            if guesses.count == request.count { break }
        }
        let elapsed = ContinuousClock.now - started
        if guesses.isEmpty, elapsed >= .milliseconds(request.deadlineMs) {
            return respond([], .fallbackTimeout, "deadline")
        }
        return respond(guesses, .model, guesses.isEmpty ? "no Arabic word among the guesses" : nil)
    }

    /// A guessed word as the ↑ list takes it: no spaces, diacritics or tatweel, nothing but Arabic letters around
    /// it, and only Arabic letters inside; nil otherwise.
    static func arabicWord(_ raw: String) -> String? {
        let scalars = Array(raw.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) && $0.value != 0x0670
                                                         && $0.value != 0x0640 && !$0.properties.isWhitespace })
        let isLetter = { (s: Unicode.Scalar) in (0x0621...0x064A).contains(s.value) }
        guard let start = scalars.firstIndex(where: isLetter), let end = scalars.lastIndex(where: isLetter) else {
            return nil
        }
        let core = scalars[start...end]
        guard core.allSatisfy(isLetter) else { return nil }
        return String(String.UnicodeScalarView(core))
    }

    /// The rules' conversion, keeping chat abbreviations as typed.
    private func ruled(_ text: String) -> String {
        abbreviations?.convert(text, with: rules) ?? rules.convert(text)
    }

    /// The model's checked answer with the words that come from chat abbreviations written as typed.
    private func kept(_ answer: String, typed text: String) -> String {
        abbreviations?.restore(in: answer, typed: text, rules: rules) ?? answer
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

    /// Repairs the tokens of `answer` that hold Latin letters the input (`input`, masked) does not have as a word
    /// (OutputChecks' "new Latin" rule). nil when a token cannot be traced to one input word.
    ///
    /// - Arabic letters then Latin (`الvideo`, `عالschool`), where the Latin part is an input word, alone or glued to
    ///   an Arabizi prefix (`lvideo`): split with a space, as SPELLING.md 4 writes an English word with an Arabic prefix.
    /// - Anything else (`program` for `programe`, `قadir`): replaced by the rule conversion of the single input word
    ///   that contains its Latin letters.
    static func repair(_ answer: String, input: String, rules: RuleConverter) -> (String, Int)? {
        let inputWords = input.split(whereSeparator: \.isWhitespace).map { core(of: String($0)).core.lowercased() }
            .filter { !$0.contains("⟦") }
        let allowed = Set(inputWords), kept = rules.keptLatinWords
        let inputTokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        let answerTokens = answer.split(whereSeparator: \.isWhitespace).map(String.init)
        var repaired = 0
        var output: [String] = []
        for (position, word) in answerTokens.enumerated() {
            let (lead, core, trail) = core(of: word)
            guard core.unicodeScalars.contains(where: isLatinLetter),
                  !OutputChecks.isInputWord(core, allowed, keptLatin: kept) else {
                output.append(word)
                continue
            }
            let latin = String(String.UnicodeScalarView(core.unicodeScalars.filter { $0.isASCII })).lowercased()
            if let match = core.wholeMatch(of: /(\p{Arabic}+)([A-Za-z][A-Za-z0-9'-]*)/),
               OutputChecks.isInputWord(String(match.2), allowed, keptLatin: kept) {
                output.append("\(lead)\(match.1) \(match.2)\(trail)")
            } else {
                let sources = Set(inputWords.filter { !latin.isEmpty && $0.contains(latin) })
                if sources.count == 1, let source = sources.first {
                    output.append(lead + rules.convert(source) + trail)
                } else if answerTokens.count == inputTokens.count,
                          case let same = Self.core(of: inputTokens[position]).core.lowercased(),
                          !same.contains("⟦"), same.unicodeScalars.contains(where: isLatinLetter) {
                    output.append(lead + rules.convert(same) + trail)  // the input word in the same position
                } else {
                    return nil
                }
            }
            repaired += 1
        }
        return repaired > 0 ? (output.joined(separator: " "), repaired) : nil
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && scalar.properties.isAlphabetic
    }

    /// Leading punctuation, the word, trailing punctuation or emoji.
    private static func core(of word: String) -> (lead: String, core: String, trail: String) {
        let isWord = { (s: Unicode.Scalar) in s.properties.isAlphabetic || s.properties.numericType != nil }
        let scalars = Array(word.unicodeScalars)
        guard let start = scalars.firstIndex(where: isWord), let end = scalars.lastIndex(where: isWord) else {
            return ("", word, "")
        }
        func text(_ range: some RangeExpression<Int>) -> String {
            String(String.UnicodeScalarView(scalars[range]))
        }
        return (text(..<start), text(start...end), text((end + 1)...))
    }

    /// A check failure without the words themselves.
    static func describe(_ failure: OutputChecks.Failure) -> String {
        switch failure {
        case .empty: "check: empty"
        case .placeholders: "check: placeholders"
        case .newLatin(let words): "check: new Latin words (\(words.count))"
        case .wordCount(let output, let input): "check: word count \(output) for \(input) input words"
        case .emoji: "check: emoji changed"
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
