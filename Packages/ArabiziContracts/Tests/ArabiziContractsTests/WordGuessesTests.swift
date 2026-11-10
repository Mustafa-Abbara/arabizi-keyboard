import Foundation
import Testing
@testable import ArabiziContracts

/// The word-guess messages (ADR 0036) against their schemas and examples (docs/schemas).
@Suite struct WordGuessesTests {
    @Test func requestExampleRoundTripsExactly() throws {
        let data = try example("word_guess_request")
        let request = try JSONDecoder().decode(WordGuessRequest.self, from: data)
        #expect(request.kind == WordGuessRequest.kind && request.count == 5 && request.before == "شو")
        #expect(trimmed(try Contract.encoder().encode(request)) == trimmed(data))
    }

    @Test func responseExampleRoundTripsExactly() throws {
        let data = try example("word_guess_response")
        let response = try JSONDecoder().decode(WordGuessResponse.self, from: data)
        #expect(response.guesses.map(\.word) == ["عم", "عام"] && response.outcome == .model)
        #expect(trimmed(try Contract.encoder().encode(response)) == trimmed(data))
    }

    @Test func fieldsMatchTheSchemas() throws {
        let request = try JSONSerialization.jsonObject(
            with: Contract.encoder().encode(WordGuessRequest(text: "shu", before: "", deadlineMs: 10))) as? [String: Any]
        let response = try JSONSerialization.jsonObject(
            with: Contract.encoder().encode(WordGuessResponse(id: UUID(), guesses: [], outcome: .model, latencyMs: 1)))
            as? [String: Any]
        #expect(Set(try #require(request).keys) == (try schemaProperties("word_guess_request")).required)
        let responseSchema = try schemaProperties("word_guess_response")
        #expect(Set(try #require(response).keys) == responseSchema.required)
        #expect(Set(Outcome.allCases.map(\.rawValue)) == responseSchema.outcomes)
    }

    @Test func aWordGuessRequestIsToldApartFromAConversion() throws {
        #expect(WordGuessRequest.isWordGuessRequest(try example("word_guess_request")))
        #expect(!WordGuessRequest.isWordGuessRequest(try example("convert_request")))
        #expect(!WordGuessRequest.isWordGuessRequest(Data("status".utf8)))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WordGuessRequest.self, from: try example("convert_request"))
        }
    }

    @Test(arguments: [
        #"{"v":2,"kind":"wordGuesses","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","before":"","count":5,"deadlineMs":400}"#,
        #"{"v":1,"kind":"convert","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","before":"","count":5,"deadlineMs":400}"#,
        #"{"v":1,"kind":"wordGuesses","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","before":"","count":0,"deadlineMs":400}"#,
        #"{"v":1,"kind":"wordGuesses","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","before":"","count":11,"deadlineMs":400}"#,
        #"{"v":1,"kind":"wordGuesses","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","before":"","count":5,"deadlineMs":0}"#,
        #"{"v":1,"kind":"wordGuesses","id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","text":"shu","count":5,"deadlineMs":400}"#,
    ])
    func badRequestsAreRejected(json: String) {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WordGuessRequest.self, from: Data(json.utf8)) }
    }
}
