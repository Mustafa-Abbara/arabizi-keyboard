// The core's C interface for the Windows keyboard (ADR 0032, task 2): plain C functions, UTF-8 JSON in and out, so
// a C++ text service can use the same behaviour as the Mac keyboard. Strings returned are owned by the caller and
// freed with harfi_free. The header is Apps/HarfiWindows/include/harfi_core.h.
//
//   harfi_core_open(rules_dir)          -> core handle, or NULL when the rule files cannot be read
//   harfi_convert(core, text)           -> the rules' Arabic for text
//   harfi_is_english(core, text)        -> 1 when text is plain English (left as typed), else 0
//   harfi_preview(core, text, whole)    -> what the live preview box shows for the text typed so far, as JSON
//   harfi_habit_refuse(core, latin, sp) -> the user said no to a learned habit (ADR 0033)
//   harfi_composer_new(core)            -> a composer: the key-by-key typing behaviour
//   harfi_composer_key(composer, json)  -> what to do in the app after a key, as JSON (see `effectJSON`)
//   harfi_composer_pick(composer, text) -> the same for a spelling (or letter) clicked in the chip row
//   harfi_composer_buffer(composer)     -> the Latin text being typed
//   harfi_free(string), harfi_composer_free(composer), harfi_core_close(core)
import ArabiziCore
import Foundation

/// The rules, the English guard and what suggestions need, read once from a rules folder.
final class Core: Sendable {
    let rules: RuleConverter
    let english: EnglishGuard?
    /// Chat abbreviations kept as typed (ADR 0035), as the engine keeps them.
    let abbreviations: ChatAbbreviations?
    let suggester: Suggester?
    /// The user's recorded picks and learned habits; only for the installed keyboard (a folder holding HarfiTIP.dll),
    /// so tests and tools reading data/rules never write a record.
    let personal: PersonalWords?
    /// The model's words never written in training: the dictionary's spelling where it has one (ADR 0034).
    let unsure: UnsureWords
    /// Unsure words already pointed out in this app, so a word the user keeps is not pointed out again.
    private let pointedOut = PointedOut()
    /// How sure the model was of each word of the last conversions, by the text shown: ↑ starts on the least sure.
    let confidences: WordConfidences

    init(rulesDirectory: URL) throws {
        let confidences = WordConfidences()
        self.confidences = confidences
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        self.rules = rules
        english = EnglishGuard(rulesDirectory: rulesDirectory, rules: rules)
        abbreviations = ChatAbbreviations(rulesDirectory: rulesDirectory)
        let lexicon = (try? Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName))) ?? Data()
        let suggestions = Suggestions(dictionary: Suggestions.dictionary(lexicon: lexicon),
                                      arabicWords: Suggestions.arabicWords(lexicon: lexicon),
                                      rules: { rules.convert($0) })
        let spelling = try? SpellingOptions(rulesDirectory: rulesDirectory, rules: rules)
        unsure = UnsureWords(known: Suggestions.arabicWords(lexicon: lexicon).keys,
                             dictionary: Suggestions.dictionary(lexicon: lexicon))
        let keyboard = rulesDirectory.deletingLastPathComponent()
        let personal = FileManager.default.fileExists(atPath: keyboard.appending(path: "HarfiTIP.dll").path)
            ? CorrectionStore.standard(folder: keyboard.appending(path: "words")).map { PersonalWords(store: $0) }
            : nil
        self.personal = personal
        // Word suggestions v2 (ADR 0036), loaded in the background; the first list until it is ready.
        let candidates = BackgroundCandidateList(rulesDirectory: rulesDirectory)
        suggester = Suggester(
            candidates: { shown, latin in  // the user's earlier fixes first, as on the Mac (ADR 0027 #8–9)
                let past = personal?.store.all() ?? []
                return candidates.list?.personalized(for: shown, latin: latin, past: past)
                    ?? suggestions.personalized(for: shown, latin: latin, past: past)
            },
            align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) }) },
            record: { correction in personal?.record(correction) },
            spelling: spelling,
            doubtful: { shown, latin in spelling.map { suggestions.isDoubtful(shown, latin: latin, spelling: $0) } ?? false },
            confidence: { [confidences] converted in confidences.of(converted) })
        #if os(Windows)
        // The keyboard's folder holds rules\, config\ and harfi-engine.exe.
        let engine = EngineClient(folder: rulesDirectory.deletingLastPathComponent())
        self.engine = engine
        ahead = engine.map { PreviewConversions(engine: $0) }
        if let engine { Thread.detachNewThread { engine.warmUp() } }  // never delays the keyboard's start
        #endif
    }

    /// The engine's conversion of exactly this text, made ahead for the preview: Enter sends it without asking again.
    func ready(_ text: String) -> String? {
        #if os(Windows)
        guard let made = ahead?.answer(for: text) else { return nil }
        let shown = fromModel(text, made.arabic)
        confidences.remember(shown, made.confidence)
        return shown
        #else
        return nil
        #endif
    }

    /// The model's answer for `latin` as the keyboard shows it: unsure words with a dictionary spelling written that
    /// way (ADR 0034), then the user's habits over everything (ADR 0033).
    func fromModel(_ latin: String, _ arabic: String) -> String {
        guard let suggester else { return arabic }
        return yours(latin, unsure.swap(latin: latin, converted: arabic, align: suggester.align))
    }

    /// The first unsure word of a text just sent, to point out: not one the user has chosen themself, and each word
    /// once per app.
    func toPointOut(in text: String) -> String? {
        let words = unsure.unsure(in: text)
        guard !words.isEmpty else { return nil }
        let chosen = Set((personal?.store.all() ?? []).map(\.chosen))
        return pointedOut.first(of: words.filter { !chosen.contains($0) })
    }

    /// `arabic` (a conversion of `latin`) with the user's learned habits applied, after the model (ADR 0027 #6).
    func yours(_ latin: String, _ arabic: String) -> String {
        guard let personal, let suggester else { return arabic }
        return Habits.apply(personal.current(), latin: latin, converted: arabic, align: suggester.align)
    }

    /// The text as the keyboard converts it without the model: plain English stays as typed. Instant: the live
    /// preview uses it on every key.
    func convert(_ text: String) -> String {
        if english?.isEnglish(text) == true { return text }
        return abbreviations?.convert(text, with: rules) ?? rules.convert(text)
    }

    #if os(Windows)
    /// harfi-engine (the fine-tuned model), when it is installed next to the keyboard; nil keeps to the rules.
    let engine: EngineClient?
    /// Its conversions for the live preview, made in the background.
    let ahead: PreviewConversions?
    /// The user's settings (the settings window writes the file).
    let settings = UserSettingsFile()
    #endif

    /// What Enter sends: the engine's answer within its deadline (the model, with its own rule fallback), else the
    /// rules here.
    func convertForSending(_ text: String) -> String {
        #if os(Windows)
        if let answer = engine?.answer(text) {
            let shown = fromModel(text, answer.text)
            confidences.remember(shown, answer.wordConfidence)
            return shown
        }
        #endif
        return yours(text, convert(text))
    }

    /// Which shown words look wrong (dotted in the preview), given the Latin they were converted from.
    func doubtful(_ words: [String], latin: String) -> [Int] {
        guard let suggester else { return [] }
        let typed = latin.split(whereSeparator: \.isWhitespace).map(String.init)
        let alignment = suggester.align(typed, words)
        return words.indices.filter { i in
            suggester.doubtful(words[i], alignment[i].map { typed[$0].joined(separator: " ") })
        }
    }

    /// What the live preview box shows for the text typed so far, as on the Mac (PreviewCache.display): the Arabic of
    /// the longest start that ends at a word boundary, then the Latin typed since. The word being typed counts only
    /// when `whole` (after a pause in typing). A start ending in a small word (el, w, b) waits for the next word, so a
    /// lone ال never shows before its word. The Arabic is the engine's once it has converted that start (asked in the
    /// background), the rules' until then; "pending" says the engine's is coming. Empty when nothing shows yet.
    func preview(_ buffer: String, whole: Bool) -> [String: Any] {
        func endsWithClitic(_ text: String) -> Bool {
            text.split(whereSeparator: \.isWhitespace).last.map { rules.isClitic(String($0)) } ?? false
        }
        let characters = Array(buffer)
        var head: String?
        for end in stride(from: characters.count, through: 1, by: -1) {
            let start = String(characters[..<end])
            let usable = end == characters.count
                ? whole || (characters[end - 1].isWhitespace && !endsWithClitic(start))
                : (characters[end - 1].isWhitespace || characters[end].isWhitespace) && !endsWithClitic(start)
            guard usable else { continue }
            if start.contains(where: \.isLetter) { head = start }
            break
        }
        guard let head else { return [:] }
        var arabic = ready(head)
        var pending = false
        #if os(Windows)
        if arabic == nil, let ahead { pending = ahead.request(head) }
        #endif
        // "Live preview" switched off: no box, but the engine still converts ahead, so Enter does not wait.
        guard settings.current.livePreview else { return [:] }
        if arabic == nil { arabic = yours(head, convert(head)) }
        let words = (arabic ?? "").trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        return ["arabic": words, "latin": String(buffer.dropFirst(head.count)).trimmingCharacters(in: .whitespaces),
                "doubtful": doubtful(words, latin: head), "pending": pending]
    }
}

final class ComposerBox {
    let core: Core
    var composer: Composer
    init(core: Core) {
        self.core = core
        composer = Composer(convert: { [core] in core.convertForSending($0) }, suggester: core.suggester,
                            ready: { [core] in core.ready($0) })
    }
}

private func string(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

/// A C string the caller frees with harfi_free.
private func owned(_ text: String) -> UnsafeMutablePointer<CChar>? {
    strdup(text)
}

@_cdecl("harfi_core_open")
public func harfi_core_open(_ rulesDirectory: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let core = try? Core(rulesDirectory: URL(filePath: string(rulesDirectory))) else { return nil }
    return Unmanaged.passRetained(core).toOpaque()
}

@_cdecl("harfi_core_close")
public func harfi_core_close(_ core: UnsafeMutableRawPointer?) {
    guard let core else { return }
    Unmanaged<Core>.fromOpaque(core).release()
}

@_cdecl("harfi_convert")
public func harfi_convert(_ core: UnsafeMutableRawPointer?, _ text: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let core else { return nil }
    return owned(Unmanaged<Core>.fromOpaque(core).takeUnretainedValue().convert(string(text)))
}

@_cdecl("harfi_is_english")
public func harfi_is_english(_ core: UnsafeMutableRawPointer?, _ text: UnsafePointer<CChar>?) -> Int32 {
    guard let core else { return 0 }
    return Unmanaged<Core>.fromOpaque(core).takeUnretainedValue().english?.isEnglish(string(text)) == true ? 1 : 0
}

/// The live preview for the Latin typed so far: {"arabic": [words], "latin": the Latin typed since, "doubtful":
/// [indices of words that look wrong]}, or {} when nothing shows yet. `whole` (nonzero after a pause in typing):
/// the word being typed too.
@_cdecl("harfi_preview")
public func harfi_preview(_ core: UnsafeMutableRawPointer?, _ latin: UnsafePointer<CChar>?,
                          _ whole: Int32) -> UnsafeMutablePointer<CChar>? {
    guard let core else { return nil }
    return owned(encode(Unmanaged<Core>.fromOpaque(core).takeUnretainedValue().preview(string(latin), whole: whole != 0)))
}

/// The user refused a habit the keyboard announced (Esc on the tip): it is never applied or announced again.
@_cdecl("harfi_habit_refuse")
public func harfi_habit_refuse(_ core: UnsafeMutableRawPointer?, _ latin: UnsafePointer<CChar>?,
                               _ spelling: UnsafePointer<CChar>?) {
    guard let core else { return }
    Unmanaged<Core>.fromOpaque(core).takeUnretainedValue().personal?
        .refuse(Habit(latin: string(latin), spelling: string(spelling)))
}

@_cdecl("harfi_composer_new")
public func harfi_composer_new(_ core: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let core else { return nil }
    let box = ComposerBox(core: Unmanaged<Core>.fromOpaque(core).takeUnretainedValue())
    return Unmanaged.passRetained(box).toOpaque()
}

@_cdecl("harfi_composer_free")
public func harfi_composer_free(_ composer: UnsafeMutableRawPointer?) {
    guard let composer else { return }
    Unmanaged<ComposerBox>.fromOpaque(composer).release()
}

@_cdecl("harfi_composer_buffer")
public func harfi_composer_buffer(_ composer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let composer else { return nil }
    return owned(Unmanaged<ComposerBox>.fromOpaque(composer).takeUnretainedValue().composer.buffer)
}

/// A key as JSON: {"key": "text", "text": "a"} or {"key": "enter" | "backspace" | "escape" | "undo" |
/// "convertSelection" | "suggest" | "arrowLeft" | "arrowRight" | "arrowUp" | "arrowDown" | "tab" | "backtab" |
/// "other"}, with optional "secureInput", "cursorAtLastConversion" (booleans) and "selectedText".
@_cdecl("harfi_composer_key")
public func harfi_composer_key(_ composer: UnsafeMutableRawPointer?,
                               _ json: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let composer, let request = KeyRequest(json: string(json)) else { return owned(#"{"effect":"pass"}"#) }
    let box = Unmanaged<ComposerBox>.fromOpaque(composer).takeUnretainedValue()
    return owned(reply(box, box.composer.handle(request.key, context: request.context)))
}

@_cdecl("harfi_composer_pick")
public func harfi_composer_pick(_ composer: UnsafeMutableRawPointer?,
                                _ candidate: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let composer else { return owned(#"{"effect":"pass"}"#) }
    let box = Unmanaged<ComposerBox>.fromOpaque(composer).takeUnretainedValue()
    return owned(reply(box, box.composer.pick(string(candidate))))
}

/// The effect with what the chip row shows: the spellings offered, the one highlighted, the word being fixed.
private func reply(_ box: ComposerBox, _ effect: Effect) -> String {
    var reply = effectJSON(effect)
    reply["candidates"] = box.composer.currentCandidates
    if let choice = box.composer.currentChoice { reply["choice"] = choice }
    if let word = box.composer.selectedText {
        reply["word"] = word.shown
        reply["wordDoubtful"] = box.core.suggester?.doubtful(word.shown, word.latin) ?? false  // amber in the chip row
    }
    reply["spelling"] = box.composer.isSpelling
    if let typed = box.composer.typedSentence {  // the sentence as typed, the selected word's part highlighted
        reply["typed"] = typed.text
        if let selected = typed.selected {
            reply["typedStart"] = selected.lowerBound
            reply["typedLength"] = selected.count
        }
    }
    if case .commit(let text) = effect, box.composer.lastConversion != nil,
       let word = box.core.toPointOut(in: text) {  // a conversion was sent with a word the model was unsure of
        reply["unsureWord"] = word
    }
    if let habit = box.core.personal?.takeLearned() {  // a pick just made this a habit: the keyboard says so, once
        reply["learnedLatin"] = habit.latin
        reply["learnedSpelling"] = habit.spelling
    }
    if let fix = box.composer.fixingBeforeSending {  // the preview stays on screen around the chips
        reply["fixingWords"] = fix.words
        reply["fixingIndex"] = fix.index
        reply["fixingDoubtful"] = box.core.doubtful(fix.words, latin: fix.latin)
    }
    return encode(reply)
}

@_cdecl("harfi_free")
public func harfi_free(_ text: UnsafeMutablePointer<CChar>?) {
    free(text)
}

struct KeyRequest {
    let key: Key
    let context: Context

    init?(json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let name = object["key"] as? String else { return nil }
        let keys: [String: Key] = [
            "enter": .enter, "backspace": .backspace, "escape": .escape, "undo": .undo,
            "convertSelection": .convertSelection, "suggest": .suggest, "arrowLeft": .arrowLeft,
            "arrowRight": .arrowRight, "arrowUp": .arrowUp, "arrowDown": .arrowDown, "tab": .tab,
            "backtab": .backtab, "other": .other,
        ]
        if name == "text" {
            guard let text = object["text"] as? String, !text.isEmpty else { return nil }
            key = .text(text)
        } else {
            guard let known = keys[name] else { return nil }
            key = known
        }
        context = Context(secureInput: object["secureInput"] as? Bool ?? false,
                          cursorAtLastConversion: object["cursorAtLastConversion"] as? Bool ?? false,
                          selectedText: object["selectedText"] as? String)
    }
}

/// An effect as JSON: {"effect": name} plus its text fields ("marked", "text", "selected": [start, end] in UTF-16
/// units, "replacingLength").
func effectJSON(_ effect: Effect) -> [String: Any] {
    switch effect {
    case .pass: return ["effect": "pass"]
    case .consume: return ["effect": "consume"]
    case .update(let marked): return ["effect": "update", "marked": marked]
    case .commit(let text): return ["effect": "commit", "text": text]
    case .commitAndPass(let text): return ["effect": "commitAndPass", "text": text]
    case .replaceSelection(let text): return ["effect": "replaceSelection", "text": text]
    case .restore(let marked, let length): return ["effect": "restore", "marked": marked, "replacingLength": length]
    case .suggest(let marked, let selected, _, let length):
        var json: [String: Any] = ["effect": "suggest", "marked": marked, "selected": [selected.lowerBound, selected.upperBound]]
        if let length { json["replacingLength"] = length }
        return json
    case .commitAndCompose(let text, let marked): return ["effect": "commitAndCompose", "text": text, "marked": marked]
    }
}

func encode(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}
