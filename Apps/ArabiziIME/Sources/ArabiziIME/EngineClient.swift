import ArabiziContracts
import ArabiziCore
import Foundation
import os

/// The keyboard's side of the engine service (roadmap P5 step 5, ADR 0020): send the Latin text, wait at most the
/// deadline plus a margin, and return the converted text, or nil so the keyboard uses its own rules. The service
/// starts on the rules and loads the model in the background, so the first Enter after login is never slow.
/// Logs only outcomes, timings and the service status: never the text.
final class EngineClient: @unchecked Sendable {  // `connection` is behind `lock`
    private let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let config: EngineConfig
    private let encoder = Contract.encoder()
    /// How long past the deadline the keyboard waits for the reply (the rule fallback inside the service).
    private static let replyMarginMs = 500

    /// nil when the bundled config cannot be read: the keyboard then keeps to its own rules.
    init?(resources: URL) {
        guard let config = try? EngineConfig(configDirectory: resources) else {
            Logger(subsystem: "lb.aub.arabizi", category: "ime").error("engine config not readable: rules only")
            return nil
        }
        self.config = config
    }

    private func proxy() -> ArabiziEngineServiceProtocol? {
        lock.withLock {
            if connection == nil {
                let new = NSXPCConnection(serviceName: EngineService.name)
                new.remoteObjectInterface = NSXPCInterface(with: ArabiziEngineServiceProtocol.self)
                new.invalidationHandler = { [weak self] in
                    self?.lock.withLock { self?.connection = nil }
                }
                new.resume()
                connection = new
            }
            return connection?.remoteObjectProxyWithErrorHandler { [log] error in
                log.error("engine service error: \(String(describing: error), privacy: .public)")
            } as? ArabiziEngineServiceProtocol
        }
    }

    /// Starts the service early (it loads the model in the background) and logs its status, network probe included.
    func warmUp() {
        proxy()?.status { [log] data in
            log.info("engine status: \(String(decoding: data, as: UTF8.self), privacy: .public)")
        }
    }

    func convert(_ text: String) -> String? {
        let deadlineMs = config.deadlineMs(for: text)  // longer messages get longer (ADR 0025)
        guard let proxy = proxy(),
              let request = try? encoder.encode(ConvertRequest(text: text, deadlineMs: deadlineMs)) else { return nil }
        let box = ReplyBox()
        proxy.convert(request) { data in box.set(data) }
        guard let data = box.wait(milliseconds: deadlineMs + Self.replyMarginMs),
              let response = try? JSONDecoder().decode(ConvertResponse.self, from: data) else {
            log.error("engine service did not answer in time: rules in the keyboard")
            return nil
        }
        log.info("converted by the engine: \(response.outcome.rawValue, privacy: .public) in \(response.latencyMs) ms")
        return response.text
    }
}

/// The reply of one XPC call, handed from the XPC queue to the waiting keyboard thread.
private final class ReplyBox: @unchecked Sendable {  // `data` is behind `lock`
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var data: Data?

    func set(_ value: Data) {
        lock.withLock { data = value }
        semaphore.signal()
    }

    func wait(milliseconds: Int) -> Data? {
        guard semaphore.wait(timeout: .now() + .milliseconds(milliseconds)) == .success else { return nil }
        return lock.withLock { data }
    }
}
