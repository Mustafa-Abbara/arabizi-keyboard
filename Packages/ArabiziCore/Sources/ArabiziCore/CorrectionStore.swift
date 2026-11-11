#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto: the same API on Windows and Linux (ADR 0032)
#endif
import Foundation

/// One word the user corrected (ADR 0027): never a sentence.
public struct Correction: Codable, Equatable, Sendable {
    /// The Arabizi word as typed.
    public let latin: String
    /// The spelling the user picked.
    public let chosen: String
    /// The spelling the keyboard had shown.
    public let rejected: String
    public let date: Date

    public init(latin: String, chosen: String, rejected: String, date: Date) {
        self.latin = latin
        self.chosen = chosen
        self.rejected = rejected
        self.date = date
    }
}

/// The user's corrections on this computer only, encrypted at rest (AES-GCM) and kept for `lifetime` (30 days):
/// the raw material for learned habits (ADR 0027 step 2, Habits), with the habits the user refused. Never logs or
/// sends them.
public final class CorrectionStore: @unchecked Sendable {  // file access is behind `lock`
    public static let lifetime: TimeInterval = 30 * 24 * 3600
    private let file: URL
    private let key: SymmetricKey
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(file: URL, key: SymmetricKey, now: @escaping @Sendable () -> Date = { Date() }) {
        self.file = file
        self.key = key
        self.now = now
    }

    /// The store in ~/Library/Application Support/ArabiziKeyboard, with its key in a separate file readable only
    /// by the user (not the Keychain: an ad-hoc signed app changes identity on every build, ADR 0027). The folder
    /// is excluded from backups. nil if the folder cannot be prepared: the keyboard then records nothing.
    public static func standard(folder: URL? = nil) -> CorrectionStore? {
        let fm = FileManager.default
        guard var folder = folder ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "ArabiziKeyboard") else { return nil }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Self.ownerOnly(0o700))
            #if os(macOS)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            #endif
            let keyFile = folder.appending(path: "corrections.key")
            let key: SymmetricKey
            if let data = try? Data(contentsOf: keyFile), data.count == 32 {
                key = SymmetricKey(data: data)
            } else {
                key = SymmetricKey(size: .bits256)
                let data = key.withUnsafeBytes { Data($0) }
                guard fm.createFile(atPath: keyFile.path, contents: data, attributes: Self.ownerOnly(0o600))
                else { return nil }
            }
            return CorrectionStore(file: folder.appending(path: "corrections.bin"), key: key)
        } catch {
            return nil
        }
    }

    /// The corrections still within their lifetime, oldest first.
    public func all() -> [Correction] {
        lock.withLock { load() }
    }

    public func record(_ correction: Correction) throws {
        try changing { try save(load() + [correction]) }
    }

    /// Forgets every correction of this typed word to this spelling (the "Your words" page).
    public func forget(latin: String, chosen: String) throws {
        try changing { try save(load().filter { $0.latin.lowercased() != latin.lowercased() || $0.chosen != chosen }) }
    }

    /// Deletes every correction, and the habits the user refused.
    public func wipe() throws {
        try changing {
            for url in [file, refusedFile] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - habits the user refused (ADR 0033)

    /// Beside the corrections, sealed with the same key.
    private var refusedFile: URL { file.deletingLastPathComponent().appending(path: "refused.bin") }

    /// The habits the user said no to: never proposed or applied again, until allowed.
    public func refused() -> Set<Habit> {
        lock.withLock { Set(open([Habit].self, from: refusedFile) ?? []) }
    }

    public func refuse(_ habit: Habit) throws {
        try changing {
            var habits = Set(open([Habit].self, from: refusedFile) ?? [])
            habits.insert(habit)
            try seal(Array(habits), to: refusedFile)
        }
    }

    public func allow(_ habit: Habit) throws {
        try changing {
            var habits = Set(open([Habit].self, from: refusedFile) ?? [])
            habits.remove(habit)
            try seal(Array(habits), to: refusedFile)
        }
    }

    /// When the corrections or the refusals last changed (another app may have recorded one); nil for none yet.
    public var changed: Date? {
        [file, refusedFile].compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
    }

    /// Runs a read-change-write of the files with the lock of this process and the lock folder beside the files,
    /// so two apps saving at the same moment (on Windows, each app has its own keyboard) do not lose a change.
    private func changing(_ body: () throws -> Void) throws {
        try lock.withLock {
            let held = FileLock.acquire(file.deletingLastPathComponent().appending(path: "corrections.lock"))
            defer { held?.release() }
            try body()
        }
    }

    private func load() -> [Correction] {
        guard let corrections = open([Correction].self, from: file) else { return [] }
        let oldest = now().addingTimeInterval(-Self.lifetime)
        return corrections.filter { $0.date >= oldest }
    }

    private func save(_ corrections: [Correction]) throws {
        try seal(corrections, to: file)
    }

    private func open<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let sealed = try? Data(contentsOf: url), let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func seal<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        guard let sealed = try AES.GCM.seal(data, using: key).combined else { return }
        try sealed.write(to: url, options: [.atomic])
        #if !os(Windows)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    /// File permissions for the user alone; Windows keeps the user profile's own access rules instead.
    private static func ownerOnly(_ mode: Int) -> [FileAttributeKey: Any] {
        #if os(Windows)
        return [:]
        #else
        return [.posixPermissions: mode]
        #endif
    }
}

/// A lock across processes: a folder that only one process can create (creating a folder that exists fails, on
/// every system). It holds the time it was taken (`taken`: folder dates cannot be relied on on Windows); a lock older
/// than `stale` is left from a process that ended mid-change and is taken over.
struct FileLock {
    let url: URL

    static func acquire(_ url: URL, wait: TimeInterval = 2, stale: TimeInterval = 10) -> FileLock? {
        let fm = FileManager.default
        let until = Date().addingTimeInterval(wait)
        while true {
            if (try? fm.createDirectory(at: url, withIntermediateDirectories: false)) != nil {
                try? Data(String(Date().timeIntervalSince1970).utf8).write(to: url.appending(path: "taken"))
                return FileLock(url: url)
            }
            if let made = taken(url), Date().timeIntervalSince(made) > stale {
                try? fm.removeItem(at: url)
                continue
            }
            // Gave up waiting: change anyway, as before the lock (better than losing the user's pick).
            if Date() > until { return nil }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// When the lock at `url` was taken; nil when that cannot be read (the holder may be writing it right now).
    static func taken(_ url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url.appending(path: "taken")),
              let seconds = TimeInterval(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func release() {
        try? FileManager.default.removeItem(at: url)
    }
}
