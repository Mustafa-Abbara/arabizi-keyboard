import Foundation

/// The model's other spellings for one word of its answer (ADR 0036): the ↑ list's first source. `text` is the
/// message as typed; `before` is the model's answer up to the word being fixed (empty for the first word). The
/// `kind` field tells it apart from a ConvertRequest on the same pipe or service. JSON form:
/// docs/schemas/word_guess_request.v1.schema.json.
public struct WordGuessRequest: Codable, Equatable, Sendable {
    public static let kind = "wordGuesses"
    public let v: Int
    public let kind: String
    public let id: UUID
    public let text: String
    public let before: String
    public let count: Int
    public let deadlineMs: Int

    public init(id: UUID = UUID(), text: String, before: String, count: Int = 5, deadlineMs: Int) {
        v = Contract.version
        kind = Self.kind
        self.id = id
        self.text = text
        self.before = before
        self.count = count
        self.deadlineMs = deadlineMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeVersion(forKey: .v)
        kind = try container.decode(String.self, forKey: .kind)
        guard kind == Self.kind else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                                                   debugDescription: "not a word guess request")
        }
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        before = try container.decode(String.self, forKey: .before)
        count = try container.decode(Int.self, forKey: .count)
        deadlineMs = try container.decode(Int.self, forKey: .deadlineMs)
        guard (1...10).contains(count) else {
            throw DecodingError.dataCorruptedError(forKey: .count, in: container,
                                                   debugDescription: "count must be 1 to 10")
        }
        guard deadlineMs > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .deadlineMs, in: container,
                                                   debugDescription: "deadlineMs must be positive")
        }
    }

    /// True for a JSON line that carries this kind of request (and not a ConvertRequest).
    public static func isWordGuessRequest(_ line: Data) -> Bool {
        struct Kind: Decodable { let kind: String? }
        return (try? JSONDecoder().decode(Kind.self, from: line))?.kind == Self.kind
    }
}

/// The model's guesses for that word, best first. `outcome` is `model` when the model answered (the list may still
/// be empty), `fallbackTimeout` when the deadline passed, `fallbackModelUnavailable` without a model; the keyboard
/// then keeps the list it already shows. JSON form: docs/schemas/word_guess_response.v1.schema.json.
public struct WordGuessResponse: Codable, Equatable, Sendable {
    public struct Guess: Codable, Equatable, Sendable {
        public let word: String
        public let logProbability: Double

        public init(word: String, logProbability: Double) {
            self.word = word
            self.logProbability = logProbability
        }
    }

    public let v: Int
    public let id: UUID
    public let guesses: [Guess]
    public let outcome: Outcome
    public let latencyMs: Int

    public init(id: UUID, guesses: [Guess], outcome: Outcome, latencyMs: Int) {
        v = Contract.version
        self.id = id
        self.guesses = guesses
        self.outcome = outcome
        self.latencyMs = latencyMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decodeVersion(forKey: .v)
        id = try container.decode(UUID.self, forKey: .id)
        guesses = try container.decode([Guess].self, forKey: .guesses)
        outcome = try container.decode(Outcome.self, forKey: .outcome)
        latencyMs = try container.decode(Int.self, forKey: .latencyMs)
        guard latencyMs >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .latencyMs, in: container,
                                                   debugDescription: "latencyMs cannot be negative")
        }
    }
}
