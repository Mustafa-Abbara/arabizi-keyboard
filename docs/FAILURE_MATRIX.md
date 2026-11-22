# Failure matrix

Every failure Harfi can meet, what the user sees, and what checks it. The rule throughout: a failure never stops typing; the worst case is the rule converter's Arabic, or the Latin text unchanged. Tests are Swift tests (`swift test --package-path Packages/<package>`) unless marked **manual**; manual rows are gaps for the P7 gate (every row needs a passing test).

As of 1 Nov 2026 (v0.1.0, model v3); the Windows section as of 7 Nov 2026; the installer rows and the hand-check log as of 22 Nov 2026 (v0.5.1, model v5).

## Engine and model

| Failure | What the user sees | Covered by |
|---|---|---|
| Model file missing (not installed, not yet published) | Arabic from the rules (less accurate); the installer says the model can be added later | `withoutAModelTheRulesAnswer`, `missingModelFileThrows` (ArabiziLLM); installer: `scripts/test_harfi_setup.sh` (not published yet) |
| Model file corrupt (SHA-256 differs from `config/models.json`) | Arabic from the rules; the installer deletes a damaged download and asks to run it again | `aModelFileWithTheWrongHashIsNotUsed`; installer: `scripts/test_harfi_setup.sh` (damaged download) |
| Model too slow for the message's deadline (ADR 0025) | Arabic from the rules for that message | `badAnswersGiveTheRules` (deadline case), `theDeadlineGrowsWithTheMessageUpToItsCap` |
| Model still loading after login | Arabic from the rules until it is ready (about 1.5 s) | `withoutAModelTheRulesAnswer`; load in background: **manual** (`arabizi-engine-check` status); checked by hand on the 8 GB Air, 22 Nov 2026: a freshly started engine reports `loading: 1` and answers from the rules in 2 ms |
| Model answer unusable: invented Latin words, lost placeholder, runaway length, emoji changed | Repaired word by word when each word can be traced, otherwise Arabic from the rules | `badAnswersGiveTheRules`, `mixedTokensAreSplit`, `anInventedWordIsReplacedByTheRulesForItsInputWord`, `untraceableLatinStillGivesTheRules`, `aMisreadArabiziWordLeftInLatinIsConvertedByTheRules`, `emojiMustComeBackAsTyped` |
| Model throws an error | Arabic from the rules | `aFailingModelGivesTheRules` |
| Very long input (over `max_input_chars`) | Arabic from the rules, without the model | `tooLongInputSkipsTheModel` |
| Plain English typed | Left exactly as typed | `plainEnglishIsLeftAloneAndNeverReachesTheModel`, `plainEnglishIsRecognised`, `arabiziAndShortTextIsNotEnglish` |
| A word the model writes from nothing typed (`waraye` → ورايق) | The conversion is kept; the word gets a dashed line and ↑ starts on it | `aWordWithALetterNoKeyWritesIsDoubtful`, `suggestionsStartOnTheWordThatLooksWrong` |
| Word guesses for the ↑ list (ADR 0036): no model, model error, input too long | No model guesses; the ↑ list from the other sources is already shown and stays | `withoutAModelThereAreNoGuesses`, `aGeneratorThatCannotGuessGivesNoGuesses`, `anErrorIsNeverThrown` |
| Word guesses too slow for their deadline | No model guesses for that word (`fallbackTimeout`); the list stays | `aSlowModelWithNothingToOfferIsATimeout`, `wordGuessesPastTheDeadlineAreEmpty` (ArabiziLLM, with a model) |
| Word guesses that are not Arabic words (Latin, tokens of the prompt) | Dropped; only whole Arabic words reach the list | `theModelsGuessesComeBackCleanAndBestFirst`, `guessedWordsAreCleaned` |
| Word guesses leaving state in the model's cache | Conversions start from an empty cache: the same answers as without guesses | `aConversionIsTheSameBeforeAndAfterWordGuesses` (ArabiziLLM, with a model); 104/104 dev conversions identical (PR) |

## Service, files and installation

| Failure | What the user sees | Covered by |
|---|---|---|
| Engine service crashes or does not answer | The keyboard's own rules answer (after the deadline plus 0.5 s); the next message reconnects | `aServiceThatNeverAnswersGivesUpAfterTheDeadline`, `aServiceThatCrashesIsReachedAgainOnTheNextMessage` (`swift test --package-path Apps/ArabiziIME`) |
| Engine service idle for 30 minutes | It quits and gives back the model's memory (about 1 GB); the next message gets the rules while the model loads again (about 3 s) | `theEngineIsIdleOnlyAfterTheLimitWithoutRequests`, `theDefaultLimitIsHalfAnHour` (ArabiziEngine); the quit itself: **manual** (`log stream`: "idle for 30 minutes", 11 Nov 2026) |
| Engine tries the network | Refused by the sandbox (no network entitlement); nothing is sent | **manual**: `arabizi-engine-check` must report `network: blocked`; checked by hand on the 8 GB Air, 22 Nov 2026: `network: blocked` (0.5.2) |
| Engine config unreadable | The keyboard's own rules | `committedConfigLoads` (the shipped config loads); unreadable case: **manual**; checked by hand on the 8 GB Air, 22 Nov 2026: with a broken `engine.json` the service logs "engine service cannot start" and exits; the keyboard gets a connection error and uses its rules |
| Rule dictionary missing | Letter rules only | `missingDictionaryMeansLetterRulesOnly` |
| English word list missing | The guard is off; English goes to the model, which keeps English words itself | `theGuardIsOffWithoutItsFile` |
| Rule files missing altogether | The toy letter converter keeps typing usable | `noRuleFilesAtAllIsRefusedAndTheToyConverterStillTypes` (ArabiziCore); the keyboard logs "Rule files not loaded" |
| Correction record unreadable or its key replaced | No personal suggestions; nothing else changes | `theStoreEncryptsKeepsAndExpiresCorrections` (wrong key reads nothing) |
| Model download drops | It resumes the part in progress, also on a later run | `scripts/test_harfi_setup.sh` (resumed part, already downloaded) |
| App quarantined (downloaded through a browser or Homebrew) | macOS refuses to open it ("could not check it for malicious software"); the one-line installer avoids it | **manual**; documented in `docs/INSTALL.md`; checked by hand on the 8 GB Air, 22 Nov 2026: the 0.5.2 zip with a Safari quarantine mark is `rejected` by `spctl --assess` (ad hoc, no Team ID); the one-line installer installs it |

## Typing in apps

| Failure | What the user sees | Covered by |
|---|---|---|
| Password field (secure input) | Nothing is underlined or converted; keys go straight to the field | `secureInputNeverComposes`, `passwordFieldsForgetTheLastConversion` |
| App cannot report the cursor | ⌘Z stays the app's own undo, ⌥Enter beeps, ⌥Tab does nothing | `undoIsTheAppsOwnWhenTheCursorMoved`, `optionTabDoesNothingWhenTheCursorMovedOrNothingWasConverted` |
| App reports no or a wrong text position | The preview and chips sit at the last good position, above the text | **manual** (`lineRect` / `plausibleLine`); Brave and Claude, 17 Nov 2026: they report no cursor or marked range while ending a sentence, and typing goes on; where the boxes then sit was not checked by hand |
| No room above the line for the preview and the chips | Both go below the line, the chips on the far side of the preview, never over the text | `withRoomThePreviewIsAboveTheLineAndTheChipsAboveIt`, `whenThePreviewFitsAboveButNotTheChipsBothGoBelow` |
| App drops marked text set over a range (Notes) | ⌘Z and ↑ right after Enter still work: the converted text is deleted first, then the Latin or the spellings are composed at the cursor | **manual** (`replace(_:with:)`; Notes and WhatsApp, 11 Nov 2026; Notes again on the 8 GB Air with 0.5.2, 22 Nov 2026: ⌘Z after Enter brought the Latin back) |
| ↑ pressed when nothing was just converted, or after the cursor moved | The app's own ↑ (the cursor moves) | `upIsTheAppsWhenTheCursorMovedOrAnotherKeyCameFirst`, `upRightAfterAConversionOrAFixOpensTheSpellings` |
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
| Model download drops | Run `install.ps1` again: it keeps the parts already complete (checked by SHA-256), resumes the part in progress and checks every part | **manual** |
| Keyboard files in use by open apps | Installed anyway: the old files are moved aside and removed at a later install | **manual** (`install.ps1`, 7 Nov 2026) |
| The installer window is closed while it installs | It asks first. Yes stops the install script and everything it started (a job object); once the keyboard is on, only the model is left, and the next run carries on where it stopped | **manual**: "Install Harfi.exe" with stand-in scripts, 22 Nov 2026 (asked, then the script and its child process stopped) |
| A process the install script started keeps its output open | The window still finishes when the script exits (it no longer waits for the output to close) | **manual**: the same stand-in check, 22 Nov 2026 (reached Done and closed) |
| Earlier models left from an older version (808 MB each) | Removed once the current model is in place, with any leftover download parts; on the Mac since #101 | `install.ps1` (22 Nov 2026); Mac: `scripts/test_harfi_setup.sh` |
| Learned-words record unreadable (or its key replaced) | No personal suggestions or habits; nothing else changes | `theStoreEncryptsKeepsAndExpiresCorrections`, `refusedHabitsAreKeptSealedAndCanBeAllowedAgain` |
| A habit the user does not want | Esc while the tip shows refuses it; "Don't" under Your words in the Harfi window later (`harfi-words refuse WORD` for developers) | `aThirdPickOnASecondDayBecomesAHabitThatCanBeRefused` |
| Two apps record a fix at the same moment | Both fixes are kept: a change waits for the other app (a lock folder beside the record; one left by an app that ended is taken over after 10 s) | `twoAppsSavingAtTheSameMomentKeepBothFixes`, `aLockLeftByAnAppThatEndedIsTakenOver` |

## Hand checks (dated)

| Date | Where | Row | Result |
|---|---|---|---|
| 22 Nov 2026 | Windows laptop, 0.5.1 | Store app (app container) | Pass: `icacls %LOCALAPPDATA%\Harfi\words` lists only `NT AUTHORITY\SYSTEM` and the account |
| 22 Nov 2026 | Windows laptop, 0.5.1 | An app still holds an older build | `status.ps1` runs and reports the installed build (2026-11-20) and the engine's state; no app had Harfi loaded at the time, so the "OLDER" mark was not exercised |
| 22 Nov 2026 | Windows laptop | Installer closed while installing; output kept open | Pass with stand-in scripts (rows above) |

Still by hand and not yet dated: on Windows, the engine killed or not running while typing, a model download that drops, keyboard files in use, an app with no text position, ending the composition, switching keyboards while typing, and the pipe rows (another account, an administrator app, a pipe error). On the Mac: the rows in `MAC_HANDOFF.md` §5b.

## Gaps to close for the P7 gate

1. The per-app matrix (Mac and Windows).
2. The remaining manual rows: the engine's network block (`arabizi-engine-check`), the model loading in the background, positions in apps that report none, a quarantined app.
3. Windows: the manual rows above (a test host for the text service, an engine smoke test in the `windows` CI job).
