import Foundation

/// The ↑ list, version 2 (ADR 0036): candidates for one word from seven sources, their signals, and the order a
/// small learned ranker gives them. The Swift port of `eval/src/arabizi_eval/candidates.py`, checked against
/// `Fixtures/candidates_parity.json`.
///
/// Sources: (1) the model's guesses for that spot (given by the engine); (2) spellings of the typed word ranked by
/// letter odds, unknown words kept; (3) known spellings of the typed word; (4) the training data's own spellings
/// of the typed word; (5) a prefix typed joined (w, b, l, el, bel…) split off, the rest spelled, the Arabic prefix
/// put back; (6) variants of the model's word, unknown kept; (7) today's list (`Suggestions`, ADR 0027).
public struct CandidateList: Sendable {
    public static let rankerFileName = "candidate_ranker.json"
    /// Places on the keyboard; the last keeps the typed word.
    public static let listLength = 7
    public static let features = [
        "model_lp", "in_model", "model_rank", "model_gap",
        "spell_lp", "in_spell", "spell_rank",
        "known", "log_freq", "in_known_spell",
        "in_first", "first_rank",
        "in_train", "train_rank", "train_count", "is_dict",
        "clitic_lp", "in_clitic",
        "in_variant", "variant_rank",
        "sim_shown", "sim_rules", "is_rules", "len_diff",
        "typing_lp", "typing_lp_per_letter", "typed_matches", "shape_lp",
        "n_sources",
    ]

    /// The ranker's weights over standardized signals (`pairs train-ranker`).
    public struct Ranker: Sendable, Decodable {
        let features: [String]
        let mean: [Double]
        let scale: [Double]
        let weights: [Double]
        let bias: Double

        func score(_ signals: [Double]) -> Double {
            var total = bias
            for i in signals.indices { total += (signals[i] - mean[i]) / scale[i] * weights[i] }
            return total
        }
    }

    let rules: RuleConverter
    let odds: SpellingOdds
    let ranker: Ranker?
    let suggestions: Suggestions
    let dictionary: [String: String]
    let arabicWords: [String: Int]
    let known: Set<String>
    let trie: TrieNode
    let clitics: [(latin: String, arabic: String)]
    let trigrams: [String: Int]
    let bigrams: [String: Int]

    /// Reads the rules, the dictionary, the letter odds and the ranker from one folder (data/rules in the repo,
    /// Resources in the app). Without the ranker file the candidates keep the order they were built in.
    public init(rulesDirectory: URL) throws {
        let lexicon = try Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName))
        let rankerURL = rulesDirectory.appending(path: Self.rankerFileName)
        try self.init(rules: RuleConverter(rulesDirectory: rulesDirectory), lexicon: lexicon,
                      odds: Data(contentsOf: rulesDirectory.appending(path: SpellingOdds.fileName)),
                      ranker: FileManager.default.fileExists(atPath: rankerURL.path) ? Data(contentsOf: rankerURL) : nil)
    }

    public init(rules: RuleConverter, lexicon: Data, odds: Data, ranker: Data?) throws {
        self.rules = rules
        self.odds = try SpellingOdds(data: odds)
        if let ranker {
            let decoded = try JSONDecoder().decode(Ranker.self, from: ranker)
            guard decoded.features == Self.features, decoded.weights.count == Self.features.count else {
                throw RuleConverter.FileError(description: "the ranker's signals do not match this version")
            }
            self.ranker = decoded
        } else {
            self.ranker = nil
        }
        dictionary = Suggestions.dictionary(lexicon: lexicon)
        arabicWords = Suggestions.arabicWords(lexicon: lexicon)
        known = Set(dictionary.values).union(arabicWords.keys)
        trie = TrieNode(words: known)
        let converter = rules
        suggestions = Suggestions(dictionary: dictionary, arabicWords: arabicWords,
                                  rules: { converter.convert($0) })
        clitics = rules.clitics.filter { !$0.value.contains(" ") }
            .map { (latin: $0.key, arabic: $0.value) }
            .sorted { $0.latin.count != $1.latin.count ? $0.latin.count > $1.latin.count
                                                         : SpellingOdds.less($0.latin, $1.latin) }
        var trigrams: [String: Int] = [:], bigrams: [String: Int] = [:]
        for (word, count) in arabicWords {
            let padded = Array(("^^" + word + "$").unicodeScalars)
            for i in 2..<padded.count {
                trigrams[String(String.UnicodeScalarView(padded[(i - 2)...i])), default: 0] += count
                bigrams[String(String.UnicodeScalarView(padded[(i - 2)..<i])), default: 0] += count
            }
        }
        self.trigrams = trigrams
        self.bigrams = bigrams
    }

    // MARK: The list

    /// The ↑ list for one word: the best `limit - 1` Arabic candidates, then the typed word to keep it in Latin.
    /// `guesses`: the model's guesses for that spot with their log-probabilities, best first (none: the instant
    /// list).
    public func suggestions(shown: String, typedWords: [String], guesses: [(String, Double)] = [],
                            limit: Int = listLength) -> [String] {
        let pool = pool(shown: shown, typedWords: typedWords, guesses: guesses)
        var out = Array(order(pool).prefix(limit - 1))
        let latin = typedWords.joined(separator: " ")
        if !latin.isEmpty { out.append(latin) }
        return out
    }

    /// Candidates best first by the ranker (or as built without one); equal scores keep the built order.
    func order(_ pool: [(word: String, signals: [Double])]) -> [String] {
        guard let ranker else { return pool.map(\.word) }
        let scores = pool.map { ranker.score($0.signals) }
        return pool.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }.map { pool[$0].word }
    }

    // MARK: The pool and its signals

    /// Every candidate for the word `shown`, written by the model from `typedWords`, with its signals.
    func pool(shown: String, typedWords: [String], guesses: [(String, Double)])
        -> [(word: String, signals: [Double])] {
        let typed = typedWords.map { $0.lowercased() }.joined()
        let model = Ordered(guesses.enumerated().filter { $0.element.0 != shown }
            .map { ($0.element.0, (lp: $0.element.1, rank: Double($0.offset + 1))) })
        let spelled = Ordered(odds.spellings(typed, known: known).enumerated().filter { $0.element.0 != shown }
            .map { ($0.element.0, (lp: $0.element.1, rank: Double($0.offset + 1))) })
        let knownSpelled = odds.knownSpellings(typed, trie: trie, frequency: arabicWords)
        let knownSet = Set(knownSpelled)
        let first = Ordered(firstList(shown: shown, typed: typed).enumerated().map { ($0.element, Double($0.offset + 1)) })
        let ruled = Self.arabicCore(rules.convert(typedWords.joined(separator: " ")))
        var trained = odds.typedSpellings[typed] ?? [:]
        if trained.isEmpty, let word = dictionary[typed] { trained = [word: 1] }
        let trainOrder = trained.sorted { $0.value != $1.value ? $0.value > $1.value : SpellingOdds.less($0.key, $1.key) }
        let trainList = Ordered(trainOrder.prefix(5).enumerated().map { ($0.element.key, Double($0.offset + 1)) })
        let clitic = cliticSpellings(typed)
        let variants = Ordered(Suggestions.variants(of: shown).prefix(40).enumerated()
            .map { ($0.element, Double($0.offset + 1)) }, lastWins: true)

        var candidates: [String] = []
        var seen = Set<String>()
        for word in model.keys + spelled.keys + knownSpelled + trainList.keys + clitic.keys + variants.keys + first.keys
        where word != shown && SpellingOdds.isArabicWord(word) && !seen.contains(word) {
            candidates.append(word)
            seen.insert(word)
        }
        let bestModel = model.values.map(\.lp).max() ?? 0
        let shownLength = Double(shown.unicodeScalars.count)
        return candidates.map { word in
            let (mlp, mrank) = model[word] ?? (-30, 11)
            let (slp, srank) = spelled[word] ?? (-60, 31)
            let tlp = odds.typingLogProbability(typed, word)
            let length = Double(word.unicodeScalars.count)
            let sources = [model[word] != nil, spelled[word] != nil, knownSet.contains(word), trainList[word] != nil,
                           clitic[word] != nil, variants[word] != nil, first[word] != nil]
            let signals: [Double] = [
                mlp, flag(model[word] != nil), mrank, model[word] != nil ? mlp - bestModel : -30,
                slp, flag(spelled[word] != nil), srank,
                flag(known.contains(word)), Foundation.log1p(Double(arabicWords[word] ?? 0)), flag(knownSet.contains(word)),
                flag(first[word] != nil), first[word] ?? 50,
                flag(trainList[word] != nil), trainList[word] ?? 6, Foundation.log1p(Double(trained[word] ?? 0)),
                flag(dictionary[typed] == word),
                clitic[word] ?? -60, flag(clitic[word] != nil),
                flag(variants[word] != nil), variants[word] ?? 41,
                Self.similarity(word, shown), Self.similarity(word, ruled), flag(word == ruled), abs(length - shownLength),
                tlp, tlp / max(length, 1), flag(tlp > -60), shapeLogProbability(word),
                Double(sources.filter { $0 }.count),
            ]
            return (word, signals)
        }
    }

    /// Source 7: today's list (ADR 0027), without its limit and without the typed word.
    func firstList(shown: String, typed: String) -> [String] {
        suggestions.candidates(for: shown, latin: typed, limit: 100_000).filter { $0 != typed }
    }

    /// Source 5: a small word typed joined to the next (wamen, bleyle), best score per word.
    func cliticSpellings(_ typed: String) -> Ordered<Double> {
        var out = Ordered<Double>([])
        for (latin, arabic) in clitics where typed.hasPrefix(latin) && typed.count - latin.count >= 2 {
            for (word, lp) in odds.spellings(String(typed.dropFirst(latin.count)), known: known, keep: 8) {
                let joined = RuleConverter.joinClitic(arabic, word)
                out[joined] = max(out[joined] ?? -1e9, lp)
            }
        }
        return out
    }

    /// How Arabic-like a word looks: average log-probability per letter, character 3-grams of known words.
    func shapeLogProbability(_ word: String) -> Double {
        let padded = Array(("^^" + word + "$").unicodeScalars)
        var total = 0.0
        for i in 2..<padded.count {
            let tri = trigrams[String(String.UnicodeScalarView(padded[(i - 2)...i]))] ?? 0
            let bi = bigrams[String(String.UnicodeScalarView(padded[(i - 2)..<i]))] ?? 0
            total += Foundation.log(Double(tri + 1) / Double(bi + 40))
        }
        return total / Double(max(padded.count - 2, 1))
    }

    // MARK: Helpers

    private func flag(_ value: Bool) -> Double { value ? 1 : 0 }

    /// 1 - edit distance / the longer length, by Unicode scalar.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var previous = Array(0...y.count)
        for i in stride(from: 1, through: x.count, by: 1) {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in stride(from: 1, through: y.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    /// The text without anything but Arabic letters at its ends (Python's `ARABIC_CORE`).
    static func arabicCore(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let isLetter = { (s: Unicode.Scalar) in (0x0621...0x064A).contains(s.value) }
        guard let start = scalars.firstIndex(where: isLetter), let end = scalars.lastIndex(where: isLetter) else {
            return ""
        }
        return String(String.UnicodeScalarView(scalars[start...end]))
    }
}

/// A dictionary that remembers the order words were first added (Python's dict). With `lastWins`, a word added
/// again keeps its first place but takes the later value (a Python dict comprehension over a list with repeats).
struct Ordered<Value> {
    private(set) var keys: [String] = []
    private var values_: [String: Value] = [:]

    init(_ pairs: [(String, Value)], lastWins: Bool = false) {
        for (key, value) in pairs {
            if values_[key] == nil {
                keys.append(key)
                values_[key] = value
            } else if lastWins {
                values_[key] = value
            }
        }
    }

    var values: [Value] { keys.compactMap { values_[$0] } }

    subscript(key: String) -> Value? {
        get { values_[key] }
        set {
            if values_[key] == nil, newValue != nil { keys.append(key) }
            values_[key] = newValue
        }
    }
}
