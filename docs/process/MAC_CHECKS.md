# Hands-on checks on a Mac (roadmap gates P0, P1, P6, P7)

These are the roadmap gates that only a person at a Mac can close. Everything else was checked from the repository and CI on 12 Nov 2026 (`docs/ROADMAP.md`, the notes in italics under each gate).

**What you need:** an Apple silicon Mac with macOS 14 or later, about 1 hour 30 minutes, and Harfi 0.3.2 or later. **Never paste a private message into an issue, a PR or this file:** use the test sentences below, or describe what happened.

**How to report:** fill in the "Result" column of each table (✅ pass, ❌ fail, ⚠️ works with a problem, plus a few words), and send the file back. A failure is a useful result: write what you did, what you expected and what you saw.

Tester: ______________ · Mac model: ______________ · macOS version: ______ · Harfi version (Harfi window, or `defaults read ~/Library/Input\ Methods/ArabiziIME.app/Contents/Info CFBundleShortVersionString`): ______ · Date: ______

---

## A. Tools (gate P0)

In Terminal:

```bash
swift --version
xcodebuild -version
```

| # | Check | Result |
|---|---|---|
| A1 | `swift --version` prints a version (6.x) | |
| A2 | `xcodebuild -version` prints an Xcode version (if it says only the Command Line Tools are installed, write that down) | |

Docker is in the gate but the project never uses it: skip it and write "not used".

---

## B. Install on a fresh user account, from the docs only (gates P1 and P7)

Make a new user: System Settings → Users & Groups → Add User. Log in to it. Follow **only** what the repository's docs say, starting from `README.md` and `docs/INSTALL.md` (the one-line installer). Do not use anything you already know about Harfi.

| # | Check | Result |
|---|---|---|
| B1 | Harfi installs by following only the docs | |
| B2 | Harfi turns itself on (if macOS asks to **Allow** a new input method, click Allow), or the docs say clearly what to click | |
| B3 | Harfi works on its rules while the model downloads, then on the model | |
| B4 | Every step that was missing, wrong or confusing in the docs (write each one down) | |

**Reproducibility drill (P7), on the same fresh account, for whoever has 30 more minutes:** clone the repository, follow `README.md` and `docs/SETUP_IME.md` to build and install from source, put the model in `models/` (`docs/MODELS.md`), and run one evaluation:

```bash
uv run --project eval evalrun run --system b0 --split dev
```

| # | Check | Result |
|---|---|---|
| B5 | It builds and installs from source with only the docs | |
| B6 | The B0 dev run's word accuracy matches `docs/EVAL.md` ("Reproducing a baseline from a fresh clone"); write both numbers | |
| B7 | Missing or wrong steps | |

---

## C. The app matrix (gates P1 and P6)

Use your normal account with Harfi switched on (Ctrl+Space). For each app open a new message or document. Test sentence: **`kifak shu 3am ta3mel`** (expected: كيفك شو عم تعمل). Do not press Enter twice in a chat with a real person: use a chat with yourself (WhatsApp: "Message yourself"; Slack: your own DM).

The cases:

1. Type the sentence: the Latin shows underlined.
2. Press Enter: the Arabic replaces it and the message is **not** sent.
3. Press Enter again: the app sends (or starts a new line).
4. Type a sentence, press Backspace three times: only the underlined text loses letters.
5. Type a sentence, click somewhere else in the app: the Latin stays once (no duplicate, nothing lost).

Write ✅/❌/⚠️ for each case in each app, e.g. `1✅ 2✅ 3✅ 4✅ 5⚠️ (duplicated)`.

| App | Cases 1–5 | Notes |
|---|---|---|
| TextEdit | | |
| Safari (e.g. a Google search box) | | |
| Chrome (web.whatsapp.com or any text box) | | |
| Slack desktop | | |
| WhatsApp desktop | | |
| Outlook (or Mail, if Outlook is not installed: say which) | | |
| Notes | | |

**Gate:** at least 5 of the 7 pass cases 1–5, and **WhatsApp and Slack both pass**. For each failure, write what works instead (a workaround), if you find one.

---

## D. Password fields (gates P1 and P6)

Open any login page in **Safari**, then in **Chrome** (for example `https://github.com/login`; do not log in). Click the password field, switch to Harfi, type `kifak`.

| # | Check | Result |
|---|---|---|
| D1 | Safari: nothing underlined, no preview box, the dots appear as you type | |
| D2 | Chrome: the same | |
| D3 | After leaving the password field, Harfi works normally again in a normal field | |

---

## E. Ten minutes of typing (gate P1)

Set a timer for 10 minutes. Type continuously in Notes with Harfi: sentences of different lengths, English words in the middle, numbers (`3 pm`, `100$`), emoji, ↑ to fix words, ⌘Z, Esc, fast typing.

| # | Check | Result |
|---|---|---|
| E1 | No crash: Harfi never stopped working, and you never had to switch keyboards to get your keys back | |
| E2 | Nothing typed was lost or doubled | |
| E3 | Anything odd (what you did, what happened) | |

---

## F. Speed in the real keyboard (gate P6)

The gate: on an **8 GB** M-series Mac (the MacBook Air), with the model already loaded, messages of **15 words or fewer**, the 95th-percentile time is **1.2 s or less**. On a Mac with more memory, still do it and write which Mac.

1. Type one sentence and press Enter, so the model is loaded. Wait 10 seconds.
2. In Notes, convert **at least 20 sentences** of 5–15 words, pressing Enter after each (any sentences; write them yourself).
3. Then in Terminal:

```bash
/usr/bin/log show --last 15m --info --predicate 'subsystem == "lb.aub.arabizi"' \
  | grep -o 'converted by the engine: [a-zA-Z]* in [0-9]* ms' | tee speed.txt | sort | uniq -c | sort -rn | head -3
grep -o '[0-9]* ms' speed.txt | grep -o '[0-9]*' | sort -n | awk '{a[NR]=$1} END {print "count", NR, "p50", a[int(NR*0.5)+1], "ms, p95", a[int(NR*0.95)+1] " ms"}'
```

The log holds only the outcome and the time of each conversion, never the text.

| # | Check | Result |
|---|---|---|
| F1 | Mac model and memory | |
| F2 | Count, p50 and p95 printed by the second command | |
| F3 | How many conversions were not `model` (the first command lists the outcomes) | |

Note: the live preview converts while you type, so many Enters take the ready conversion; that is what users see, and it is what the gate measures.

---

## G. The engine stopped in the middle (gate P6)

1. Type a long sentence (about 15 words) in Notes. Do not press Enter yet.
2. In Terminal, have this ready: `pkill -x ArabiziEngineXPC`
3. Press Enter in Notes and, at once, run the command in Terminal.
4. Then type a new sentence and press Enter.

| # | Check | Result |
|---|---|---|
| G1 | Step 3: the text was still converted (by the rules: it may look worse), nothing was lost, and typing went on | |
| G2 | Step 4, or the sentence after it: converted by the model again (the log line says `model`) | |

---

## H. Nothing you type is in the logs (gate P6)

1. For 5 minutes, use Harfi in Notes and include this made-up word several times: **`zibzabzoob`**.
2. Then in Terminal:

```bash
/usr/bin/log show --last 10m --info --debug | grep -i -c zibzabzoob
grep -r -i -l zibzabzoob ~/Library/Logs ~/Library/Containers/lb.aub.arabizi* ~/Library/Application\ Support/ArabiziKeyboard 2>/dev/null | wc -l
```

| # | Check | Result |
|---|---|---|
| H1 | The first command prints **0** | |
| H2 | The second command prints **0** (the record of your fixes is encrypted, so the word never appears in it as text) | |

If H1 is not 0, run `/usr/bin/log show --last 10m --info --debug | grep -i zibzabzoob | cut -c1-120 | head` and write down which process logged it (the first columns), not the whole line.

---

## I. Checks the failure matrix leaves to a person (gate P7)

| # | Do this | Expected | Result |
|---|---|---|---|
| I1 | `~/Library/Input\ Methods/ArabiziIME.app/Contents/MacOS/arabizi-engine-check` | It reports the model's status and `network: blocked` | |
| I2 | Log out and in, then at once type a sentence and press Enter | Arabic from the rules at first, the model's within about 30 s | |
| I3 | In Notes: convert a sentence, then ⌘Z right after Enter; again, then ↑ right after Enter | ⌘Z brings the Latin back; ↑ opens the spellings | |
| I4 | Type in an app that shows no text position (e.g. Terminal) | The preview and spellings sit somewhere sensible, not at the screen's corner | |

---

## J. Anything else

Bugs, confusing moments, ideas. One line each is enough.

-
-
