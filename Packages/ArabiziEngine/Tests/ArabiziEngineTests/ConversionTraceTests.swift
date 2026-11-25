import ArabiziContracts
import ArabiziLLM
import Foundation
import Testing
@testable import ArabiziEngine

// A conversion's trace (docs/OBSERVABILITY.md): the route, one span per step, the model's token counts, never text.

private func names(_ trace: ConversionTrace) -> [String] { trace.spans.map(\.name) }

@Test func aModelAnswerIsTracedStepByStep() throws {
    let model = ScriptedModel { _ in finished("كيفك، شو عم تعمل؟") }
    let (response, _, trace) = try engine(model).convertTraced(request("kifak, shu 3am ta3mel?"))
    #expect(trace.route == "model" && trace.outcome == response.outcome.rawValue && trace.outcome == "model")
    #expect(names(trace) == ["route", "protect", "generate", "check", "restore"])
    #expect(trace.promptTokens == 10 && trace.generatedTokens == 5 && trace.stop == "endOfTurn")
    #expect(trace.inputWords == 4 && trace.outputWords == 4 && trace.deadlineMs == 1500)
    #expect(trace.reason == nil && trace.repairedTokens == nil)
    #expect(trace.spans.allSatisfy { $0.ms >= 0 } && trace.totalMs >= trace.spans.map(\.ms).reduce(0, +) - 0.1)
}

@Test(arguments: [
    (finished("كيفك", .deadline), "fallbackTimeout", ["route", "protect", "generate", "rules"], "deadline"),
    (finished("كيفك كيفك", .maxTokens), "fallbackCheckFailed", ["route", "protect", "generate", "rules"], "maxTokens"),
    (finished("كيفك how are you"), "fallbackCheckFailed", ["route", "protect", "generate", "check", "repair", "rules"],
     "endOfTurn"),
])
func fallbacksEndWithTheRules(answer: Generation, outcome: String, spans: [String], stop: String) throws {
    let (_, reason, trace) = try engine(ScriptedModel { _ in answer }).convertTraced(request("kifak"))
    #expect(trace.outcome == outcome && names(trace) == spans && trace.stop == stop)
    #expect(trace.reason == reason && trace.reason != nil)
}

@Test func aRepairIsCounted() throws {
    let model = ScriptedModel { _ in finished("شفت الvideo عالfacebook") }
    let (_, _, trace) = try engine(model).convertTraced(request("shefet el video 3al facebook"))
    #expect(trace.outcome == "model" && trace.repairedTokens == 2)
    #expect(names(trace) == ["route", "protect", "generate", "check", "repair", "restore"])
}

@Test func routesWithoutTheModel() throws {
    let model = ScriptedModel { _ in finished("x") }
    #expect(try engine(model).convertTraced(request("١٢٣")).trace.route == "passthrough")
    #expect(try engine(model, english: true).convertTraced(request("see you at the meeting tomorrow")).trace.route
            == "english")
    let noModel = try engine(nil).convertTraced(request("kifak")).trace
    #expect(noModel.route == "noModel" && names(noModel) == ["route", "rules"] && noModel.promptTokens == nil)
    #expect(try engine(model, maxInputChars: 3).convertTraced(request("kifak")).trace.route == "tooLong")
    #expect(model.prompts.isEmpty)
}

@Test func theTraceHoldsNoText() throws {
    let typed = "b3at 100$ la mohammad, shu 3am ta3mel?"
    let model = ScriptedModel { _ in finished("بعت ⟦0⟧ لمحمد how") }
    let line = try engine(model).convertTraced(request(typed)).trace.jsonLine()
    for word in typed.split(separator: " ").map(String.init) + ["بعت", "لمحمد", "how"] {
        #expect(!line.contains(word), "the trace line holds \(word)")
    }
    let decoded = try JSONDecoder().decode(ConversionTrace.self, from: Data(line.utf8))
    #expect(decoded.route == "model" && decoded.v == 1)
}
