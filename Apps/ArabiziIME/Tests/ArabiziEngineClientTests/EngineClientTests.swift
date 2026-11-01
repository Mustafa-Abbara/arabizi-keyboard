import ArabiziContracts
import ArabiziCore
import Foundation
import Testing
@testable import ArabiziEngineClient

// The keyboard's side of the engine service when the service fails (docs/FAILURE_MATRIX.md): it must give up after
// the deadline plus a margin, so the keyboard answers with its own rules, and reconnect on the next message.
// A fake service stands in for the XPC one (the keyboard's real link is checked with `arabizi-engine-check`).

private let config = try! EngineConfig(  // swiftlint:disable:this force_try
    configDirectory: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../config"))

/// How the fake service behaves on each new link, in order (the last one repeats).
private enum Behaviour { case answer, silent, crash }

private final class FakeService: NSObject, ArabiziEngineServiceProtocol, @unchecked Sendable {
    let behaviour: Behaviour
    let lost: @Sendable () -> Void

    init(_ behaviour: Behaviour, lost: @escaping @Sendable () -> Void) {
        self.behaviour = behaviour
        self.lost = lost
    }

    func convert(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        switch behaviour {
        case .answer:
            let response = ConvertResponse(id: UUID(), text: "كيفك", outcome: .model, latencyMs: 5)
            reply((try? Contract.encoder().encode(response)) ?? Data())
        case .silent:
            break  // never replies, like a service stuck in a long generation
        case .crash:
            DispatchQueue.global().async { self.lost() }  // the link ends mid-request, no reply
        }
    }

    func status(reply: @escaping @Sendable (Data) -> Void) { reply(Data("{}".utf8)) }
}

/// Hands out a link per connection attempt, each with the next behaviour, and counts the attempts.
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var behaviours: [Behaviour]
    private var count = 0
    var connections: Int { lock.withLock { count } }

    init(_ behaviours: [Behaviour]) { self.behaviours = behaviours }

    func client() -> EngineClient {
        EngineClient(config: config) { lost in
            let behaviour = self.lock.withLock {
                self.count += 1
                return self.behaviours.count > 1 ? self.behaviours.removeFirst() : self.behaviours[0]
            }
            return EngineLink(service: FakeService(behaviour, lost: lost))
        }
    }
}

private func timed<T>(_ body: () -> T) -> (T, Int) {
    let start = Date()
    let value = body()
    return (value, Int(Date().timeIntervalSince(start) * 1000))
}

@Test func aServiceThatAnswersGivesItsText() {
    #expect(FakeServer([.answer]).client().convert("kifak") == "كيفك")
}

@Test func aServiceThatNeverAnswersGivesUpAfterTheDeadline() {
    let server = FakeServer([.silent])
    let limit = config.deadlineMs(for: "kifak") + EngineClient.replyMarginMs
    let (text, ms) = timed { server.client().convert("kifak") }
    #expect(text == nil)  // the keyboard then uses its own rules
    #expect(ms >= limit - 50 && ms < limit + 1_000, "gave up after \(ms) ms, limit \(limit) ms")
}

@Test func aServiceThatCrashesIsReachedAgainOnTheNextMessage() {
    let server = FakeServer([.crash, .answer])
    let client = server.client()
    #expect(client.convert("kifak") == nil)  // the link ended: rules in the keyboard
    #expect(client.convert("kifak") == "كيفك")  // a new link, a working service
    #expect(server.connections == 2)
}
