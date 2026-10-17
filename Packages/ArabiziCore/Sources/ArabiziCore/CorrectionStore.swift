import CryptoKit
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

/// The user's corrections on this Mac only, encrypted at rest (AES-GCM) and kept for `lifetime` (30 days):
/// the raw material for learned habits (ADR 0027, step 2). Never logs or sends them.
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
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let keyFile = folder.appending(path: "corrections.key")
            let key: SymmetricKey
            if let data = try? Data(contentsOf: keyFile), data.count == 32 {
                key = SymmetricKey(data: data)
            } else {
                key = SymmetricKey(size: .bits256)
                let data = key.withUnsafeBytes { Data($0) }
                guard fm.createFile(atPath: keyFile.path, contents: data, attributes: [.posixPermissions: 0o600])
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
        try lock.withLock {
            try save(load() + [correction])
        }
    }

    /// Deletes every correction.
    public func wipe() throws {
        try lock.withLock {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    private func load() -> [Correction] {
        guard let sealed = try? Data(contentsOf: file), let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key),
              let corrections = try? JSONDecoder().decode([Correction].self, from: data) else { return [] }
        let oldest = now().addingTimeInterval(-Self.lifetime)
        return corrections.filter { $0.date >= oldest }
    }

    private func save(_ corrections: [Correction]) throws {
        let data = try JSONEncoder().encode(corrections)
        guard let sealed = try AES.GCM.seal(data, using: key).combined else { return }
        try sealed.write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
