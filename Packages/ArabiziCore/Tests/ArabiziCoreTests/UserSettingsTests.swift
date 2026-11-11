import Foundation
import Testing
@testable import ArabiziCore

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "harfi-settings-\(UUID().uuidString)")
        .appending(path: "settings.json")
}

@Test func settingsDefaultToFasterPreviewOn() {
    #expect(UserSettings().fasterPreview && UserSettings().livePreview)
    #expect(UserSettings.read(temporaryFile()).fasterPreview)  // no file
}

@Test func settingsAreWrittenAndReadBack() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var settings = UserSettings()
    settings.fasterPreview = false
    settings.livePreview = false
    try settings.write(to: file)  // makes the folder
    #expect(UserSettings.read(file) == settings)
}

@Test func aBrokenFileOrAMissingKeyMeansTheDefaults() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file)
    #expect(UserSettings.read(file) == UserSettings())
    try Data(#"{"somethingNewer": 3}"#.utf8).write(to: file)
    #expect(UserSettings.read(file) == UserSettings())
}

@Test func theKeyboardReadsTheFileAndWithoutOneUsesTheDefaults() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var settings = UserSettings()
    settings.fasterPreview = false
    try settings.write(to: file)
    #expect(UserSettingsFile(file: file).current.fasterPreview == false)
    #expect(UserSettingsFile(file: nil).current == UserSettings())
}

private func fix(_ latin: String, _ chosen: String, day: Int = 0) -> Correction {
    Correction(latin: latin, chosen: chosen, rejected: "x", date: Date(timeIntervalSince1970: Double(day) * 86_400))
}

@Test func yourWordsCountsEachSpellingAndListsHabits() {
    let corrections = [fix("Sawa", "سوا"), fix("sawa", "سوا", day: 1), fix("sawa", "سوا", day: 2), fix("heik", "هيك")]
    let words = YourWords(corrections: corrections, refused: [Habit(latin: "tab", spelling: "طب")])
    #expect(words.fixes == 4)
    #expect(words.words == [YourWords.Word(latin: "sawa", arabic: "سوا", times: 3),
                            YourWords.Word(latin: "heik", arabic: "هيك", times: 1)])
    #expect(words.habits == [Habit(latin: "sawa", spelling: "سوا")])  // 3 picks on 2 days or more
    #expect(words.refused == [Habit(latin: "tab", spelling: "طب")])
    #expect(words.lines == "fixes\t4\nhabit\tsawa\tسوا\nrefused\ttab\tطب\nword\tsawa\tسوا\t3\nword\theik\tهيك\t1")
}

@Test func aRefusedHabitIsNotInForce() {
    let corrections = [fix("sawa", "سوا"), fix("sawa", "سوا", day: 1), fix("sawa", "سوا", day: 2)]
    let words = YourWords(corrections: corrections, refused: [Habit(latin: "sawa", spelling: "سوا")])
    #expect(words.habits.isEmpty && words.refused.count == 1)
    #expect(YourWords(corrections: [], refused: []).lines == "fixes\t0")
}
