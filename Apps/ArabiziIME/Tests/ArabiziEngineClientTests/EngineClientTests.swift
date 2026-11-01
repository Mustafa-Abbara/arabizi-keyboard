import ArabiziContracts
import ArabiziCore
import Foundation
import Testing
@testable import ArabiziEngineClient

// The keyboard's side of the engine service when the service fails (docs/FAILURE_MATRIX.md): it must give up after
// the deadline plus a margin, so the keyboard answers with its own rules, and reconnect on the next message.
// A real XPC connection to an in-process listener stands in for the service.

private let config = try! EngineConfig(  // swiftlint:disable:this force_try
    configDirectory: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../config"))

/// How the fake service behaves for each connection, in order.
private enum Behaviour { case answer, silent, dropConnection }

private final class FakeService: NSObject, ArabiziEngineServiceProtocol, @unchecked Sendable {
    let behaviour: Behaviour
    weak var connection: NSXPCConnection?

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func convert(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        switch behaviour {
        case .answer:
            let response = ConvertResponse(id: UUID(), text: "كيفك", outcome: .model, latencyMs: 5)
            reply((try? Contract.encoder().encode(response)) ?? Data())
        case .silent:
            break  // never replies, like a service stuck in a long generation
        case .dropConnection:
            connection?.invalidate()  // like the service crashing mid-request
        }
    }

    func status(reply: @escaping @Sendable (Data) -> Void) { reply(Data("{}".utf8)) }
}

/// An anonymous listener: each new connection gets the next behaviour (the last one repeats).
private final class FakeListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var behaviours: [Behaviour]
    private(set) var connections = 0

    init(_ behaviours: [Behaviour]) {
        self.behaviours = behaviours
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let behaviour = lock.withLock {
            connections += 1
            return behaviours.count > 1 ? behaviours.removeFirst() : behaviours[0]
        }
        let service = FakeService(behaviour)
        service.connection = connection
        connection.exportedInterface = NSXPCInterface(with: ArabiziEngineServiceProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    func client() -> EngineClient {
        let endpoint = listener.endpoint
        return EngineClient(config: config) { NSXPCConnection(listenerEndpoint: endpoint) }
    }
}

private func timed<T>(_ body: () -> T) -> (T, Int) {
    let start = Date()
    let value = body()
    return (value, Int(Date().timeIntervalSince(start) * 1000))
}

@Test func aServiceThatAnswersGivesItsText() {
    let fake = FakeListener([.answer])
    #expect(fake.client().convert("kifak") == "كيفك")
}

@Test func aServiceThatNeverAnswersGivesUpAfterTheDeadline() {
    let fake = FakeListener([.silent])
    let limit = config.deadlineMs(for: "kifak") + EngineClient.replyMarginMs
    let (text, ms) = timed { fake.client().convert("kifak") }
    #expect(text == nil)  // the keyboard then uses its own rules
    #expect(ms >= limit - 50 && ms < limit + 1_000, "gave up after \(ms) ms, limit \(limit) ms")
}

@Test func aServiceThatCrashesIsReachedAgainOnTheNextMessage() {
    let fake = FakeListener([.dropConnection, .answer])
    let client = fake.client()
    #expect(client.convert("kifak") == nil)  // the connection dropped: rules in the keyboard
    #expect(client.convert("kifak") == "كيفك")  // a new connection, a working service
    #expect(fake.connections == 2)
}
