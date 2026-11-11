import Foundation

/// The keyboard's settings on Windows, one small JSON file the user owns (`%LOCALAPPDATA%\\Harfi\\settings.json`):
/// written by the settings window, read by the keyboard. A missing or broken file, or a missing key, means the
/// defaults. The Mac keeps its settings in the keyboard's own defaults (SettingsWindow.swift). No text is ever in it.
public struct UserSettings: Codable, Equatable, Sendable {
    /// Incremental conversion while typing (ADR 0037): faster, and an answer can differ by a word from the same
    /// text converted on its own.
    public var fasterPreview = true
    /// The box above the text that shows the Arabic while typing.
    public var livePreview = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fasterPreview = try container.decodeIfPresent(Bool.self, forKey: .fasterPreview) ?? true
        livePreview = try container.decodeIfPresent(Bool.self, forKey: .livePreview) ?? true
    }

    /// The settings in `file`; the defaults when it is missing or cannot be read.
    public static func read(_ file: URL) -> UserSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else { return UserSettings() }
        return settings
    }

    public func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: file, options: .atomic)
    }

    /// `%LOCALAPPDATA%\\Harfi\\settings.json`, next to the record of the user's words; nil off Windows.
    public static var standardFile: URL? {
        #if os(Windows)
        guard let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"] else { return nil }
        return URL(fileURLWithPath: local).appending(path: "Harfi").appending(path: "settings.json")
        #else
        return nil
        #endif
    }
}

/// The settings file as the keyboard reads it while typing: kept in memory and read again at most every
/// `refreshSeconds`, so a change in the settings window is picked up without restarting anything.
public final class UserSettingsFile: @unchecked Sendable {  // `cached` and `readAt` are behind `lock`
    public static let refreshSeconds: TimeInterval = 2

    private let file: URL?
    private let lock = NSLock()
    private var cached = UserSettings()
    private var readAt: Date?

    /// `file` nil: always the defaults.
    public init(file: URL? = UserSettings.standardFile) { self.file = file }

    public var current: UserSettings {
        guard let file else { return UserSettings() }
        return lock.withLock {
            if let readAt, Date().timeIntervalSince(readAt) < Self.refreshSeconds { return cached }
            cached = UserSettings.read(file)
            readAt = Date()
            return cached
        }
    }
}
