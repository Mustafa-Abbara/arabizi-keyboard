import Foundation

/// What a key press means to the keyboard, independent of AppKit.
public enum Key: Equatable, Sendable {
    /// One printable character (letters, digits, punctuation, space).
    case text(String)
    case enter
    case backspace
    case escape
    /// ⌘Z: undoes the last conversion when nothing happened since, otherwise the app's own undo.
    case undo
    /// ⌥Enter: converts the selected text in place (or the underlined text, like Enter).
    case convertSelection
    /// ⌥Tab right after a conversion: other spellings for its words (ADR 0027).
    case suggest
    /// ← and → (they move between words while suggestions are shown).
    case arrowLeft
    case arrowRight
    /// Tab and ⇧Tab (they change the last letter while a word is spelled; otherwise like `other`).
    case tab
    case backtab
    /// ↓ and ↑ (they move through the candidate window while it is shown; otherwise like `other`).
    case arrowDown
    case arrowUp
    /// Anything else: other keys, shortcuts with Command/Control/Option.
    case other
}

/// Facts about the text field that only the app can answer. The controller fills in what a key needs.
public struct Context: Equatable, Sendable {
    /// Password field: never compose.
    public var secureInput: Bool
    /// The cursor is still right after the last converted text, with nothing selected.
    public var cursorAtLastConversion: Bool
    /// The selected text, for ⌥Enter. nil when nothing is selected or the app cannot tell us.
    public var selectedText: String?

    public init(secureInput: Bool = false, cursorAtLastConversion: Bool = false, selectedText: String? = nil) {
        self.secureInput = secureInput
        self.cursorAtLastConversion = cursorAtLastConversion
        self.selectedText = selectedText
    }
}

/// What the input method must do in the app after a key press.
public enum Effect: Equatable, Sendable {
    /// Let the app handle the key (e.g. Enter on an empty buffer sends the message).
    case pass
    /// Swallow the key and change nothing. Used for ⌥Enter when there is nothing to convert: passing it on
    /// would let the app type a new line over the selection and delete it.
    case consume
    /// Show this text as underlined marked text; the key is consumed.
    case update(marked: String)
    /// Insert this text into the app and clear the marked text; the key is consumed.
    case commit(String)
    /// Insert this text, then let the app handle the key too.
    case commitAndPass(String)
    /// Replace the selected text with this text; the key is consumed.
    case replaceSelection(String)
    /// Replace the last `replacingLength` UTF-16 units before the cursor (the converted text) with
    /// this underlined text, so the user is composing again; the key is consumed.
    case restore(marked: String, replacingLength: Int)
    /// Show the converted text as marked text with one word selected (UTF-16 range) and offer `candidates` for
    /// it. `replacingLength`: on the first call, the converted text before the cursor that the marked text
    /// replaces; nil when the marked text is already there. The key is consumed.
    case suggest(marked: String, selected: Range<Int>, candidates: [String], replacingLength: Int?)
    /// Insert this text, then show `marked` as underlined text (a letter typed while suggestions were shown).
    case commitAndCompose(String, marked: String)
}

/// What suggestions need from the outside (ADR 0027): spellings for a word, which typed word each shown word
/// came from, where a correction goes, and the letters for spelling a word (nil: no spelling).
public struct Suggester: Sendable {
    public let candidates: @Sendable (_ shown: String, _ latin: String?) -> [String]
    public let align: @Sendable (_ latin: [String], _ shown: [String]) -> [Range<Int>?]
    public let record: @Sendable (Correction) -> Void
    public let now: @Sendable () -> Date
    public let spelling: SpellingOptions?

    public init(candidates: @escaping @Sendable (String, String?) -> [String],
                align: @escaping @Sendable ([String], [String]) -> [Range<Int>?],
                record: @escaping @Sendable (Correction) -> Void,
                now: @escaping @Sendable () -> Date = { Date() },
                spelling: SpellingOptions? = nil) {
        self.candidates = candidates
        self.align = align
        self.record = record
        self.now = now
        self.spelling = spelling
    }
}

/// Suggestions being shown for one conversion.
struct SuggestionSession: Equatable {
    let latin: String
    let latinWords: [String]
    var words: [String]
    let alignment: [Range<Int>?]
    var index: Int
    var candidates: [String]
    let original: String
    /// Set while the selected word is spelled letter by letter (⌥Tab a second time).
    var speller: Speller?
    /// The candidate moved to with ↓/↑ (Enter takes it); nil until an arrow is pressed.
    var highlighted: Int?

    var text: String { words.joined(separator: " ") }

    /// The UTF-16 range of word `index` in `text`.
    var selected: Range<Int> {
        let start = words[..<index].reduce(0) { $0 + $1.utf16.count + 1 }
        return start..<(start + words[index].utf16.count)
    }

    /// The typed words shown word `i` came from (one, or a run like `el shr` for الشر).
    func latinWord(_ i: Int) -> String? { alignment[i].map { latinWords[$0].joined(separator: " ") } }
}

/// The last conversion, kept for exactly one key press so ⌘Z can bring the Latin back.
public struct Conversion: Equatable, Sendable {
    public let latin: String
    public let converted: String
}

/// The Phase 1 typing behaviour (roadmap P1 step 2): type Latin, Enter converts, Enter again sends.
public struct Composer {
    public private(set) var buffer = ""
    public private(set) var lastConversion: Conversion?
    /// True while suggestions are shown.
    public var isSuggesting: Bool { session != nil }
    /// Which word is selected while suggestions are shown, and of how many (for logs: positions only, no text).
    public var selectedWord: (index: Int, count: Int)? { session.map { ($0.index, $0.words.count) } }
    /// True while the selected word is spelled letter by letter.
    public var isSpelling: Bool { session?.speller != nil }
    /// The spellings currently offered (for the candidate window); while spelling, the letters for the last key.
    public var currentCandidates: [String] { session?.speller?.labels ?? session?.candidates ?? [] }
    /// Which of `currentCandidates` is highlighted now (the letter chosen while spelling, or the one moved to with ↓/↑).
    public var currentChoice: Int? { session?.speller != nil ? session?.speller?.choice : session?.highlighted }
    private var session: SuggestionSession?
    private let convert: @Sendable (String) -> String
    /// A conversion already made for exactly this text (the live preview), used instead of converting again.
    private let ready: @Sendable (String) -> String?
    private let suggester: Suggester?

    public init(convert: @escaping @Sendable (String) -> String, suggester: Suggester? = nil,
                ready: @escaping @Sendable (String) -> String? = { _ in nil }) {
        self.convert = convert
        self.suggester = suggester
        self.ready = ready
    }

    public mutating func handle(_ key: Key, context: Context = Context()) -> Effect {
        // A conversion can only be undone by the very next key press.
        let previous = lastConversion
        lastConversion = nil
        if session != nil {
            return handleSuggestion(key)
        }
        if context.secureInput {
            // Password fields: never show or keep anything; hand back what was typed before, unchanged.
            return buffer.isEmpty ? .pass : .commitAndPass(take())
        }
        switch key {
        case .text(let character):
            if buffer.isEmpty && character == " " {
                return .pass
            }
            buffer += character
            return .update(marked: buffer)
        case .enter:
            return buffer.isEmpty ? .pass : .commit(convertAndRemember(take()))
        case .convertSelection:
            if !buffer.isEmpty {
                return .commit(convertAndRemember(take()))
            }
            guard let selected = context.selectedText, selected.contains(where: \.isLetter) else { return .consume }
            return .replaceSelection(convertAndRemember(selected))
        case .undo:
            if !buffer.isEmpty {
                return .commitAndPass(take())
            }
            guard let previous, context.cursorAtLastConversion else { return .pass }
            buffer = previous.latin
            return .restore(marked: buffer, replacingLength: previous.converted.utf16.count)
        case .escape:
            return buffer.isEmpty ? .pass : .commit(take())
        case .backspace:
            guard !buffer.isEmpty else { return .pass }
            buffer.removeLast()
            return .update(marked: buffer)
        case .suggest:
            guard buffer.isEmpty else { return .commit(convertAndRemember(take())) }
            guard let previous, context.cursorAtLastConversion, let started = startSuggesting(previous) else {
                lastConversion = previous
                return .consume
            }
            session = started
            return .suggest(marked: started.text, selected: started.selected, candidates: started.candidates,
                            replacingLength: previous.converted.utf16.count)
        case .arrowLeft, .arrowRight, .arrowDown, .arrowUp, .tab, .backtab, .other:
            return buffer.isEmpty ? .pass : .commitAndPass(take())
        }
    }

    /// The candidate window moved its highlight to `candidate` after ↓/↑: follow it, so the text shows that spelling
    /// (or, while spelling, that letter) and Enter takes it. nil when nothing changes.
    public mutating func highlight(_ candidate: String) -> Effect? {
        guard var current = session else { return nil }
        if let speller = current.speller {
            guard let index = speller.labels.firstIndex(of: candidate), index != speller.choice else { return nil }
            current.speller?.choose(candidate)
            session = current
            return spellingEffect(current)
        }
        guard let index = current.candidates.firstIndex(of: candidate), index != current.highlighted else { return nil }
        current.highlighted = index
        session = current
        var shown = current
        shown.words[shown.index] = WordParts(shown.words[shown.index]).with(candidate)
        return .suggest(marked: shown.text, selected: shown.selected, candidates: current.candidates,
                        replacingLength: nil)
    }

    /// A spelling (or, while spelling, a letter) clicked in the candidate window.
    public mutating func pick(_ candidate: String) -> Effect {
        guard var current = session else { return .pass }
        if current.speller != nil {
            guard current.speller?.choose(candidate) == true else { return .consume }
            session = current
            return spellingEffect(current)
        }
        guard let index = current.candidates.firstIndex(of: candidate) else { return .consume }
        return handle(.text(String(index + 1)))
    }

    private func startSuggesting(_ conversion: Conversion) -> SuggestionSession? {
        guard let suggester else { return nil }
        let words = conversion.converted.components(separatedBy: " ")
        let latinWords = conversion.latin.split(whereSeparator: \.isWhitespace).map(String.init)
        let alignment = suggester.align(latinWords, words)
        var session = SuggestionSession(latin: conversion.latin, latinWords: latinWords, words: words,
                                        alignment: alignment, index: 0, candidates: [], original: conversion.converted)
        // Start on the last word (the one just typed is the usual suspect), even without candidates: any word
        // can be spelled.
        guard let last = words.indices.last(where: { words[$0].contains(where: \.isLetter) }) else { return nil }
        session.index = last
        session.candidates = suggester.candidates(words[last], session.latinWord(last))
        return session
    }

    private mutating func handleSuggestion(_ key: Key) -> Effect {
        guard var current = session, let suggester else { return .pass }
        if current.speller != nil {
            return handleSpelling(key, current, suggester)
        }
        func finish(_ text: String) -> String {
            session = nil
            lastConversion = Conversion(latin: current.latin, converted: text)  // ⌘Z and ⌥Tab still work
            return text
        }
        func take(_ chosen: String) -> Effect {
            let parts = WordParts(current.words[current.index])
            if let latin = current.latinWord(current.index) {
                suggester.record(Correction(latin: WordParts(latin).core, chosen: chosen, rejected: parts.core,
                                            date: suggester.now()))
            }
            current.words[current.index] = parts.with(chosen)
            return .commit(finish(current.text))
        }
        switch key {
        case .text(let character):
            if let number = Int(character), number >= 1, number <= current.candidates.count {
                return take(current.candidates[number - 1])
            }
            let text = finish(current.text)
            if character == " " { return .commitAndPass(text) }
            buffer = character
            return .commitAndCompose(text, marked: buffer)
        case .arrowLeft, .arrowRight:
            // Arabic runs right to left: ← moves to the next word, → to the previous one. Every word with letters
            // can be selected (spelled with ⌥Tab when nothing is offered); numbers and emoji are skipped.
            let step = key == .arrowLeft ? 1 : -1
            var i = current.index + step
            while current.words.indices.contains(i) {
                if current.words[i].contains(where: \.isLetter) {
                    current.index = i
                    current.highlighted = nil
                    current.candidates = suggester.candidates(current.words[i], current.latinWord(i))
                    session = current
                    return .suggest(marked: current.text, selected: current.selected, candidates: current.candidates,
                                    replacingLength: nil)
                }
                i += step
            }
            return .consume
        case .arrowDown, .arrowUp:
            // Move through the spellings (round), shown in place of the word; Enter takes it, Esc restores it.
            let count = current.candidates.count
            var shown = current
            if count > 0 {
                let from = current.highlighted ?? (key == .arrowDown ? -1 : count)
                let highlighted = ((from + (key == .arrowDown ? 1 : -1)) % count + count) % count
                current.highlighted = highlighted
                session = current
                shown = current
                shown.words[shown.index] = WordParts(shown.words[shown.index]).with(current.candidates[highlighted])
            }
            return .suggest(marked: shown.text, selected: shown.selected, candidates: current.candidates,
                            replacingLength: nil)
        case .escape:
            return .commit(finish(current.original))
        case .suggest:
            // ⌥Tab a second time: spell the selected word letter by letter.
            guard let spelling = suggester.spelling else { return .commit(finish(current.text)) }
            current.speller = Speller(spelling)
            session = current
            return spellingEffect(current)
        case .enter:
            if let highlighted = current.highlighted { return take(current.candidates[highlighted]) }
            return .commit(finish(current.text))
        case .undo, .convertSelection:
            return .commit(finish(current.text))
        case .backspace, .tab, .backtab, .other:
            return .commitAndPass(finish(current.text))
        }
    }

    /// Keys while a word is spelled: letters and digits spell, Tab/⇧Tab or ↓/↑ change the last letter, Enter takes
    /// the word (and records it), Esc or Backspace on an empty word go back to the suggestions.
    private mutating func handleSpelling(_ key: Key, _ start: SuggestionSession, _ suggester: Suggester) -> Effect {
        var current = start
        guard var speller = current.speller else { return .pass }
        func backToSuggestions() -> Effect {
            current.speller = nil
            session = current
            return .suggest(marked: current.text, selected: current.selected, candidates: current.candidates,
                            replacingLength: nil)
        }
        func finish(_ text: String) -> String {
            session = nil
            lastConversion = Conversion(latin: current.latin, converted: text)
            return text
        }
        switch key {
        case .text(let character):
            guard speller.type(character) else { return .consume }
        case .tab, .arrowDown:
            speller.cycle(1)
        case .backtab, .arrowUp:
            speller.cycle(-1)
        case .backspace:
            if speller.isEmpty { return backToSuggestions() }
            speller.backspace()
        case .escape:
            return backToSuggestions()
        case .enter:
            guard !speller.arabic.isEmpty else { return backToSuggestions() }
            let parts = WordParts(current.words[current.index])
            if speller.arabic != parts.core, let latin = current.latinWord(current.index) {
                suggester.record(Correction(latin: WordParts(latin).core, chosen: speller.arabic, rejected: parts.core,
                                            date: suggester.now()))
            }
            current.words[current.index] = parts.with(speller.arabic)
            return .commit(finish(current.text))
        case .suggest, .arrowLeft, .arrowRight:
            break
        case .undo, .convertSelection:
            return .commit(finish(current.text))
        case .other:
            return .commitAndPass(finish(current.text))
        }
        current.speller = speller
        session = current
        return spellingEffect(current)
    }

    /// The text with the word being spelled in place of the selected word (the old word until a key is typed).
    private func spellingEffect(_ current: SuggestionSession) -> Effect {
        var shown = current
        if let speller = current.speller, !speller.isEmpty {
            shown.words[shown.index] = WordParts(shown.words[shown.index]).with(speller.arabic)
        }
        return .suggest(marked: shown.text, selected: shown.selected, candidates: current.speller?.labels ?? [],
                        replacingLength: nil)
    }

    /// Focus moved away while composing: return the Latin text so it is committed unchanged, never converted.
    /// While suggestions are shown, the converted text as it stands.
    public mutating func flush() -> String? {
        lastConversion = nil
        if let current = session {
            session = nil
            return current.text
        }
        return buffer.isEmpty ? nil : take()
    }

    private mutating func convertAndRemember(_ latin: String) -> String {
        let converted = ready(latin) ?? convert(latin)
        lastConversion = Conversion(latin: latin, converted: converted)
        return converted
    }

    private mutating func take() -> String {
        defer { buffer = "" }
        return buffer
    }
}
