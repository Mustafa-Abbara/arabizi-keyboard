// The sandboxed engine service (roadmap P5 step 5, ADR 0020). It has no network entitlement and reads only its
// own bundle: the config, the rule files and the model are copied into Contents/Resources by scripts/build_ime.sh.
// It answers on the rules at once and loads the model in the background (its SHA-256 check reads the whole file),
// so the keyboard is never blocked. Never logs user text: only states, outcomes and timings.
import ArabiziContracts
import ArabiziCore
import ArabiziEngine
import Foundation
import os

let log = Logger(subsystem: "lb.aub.arabizi", category: "engine")
let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL

final class EngineHost: NSObject, ArabiziEngineServiceProtocol, @unchecked Sendable {  // state behind `lock`
    private let lock = NSLock()
    private var engine: Engine
    private var loading = true
    private let decoder = JSONDecoder()
    private let encoder = Contract.encoder()
    /// Requests come in through here: after 30 minutes without any, the service quits to free the model's memory.
    let idle = IdleClock()

    /// True while the model is still being loaded (the service never quits then).
    var isLoading: Bool { lock.withLock { loading } }

    init(rulesOnly: Engine) {
        engine = rulesOnly
        super.init()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let started = ContinuousClock.now
            do {
                let full = try Engine.load(configDirectory: resources, rulesDirectory: resources,
                                           modelsDirectory: resources)
                lock.withLock {
                    engine = full
                    loading = false
                }
                log.info("engine ready: \(String(describing: full.modelState), privacy: .public) in \(String(describing: ContinuousClock.now - started), privacy: .public)")
            } catch {
                lock.withLock { loading = false }
                log.error("engine failed to load, staying on the rules: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func convert(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        idle.touch()
        defer { idle.touch() }
        guard let decoded = try? decoder.decode(ConvertRequest.self, from: request) else {
            reply(Data())
            return
        }
        let current = lock.withLock { engine }
        let response = current.convert(decoded)
        log.debug("converted: \(response.outcome.rawValue, privacy: .public) in \(response.latencyMs) ms")
        reply((try? encoder.encode(response)) ?? Data())
    }

    func wordGuesses(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        idle.touch()
        defer { idle.touch() }
        guard let decoded = try? decoder.decode(WordGuessRequest.self, from: request) else {
            reply(Data())
            return
        }
        let current = lock.withLock { engine }
        let response = current.wordGuesses(decoded)
        log.debug("guessed: \(response.outcome.rawValue, privacy: .public), \(response.guesses.count) word(s) in \(response.latencyMs) ms")
        reply((try? encoder.encode(response)) ?? Data())
    }

    struct Status: Codable, Sendable {
        var loading: Bool
        var state: String
        var model: String?
        var reason: String?
        var network: String?
    }

    func status(reply: @escaping @Sendable (Data) -> Void) {
        idle.touch()
        let (current, stillLoading) = lock.withLock { (engine, loading) }
        let status: Status
        switch current.modelState {
        case .off: status = Status(loading: stillLoading, state: "off")
        case .ready(let id): status = Status(loading: stillLoading, state: "ready", model: id)
        case .unavailable(let id, let reason):
            status = Status(loading: stillLoading, state: "unavailable", model: id, reason: reason)
        }
        probeNetwork { result in
            var answered = status
            answered.network = result
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            reply((try? encoder.encode(answered)) ?? Data())
        }
    }

    /// Tries to reach the internet; without a network entitlement the sandbox must refuse (P5 gate). The answer is
    /// "blocked: …" or, if something is wrong with the signing, "ALLOWED".
    private func probeNetwork(_ done: @escaping @Sendable (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.timeoutInterval = 3
        URLSession(configuration: .ephemeral).dataTask(with: request) { _, response, error in
            if let error = error as NSError? {
                done("blocked: \(error.domain) \(error.code)")
            } else {
                done(response == nil ? "blocked: no response" : "ALLOWED")
            }
        }.resume()
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let host: EngineHost

    init(host: EngineHost) { self.host = host }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ArabiziEngineServiceProtocol.self)
        connection.exportedObject = host
        connection.resume()
        return true
    }
}

// Rules only until the model has loaded: the same config with the model switched off.
let rulesOnly: Engine
do {
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appending(path: "engine.json")))
        as? [String: Any] ?? [:]
    json["features"] = ["use_model": false]
    let config = try EngineConfig(engine: JSONSerialization.data(withJSONObject: json),
                                  models: Data(contentsOf: resources.appending(path: "models.json")))
    rulesOnly = try Engine.load(config: config, rulesDirectory: resources, modelsDirectory: resources)
} catch {
    log.fault("engine service cannot start (config or rule files missing): \(String(describing: error), privacy: .public)")
    exit(1)
}
log.info("engine service started on the rules; loading the model in the background")
let host = EngineHost(rulesOnly: rulesOnly)
// After half an hour without a request the service quits, which gives the model's memory back (about 1 GB, measured
// as wired memory on the 8 GB Air); launchd starts it again on the next request, and the keyboard converts ahead
// while the user types, so the model has loaded again by Enter in most cases.
// A strict timer: macOS may otherwise delay a background service's sleeping thread by many minutes (the service
// quit 47 minutes after its last request in a 30-minute test, 11 Nov 2026).
let idleCheck = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .utility))
idleCheck.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(1))
idleCheck.setEventHandler { [host] in
    if host.idle.isIdle, !host.isLoading {
        log.info("idle for 30 minutes: quitting to free the model's memory")
        exit(0)
    }
}
idleCheck.resume()
let delegate = ListenerDelegate(host: host)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()  // never returns
