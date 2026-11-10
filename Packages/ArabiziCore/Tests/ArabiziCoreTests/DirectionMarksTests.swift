import Testing
@testable import ArabiziCore

@Test func mixedTextIsWrappedRightToLeft() {
    #expect(DirectionMarks.marked("ok منشوف meeting") == "\u{200F}\u{202B}ok منشوف meeting\u{202C}")
}

@Test func textInOneScriptIsLeftAlone() {
    #expect(DirectionMarks.marked("منشوف بكرا") == "منشوف بكرا")
    #expect(DirectionMarks.marked("see you") == "see you")
}

@Test func markingTwiceGivesTheSameText() {
    let once = DirectionMarks.marked("ok منشوف")
    #expect(DirectionMarks.marked(once) == once)
    #expect(DirectionMarks.removed(once) == "ok منشوف")
}

@Test func upStartsOnTheWordTheModelWasLeastSureOf() {
    let suggester = Suggester(candidates: { _, _ in ["x"] },
                              align: { latin, _ in latin.indices.map { $0..<($0 + 1) } },
                              record: { _ in }, confidence: { _ in [0.9, 0.2, 0.8] })
    var c = Composer(convert: { $0.uppercased() }, suggester: suggester)
    for character in "ejet waraye ktir" { _ = c.handle(.text(String(character))) }
    #expect(c.handle(.arrowUp) == .suggest(marked: "EJET WARAYE KTIR", selected: 5..<11, candidates: ["x"],
                                           replacingLength: nil))
}

@Test func confidenceIsFoundByTheShownWordsWithOrWithoutMarks() {
    let confidences = WordConfidences()
    confidences.remember(DirectionMarks.marked("ok منشوف meeting"), [0.9, 0.3, 0.8])
    #expect(confidences.of("ok  منشوف meeting") == [0.9, 0.3, 0.8])
    confidences.remember("شو عم", [0.5])  // one value for two words: not kept
    #expect(confidences.of("شو عم") == nil)
}
