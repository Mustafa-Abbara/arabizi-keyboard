# Installing Harfi from source (developers)

For a normal install, see [INSTALL.md](INSTALL.md). The keyboard is a macOS **input method**: a background app that macOS loads when you pick it in the input menu, which then receives your key presses in every app. Stage P1 ships a **spike**: the real typing behaviour with a toy letter converter (`3` → ع, `7` → ح …). The fine-tuned model replaces the toy in P5–P6.

## What it does (P1)

| You do | You see |
|---|---|
| Type Arabizi | Your Latin text, underlined (marked text) |
| Typing (live preview) | A small box above the text shows the Arabic for the words typed so far, then the Latin typed since; each finished word, or a short pause, converts the sentence in the background. Enter uses the ready conversion at once. A word with a dotted line holds a letter nothing typed can write, in a word never seen written (80–88% of them are wrong on dev): ↑ and ⌥Tab start on it, the rules' spelling first. Off: `defaults write lb.aub.arabizi.inputmethod.ArabiziIME livePreview -bool false` |
| **Enter** | The underlined text is replaced by Arabic; the message is **not** sent |
| **↑ while typing** | Fix before converting: the Arabic of the typed text appears with the last word selected and its spellings as chips. ← → choose the word, a number or a click picks a spelling and converts, Enter converts as shown; Esc, Backspace or a letter go back to the Latin text |
| **Enter** again | The app sends (WhatsApp, Slack…) |
| **Esc** | The Latin text is kept as typed |
| Backspace | Edits the underlined text |
| Click elsewhere, arrows, Tab, ⌘ shortcuts | The Latin text is kept as typed, then the key works normally |
| **⌘Z right after a conversion** (cursor not moved) | The Arabic turns back into your underlined Latin: edit it and press Enter again, or Esc to keep it Latin. Any other time, ⌘Z is the app's own undo |
| Select Latin text, then **⌥Enter** | The selection is converted in place (⌘Z right after brings it back). Useful for text that lost its underline after a click |
| **⌥Tab right after a conversion** (cursor not moved) | Other spellings for the last word appear as a row of chips above the text (1–7), then "Spell it". → selects the previous word, ← the next one (any word, even with no spellings offered), a number, a click, or ↓/↑ then Enter replaces it, Esc keeps the text. Your earlier fixes come first (for this typed word, then for typed words one letter apart), and the kinds of change you pick most are listed first; `arabizi-suggestions-report --corrections` shows counts over your fixes. **⌥Tab again** spells the word yourself: type it in Arabizi, each key appears as its likeliest Arabic letter, Tab/⇧Tab or ↓/↑ change the last letter (س ↔ ص, ت ↔ ط, nothing for a short vowel), two keys that joined (`sh` → ش) offer their letters apart with ⇧Tab (سه), or type `'` between them (`s'h`), Backspace removes a letter, Enter takes the word, Esc goes back to the list. Your pick is recorded privately on this Mac (one word, 30 days, encrypted) so the keyboard can learn from it later ([ADR 0027](decisions/0027-word-suggestions-and-corrections.md)) |
| A spelling picked 3 times on 2 days | It becomes a habit: a tip says "Harfi will now write … as …", and Harfi writes that word your way from then on. Esc while the tip shows refuses it; Your words in the Harfi window lists habits (Don't / Allow again) |
| After Enter | A word the model has never seen in training, with no dictionary spelling to replace it, is pointed out once: "Not sure about … · ⌥Tab to fix it" |
| Password field | Nothing is underlined; keys go straight to the field |

The toy converter is not smart: it converts English words too and ignores context. Judge the **behaviour**, not the Arabic.

Some apps (often browsers and Electron apps) cannot tell the keyboard where the cursor or selection is. There, ⌘Z stays the app's normal undo and ⌥Enter **beeps and changes nothing** (it is never passed to the app, which would type a new line over the selection); the matrix records which apps.

## 1. Use a second macOS user account (recommended)

A broken input method can make typing awkward until you switch it off. Testing in a separate account keeps your main one safe: System Settings → Users & Groups → Add User. Log in to that account, clone or copy the repo there, and continue.

## 2. Build and install

```bash
scripts/install_ime.sh
```

This builds `build/ArabiziIME.app` (Swift package + ad-hoc signature, [ADR 0013](decisions/0013-ime-build-with-swiftpm.md)), copies it to `~/Library/Input Methods/`, and registers it with macOS. It prints whether macOS can see it.

## 3. Turn it on

System Settings → Keyboard → Input Sources → **Edit…** → **+** → **Arabic** → **Harfi** → Add. Then pick it from the input menu in the menu bar (the ع icon), or switch with Ctrl+Space.

**First install:** if it is not in the list, log out and back in once. Other developers report that a freshly copied input method sometimes only becomes selectable after a new login.

## 4. Update after a code change

Run `scripts/install_ime.sh` again. It stops the running copy; macOS starts the new one the next time you type with it. If the old behaviour remains, switch to another input source and back.

## 4b. The engine service (P5)

Since P5 the keyboard converts with the **fine-tuned model**, which runs in a separate, sandboxed service inside the app (`Contents/XPCServices/ArabiziEngineXPC.xpc`, no network access; [ADR 0020](decisions/0020-engine-xpc-service.md)). Build the app with the model in `models/` (docs/MODELS.md) and it is bundled automatically; without it, the keyboard uses the rules.

- The first time after a login or install, the service loads the model in the background (up to about 30 s); Enter meanwhile gives the rule conversion, then the model's.
- Check it from the terminal (status, a network probe that must say `blocked`, one test sentence):

```bash
build/ArabiziIME.app/Contents/MacOS/arabizi-engine-check
```

## 5. Logs

The keyboard never logs what you type, only key types, actions and lengths. Enter, Esc, ⌘Z and ⌥Enter are logged at a level macOS keeps, so they can be read afterwards:

```bash
/usr/bin/log show --predicate 'subsystem == "lb.aub.arabizi"' --last 10m
```

Live, including debug lines:

```bash
/usr/bin/log stream --predicate 'subsystem == "lb.aub.arabizi"' --level debug
```

## 6. Remove it

```bash
scripts/uninstall_ime.sh
```

Then remove it from Input Sources (**−**) if it is still listed.

## Troubleshooting

| Problem | Try |
|---|---|
| Not in the Input Sources list | Log out and back in; check `"$HOME/Library/Input Methods/ArabiziIME.app/Contents/MacOS/harfi-register" "$HOME/Library/Input Methods/ArabiziIME.app"` |
| Selected, but typing shows nothing underlined | `/usr/bin/log stream …` above: look for "Could not start the IMK server" |
| A key does something odd (e.g. a new line appears) | Check for a crash: `ls -t ~/Library/Logs/DiagnosticReports/ \| grep ArabiziIME`. When the keyboard crashes mid-key, macOS gives the key to the app |
| Typing is stuck | Ctrl+Space to switch input source, or pick another source in the menu bar |
