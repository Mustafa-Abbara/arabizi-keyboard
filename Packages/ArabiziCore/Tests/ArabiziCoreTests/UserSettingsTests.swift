import Foundation
import Testing
@testable import ArabiziCore

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "harfi-settings-\(UUID().uuidString)")
        .appending(path: "settings.json")
}

@Test func settingsDefaultToFasterPreviewOn() {
    #expect(UserSettings().fasterPreview)
    #expect(UserSettings.read(temporaryFile()).fasterPreview)  // no file
}

@Test func settingsAreWrittenAndReadBack() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var settings = UserSettings()
    settings.fasterPreview = false
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
