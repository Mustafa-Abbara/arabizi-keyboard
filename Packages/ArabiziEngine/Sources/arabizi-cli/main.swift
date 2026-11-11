// arabizi-cli (roadmap P5 step 6): the engine over JSON lines, so the evaluation harness measures the real Swift
// engine. One ConvertRequest per line on stdin, one ConvertResponse per line on stdout (docs/API_CONTRACTS.md).
// The engine's status goes to stderr as one JSON line at start-up. Never prints the text it converts to stderr.
//
//   arabizi-cli [--config DIR] [--rules DIR] [--models DIR] [--model ID | --no-model] [--skip-hash] [--explain] [--no-repair] [--no-pin] [--no-incremental] [--keyboard-deadline]
// A line that is a WordGuessRequest (`"kind": "wordGuesses"`) gets a WordGuessResponse: the ↑ list's model guesses
// (ADR 0036). Conversions and guesses can be mixed, as the keyboard sends them.
// --explain writes one line per request to stderr: why a fallback happened, or how many tokens of a model answer
// were repaired (ADR 0023); reason null otherwise. Counts only, no text.
import ArabiziContracts
import ArabiziCore
import ArabiziEngine
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((#"{"error": "# + json(message) + "}\n").utf8))
    exit(2)
}

func json(_ value: Any) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data("[null]".utf8)
    return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
}

var configDirectory = "config", rulesDirectory = "data/rules", modelsDirectory = "models"
var modelOverride: String?, noModel = false, verifyHash = true, explain = false, repair = true
var keyboardDeadline = false, pin = true, incremental = true
var arguments = CommandLine.arguments.dropFirst().makeIterator()
@MainActor func value(after flag: String) -> String {
    guard let value = arguments.next() else { fail("\(flag) needs a value") }
    return value
}
while let argument = arguments.next() {
    switch argument {
    case "--config": configDirectory = value(after: argument)
    case "--rules": rulesDirectory = value(after: argument)
    case "--models": modelsDirectory = value(after: argument)
    case "--model": modelOverride = value(after: argument)
    case "--no-model": noModel = true
    case "--skip-hash": verifyHash = false
    case "--explain": explain = true
    case "--no-repair": repair = false
    case "--no-pin": pin = false  // the whole prompt decoded for every conversion, as before the instruction was kept
    case "--no-incremental": incremental = false  // every text converted on its own (ADR 0037)
    case "--keyboard-deadline": keyboardDeadline = true
    default: fail("unknown argument \(argument)")
    }
}

let started = ContinuousClock.now
let engine: Engine
do {
    let configURL = URL(filePath: configDirectory)
    var engineJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL.appending(path: "engine.json")))
        as? [String: Any] ?? [:]
    if let modelOverride {
        engineJSON["model"] = modelOverride
        engineJSON["features"] = ["use_model": true]
    } else if noModel {
        engineJSON["features"] = ["use_model": false]
    }
    let config = try EngineConfig(engine: JSONSerialization.data(withJSONObject: engineJSON),
                                  models: Data(contentsOf: configURL.appending(path: "models.json")))
    engine = try Engine.load(config: config, rulesDirectory: URL(filePath: rulesDirectory),
                             modelsDirectory: URL(filePath: modelsDirectory), verifyModelHash: verifyHash,
                             repairTokens: repair, pinInstruction: pin, incremental: incremental)
} catch {
    fail("could not start the engine: \(error)")
}

let loadMs = Int((ContinuousClock.now - started).components.seconds * 1000
                 + (ContinuousClock.now - started).components.attoseconds / 1_000_000_000_000_000)
var status: [String: Any] = ["load_ms": loadMs, "deadline_ms": engine.config.deadlineMs]
switch engine.modelState {
case .off: status["state"] = "off"
case .ready(let id): status["state"] = "ready"; status["model"] = id
case .unavailable(let id, let reason): status["state"] = "unavailable"; status["model"] = id; status["reason"] = reason
}
FileHandle.standardError.write(Data(json(status).utf8 + Data("\n".utf8)))

let decoder = JSONDecoder(), encoder = Contract.encoder()
var lineNumber = 0
while let line = readLine(strippingNewline: true) {
    lineNumber += 1
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    do {
        if WordGuessRequest.isWordGuessRequest(Data(line.utf8)) {  // the ↑ list's model guesses (ADR 0036)
            let (response, reason) = engine.wordGuessesExplained(try decoder.decode(WordGuessRequest.self,
                                                                                     from: Data(line.utf8)))
            FileHandle.standardOutput.write(try encoder.encode(response) + Data("\n".utf8))
            if explain {
                let shown = reason.map(json) ?? "null"
                FileHandle.standardError.write(Data((#"{"line": \#(lineNumber), "reason": "# + shown + "}\n").utf8))
            }
            continue
        }
        var request = try decoder.decode(ConvertRequest.self, from: Data(line.utf8))
        if keyboardDeadline {  // the deadline the keyboard would give this message (ADR 0025)
            request = ConvertRequest(id: request.id, text: request.text,
                                     deadlineMs: engine.config.deadlineMs(for: request.text),
                                     incremental: request.incremental)
        }
        let (response, reason) = engine.convertExplained(request)
        FileHandle.standardOutput.write(try encoder.encode(response) + Data("\n".utf8))
        if explain {
            let shown = reason.map(json) ?? "null"
            FileHandle.standardError.write(Data((#"{"line": \#(lineNumber), "reason": "# + shown + "}\n").utf8))
        }
    } catch {
        // The request is not echoed: it can hold private text.
        FileHandle.standardError.write(Data(#"{"error": "invalid request", "line": \#(lineNumber)}"#.utf8 + Data("\n".utf8)))
    }
}
