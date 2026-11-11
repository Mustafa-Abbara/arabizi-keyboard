#if os(Windows)
import ArabiziCore
import Foundation

// The part of the C interface the settings window uses (harfi-settings.exe, Apps/HarfiWindows/src/settings): the
// keyboard's settings file and the user's own words. No core is needed: each call opens the file or the encrypted
// record, as harfi-words does. Nothing here reads or writes what is typed.

/// The record of the user's words: `%LOCALAPPDATA%\Harfi\words`, the folder the keyboard writes.
private func wordsStore() -> CorrectionStore? {
    guard let folder = UserSettings.standardFile?.deletingLastPathComponent() else { return nil }
    return CorrectionStore.standard(folder: folder.appending(path: "words"))
}

private func text(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

/// 1 or 0 for a setting by name ("fasterPreview", "livePreview"); -1 for a name this version does not know.
@_cdecl("harfi_setting_get")
public func harfi_setting_get(_ name: UnsafePointer<CChar>?) -> Int32 {
    guard let file = UserSettings.standardFile else { return -1 }
    let settings = UserSettings.read(file)
    switch text(name) {
    case "fasterPreview": return settings.fasterPreview ? 1 : 0
    case "livePreview": return settings.livePreview ? 1 : 0
    default: return -1
    }
}

/// Changes one setting and writes the file; 1 when it is written.
@_cdecl("harfi_setting_set")
public func harfi_setting_set(_ name: UnsafePointer<CChar>?, _ value: Int32) -> Int32 {
    guard let file = UserSettings.standardFile else { return 0 }
    var settings = UserSettings.read(file)
    switch text(name) {
    case "fasterPreview": settings.fasterPreview = value != 0
    case "livePreview": settings.livePreview = value != 0
    default: return 0
    }
    return (try? settings.write(to: file)) == nil ? 0 : 1
}

/// The user's words as `YourWords.lines`; freed with harfi_free. NULL when the record cannot be opened.
@_cdecl("harfi_words_list")
public func harfi_words_list() -> UnsafeMutablePointer<CChar>? {
    guard let store = wordsStore() else { return nil }
    return strdup(YourWords(corrections: store.all(), refused: store.refused()).lines)
}

/// Forgets every fix of `latin` as `arabic`; 1 when done.
@_cdecl("harfi_words_forget")
public func harfi_words_forget(_ latin: UnsafePointer<CChar>?, _ arabic: UnsafePointer<CChar>?) -> Int32 {
    guard let store = wordsStore() else { return 0 }
    return (try? store.forget(latin: text(latin), chosen: text(arabic))) == nil ? 0 : 1
}

/// Stops a habit: it is not applied, and not learned again until allowed. 1 when done.
@_cdecl("harfi_words_refuse")
public func harfi_words_refuse(_ latin: UnsafePointer<CChar>?, _ spelling: UnsafePointer<CChar>?) -> Int32 {
    guard let store = wordsStore() else { return 0 }
    return (try? store.refuse(Habit(latin: text(latin), spelling: text(spelling)))) == nil ? 0 : 1
}

/// Undoes a refusal; 1 when done.
@_cdecl("harfi_words_allow")
public func harfi_words_allow(_ latin: UnsafePointer<CChar>?, _ spelling: UnsafePointer<CChar>?) -> Int32 {
    guard let store = wordsStore() else { return 0 }
    return (try? store.allow(Habit(latin: text(latin), spelling: text(spelling)))) == nil ? 0 : 1
}

/// Forgets every fix and refusal; 1 when done.
@_cdecl("harfi_words_wipe")
public func harfi_words_wipe() -> Int32 {
    guard let store = wordsStore() else { return 0 }
    return (try? store.wipe()) == nil ? 0 : 1
}
#endif
