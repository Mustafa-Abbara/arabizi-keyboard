import Testing
@testable import ArabiziCore

// The cursor inside the text being typed (Windows: `editsInPlace`). ← → and a click move it instead of letting go of
// the sentence; letters and Backspace act where it is; Enter still converts the whole text.

private func editing(_ typed: String) -> Composer {
    var c = Composer(convert: { "<" + $0 + ">" })
    c.editsInPlace = true
    for character in typed { _ = c.handle(.text(String(character))) }
    return c
}

@Test func leftKeepsTheSentenceAndMovesTheCursor() {
    var c = editing("kifak")
    #expect(c.handle(.arrowLeft) == .update(marked: "kifak"))
    #expect(c.caret == 4)
    #expect(c.buffer == "kifak")
}

@Test func aLetterGoesWhereTheCursorIs() {
    var c = editing("kfak")
    for _ in 0..<3 { _ = c.handle(.arrowLeft) }   // k|fak
    #expect(c.handle(.text("i")) == .update(marked: "kifak"))
    #expect(c.caret == 2)
    #expect(c.handle(.enter) == .commit("<kifak>"))
}

@Test func backspaceRemovesTheLetterBeforeTheCursor() {
    var c = editing("kiifak")
    for _ in 0..<3 { _ = c.handle(.arrowLeft) }   // kii|fak
    #expect(c.handle(.backspace) == .update(marked: "kifak"))
    #expect(c.caret == 2)
}

@Test func atTheStartLeftAndBackspaceChangeNothing() {
    var c = editing("ya")
    _ = c.handle(.arrowLeft)
    _ = c.handle(.arrowLeft)
    #expect(c.handle(.arrowLeft) == .consume)
    #expect(c.handle(.backspace) == .consume)
    #expect(c.buffer == "ya")
}

@Test func rightGoesBackToTheEndThenHandsTheTextOver() {
    var c = editing("ya")
    _ = c.handle(.arrowLeft)
    #expect(c.handle(.arrowRight) == .update(marked: "ya"))
    #expect(c.caret == 2)
    #expect(c.handle(.arrowRight) == .commitAndPass("ya"))  // at the end, as before
}

@Test func aClickInsideTheTextMovesTheCursor() {
    var c = editing("shu 3am")
    let moved1 = c.moveCaret(toUTF16: 3)
    #expect(moved1)
    #expect(c.caret == 3)
    _ = c.handle(.text("e"))
    #expect(c.buffer == "shue 3am")
    let moved2 = c.moveCaret(toUTF16: 99)
    #expect(!moved2)
}

@Test func aNewSentenceStartsWithTheCursorAtTheEnd() {
    var c = editing("ya")
    _ = c.handle(.arrowLeft)
    _ = c.handle(.enter)
    _ = c.handle(.text("k"))
    #expect(c.caret == 1)
}

@Test func withoutEditsInPlaceLeftHandsTheTextOverAsBefore() {
    var c = Composer(convert: { $0 })
    for character in "kifak" { _ = c.handle(.text(String(character))) }
    #expect(c.handle(.arrowLeft) == .commitAndPass("kifak"))
    let moved3 = c.moveCaret(toUTF16: 1)
    #expect(!moved3)
}

@Test func anEmojiIsOneStepForTheCursor() {
    var c = editing("ya😂")
    _ = c.handle(.arrowLeft)
    #expect(c.caret == 2)                          // before the emoji (two UTF-16 units)
    let moved4 = c.moveCaret(toUTF16: 3)
    #expect(moved4)               // inside the emoji: its start
    #expect(c.caret == 2)
}
