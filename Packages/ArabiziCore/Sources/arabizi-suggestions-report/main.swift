// arabizi-suggestions-report: how well ⌥Tab can fix wrong words, and what the user's own fixes look like
// (ADR 0027). Counts only, never text. Run from the repo root:
//
//   swift run -c release --package-path Packages/ArabiziCore arabizi-suggestions-report [predictions.jsonl ...]
//   swift run -c release --package-path Packages/ArabiziCore arabizi-suggestions-report --corrections
//   swift run -c release --package-path Packages/ArabiziCore arabizi-suggestions-report --doubtful predictions.jsonl ...
//
// Without arguments: can every Arabic word in the dev sets and the training data be spelled letter by letter,
// and with how many presses. With predictions (eval/results/<run>/predictions.jsonl): for each wrong word, is the
// right word among the ⌥Tab suggestions, and how many presses spelling it takes. With --corrections: counts over
// the corrections recorded on this Mac (the last 30 days): fixes, days, repeats and kinds of change.
import ArabiziCore
import Foundation

let rulesDirectory = URL(filePath: "data/rules")
let rules = try RuleConverter(rulesDirectory: rulesDirectory)
let spelling = try SpellingOptions(rulesDirectory: rulesDirectory, rules: rules)
let lexicon = try Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName))
let suggestions = Suggestions(dictionary: Suggestions.dictionary(lexicon: lexicon),
                              arabicWords: Suggestions.arabicWords(lexicon: lexicon), rules: { rules.convert($0) })

func rows(_ path: String) throws -> [[String: Any]] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
    }
}

func isArabicWord(_ word: String) -> Bool {
    !word.isEmpty && word.unicodeScalars.allSatisfy { (0x0621...0x064A).contains($0.value) }
}

func summary(_ presses: [Int]) -> String {
    guard !presses.isEmpty else { return "none" }
    let sorted = presses.sorted()
    let mean = Double(presses.reduce(0, +)) / Double(presses.count)
    return String(format: "mean %.1f presses, median %d, 90th percentile %d", mean, sorted[sorted.count / 2],
                  sorted[sorted.count * 9 / 10])
}

func percent(_ part: Int, _ whole: Int) -> String { whole == 0 ? "-" : "\(100 * part / whole)%" }

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--english" {
    // Which sentences the English guard would leave unchanged: counts per file, and the sentences with --show.
    guard let guardRules = EnglishGuard(rulesDirectory: rulesDirectory, rules: rules) else { exit(1) }
    let show = arguments.contains("--show")
    for path in arguments.dropFirst().filter({ !$0.hasPrefix("--") }) {
        let texts = try rows(path).compactMap { $0["arabizi"] as? String }
        let flagged = texts.filter { guardRules.isEnglish($0) }
        print("\(URL(filePath: path).lastPathComponent): \(flagged.count) of \(texts.count) left unchanged")
        if show { flagged.forEach { print("   \($0)") } }
    }
    exit(0)
}

if arguments.first == "--doubtful" {
    // How well "doubtful" (a letter no typed key writes, in an unknown word) points at wrong words: counts only.
    let spellingOptions = try SpellingOptions(rulesDirectory: rulesDirectory, rules: rules)
    for path in arguments.dropFirst() {
        var flagged = 0, wrongFlagged = 0, wrong = 0, sentencesFlagged = 0, sentences = 0
        for row in try rows(path) {
            let latin = (row["arabizi"] as? String ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
            let shown = (row["prediction"] as? String ?? "").components(separatedBy: " ")
            let reference = (row["reference"] as? String ?? "").components(separatedBy: " ")
            guard shown.count == reference.count, shown.count == latin.count else { continue }
            sentences += 1
            var any = false
            for i in shown.indices {
                let isWrong = WordParts(shown[i]).core != WordParts(reference[i]).core
                if isWrong { wrong += 1 }
                if suggestions.isDoubtful(shown[i], latin: latin[i], spelling: spellingOptions) {
                    flagged += 1
                    any = true
                    if isWrong { wrongFlagged += 1 }
                }
            }
            if any { sentencesFlagged += 1 }
        }
        print(URL(filePath: path).deletingLastPathComponent().lastPathComponent)
        print("  doubtful words: \(flagged), of them wrong: \(wrongFlagged) (\(percent(wrongFlagged, flagged)))")
        print("  wrong words caught: \(wrongFlagged) of \(wrong) (\(percent(wrongFlagged, wrong)))")
        print("  sentences with a doubtful word: \(sentencesFlagged) of \(sentences)")
    }
    exit(0)
}

if arguments == ["--corrections"] {
    guard let store = CorrectionStore.standard() else {
        print("no correction record on this Mac")
        exit(1)
    }
    let counts = CorrectionSummary(store.all()) { suggestions.kind(of: $0.chosen, replacing: $0.rejected, latin: $0.latin) }
    print("corrections (last 30 days): \(counts.fixes) fixes on \(counts.days) days, \(counts.typedWords) typed words")
    print("  repeat an earlier fix exactly: \(counts.repeats) (\(percent(counts.repeats, counts.fixes)))")
    print("  typed words fixed the same way on 2+ days: \(counts.repeatedOnTwoDays)")
    for kind in FixKind.allCases {
        let n = counts.byKind[kind, default: 0]
        print("  \(kind.rawValue): \(n) (\(percent(n, counts.fixes)))")
    }
    exit(0)
}

if arguments.isEmpty {
    for (name, files) in [("dev sets", ["data/pairs/dev.jsonl", "data/pairs/others/dev.jsonl"]),
                          ("training", ["data/pairs/train-hand.jsonl", "data/pairs/train-ai_checked.jsonl"])] {
        var words: Set<String> = []
        for file in files {
            for row in try rows(file) {
                for word in (row["arabic"] as? String ?? "").split(separator: " ") {
                    let core = WordParts(String(word)).core
                    if isArabicWord(core) { words.insert(core) }
                }
            }
        }
        let spelled = words.compactMap { Speller.keystrokes(toSpell: $0, with: spelling) }
        print("\(name): \(words.count) distinct words, \(words.count - spelled.count) cannot be spelled; \(summary(spelled))")
    }
}

for path in arguments {
    var wrong = 0, offered = 0, spellCost: [Int] = [], unspellable = 0, skipped = 0
    for row in try rows(path) {
        let latin = (row["arabizi"] as? String ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let shown = (row["prediction"] as? String ?? "").components(separatedBy: " ")
        let reference = (row["reference"] as? String ?? "").components(separatedBy: " ")
        guard shown.count == reference.count else {  // words are compared by position only
            skipped += 1
            continue
        }
        let alignment = WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) })
        for i in shown.indices {
            let word = WordParts(shown[i]).core, right = WordParts(reference[i]).core
            guard word != right, word.contains(where: \.isLetter) else { continue }
            wrong += 1
            if suggestions.candidates(for: shown[i], latin: alignment[i].map { latin[$0].joined(separator: " ") })
                .contains(right) {
                offered += 1
            } else if isArabicWord(right) {
                if let presses = Speller.keystrokes(toSpell: right, with: spelling) {
                    spellCost.append(presses)
                } else {
                    unspellable += 1
                }
            }
        }
    }
    print(URL(filePath: path).deletingLastPathComponent().lastPathComponent)
    print("  \(wrong) wrong words (\(skipped) sentences skipped: word count changed)")
    print("  right word among the suggestions: \(offered) (\(percent(offered, wrong)))")
    print("  the others, spelled: \(spellCost.count) words, \(summary(spellCost)); cannot be spelled: \(unspellable)")
}
