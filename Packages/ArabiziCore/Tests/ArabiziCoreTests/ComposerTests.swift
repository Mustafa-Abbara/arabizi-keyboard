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
    #expect(c.handle(.text("p"), secureInput: true) == .pass)
    type("ab", into: &c)
    #expect(c.handle(.text("c"), secureInput: true) == .commitAndPass("ab"))
    #expect(c.buffer.isEmpty)
}

@Test func focusLossCommitsLatinNotConverted() {
    var c = composer()
    #expect(c.flush() == nil)
    type("kifak", into: &c)
    #expect(c.flush() == "kifak")
    #expect(c.buffer.isEmpty)
}
