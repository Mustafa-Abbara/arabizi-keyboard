// Registers an installed input method with macOS so it appears in System Settings → Keyboard → Input Sources,
// then prints whether it is visible and enabled. It does not enable it: the user does that in System Settings.
// Usage: swift register.swift "$HOME/Library/Input Methods/ArabiziIME.app"
import Carbon
import Foundation

let bundleID = "lb.aub.arabizi.inputmethod.ArabiziIME"
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL

let status = TISRegisterInputSource(url)
print(status == noErr ? "Registered with macOS." : "TISRegisterInputSource returned \(status).")

let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
let sources = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
if sources.isEmpty {
    print("Not visible yet. Log out and back in once, then check Input Sources again.")
}
for source in sources {
    func flag(_ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
    let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
    let enabled = flag(kTISPropertyInputSourceIsEnabled)
    print("Found \(id): enabled=\(enabled), selectable=\(flag(kTISPropertyInputSourceIsSelectCapable))")
    if enabled {
        print("Already enabled: switch to another input source and back (Ctrl+Space) to load the new version.")
    } else {
        print("Next: System Settings → Keyboard → Input Sources → Edit… → + → Arabic → \"Arabizi Keyboard\".")
    }
}
