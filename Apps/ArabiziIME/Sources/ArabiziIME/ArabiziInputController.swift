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
        let suggestions = Suggestions(dictionary: Suggestions.dictionary(lexicon: lexicon),
                                      rules: { rules.convert($0) })
        let store = CorrectionStore.standard()
        let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")
        log.info("suggestions ready; corrections \(store == nil ? "not recorded" : "recorded", privacy: .public)")
        let spelling = try? SpellingOptions(rulesDirectory: resources, rules: rules)
        if spelling == nil { log.error("spelling options not loaded") }
        return Suggester(
            candidates: { shown, latin in
                suggestions.personalized(for: shown, latin: latin, past: store?.all() ?? [])
            },
            align: { latin, shown in WordAlignment.align(latin: latin, shown: shown, rules: { rules.convert($0) }) },
            record: { correction in
                do { try store?.record(correction) } catch { log.error("correction not saved") }
            },
            spelling: spelling)
    }()
    /// Conversions made ahead while the user types (live preview), by the exact Latin text. Enter takes a ready one.
    private static let previews = PreviewCache()
    /// One conversion at a time, off the main thread: the keyboard never waits for the engine while the user types.
    private static let previewQueue = DispatchQueue(label: "lb.aub.arabizi.preview", qos: .userInitiated)
    private static let previewDelay: DispatchTimeInterval = .milliseconds(300)
    /// `defaults write lb.aub.arabizi.inputmethod.ArabiziIME livePreview -bool false` switches the preview off.
    private static var livePreviewEnabled: Bool { UserDefaults.standard.object(forKey: "livePreview") as? Bool ?? true }
    private let previewState = PreviewGeneration()
    private static let previewWork = PreviewWork()
    private var composer = Composer(convert: ArabiziInputController.convert, suggester: ArabiziInputController.suggester,
                                    ready: { ArabiziInputController.previews.arabic(for: $0) })
    private let candidatesPanel = CandidatesPanel()
    private let previewWindow = PreviewWindow()

    /// Converts what is typed in the background so the Arabic can be shown under it: at once when a word is finished
    /// (a space), after a short pause otherwise. Typing never waits for the engine.
    private func schedulePreview() {
        let latin = composer.buffer
        let generation = previewState.next()
        guard Self.livePreviewEnabled, latin.contains(where: \.isLetter), !composer.isSuggesting else { return }
        if latin.last?.isWhitespace == true {
            requestPreview(latin)
            return
        }
        let state = previewState
        nonisolated(unsafe) let controller = self  // the main queue is where InputMethodKit calls the controller
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDelay) {
            guard state.isCurrent(generation) else { return }  // typed on since: a later request covers it
            controller.requestPreview(latin)
        }
    }

    /// One worker converts the newest request, then any newer one, so the preview catches up with fast typing.
    private func requestPreview(_ latin: String) {
        if Self.previews.arabic(for: latin) != nil {
            showPreview()
            return
        }
        guard Self.previewWork.request(latin) else { return }  // a worker is running and will take this one
        nonisolated(unsafe) let controller = self
        Self.previewQueue.async {
            while let next = Self.previewWork.take() {
                Self.previews.set(next, Self.convert(next))
                DispatchQueue.main.async { controller.showPreview() }
            }
        }
    }

    /// The preview box above the typed text: the Arabic of what has been converted, then the Latin typed since.
    /// Hidden when nothing is converted yet or the user is not composing.
    private func showPreview() {
        guard !composer.isSuggesting, let client = client(),
              let text = Self.previews.display(for: composer.buffer) else { return hidePreview() }
        let marked = client.markedRange()
        let index = marked.location == NSNotFound ? max(0, client.selectedRange().location) : marked.location
        var line = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &line)
        nonisolated(unsafe) let window = previewWindow
        MainActor.assumeIsolated { window.show(text, above: line) }
    }

    private func hidePreview() {
        nonisolated(unsafe) let window = previewWindow
        MainActor.assumeIsolated { window.hide() }
    }

    /// The candidate window under the selected word (hidden when there is nothing to offer). InputMethodKit calls
    /// the controller on the main thread.
    private func showCandidates() {
        guard !composer.currentCandidates.isEmpty else { return hideCandidates() }
        hidePreview()
        nonisolated(unsafe) let panel = candidatesPanel, server = server()
        let candidates = composer.currentCandidates, spelling = composer.isSpelling, choice = composer.currentChoice
        MainActor.assumeIsolated { panel.show(server: server, candidates: candidates, spelling: spelling, choice: choice) }
    }

    private func hideCandidates() {
        nonisolated(unsafe) let panel = candidatesPanel
        MainActor.assumeIsolated { panel.hide() }
    }
    /// Where the cursor was right after the last conversion, so ⌘Z can tell whether it moved since.
    private var conversionEnd: Int?
    /// ↓/↑ presses handed to the candidate window whose new highlight has not been reported yet. Only these
    /// reports are followed: the window also reports a highlight of its own when its list is reloaded.
    private var windowMoves = 0

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

        // Once a spelling (or letter) is highlighted, ↓/↑ go to the candidate window, which moves and draws its own
        // highlight and reports it (candidateSelectionChanged); the first ↓/↑ highlights the first line.
        if key == .arrowDown || key == .arrowUp, composer.isSuggesting, composer.currentChoice != nil,
           !composer.currentCandidates.isEmpty {
            nonisolated(unsafe) let panel = candidatesPanel, keyEvent = event
            if MainActor.assumeIsolated({ panel.forward(keyEvent) }) {
                windowMoves += 1
                log.notice("\(key.kind, privacy: .public) -> candidate window")
                return true
            }
        }

        let effect = composer.handle(key, context: context)
        if key.isCommand {
            log.notice("\(key.kind, privacy: .public) -> \(effect.kind, privacy: .public)")
        }
        if key == .arrowLeft || key == .arrowRight || key == .suggest, let word = composer.selectedWord {
            log.notice("\(key.kind, privacy: .public): word \(word.index + 1, privacy: .public) of \(word.count, privacy: .public)")
        }
        let handled = apply(effect, to: client, selection: selection)
        if case .update = effect {
            schedulePreview()
            showPreview()  // the converted words stay on screen while typing
        } else {
            _ = previewState.next()
            if !composer.buffer.isEmpty { showPreview() }
        }
        return handled
    }

    /// Carries out what the composer decided, in the app.
    private func apply(_ effect: Effect, to client: IMKTextInput, selection: NSRange? = nil) -> Bool {
        defer {
            if composer.lastConversion == nil { conversionEnd = nil }
            if !composer.isSuggesting {
                hideCandidates()
                windowMoves = 0
                if composer.buffer.isEmpty { hidePreview() }  // still composing: showPreview decides
            }
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

    /// The candidate window moved its highlight after a ↓/↑ it was given: show that spelling (or letter) in the
    /// text, so Enter takes it. The window is not refreshed here, which would move its highlight again.
    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        guard windowMoves > 0, let highlighted = candidateString?.string, let client = client() else { return }
        windowMoves -= 1
        log.notice("candidate window highlight followed")
        guard let effect = composer.highlight(highlighted),
              case .suggest(let marked, let selected, _, _) = effect else { return }
        client.setMarkedText(marked, selectionRange: NSRange(location: selected.lowerBound, length: selected.count),
                             replacementRange: Self.notFound)
    }

    /// The spellings shown in the candidate window (InputMethodKit asks for them).
    override func candidates(_ sender: Any!) -> [Any]! {
        composer.currentCandidates
    }

    /// A spelling clicked in the candidate window: the same as pressing its number. While spelling, a letter for
    /// the last key (by its text: a number key would spell a letter there).
    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let picked = candidateString?.string, let client = client() else { return }
        let effect = composer.pick(picked)
        guard effect != .consume else { return }
        _ = apply(effect, to: client)
        if !composer.isSuggesting { rememberConversionEnd(in: client) }
    }

    /// Called when focus moves away (click elsewhere, app switch) while composing.
    override func commitComposition(_ sender: Any!) {
        _ = previewState.next()
        hideCandidates()
        hidePreview()
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
    /// What the window lists now: reloading it puts its highlight back on the first line, so it is reloaded only
    /// when the list changes, not when ↓/↑ or Tab only move the highlight.
    private var listed: (candidates: [String], spelling: Bool)?

    /// Spellings are picked with the keys 1–5. While spelling, digits are letters, so the window has no number
    /// keys and highlights the letter chosen for the last key (Tab/⇧Tab and ↓/↑ move it).
    @MainActor func show(server: IMKServer?, candidates: [String], spelling: Bool, choice: Int?) {
        if window == nil {
            window = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        }
        guard let window else { return }
        if listed?.candidates != candidates || listed?.spelling != spelling {
            window.setSelectionKeys(spelling ? [] : [18, 19, 20, 21, 23].map { NSNumber(value: $0) })  // the keys 1–5
            window.update()
            listed = (candidates, spelling)
        }
        window.show(kIMKLocateCandidatesBelowHint)
        if let choice {
            window.selectCandidate(withIdentifier: window.candidateIdentifier(atLineNumber: choice))
        }
    }

    @MainActor func hide() {
        window?.hide()
        listed = nil
    }

    /// Hands a ↓/↑ key to the visible window, which moves and draws its highlight itself; false when it is hidden.
    @MainActor func forward(_ event: NSEvent) -> Bool {
        guard let window, window.isVisible() else { return false }
        window.interpretKeyEvents([event])
        return true
    }
}

// Names for logs: kinds only, never the text the user typed.
extension Key {
    var isCommand: Bool {
        self == .enter || self == .undo || self == .convertSelection || self == .escape || self == .suggest
            || self == .arrowDown || self == .arrowUp || self == .tab || self == .backtab
    }
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Effect {
    var kind: String { "\(self)".prefix(while: { $0 != "(" }).description }
}

extension Key {
    /// macOS virtual key codes: 36 Return, 76 keypad Enter, 51 Delete (backspace), 53 Escape, 48 Tab,
    /// 123 ←, 124 →, 125 ↓ and 126 ↑.
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
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            self = modifiers.isEmpty ? .tab : .backtab
            return
        }
        if modifiers.isEmpty, event.keyCode == 123 || event.keyCode == 124 {
            self = event.keyCode == 123 ? .arrowLeft : .arrowRight
            return
        }
        if modifiers.isEmpty, event.keyCode == 125 || event.keyCode == 126 {
            self = event.keyCode == 125 ? .arrowDown : .arrowUp
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


/// The conversions made ahead for the live preview: the last few, by the exact Latin text.
final class PreviewCache: @unchecked Sendable {  // `items` is behind `lock`
    private let lock = NSLock()
    private var items: [(latin: String, arabic: String)] = []

    func set(_ latin: String, _ arabic: String) {
        lock.withLock {
            items.removeAll { $0.latin == latin }
            items.append((latin, arabic))
            if items.count > 16 { items.removeFirst() }
        }
    }

    /// The Arabic for exactly this text.
    func arabic(for latin: String) -> String? {
        lock.withLock { items.last { $0.latin == latin }?.arabic }
    }

    /// What the preview window shows for the text typed so far: the Arabic of the longest converted start that ends
    /// at a word boundary, then the Latin typed since. nil when no start of the text is converted yet.
    func display(for buffer: String) -> String? {
        lock.withLock {
            let starts = items.filter { item in
                guard buffer.hasPrefix(item.latin) else { return false }
                if item.latin.count == buffer.count || item.latin.last?.isWhitespace == true { return true }
                return buffer[buffer.index(buffer.startIndex, offsetBy: item.latin.count)].isWhitespace
            }
            guard let best = starts.max(by: { $0.latin.count < $1.latin.count }) else { return nil }
            let head = best.arabic.trimmingCharacters(in: .whitespaces)
            let rest = String(buffer.dropFirst(best.latin.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? head : head + " " + rest
        }
    }
}

/// The newest text waiting to be converted for the preview, and whether a worker is running.
final class PreviewWork: @unchecked Sendable {  // both fields are behind `lock`
    private let lock = NSLock()
    private var pending: String?
    private var running = false

    /// Records `latin` as the newest request; true when the caller must start a worker.
    func request(_ latin: String) -> Bool {
        lock.withLock {
            pending = latin
            if running { return false }
            running = true
            return true
        }
    }

    /// The newest request, or nil (and the worker ends) when there is none.
    func take() -> String? {
        lock.withLock {
            guard let next = pending else {
                running = false
                return nil
            }
            pending = nil
            return next
        }
    }
}

/// Which typing the pending preview belongs to: each key press makes the older previews stale.
final class PreviewGeneration: @unchecked Sendable {  // `value` is behind `lock`
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    func isCurrent(_ generation: Int) -> Bool { lock.withLock { value == generation } }
}


/// The small box above the typed text that shows the live preview: one rounded, translucent label that follows the
/// system light or dark appearance, never takes the focus or the mouse, and sits just above the line being typed.
final class PreviewWindow {
    private var panel: NSPanel?
    private var label: NSTextField?
    private static let maxWidth: CGFloat = 560
    private static let padding = NSSize(width: 14, height: 8)

    @MainActor private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let label = NSTextField(wrappingLabelWithString: "")
        self.label = label
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 20)
        label.textColor = .labelColor
        label.baseWritingDirection = .natural
        label.maximumNumberOfLines = 4
        label.isSelectable = false
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        return panel
    }

    /// Shows `text` just above `line` (the line being typed, in screen coordinates; empty when the app gives none).
    @MainActor func show(_ text: String, above line: NSRect) {
        let panel = ensurePanel()
        guard let label else { return }
        label.stringValue = text
        let fitted = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: Self.maxWidth - 2 * Self.padding.width,
                                                            height: 10_000)) ?? .zero
        let size = NSSize(width: ceil(fitted.width) + 2 * Self.padding.width,
                          height: ceil(fitted.height) + 2 * Self.padding.height)
        label.frame = NSRect(x: Self.padding.width, y: Self.padding.height, width: ceil(fitted.width),
                             height: ceil(fitted.height))
        let anchor = line == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : line
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_600, height: 1_000)
        var origin = NSPoint(x: anchor.minX, y: anchor.maxY + 6)  // above the line
        if origin.y + size.height > visible.maxY { origin.y = anchor.minY - size.height - 6 }  // no room: below it
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    @MainActor func hide() {
        panel?.orderOut(nil)
    }
}
