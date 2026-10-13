import Testing
@testable import ArabiziCore

@Test(arguments: [
    ("kifak", "كيفك"),
    ("shu", "شو"),
    ("3am", "عم"),
    ("ta3mel", "تعمل"),
    ("mni7", "منيح"),
    ("ktir", "كتير"),
    ("ana", "أنا"),
    ("hayda", "هيدا"),
    ("bade", "بدي"),
    ("7abibi", "حبيبي"),
])
func commonWords(arabizi: String, arabic: String) {
    #expect(ToyTransliterator.convert(arabizi) == arabic)
}

@Test func sentenceWithPunctuation() {
    #expect(ToyTransliterator.convert("kifak, shu 3am ta3mel?") == "كيفك، شو عم تعمل؟")
}

@Test func standaloneNumbersAndSymbolsAreKept() {
    #expect(ToyTransliterator.convert("b3at 100$") == "بعت 100$")
    #expect(ToyTransliterator.convert("10:30") == "10:30")
}

@Test func spacesArePreserved() {
    #expect(ToyTransliterator.convert("shu  3am ") == "شو  عم ")
}
