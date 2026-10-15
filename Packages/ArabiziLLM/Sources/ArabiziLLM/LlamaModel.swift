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
public final class LlamaModel: @unchecked Sendable {  // all mutable state is behind `lock`
    public struct Settings: Sendable {
        /// Prompt plus answer, in tokens. A keyboard message is short; 512 keeps the KV cache small on 8 GB.
        public var contextLength: Int32 = 512
        /// Layers on the GPU (Metal); a large number means all of them.
        public var gpuLayers: Int32 = 999

        public init() {}
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private let contextLength: Int
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

        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)
        var tokens = try tokenize(prompt)
        let promptTokens = tokens.count
        guard tokens.count + maxTokens <= contextLength else {
            throw LlamaError.promptTooLong(tokens: tokens.count, limit: contextLength - maxTokens)
        }
        var output: [UInt8] = []
        var generated = 0
        var stop = Generation.Stop.maxTokens
        while generated < maxTokens {
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
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

    private func tokenize(_ text: String) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), true, true)
        if count < 0 {  // buffer too small: -count is the size needed
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), true, true)
        }
        guard count > 0 else { throw LlamaError.tokenizeFailed }
        tokens.removeLast(tokens.count - Int(count))
        // A template that already starts with the BOS text (Llama 3) plus the BOS llama.cpp adds would give two.
        let bos = llama_vocab_bos(vocab)
        if tokens.count >= 2 && tokens[0] == bos && tokens[1] == bos {
            tokens.removeFirst()
        }
        return tokens
    }

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
