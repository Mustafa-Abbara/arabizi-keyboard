# Harfi for Windows (in progress)

A TSF text input processor (`HarfiTIP.dll`, C++) that uses the same core as the Mac keyboard through its C interface (`HarfiCoreC.dll`, built from `Packages/ArabiziCore`). Design and tasks: [ADR 0032](../../docs/decisions/0032-windows-port.md), issue #34.

**Works now:** typing Arabizi shows it underlined; Enter turns it into Arabic with the rules (no model yet); ↑ before Enter (or Alt+Tab after converting) opens the chip row above the text: number keys, ←/→, ↓/↑ or a click pick a spelling, "Spell it" spells the word letter by letter; arrow keys while typing insert the text and then move the cursor; Esc keeps the Latin; plain English stays as typed.

## Try it

On an x64 Windows 10 or 11 PC:

1. Download the `harfi-windows` artifact from the latest CI run of the pull request (Actions → the run → Artifacts) and unzip it. It holds `HarfiTIP.dll`, `HarfiCoreC.dll`, the Swift runtime DLLs, `rules\` and `install.ps1`.
2. Right-click `install.ps1` → **Run with PowerShell**. It copies the files to `%LOCALAPPDATA%\Harfi` and registers the keyboard; if Windows needs administrator rights for that, it asks once.
3. Settings → Time & language → Language & region → Arabic (Lebanon) → Language options → Add a keyboard → **Harfi**. Switch with Win+Space.
4. Type `shu 3am ta3mel` in Notepad and press Enter: شو عم تعمل.

Remove it with `install.ps1 -Uninstall`.

## Build

```bat
swift build -c release --package-path Packages/ArabiziCore --product HarfiCoreC -Xcc -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
cmake -S Apps/HarfiWindows -B build/windows -A x64
cmake --build build/windows --config Release
```

The CI job `windows` does the same and runs the core's tests on Windows.

## Known gaps

- Password fields are not detected yet (the Mac skips them); `restore` (Ctrl+Z after converting) only shows the Latin again.
- No model or live preview box yet (tasks 4 and 5); no installer beyond `install.ps1` (task 6).
