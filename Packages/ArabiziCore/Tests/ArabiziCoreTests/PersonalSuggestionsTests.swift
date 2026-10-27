import Foundation
import Testing
@testable import ArabiziCore

private func fix(_ latin: String, _ chosen: String, _ rejected: String, day: Double = 1) -> Correction {
    Correction(latin: latin, chosen: chosen, rejected: rejected, date: Date(timeIntervalSince1970: day * 86_400))
}

private let suggestions = Suggestions(dictionary: [:], rules: fakeRules)

@Test func fixesAreSortedIntoKinds() {
    #expect(suggestions.kind(of: "صبية", replacing: "سبية", latin: "sabiye") == .rules)  // fakeRules: sabiye -> صبية
    #expect(suggestions.kind(of: "sabiye", replacing: "سبية", latin: "sabiye") == .latin)
    #expect(suggestions.kind(of: "طولة", replacing: "تولة", latin: nil) == .letter)
    #expect(suggestions.kind(of: "تاولة", replacing: "تولة", latin: nil) == .longVowel)
    #expect(suggestions.kind(of: "تلة", replacing: "تولة", latin: nil) == .longVowel)
    #expect(suggestions.kind(of: "تولا", replacing: "تولة", latin: nil) == .ending)
    #expect(suggestions.kind(of: "أكل", replacing: "اكل", latin: nil) == .alif)
    #expect(suggestions.kind(of: "مرحبا", replacing: "تولة", latin: nil) == .other)
}

@Test func fixesOfASimilarTypedWordAreOffered() {
    // "tawle" was fixed before; "tawla" is typed one letter differently and shown as a look-alike.
    let past = [fix("tawle", "طاولة", "تاولة")]
    let offered = suggestions.personalized(for: "تاولا", latin: "tawla", past: past)
    #expect(offered.first == "طاولة")
    // Not offered when the spelling does not look like the shown word.
    #expect(!suggestions.personalized(for: "كيف", latin: "tawla", past: past).contains("طاولة"))
}

@Test func theKindsOfChangePickedMostComeFirst() {
    let shown = "تولة"
    let usual = ["طولة", "تولا"]  // a letter swap, then an ending
    // Three ending fixes, no letter swaps: the ending moves up.
    let past = [fix("a", "بيتا", "بيتة"), fix("b", "سما", "سمة"), fix("c", "كرا", "كرة")]
    #expect(suggestions.ordered(usual, shown: shown, latin: nil, by: past) == ["تولا", "طولة"])
    // Fewer than three fixes: the order is unchanged.
    #expect(suggestions.ordered(usual, shown: shown, latin: nil, by: Array(past.prefix(2))) == usual)
}

@Test func theSameTypedWordStillComesFirst() {
    let past = [fix("sabiye", "صبيه", "سبية"), fix("sabiya", "صبية", "سبية")]
    let offered = suggestions.personalized(for: "سبية", latin: "sabiye", past: past)
    #expect(offered.first == "صبيه")  // the exact typed word's own fix
    #expect(offered.contains("صبية"))
    #expect(!offered.contains("سبية"))
    #expect(offered.count <= 5)
}

@Test func theSummaryCountsWithoutText() {
    let past = [fix("tawle", "طاولة", "تاولة", day: 1), fix("tawle", "طاولة", "تاولة", day: 1),
                fix("tawle", "طاولة", "تاولة", day: 2), fix("sabiye", "صبية", "سبية", day: 2),
                fix("kifik", "كيفك", "كيفيك", day: 3)]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let summary = CorrectionSummary(past, kind: { suggestions.kind(of: $0.chosen, replacing: $0.rejected, latin: $0.latin) },
                                    calendar: calendar)
    #expect(summary.fixes == 5 && summary.days == 3 && summary.typedWords == 3)
    #expect(summary.repeats == 2)  // the second and third "tawle"
    #expect(summary.repeatedOnTwoDays == 1)
    #expect(summary.byKind[.rules] == 4 && summary.byKind[.longVowel] == 1)  // kifik: a long vowel dropped
    #expect(summary.byKind.values.reduce(0, +) == 5)
}
