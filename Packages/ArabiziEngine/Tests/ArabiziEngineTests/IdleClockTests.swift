import Foundation
import Testing
@testable import ArabiziEngine

private final class FakeTime: @unchecked Sendable {
    var instant = ContinuousClock.now
}

@Test func theEngineIsIdleOnlyAfterTheLimitWithoutRequests() {
    let time = FakeTime()
    let clock = IdleClock(limit: .seconds(60)) { time.instant }
    time.instant += .seconds(59)
    #expect(!clock.isIdle)
    time.instant += .seconds(2)
    #expect(clock.isIdle)
    clock.touch()  // a request: the idle time starts again
    #expect(!clock.isIdle)
    time.instant += .seconds(61)
    #expect(clock.isIdle)
}

@Test func theDefaultLimitIsHalfAnHour() {
    #expect(IdleClock.limit == .seconds(1_800))
}
