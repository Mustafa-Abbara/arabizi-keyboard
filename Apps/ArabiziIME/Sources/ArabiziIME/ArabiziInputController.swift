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
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let rules = quickConvert
        guard let engine = EngineClient(resources: resources) else { return rules }
        engine.warmUp()
        return { text in engine.convert(text) ?? rules(text) }
    }()
    /// The rule converter from Resources, nil without the rule files.
    private static let ruleConverter: RuleConverter? = {
        let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")
        do {
            let converter = try RuleConverter(rulesDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            log.info("Rule converter loaded")
            return converter
        } catch {
            log.error("Rule files not loaded (\(String(describing: error), privacy: .public)): using the toy converter")
            return nil
        }
    }()
    /// The rules alone: instant, used as the fallback and for the first preview while the model works.
    private static let quickConvert: @Sendable (String) -> String = {
        guard let converter = ruleConverter else { return ToyTransliterator.convert }
        return { converter.convert($0) }
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
                                      arabicWords: Suggestions.arabicWords(lexicon: lexicon),
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
            spelling: spelling,
            doubtful: { shown, latin in spelling.map { suggestions.isDoubtful(shown, latin: latin, spelling: $0) } ?? false })
    }()
    /// Conversions made ahead while the user types (live preview), by the exact Latin text. Enter takes a ready one.
    private static let previews = PreviewCache(isClitic: { ruleConverter?.isClitic($0) ?? false })
    /// One conversion at a time, off the main thread: the keyboard never waits for the engine while the user types.
    private static let previewQueue = DispatchQueue(label: "lb.aub.arabizi.preview", qos: .userInitiated)
    private static let previewDelay: DispatchTimeInterval = .milliseconds(300)
    private static var livePreviewEnabled: Bool { Settings.livePreview }
    private let previewState = PreviewGeneration()
    private static let previewWork = PreviewWork()
    private var composer = Composer(convert: ArabiziInputController.convert, suggester: ArabiziInputController.suggester,
                                    ready: { ArabiziInputController.previews.arabic(for: $0) })
    private let chips = CorrectionChips()
    private let previewWindow = PreviewWindow()

    /// Converts what is typed in the background so the Arabic can be shown under it: at once when a word is finished
    /// (a space), after a short pause otherwise. Typing never waits for the engine.
    private func schedulePreview() {
        let latin = composer.buffer
        let generation = previewState.next()
        guard Self.livePreviewEnabled, latin.contains(where: \.isLetter), !composer.isSuggesting else { return }
        if latin.last?.isWhitespace == true, !Self.previews.endsWithClitic(latin) {
            // A finished word: the rules at once, then the model. After a small word (el, w, b) the next word
            // decides its Arabic, so that waits for the next word or a pause.
            if Self.previews.arabic(for: latin) == nil {
                Self.previews.set(latin, Self.quickConvert(latin), final: false)
                showPreview()
            }
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
        let index = marked.location == NSNotFound ? client.selectedRange().location : marked.location
        let line = lineRect(client, at: [index])
        nonisolated(unsafe) let window = previewWindow
        // Until ↑ has been used a few times, a quiet reminder that a word can be fixed before converting.
        let words = text.arabic.components(separatedBy: " ")
        let doubtful = Self.doubtfulWords(words, latin: String(composer.buffer.dropLast(text.typedSince)))
        let hint = text.latin.isEmpty && Settings.personality != .quiet
            && UserDefaults.standard.integer(forKey: "previewFixUses") < Self.previewFixUses ? "↑ fix a word" : nil
        MainActor.assumeIsolated { window.show(arabic: words, doubtful: doubtful, latin: text.latin, hint: hint, above: line) }
    }

    /// Which shown words look wrong (a letter no typed key writes, in a word never seen written): dotted in the preview.
    private static func doubtfulWords(_ words: [String], latin: String) -> Set<Int> {
        guard let suggester else { return [] }
        let typed = latin.split(whereSeparator: \.isWhitespace).map(String.init)
        let alignment = suggester.align(typed, words)
        return Set(words.indices.filter { i in
            suggester.doubtful(words[i], alignment[i].map { typed[$0].joined(separator: " ") })
        })
    }

    private func hidePreview() {
        nonisolated(unsafe) let window = previewWindow
        MainActor.assumeIsolated { window.hide() }
    }

    /// The chip row above the text (hidden when there is nothing to offer and nothing to spell).
    /// `wordStart` is where the word starts in the marked text. InputMethodKit calls the controller on the main thread.
    private func showCandidates(wordStart: Int) {
        let candidates = composer.currentCandidates, spelling = composer.isSpelling, choice = composer.currentChoice
        guard !candidates.isEmpty || spelling, let client = client() else { return hideCandidates() }
        hidePreview()
        // Above the text's first line, the same place as the live preview, lined up with the word when the app
        // reports it on that line.
        let marked = client.markedRange()
        let start = marked.location == NSNotFound ? client.selectedRange().location : marked.location
        var line = lineRect(client, at: [start])
        if line != .zero, let word = plausibleLine(client, at: start + wordStart), abs(word.midY - line.midY) < 2 {
            line.origin.x = word.minX
        }
        nonisolated(unsafe) let chips = chips, controller = self
        MainActor.assumeIsolated {
            chips.show(candidates: candidates, spelling: spelling, choice: choice, above: line,
                       pick: { controller.chipPicked($0) }, spellIt: { controller.spellFromChip() })
        }
    }

    private func hideCandidates() {
        nonisolated(unsafe) let chips = chips
        MainActor.assumeIsolated { chips.hide() }
    }

    /// After a conversion, a one-line hint that ⌥Tab fixes a word: the first few times only, never in Quiet mode,
    /// and no more once ⌥Tab has been used a few times.
    private func showFixHint(in client: IMKTextInput) {
        let shown = UserDefaults.standard.integer(forKey: "fixHintShown")
        guard shown < Self.fixHintTimes, UserDefaults.standard.integer(forKey: "fixHintUses") < Self.fixHintUses,
              Settings.personality != .quiet else { return }
        UserDefaults.standard.set(shown + 1, forKey: "fixHintShown")
        let cursor = client.selectedRange().location
        let line = lineRect(client, at: [cursor - 1, cursor])
        guard line != .zero else { return }
        nonisolated(unsafe) let chips = chips
        MainActor.assumeIsolated { chips.showHint("Not quite? ⌥Tab to fix a word", above: line) }
    }

    private static let fixHintTimes = 5, fixHintUses = 3, previewFixUses = 3

    /// The last line position an app reported that made sense: used when the app reports none or a wrong one.
    private var lastLine: NSRect?

    /// The screen rectangle of the line holding the first of `indices` the app reports sensibly, else the last good
    /// one, else .zero (the boxes then sit at the mouse, which only happens before any position is known).
    private func lineRect(_ client: IMKTextInput, at indices: [Int]) -> NSRect {
        for index in indices {
            if let line = plausibleLine(client, at: index) {
                lastLine = line
                return line
            }
        }
        return lastLine ?? .zero
    }

    /// The line rectangle at `index`, nil when the app gives none or one that cannot be a line of text on a screen.
    private func plausibleLine(_ client: IMKTextInput, at index: Int) -> NSRect? {
        guard index >= 0, index != NSNotFound else { return nil }
        var line = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &line)
        guard line.height > 4, line.height < 200, line.origin != .zero,
              NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: line.minX, y: line.midY)) })
        else { return nil }
        return line
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

        let wasComposing = !composer.buffer.isEmpty && !composer.isSuggesting
        let effect = composer.handle(key, context: context)
        if key.isCommand {
            log.notice("\(key.kind, privacy: .public) -> \(effect.kind, privacy: .public)")
        }
        if key == .arrowLeft || key == .arrowRight || key == .suggest, let word = composer.selectedWord {
            log.notice("\(key.kind, privacy: .public): word \(word.index + 1, privacy: .public) of \(word.count, privacy: .public)")
        }
        if key == .suggest {  // ⌥Tab used: after a few times the hint is no longer needed
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "fixHintUses") + 1, forKey: "fixHintUses")
        }
        if key == .arrowUp, case .suggest = effect, wasComposing {  // fixing before sending
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "previewFixUses") + 1, forKey: "previewFixUses")
        }
        let handled = apply(effect, to: client, selection: selection)
        if key == .enter, case .commit = effect, composer.lastConversion != nil { showFixHint(in: client) }
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
            showCandidates(wordStart: selected.lowerBound)
            return true
        case .commitAndCompose(let text, let marked):
            insert(text, into: client)
            setMarked(marked, in: client)
            return true
        }
    }

    /// The keyboard's items in the input menu (the ع icon in the menu bar): quick toggles, and the Harfi window.
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let preview = NSMenuItem(title: "Live preview", action: #selector(toggleLivePreview(_:)), keyEquivalent: "")
        preview.state = Settings.livePreview ? .on : .off
        menu.addItem(preview)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Your words…", action: #selector(showWords(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Harfi settings…", action: #selector(showSettings(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Help and shortcuts", action: #selector(showHelp(_:)), keyEquivalent: ""))
        return menu
    }

    @objc func toggleLivePreview(_ sender: Any?) {
        Settings.livePreview.toggle()
        if !Settings.livePreview { hidePreview() }
    }

    @objc func showWords(_ sender: Any?) { openWindow(.words) }
    @objc func showSettings(_ sender: Any?) { openWindow(.typing) }
    @objc func showHelp(_ sender: Any?) { openWindow(.help) }

    private func openWindow(_ tab: SettingsModel.Tab) {
        MainActor.assumeIsolated { SettingsWindow.shared.show(tab) }
    }

    /// A chip clicked: the same as pressing its number. While spelling, a letter for the last key (by its text:
    /// a number key would spell a letter there).
    fileprivate func chipPicked(_ picked: String) {
        guard let client = client() else { return }
        let effect = composer.pick(picked)
        guard effect != .consume else { return }
        _ = apply(effect, to: client)
        if !composer.isSuggesting { rememberConversionEnd(in: client) }
    }

    /// "Spell it" clicked: the same as ⌥Tab a second time.
    fileprivate func spellFromChip() {
        guard let client = client() else { return }
        _ = apply(composer.handle(.suggest, context: Context(secureInput: IsSecureEventInputEnabled())), to: client)
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


/// The conversions made ahead for the live preview: the last few, by the exact Latin text. A conversion is final
/// (the model's, which Enter may use) or quick (the rules', shown only until the model's arrives).
final class PreviewCache: @unchecked Sendable {  // `items` is behind `lock`
    private let lock = NSLock()
    private var items: [(latin: String, arabic: String, final: Bool)] = []
    private let isClitic: @Sendable (String) -> Bool

    init(isClitic: @escaping @Sendable (String) -> Bool) { self.isClitic = isClitic }

    func set(_ latin: String, _ arabic: String, final: Bool = true) {
        lock.withLock {
            if !final, items.contains(where: { $0.latin == latin && $0.final }) { return }
            items.removeAll { $0.latin == latin }
            items.append((latin, arabic, final))
            if items.count > 16 { items.removeFirst() }
        }
    }

    /// The final Arabic for exactly this text.
    func arabic(for latin: String) -> String? {
        lock.withLock { items.last { $0.latin == latin && $0.final }?.arabic }
    }

    /// True when the last word of `latin` is a small word whose Arabic depends on the next one (el, w, b).
    func endsWithClitic(_ latin: String) -> Bool {
        guard let last = latin.split(whereSeparator: \.isWhitespace).last else { return false }
        return isClitic(String(last))
    }

    /// What the preview window shows for the text typed so far: the Arabic of the longest converted start that ends
    /// at a word boundary, then the Latin typed since. A start ending in a small word (el, w, b) is not used, so
    /// a lone ال never shows before its word. nil when no start of the text is converted yet.
    func display(for buffer: String) -> (arabic: String, latin: String, typedSince: Int)? {
        lock.withLock {
            let starts = items.filter { item in
                guard buffer.hasPrefix(item.latin), !endsWithClitic(item.latin) || item.latin.count == buffer.count
                else { return false }
                if item.latin.count == buffer.count || item.latin.last?.isWhitespace == true { return true }
                return buffer[buffer.index(buffer.startIndex, offsetBy: item.latin.count)].isWhitespace
            }
            guard let best = starts.max(by: { ($0.latin.count, $0.final ? 1 : 0) < ($1.latin.count, $1.final ? 1 : 0) })
            else { return nil }
            let head = best.arabic.trimmingCharacters(in: .whitespaces)
            let rest = String(buffer.dropFirst(best.latin.count)).trimmingCharacters(in: .whitespaces)
            return (head, rest, buffer.count - best.latin.count)
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
        let background = PreviewBackground()
        label.font = .systemFont(ofSize: 20)
        label.textColor = Theme.text
        label.baseWritingDirection = .natural
        label.maximumNumberOfLines = 4
        label.isSelectable = false
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        return panel
    }

    /// Shows the converted Arabic, then the Latin typed since in a quieter colour, just above `line` (the line being
    /// typed, in screen coordinates; empty when the app gives none).
    @MainActor func show(arabic words: [String], doubtful: Set<Int>, latin: String, hint: String? = nil,
                         above line: NSRect) {
        let panel = ensurePanel()
        guard let label else { return }
        let text = NSMutableAttributedString()
        for (i, word) in words.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: Theme.text]
            if doubtful.contains(i) {  // likely wrong: a dotted line under it, and ↑ starts on it
                attributes[.underlineStyle] = NSUnderlineStyle.single.union(.patternDot).rawValue
                attributes[.underlineColor] = Theme.warning
            }
            if i > 0 { text.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 20)])) }
            text.append(NSAttributedString(string: word, attributes: attributes))
        }
        if !latin.isEmpty {
            text.append(NSAttributedString(string: " " + latin, attributes: [
                .font: NSFont.systemFont(ofSize: 16), .foregroundColor: Theme.textMuted]))
        }
        if let hint {
            text.append(NSAttributedString(string: "   " + hint, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.accent]))
        }
        label.attributedStringValue = text
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

/// The preview box: the palette's surface with a thin border and rounded corners, redrawn when the appearance
/// changes (layer colours do not follow it on their own).
final class PreviewBackground: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Theme.surface.cgColor
            layer?.borderColor = Theme.border.cgColor
        }
    }
}
