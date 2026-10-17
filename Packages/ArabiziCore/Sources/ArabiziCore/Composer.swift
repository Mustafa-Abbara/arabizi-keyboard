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
    /// Anything else: arrows, Tab, shortcuts with Command/Control/Option.
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
/// came from, and where a correction goes.
public struct Suggester: Sendable {
    public let candidates: @Sendable (_ shown: String, _ latin: String?) -> [String]
    public let align: @Sendable (_ latin: [String], _ shown: [String]) -> [Int?]
    public let record: @Sendable (Correction) -> Void
    public let now: @Sendable () -> Date

    public init(candidates: @escaping @Sendable (String, String?) -> [String],
                align: @escaping @Sendable ([String], [String]) -> [Int?],
                record: @escaping @Sendable (Correction) -> Void,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.candidates = candidates
        self.align = align
        self.record = record
        self.now = now
    }
}

/// Suggestions being shown for one conversion.
struct SuggestionSession: Equatable {
    let latin: String
    let latinWords: [String]
    var words: [String]
    let alignment: [Int?]
    var index: Int
    var candidates: [String]
    let original: String

    var text: String { words.joined(separator: " ") }

    /// The UTF-16 range of word `index` in `text`.
    var selected: Range<Int> {
        let start = words[..<index].reduce(0) { $0 + $1.utf16.count + 1 }
        return start..<(start + words[index].utf16.count)
    }

    func latinWord(_ i: Int) -> String? { alignment[i].map { latinWords[$0] } }
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
    /// The spellings currently offered (for the candidate window).
    public var currentCandidates: [String] { session?.candidates ?? [] }
    private var session: SuggestionSession?
    private let convert: @Sendable (String) -> String
    private let suggester: Suggester?

    public init(convert: @escaping @Sendable (String) -> String, suggester: Suggester? = nil) {
        self.convert = convert
        self.suggester = suggester
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
        case .arrowLeft, .arrowRight, .other:
            return buffer.isEmpty ? .pass : .commitAndPass(take())
        }
    }

    private func startSuggesting(_ conversion: Conversion) -> SuggestionSession? {
        guard let suggester else { return nil }
        let words = conversion.converted.components(separatedBy: " ")
        let latinWords = conversion.latin.split(whereSeparator: \.isWhitespace).map(String.init)
        let alignment = suggester.align(latinWords, words)
        var session = SuggestionSession(latin: conversion.latin, latinWords: latinWords, words: words,
                                        alignment: alignment, index: 0, candidates: [], original: conversion.converted)
        // Start on the last word that has candidates (the one just typed is the usual suspect).
        for i in words.indices.reversed() where words[i].contains(where: \.isLetter) {
            let offered = suggester.candidates(words[i], session.latinWord(i))
            if !offered.isEmpty {
                session.index = i
                session.candidates = offered
                return session
            }
        }
        return nil
    }

    private mutating func handleSuggestion(_ key: Key) -> Effect {
        guard var current = session, let suggester else { return .pass }
        func finish(_ text: String) -> String {
            session = nil
            lastConversion = Conversion(latin: current.latin, converted: text)  // ⌘Z and ⌥Tab still work
            return text
        }
        switch key {
        case .text(let character):
            if let number = Int(character), (1...current.candidates.count).contains(number) {
                let shown = current.words[current.index]
                let parts = WordParts(shown)
                let chosen = current.candidates[number - 1]
                if let latin = current.latinWord(current.index) {
                    suggester.record(Correction(latin: WordParts(latin).core, chosen: chosen, rejected: parts.core,
                                                date: suggester.now()))
                }
                current.words[current.index] = parts.with(chosen)
                return .commit(finish(current.text))
            }
            let text = finish(current.text)
            if character == " " { return .commitAndPass(text) }
            buffer = character
            return .commitAndCompose(text, marked: buffer)
        case .arrowLeft, .arrowRight:
            // Arabic runs right to left: ← moves to the next word, → to the previous one.
            let step = key == .arrowLeft ? 1 : -1
            var i = current.index + step
            while current.words.indices.contains(i) {
                let offered = current.words[i].contains(where: \.isLetter)
                    ? suggester.candidates(current.words[i], current.latinWord(i)) : []
                if !offered.isEmpty {
                    current.index = i
                    current.candidates = offered
                    session = current
                    return .suggest(marked: current.text, selected: current.selected, candidates: offered,
                                    replacingLength: nil)
                }
                i += step
            }
            return .consume
        case .escape:
            return .commit(finish(current.original))
        case .enter, .suggest, .undo, .convertSelection:
            return .commit(finish(current.text))
        case .backspace, .other:
            return .commitAndPass(finish(current.text))
        }
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
        let converted = convert(latin)
        lastConversion = Conversion(latin: latin, converted: converted)
        return converted
    }

    private mutating func take() -> String {
        defer { buffer = "" }
        return buffer
    }
}
