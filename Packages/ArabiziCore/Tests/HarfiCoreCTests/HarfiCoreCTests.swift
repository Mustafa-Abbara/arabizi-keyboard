import ArabiziCore
import Foundation
import Testing
@testable import HarfiCoreC

// The C interface the Windows keyboard uses (ADR 0032): the same behaviour as the Mac keyboard, through JSON.

private let rules = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../data/rules")

private func call(_ function: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?, _ text: String) -> String {
    let result = text.withCString { function($0) }
    defer { harfi_free(result) }
    return result.map { String(cString: $0) } ?? ""
}

private func json(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
}

@Test func theCoreConvertsWithTheRulesAndLeavesEnglishAlone() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    #expect(call({ harfi_convert(core, $0) }, "shu 3am ta3mel") == "شو عم تعمل")
    let english = "this is not what we want"
    #expect(call({ harfi_convert(core, $0) }, english) == english)
    #expect(english.withCString { harfi_is_english(core, $0) } == 1)
    #expect("kifak".withCString { harfi_is_english(core, $0) } == 0)
}

@Test func aMissingRulesFolderGivesNoCore() {
    #expect("/no/such/folder".withCString { harfi_core_open($0) } == nil)
}

@Test func theComposerTypesConvertsAndFixesBeforeSending() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    let composer = try #require(harfi_composer_new(core))
    defer { harfi_composer_free(composer) }
    func key(_ request: String) -> [String: Any] { json(call({ harfi_composer_key(composer, $0) }, request)) }

    #expect(key(#"{"key":"text","text":"s"}"#)["effect"] as? String == "update")
    for letter in "hu 3am" { _ = key(#"{"key":"text","text":"\#(letter)"}"#) }
    #expect(call({ _ in harfi_composer_buffer(composer) }, "") == "shu 3am")
    let fix = key(#"{"key":"arrowUp"}"#)  // ↑ before sending: the Arabic with the last word selected
    #expect(fix["effect"] as? String == "suggest" && fix["marked"] as? String == "شو عم")
    #expect((fix["selected"] as? [Int]) == [3, 5])
    #expect(!(fix["candidates"] as? [String] ?? []).isEmpty)
    #expect(fix["word"] as? String == "عم")  // the word being fixed, shown first in the chip row
    let sent = key(#"{"key":"enter"}"#)
    #expect(sent["effect"] as? String == "commit" && sent["text"] as? String == "شو عم")
    #expect(key(#"{"key":"enter"}"#)["effect"] as? String == "pass")  // Enter again sends
}

@Test func passwordFieldsAndUnknownKeysPassThrough() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    let composer = try #require(harfi_composer_new(core))
    defer { harfi_composer_free(composer) }
    func key(_ request: String) -> String { json(call({ harfi_composer_key(composer, $0) }, request))["effect"] as? String ?? "" }
    #expect(key(#"{"key":"text","text":"a","secureInput":true}"#) == "pass")
    #expect(key(#"{"key":"teleport"}"#) == "pass")
    #expect(key("not json") == "pass")
}

@Test func thePreviewShowsFinishedWordsThenTheLatinTypedSince() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    func preview(_ text: String, whole: Bool = false) -> [String: Any] {
        json(call({ harfi_preview(core, $0, whole ? 1 : 0) }, text))
    }
    #expect(preview("shu 3am ta")["arabic"] as? [String] == ["شو", "عم"])
    #expect(preview("shu 3am ta")["latin"] as? String == "ta")
    #expect(preview("shu 3am ta3mel", whole: true)["arabic"] as? [String] == ["شو", "عم", "تعمل"])
    #expect(preview("shu 3am ta3mel", whole: true)["latin"] as? String == "")
    #expect(preview("shu el ")["arabic"] as? [String] == ["شو"])  // ال waits for its word
    #expect(preview("shu el ")["latin"] as? String == "el")
    #expect(preview("sh").isEmpty)  // nothing finished yet
    #expect(preview("12 ").isEmpty)  // no letters
}

@Test func fixingBeforeSendingKeepsThePreviewWords() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    let composer = try #require(harfi_composer_new(core))
    defer { harfi_composer_free(composer) }
    for letter in "shu 3am" { _ = call({ harfi_composer_key(composer, $0) }, #"{"key":"text","text":"\#(letter)"}"#) }
    let fix = json(call({ harfi_composer_key(composer, $0) }, #"{"key":"arrowUp"}"#))
    #expect(fix["fixingWords"] as? [String] == ["شو", "عم"])
    #expect(fix["fixingIndex"] as? Int == 1)
}

@Test func aThirdPickOnASecondDayBecomesAHabitThatCanBeRefused() throws {
    // An installed keyboard's folder (HarfiTIP.dll beside rules\), so the core keeps a record of picks.
    let keyboard = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let folder = keyboard.appending(path: "rules")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: keyboard) }
    for file in try FileManager.default.contentsOfDirectory(atPath: rules.path) where file.hasSuffix(".json") {
        try FileManager.default.copyItem(at: rules.appending(path: file), to: folder.appending(path: file))
    }
    FileManager.default.createFile(atPath: keyboard.appending(path: "HarfiTIP.dll").path, contents: Data())
    let core = try #require(folder.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    func typed(_ text: String, then last: String) -> [String: Any] {
        let composer = harfi_composer_new(core)
        defer { harfi_composer_free(composer) }
        for letter in text { _ = call({ harfi_composer_key(composer, $0) }, #"{"key":"text","text":"\#(letter)"}"#) }
        return json(call({ harfi_composer_key(composer, $0) }, last))
    }
    let usual = try #require(typed("flfoul", then: #"{"key":"enter"}"#)["text"] as? String)
    let fixUp = typed("flfoul", then: #"{"key":"arrowUp"}"#)
    let mine = try #require((fixUp["candidates"] as? [String])?.first { $0 != usual })

    // Two earlier fixes of flfoul to the same spelling, yesterday and the day before.
    let store = try #require(CorrectionStore.standard(folder: keyboard.appending(path: "words")))
    for days in [2.0, 1.0] {
        try store.record(Correction(latin: "flfoul", chosen: mine, rejected: usual, date: Date().addingTimeInterval(-days * 86_400)))
    }
    // The third, today: the reply announces the habit.
    let composer = try #require(harfi_composer_new(core))
    for letter in "flfoul" { _ = call({ harfi_composer_key(composer, $0) }, #"{"key":"text","text":"\#(letter)"}"#) }
    _ = call({ harfi_composer_key(composer, $0) }, #"{"key":"arrowUp"}"#)
    let picked = json(call({ harfi_composer_pick(composer, $0) }, mine))
    harfi_composer_free(composer)
    #expect(picked["text"] as? String == mine)
    #expect(picked["learnedLatin"] as? String == "flfoul" && picked["learnedSpelling"] as? String == mine)

    // From now on Enter and the preview write it the user's way.
    #expect(typed("flfoul", then: #"{"key":"enter"}"#)["text"] as? String == mine)
    #expect(json(call({ harfi_preview(core, $0, 1) }, "flfoul"))["arabic"] as? [String] == [mine])
    #expect(typed("flfoul", then: #"{"key":"enter"}"#)["learnedLatin"] == nil)  // announced once only

    // Refused: back to the usual spelling.
    "flfoul".withCString { latin in mine.withCString { harfi_habit_refuse(core, latin, $0) } }
    #expect(typed("flfoul", then: #"{"key":"enter"}"#)["text"] as? String == usual)
}

@Test func aClickedSpellingIsPickedLikeItsNumber() throws {
    let core = try #require(rules.path.withCString { harfi_core_open($0) })
    defer { harfi_core_close(core) }
    let composer = try #require(harfi_composer_new(core))
    defer { harfi_composer_free(composer) }
    for letter in "ma bade" { _ = call({ harfi_composer_key(composer, $0) }, #"{"key":"text","text":"\#(letter)"}"#) }
    let fix = json(call({ harfi_composer_key(composer, $0) }, #"{"key":"arrowUp"}"#))
    let offered = try #require((fix["candidates"] as? [String])?.first)
    let picked = json(call({ harfi_composer_pick(composer, $0) }, offered))
    #expect(picked["effect"] as? String == "commit")
    #expect((picked["text"] as? String)?.hasSuffix(offered) == true)
}
