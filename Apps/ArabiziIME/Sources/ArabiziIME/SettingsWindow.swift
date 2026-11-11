import AppKit
import ArabiziCore
import SwiftUI

/// The keyboard's settings, shared by the menu, the window and the controller (the keyboard's own defaults).
enum Settings {
    /// `defaults write lb.aub.arabizi.inputmethod.ArabiziIME livePreview -bool false` switches the preview off.
    static var livePreview: Bool {
        get { UserDefaults.standard.object(forKey: "livePreview") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "livePreview") }
    }

    /// Incremental conversion while typing (ADR 0037): faster, and an answer can differ by a word. On by default.
    static var fasterPreview: Bool {
        get { UserDefaults.standard.object(forKey: "fasterPreview") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fasterPreview") }
    }

    /// Larger Arabic in the preview and the chips.
    static var largerText: Bool {
        get { UserDefaults.standard.bool(forKey: "largerText") }
        set { UserDefaults.standard.set(newValue, forKey: "largerText") }
    }

    enum Personality: String, CaseIterable, Identifiable {
        case full, calm, quiet
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var detail: String {
            switch self {
            case .full: "Greetings and small touches"
            case .calm: "Friendly words only"
            case .quiet: "Just the essentials"
            }
        }
    }

    /// The three practice steps of the welcome page, ticked when the user does them in any app.
    enum Practice: String, CaseIterable {
        case converted, fixed, privacy
        var key: String { "practice." + rawValue }
    }

    static func done(_ step: Practice) -> Bool { UserDefaults.standard.bool(forKey: step.key) }

    /// Ticks a practice step; the welcome page updates if it is open.
    static func complete(_ step: Practice) {
        guard !done(step) else { return }
        UserDefaults.standard.set(true, forKey: step.key)
        NotificationCenter.default.post(name: practiceChanged, object: nil)
    }

    static let practiceChanged = Notification.Name("HarfiPracticeChanged")

    static var personality: Personality {
        get { UserDefaults.standard.string(forKey: "personality").flatMap(Personality.init) ?? .full }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "personality") }
    }
}

/// The Harfi window (Settings…, Your words…, Help in the input menu): a panel that works without making the
/// keyboard the active app, since an input method runs in the background.
@MainActor final class SettingsWindow {
    static let shared = SettingsWindow()
    private var panel: NSPanel?
    private let model = SettingsModel()

    func show(_ tab: SettingsModel.Tab) {
        model.tab = tab
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "Harfi"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Theme.background
        panel.contentView = NSHostingView(rootView: SettingsView(model: model))
        return panel
    }
}

/// What the window shows; the corrections are read from the encrypted record each time the window opens.
@MainActor final class SettingsModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case welcome = "Welcome", typing = "Typing", words = "Your words", privacy = "Privacy", help = "Help"
        var id: String { rawValue }
    }

    struct Word: Identifiable {
        let latin: String, arabic: String, times: Int
        var id: String { latin + "\u{0}" + arabic }
    }

    @Published var tab: Tab = .typing
    @Published var livePreview = Settings.livePreview { didSet { Settings.livePreview = livePreview } }
    @Published var personality = Settings.personality { didSet { Settings.personality = personality } }
    @Published var largerText = Settings.largerText { didSet { Settings.largerText = largerText } }
    @Published var fasterPreview = Settings.fasterPreview { didSet { Settings.fasterPreview = fasterPreview } }
    @Published private(set) var words: [Word] = []
    @Published private(set) var fixes = 0
    /// Spellings Harfi now writes by itself (ADR 0033), and the ones the user said no to.
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var refused: [Habit] = []
    private let store = CorrectionStore.standard()

    @Published private(set) var practice: Set<Settings.Practice> = []
    private var practiceObserver: NSObjectProtocol?

    init() {
        practiceObserver = NotificationCenter.default.addObserver(forName: Settings.practiceChanged, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadPractice() }
        }
    }

    func reloadPractice() {
        practice = Set(Settings.Practice.allCases.filter(Settings.done))
    }

    func readPrivacy() {
        Settings.complete(.privacy)
        tab = .privacy
    }

    func reload() {
        reloadPractice()
        livePreview = Settings.livePreview
        personality = Settings.personality
        largerText = Settings.largerText
        fasterPreview = Settings.fasterPreview
        let all = store?.all() ?? []
        fixes = all.count
        var counts: [String: (latin: String, arabic: String, times: Int)] = [:]
        for fix in all {
            let key = fix.latin.lowercased() + "\u{0}" + fix.chosen
            counts[key] = (fix.latin.lowercased(), fix.chosen, (counts[key]?.times ?? 0) + 1)
        }
        words = counts.values.map { Word(latin: $0.latin, arabic: $0.arabic, times: $0.times) }
            .sorted { ($0.times, $1.latin) > ($1.times, $0.latin) }
        let no = store?.refused() ?? []
        habits = Habits.learned(from: all).filter { !no.contains($0) }.sorted { $0.latin < $1.latin }
        refused = no.sorted { $0.latin < $1.latin }
    }

    func refuse(_ habit: Habit) {
        try? store?.refuse(habit)
        reload()
    }

    func allow(_ habit: Habit) {
        try? store?.allow(habit)
        reload()
    }

    func forget(_ word: Word) {
        try? store?.forget(latin: word.latin, chosen: word.arabic)
        reload()
    }

    func forgetAll() {
        try? store?.wipe()
        reload()
    }

    var greeting: String? {
        guard personality != .quiet else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        return (5..<12).contains(hour) ? "صباح الخير" : "مساء الخير"
    }
}

private extension Color {
    static let ink = Color(nsColor: Theme.text)
    static let muted = Color(nsColor: Theme.textMuted)
    static let surface = Color(nsColor: Theme.surface)
    static let line = Color(nsColor: Theme.border)
    static let accent = Color(nsColor: Theme.accent)
    static let accentSoft = Color(nsColor: Theme.accentSoft)
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingForgetAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let greeting = model.greeting {
                    Text(greeting).font(Font(Theme.arabic(16))).foregroundStyle(Color.muted)
                }
                Text("Harfi").font(.system(size: 22, weight: .medium)).foregroundStyle(Color.ink)
            }
            HStack(spacing: 4) {
                ForEach(SettingsModel.Tab.allCases) { tab in
                    Button(tab.rawValue) { model.tab = tab }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(model.tab == tab ? Color.accentSoft : .clear, in: .rect(cornerRadius: 8))
                        .foregroundStyle(model.tab == tab ? Color.accent : Color.ink)
                        .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.tab {
                    case .welcome: welcome
                    case .typing: typing
                    case .words: words
                    case .privacy: privacy
                    case .help: help
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 20)
        .frame(width: 520, height: 460, alignment: .topLeading)
        .background(Color(nsColor: Theme.background))
        .tint(Color.accent)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
    }

    private func step(_ number: Int, _ done: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.accent : Color.accentSoft).frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.surface)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accent)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(Color.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "not done yet")
    }

    private var welcome: some View {
        Group {
            card {
                Text(model.practice.count == 3 ? "You're all set. Type away." : "Welcome. Let's try it once.")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink)
                Text("Do these in any app where you type. Each step ticks by itself when you do it.")
                    .font(.system(size: 12)).foregroundStyle(Color.muted)
                Button("Open Notes to try it") {
                    if let notes = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
                        NSWorkspace.shared.openApplication(at: notes, configuration: .init())
                    }
                }
            }
            card {
                step(1, model.practice.contains(.converted), "Type kifak, shu 3am ta3mel? and press Enter",
                     "Your text becomes Arabic. Press Enter again to send it. ⌘Z right after brings your Latin back.")
                Divider().overlay(Color.line)
                step(2, model.practice.contains(.fixed), "Type a sentence, then press ↑ before Enter",
                     "The preview opens on a word. ← → choose another word, a number picks its spelling.")
                Divider().overlay(Color.line)
                HStack(alignment: .top) {
                    step(3, model.practice.contains(.privacy), "See how your words stay on this Mac",
                         "Nothing you type is sent anywhere.")
                    Spacer()
                    Button("Read") { model.readPrivacy() }
                }
            }
        }
    }

    private var typing: some View {
        Group {
            card {
                Toggle(isOn: $model.livePreview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live preview").foregroundStyle(Color.ink)
                        Text("A small box above your text shows the Arabic as you type.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                }
                .toggleStyle(.switch)
            }
            card {
                Toggle(isOn: $model.fasterPreview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Faster preview").foregroundStyle(Color.ink)
                        Text("Reuses what is already converted as you type. Now and then a word can come out differently.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                }
                .toggleStyle(.switch)
            }
            card {
                Toggle(isOn: $model.largerText) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Larger text").foregroundStyle(Color.ink)
                        Text("Bigger Arabic in the preview and the spellings.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                }
                .toggleStyle(.switch)
            }
            card {
                Text("Personality").foregroundStyle(Color.ink)
                Picker("Personality", selection: $model.personality) {
                    ForEach(Settings.Personality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.personality.detail).font(.system(size: 12)).foregroundStyle(Color.muted)
            }
        }
    }

    private var words: some View {
        Group {
            if model.words.isEmpty {
                card {
                    Text("Teach Harfi your spellings").foregroundStyle(Color.ink)
                    Text("After a conversion, press ⌥Tab and pick the right word. Your picks show up here and come first next time.")
                        .font(.system(size: 12)).foregroundStyle(Color.muted)
                }
            } else {
                Text("\(model.words.count) words taught · \(model.fixes) fixes in the last 30 days")
                    .font(.system(size: 13)).foregroundStyle(Color.muted)
                if !model.habits.isEmpty || !model.refused.isEmpty {
                    card {
                        Text("Harfi now writes these your way").foregroundStyle(Color.ink)
                        Text("A word becomes a habit after you pick the same spelling 3 times on 2 different days.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted)
                        ForEach(model.habits, id: \.self) { habit in
                            habitRow(habit, button: "Don't") { model.refuse(habit) }
                        }
                        ForEach(model.refused, id: \.self) { habit in
                            habitRow(habit, button: "Allow again", muted: true) { model.allow(habit) }
                        }
                    }
                }
                card {
                    ForEach(model.words) { word in
                        HStack {
                            Text(word.latin).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.muted)
                            Spacer()
                            if word.times > 1 {
                                Text("×\(word.times)").font(.system(size: 12)).foregroundStyle(Color.muted)
                            }
                            Text(word.arabic).font(Font(Theme.arabic(20))).foregroundStyle(Color.ink)
                            Button { model.forget(word) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(Color.muted)
                                .accessibilityLabel("Forget \(word.latin)")
                        }
                        if word.id != model.words.last?.id { Divider().overlay(Color.line) }
                    }
                }
                Button("Forget all my words") { confirmingForgetAll = true }
                    .confirmationDialog("Forget all your words?", isPresented: $confirmingForgetAll) {
                        Button("Forget all", role: .destructive) { model.forgetAll() }
                    } message: {
                        Text("Harfi will stop putting your spellings first. This can't be undone.")
                    }
            }
        }
    }

    private func habitRow(_ habit: Habit, button: String, muted: Bool = false,
                          action: @escaping () -> Void) -> some View {
        HStack {
            Text(habit.latin).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.muted)
            Spacer()
            Text(habit.spelling).font(Font(Theme.arabic(20))).foregroundStyle(muted ? Color.muted : Color.ink)
                .strikethrough(muted)
            Button(button, action: action).font(.system(size: 12))
                .accessibilityLabel("\(button): \(habit.latin) as \(habit.spelling)")
        }
    }

    private var privacy: some View {
        card {
            Text("Everything happens on your Mac").foregroundStyle(Color.ink)
            Text("""
            What you type is converted on this Mac and never sent anywhere. The conversion runs in a separate \
            service with no network access.

            When you pick a different spelling, Harfi keeps that one word (not the sentence) in an encrypted file \
            on this Mac for 30 days, so your spelling comes first next time. You can forget words in Your words.

            Password fields are never touched.
            """)
            .font(.system(size: 13)).foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var help: some View {
        card {
            ForEach([("Enter", "Turn the Latin into Arabic. Enter again sends."),
                     ("↑ while typing", "Fix a word in the preview before converting: ← → the word, 1–7 the spelling."),
                     ("⌘Z", "Right after: back to your Latin."),
                     ("⌥Enter", "Convert the selected Latin text."),
                     ("⌥Tab", "Other spellings for a word. ← → pick the word, ↓ ↑ the spelling."),
                     ("⌥Tab again", "Spell the word yourself, letter by letter."),
                     ("Esc", "Keep the text as typed."),
                     ("Ctrl+Space", "Switch between Harfi and your other keyboard.")], id: \.0) { key, what in
                HStack(alignment: .firstTextBaseline) {
                    Text(key).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accent)
                        .frame(width: 96, alignment: .leading)
                    Text(what).font(.system(size: 13)).foregroundStyle(Color.ink)
                }
            }
        }
    }
}
