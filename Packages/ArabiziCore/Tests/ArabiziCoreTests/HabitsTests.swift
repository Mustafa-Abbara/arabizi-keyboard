#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto: the same API on Windows and Linux (ADR 0032)
#endif
import Foundation
import Testing
@testable import ArabiziCore

// Learned habits (ADR 0027 step 2, ADR 0033): repeated corrections become the user's spelling of a word.

private let day: TimeInterval = 86_400
private let start = Date(timeIntervalSince1970: 2_000_000_000)
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func fix(_ latin: String, _ chosen: String, after days: Double) -> Correction {
    Correction(latin: latin, chosen: chosen, rejected: "فلوفول", date: start.addingTimeInterval(days * day))
}

@Test func threePicksOnTwoDaysMakeAHabit() {
    let twoDays = [fix("flfoul", "فليفلة", after: 0), fix("flfoul", "فليفلة", after: 0.1), fix("Flfoul", "فليفلة", after: 1)]
    #expect(Habits.learned(from: twoDays, calendar: utc) == [Habit(latin: "flfoul", spelling: "فليفلة")])
    let oneDay = [fix("flfoul", "فليفلة", after: 0), fix("flfoul", "فليفلة", after: 0.1), fix("flfoul", "فليفلة", after: 0.2)]
    #expect(Habits.learned(from: oneDay, calendar: utc).isEmpty)  // three picks, but all on one day
    let twoPicks = [fix("flfoul", "فليفلة", after: 0), fix("flfoul", "فليفلة", after: 1)]
    #expect(Habits.learned(from: twoPicks, calendar: utc).isEmpty)  // two days, but only two picks
}

@Test func onlyPicksSinceTheLastChangeOfMindCount() {
    let changed = [fix("flfoul", "فليفلة", after: 0), fix("flfoul", "فليفلة", after: 1), fix("flfoul", "فليفلة", after: 2),
                   fix("flfoul", "فلفل", after: 3)]
    #expect(Habits.learned(from: changed, calendar: utc).isEmpty)  // the newest pick disagrees: no habit
    let settled = changed + [fix("flfoul", "فلفل", after: 3.1), fix("flfoul", "فلفل", after: 4)]
    #expect(Habits.learned(from: settled, calendar: utc) == [Habit(latin: "flfoul", spelling: "فلفل")])
}

@Test func habitsAreAppliedToTheirWordsOnly() {
    let habits = [Habit(latin: "Sabiye!", spelling: "سابية"), Habit(latin: "el bet", spelling: "اللبيت")]
    let align: ([String], [String]) -> [Range<Int>?] = { latin, shown in
        WordAlignment.align(latin: latin, shown: shown, rules: fakeRules)
    }
    #expect(Habits.apply(habits, latin: "kifak ya sabiye?", converted: "كيفك يا صبية؟", align: align)
            == "كيفك يا سابية؟")  // punctuation kept
    #expect(Habits.apply(habits, latin: "kifak", converted: "كيفك", align: align) == "كيفك")
    #expect(Habits.apply([], latin: "sabiye", converted: "صبية", align: align) == "صبية")
}

@Test func refusedHabitsAreKeptSealedAndCanBeAllowedAgain() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = CorrectionStore(file: folder.appending(path: "corrections.bin"), key: SymmetricKey(size: .bits256),
                                now: { start })
    #expect(store.changed == nil)
    let habit = Habit(latin: "flfoul", spelling: "فليفلة")
    try store.refuse(habit)
    #expect(store.refused() == [habit])
    #expect(store.changed != nil)
    let bytes = try Data(contentsOf: folder.appending(path: "refused.bin"))
    #expect(String(decoding: bytes, as: UTF8.self).contains("flfoul") == false)  // not readable on disk
    try store.allow(habit)
    #expect(store.refused().isEmpty)
    try store.refuse(habit)
    try store.wipe()
    #expect(store.refused().isEmpty)
}
