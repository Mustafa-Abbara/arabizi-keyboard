import AppKit

/// The row of spellings above the text (⌥Tab), where the live preview sits, in the palette: the first spelling on the right, as Arabic
/// reads, each with its number key, then "Spell it". While spelling, the letters for the last key. The keys work
/// as before (the composer handles them); a click picks a chip without taking the focus from the app.
final class CorrectionChips {
    private var panel: NSPanel?
    private var row: NSStackView?
    private var hintToken = 0

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
        row.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        row.userInterfaceLayoutDirection = .rightToLeft
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            row.topAnchor.constraint(equalTo: background.topAnchor),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        self.row = row
        return (panel, row)
    }

    /// Shows the spellings above `line` (the text's first line, in screen coordinates). `choice` is highlighted.
    @MainActor func show(word: String?, doubtful: Bool, candidates: [String], spelling: Bool, choice: Int?,
                         above line: NSRect,
                         pick: @escaping (String) -> Void, spellIt: @escaping () -> Void) {
        hintToken += 1
        let (panel, row) = ensurePanel()
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let word, !spelling {  // the word being fixed, first (on the right): amber when it looks wrong
            row.addArrangedSubview(ChipView(current: word, doubtful: doubtful))
        }
        for (i, candidate) in candidates.enumerated() {
            let number = spelling || i >= 9 ? nil : "\(i + 1)"
            row.addArrangedSubview(ChipView(text: candidate, number: number, selected: i == choice,
                                            onClick: { pick(candidate) }))
        }
        if spelling {
            row.addArrangedSubview(ChipView(hint: candidates.isEmpty ? "Type the word" : "Tab changes it · Enter takes it"))
        } else {
            row.addArrangedSubview(ChipView(quiet: "Spell it", onClick: spellIt))
        }
        place(panel, size: row.fittingSize, above: line)
    }

    /// A short line above the text after a conversion, hidden after `seconds` or by the next chips.
    @MainActor func showHint(_ text: String, above line: NSRect, seconds: Double = 3) {
        hintToken += 1
        let token = hintToken
        let (panel, row) = ensurePanel()
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        row.addArrangedSubview(ChipView(hint: text))
        place(panel, size: row.fittingSize, above: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.hintToken == token else { return }
            self.hide()
        }
    }

    @MainActor func hide() {
        hintToken += 1
        panel?.orderOut(nil)
    }

    @MainActor private func place(_ panel: NSPanel, size: NSSize, above line: NSRect) {
        let anchor = line == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : line
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_600, height: 1_000)
        // Above the line, where the live preview sits (typing boxes are often at the bottom of the screen).
        var origin = NSPoint(x: anchor.minX, y: anchor.maxY + 6)
        if origin.y + size.height > visible.maxY { origin.y = anchor.minY - size.height - 6 }  // no room: below
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
    private let selected: Bool
    private let onClick: (() -> Void)?

    convenience init(text: String, number: String?, selected: Bool, onClick: @escaping () -> Void) {
        let label = NSMutableAttributedString()
        if let number {
            label.append(NSAttributedString(string: number + "  ", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: selected ? Theme.accent : Theme.textMuted]))
        }
        label.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: selected ? Theme.accent : Theme.text]))
        self.init(label, style: .spelling, selected: selected, onClick: onClick)
        setAccessibilityLabel(number.map { "\(text), key \($0)" } ?? text)
    }

    convenience init(quiet text: String, onClick: @escaping () -> Void) {
        self.init(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                                .foregroundColor: Theme.textMuted]),
                  style: .quiet, selected: false, onClick: onClick)
        setAccessibilityLabel(text)
    }

    /// The word being fixed, with an arrow to its spellings: amber with a dashed line when it looks wrong.
    convenience init(current word: String, doubtful: Bool) {
        let label = NSMutableAttributedString(string: word, attributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: doubtful ? Theme.warning : Theme.textMuted])
        label.append(NSAttributedString(string: "  ←", attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                                     .foregroundColor: Theme.textMuted]))
        self.init(label, style: .current, selected: false, onClick: nil)
        setAccessibilityLabel(doubtful ? "Fixing \(word), it looks wrong" : "Fixing \(word)")
        setAccessibilityElement(true)
    }

    convenience init(hint text: String) {
        self.init(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13),
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
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
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

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return onClick != nil
    }
}
