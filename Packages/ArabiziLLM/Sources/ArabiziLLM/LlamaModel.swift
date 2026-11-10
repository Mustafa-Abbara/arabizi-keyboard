import Foundation
import llama

/// How a fine-tuned model's prompt looks around the Arabizi, exactly as rendered at training time (ADR 0015 #4).
/// It is stored, not built here: the XCFramework has no Jinja templates, and llama.cpp's built-in guesses do not
/// add Qwen3's empty <think> block (ADR 0017 #3).
public struct PromptTemplate: Codable, Equatable, Sendable {
    public let prefix: String
    public let suffix: String

    public init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public func render(_ arabizi: String) -> String { prefix + arabizi + suffix }
}

/// The result of one generation. Only `.endOfTurn` is a finished answer; the engine treats the others as
/// failures and uses the rule fallback.
public struct Generation: Equatable, Sendable {
    public enum Stop: Equatable, Sendable {
        /// The model ended its turn: a complete answer.
        case endOfTurn
        /// The token limit was reached before the end of the turn.
        case maxTokens
        /// The deadline passed: checked after every token, and during the prompt through llama.cpp's abort
        /// callback where the backend honours it (the CPU backend does; a Metal prompt decode may run to the end).
        case deadline
    }

    public let text: String
    public let stop: Stop
    public let promptTokens: Int
    public let generatedTokens: Int
    public let elapsed: Duration

    public init(text: String, stop: Stop, promptTokens: Int, generatedTokens: Int, elapsed: Duration) {
        self.text = text
        self.stop = stop
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.elapsed = elapsed
    }
}

/// Something that turns a rendered prompt into text: the real `LlamaModel`, or a stand-in in tests of the engine.
public protocol TextGenerator: Sendable {
    func generate(_ prompt: String, maxTokens: Int, timeout: Duration) throws -> Generation
}

/// The model's other ways to write one word of its answer (ADR 0036, the up-arrow list's first source).
public protocol WordGuessing: Sendable {
    /// Up to `count` words the model would write after `answerSoFar` (its own answer, up to the word being fixed),
    /// best first, with their log-probabilities; empty when the deadline passes first.
    func wordGuesses(_ prompt: String, answerSoFar: String, count: Int, timeout: Duration) throws
        -> [(word: String, logProbability: Double)]
}

public enum LlamaError: Error, Equatable {
    case modelNotFound(String)
    case loadFailed(String)
    case contextFailed
    case tokenizeFailed
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(Int32)
    /// The model was freed (at process exit).
    case modelClosed
}

/// One GGUF model loaded once and kept in memory ("warm"), generating greedily with a hard deadline
/// (roadmap P5 step 4, ADR 0017). Uses only llama.cpp's C API. One generation runs at a time; other calls wait.
/// Never logs prompt or output text, and llama.cpp's own logging is switched off.
public final class LlamaModel: TextGenerator, WordGuessing, @unchecked Sendable {  // all mutable state is behind `lock`
    public struct Settings: Sendable {
        /// Prompt plus answer, in tokens. A keyboard message is short; 512 keeps the KV cache small on 8 GB.
        public var contextLength: Int32 = 512
        /// Layers on the GPU (Metal); a large number means all of them.
        public var gpuLayers: Int32 = 999
        /// CPU threads for generation and the prompt; nil keeps llama.cpp's default. On Windows the model runs on the
        /// CPU, so it gets one thread per core (half the logical processors), not llama.cpp's 4.
        public var threads: Int32? = {
            #if os(Windows)
            return Int32(max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
            #else
            return nil
            #endif
        }()

        /// Sequences decoded together (the word-guess branches, ADR 0036). The cache is unified, so they share the
        /// prompt's cells and one conversion still has the whole context.
        public var sequences: Int32 = 16

        public init() {}
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private let contextLength: Int
    private let sequences: Int
    /// The tokens sequence 0 of the cache holds, so the next prompt decodes only what differs (behind `lock`).
    private var cached: [llama_token] = []
    private let lock = NSLock()
    private var freed = false
    /// Uptime in nanoseconds after which llama_decode aborts; read by the C abort callback.
    private let abortAt = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)

    private static let backend: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    public init(path: String, settings: Settings = Settings()) throws {
        guard FileManager.default.fileExists(atPath: path) else { throw LlamaError.modelNotFound(path) }
        _ = Self.backend
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = settings.gpuLayers
        guard let model = llama_model_load_from_file(path, modelParams) else { throw LlamaError.loadFailed(path) }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(settings.contextLength)
        contextParams.n_batch = UInt32(settings.contextLength)  // the whole prompt in one decode call
        contextParams.n_seq_max = UInt32(max(1, settings.sequences))
        contextParams.kv_unified = true
        if let threads = settings.threads {
            contextParams.n_threads = threads
            contextParams.n_threads_batch = threads
        }
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaError.contextFailed
        }
        self.model = model
        self.context = context
        vocab = llama_model_get_vocab(model)
        sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        contextLength = Int(settings.contextLength)
        sequences = Int(max(1, settings.sequences))
        abortAt.initialize(to: .max)
        llama_set_abort_callback(context, { data in
            guard let data else { return false }
            return DispatchTime.now().uptimeNanoseconds >= data.load(as: UInt64.self)
        }, UnsafeMutableRawPointer(abortAt))
        ExitCleanup.register(self)
    }

    deinit {
        ExitCleanup.unregister(self)
        freeResources()
        abortAt.deallocate()
    }

    /// Free the model and context once; after this, `generate` throws. Waits for a running generation.
    fileprivate func freeResources() {
        lock.lock()
        defer { lock.unlock() }
        guard !freed else { return }
        freed = true
        llama_sampler_free(sampler)
        llama_free(context)
        llama_model_free(model)
    }

    /// Generate the answer to `prompt` (already rendered with the model's `PromptTemplate`), greedily, stopping at
    /// the end of the turn, after `maxTokens`, or when `timeout` has passed since the call.
    public func generate(_ prompt: String, maxTokens: Int = 128, timeout: Duration) throws -> Generation {
        lock.lock()
        defer { lock.unlock() }
        guard !freed else { throw LlamaError.modelClosed }
        let start = DispatchTime.now().uptimeNanoseconds
        let timeoutNanos = UInt64(max(0, timeout.components.seconds)) * 1_000_000_000
            + UInt64(max(0, timeout.components.attoseconds / 1_000_000_000))
        let deadline = start &+ timeoutNanos
        abortAt.pointee = deadline
        defer { abortAt.pointee = .max }
        func elapsed() -> Duration { .nanoseconds(Int64(DispatchTime.now().uptimeNanoseconds - start)) }

        llama_sampler_reset(sampler)
        // A conversion starts from an empty cache, exactly as before word guesses existed (reusing part of it
        // changes the arithmetic, and so a few greedy answers); it leaves its prompt and answer for the guesses.
        llama_memory_clear(llama_get_memory(context), true)
        cached = []
        let prompt = try tokenize(prompt)
        let promptTokens = prompt.count
        guard prompt.count + maxTokens <= contextLength else {
            throw LlamaError.promptTooLong(tokens: prompt.count, limit: contextLength - maxTokens)
        }
        var output: [UInt8] = []
        var generated = 0
        var stop = Generation.Stop.maxTokens
        var tokens: [llama_token] = []
        while generated < maxTokens {
            // The prompt goes through `prefill` (it reuses what the cache already holds); then one token at a time.
            let status = tokens.isEmpty ? prefill(prompt) : decodeContinuing(tokens)
            if status == 2 {  // aborted by the deadline callback
                stop = .deadline
                break
            }
            guard status == 0 else { throw LlamaError.decodeFailed(status) }
            let next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) {
                stop = .endOfTurn
                break
            }
            output += piece(next)
            generated += 1
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                stop = .deadline
                break
            }
            tokens = [next]
        }
        // Pieces can split a multi-byte character; the bytes are decoded once, at the end.
        return Generation(text: String(decoding: output, as: UTF8.self), stop: stop,
                          promptTokens: promptTokens, generatedTokens: generated, elapsed: elapsed())
    }

    /// The model's other ways to write the word after `answerSoFar` (ADR 0036): a beam search over its next tokens,
    /// the prompt and the answer so far decoded once, then one decode per step for every branch together (each
    /// branch is a sequence that shares the prompt's cache cells). A word ends at a token that starts with a space
    /// or a new line, or at the end of the turn. Returns raw words (as the model wrote them); the caller cleans them.
    public func wordGuesses(_ prompt: String, answerSoFar: String, count: Int, timeout: Duration) throws
        -> [(word: String, logProbability: Double)] {
        lock.lock()
        defer { lock.unlock() }
        guard !freed else { throw LlamaError.modelClosed }
        let width = max(1, min(count, (sequences - 1) / 2)), depth = 6
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start &+ UInt64(max(0, timeout.components.seconds)) * 1_000_000_000
            &+ UInt64(max(0, timeout.components.attoseconds / 1_000_000_000))
        abortAt.pointee = deadline
        defer { abortAt.pointee = .max }
        let memory = llama_get_memory(context)
        var tokens = try tokenize(prompt)
        if !answerSoFar.isEmpty { tokens += try tokenize(answerSoFar, special: false) }
        guard tokens.count + depth + 1 <= contextLength else {
            throw LlamaError.promptTooLong(tokens: tokens.count, limit: contextLength - depth - 1)
        }
        let status = prefill(tokens)  // usually only the answer so far: the conversion left the prompt in the cache
        defer { for s in 1..<sequences { _ = llama_memory_seq_rm(memory, llama_seq_id(s), -1, -1) } }
        if status == 2 { return [] }
        guard status == 0 else { throw LlamaError.decodeFailed(status) }
        let prefixLength = Int32(tokens.count)
        let vocabSize = Int(llama_vocab_n_tokens(vocab))
        let needsSpace = !answerSoFar.isEmpty

        struct Beam {
            var logProbability: Double
            var tokens: [llama_token]
            var sequence: llama_seq_id
            var row: Int32
        }
        // Sequence 0 holds the prompt; branches use 1...width and width+1...2*width in turns.
        var beams = [Beam(logProbability: 0, tokens: [], sequence: 0, row: -1)]
        var done: [String: Double] = [:]
        var batch = llama_batch_init(Int32(width), 0, 1)
        defer { llama_batch_free(batch) }
        for step in 0..<depth {
            var grown: [Beam] = []
            for beam in beams {
                guard let logits = llama_get_logits_ith(context, beam.row) else { continue }
                for (token, logProbability) in Self.best(logits, vocabularySize: vocabSize, count: width * 2) {
                    let piece = self.piece(token)
                    let startsWord = piece.first == 0x20 || piece.first == 0x0A
                    if llama_vocab_is_eog(vocab, token) || (!beam.tokens.isEmpty && startsWord) {
                        if !beam.tokens.isEmpty {
                            let word = text(of: beam.tokens)
                            if done[word].map({ $0 < beam.logProbability }) ?? true { done[word] = beam.logProbability }
                        }
                        continue
                    }
                    if beam.tokens.isEmpty && needsSpace && !startsWord { continue }  // the next word starts here
                    grown.append(Beam(logProbability: beam.logProbability + logProbability,
                                      tokens: beam.tokens + [token], sequence: beam.sequence, row: -1))
                }
            }
            beams = Array(grown.sorted { $0.logProbability > $1.logProbability }.prefix(width))
            if beams.isEmpty || DispatchTime.now().uptimeNanoseconds >= deadline { break }
            // A branch's score only falls as it grows: once `count` words are done and the best open branch is
            // already below the weakest of them, no branch can still make the list. Most words end in 1-3 tokens.
            let finished = done.values.sorted(by: >)
            if finished.count >= count, let open = beams.first?.logProbability, open < finished[count - 1] {
                beams = []
                break
            }
            // Each surviving branch gets its own sequence: a copy of its parent's, plus its new token.
            let base = llama_seq_id(1 + (step % 2) * width)
            for i in 0..<width { _ = llama_memory_seq_rm(memory, base + llama_seq_id(i), -1, -1) }
            batch.n_tokens = Int32(beams.count)
            for (i, beam) in beams.enumerated() {
                let sequence = base + llama_seq_id(i)
                llama_memory_seq_cp(memory, beam.sequence, sequence, -1, -1)
                batch.token[i] = beam.tokens[beam.tokens.count - 1]
                batch.pos[i] = prefixLength + Int32(beam.tokens.count) - 1
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = sequence
                batch.logits[i] = 1
                beams[i].sequence = sequence
                beams[i].row = Int32(i)
            }
            if step > 0 {  // the parents' sequences are no longer needed
                let previous = llama_seq_id(1 + ((step + 1) % 2) * width)
                for i in 0..<width { _ = llama_memory_seq_rm(memory, previous + llama_seq_id(i), -1, -1) }
            }
            let decoded = llama_decode(context, batch)
            if decoded == 2 {
                beams = []
                break
            }
            guard decoded == 0 else { throw LlamaError.decodeFailed(decoded) }
        }
        for beam in beams where !beam.tokens.isEmpty {  // words still open after `depth` tokens
            let word = text(of: beam.tokens)
            if done[word] == nil { done[word] = beam.logProbability }
        }
        // A few spare words: the caller drops the ones that are not whole Arabic words.
        return done.sorted { $0.value > $1.value }.prefix(count * 2).map { (word: $0.key, logProbability: $0.value) }
    }

    /// Puts `tokens` in sequence 0, decoding only what the cache does not already hold there: the longest common
    /// start with `cached` is kept (less its last token, decoded again so its logits are fresh), the rest decoded.
    /// Branch sequences are dropped first. After an abort or an error the cache is cleared, never trusted.
    private func prefill(_ tokens: [llama_token]) -> Int32 {
        let memory = llama_get_memory(context)
        for s in 1..<sequences { _ = llama_memory_seq_rm(memory, llama_seq_id(s), -1, -1) }
        var keep = zip(cached, tokens).prefix { $0 == $1 }.count
        keep = max(0, min(keep, tokens.count - 1))
        if !llama_memory_seq_rm(memory, 0, Int32(keep), -1) {
            llama_memory_clear(memory, true)
            keep = 0
        }
        cached = Array(cached.prefix(keep))
        return decodeContinuing(Array(tokens[keep...]))
    }

    /// Decodes `tokens` after what sequence 0 holds, and records them as cached when that worked.
    private func decodeContinuing(_ tokens: [llama_token]) -> Int32 {
        var tokens = tokens
        let status = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        if status == 0 {
            cached += tokens
        } else {
            llama_memory_clear(llama_get_memory(context), true)
            cached = []
        }
        return status
    }

    private func text(of tokens: [llama_token]) -> String {
        String(decoding: tokens.flatMap(piece), as: UTF8.self)
    }

    /// The `count` most likely next tokens of one row of logits, best first, with their log-probabilities: one pass
    /// for the best raw scores and their maximum, one for the normaliser; no array the size of the vocabulary.
    static func best(_ logits: UnsafeMutablePointer<Float>, vocabularySize: Int, count: Int)
        -> [(token: llama_token, logProbability: Double)] {
        var top: [(Float, Int)] = []
        top.reserveCapacity(count + 1)
        var largest = -Float.infinity
        for i in 0..<vocabularySize {
            let value = logits[i]
            if value > largest { largest = value }
            if top.count < count || value > top[top.count - 1].0 {
                let at = top.firstIndex { value > $0.0 } ?? top.count
                top.insert((value, i), at: at)
                if top.count > count { top.removeLast() }
            }
        }
        var sum = 0.0
        for i in 0..<vocabularySize { sum += Foundation.exp(Double(logits[i] - largest)) }
        let norm = Double(largest) + Foundation.log(sum)
        return top.map { (token: llama_token($0.1), logProbability: Double($0.0) - norm) }
    }

    /// The prompt's tokens exactly as llama-server's /completion makes them from text, and as training did: special
    /// tokens in the text are parsed and the model's BOS is added. A Llama 3 prompt that starts with the text
    /// `<|begin_of_text|>` therefore gets two BOS tokens, and that is right: the fine-tune was trained that way, and
    /// removing one degrades its output (MODELS.md, "Fine-tuned models").
    /// With `special` false (the model's own answer so far): no BOS, and special-token text is plain text.
    func tokenize(_ text: String, special: Bool = true) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), special, special)
        if count < 0 {  // buffer too small: -count is the size needed
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), special, special)
        }
        guard count > 0 else { throw LlamaError.tokenizeFailed }
        tokens.removeLast(tokens.count - Int(count))
        return tokens
    }

    /// The model's beginning-of-sequence token.
    var bosToken: llama_token { llama_vocab_bos(vocab) }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 32)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(count, 0))).map { UInt8(bitPattern: $0) }
    }
}

/// llama.cpp's Metal device asserts when the process exits with a model still loaded
/// (`GGML_ASSERT([rsets->data count] == 0)` in ggml-metal-device.m), which would crash a service that keeps its
/// model warm every time it quits. Models still alive at exit are freed first: the atexit handler is registered
/// after the first model is loaded, so it runs before llama.cpp's own clean-up (registered during that load).
private enum ExitCleanup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var models: [ObjectIdentifier: Unmanaged<LlamaModel>] = [:]
    nonisolated(unsafe) private static var handlerRegistered = false

    static func register(_ model: LlamaModel) {
        lock.lock()
        defer { lock.unlock() }
        models[ObjectIdentifier(model)] = .passUnretained(model)
        if !handlerRegistered {
            handlerRegistered = true
            atexit { ExitCleanup.freeAll() }
        }
    }

    static func unregister(_ model: LlamaModel) {
        lock.lock()
        defer { lock.unlock() }
        models[ObjectIdentifier(model)] = nil
    }

    private static func freeAll() {
        lock.lock()
        defer { lock.unlock() }
        for model in models.values {
            model.takeUnretainedValue().freeResources()
        }
    }
}
