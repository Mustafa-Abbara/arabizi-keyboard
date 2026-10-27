import Foundation
import Testing
@testable import ArabiziCore

let spellingOptions = try! SpellingOptions(rulesDirectory: rulesDirectory, rules: committedConverter)  // swiftlint:disable:this force_try

func spell(_ keys: String) -> Speller {
    var speller = Speller(spellingOptions)
    for key in keys {
        speller.type(String(key))
    }
    return speller
}

@Test func eachKeyIsItsLikeliestLetterAndTheOthersAreOffered() {
    var speller = spell("s")
    #expect(speller.arabic == "س")
    #expect(speller.labels.prefix(2) == ["س", "ص"])
    speller.cycle(1)
    speller.type("a")  // a later short vowel is not written
    speller.type("7")
    #expect(speller.arabic == "صح")
}

@Test func aLetterDoesNotChangeOnceTheNextKeyIsTyped() {
    var speller = spell("kbir")
    speller.type("e")
    #expect(speller.arabic == "كبير")  // the e writes nothing until it is chosen
    #expect(speller.labels.contains("ة") && speller.labels.first == Speller.nothingLabel)
    speller.choose("ة")
    #expect(speller.arabic == "كبيرة")
}

@Test func twoKeysForOneSoundJoinUnlessSeparatedOrChosen() {
    #expect(spell("sh").arabic == "ش")
    #expect(spell("kh").arabic == "خ")
    #expect(spell("3'").arabic == "غ")
    #expect(spell("s'h").arabic == "سه")
    var apart = spell("bsh")
    #expect(apart.arabic == "بش")
    apart.cycle(1)  // the joined keys also offer their letters apart
    apart.type("r")
    #expect(apart.arabic == "بسهر")
    var th = spell("th")
    th.cycle(-1)  // offered last, so ⇧Tab reaches it at once
    #expect(th.arabic == "ته")
    var chosen = spell("s")
    chosen.cycle(1)
    chosen.type("h")
    #expect(chosen.arabic == "صه")  // a chosen letter stays itself
}

@Test func firstVowelsAndDoubledConsonantsFollowTheRules() {
    #expect(spell("a").arabic == "أ")
    #expect(spell("ou").arabic == "أو")
    #expect(spell("bb").arabic == "ب")
    var doubled = spell("bb")
    doubled.choose("ب")
    #expect(doubled.arabic == "بب")
}

@Test func backspaceRemovesTheLastKeyWithItsChoice() {
    var speller = spell("t")
    speller.cycle(1)
    speller.type("a")
    speller.backspace()
    #expect(speller.arabic == "ط")
    #expect(speller.choice == 1)
    speller.backspace()
    #expect(speller.isEmpty)
    speller.backspace()  // nothing left: no change
    #expect(speller.isEmpty)
}

@Test func cyclingWrapsAroundBothWays() {
    var speller = spell("d")
    let count = speller.labels.count
    speller.cycle(-1)
    #expect(speller.choice == count - 1)
    speller.cycle(1)
    #expect(speller.choice == 0)
}

@Test func onlyKeysThatSpellALetterAreTaken() {
    var speller = Speller(spellingOptions)
    for key in [" ", "1", "?", ".", "é", "ab"] {
        let taken = speller.type(key)
        #expect(!taken)
    }
    #expect(speller.isEmpty)
    let upper = speller.type("S")  // upper case is the same key
    #expect(upper)
    #expect(speller.arabic == "س")
}

@Test func aKeyWithOneLetterOffersNoChoice() {
    let speller = spell("m")
    #expect(speller.labels.isEmpty)
    #expect(speller.choice == nil)
}

@Test func theOptionsFileMustCoverEveryRuleKey() {
    let partial = Data(#"{"version": 1, "options": {"a": ["ا"]}}"#.utf8)
    #expect(throws: RuleConverter.FileError.self) {
        try SpellingOptions(options: partial, rules: committedConverter)
    }
}

// MARK: - spelling in the ⌥Tab flow

func spellingComposer(_ recorded: Recorded) -> Composer {
    let suggester = Suggester(
        candidates: { shown, _ in ["سبية؟": ["صبيه", "sabiye"]][shown] ?? [] },
        align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: fakeRules) },
        record: { recorded.add($0) },
        now: { Date(timeIntervalSince1970: 0) },
        spelling: spellingOptions)
    return Composer(convert: { ["kifak ya sabiye": "كيفك يا سبية؟"][$0] ?? $0 }, suggester: suggester)
}

let spellingConverted = "كيفك يا سبية؟"
let spellingLastWord = ("كيفك يا " as String).utf16.count..<spellingConverted.utf16.count

@Test func optionTabTwiceSpellsTheWordAndEnterRecordsIt() {
    let recorded = Recorded()
    var composer = spellingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    #expect(composer.handle(.suggest) == .suggest(marked: spellingConverted, selected: spellingLastWord,
                                                  candidates: [], replacingLength: nil))
    #expect(composer.isSpelling)
    _ = composer.handle(.text("s"))
    #expect(composer.currentCandidates.prefix(2) == ["س", "ص"])
    _ = composer.handle(.tab)
    for key in "abye" { _ = composer.handle(.text(String(key))) }
    #expect(composer.pick("ة") == .suggest(marked: "كيفك يا صبية؟", selected: spellingLastWord,
                                           candidates: composer.currentCandidates, replacingLength: nil))
    #expect(composer.handle(.enter) == .commit("كيفك يا صبية؟"))  // punctuation kept
    #expect(recorded.all == [Correction(latin: "sabiye", chosen: "صبية", rejected: "سبية",
                                        date: Date(timeIntervalSince1970: 0))])
    #expect(!composer.isSuggesting)
    // ⌘Z right after still brings the Latin back.
    #expect(composer.handle(.undo, context: Context(cursorAtLastConversion: true))
            == .restore(marked: "kifak ya sabiye", replacingLength: "كيفك يا صبية؟".utf16.count))
}

@Test func digitsSpellLettersWhileSpelling() {
    var composer = spellingComposer(Recorded())
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    _ = composer.handle(.suggest)
    _ = composer.handle(.text("7"))  // not "pick candidate 7"
    _ = composer.handle(.text("b"))
    #expect(composer.handle(.enter) == .commit("كيفك يا حب؟"))
}

@Test func escapeOrBackspaceOnAnEmptyWordGoBackToTheSuggestions() {
    let recorded = Recorded()
    var composer = spellingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    let list = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    let back = Effect.suggest(marked: spellingConverted, selected: spellingLastWord, candidates: ["صبيه", "sabiye"],
                              replacingLength: nil)
    _ = composer.handle(.suggest)
    _ = composer.handle(.text("s"))
    #expect(composer.handle(.escape) == back)
    #expect(!composer.isSpelling && composer.isSuggesting)
    _ = composer.handle(.suggest)
    _ = composer.handle(.text("s"))
    _ = composer.handle(.backspace)
    #expect(composer.handle(.backspace) == back)
    _ = composer.handle(.suggest)
    #expect(composer.handle(.enter) == back)  // nothing spelled: nothing to take
    #expect(recorded.all.isEmpty)
    #expect(list != back)  // the first ⌥Tab also replaces the converted text
}

@Test func keysThatSpellNothingAreSwallowed() {
    var composer = spellingComposer(Recorded())
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    _ = composer.handle(.suggest)
    #expect(composer.handle(.text(" ")) == .consume)
    #expect(composer.handle(.text("?")) == .consume)
    #expect(composer.isSpelling)
}

@Test func tabOutsideSpellingIsAnOrdinaryKey() {
    var composer = spellingComposer(Recorded())
    for key in "kifak" { _ = composer.handle(.text(String(key))) }
    #expect(composer.handle(.tab) == .commitAndPass("kifak"))
    #expect(composer.handle(.tab) == .pass)
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    #expect(composer.handle(.tab) == .commitAndPass(spellingConverted))
}

@Test func clickingASpellingPicksItLikeItsNumber() {
    let recorded = Recorded()
    var composer = spellingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    #expect(composer.pick("صبيه") == .commit("كيفك يا صبيه؟"))
    #expect(recorded.all.count == 1)
}

@Test func keystrokesCountKeysAndTabs() {
    #expect(Speller.keystrokes(toSpell: "حب", with: spellingOptions) == 2)  // 7 b
    #expect(Speller.keystrokes(toSpell: "صح", with: spellingOptions) == 2)  // 9 7
    let tawle = Speller.keystrokes(toSpell: "طاولة", with: spellingOptions)
    #expect(tawle == 7, "\(String(describing: tawle))")  // 6 a w l e Tab Tab…: the ending is a choice
    let shou = Speller.keystrokes(toSpell: "شو", with: spellingOptions)
    #expect(shou == 3, "\(String(describing: shou))")  // s h u
    #expect(Speller.keystrokes(toSpell: "abc", with: spellingOptions) == nil)
}

/// Every Arabic word in the dev sets can be spelled (the frozen test sets are not read; the training data is
/// checked by `arabizi-suggestions-report`, which takes about a minute).
@Test func everyArabicWordInTheDevSetsCanBeSpelled() throws {
    var words: Set<String> = []
    for file in ["data/pairs/dev.jsonl", "data/pairs/others/dev.jsonl"] {
        for line in try String(contentsOf: repoRoot.appending(path: file), encoding: .utf8).split(separator: "\n") {
            let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            for word in (row?["arabic"] as? String ?? "").split(separator: " ") {
                let core = WordParts(String(word)).core
                if !core.isEmpty, core.unicodeScalars.allSatisfy({ (0x0621...0x064A).contains($0.value) }) {
                    words.insert(core)
                }
            }
        }
    }
    let unspellable = words.filter { Speller.keystrokes(toSpell: $0, with: spellingOptions) == nil }
    #expect(words.count > 1_000)
    #expect(unspellable.isEmpty, "\(unspellable.count) words cannot be spelled")
}

@Test func downAndUpMoveThroughTheSpellingsAndEnterTakesOne() {
    let recorded = Recorded()
    var composer = spellingComposer(recorded)
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    #expect(composer.currentChoice == nil)
    let first = "كيفك يا صبيه؟"
    #expect(composer.handle(.arrowDown) == .suggest(marked: first, selected: spellingLastWord.lowerBound..<first.utf16.count,
                                                    candidates: ["صبيه", "sabiye"], replacingLength: nil))
    _ = composer.handle(.arrowDown)
    #expect(composer.currentChoice == 1)
    _ = composer.handle(.arrowUp)
    #expect(composer.currentChoice == 0)
    _ = composer.handle(.arrowUp)  // round
    #expect(composer.currentChoice == 1)
    #expect(composer.handle(.enter) == .commit("كيفك يا sabiye؟"))  // punctuation kept
    #expect(recorded.all.map(\.chosen) == ["sabiye"])
}

@Test func downAndUpChangeTheLastLetterWhileSpelling() {
    var composer = spellingComposer(Recorded())
    typeAndConvert(&composer, "kifak ya sabiye")
    _ = composer.handle(.suggest, context: Context(cursorAtLastConversion: true))
    _ = composer.handle(.suggest)
    _ = composer.handle(.text("s"))
    _ = composer.handle(.arrowDown)
    #expect(composer.isSpelling)  // not passed to the app
    _ = composer.handle(.text("7"))
    #expect(composer.handle(.enter) == .commit("كيفك يا صح؟"))
}

@Test func downOutsideTheWindowIsAnOrdinaryKey() {
    var composer = spellingComposer(Recorded())
    #expect(composer.handle(.arrowDown) == .pass)
    for key in "ya" { _ = composer.handle(.text(String(key))) }
    #expect(composer.handle(.arrowUp) == .commitAndPass("ya"))
}
