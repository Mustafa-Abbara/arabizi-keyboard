# ADR 0027: Word suggestions (⌥Tab) and a private record of corrections

- **Status:** accepted (Moustafa, 17 Oct 2026: "start building this feature")
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara (design: Claude's recommendation)
- **Stage:** Phase 2 item started early (ROADMAP §"Phase 2", "Memory curator"; QUESTIONS_BEFORE_BUILDING Q59–65)

## Context

The keyboard gets about 82% of words right (ADR 0025–0026). Moustafa wants it to learn his spelling over time. A model that retrains itself on the Mac was ruled out (8 GB, drift, no way to measure). The plan is instead (1) let the user fix a word quickly and record the fix, then (2) turn repeated fixes into habits the user approves (Q61, Q63). Today the keyboard cannot see a fix: once Arabic is inserted, macOS does not tell an input method that the app's text was edited. This ADR is step 1. It is a Phase 2 item, built before the P1 app matrix and P6 dogfooding at Moustafa's request.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **⌥Tab right after a conversion** (cursor not moved, the same condition as ⌘Z) shows the converted text as marked text with one word selected, and the macOS candidate window (`IMKCandidates`) below it. It starts on the last word that has suggestions. ←/→ move between words (← is the next word, since Arabic runs right to left). A number 1–5, or a click, replaces the word and ends; Esc keeps the text unchanged; Enter, ⌘Z and other keys keep it as it stands; a typed letter starts a new word. ⌘Z still restores the Latin afterwards. | **Claude's recommendation**; Moustafa chose the on-demand approach (no suggestions while typing) |
| 2 | **Suggestions** (`Suggestions`, ArabiziCore): the rules' spelling of the typed word; then the Arabic of dictionary words typed one letter differently (`sabiyeh` for `sabiye`) when it shares at least half its letters with the shown word (added after the first try: one-edit Arabic variants alone offered almost nothing for words that were already right); then one-edit variants of the shown word that the rule dictionary knows as words: a long vowel (ا و ي) added or dropped, a letter swap (ت/ط, س/ص, د/ض, ز/ظ, ذ/ز, ذ/د, ث/ت, ث/س, ك/ق), the ending (ه/ة, ة/ا, ى/ي, ا/ى) or the first alif (ا/أ/إ); then the typed word itself, to keep it in Latin. At most 5; the shown word is never offered; punctuation around the word is kept. These are the error kinds measured on dev (17 Oct 2026). | **Claude's recommendation** |
| 3 | **Which typed word a shown word came from** (`WordAlignment`): by position when the word counts match; otherwise the best in-order matching by how close the rules' spelling of each Latin word is to the shown word. A word with no match gets suggestions but no record. | **Claude's recommendation** |
| 4 | **The record** (`CorrectionStore`): one entry per pick, **a single word**: the Arabizi word, the chosen spelling, the rejected spelling and the date; never a sentence. Kept 30 days (Q59). File `~/Library/Application Support/ArabiziKeyboard/corrections.bin`, encrypted with AES-GCM (CryptoKit). Folder 0700, files 0600, excluded from backups. Never logged, never sent; the engine service never sees it. | Q59, Q65; storage **Claude's recommendation** |
| 5 | **The key** is a random 256-bit key in `corrections.key` (0600) beside the store, **not the Keychain**: the keyboard is ad-hoc signed (ADR 0013), so its identity changes with every build, and the Keychain would either ask for permission while the user types or lose the key at each reinstall. Encryption at rest therefore protects the file when it is copied or shared on its own, not against software running as the same user. Move the key to the Keychain if the app is ever signed with a Developer ID. | **Claude's recommendation** |
| 6 | Step 1 **only records**. Nothing changes how the keyboard converts yet. Step 2 (next): a correction repeated 3+ times on 2+ days becomes a proposed habit, replayed against past corrections before it is kept (Q61), shown in a "What I learned" menu to approve, edit, delete, pause or wipe (Q63), and applied after the model (a habit overrides the model's spelling of that word). | Q61, Q63 |

## Not in step 1

- **Selecting an older word and pressing ⌥Tab** (it needs the app to report the selection, like ⌥Enter, and fails in some browsers and Electron apps). Next, on the same parts.
- Suggestions while typing (rejected: they slow normal typing for the ~82% of words that are right).
- Using the record to change conversions (step 2).

## Consequences

- Tests: suggestions, variants, alignment, the store (encryption, expiry, wrong key, permissions) and the whole ⌥Tab flow in the Composer are unit-tested (ArabiziCore). The candidate window and the in-app replacement can only be checked by hand: ⌥Tab uses the same marked-text replacement as ⌘Z, so it works in the apps where ⌘Z works, and beeps where the app cannot report the cursor (`docs/spikes/ime_app_matrix.md`).
- Arabizi digits (2, 3, 5, 7…) pick a suggestion while the window is open, as in other input methods' candidate windows.
- The record stays on the Mac; deleting `~/Library/Application Support/ArabiziKeyboard` removes it and its key.
