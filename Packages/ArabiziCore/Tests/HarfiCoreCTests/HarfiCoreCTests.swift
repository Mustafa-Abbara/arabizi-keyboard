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
