import AppKit
import ArabiziEngineClient

/// The row of spellings above the text (⌥Tab), where the live preview sits, in the palette: the first spelling on the right, as Arabic
/// reads, each with its number key, then "Spell it". While spelling, the letters for the last key. The keys work
/// as before (the composer handles them); a click picks a chip without taking the focus from the app, and the mouse
/// over a spelling shows it in the text, as ↓/↑ do. Above the chips, the sentence as typed, with the words the
/// selected one came from highlighted.
final class CorrectionChips {
    private var panel: NSPanel?
    private var column: NSStackView?
    private var row: NSStackView?
    private var typedLine: TypedLine?
    private var hintToken = 0
    /// While a list is open: the largest size it has had, so the box only grows and never jumps back and forth,
    /// and the row's width, which the chips stretch to fill so no gap is left beside them.
    private var listSize: NSSize?
    private var rowWidth: NSLayoutConstraint?

    @MainActor private func ensurePanel() -> (NSPanel, NSStackView) {
        if let panel, let row { return (panel, row) }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let background = PreviewBackground()
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.userInterfaceLayoutDirection = .rightToLeft
        let typedLine = TypedLine()
        typedLine.isHidden = true
        // The typed sentence on top, then the chips, both on the right as Arabic reads.
        let column = NSStackView(views: [typedLine, row])
        column.orientation = .vertical
        column.alignment = .trailing
        column.spacing = 6
        column.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        column.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            column.topAnchor.constraint(equalTo: background.topAnchor),
            column.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        self.column = column
        self.row = row
        self.typedLine = typedLine
        return (panel, row)
    }

    /// Shows the spellings above `line` (the text's first line, in screen coordinates). `choice` is highlighted.
    /// `typed`: the sentence as typed, with the UTF-16 range of the words the selected word came from.
    @MainActor func show(word: String?, doubtful: Bool, candidates: [String], spelling: Bool, choice: Int?,
                         typed: (text: String, selected: Range<Int>?)?, above line: NSRect,
                         preview: ((CGFloat) -> NSRect)? = nil, side: Bool? = nil,
                         pick: @escaping (String) -> Void, hover: @escaping (String) -> Void = { _ in },
                         spellIt: @escaping () -> Void) {
        hintToken += 1
        let (panel, row) = ensurePanel()
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let typed, !typed.text.isEmpty {
            typedLine?.set(typed.text, selected: typed.selected)
            typedLine?.isHidden = false
        } else {
            typedLine?.isHidden = true
        }
        if let word, !spelling {  // the word being fixed, first (on the right): amber when it looks wrong
            row.addArrangedSubview(ChipView(current: word, doubtful: doubtful))
        }
        for (i, candidate) in candidates.enumerated() {
            let number = spelling || i >= 9 ? nil : "\(i + 1)"
            row.addArrangedSubview(ChipView(text: candidate, number: number, selected: i == choice,
                                            onClick: { pick(candidate) }, onHover: { hover(candidate) }))
        }
        if spelling {
            row.addArrangedSubview(ChipView(hint: candidates.isEmpty ? "Type the word" : "Tab changes it · Enter takes it"))
        } else {
            row.addArrangedSubview(ChipView(quiet: "Spell it", onClick: spellIt))
        }
        rowWidth?.isActive = false
        row.distribution = .fill
        let natural = column?.fittingSize ?? row.fittingSize
        let size = NSSize(width: max(natural.width, listSize?.width ?? 0), height: max(natural.height, listSize?.height ?? 0))
        listSize = size
        // The chips fill the box's width (the typed line or an earlier word may have made it wider).
        let inner = size.width - 12  // the column's insets
        if row.fittingSize.width < inner - 0.5 {
            row.distribution = .fillProportionally
            rowWidth = row.widthAnchor.constraint(equalToConstant: inner)
            rowWidth?.isActive = true
        }
        height = size.height
        // With the preview: it is placed knowing the chips' height, and the chips go on its far side from the text.
        let besides = preview?(size.height)
        place(panel, size: size, above: line, beside: besides, side: side)
        // What decides the side: the preview when the chips sit beside it, else the chips themselves.
        placed = (besides ?? panel.frame, line == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : line)
    }

    /// Where the last chip row (or the preview it sits beside) went, and the line it was placed around.
    @MainActor private(set) var placed: (box: NSRect, line: NSRect)?

    /// Lights `candidate`'s chip and dims the others, in place: the row keeps its size and place, so the chip under
    /// the mouse stays the same chip.
    @MainActor func select(_ candidate: String) {
        for case let chip as ChipView in row?.arrangedSubviews ?? [] where chip.spelling != nil {
            chip.selected = chip.spelling == candidate
        }
    }

    /// A short line above the text after a conversion, hidden after `seconds` or by the next chips.
    /// The height of the last chip row shown with its sentence: the preview keeps this much room over it.
    @MainActor private(set) var height: CGFloat?

    @MainActor func showHint(_ text: String, above line: NSRect, seconds: Double = 3) {
        hintToken += 1
        listSize = nil
        rowWidth?.isActive = false
        row?.distribution = .fill
        let token = hintToken
        let (panel, row) = ensurePanel()
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        typedLine?.isHidden = true
        row.addArrangedSubview(ChipView(hint: text))
        place(panel, size: column?.fittingSize ?? row.fittingSize, above: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.hintToken == token else { return }
            self.hide()
        }
    }

    @MainActor func hide() {
        hintToken += 1
        listSize = nil
        panel?.orderOut(nil)
    }

    @MainActor private func place(_ panel: NSPanel, size: NSSize, above line: NSRect, beside preview: NSRect? = nil,
                                  side: Bool? = nil) {
        let anchor = line == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : line
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_600, height: 1_000)
        // Above the line, where the live preview sits (typing boxes are often at the bottom of the screen).
        var origin = NSPoint(x: anchor.minX,
                             y: StackPlacement.y(for: anchor, height: size.height, top: visible.maxY, above: side))
        if let preview { origin = NSPoint(x: preview.minX, y: StackPlacement.y(beside: preview, of: anchor, height: size.height)) }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        let frame = NSRect(origin: origin, size: size)
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !panel.isVisible, !still else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        // The row rises a few points into place while it fades in.
        panel.setFrame(frame.offsetBy(dx: 0, dy: -8), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }
}

/// One chip: a spelling (Arabic, with its number key), a quiet action ("Spell it") or a hint that cannot be clicked.
final class ChipView: NSView {
    private enum Style { case spelling, quiet, hint, current }
    private let style: Style
    private let onClick: (() -> Void)?
    private var onHover: (() -> Void)?
    private var label: NSTextField!
    /// The spelling this chip offers, and its number key (nil for the other kinds of chip).
    private(set) var spelling: String?
    private var number: String?
    var selected: Bool {
        didSet {
            guard selected != oldValue else { return }
            if let spelling {
                label.attributedStringValue = Self.spellingLabel(spelling, number: number, selected: selected)
            }
            needsDisplay = true
        }
    }

    private static func spellingLabel(_ text: String, number: String?, selected: Bool) -> NSAttributedString {
        let label = NSMutableAttributedString()
        if let number {
            label.append(NSAttributedString(string: number + "  ", attributes: [
                .font: NSFont.systemFont(ofSize: 12 * Theme.scale), .foregroundColor: selected ? Theme.accent : Theme.textMuted]))
        }
        label.append(NSAttributedString(string: text, attributes: [
            .font: Theme.arabic(20 * Theme.scale), .foregroundColor: selected ? Theme.accent : Theme.text]))
        return label
    }

    convenience init(text: String, number: String?, selected: Bool, onClick: @escaping () -> Void,
                     onHover: (() -> Void)? = nil) {
        self.init(Self.spellingLabel(text, number: number, selected: selected), style: .spelling, selected: selected,
                  onClick: onClick)
        spelling = text
        self.number = number
        self.onHover = onHover
        setAccessibilityLabel(number.map { "\(text), key \($0)" } ?? text)
    }

    convenience init(quiet text: String, onClick: @escaping () -> Void) {
        self.init(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13 * Theme.scale),
                                                                .foregroundColor: Theme.textMuted]),
                  style: .quiet, selected: false, onClick: onClick)
        setAccessibilityLabel(text)
    }

    /// The word being fixed, with an arrow to its spellings: amber with a dashed line when it looks wrong.
    convenience init(current word: String, doubtful: Bool) {
        let label = NSMutableAttributedString(string: word, attributes: [
            .font: Theme.arabic(20 * Theme.scale), .foregroundColor: doubtful ? Theme.warning : Theme.textMuted])
        label.append(NSAttributedString(string: "  ←", attributes: [.font: NSFont.systemFont(ofSize: 13 * Theme.scale),
                                                                     .foregroundColor: Theme.textMuted]))
        self.init(label, style: .current, selected: false, onClick: nil)
        setAccessibilityLabel(doubtful ? "Fixing \(word), it looks wrong" : "Fixing \(word)")
        setAccessibilityElement(true)
    }

    convenience init(hint text: String) {
        self.init(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13 * Theme.scale),
                                                                .foregroundColor: Theme.textMuted]),
                  style: .hint, selected: false, onClick: nil)
    }

    private init(_ text: NSAttributedString, style: Style, selected: Bool, onClick: (() -> Void)?) {
        self.style = style
        self.selected = selected
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = style == .hint || style == .current ? 0 : 1
        let label = NSTextField(labelWithAttributedString: text)
        self.label = label
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32 * Theme.scale),
        ])
        if onClick != nil {
            setAccessibilityRole(.button)
            setAccessibilityElement(true)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .spelling, .quiet:
                layer?.backgroundColor = (selected ? Theme.accentSoft : Theme.surface).cgColor
                layer?.borderColor = (selected ? Theme.accent : Theme.border).cgColor
            case .hint, .current:
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The panel never becomes key, so the area works whichever app is active.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard onHover != nil else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                                                              .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }

    override func mouseMoved(with event: NSEvent) { onHover?() }  // the row was rebuilt under a still mouse

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return onClick != nil
    }
}

/// The sentence as typed, above the chips: its words laid out right to left like the Arabic (the first word on the
/// right), so the arrows move its highlight the same way as in the Arabic. The words the selected Arabic word came
/// from sit on a soft accent pill; the others are quiet. Not clickable.
final class TypedLine: NSView {
    private struct Word {
        let text: NSAttributedString
        let chosen: Bool
        var frame: NSRect
    }
    private var words: [Word] = []
    private var size = NSSize.zero
    private static let padding = NSSize(width: 5, height: 2)
    private static let gap: CGFloat = 6

    /// `selected`: the UTF-16 range in `text` of the chosen words (a word is chosen when it starts inside it).
    func set(_ text: String, selected: Range<Int>?) {
        let font = NSFont.systemFont(ofSize: 13 * Theme.scale)
        var start = 0
        words = []
        for piece in text.components(separatedBy: " ") {
            defer { start += piece.utf16.count + 1 }
            guard !piece.isEmpty else { continue }
            let chosen = selected?.contains(start) ?? false
            let label = NSAttributedString(string: piece, attributes: [
                .font: font, .foregroundColor: chosen ? Theme.accent : Theme.textMuted])
            words.append(Word(text: label, chosen: chosen, frame: .zero))
        }
        let height = ceil(words.map { $0.text.size().height }.max() ?? 0) + 2 * Self.padding.height
        let widths = words.map { ceil($0.text.size().width) + 2 * Self.padding.width }
        let width = widths.reduce(0, +) + Self.gap * CGFloat(max(words.count - 1, 0))
        // Right to left: the first word against the right edge.
        var right = width
        for i in words.indices {
            words[i].frame = NSRect(x: right - widths[i], y: 0, width: widths[i], height: height)
            right -= widths[i] + Self.gap
        }
        size = NSSize(width: width, height: height)
        setAccessibilityElement(true)
        setAccessibilityLabel("Typed: " + text)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { size }

    override func draw(_ dirtyRect: NSRect) {
        for word in words {
            if word.chosen {
                Theme.accentSoft.setFill()
                NSBezierPath(roundedRect: word.frame, xRadius: 6, yRadius: 6).fill()
            }
            word.text.draw(at: NSPoint(x: word.frame.minX + Self.padding.width,
                                       y: word.frame.minY + Self.padding.height))
        }
    }
}
