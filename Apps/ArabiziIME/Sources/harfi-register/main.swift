// Registers an installed input method with macOS and asks macOS to turn it on. macOS 26.6 answers TISEnableInputSource
// with noErr and leaves the input method off (tested 12 Nov 2026), so then it opens Keyboard settings and says what to
// click there.
// Built into the app (Contents/MacOS/harfi-register) so installing needs no developer tools.
// Usage: harfi-register "$HOME/Library/Input Methods/ArabiziIME.app"
import AppKit
import Carbon

let bundleID = "lb.aub.arabizi.inputmethod.ArabiziIME"
let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL

let status = TISRegisterInputSource(url)
print(status == noErr ? "Registered with macOS." : "TISRegisterInputSource returned \(status).")

func sources() -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let raw = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
}

/// The keyboard is on when the source the user picks (selectable) is enabled.
func isOn() -> Bool {
    sources().contains { flag($0, kTISPropertyInputSourceIsSelectCapable) && flag($0, kTISPropertyInputSourceIsEnabled) }
}

let wasOn = isOn()
if !wasOn {
    for source in sources() where !flag(source, kTISPropertyInputSourceIsEnabled) {
        let result = TISEnableInputSource(source)
        if result != noErr { print("TISEnableInputSource returned \(result).") }
    }
}

if wasOn {
    print("Already enabled: switch to another keyboard and back (Ctrl+Space) to load the new version.")
} else if isOn() {
    print("Harfi is on: switch to it with Ctrl+Space (or the input menu in the menu bar).")
} else {
    print("macOS needs one click to turn Harfi on. In the window that opens: Edit… → + → Arabic → Harfi → Add.")
    print("(If Harfi is not in that list yet, log out and back in once.)")
    if let settings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
        NSWorkspace.shared.open(settings)
    }
}
