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

    public init(id: UUID = UUID(), text: String, deadlineMs: Int) {
        v = Contract.version
        self.id = id
        self.text = text
        self.deadlineMs = deadlineMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeVersion(forKey: .v)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        deadlineMs = try container.decode(Int.self, forKey: .deadlineMs)
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

    public init(id: UUID, text: String, outcome: Outcome, latencyMs: Int) {
        v = Contract.version
        self.id = id
        self.text = text
        self.outcome = outcome
        self.latencyMs = latencyMs
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
