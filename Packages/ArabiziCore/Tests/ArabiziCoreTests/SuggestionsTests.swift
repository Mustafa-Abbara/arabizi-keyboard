import CryptoKit
import Foundation
import Testing
@testable import ArabiziCore

let fakeRules: @Sendable (String) -> String = { latin in
    ["sabiye": "صبية", "kifak": "كيفك", "ya": "يا", "tawle": "طاولة", "w": "و", "el": "ال", "bet": "بيت"][latin] ?? latin
}

func dictionary(_ arabic: [String]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: arabic.enumerated().map { ("w\($0.offset)", $0.element) })
}

@Test func candidatesPutTheRulesFirstThenRealVariantsThenLatin() {
    let suggestions = Suggestions(dictionary: dictionary(["سبيه", "صبيه", "سابية"]), rules: fakeRules)
    let offered = suggestions.candidates(for: "سبية؟", latin: "sabiye")
    #expect(offered.first == "صبية")  // the rules' spelling of the typed word
    #expect(offered.contains("سابية") && offered.contains("سبيه"))  // a long vowel added; the ending
    #expect(offered.last == "sabiye")  // keep it in Latin
    #expect(!offered.contains("سبية"))  // never the word already shown
    #expect(!offered.contains("صبيه"))  // two edits away: not offered
    #expect(offered.count <= 5)
}

@Test func variantsCoverLongVowelsLettersAndEndings() {
    let variants = Suggestions.variants(of: "تولة")
    #expect(variants.contains("طولة"))  // ت -> ط
    #expect(variants.contains("تاولة"))  // long vowel added
    #expect(variants.contains("تلة"))  // long vowel dropped
    #expect(variants.contains("تولا"))  // ending
}

@Test func withoutALatinWordThereIsNoLatinCandidate() {
    let suggestions = Suggestions(dictionary: dictionary(["كيفيك"]), rules: fakeRules)
    #expect(suggestions.candidates(for: "كيفك", latin: nil) == ["كيفيك"])
}

@Test func theDictionaryIsReadFromTheLexiconFile() {
    let lexicon = Data(#"{"words": {"kifak": "كيفك", "2alb": "قلب"}, "keep_latin": []}"#.utf8)
    #expect(Suggestions.dictionary(lexicon: lexicon) == ["kifak": "كيفك", "2alb": "قلب"])
}

@Test func wordsTypedOneLetterDifferentlyOfferTheirArabicWhenItLooksAlike() {
    let suggestions = Suggestions(dictionary: [
        "sabiyeh": "صبيه", "sabaya": "صبايا", "sabiye2": "سابق",  // one letter off; the last looks nothing alike
        "sabiyeteh": "صبيتها",  // three letters off: not a neighbour
    ], rules: { _ in "" })
    #expect(suggestions.candidates(for: "صبية", latin: "sabiye") == ["صبيه", "sabiye"])
    #expect(!suggestions.candidates(for: "صبية", latin: "sabiye").contains("صبايا"))  // two letters off
}

@Test func alignmentIsByPositionWhenTheCountsMatch() {
    #expect(WordAlignment.align(latin: ["kifak", "ya", "sabiye"], shown: ["كيفك", "يا", "سبية"], rules: fakeRules)
            == [0..<1, 1..<2, 2..<3])
}

@Test func alignmentMatchesWordsWhenTheCountsDiffer() {
    // "w el bet" became one word; "kifak" and "sabiye" still line up.
    let shown = ["كيفك", "والبيت", "صبية"]
    let aligned = WordAlignment.align(latin: ["kifak", "w", "el", "bet", "sabiye"], shown: shown, rules: fakeRules)
    #expect(aligned[0] == 0..<1 && aligned[2] == 4..<5)
    // A word kept in Latin lines up with itself.
    #expect(WordAlignment.align(latin: ["shefet", "el", "video"], shown: ["شفت", "الvideo-not", "video"],
                                rules: fakeRules)[2] == 2..<3)
}

@Test func aShownWordCanComeFromARunOfTypedWords() {
    // The rules write a small word joined to the next one: الشر comes from "el shr", never from "el" alone.
    let rules: @Sendable (String) -> String = { ["el shr": "الشر", "el": "ال", "shr": "شر", "ma": "ما",
                                                  "byswa": "بيسوى", "w el bet": "والبيت"][$0] ?? $0 }
    #expect(WordAlignment.align(latin: ["el", "shr", "ma", "byswa"], shown: ["الشر", "ما", "بيسوى"], rules: rules)
            == [0..<2, 2..<3, 3..<4])
    #expect(WordAlignment.align(latin: ["w", "el", "bet"], shown: ["والبيت"], rules: rules) == [0..<3])
}

@Test func theStoreEncryptsKeepsAndExpiresCorrections() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "corrections.bin")
    let key = SymmetricKey(size: .bits256)
    let today = Date(timeIntervalSince1970: 2_000_000_000)
    let store = CorrectionStore(file: file, key: key, now: { today })
    let old = Correction(latin: "sabiye", chosen: "صبية", rejected: "سبية", date: today.addingTimeInterval(-31 * 86400))
    let new = Correction(latin: "tawle", chosen: "طاولة", rejected: "تاولة", date: today)
    try store.record(old)
    try store.record(new)
    #expect(store.all() == [new])  // older than 30 days: gone
    let bytes = try Data(contentsOf: file)
    #expect(String(decoding: bytes, as: UTF8.self).contains("tawle") == false)  // not readable on disk
    #expect(CorrectionStore(file: file, key: SymmetricKey(size: .bits256)).all().isEmpty)  // wrong key: nothing
    try store.wipe()
    #expect(store.all().isEmpty)
}

@Test func theStandardStoreKeepsItsKeyBetweenStarts() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try #require(CorrectionStore.standard(folder: folder))
    try first.record(Correction(latin: "kifak", chosen: "كيفك", rejected: "كيفيك", date: Date()))
    let again = try #require(CorrectionStore.standard(folder: folder))
    #expect(again.all().map(\.latin) == ["kifak"])
    let mode = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "corrections.key").path)[.posixPermissions]
    #expect((mode as? NSNumber)?.intValue == 0o600)
}

// MARK: - the ⌥Tab flow in the Composer

final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Correction] = []
    var all: [Correction] { lock.withLock { items } }
    func add(_ c: Correction) { lock.withLock { items.append(c) } }
}

func suggestingComposer(_ recorded: Recorded) -> Composer {
    let converted = ["kifak ya sabiye": "كيفك يا سبية؟"]
    let suggester = Suggester(
        candidates: { shown, _ in
            ["سبية؟": ["صبية", "سابية", "sabiye"], "كيفك": ["كيفيك"]][shown] ?? []
        },
        align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: fakeRules) },
        record: { recorded.add($0) },
        now: { Date(timeIntervalSince1970: 0) })
    return Composer(convert: { converted[$0] ?? $0 }, suggester: suggester)
}

func typeAndConvert(_ composer: inout Composer, _ text: String) {
    for character in text { _ = composer.handle(.text(String(character))) }
    _ = composer.handle(.enter)
}

@Test func optionTabOffersSpellingsForTheLastWordAndANumberPicksOne() {
    let recorded = Recorded()
    var composer = suggestingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    let shown = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    let converted = "كيفك يا سبية؟"
    let lastWord = (("كيفك يا ") as String).utf16.count..<converted.utf16.count
    #expect(shown == .suggest(marked: converted, selected: lastWord, candidates: ["صبية", "سابية", "sabiye"],
                              replacingLength: converted.utf16.count))
    #expect(composer.handle(.text("1")) == .commit("كيفك يا صبية؟"))  // punctuation kept
    #expect(recorded.all == [Correction(latin: "sabiye", chosen: "صبية", rejected: "سبية",
                                        date: Date(timeIntervalSince1970: 0))])
    #expect(!composer.isSuggesting)
    // ⌘Z right after still brings the Latin back.
    #expect(composer.handle(.undo, context: Context(cursorAtLastConversion: true))
            == .restore(marked: "kifak ya sabiye", replacingLength: "كيفك يا صبية؟".utf16.count))
}

@Test func arrowsMoveBetweenWordsAndEscapeChangesNothing() {
    let recorded = Recorded()
    var composer = suggestingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    // ← goes to the next word in reading order: none after the last word, so the key is swallowed.
    #expect(composer.handle(.arrowLeft) == .consume)
    // → goes back one word at a time, also to a word with no candidates (it can still be spelled).
    #expect(composer.handle(.arrowRight) == .suggest(marked: "كيفك يا سبية؟", selected: 5..<7,
                                                     candidates: [], replacingLength: nil))
    #expect(composer.handle(.arrowRight) == .suggest(marked: "كيفك يا سبية؟", selected: 0..<4,
                                                     candidates: ["كيفيك"], replacingLength: nil))
    #expect(composer.handle(.arrowRight) == .consume)  // no word before the first
    #expect(composer.handle(.escape) == .commit("كيفك يا سبية؟"))
    #expect(recorded.all.isEmpty)
}

@Test func optionTabDoesNothingWhenTheCursorMovedOrNothingWasConverted() {
    var composer = suggestingComposer(Recorded())
    #expect(composer.handle(.suggest, context: Context(cursorAtLastConversion: true)) == .consume)
    typeAndConvert(&composer, "kifak ya sabiye")
    #expect(composer.handle(.suggest, context: Context(cursorAtLastConversion: false)) == .consume)
    // The conversion is kept, so ⌥Tab still works once the cursor is back.
    #expect(composer.lastConversion != nil)
}

@Test func optionTabOpensOnTheLastWordEvenWithoutCandidates() {
    var composer = suggestingComposer(Recorded())
    for character in "ya" { _ = composer.handle(.text(String(character))) }
    _ = composer.handle(.enter)  // converted to itself: no candidates for it
    #expect(composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
            == .suggest(marked: "ya", selected: 0..<2, candidates: [], replacingLength: 2))
    #expect(composer.isSuggesting)
}

@Test func typingALetterWhileSuggestingStartsANewWord() {
    var composer = suggestingComposer(Recorded())
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    #expect(composer.handle(.text("s")) == .commitAndCompose("كيفك يا سبية؟", marked: "s"))
    #expect(composer.buffer == "s")
}

@Test func oneEditApartCountsExactlyOneChange() {
    let one = { (a: String, b: String) in Suggestions.oneEditApart(Array(a), Array(b)) }
    #expect(one("sabiye", "sabiyeh") && one("sabiye", "sabiy") && one("sabiye", "sabiya"))
    #expect(!one("sabiye", "sabiye") && !one("sabiye", "sabaya") && !one("sabiye", "sabiyeteh"))
}

@Test func pastFixesForTheSameTypedWordComeFirst() {
    func fix(_ latin: String, _ chosen: String, _ day: Double) -> Correction {
        Correction(latin: latin, chosen: chosen, rejected: "سبية", date: Date(timeIntervalSince1970: day * 86_400))
    }
    let past = [fix("sabiye", "صبية", 1), fix("Sabiye", "صبية", 2), fix("sabiye", "سابية", 3),
                fix("kifak", "كيفك", 3), fix("sabiye", "سبية", 4)]
    let offered = Suggestions.pastFixesFirst(past, latin: "sabiye?", shown: "سبية؟",
                                             candidates: ["سابية", "صبيه", "sabiye", "a", "b"])
    #expect(offered == ["صبية", "سابية", "صبيه", "sabiye", "a"])  // most often chosen first; no repeats; at most 5
    #expect(!offered.contains("سبية"))  // never the word already shown
    #expect(!offered.contains("كيفك"))  // another typed word's fix
    #expect(Suggestions.pastFixesFirst(past, latin: nil, shown: "سبية", candidates: ["صبيه"]) == ["صبيه"])
}

@Test func aWordFromARunOfTypedWordsOffersSpellingsOfItsMainWord() {
    let rules: @Sendable (String) -> String = { ["el shr": "الشر", "el": "ال", "shr": "شر"][$0] ?? $0 }
    let suggestions = Suggestions(dictionary: ["shar": "شار"], rules: rules)
    let offered = suggestions.candidates(for: "الشر", latin: "el shr")
    #expect(offered.first == "الشار")  // the main word's spelling, with ال in front
    #expect(!offered.contains("ال") && !offered.contains("الشر"))
}
