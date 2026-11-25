import Foundation

/// What one conversion did, step by step: the path it took, how long each step took, and the model's token counts
/// (docs/OBSERVABILITY.md). It never holds text: only names, counts and timings, so the engines can keep it in their
/// logs and `evalrun ops` can summarise it.
///
/// Routes, in the order the engine tries them:
/// - `passthrough`: no Latin letter, returned unchanged;
/// - `english`: plain English (EnglishGuard), returned unchanged;
/// - `noModel`: no usable model, the rules answer;
/// - `tooLong`: longer than `max_input_chars`, the rules answer;
/// - `model`: the model was asked (its `outcome` says whether its answer was kept).
///
/// Spans, each timed from the end of the one before: `route` (the guards), `protect` (placeholders), `generate` (the
/// model), `check` (output checks), `repair` (token repair, ADR 0023), `restore` (abbreviations kept as typed) and
/// `rules` (the rule converter, for a fallback or a message the model is not asked about).
public struct ConversionTrace: Codable, Equatable, Sendable {
    public struct Span: Codable, Equatable, Sendable {
        public let name: String
        public let ms: Double

        public init(name: String, ms: Double) {
            self.name = name
            self.ms = ms
        }
    }

    public var v = 1
    public var route: String
    /// The response's outcome (`model`, `fallbackTimeout`…).
    public var outcome: String
    /// Why a fallback happened, or how many tokens were repaired: counts only (Engine.describe).
    public var reason: String?
    public var inputWords: Int
    public var outputWords: Int
    public var deadlineMs: Int
    /// The prompt's length in tokens, the saved instruction included (a kept instruction is not decoded again).
    public var promptTokens: Int?
    public var generatedTokens: Int?
    /// How generation ended: `endOfTurn`, `maxTokens` or `deadline`.
    public var stop: String?
    public var repairedTokens: Int?
    public var spans: [Span]
    public var totalMs: Double

    public init(route: String, outcome: String, reason: String? = nil, inputWords: Int, outputWords: Int,
                deadlineMs: Int, promptTokens: Int? = nil, generatedTokens: Int? = nil, stop: String? = nil,
                repairedTokens: Int? = nil, spans: [Span], totalMs: Double) {
        self.route = route
        self.outcome = outcome
        self.reason = reason
        self.inputWords = inputWords
        self.outputWords = outputWords
        self.deadlineMs = deadlineMs
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.stop = stop
        self.repairedTokens = repairedTokens
        self.spans = spans
        self.totalMs = totalMs
    }

    /// One JSON line (sorted keys, no newline), for logs.
    public func jsonLine() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return (Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15).rounded(toPlaces: 2)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
