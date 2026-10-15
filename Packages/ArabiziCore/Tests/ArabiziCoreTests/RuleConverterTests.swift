import CryptoKit
import Foundation
import Testing
@testable import ArabiziCore

/// The repository root, found from this file: the tests read data/rules and data/pairs where they are.
let repoRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let rulesDirectory = repoRoot.appending(path: "data/rules")
let rulesData = try! Data(contentsOf: rulesDirectory.appending(path: RuleConverter.rulesFileName))  // swiftlint:disable:this force_try

/// The same small dictionary as eval/tests/test_b0.py, so these cases match the Python ones line for line.
let testConverter = try! RuleConverter(rules: rulesData, lexicon: Data("""
    {"words": {"shu": "شو", "beit": "بيت", "bet": "البيت", "kifak": "كيفك", "3am": "عم"},
     "keep_latin": ["meeting", "lau"]}
    """.utf8))  // swiftlint:disable:this force_try

// MARK: - the cases of eval/tests/test_b0.py

@Test(arguments: [
    ("ktir", "كتير"), ("mni7", "منيح"), ("ta3mel", "تعمل"), ("7abibi", "حبيبي"),
    ("ana", "أنا"), ("hayda", "هيدا"), ("bade", "بدي"), ("kbire", "كبيرة"),
    ("shhr", "شهر"),  // the h of "sh" is not a doubled h
    ("sakkar", "سكر"),  // doubled k collapses
    ("sheyfne", "شيفني"), ("kllfne", "كلفني"),  // -ne ending is "me"
    ("8ayr", "غير"), ("2ahwe", "قهوة"),  // 8 is غ and 2 is ق for many Lebanese typists
])
func letterRules(word: String, arabic: String) {
    #expect(testConverter.letters(word) == arabic)
}

@Test(arguments: [
    ("8ali", "غلي", "غالي"),  // a medial a can be a long vowel: letter rules drop it
    ("2alle", "قلة", "قلي"),  // final -e is ي here, ة in kbire: letter rules cannot tell
])
func knownLimitsOfLetterRules(word: String, rulesGive: String, right: String) {
    // Documented, not hidden: these words need the dictionary (or the model).
    #expect(testConverter.letters(word) == rulesGive)
    #expect(rulesGive != right)
}

@Test(arguments: [
    ("بال", "البيت", "بالبيت"), ("ل", "البيت", "للبيت"), ("لل", "البيت", "للبيت"), ("لل", "بيت", "للبيت"),
    ("و", "البيت", "والبيت"), ("ب", "البيت", "بالبيت"), ("من ال", "البيت", "من البيت"), ("ل", "محمد", "لمحمد"),
])
func joinCliticNeverDoublesTheArticle(prefix: String, word: String, joined: String) {
    #expect(RuleConverter.joinClitic(prefix, word) == joined)
}

@Test(arguments: [
    ("kifak, shu 3am?", "كيفك، شو عم؟"),  // dictionary + punctuation
    ("bel beit", "بالبيت"),
    ("w el bet", "والبيت"),  // a run of clitics, dictionary word with its own article
    ("la el beit", "للبيت"),
    ("el meeting", "ال meeting"),  // before a kept Latin word the clitic stays separate
    ("w el meeting", "وال meeting"),
    ("bel LAU", "بال LAU"),  // kept Latin words keep their case
    ("b3at 100$ la", "بعت 100$ ل"),  // numbers untouched; a trailing clitic stays
    ("shuf www.lau.edu, @rami #lebanon 😂", "شوف www.lau.edu, @rami #lebanon 😂"),
    ("3al 7:30?", "عال 7:30؟"),
    ("shu\nkifak 3am", "shu\nkifak عم"),
])
func conversion(arabizi: String, arabic: String) {
    #expect(testConverter.convert(arabizi).unicodeScalars.elementsEqual(arabic.unicodeScalars))
}

// MARK: - parity with Python, from the fixture written by eval/src/arabizi_eval/parity.py

struct ParityFixture: Decodable {
    struct Corpus: Decodable {
        let files: [String]
        let hashChars: Int
        let outputs: [String: String]
        enum CodingKeys: String, CodingKey { case files, outputs, hashChars = "hash_chars" }
    }
    struct Letters: Decodable {
        let words: Int
        let outputsSha256: String
        enum CodingKeys: String, CodingKey { case words, outputsSha256 = "outputs_sha256" }
    }
    let rulesSha256: String
    let lexiconSha256: String
    let cases: [[String]]
    let corpus: Corpus
    let letters: Letters
    enum CodingKeys: String, CodingKey {
        case cases, corpus, letters, rulesSha256 = "rules_sha256", lexiconSha256 = "lexicon_sha256"
    }
}

let fixture = try! JSONDecoder().decode(  // swiftlint:disable:this force_try
    ParityFixture.self,
    from: Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/b0_parity.json")))
let committedConverter = try! RuleConverter(rulesDirectory: rulesDirectory)  // swiftlint:disable:this force_try
let regenerate = "rules changed: run `uv run --project eval python -m arabizi_eval.parity` and commit the fixture"

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Test func fixtureMatchesTheCommittedRuleFiles() throws {
    let lexicon = try Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName))
    #expect(sha256(rulesData) == fixture.rulesSha256, "\(regenerate)")
    #expect(sha256(lexicon) == fixture.lexiconSha256, "\(regenerate)")
}

@Test func edgeCasesMatchPython() {
    for pair in fixture.cases {
        let swift = committedConverter.convert(pair[0])
        // Compare code points: Swift's == would call different but canonically equal strings the same.
        #expect(swift.unicodeScalars.elementsEqual(pair[1].unicodeScalars),
                "\(pair[0].debugDescription): Swift \(swift.debugDescription), Python \(pair[1].debugDescription)")
    }
}

@Test func everyPublicTrainingAndDevRowMatchesPython() throws {
    var checked = 0
    var mismatches: [String] = []
    for file in fixture.corpus.files {
        let text = try String(contentsOf: repoRoot.appending(path: file), encoding: .utf8)
        for line in text.split(separator: "\n") where !line.allSatisfy(\.isWhitespace) {
            let row = try JSONDecoder().decode([String: JSONValue].self, from: Data(line.utf8))
            guard case .string(let id) = row["id"], case .string(let arabizi) = row["arabizi"] else { continue }
            let swift = committedConverter.convert(arabizi)
            if String(sha256(Data(swift.utf8)).prefix(fixture.corpus.hashChars)) != fixture.corpus.outputs[id] {
                mismatches.append("\(id): \(arabizi) -> \(swift)")
            }
            checked += 1
        }
    }
    #expect(checked == fixture.corpus.outputs.count, "\(regenerate)")
    #expect(mismatches.isEmpty, "\(mismatches.count) rows differ from Python, first: \(mismatches.prefix(5))")
}

@Test func letterRulesMatchPythonOnEveryDictionaryWord() {
    let words = committedConverter.words.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
    #expect(words.count == fixture.letters.words, "\(regenerate)")
    let joined = words.map { committedConverter.letters($0) }.joined(separator: "\n")
    #expect(sha256(Data(joined.utf8)) == fixture.letters.outputsSha256)
}

/// Enough JSON to read the id and the Arabizi of a row whatever its other fields hold.
enum JSONValue: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        self = (try? decoder.singleValueContainer().decode(String.self)).map(JSONValue.string) ?? .other
    }
}

// MARK: - loading

@Test func committedFilesLoad() {
    #expect(committedConverter.clitics["w"] == "و")
    #expect(committedConverter.clitics["_comment"] == nil)
    #expect(!committedConverter.words.isEmpty && !committedConverter.keepLatin.isEmpty)
}

@Test func missingDictionaryMeansLetterRulesOnly() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try rulesData.write(to: folder.appending(path: RuleConverter.rulesFileName))
    let converter = try RuleConverter(rulesDirectory: folder)
    #expect(converter.words.isEmpty)
    #expect(converter.convert("ktir") == "كتير")
}

@Test func overlappingWordEndingsAreRejected() throws {
    var rules = try #require(JSONSerialization.jsonObject(with: rulesData) as? [String: Any])
    var letters = try #require(rules["letters"] as? [String: Any])
    letters["word_endings"] = ["ne": "ني", "e": "ة"]  // "ne" ends with "e": Python's dict order would decide
    rules["letters"] = letters
    let data = try JSONSerialization.data(withJSONObject: rules)
    #expect(throws: RuleConverter.FileError.self) { try RuleConverter(rules: data, lexicon: nil) }
}

@Test func unknownRulesVersionIsRejected() throws {
    var rules = try #require(JSONSerialization.jsonObject(with: rulesData) as? [String: Any])
    rules["version"] = 2
    let data = try JSONSerialization.data(withJSONObject: rules)
    #expect(throws: RuleConverter.FileError.self) { try RuleConverter(rules: data, lexicon: nil) }
}
