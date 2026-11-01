# Failure matrix

Every failure Harfi can meet, what the user sees, and what checks it. The rule throughout: a failure never stops typing; the worst case is the rule converter's Arabic, or the Latin text unchanged. Tests are Swift tests (`swift test --package-path Packages/<package>`) unless marked **manual**; manual rows are gaps for the P7 gate (every row needs a passing test).

As of 1 Nov 2026 (v0.1.0, model v3).

## Engine and model

| Failure | What the user sees | Covered by |
|---|---|---|
| Model file missing (not installed, not yet published) | Arabic from the rules (less accurate); the installer says the model can be added later | `withoutAModelTheRulesAnswer`, `missingModelFileThrows` (ArabiziLLM); installer: **manual** (404 path of `harfi-setup.sh`) |
| Model file corrupt (SHA-256 differs from `config/models.json`) | Arabic from the rules; the installer deletes a damaged download and asks to run it again | `aModelFileWithTheWrongHashIsNotUsed`; installer checksum: **manual** |
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
| Model download drops | It resumes the part in progress, also on a later run | **manual** (`harfi-setup.sh`, 100 MiB parts) |
| App quarantined (downloaded through a browser or Homebrew) | macOS refuses to open it ("could not check it for malicious software"); the one-line installer avoids it | **manual**; documented in `docs/INSTALL.md` |

## Typing in apps

| Failure | What the user sees | Covered by |
|---|---|---|
| Password field (secure input) | Nothing is underlined or converted; keys go straight to the field | `secureInputNeverComposes`, `passwordFieldsForgetTheLastConversion` |
| App cannot report the cursor | ⌘Z stays the app's own undo, ⌥Enter beeps, ⌥Tab does nothing | `undoIsTheAppsOwnWhenTheCursorMoved`, `optionTabDoesNothingWhenTheCursorMovedOrNothingWasConverted` |
| App reports no or a wrong text position | The preview and chips sit at the last good position, above the text | **manual** (`lineRect` / `plausibleLine`) |
| Focus moves away while composing | The Latin text is committed unchanged | `focusLossCommitsLatinNotConverted`, `focusLossForgetsTheLastConversion` |
| App without marked-text support | Per app, recorded in the matrix | **open**: `docs/spikes/ime_app_matrix.md` |

## Gaps to close for the P7 gate

1. Shell tests for `harfi-setup.sh`: missing model (404), damaged download, resumed part.
2. The per-app matrix.
