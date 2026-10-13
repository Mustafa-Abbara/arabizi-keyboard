import AppKit
import ArabiziCore
import Carbon
import InputMethodKit

/// Thin bridge between macOS key events and `Composer`. All behaviour lives in ArabiziCore (tested there).
/// Never log what the user types: only key kinds and lengths.
@objc(ArabiziInputController)
final class ArabiziInputController: IMKInputController {
    private var composer = Composer(convert: ToyTransliterator.convert)
    /// Where the cursor was right after the last conversion, so ⌘Z can tell whether it moved since.
    private var conversionEnd: Int?

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        let key = Key(event)
        var context = Context(secureInput: IsSecureEventInputEnabled())
        var selection: NSRange?
        switch key {
        case .undo:
            let cursor = client.selectedRange()
            context.cursorAtLastConversion = cursor.length == 0 && cursor.location != NSNotFound
                && cursor.location == conversionEnd
        case .convertSelection where composer.buffer.isEmpty:
            selection = Self.usable(client.selectedRange())
            if let range = selection {
                // Two ways to read the selection; apps support one, the other or neither.
                // actualRange must be a real pointer: InputMethodKit writes to it without a nil check and
                // crashed the keyboard (EXC_BAD_ACCESS, 13 Oct 2026), which let the app type a new line instead.
                var actualRange = NSRange(location: NSNotFound, length: 0)
                context.selectedText = client.string(from: range, actualRange: &actualRange)
                    ?? client.attributedSubstring(from: range)?.string
            }
            log.notice("""
                ⌥Enter: selection \(selection == nil ? "not reported" : "reported", privacy: .public), \
                text \(context.selectedText == nil ? "not readable" : "readable", privacy: .public)
                """)
        default:
            break
        }

        let effect = composer.handle(key, context: context)
        if key.isCommand {
            log.notice("\(key.kind, privacy: .public) -> \(effect.kind, privacy: .public)")
        }
        defer { if composer.lastConversion == nil { conversionEnd = nil } }
        switch effect {
        case .pass:
            return false
        case .consume:
            NSSound.beep()
            return true
        case .update(let marked):
            setMarked(marked, in: client)
            return true
        case .commit(let text):
            insert(text, into: client)
            rememberConversionEnd(in: client)
            return true
        case .commitAndPass(let text):
            insert(text, into: client)
            return false
        case .replaceSelection(let text):
            guard let selection else { return false }
            insert(text, into: client, replacing: selection)
            rememberConversionEnd(in: client)
            return true
        case .restore(let marked, let replacingLength):
            guard let end = conversionEnd, end >= replacingLength else {
                _ = composer.flush()  // the app moved the text under us: stop composing, let ⌘Z be the app's
                return false
            }
            setMarked(marked, in: client, replacing: NSRange(location: end - replacingLength, length: replacingLength))
            log.debug("restored \(marked.count) Latin characters")
            return true
        }
    }

    /// Called when focus moves away (click elsewhere, app switch) while composing.
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput, let text = composer.flush() else { return }
        insert(text, into: client)
    }

    private static let notFound = NSRange(location: NSNotFound, length: 0)

    /// A real, non-empty selection; apps that cannot report one return NSNotFound.
    private static func usable(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound || range.length == 0 || range.length == NSNotFound ? nil : range
    }

    /// Some apps (often browsers and Electron) cannot report the cursor; then ⌘Z simply stays the app's undo.
    private func rememberConversionEnd(in client: IMKTextInput) {
        let cursor = client.selectedRange()
        conversionEnd = cursor.location == NSNotFound ? nil : cursor.location
    }

    private func setMarked(_ text: String, in client: IMKTextInput, replacing range: NSRange = notFound) {
        let caret = NSRange(location: (text as NSString).length, length: 0)
        client.setMarkedText(text, selectionRange: caret, replacementRange: range)
    }

    private func insert(_ text: String, into client: IMKTextInput, replacing range: NSRange = notFound) {
        client.insertText(text, replacementRange: range)
        log.debug("committed \(text.count) characters")
    }
}

// Names for logs: kinds only, never the text the user typed.
extension Key {
    var isCommand: Bool { self == .enter || self == .undo || self == .convertSelection || self == .escape }
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Effect {
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Key {
    /// macOS virtual key codes: 36 Return, 76 keypad Enter, 51 Delete (backspace), 53 Escape.
    init(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            self = .undo  // ⌘⇧Z (redo) has Shift too, so it stays .other
            return
        }
        if modifiers == .option, isReturn {
            self = .convertSelection
            return
        }
        if !modifiers.isDisjoint(with: [.command, .control, .option]) {
            self = .other
            return
        }
        switch event.keyCode {
        case 36, 76: self = .enter
        case 51: self = .backspace
        case 53: self = .escape
        default:
            if let characters = event.characters, characters.count == 1,
               let scalar = characters.unicodeScalars.first, (0x20...0x7E).contains(scalar.value) {
                self = .text(characters)
            } else {
                self = .other
            }
        }
    }
}
