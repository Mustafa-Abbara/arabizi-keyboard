import Foundation
import Testing
@testable import ArabiziCore

let englishGuard = EnglishGuard(rulesDirectory: rulesDirectory, rules: committedConverter)!  // swiftlint:disable:this force_unwrapped_optional

@Test(arguments: [
    "(if the model doesnt know the word what does it do)",
    "why is it converting the sentence in paran to arabic (also the one after)",
    "The meeting is at 5 pm tomorrow, can you send me the slides?",
    "I don't think that this is a good idea",
    "what are you doing after the class",
    "Thanks, see you at the office tomorrow.",
    "this is not what we want",
    "please check https://example.com/page and tell me what you think",
])
func plainEnglishIsRecognised(_ text: String) {
    #expect(englishGuard.isEnglish(text), "\(text)")
}

@Test(arguments: [
    "kifak, shu 3am ta3mel?",
    "ba3atlak el report w the deadline is tomorrow",
    "the meeting is at 5 pm, kifak enta?",
    "shu hal awareness l m2ayar",
    "ana ma bkhaf men el hala2",
    "bas the thing is eno ma fi wa2et",
    "yalla bye",
    "the",
    "meeting tomorrow",
    "كيفك the meeting is at five",
    "😂😂😂",
    "ok",
])
func arabiziAndShortTextIsNotEnglish(_ text: String) {
    #expect(!englishGuard.isEnglish(text), "\(text)")
}

@Test func aWordLikeAnArabiziOneNeedsMoreThanEnglishWordsAroundIt() {
    let guardWithArabizi = EnglishGuard(functionWords: ["the", "is", "this"], arabizi: ["bas"])
    #expect(guardWithArabizi.isEnglish("this is the thing"))
    #expect(!guardWithArabizi.isEnglish("this is bas the thing"))
    #expect(!guardWithArabizi.isEnglish("this is 3am the thing"))
    #expect(guardWithArabizi.isEnglish("this is 20 the thing"))  // a bare number is not Arabizi
}

@Test func apostrophesAndCaseDoNotMatter() {
    let guardOnly = EnglishGuard(functionWords: ["doesnt", "the", "it"], arabizi: [])
    #expect(guardOnly.isEnglish("It DOESN'T matter the"))
    #expect(guardOnly.isEnglish("it doesn’t matter, the"))
}

@Test func theGuardIsOffWithoutItsFile() {
    #expect(EnglishGuard(rulesDirectory: rulesDirectory.appending(path: "nowhere"), rules: committedConverter) == nil)
}
