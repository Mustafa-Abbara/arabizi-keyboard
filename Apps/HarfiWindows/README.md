# Harfi for Windows (in progress)

A TSF text input processor (`HarfiTIP.dll`, C++) that uses the same core as the Mac keyboard through its C interface (`HarfiCoreC.dll`, built from `Packages/ArabiziCore`), and the same conversion engine with the fine-tuned model as its own process (`harfi-engine.exe`, built from `Packages/ArabiziEngine`). Design and tasks: [ADR 0032](../../docs/decisions/0032-windows-port.md), issue #34.

**Works now:** typing Arabizi shows it underlined, with the live preview box above it (the model's Arabic once it has converted what is typed, the rules' until then); Enter sends the model's Arabic (the rules if the model is not ready in time); ↑ before Enter, or ↑ right after converting (while the cursor is still just after the Arabic; Alt+Tab too, where Windows lets it through), opens the chip row above the text: number keys, ←/→, ↓/↑ or a click pick a spelling, "Spell it" spells the word letter by letter; arrow keys while typing insert the text and then move the cursor; Esc keeps the Latin; plain English stays as typed; Ctrl+Z right after converting brings the Latin back; Alt+Enter converts the selected text; password and PIN fields are left alone. Keys are read as on a US keyboard whatever layout the language has (Arabic (101) for Arabic (Lebanon)); password fields get the Latin keys too, without composing.

## Your words (learned habits)

Every spelling you pick from the chip row is recorded on this computer only (one word per entry, encrypted, kept 30 days, never sent; `%LOCALAPPDATA%\Harfi\words`) and puts your earlier choices first among the suggestions. When you have picked the same spelling for a typed word 3 times on 2 different days (with no other choice since), it becomes a habit: a tip says "Harfi will now write flfoul as فليفلة", Esc while it shows refuses it, and from then on that word is written your way after the model, in the preview and on Enter ([ADR 0033](../../docs/decisions/0033-learned-habits.md)). To see or change them:

```bat
"%LOCALAPPDATA%\Harfi\harfi-words.exe"                 :: your habits, refused ones, fixes recorded
"%LOCALAPPDATA%\Harfi\harfi-words.exe" refuse flfoul   :: stop a habit (also: allow, forget WORD, wipe)
```

## How the model runs

As on the Mac (the XPC service, ADR 0020), the model is never loaded inside the apps the keyboard runs in: `harfi-engine.exe` loads it once, and the keyboard asks it over a named pipe (`\\.\pipe\harfi-engine-<user>`, one JSON line per message: the ADR 0018 `ConvertRequest` and `ConvertResponse`). The keyboard starts the engine when it is first used; the engine answers on the rules at once and loads the model in the background (after checking its SHA-256), and quits after half an hour without a request, which frees its memory. Every failure (no engine, a slow answer, a model problem) falls back to the rules. The engine logs states and timings only, never text (`engine.log`).

## Try it

On an x64 Windows 10 or 11 PC:

1. Download the `harfi-windows` artifact from the latest CI run of the pull request (Actions → the run → Artifacts) and unzip it. It holds `HarfiTIP.dll`, `HarfiCoreC.dll`, `harfi-engine.exe`, the llama.cpp and Swift runtime DLLs, `rules\`, `config\` and `install.ps1`.
2. Right-click `install.ps1` → **Run with PowerShell** (a normal PowerShell window, not a terminal inside a Store app such as Claude: Windows would put the files in that app's private storage, and the installer stops). It copies the files to `%LOCALAPPDATA%\Harfi`, downloads the model once (808 MB, from the `model-v3` release, each part checked), and registers the keyboard; if Windows needs administrator rights for that, it asks once.
3. Settings → Time & language → Language & region → Arabic (Lebanon) → Language options → Add a keyboard → **Harfi**. Switch with Win+Space.
4. Type `shu 3am ta3mel` in Notepad and press Enter: شو عم تعمل.

Remove it with `install.ps1 -Uninstall` (this also removes your recorded words).

Which build is installed, which running apps use it, and whether the engine has its model: `status.ps1` (in the same folder). An app keeps the build it loaded until it is restarted; the script marks those "OLDER: restart this app".

## Build

```bat
swift build -c release --package-path Packages/ArabiziCore --product HarfiCoreC -Xcc -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
swift build -c release --package-path Packages/ArabiziCore --product harfi-words -Xcc -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
cmake -S Apps/HarfiWindows -B build/windows -A x64
cmake --build build/windows --config Release
```

The engine needs llama.cpp at the release the Mac pins (b11429), built from source into `build/llama.cpp` (or set `LLAMA_CPP_DIR`):

```bat
git init build/llama.cpp && cd build/llama.cpp && git remote add origin https://github.com/ggml-org/llama.cpp.git
git fetch --depth 1 origin tag b11429 && git checkout FETCH_HEAD
cmake -S . -B build -A x64 -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF -DGGML_NATIVE=OFF -DGGML_AVX2=ON
cmake --build build --config Release --target llama
cd ../..
swift build -c release --package-path Packages/ArabiziEngine --product harfi-engine -Xcc -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
```

The CI job `windows` does the same, runs the core's tests on Windows, and puts the package together (without the model, which `install.ps1` downloads).

## Known gaps

- The word being fixed is not highlighted inside the underlined text (the chip row shows which one it is).
- The model runs on the CPU only; the engine is not yet in an app container without network access (the Mac's sandbox counterpart).
- No installer beyond `install.ps1` (task 6); no settings window or input menu yet.
