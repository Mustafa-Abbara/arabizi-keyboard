# Harfi testing checklist (Windows, by hand)

Use this before each release to check that Harfi works as intended. Tick each line, and write down anything that looks wrong: what you typed, which app, and what you saw. Most checks take under a minute. Sections 1–4 are the core and should always pass. The rest cover features that are easy to break without noticing.

Use messages of your own, but never paste private chats into a bug report: describe them instead.

## 0. Before you start

- [ ] The installed version is the one under test: **Settings → Apps → Installed apps → Harfi** shows it (for example 0.4.2).
- [ ] The model is in place: `%LOCALAPPDATA%\Harfi\models\` has `arabizi-llama3.2-1b-v5-Q4_K_M.gguf` (808 MB).
- [ ] The first conversion after starting Windows can take a few seconds while the model loads. Wait for it once before timing anything.

## 1. Install and update

- [ ] **Fresh install:** on a machine (or Windows account) without Harfi, download `Harfi-Setup.exe` from the website, double-click it, and allow anything Windows asks once. It ends with "Harfi is on" or "Harfi is installed".
- [ ] **"Show me how to use it"** opens the Harfi window **in front**, not only as a flashing button in the taskbar.
- [ ] **Update over an older version:** the old version is replaced, and the model is **not** downloaded again when it is already there.
- [ ] **Keyboard list:** Harfi appears in Windows' keyboards under **Arabic (Lebanon)**, with the Harfi icon.
- [ ] **Uninstall** (Installed apps → Harfi → Uninstall) removes it from the keyboard list and deletes `%LOCALAPPDATA%\Harfi`, including the model and your words. Do this last, or on a test account.

## 2. Switching to Harfi

- [ ] **Win+Space** switches to Harfi in Notepad.
- [ ] **Keyboard list:** the Win+Space list shows Harfi under Arabic (Lebanon).
- [ ] **Switching back** to English with Win+Space makes typing plain English again.

## 3. Typing and sending (the core)

In Notepad, with Harfi on:

| Type | Expected after Enter |
|---|---|
| `kifak` | كيفك |
| `shu 3am ta3mel` | شو عم تعمل |
| `ana ktir mabsout el yom` | Arabic for every word |
| `bade 2elak shi` | the 2 is read as a letter (ق or ء), not kept as a number |
| `meeting at 5 bukra` | `meeting` stays English, `5` stays 5, `bukra` → بكرا |
| `hello how are you` | stays exactly as typed (plain English) |
| `ok lol` | `ok` and `lol` stay as typed (chat abbreviations) |
| `😂😂 ya zalame` | the emojis stay where they were |

- [ ] **Underline:** while typing, the Latin is underlined, and a **preview box** above it shows the Arabic so far.
- [ ] **Preview:** after a short pause the preview shows the last word too. A dashed word in the preview means Harfi is unsure of it.
- [ ] **Enter sends the Arabic** shown in the preview. The cursor ends after the Arabic.
- [ ] **Esc** while typing keeps the Latin as you typed it.
- [ ] **Fix a typo with the arrows:** while typing (no Enter), ← and → move inside the sentence; fix a letter and Enter converts the whole sentence.
- [ ] **Click inside the sentence:** the cursor goes there, the sentence stays underlined, and Enter converts all of it.
- [ ] **Switch apps mid-sentence:** the preview hides while you are away; back in the app the sentence is still underlined and the preview returns.
- [ ] **Long sentence:** the preview wraps onto new lines instead of stretching off the screen.
- [ ] **Backspace** while typing removes Latin letters, and the preview follows.
- [ ] **Ctrl+Z** right after Enter brings back the Latin you typed.
- [ ] **Alt+Enter** on selected Latin text converts just that selection.
- [ ] **Speed:** a short message (under 8 words) appears within about 1.5 s after Enter, usually much sooner.

## 4. Fixing a word with ↑ (the list)

### Before sending

- [ ] Type `shu 3am` (don't press Enter), then press **↑**. A row of chips appears above the preview: the word being fixed, its spellings numbered 1–9, then "Spell it".
- [ ] The typed sentence shows above the chips, with the Latin of the selected word highlighted.
- [ ] **←/→** move to the other words. The chips change, and the preview highlights the word.
- [ ] **↓/↑** move through the spellings. The **word in the preview and in the text changes** to the highlighted spelling.
- [ ] **Hovering with the mouse** over a spelling does the same: the **preview and the text show the spelling under the mouse**. Moving to another chip changes it again. The chip row does not jump while you hover.
- [ ] **A number key** (1–9) picks that spelling.
- [ ] **Clicking** a spelling picks it.
- [ ] **Enter** takes the highlighted spelling.
- [ ] **Esc** closes the list and keeps the word as it was.

### After sending

- [ ] Send a message with Enter, then press **↑** right away (cursor still after the Arabic). The chips open on the word Harfi was least sure of.
- [ ] **Alt+Tab** right after sending does the same, in apps where Windows lets it through.
- [ ] **Picking** a spelling replaces just that word in the sent text.

### The model's guesses (0.4.1 and later)

- [ ] **Guesses arrive:** after ↑ opens the list, within about half a second **the order may change once**, as the model's own guesses arrive. Nothing changes if they are late.
- [ ] **Your highlight stays:** if you already moved to a spelling with ↓ before the guesses arrive, that spelling and those before it **stay in place**. Only the ones after it can change.
- [ ] **Next message isn't slowed:** send a message, then quickly type and send the next one without pressing ↑. The second one isn't noticeably slower.

### Spell it

- [ ] Click **Spell it** (or press Alt+Tab a second time): you spell the word letter by letter. **Tab** changes the letter and **Enter** takes it.
- [ ] Esc leaves spelling and keeps the word.

## 5. Learning your spellings

- [ ] **Your choices come first:** pick the same spelling for a word (say `flfoul` → فليفلة) from the list. Next time, that spelling is first in the list.
- [ ] **Habits:** after picking it 3 times on 2 different days, a tip says "Harfi will now write flfoul as فليفلة". From then on Enter writes it that way.
- [ ] **Refusing a habit:** pressing **Esc** while that tip shows refuses the habit, and it never comes back.
- [ ] **Your words page:** the Harfi window → **Your words** lists the habit. "Stop", "Allow again", "Forget" and "Forget all" each do what they say.

## 6. The Harfi window

Start menu → **Harfi**:

- [ ] **Welcome:** the "Try it" button opens Notepad.
- [ ] **Typing:** turning **Live preview** off hides the preview box within 2 seconds. Turning it back on brings the box back.
- [ ] **Typing:** **Faster preview** on and off both still convert correctly.
- [ ] **Privacy** and **Help** pages open and read correctly.
- [ ] **One window only:** opening the Harfi window a second time brings the open one to the front instead of opening a second copy.

## 7. Where Harfi must stay out of the way

- [ ] **Password fields:** Harfi leaves them alone (try a website login form). No preview, no Arabic.
- [ ] **PIN fields:** the Windows sign-in PIN screen works normally.
- [ ] **Shortcuts:** Ctrl+C, Ctrl+V, Ctrl+A, Ctrl+S, Alt+F4 and Win+key shortcuts work as usual while Harfi is on.
- [ ] **Arrow keys while typing:** the Latin is put into the text first, then the cursor moves.
- [ ] **Games and full-screen apps** don't lose keys (optional).

## 8. Apps

For each app, check type → preview → Enter → ↑ → hover → pick:

| App | Type + Enter | ↑ list | Hover | Notes |
|---|---|---|---|---|
| Notepad | [ ] | [ ] | [ ] | |
| Word | [ ] | [ ] | [ ] | |
| Chrome | [ ] | [ ] | [ ] | |
| Edge | [ ] | [ ] | [ ] | |
| Brave | [ ] | [ ] | [ ] | earlier versions refused the switch |
| WhatsApp (desktop) | [ ] | [ ] | [ ] | Enter sends the message: check the Arabic is what gets sent |
| WhatsApp Web | [ ] | [ ] | [ ] | |
| Discord / Teams / Messenger | [ ] | [ ] | [ ] | |
| VS Code | [ ] | [ ] | [ ] | |
| Windows search box (Start) | [ ] | [ ] | [ ] | |

## 9. When the model can't help

- [ ] **Rules fallback:** rename the model file in `%LOCALAPPDATA%\Harfi\models\` and restart Windows (or end `harfi-engine.exe` in Task Manager). Typing still works using the rules, which are less accurate. Rename the file back afterwards.
- [ ] **Model loading:** right after switching on, the first message may use the rules. Within a few seconds the preview starts showing the model's Arabic.
- [ ] **Idle:** after 30 minutes without typing, `harfi-engine.exe` quits, freeing memory, and the next message starts it again. That message is a little slower.
- [ ] **Offline:** with Wi-Fi off, everything above still works. Harfi never needs the internet after installing.

## 10. Reporting a problem

Write down:
1. the Harfi version;
2. the app;
3. what you typed (or a made-up example that shows the same thing);
4. what you expected, and what you saw;
5. a screenshot if the chips or preview look wrong.

For a problem where an app won't load the keyboard, set `HKCU\Software\Harfi\DebugLog` to 1, try again, and attach `%LOCALAPPDATA%\Harfi\debug.log`. It records events only, never what you type.
