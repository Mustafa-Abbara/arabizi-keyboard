// arabizi-engine-check: talks to the engine service the way the keyboard does, from inside the app bundle
// (Contents/MacOS), where macOS lets it reach Contents/XPCServices. Prints the service status, including the
// network probe that must say "blocked", then converts one public test sentence. No user text involved.
//
//   build/ArabiziIME.app/Contents/MacOS/arabizi-engine-check [--wait SECONDS]
import ArabiziContracts
import Foundation

var waitSeconds = 30.0
if let index = CommandLine.arguments.firstIndex(of: "--wait"), index + 1 < CommandLine.arguments.count {
    waitSeconds = Double(CommandLine.arguments[index + 1]) ?? waitSeconds
}

let connection = NSXPCConnection(serviceName: EngineService.name)
connection.remoteObjectInterface = NSXPCInterface(with: ArabiziEngineServiceProtocol.self)
connection.resume()
guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
    print("engine service error: \(error)")
    exit(1)
}) as? ArabiziEngineServiceProtocol else { exit(1) }

func call(_ body: (@escaping @Sendable (Data) -> Void) -> Void, timeout: Double) -> Data? {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Data?
    body { data in result = data; semaphore.signal() }
    return semaphore.wait(timeout: .now() + timeout) == .success ? result : nil
}

// Poll the status until the model has loaded (or the wait runs out): the service starts on the rules.
let started = Date()
var status: [String: Any] = [:]
repeat {
    guard let data = call({ service.status(reply: $0) }, timeout: 10),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("no status from the engine service")
        exit(1)
    }
    status = object
    if status["loading"] as? Bool == false { break }
    Thread.sleep(forTimeInterval: 1)
} while Date().timeIntervalSince(started) < waitSeconds
print("status: \(status)")

let sentence = "kifik ya sabiyye? shu hal jamal el yom? b3at 100$ 3al 7:30"  // public validation row + numbers
let request = try JSONEncoder().encode(ConvertRequest(text: sentence, deadlineMs: 5000))
guard let data = call({ service.convert(request, reply: $0) }, timeout: 10),
      let response = try? JSONDecoder().decode(ConvertResponse.self, from: data) else {
    print("no answer from the engine service")
    exit(1)
}
print("convert: \(response.outcome.rawValue) in \(response.latencyMs) ms -> \(response.text)")
exit(status["network"].map { "\($0)".hasPrefix("blocked") } ?? false ? 0 : 2)
