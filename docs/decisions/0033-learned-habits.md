# ADR 0033: Learned habits (ADR 0027 step 2), first on Windows

- **Status:** Proposed, 7 Nov 2026
- **Date:** 2026-11-07
- **Deciders:** Moustafa Abbara
- **Stage:** Phase 2 (ADR 0027), Windows port (ADR 0032)

## Context

Rare or unseen words are 54% of v3's wrong words on the test sets (EVAL.md, final report): names, slang and family words the model never saw, so it reads them letter by letter (`flfoul` → فلوفول for فليفلة). The user fixes them with ↑ or Alt+Tab, and the Mac records each fix (ADR 0027 step 1) but never uses the record to change a conversion. On Windows the fixes were not even recorded (`record: { _ in }` in HarfiCoreC). ADR 0027 #6 planned step 2: a fix repeated 3+ times on 2+ days becomes a proposed habit, replayed against past corrections, approved by the user, and applied after the model. Windows has no menu or settings window to approve habits in yet.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| Apply after 2 fixes, automatically | Learns fastest | Changes ADR 0027 #6; no approval; one wrong pick twice sticks |
| **ADR 0027 #6, approved with a tip** (chosen) | The planned thresholds; the user sees every habit as it forms and can refuse it with one key | A habit needs fixes on two days |
| ADR 0027 #6 with an approval menu | As the Mac will have | Windows has no menu yet; waits for a settings window |

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Follow ADR 0027 #6.** A typed word (or run such as `el shr`) becomes a habit when the user chose the same spelling 3+ times on 2+ days, counting only the picks since the user last chose a different spelling ("replayed against past corrections"): a change of mind is never a habit, and a new one forms from the new picks alone (`Habits.learned`, ArabiziCore). | Moustafa, 7 Nov 2026 (option chosen); replay rule **Recommendation** |
| 2 | **Applied after the model**, word by word through `WordAlignment` (the suggestions' alignment), keeping the punctuation around the word (`Habits.apply`): to Enter, to ↑ before sending and to the live preview. The engine never sees the record (ADR 0027 #4). | ADR 0027 #6 |
| 3 | **Approval by a tip** while there is no menu: the pick that completes a habit shows "Harfi will now write flfoul as فليفلة · Esc: don't" for 6 seconds; Esc while it shows refuses the habit for good (kept sealed beside the record, `refused.bin`, same key); any other key keeps it. | Moustafa, 7 Nov 2026 |
| 4 | **Your words without a window:** `harfi-words` lists the habits in force, the refused ones and how many fixes are recorded, and can forget a word's fixes, refuse, allow again, or wipe. It reads the same encrypted store and prints to the user's own terminal only. | **Recommendation** |
| 5 | **Windows records fixes as the Mac does** (ADR 0027 #4–5, #8–9): `CorrectionStore` in `%LOCALAPPDATA%\Harfi\words` (removed by `install.ps1 -Uninstall`), and suggestions personalised from it. Only the installed keyboard records: a core opened on a folder without `HarfiTIP.dll` (tests, tools) keeps no record. | ADR 0027; folder **Recommendation** |

## Consequences

- Tests: `Habits.learned` (thresholds, change of mind), `Habits.apply` (only habit words, punctuation kept), the sealed refusals (ArabiziCore), and the whole flow through the C interface: two earlier fixes, the third announces the habit once, Enter and the preview use it, a refusal undoes it (HarfiCoreCTests).
- Each app's keyboard keeps the habits in memory and reads the record again only when its file changed, so a habit learned in one app reaches the others at their next key.
- **The Mac** applies habits too (8 Nov 2026), with the same core code (`PersonalWords`, now in ArabiziCore): after the engine and to the live preview, the same tip (Esc refuses), and the Harfi window's Your words lists the habits with Don't / Allow again.
- A habit applies to every occurrence of its typed word, including one where the user meant another word written the same way in Latin (`b2ellak`); the tip and `harfi-words refuse` are the way out. Watch for this in dogfooding.
