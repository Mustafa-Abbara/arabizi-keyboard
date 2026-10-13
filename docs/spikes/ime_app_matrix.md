# Per-app test matrix (P1)

Fill in after installing with [SETUP_IME.md](../SETUP_IME.md). Use ✅ pass, ❌ fail, ⚠️ works with a problem (describe it below the table). macOS 26.6.2, build: _git SHA_.

| # | Case | Expected | TextEdit | Safari | Chrome | Slack | WhatsApp | Outlook | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Type `kifak shu 3am ta3mel` | Latin text underlined | | | | | | | |
| 2 | Enter with underlined text | Arabic inserted, message **not** sent | | | | | | | |
| 3 | Enter again | App sends / new line | | | | | | | |
| 4 | Backspace inside underlined text | Edits the underlined text only | | | | | | | |
| 5 | Click elsewhere while composing | Latin text committed once (no duplicate, no loss) | | | | | | | |
| 6 | ⌘Z after a conversion | Undoes the inserted Arabic only | | | | | | | |
| 7 | Password field (a login page) | Nothing underlined; keys pass through | | | | | | | |
| 8 | Long text: 25 words underlined | Shown correctly, Enter converts all of it | | | | | | | |
| 9 | ⌘Z right after a conversion | Arabic turns back into underlined Latin | | | | | | | |
| 10 | Select Latin text, ⌥Enter | Selection converted in place | | | | | | | |
| 11 | Shift+Enter with underlined text | Converts (no new line); note what the app expected | | | | | | | |
| 12 | Enter in an address bar or search box | Converts first; second Enter submits | | | | | | | |

**Gate (roadmap P1):** at least 5 of 7 apps pass cases 1–5, with a written workaround for each failure; case 7 passes in Safari and Chrome; no crash in 10 minutes of typing.

## Notes and workarounds

### First round: 13 Oct 2026 (Moustafa; before cases 9–10 existed)

Apps: Messages, Mail, a web browser, VS Code, Terminal, the Claude desktop app, TextEdit, and in-app search fields. Results were reported for the whole round, not per app, so the table above is not filled in yet.

- ✅ Typing shows underlined Latin; Enter converts it.
- ✅ Long sentences stay underlined and convert in full.
- ✅ Fast typing and Caps Lock: no problems.
- ✅ Password field on a login page: nothing underlined, keys pass through.
- ✅ Works in Terminal.
- ⚠️ Clicking elsewhere or pressing an arrow key while composing commits the text **in Latin** (underline disappears). This is the designed behaviour (no surprise conversion), but it felt like losing the sentence. Response: ⌥Enter on a selection (case 10) converts such text afterwards.
- ⚠️ ⌘Z after a conversion deleted the whole sentence (the app undid the one insertion). Response: ⌘Z right after a conversion now restores the underlined Latin (case 9).
- ⚠️ The toy converter is letter by letter and converts English words. Expected for the spike; the dictionary-based converter (B0) is the next change.

### Second round: 13 Oct 2026 (after PR #168)

- ❌ ⌥Enter on a selection deleted the sentence. **Root cause (from crash reports and logs):** the keyboard crashed. `string(from:actualRange:)` was called with `actualRange: nil`; InputMethodKit writes to that pointer without a nil check (`EXC_BAD_ACCESS` in `-[_IPMDServerClientWrapperLegacy stringFromRange:actualRange:]`, 3 crash reports). When the input method crashes mid-key, macOS gives the key to the app, which typed a new line over the selection. Two earlier guesses (selection not reported; Option not detected) were wrong: the logs showed Option detected and the selection readable.
- Fix: pass a real `actualRange` variable. Also kept from the investigation: ⌥Enter with nothing to convert beeps instead of reaching the app; Enter/Esc/⌘Z/⌥Enter outcomes are logged (kinds only, never text). Read logs with `/usr/bin/log` (a shell `log` function can hide it).
- ✅ After the fix, TextEdit: select Latin text → ⌥Enter converts it in place (log: selection reported, text readable, replaceSelection); no new crash reports. ⌘Z right after: not tried yet.
