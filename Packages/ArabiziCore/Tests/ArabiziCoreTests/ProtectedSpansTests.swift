import Testing
@testable import ArabiziCore

@Test(arguments: [
    ("shuf www.lau.edu", "shuf ⟦0⟧", ["www.lau.edu"]),
    ("shuf https://lau.edu.lb/x?y=1.", "shuf ⟦0⟧.", ["https://lau.edu.lb/x?y=1"]),  // the full stop is not the link's
    ("ab3atle 3a rami@lau.edu.lb", "ab3atle 3a ⟦0⟧", ["rami@lau.edu.lb"]),
    ("@rami, #lebanon!", "⟦0⟧, ⟦1⟧!", ["@rami", "#lebanon"]),
    ("b3at 100$", "b3at ⟦0⟧", ["100$"]),
    ("$100 w 50%", "⟦0⟧ w ⟦1⟧", ["$100", "50%"]),
    ("ntla2a 2pm?", "ntla2a ⟦0⟧?", ["2pm"]),
    ("3al 7:30", "3al ⟦0⟧", ["7:30"]),
    // Emoji stay in the text (ADR 0025); a keycap's digit is not a number of its own.
    ("hahaha 😂😂 tamem 👍🏽", "hahaha 😂😂 tamem 👍🏽", []),
    ("🇱🇧❤️", "🇱🇧❤️", []),
    ("1️⃣ w 2️⃣", "1️⃣ w 2️⃣", []),
])
func spansAreProtected(text: String, masked: String, spans: [String]) {
    let protected = ProtectedSpans.protect(text)
    #expect(protected.masked == masked)
    #expect(protected.spans == spans)
}

@Test(arguments: ["3am", "7elo", "2alle", "w2", "3a", "kifak #1 3am", "ma3'", "8ayr"])
func digitsInsideWordsAreLetters(text: String) {
    // "#1" is a hashtag; every other digit here is a letter of an Arabizi word.
    let protected = ProtectedSpans.protect(text)
    #expect(protected.masked.contains("3am") || protected.masked == text)
    #expect(!protected.spans.contains { $0.contains(where: \.isNumber) && !$0.hasPrefix("#") })
}

@Test(arguments: [
    "shuf www.lau.edu, @rami #lebanon 😂",
    "b3at 100$ la rami@lau.edu.lb 3al 7:30 aw 2pm 👍🏽🇱🇧",
    "⟦0⟧ already has brackets ⟧",
    "",
    "bas 3arabe",
])
func roundTripGivesTheTextBack(text: String) {
    let protected = ProtectedSpans.protect(text)
    #expect(ProtectedSpans.restore(protected.masked, spans: protected.spans) == text)
}

@Test func restoreAfterTheModelConverted() {
    let protected = ProtectedSpans.protect("b3atlak 100$ 3a www.x.com 😂")
    #expect(protected.masked == "b3atlak ⟦0⟧ 3a ⟦1⟧ 😂")
    let model = "بعتلك ⟦0⟧ ع ⟦1⟧ 😂"
    #expect(ProtectedSpans.restore(model, spans: protected.spans) == "بعتلك 100$ ع www.x.com 😂")
}

@Test(arguments: [
    "بعتلك ⟦0⟧",  // one placeholder lost
    "بعتلك ⟦0⟧ ⟦0⟧ ⟦1⟧",  // repeated
    "بعتلك ⟦0⟧ ⟦1⟧ ⟦2⟧",  // invented
    "بعتلك ⟦0⟧ ⟦+1⟧",  // not a plain number
    "بعتلك ⟦0⟧ ⟦01⟧",
    "بعتلك ⟦0⟧ ⟦1",  // unclosed
    "بعتلك ⟦0⟧ ⟧ ⟦1⟧",  // stray bracket
])
func restoreRejectsBadPlaceholders(output: String) {
    #expect(ProtectedSpans.restore(output, spans: ["100$", "😂"]) == nil)
}
