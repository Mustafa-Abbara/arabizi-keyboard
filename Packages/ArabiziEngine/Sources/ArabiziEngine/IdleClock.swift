import Foundation

/// When an engine process has gone unused long enough to quit and give its memory back (about 1 GB with the model
/// loaded; it is started again on the next request). The Mac's XPC service uses it; harfi-engine on Windows has the
/// same 30-minute rule.
public final class IdleClock: @unchecked Sendable {  // `lastUse` is behind `lock`
    public static let limit: Duration = .seconds(30 * 60)
    private let lock = NSLock()
    private let now: @Sendable () -> ContinuousClock.Instant
    private let limit: Duration
    private var lastUse: ContinuousClock.Instant

    public init(limit: Duration = IdleClock.limit, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.limit = limit
        self.now = now
        lastUse = now()
    }

    /// A request came in (or finished): the idle time starts again.
    public func touch() {
        lock.withLock { lastUse = now() }
    }

    /// True when nothing has asked for longer than the limit.
    public var isIdle: Bool {
        lock.withLock { now() - lastUse > limit }
    }
}
