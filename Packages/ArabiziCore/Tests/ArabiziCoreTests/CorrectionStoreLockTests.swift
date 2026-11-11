#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import ArabiziCore

private func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "harfi-lock-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func twoAppsSavingAtTheSameMomentKeepBothFixes() async {
    // Two stores on the same files stand for two apps, each with its own keyboard and its own in-process lock.
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "corrections.bin"), key = SymmetricKey(size: .bits256)
    let apps = [CorrectionStore(file: file, key: key), CorrectionStore(file: file, key: key)]
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<40 {
            group.addTask {
                try? apps[i % 2].record(Correction(latin: "w\(i)", chosen: "و", rejected: "x", date: Date()))
            }
        }
    }
    #expect(apps[0].all().count == 40)
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "corrections.lock").path))
}

@Test func aLockLeftByAnAppThatEndedIsTakenOver() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let lock = folder.appending(path: "corrections.lock")
    try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
    try Data(String(Date().addingTimeInterval(-60).timeIntervalSince1970).utf8).write(to: lock.appending(path: "taken"))
    let store = CorrectionStore(file: folder.appending(path: "corrections.bin"), key: SymmetricKey(size: .bits256))
    let start = Date()
    try store.record(Correction(latin: "sawa", chosen: "سوا", rejected: "x", date: Date()))
    #expect(Date().timeIntervalSince(start) < 1)  // no wait for a stale lock
    #expect(store.all().count == 1)
}
