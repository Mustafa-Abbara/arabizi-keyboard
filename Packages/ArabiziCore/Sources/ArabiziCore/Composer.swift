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
    private let convert: @Sendable (String) -> String

    public init(convert: @escaping @Sendable (String) -> String) {
        self.convert = convert
    }

    public mutating func handle(_ key: Key, context: Context = Context()) -> Effect {
        // A conversion can only be undone by the very next key press.
        let previous = lastConversion
        lastConversion = nil
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
        case .other:
            return buffer.isEmpty ? .pass : .commitAndPass(take())
        }
    }

    /// Focus moved away while composing: return the Latin text so it is committed unchanged, never converted.
    public mutating func flush() -> String? {
        lastConversion = nil
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
