import Testing
@testable import ArabiziCore

let checks = OutputChecks()

func check(_ input: String, _ output: String) -> Result<String, OutputChecks.Failure> {
    checks.check(output, for: ProtectedSpans.protect(input))
}

@Test(arguments: [
    ("kifak, shu 3am ta3mel?", "كيفك، شو عم تعمل؟", "كيفك، شو عم تعمل؟"),
    ("b3at 100$ 3a www.x.com 😂", "بعت ⟦0⟧ ع ⟦1⟧ ⟦2⟧", "بعت 100$ ع www.x.com 😂"),  // spans put back
    ("el meeting ba3d shway", "ال meeting بعد شوي", "ال meeting بعد شوي"),  // English kept from the input
    ("bel LAU", "بال lau", "بال lau"),  // case does not matter
    ("w el bet", "والبيت", "والبيت"),  // 3 words to 1: allowed by the slack
    ("kifak", "\n كيفك \n", "كيفك"),  // surrounding whitespace dropped
])
func goodAnswersPass(input: String, output: String, result: String) {
    #expect(check(input, output) == .success(result))
}

@Test func emptyAnswerFails() {
    #expect(check("kifak", "  \n") == .failure(.empty))
}

@Test(arguments: ["بعت", "بعت ⟦0⟧ ⟦0⟧", "بعت ⟦1⟧", "بعت ⟦0⟧ ⟧"])
func placeholderMistakesFail(output: String) {
    #expect(check("b3at 100$", output) == .failure(.placeholders))
}

@Test func latinNotInTheInputFails() {
    #expect(check("kifak", "كيفك how are you") == .failure(.newLatin(["how", "are", "you"])))
    #expect(check("el meeting", "الmeeting") == .failure(.newLatin(["الmeeting"])))  // glued to Arabic
    #expect(check("shu 3am ta3mel", "شو 3am تaعمل") == .failure(.newLatin(["تaعمل"])))  // half converted
}

@Test func wrongLengthFails() {
    let long = "ana ktir ta3ban lyom w bade nem bakkir la2an bokra 3ande sh8l"  // 12 words
    #expect(check(long, "تعبان") == .failure(.wordCount(output: 1, input: 12)))
    #expect(check("kifak ya", "كيفك يا حبيبي شو عم تعمل اليوم بالبيت") == .failure(.wordCount(output: 8, input: 2)))
    #expect(check("kifak ya", "كيفك يا حبيبي شو عم") == .success("كيفك يا حبيبي شو عم"))  // 2 × 2 + 1 = 5 is the most
}
