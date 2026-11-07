# Failure matrix

Every failure Harfi can meet, what the user sees, and what checks it. The rule throughout: a failure never stops typing; the worst case is the rule converter's Arabic, or the Latin text unchanged. Tests are Swift tests (`swift test --package-path Packages/<package>`) unless marked **manual**; manual rows are gaps for the P7 gate (every row needs a passing test).

As of 1 Nov 2026 (v0.1.0, model v3); the Windows section as of 7 Nov 2026.

## Engine and model

| Failure | What the user sees | Covered by |
|---|---|---|
| Model file missing (not installed, not yet published) | Arabic from the rules (less accurate); the installer says the model can be added later | `withoutAModelTheRulesAnswer`, `missingModelFileThrows` (ArabiziLLM); installer: `scripts/test_harfi_setup.sh` (not published yet) |
| Model file corrupt (SHA-256 differs from `config/models.json`) | Arabic from the rules; the installer deletes a damaged download and asks to run it again | `aModelFileWithTheWrongHashIsNotUsed`; installer: `scripts/test_harfi_setup.sh` (damaged download) |
| Model too slow for the message's deadline (ADR 0025) | Arabic from the rules for that message | `badAnswersGiveTheRules` (deadline case), `theDeadlineGrowsWithTheMessageUpToItsCap` |
| Model still loading after login | Arabic from the rules until it is ready (about 1.5 s) | `withoutAModelTheRulesAnswer`; load in background: **manual** (`arabizi-engine-check` status) |
| Model answer unusable: invented Latin words, lost placeholder, runaway length, emoji changed | Repaired word by word when each word can be traced, otherwise Arabic from the rules | `badAnswersGiveTheRules`, `mixedTokensAreSplit`, `anInventedWordIsReplacedByTheRulesForItsInputWord`, `untraceableLatinStillGivesTheRules`, `aMisreadArabiziWordLeftInLatinIsConvertedByTheRules`, `emojiMustComeBackAsTyped` |
| Model throws an error | Arabic from the rules | `aFailingModelGivesTheRules` |
| Very long input (over `max_input_chars`) | Arabic from the rules, without the model | `tooLongInputSkipsTheModel` |
| Plain English typed | Left exactly as typed | `plainEnglishIsLeftAloneAndNeverReachesTheModel`, `plainEnglishIsRecognised`, `arabiziAndShortTextIsNotEnglish` |
| A word the model writes from nothing typed (`waraye` → ورايق) | The conversion is kept; the word gets a dashed line and ↑ starts on it | `aWordWithALetterNoKeyWritesIsDoubtful`, `suggestionsStartOnTheWordThatLooksWrong` |

## Service, files and installation

| Failure | What the user sees | Covered by |
|---|---|---|
| Engine service crashes or does not answer | The keyboard's own rules answer (after the deadline plus 0.5 s); the next message reconnects | `aServiceThatNeverAnswersGivesUpAfterTheDeadline`, `aServiceThatCrashesIsReachedAgainOnTheNextMessage` (`swift test --package-path Apps/ArabiziIME`) |
| Engine tries the network | Refused by the sandbox (no network entitlement); nothing is sent | **manual**: `arabizi-engine-check` must report `network: blocked` |
| Engine config unreadable | The keyboard's own rules | `committedConfigLoads` (the shipped config loads); unreadable case: **manual** |
| Rule dictionary missing | Letter rules only | `missingDictionaryMeansLetterRulesOnly` |
| English word list missing | The guard is off; English goes to the model, which keeps English words itself | `theGuardIsOffWithoutItsFile` |
| Rule files missing altogether | The toy letter converter keeps typing usable | **manual** (logged as "Rule files not loaded") |
| Correction record unreadable or its key replaced | No personal suggestions; nothing else changes | `theStoreEncryptsKeepsAndExpiresCorrections` (wrong key reads nothing) |
| Model download drops | It resumes the part in progress, also on a later run | `scripts/test_harfi_setup.sh` (resumed part, already downloaded) |
| App quarantined (downloaded through a browser or Homebrew) | macOS refuses to open it ("could not check it for malicious software"); the one-line installer avoids it | **manual**; documented in `docs/INSTALL.md` |

## Typing in apps

| Failure | What the user sees | Covered by |
|---|---|---|
| Password field (secure input) | Nothing is underlined or converted; keys go straight to the field | `secureInputNeverComposes`, `passwordFieldsForgetTheLastConversion` |
| App cannot report the cursor | ⌘Z stays the app's own undo, ⌥Enter beeps, ⌥Tab does nothing | `undoIsTheAppsOwnWhenTheCursorMoved`, `optionTabDoesNothingWhenTheCursorMovedOrNothingWasConverted` |
| App reports no or a wrong text position | The preview and chips sit at the last good position, above the text | **manual** (`lineRect` / `plausibleLine`) |
| Focus moves away while composing | The Latin text is committed unchanged | `focusLossCommitsLatinNotConverted`, `focusLossForgetsTheLastConversion` |
| App without marked-text support | Per app, recorded in the matrix | **open**: `docs/spikes/ime_app_matrix.md` |

## Windows (ADR 0032)

The same rule holds: a failure never stops typing. On Windows the model runs in `harfi-engine.exe`, which the keyboard reaches over a named pipe; every engine problem below ends in the keyboard's own rules. Tests run on Windows in CI (job `windows`) unless marked **manual**; manual checks were run by hand on 7 Nov 2026 and are written so they can be repeated.

### Engine and model

| Failure | What the user sees | Covered by |
|---|---|---|
| Engine not running (first use after login, or it quit after 30 idle minutes) | That message in Arabic from the rules; the keyboard starts the engine and the next message gets the model | **manual**: stop `harfi-engine`, type a message and press Enter (rules), type again after about 6 s (model); `engine.log` shows `started` then `converted: model` |
| Engine still loading the model | Arabic from the rules; the preview shows the model's Arabic once it is ready, and the rules' answers are not kept for Enter | `withoutAModelTheRulesAnswer`; the not-kept rule: **manual** (same check as above) |
| Model too slow for the message's deadline | Arabic from the rules for that message | as on the Mac (`badAnswersGiveTheRules`); measured on 1,401 unseen sentences: 27 timeouts (1.9%) |
| Model file missing or damaged | Arabic from the rules; `status.ps1` says "model unavailable" with the reason; `install.ps1` downloads the model again and checks each part | `aModelFileWithTheWrongHashIsNotUsed`, `withoutAModelTheRulesAnswer`; the installer's check: **manual** |
| Engine crashes, or does not answer in time | The keyboard's own rules after the deadline plus 0.5 s; it starts the engine again (at most every 15 s) | **manual**: kill `harfi-engine` while typing |
| Another account on the PC takes the engine's pipe name | Arabic from the rules; nothing is sent to that process (the keyboard checks the server is this account's engine) | **manual**: the identity check in `EngineClient.isOurEngine`; no test can create a second account in CI |
| Engine started from an app running as administrator | Nothing different: the pipe is open to the account's own normal apps too | **manual**: pipe access is granted to the account's SID (`harfi-engine` `makePipe`) |
| Engine cannot open its pipe for another reason | Arabic from the rules; `engine.log` names the error | **manual** |
| Plain English typed | Left as typed | `plainEnglishIsLeftAloneAndNeverReachesTheModel`, `theCoreConvertsWithTheRulesAndLeavesEnglishAlone` |

### Keyboard and apps

| Failure | What the user sees | Covered by |
|---|---|---|
| Keyboard files missing or the core cannot load (`HarfiCoreC.dll` or its Swift runtime) | Keys go to the app unchanged; `status.ps1` shows which apps loaded which build | `aMissingRulesFolderGivesNoCore`; loading next to the keyboard, without Swift on PATH: **manual** (`core-check`, 7 Nov 2026) |
| An app does not load the keyboard at all (it was installed into a packaged app's private storage, or the app starts text services in a restricted mode) | Switching to Harfi does nothing in that app | `install.ps1` refuses to install from a packaged app's terminal; restricted modes: **manual** probe (secure, UI-less only, COM-less: all load) |
| Store app (app container) | Harfi works; it can read the keyboard's files but not the learned-words record | **manual**: `icacls %LOCALAPPDATA%\Harfi\words` lists only SYSTEM and the account |
| Password or PIN field | Nothing is composed; keys are typed as Latin | `passwordFieldsAndUnknownKeysPassThrough` |
| App reports no text position | The preview and chips sit at the caret, else the last good position | **manual** (`TextService::TextRect`) |
| The app ends the composition (a click elsewhere, focus moves) | The Latin stays as typed; the next word starts fresh | **manual** |
| Switching keyboards while typing | What was typed stays, as Latin; the app does not freeze | **manual** (the core is never unloaded; pending edits keep the keyboard alive) |
| An app still holds an older build after an install | It keeps working with the older build until restarted; `status.ps1` marks it "OLDER: restart this app" | **manual** |

### Installation and your words

| Failure | What the user sees | Covered by |
|---|---|---|
| Model download drops | Run `install.ps1` again: it resumes the part in progress and checks every part | **manual**; a known gap: a part already complete can make the rerun fail (review on #42); delete `models\download` to retry |
| Keyboard files in use by open apps | Installed anyway: the old files are moved aside and removed at a later install | **manual** (`install.ps1`, 7 Nov 2026) |
| Learned-words record unreadable (or its key replaced) | No personal suggestions or habits; nothing else changes | `theStoreEncryptsKeepsAndExpiresCorrections`, `refusedHabitsAreKeptSealedAndCanBeAllowedAgain` |
| A habit the user does not want | Esc while the tip shows refuses it; `harfi-words refuse WORD` later | `aThirdPickOnASecondDayBecomesAHabitThatCanBeRefused` |
| Two apps record a fix at the same moment | One of the two fixes may be lost | **open** (review on #41): needs a lock across apps |

## Gaps to close for the P7 gate

1. The per-app matrix (Mac and Windows).
2. The remaining manual rows: the engine's network block (`arabizi-engine-check`), the model loading in the background, positions in apps that report none, a quarantined app.
3. Windows: the manual rows above (a test host for the text service, an engine smoke test in the `windows` CI job), and the open row: two apps recording a fix at once.
