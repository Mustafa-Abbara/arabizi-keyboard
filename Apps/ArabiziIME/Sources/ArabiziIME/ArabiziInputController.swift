import AppKit
import ArabiziCore
import Carbon
import InputMethodKit
import os

/// Thin bridge between macOS key events and `Composer`. All behaviour lives in ArabiziCore (tested there).
/// Never log what the user types: only key kinds and lengths.
@objc(ArabiziInputController)
final class ArabiziInputController: IMKInputController {
    /// Conversion for all text fields: the sandboxed engine service (the fine-tuned model with protected spans,
    /// output checks and its own rule fallback, ADR 0020), and the rule converter here if the service cannot answer
    /// in time. The rule files and config come from Resources (scripts/build_ime.sh); without them the P1 toy
    /// converter keeps the keyboard usable.
    private static let convert: @Sendable (String) -> String = {
        let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let rules: @Sendable (String) -> String
        do {
            let converter = try RuleConverter(rulesDirectory: resources)
            log.info("Rule converter loaded")
            rules = { converter.convert($0) }
        } catch {
            log.error("Rule files not loaded (\(String(describing: error), privacy: .public)): using the toy converter")
            rules = ToyTransliterator.convert
        }
        guard let engine = EngineClient(resources: resources) else { return rules }
        engine.warmUp()
        return { text in engine.convert(text) ?? rules(text) }
    }()
    /// Other spellings for a converted word (⌥Tab, ADR 0027): the rules and their dictionary from Resources, and
    /// the user's picks recorded in an encrypted file on this Mac. nil without the rule files: ⌥Tab then beeps.
    private static let suggester: Suggester? = {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        guard let rules = try? RuleConverter(rulesDirectory: resources),
              let lexicon = try? Data(contentsOf: resources.appending(path: RuleConverter.lexiconFileName)) else {
            return nil
        }
        let suggestions = Suggestions(knownArabic: Suggestions.knownArabic(lexicon: lexicon),
                                      rules: { rules.convert($0) })
        let store = CorrectionStore.standard()
        let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")
        log.info("suggestions ready; corrections \(store == nil ? "not recorded" : "recorded", privacy: .public)")
        return Suggester(
            candidates: { shown, latin in suggestions.candidates(for: shown, latin: latin) },
            align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) }) },
            record: { correction in
                do { try store?.record(correction) } catch { log.error("correction not saved") }
            })
    }()
    private var composer = Composer(convert: ArabiziInputController.convert, suggester: ArabiziInputController.suggester)
    private let candidatesPanel = CandidatesPanel()

    /// The candidate window under the selected word. InputMethodKit calls the controller on the main thread.
    private func showCandidates() {
        nonisolated(unsafe) let panel = candidatesPanel, server = server()
        MainActor.assumeIsolated { panel.show(server: server) }
    }

    private func hideCandidates() {
        nonisolated(unsafe) let panel = candidatesPanel
        MainActor.assumeIsolated { panel.hide() }
    }
    /// Where the cursor was right after the last conversion, so ⌘Z can tell whether it moved since.
    private var conversionEnd: Int?

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        let key = Key(event)
        var context = Context(secureInput: IsSecureEventInputEnabled())
        var selection: NSRange?
        switch key {
        case .undo, .suggest:
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
        return apply(effect, to: client, selection: selection)
    }

    /// Carries out what the composer decided, in the app.
    private func apply(_ effect: Effect, to client: IMKTextInput, selection: NSRange? = nil) -> Bool {
        defer {
            if composer.lastConversion == nil { conversionEnd = nil }
            if !composer.isSuggesting { hideCandidates() }
        }
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
            guard selection != nil else { return false }
            // Insert like typing: it replaces the current selection in every app. Passing the selection as an
            // explicit replacementRange only worked in TextEdit; other apps ignored it (manual test, 13 Oct 2026).
            insert(text, into: client)
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
        case .suggest(let marked, let selected, _, let replacingLength):
            var range = Self.notFound
            if let replacingLength {
                guard let end = conversionEnd, end >= replacingLength else {
                    _ = composer.flush()  // the app cannot report the cursor: leave the text alone
                    NSSound.beep()
                    return true
                }
                range = NSRange(location: end - replacingLength, length: replacingLength)
            }
            client.setMarkedText(marked, selectionRange: NSRange(location: selected.lowerBound, length: selected.count),
                                 replacementRange: range)
            showCandidates()
            return true
        case .commitAndCompose(let text, let marked):
            insert(text, into: client)
            setMarked(marked, in: client)
            return true
        }
    }

    /// The spellings shown in the candidate window (InputMethodKit asks for them).
    override func candidates(_ sender: Any!) -> [Any]! {
        composer.currentCandidates
    }

    /// A spelling clicked in the candidate window: the same as pressing its number.
    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let picked = candidateString?.string, let client = client(),
              let index = composer.currentCandidates.firstIndex(of: picked) else { return }
        _ = apply(composer.handle(.text(String(index + 1))), to: client)
        rememberConversionEnd(in: client)
    }

    /// Called when focus moves away (click elsewhere, app switch) while composing.
    override func commitComposition(_ sender: Any!) {
        hideCandidates()
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

/// The macOS candidate window (InputMethodKit), created on first use. It asks the controller for the spellings.
final class CandidatesPanel {
    private var window: IMKCandidates?

    @MainActor func show(server: IMKServer?) {
        if window == nil {
            window = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
            window?.setSelectionKeys([18, 19, 20, 21, 23].map { NSNumber(value: $0) })  // the keys 1–5
        }
        window?.update()
        window?.show(kIMKLocateCandidatesBelowHint)
    }

    @MainActor func hide() {
        window?.hide()
    }
}

// Names for logs: kinds only, never the text the user typed.
extension Key {
    var isCommand: Bool {
        self == .enter || self == .undo || self == .convertSelection || self == .escape || self == .suggest
    }
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Effect {
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Key {
    /// macOS virtual key codes: 36 Return, 76 keypad Enter, 51 Delete (backspace), 53 Escape, 48 Tab,
    /// 123 ← and 124 →.
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
        if modifiers == .option, event.keyCode == 48 {
            self = .suggest
            return
        }
        if modifiers.isEmpty, event.keyCode == 123 || event.keyCode == 124 {
            self = event.keyCode == 123 ? .arrowLeft : .arrowRight
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
