# Installing the Arabizi Keyboard (input method)

The keyboard is a macOS **input method**: a background app that macOS loads when you pick it in the input menu, which then receives your key presses in every app. Stage P1 ships a **spike**: the real typing behaviour with a toy letter converter (`3` → ع, `7` → ح …). The fine-tuned model replaces the toy in P5–P6.

## What it does (P1)

| You do | You see |
|---|---|
| Type Arabizi | Your Latin text, underlined (marked text) |
| **Enter** | The underlined text is replaced by Arabic; the message is **not** sent |
| **Enter** again | The app sends (WhatsApp, Slack…) |
| **Esc** | The Latin text is kept as typed |
| Backspace | Edits the underlined text |
| Click elsewhere, arrows, Tab, ⌘ shortcuts | The Latin text is kept as typed, then the key works normally |
| **⌘Z right after a conversion** (cursor not moved) | The Arabic turns back into your underlined Latin: edit it and press Enter again, or Esc to keep it Latin. Any other time, ⌘Z is the app's own undo |
| Select Latin text, then **⌥Enter** | The selection is converted in place (⌘Z right after brings it back). Useful for text that lost its underline after a click |
| Password field | Nothing is underlined; keys go straight to the field |

The toy converter is not smart: it converts English words too and ignores context. Judge the **behaviour**, not the Arabic.

Some apps (often browsers and Electron apps) cannot tell the keyboard where the cursor or selection is. There, ⌘Z stays the app's normal undo and ⌥Enter does nothing; the matrix records which apps.

## 1. Use a second macOS user account (recommended)

A broken input method can make typing awkward until you switch it off. Testing in a separate account keeps your main one safe: System Settings → Users & Groups → Add User. Log in to that account, clone or copy the repo there, and continue.

## 2. Build and install

```bash
scripts/install_ime.sh
```

This builds `build/ArabiziIME.app` (Swift package + ad-hoc signature, [ADR 0013](decisions/0013-ime-build-with-swiftpm.md)), copies it to `~/Library/Input Methods/`, and registers it with macOS. It prints whether macOS can see it.

## 3. Turn it on

System Settings → Keyboard → Input Sources → **Edit…** → **+** → **Arabic** → **Arabizi Keyboard** → Add. Then pick it from the input menu in the menu bar (the ع icon), or switch with Ctrl+Space.

**First install:** if it is not in the list, log out and back in once. Other developers report that a freshly copied input method sometimes only becomes selectable after a new login.

## 4. Update after a code change

Run `scripts/install_ime.sh` again. It stops the running copy; macOS starts the new one the next time you type with it. If the old behaviour remains, switch to another input source and back.

## 5. Logs

The keyboard never logs what you type, only lengths and events.

```bash
log stream --predicate 'subsystem == "lb.aub.arabizi"' --level debug
```

## 6. Remove it

```bash
scripts/uninstall_ime.sh
```

Then remove it from Input Sources (**−**) if it is still listed.

## Troubleshooting

| Problem | Try |
|---|---|
| Not in the Input Sources list | Log out and back in; check `swift Apps/ArabiziIME/Tools/register.swift "$HOME/Library/Input Methods/ArabiziIME.app"` |
| Selected, but typing shows nothing underlined | `log stream …` above: look for "Could not start the IMK server" |
| Typing is stuck | Ctrl+Space to switch input source, or pick another source in the menu bar |
