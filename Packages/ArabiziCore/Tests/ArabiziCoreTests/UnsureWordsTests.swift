import Foundation
import Testing
@testable import ArabiziCore

// Unsure words (ADR 0034): the model's words never written in training.

private let unsure = UnsureWords(known: ["كيفك", "يا", "صبية", "ست"], dictionary: ["set": "ست", "Sabiye": "صبية"])
private let align: @Sendable ([String], [String]) -> [Range<Int>?] = { latin, shown in
    WordAlignment.align(latin: latin, shown: shown, rules: fakeRules)
}

@Test func unsureWordsAreArabicWordsNeverWrittenInTraining() {
    #expect(unsure.isUnsure("سيت؟"))
    #expect(!unsure.isUnsure("كيفك،"))  // known, punctuation ignored
    #expect(!unsure.isUnsure("hello"))  // Latin is not this question
    #expect(!unsure.isUnsure("12"))
    #expect(unsure.unsure(in: "كيفك يا سيت!") == ["سيت"])
}

@Test func anUnsureWordTakesTheDictionarySpellingOfItsTypedWord() {
    #expect(unsure.swap(latin: "kifak ya set!", converted: "كيفك يا سيت!", align: align) == "كيفك يا ست!")
    #expect(unsure.swap(latin: "kifak ya sabiye", converted: "كيفك يا سابية", align: align) == "كيفك يا صبية")
}

@Test func knownWordsAndWordsOutsideTheDictionaryAreLeftAlone() {
    #expect(unsure.swap(latin: "kifak ya sabiye", converted: "كيفك يا صبية", align: align) == "كيفك يا صبية")
    #expect(unsure.swap(latin: "kifak ya flfoul", converted: "كيفك يا فلوفول", align: align) == "كيفك يا فلوفول")
}
