import Foundation
import Testing
@testable import ArabiziCore

let chatAbbreviations = ChatAbbreviations(rulesDirectory: rulesDirectory)!  // swiftlint:disable:this force_unwrapped_optional

@Test func chatAbbreviationsAreFoundWithoutThePunctuationAroundThem() {
    let text = "IDK, b3atlak 100$ lol!"
    #expect(chatAbbreviations.ranges(in: text).map { String(text[$0]) } == ["IDK", "lol"])
}

@Test(arguments: [
    ("idk shu badak tbh", "إيدك شو بدك تبح", "idk شو بدك tbh"),  // one word each
    ("Yea hek 3am ul", "يا ياه هيك عم قول", "Yea هيك عم قول"),  // two words from one abbreviation
    ("friday idk eza btezbat", "friday إيدك إذا بتزبط", "friday idk إذا بتزبط"),
    ("kifak", "كيفك", "كيفك"),  // nothing to put back
])
func wordsTheModelWroteForAnAbbreviationArePutBack(typed: String, answer: String, expected: String) {
    #expect(chatAbbreviations.restore(in: answer, typed: typed, rules: committedConverter) == expected)
}

@Test(arguments: ["idkk", "lolz", "ya", "min", "fyi", "dm", "u"])
func onlyListedWholeWordsAreKept(_ word: String) {
    #expect(chatAbbreviations.ranges(in: "\(word) shu").isEmpty, "\(word)")
}

@Test func theRulesKeepChatAbbreviationsAsTyped() {
    let converted = chatAbbreviations.convert("w lol shu 3am ta3mel tbh", with: committedConverter)
    #expect(converted.contains("lol") && converted.hasSuffix(" tbh"))
    #expect(converted.contains(committedConverter.convert("shu 3am ta3mel")))
    #expect(chatAbbreviations.convert("kifak", with: committedConverter) == committedConverter.convert("kifak"))
}

@Test func withoutTheFileNothingIsKept() {
    #expect(ChatAbbreviations(rulesDirectory: rulesDirectory.appending(path: "nowhere")) == nil)
}
