import Foundation
import Testing
@testable import ArabiziCore

private func composer() -> Composer {
    Composer(convert: { "<" + $0 + ">" })
}

private func type(_ text: String, into composer: inout Composer) {
    for character in text {
        _ = composer.handle(.text(String(character)))
    }
}

@Test func typingShowsLatinMarkedText() {
    var c = composer()
    #expect(c.handle(.text("k")) == .update(marked: "k"))
    #expect(c.handle(.text("i")) == .update(marked: "ki"))
}

@Test func enterConvertsWithoutSendingThenSecondEnterSends() {
    var c = composer()
    type("shu 3am", into: &c)
    #expect(c.handle(.enter) == .commit("<shu 3am>"))
    #expect(c.buffer.isEmpty)
    #expect(c.handle(.enter) == .pass)
}

private func suggestingComposer() -> Composer {
    let suggester = Suggester(candidates: { shown, _ in shown == "BET" ? ["بيت", "بيتي"] : [] },
                              align: { latin, shown in latin.count == shown.count ? latin.indices.map { $0..<($0 + 1) } : [] },
                              record: { _ in })
    return Composer(convert: { $0.uppercased() }, suggester: suggester)
}

@Test func upWhileTypingFixesAWordBeforeAnythingIsConverted() {
    var c = suggestingComposer()
    type("el bet", into: &c)
    #expect(c.handle(.arrowUp) == .suggest(marked: "EL BET", selected: 3..<6, candidates: ["بيت", "بيتي"],
                                           replacingLength: nil))
    #expect(c.handle(.text("2")) == .commit(DirectionMarks.marked("EL بيتي")))  // the fix and the rest, committed together
    #expect(c.lastConversion == Conversion(latin: "el bet", converted: DirectionMarks.marked("EL بيتي")))  // ⌘Z still brings it back
}

@Test func theTypedSentenceShowsWhereTheSelectedWordCameFrom() {
    var c = suggestingComposer()
    #expect(c.typedSentence == nil)  // nothing shown yet
    type("shu el bet", into: &c)
    _ = c.handle(.arrowUp)           // on the last word, BET
    #expect(c.typedSentence?.text == "shu el bet")
    #expect(c.typedSentence?.selected == 7..<10)
    _ = c.handle(.arrowRight)        // the word before it (right to left), EL
    #expect(c.typedSentence?.selected == 4..<6)
    _ = c.handle(.escape)
    #expect(c.typedSentence == nil)
}

@Test func aWordFromTwoTypedWordsHighlightsBoth() {
    let suggester = Suggester(candidates: { _, _ in ["x"] },
                              align: { _, _ in [0..<1, 1..<3] },  // SHU from "shu", ELBET from "el bet"
                              record: { _ in })
    var c = Composer(convert: { $0.uppercased().replacingOccurrences(of: "EL ", with: "EL") }, suggester: suggester)
    type("shu el bet", into: &c)
    _ = c.handle(.arrowUp)
    #expect(c.typedSentence?.selected == 4..<10)
}

@Test func suggestionsStartOnTheWordThatLooksWrong() {
    let suggester = Suggester(candidates: { _, _ in ["x"] },
                              align: { latin, _ in latin.indices.map { $0..<($0 + 1) } },
                              record: { _ in }, doubtful: { _, latin in latin == "waraye" })
    var c = Composer(convert: { $0.uppercased() }, suggester: suggester)
    type("ejet waraye ktir", into: &c)
    #expect(c.handle(.arrowUp) == .suggest(marked: "EJET WARAYE KTIR", selected: 5..<11, candidates: ["x"],
                                           replacingLength: nil))
}

@Test func leavingTheFixBeforeSendingGoesBackToTheLatin() {
    var c = suggestingComposer()
    type("el bet", into: &c)
    _ = c.handle(.arrowUp)
    #expect(c.handle(.escape) == .update(marked: "el bet"))
    _ = c.handle(.arrowUp)
    #expect(c.handle(.text("e")) == .update(marked: "el bete"))  // a letter keeps typing
    _ = c.handle(.arrowUp)
    #expect(c.handle(.backspace) == .update(marked: "el bet"))
    #expect(!c.isSuggesting)
    var empty = composer()
    #expect(empty.handle(.arrowUp) == .pass)  // nothing typed: the app's own ↑
}

@Test func escapeCommitsLatinUnchanged() {
    var c = composer()
    type("ok", into: &c)
    #expect(c.handle(.escape) == .commit("ok"))
    #expect(c.handle(.escape) == .pass)
}

@Test func backspaceEditsTheBufferThenPassesThrough() {
    var c = composer()
    type("ab", into: &c)
    #expect(c.handle(.backspace) == .update(marked: "a"))
    #expect(c.handle(.backspace) == .update(marked: ""))
    #expect(c.handle(.backspace) == .pass)
}

@Test func leadingSpaceIsNotComposed() {
    var c = composer()
    #expect(c.handle(.text(" ")) == .pass)
    type("a", into: &c)
    #expect(c.handle(.text(" ")) == .update(marked: "a "))
}

@Test func otherKeysCommitLatinAndPass() {
    var c = composer()
    type("hi", into: &c)
    #expect(c.handle(.other) == .commitAndPass("hi"))
    #expect(c.handle(.other) == .pass)
}

@Test func secureInputNeverComposes() {
    var c = composer()
    let secure = Context(secureInput: true)
    #expect(c.handle(.text("p"), context: secure) == .pass)
    type("ab", into: &c)
    #expect(c.handle(.text("c"), context: secure) == .commitAndPass("ab"))
    #expect(c.buffer.isEmpty)
}

@Test func focusLossCommitsLatinNotConverted() {
    var c = composer()
    #expect(c.flush() == nil)
    type("kifak", into: &c)
    #expect(c.flush() == "kifak")
    #expect(c.buffer.isEmpty)
}

// MARK: - Undo a conversion (⌘Z) and convert a selection (⌥Enter)

private let cursorUnmoved = Context(cursorAtLastConversion: true)

@Test func undoRightAfterConversionRestoresUnderlinedLatin() {
    var c = composer()
    type("shu", into: &c)
    #expect(c.handle(.enter) == .commit("<shu>"))
    #expect(c.handle(.undo, context: cursorUnmoved) == .restore(marked: "shu", replacingLength: 5))
    #expect(c.buffer == "shu")
    #expect(c.handle(.enter) == .commit("<shu>"))  // and it can be converted again
}

@Test func restoredTextCanBeEditedOrKeptInLatin() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    _ = c.handle(.undo, context: cursorUnmoved)
    #expect(c.handle(.backspace) == .update(marked: "sh"))
    #expect(c.handle(.escape) == .commit("sh"))
}

@Test func undoIsTheAppsOwnWhenTheCursorMoved() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    #expect(c.handle(.undo, context: Context(cursorAtLastConversion: false)) == .pass)
}

@Test func undoOnlyWorksForTheVeryNextKey() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    #expect(c.handle(.enter) == .pass)  // the app sends the message
    #expect(c.handle(.undo, context: cursorUnmoved) == .pass)
}

@Test func secondUndoIsTheAppsOwn() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    _ = c.handle(.undo, context: cursorUnmoved)
    _ = c.handle(.escape)
    #expect(c.handle(.undo, context: cursorUnmoved) == .pass)
}

@Test func undoWhileComposingCommitsLatinAndPasses() {
    var c = composer()
    type("ab", into: &c)
    #expect(c.handle(.undo, context: cursorUnmoved) == .commitAndPass("ab"))
}

@Test func optionEnterConvertsTheSelectionAndCanBeUndone() {
    var c = composer()
    let selection = Context(selectedText: "kifak shu")
    #expect(c.handle(.convertSelection, context: selection) == .replaceSelection("<kifak shu>"))
    #expect(c.handle(.undo, context: cursorUnmoved) == .restore(marked: "kifak shu", replacingLength: 11))
}

@Test func optionEnterWithNothingToConvertIsSwallowedNotPassed() {
    // Passing it on would let the app replace the selection with a new line (found in manual testing).
    var c = composer()
    #expect(c.handle(.convertSelection) == .consume)
    #expect(c.handle(.convertSelection, context: Context(selectedText: "100 $")) == .consume)
}

@Test func optionEnterWhileComposingActsLikeEnter() {
    var c = composer()
    type("shu", into: &c)
    #expect(c.handle(.convertSelection, context: Context(selectedText: "ignored")) == .commit("<shu>"))
}

@Test func passwordFieldsForgetTheLastConversion() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    _ = c.handle(.text("x"), context: Context(secureInput: true))
    #expect(c.handle(.undo, context: cursorUnmoved) == .pass)
}

@Test func focusLossForgetsTheLastConversion() {
    var c = composer()
    type("shu", into: &c)
    _ = c.handle(.enter)
    _ = c.flush()
    #expect(c.handle(.undo, context: cursorUnmoved) == .pass)
}

@Test func aReadyConversionIsUsedInsteadOfConvertingAgain() {
    let calls = Counter()
    var composer = Composer(convert: { calls.add(); return "converted:" + $0 },
                            ready: { $0 == "kifak" ? "كيفك" : nil })
    for character in "kifak" { _ = composer.handle(.text(String(character))) }
    #expect(composer.handle(.enter) == .commit("كيفك"))  // from the preview
    #expect(calls.value == 0)
    #expect(composer.lastConversion == Conversion(latin: "kifak", converted: "كيفك"))  // ⌘Z still works
    for character in "kifak2" { _ = composer.handle(.text(String(character))) }  // text changed since: converted now
    #expect(composer.handle(.enter) == .commit("converted:kifak2"))
    #expect(calls.value == 1)
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
