import Foundation
import Testing
@testable import ArabiziContracts

/// docs/schemas, found from this file. eval/tests/test_contracts.py checks the same examples against the schemas.
let schemas = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/schemas")

func example(_ name: String) throws -> Data {
    try Data(contentsOf: schemas.appending(path: "examples/\(name).json"))
}

func schemaProperties(_ name: String) throws -> (required: Set<String>, outcomes: Set<String>) {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: schemas.appending(path: "\(name).v1.schema.json")))
    let schema = try #require(json as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let outcome = (properties["outcome"] as? [String: Any])?["enum"] as? [String] ?? []
    return (Set(try #require(schema["required"] as? [String])), Set(outcome))
}

func trimmed(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

@Test func requestExampleRoundTripsExactly() throws {
    let data = try example("convert_request")
    let request = try JSONDecoder().decode(ConvertRequest.self, from: data)
    #expect(request.deadlineMs == 1500 && request.text.hasPrefix("kifak"))
    #expect(trimmed(try Contract.encoder().encode(request)) == trimmed(data))
}

@Test func responseExampleRoundTripsExactly() throws {
    let data = try example("convert_response")
    let response = try JSONDecoder().decode(ConvertResponse.self, from: data)
    #expect(response.outcome == .model)
    #expect(trimmed(try Contract.encoder().encode(response)) == trimmed(data))
}

@Test func fieldsAndOutcomesMatchTheSchemas() throws {
    let request = try JSONSerialization.jsonObject(
        with: Contract.encoder().encode(ConvertRequest(text: "shu", deadlineMs: 10))) as? [String: Any]
    let response = try JSONSerialization.jsonObject(
        with: Contract.encoder().encode(ConvertResponse(id: UUID(), text: "شو", outcome: .model, latencyMs: 1)))
        as? [String: Any]
    #expect(Set(try #require(request).keys) == (try schemaProperties("convert_request")).required)
    let responseSchema = try schemaProperties("convert_response")
    #expect(Set(try #require(response).keys) == responseSchema.required)
    #expect(Set(Outcome.allCases.map(\.rawValue)) == responseSchema.outcomes)
}

@Test(arguments: [
    #"{"v":2,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"shu","deadlineMs":1500}"#,  // another version
    #"{"v":1,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"shu","deadlineMs":0}"#,  // no time at all
    #"{"v":1,"id":"not-a-uuid","text":"shu","deadlineMs":1500}"#,
    #"{"v":1,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","deadlineMs":1500}"#,  // no text
])
func badRequestsAreRejected(json: String) {
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ConvertRequest.self, from: Data(json.utf8)) }
}

@Test(arguments: [
    #"{"v":1,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"x","outcome":"guess","latencyMs":3}"#,
    #"{"v":1,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"x","outcome":"model","latencyMs":-1}"#,
])
func badResponsesAreRejected(json: String) {
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ConvertResponse.self, from: Data(json.utf8)) }
}
