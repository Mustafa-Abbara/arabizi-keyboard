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
