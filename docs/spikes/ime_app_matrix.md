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

**Gate (roadmap P1):** at least 5 of 7 apps pass cases 1–5, with a written workaround for each failure; case 7 passes in Safari and Chrome; no crash in 10 minutes of typing.

## Notes and workarounds

- _app_: _what happened, and the workaround_
