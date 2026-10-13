import AppKit
import ArabiziCore
import Carbon
import InputMethodKit

/// Thin bridge between macOS key events and `Composer`. All behaviour lives in ArabiziCore (tested there).
/// Never log what the user types: only key kinds and lengths.
@objc(ArabiziInputController)
final class ArabiziInputController: IMKInputController {
    private var composer = Composer(convert: ToyTransliterator.convert)

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        let effect = composer.handle(Key(event), secureInput: IsSecureEventInputEnabled())
        switch effect {
        case .pass:
            return false
        case .update(let marked):
            setMarked(marked, in: client)
            return true
        case .commit(let text):
            insert(text, into: client)
            return true
        case .commitAndPass(let text):
            insert(text, into: client)
            return false
        }
    }

    /// Called when focus moves away (click elsewhere, app switch) while composing.
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput, let text = composer.flush() else { return }
        insert(text, into: client)
    }

    private func setMarked(_ text: String, in client: IMKTextInput) {
        let caret = NSRange(location: (text as NSString).length, length: 0)
        client.setMarkedText(text, selectionRange: caret, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func insert(_ text: String, into client: IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        log.debug("committed \(text.count) characters")
    }
}

extension Key {
    /// macOS virtual key codes: 36 Return, 76 keypad Enter, 51 Delete (backspace), 53 Escape.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.isDisjoint(with: [.command, .control, .option]) {
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
