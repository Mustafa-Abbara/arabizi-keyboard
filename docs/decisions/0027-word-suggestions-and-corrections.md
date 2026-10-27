# ADR 0027: Word suggestions (⌥Tab) and a private record of corrections

- **Status:** Accepted, 17 Oct 2026; amended 27 Oct 2026 (#7–#10)
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara
- **Stage:** Phase 2 item started early (ROADMAP §"Phase 2", "Memory curator"; QUESTIONS_BEFORE_BUILDING Q59–65)

## Context

The keyboard gets about 82% of words right (ADR 0025–0026). The goal is for it to learn the user's spelling over time. A model that retrains itself on the Mac was ruled out (8 GB, drift, no way to measure). The plan is instead (1) let the user fix a word quickly and record the fix, then (2) turn repeated fixes into habits the user approves (Q61, Q63). Today the keyboard cannot see a fix: once Arabic is inserted, macOS does not tell an input method that the app's text was edited. This ADR is step 1. It is a Phase 2 item, built before the P1 app matrix and P6 dogfooding.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **⌥Tab right after a conversion** (cursor not moved, the same condition as ⌘Z) shows the converted text as marked text with one word selected, and the macOS candidate window (`IMKCandidates`) below it. It starts on the last word, with or without suggestions (any word can be spelled, #7). ←/→ move between words, skipping numbers and emoji (← is the next word, since Arabic runs right to left). A number 1–5, or a click, replaces the word and ends; ↓/↑ show each spelling in place of the word and Enter takes it; Esc keeps the text unchanged; Enter, ⌘Z and other keys keep it as it stands; a typed letter starts a new word. ⌘Z still restores the Latin afterwards. | **Recommendation**; on demand, no suggestions while typing |
| 2 | **Suggestions** (`Suggestions`, ArabiziCore): the rules' spelling of the typed word; then the Arabic of dictionary words typed one letter differently (`sabiyeh` for `sabiye`) when it shares at least half its letters with the shown word; then one-edit variants of the shown word that the rule dictionary knows as words: a long vowel (ا و ي) added or dropped, a letter swap (ت/ط, س/ص, د/ض, ز/ظ, ذ/ز, ذ/د, ث/ت, ث/س, ك/ق), the ending (ه/ة, ة/ا, ى/ي, ا/ى) or the first alif (ا/أ/إ); then the typed word itself, to keep it in Latin. At most 5; the shown word is never offered; punctuation around the word is kept. These are the error kinds measured on dev (17 Oct 2026). | **Recommendation** |
| 3 | **Which typed words a shown word came from** (`WordAlignment`): by position when the word counts match; otherwise the best in-order matching by how close the rules' spelling is to the shown word, where one shown word may come from a run of up to 3 typed words that the rules write as one word (`el shr` → الشر, `w el bet` → والبيت). A joined word's suggestions are those of its last, main word with the small words' Arabic in front. A word with no match gets suggestions but no record. | **Recommendation** |
| 4 | **The record** (`CorrectionStore`): one entry per pick, **a single word**: the Arabizi word, the chosen spelling, the rejected spelling and the date; never a sentence. Kept 30 days (Q59). File `~/Library/Application Support/ArabiziKeyboard/corrections.bin`, encrypted with AES-GCM (CryptoKit). Folder 0700, files 0600, excluded from backups. Never logged, never sent; the engine service never sees it. | Q59, Q65; storage **Recommendation** |
| 5 | **The key** is a random 256-bit key in `corrections.key` (0600) beside the store, **not the Keychain**: the keyboard is ad-hoc signed (ADR 0013), so its identity changes with every build, and the Keychain would either ask for permission while the user types or lose the key at each reinstall. Encryption at rest therefore protects the file when it is copied or shared on its own, not against software running as the same user. Move the key to the Keychain if the app is ever signed with a Developer ID. | **Recommendation** |
| 6 | Step 1 **only records**. Nothing changes how the keyboard converts yet. Step 2 (next): a correction repeated 3+ times on 2+ days becomes a proposed habit, replayed against past corrections before it is kept (Q61), shown in a "What I learned" menu to approve, edit, delete, pause or wipe (Q63), and applied after the model (a habit overrides the model's spelling of that word). | Q61, Q63 |
| 7 | **Spelling a word.** On others dev the right word is among the 5 suggestions for 37% of wrong words (`arabizi-suggestions-report`); most misses are in no word list. ⌥Tab a second time spells the selected word letter by letter (`Speller`): each key is written at once as the letter rules' choice; the other letters it can stand for (`data/rules/spelling_options.json`, ordered by frequency in the training Arabic) are offered for the last key and changed with Tab/⇧Tab, ↓/↑ or a click. Digits are letters here, so numbers do not pick. A letter does not change once the next key is typed, except two keys for one sound (`sh` → ش) while the first is unchanged; the joined keys also offer their letters apart (سه), and `'` keeps them apart. Enter records the word like a pick; Esc, or Backspace on an empty word, returns to the suggestions. Every Arabic word in the dev sets and the training data can be spelled (tested); a missed word takes a median of 6 presses. | **Recommendation** |
| 8 | **Earlier fixes first:** for a typed word the user has fixed before, those spellings lead the suggestions (most often chosen, then most recent). | **Recommendation** |
| 9 | **Personal suggestions** (`Suggestions.personalized`): after the fixes of the same typed word, the fixes of typed words one letter apart (`shar` for `shr`) whose spelling shares at least half its letters with the shown word; then the usual suggestions, reordered by the kind of change the user has picked most often (`FixKind`: rules, long vowel, letter, ending, alif, Latin) once there are 3 or more fixes. All from the local record; nothing is written to the shared dictionary. | **Recommendation** |
| 10 | **Corrections report:** `arabizi-suggestions-report --corrections` prints counts over the record (fixes, days, typed words, exact repeats, fixes repeated on 2+ days, kinds of change), never text. The repeat counts decide whether step 2's learned habits are built. | **Recommendation** |

## Not in step 1

- **Selecting an older word and pressing ⌥Tab** (it needs the app to report the selection, like ⌥Enter, and fails in some browsers and Electron apps). Next, on the same parts.
- Suggestions while typing (rejected: they slow normal typing for the ~82% of words that are right).
- Using the record to change conversions (step 2).

## Consequences

- Tests: suggestions, variants, alignment (including runs), personal suggestions and their ordering, the corrections summary, the speller, the store (encryption, expiry, wrong key, permissions) and the whole ⌥Tab flow in the Composer are unit-tested (ArabiziCore). The candidate window and the in-app replacement can only be checked by hand: ⌥Tab uses the same marked-text replacement as ⌘Z, so it works in the apps where ⌘Z works, and beeps where the app cannot report the cursor (`docs/spikes/ime_app_matrix.md`).
- Arabizi digits (2, 3, 5, 7…) pick a suggestion while the list is shown, as in other input methods' candidate windows; while spelling they are letters.
- The candidate window is reloaded only when its list changes: reloading moves its highlight back to the first line, so ↓/↑ and Tab only move the highlight, and the chosen spelling is also shown in the text.
- The record stays on the Mac; deleting `~/Library/Application Support/ArabiziKeyboard` removes it and its key.
