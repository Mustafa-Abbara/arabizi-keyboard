/// What a key press means to the keyboard, independent of AppKit.
public enum Key: Equatable, Sendable {
    /// One printable character (letters, digits, punctuation, space).
    case text(String)
    case enter
    case backspace
    case escape
    /// Anything else: arrows, Tab, shortcuts with Command/Control/Option.
    case other
}

/// What the input method must do in the app after a key press.
public enum Effect: Equatable, Sendable {
    /// Let the app handle the key (e.g. Enter on an empty buffer sends the message).
    case pass
    /// Show this text as underlined marked text; the key is consumed.
    case update(marked: String)
    /// Insert this text into the app and clear the marked text; the key is consumed.
    case commit(String)
    /// Insert this text, then let the app handle the key too.
    case commitAndPass(String)
}

/// The Phase 1 typing behaviour (roadmap P1 step 2): type Latin, Enter converts, Enter again sends.
public struct Composer {
    public private(set) var buffer = ""
    private let convert: @Sendable (String) -> String

    public init(convert: @escaping @Sendable (String) -> String) {
        self.convert = convert
    }

    public mutating func handle(_ key: Key, secureInput: Bool = false) -> Effect {
        if secureInput {
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
            return buffer.isEmpty ? .pass : .commit(convert(take()))
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
        buffer.isEmpty ? nil : take()
    }

    private mutating func take() -> String {
        defer { buffer = "" }
        return buffer
    }
}
