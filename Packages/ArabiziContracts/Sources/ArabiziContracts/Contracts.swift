import Foundation

/// Version 1 of the messages between the keyboard, the engine and arabizi-cli (roadmap P5 step 1).
/// The JSON form is fixed by docs/schemas/convert_request.v1.schema.json and convert_response.v1.schema.json;
/// docs/API_CONTRACTS.md explains each field. A message with another version is rejected, never guessed at.
public enum Contract {
    public static let version = 1

    /// JSON as arabizi-cli writes it: one object per line, keys sorted so the output is stable.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Convert this Latin text. `deadlineMs` is the time the caller can wait for the model before the rule
/// fallback answers instead.
public struct ConvertRequest: Codable, Equatable, Sendable {
    public let v: Int
    public let id: UUID
    public let text: String
    public let deadlineMs: Int
    /// false: convert this text on its own, never from the last conversion (ADR 0037; the keyboard's "Faster
    /// preview" setting switched off). Absent: the engine's own default (incremental).
    public let incremental: Bool?

    public init(id: UUID = UUID(), text: String, deadlineMs: Int, incremental: Bool? = nil) {
        v = Contract.version
        self.id = id
        self.text = text
        self.deadlineMs = deadlineMs
        self.incremental = incremental
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeVersion(forKey: .v)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        deadlineMs = try container.decode(Int.self, forKey: .deadlineMs)
        incremental = try container.decodeIfPresent(Bool.self, forKey: .incremental)
        guard deadlineMs > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .deadlineMs, in: container,
                                                   debugDescription: "deadlineMs must be positive")
        }
    }
}

/// The converted text, how it was made, and how long it took.
public struct ConvertResponse: Codable, Equatable, Sendable {
    public let v: Int
    public let id: UUID
    public let text: String
    public let outcome: Outcome
    public let latencyMs: Int
    /// For a model answer: how sure the model was of each word of `text` (split at spaces), 0 to 1. Absent when
    /// unknown (the rules, or an answer whose words changed after the model). The keyboard's ↑ starts on the least
    /// sure word.
    public let wordConfidence: [Double]?

    public init(id: UUID, text: String, outcome: Outcome, latencyMs: Int, wordConfidence: [Double]? = nil) {
        v = Contract.version
        self.id = id
        self.text = text
        self.outcome = outcome
        self.latencyMs = latencyMs
        self.wordConfidence = wordConfidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeVersion(forKey: .v)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        outcome = try container.decode(Outcome.self, forKey: .outcome)
        latencyMs = try container.decode(Int.self, forKey: .latencyMs)
        guard latencyMs >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .latencyMs, in: container,
                                                   debugDescription: "latencyMs cannot be negative")
        }
        wordConfidence = try container.decodeIfPresent([Double].self, forKey: .wordConfidence)
        guard wordConfidence?.allSatisfy({ (0...1).contains($0) }) ?? true else {
            throw DecodingError.dataCorruptedError(forKey: .wordConfidence, in: container,
                                                   debugDescription: "wordConfidence values are 0 to 1")
        }
    }
}

/// Which path produced the text (roadmap P5). Everything except `model` and `passthrough` is the rule fallback,
/// with the reason.
public enum Outcome: String, Codable, CaseIterable, Sendable {
    /// The model's answer, after the output checks passed.
    case model
    /// The model did not finish before the deadline.
    case fallbackTimeout
    /// The model finished, but its answer failed an output check (placeholders, length, new Latin text).
    case fallbackCheckFailed
    /// No model: switched off in config/engine.json, missing, wrong checksum, or failed to load.
    case fallbackModelUnavailable
    /// Returned unchanged: there was nothing to convert (no Latin letter in the text).
    case passthrough
}

extension KeyedDecodingContainer {
    func decodeVersion(forKey key: Key) throws -> Int {
        let version = try decode(Int.self, forKey: key)
        guard version == Contract.version else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self,
                                                   debugDescription: "unsupported contract version \(version)")
        }
        return version
    }
}
