// The core's C interface for the Windows keyboard (ADR 0032, task 2): plain C functions, UTF-8 JSON in and out, so
// a C++ text service can use the same behaviour as the Mac keyboard. Strings returned are owned by the caller and
// freed with harfi_free. The header is Apps/HarfiWindows/include/harfi_core.h.
//
//   harfi_core_open(rules_dir)          -> core handle, or NULL when the rule files cannot be read
//   harfi_convert(core, text)           -> the rules' Arabic for text
//   harfi_is_english(core, text)        -> 1 when text is plain English (left as typed), else 0
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
    let suggester: Suggester?

    init(rulesDirectory: URL) throws {
        let rules = try RuleConverter(rulesDirectory: rulesDirectory)
        self.rules = rules
        english = EnglishGuard(rulesDirectory: rulesDirectory, rules: rules)
        let lexicon = (try? Data(contentsOf: rulesDirectory.appending(path: RuleConverter.lexiconFileName))) ?? Data()
        let suggestions = Suggestions(dictionary: Suggestions.dictionary(lexicon: lexicon),
                                      arabicWords: Suggestions.arabicWords(lexicon: lexicon),
                                      rules: { rules.convert($0) })
        let spelling = try? SpellingOptions(rulesDirectory: rulesDirectory, rules: rules)
        suggester = Suggester(
            candidates: { shown, latin in suggestions.candidates(for: shown, latin: latin) },
            align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) }) },
            record: { _ in },
            spelling: spelling,
            doubtful: { shown, latin in spelling.map { suggestions.isDoubtful(shown, latin: latin, spelling: $0) } ?? false })
    }

    /// The text as the keyboard converts it without the model: plain English stays as typed.
    func convert(_ text: String) -> String {
        english?.isEnglish(text) == true ? text : rules.convert(text)
    }
}

final class ComposerBox {
    var composer: Composer
    init(core: Core) {
        composer = Composer(convert: { [core] in core.convert($0) }, suggester: core.suggester)
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
    if let word = box.composer.selectedText { reply["word"] = word.shown }
    reply["spelling"] = box.composer.isSpelling
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
