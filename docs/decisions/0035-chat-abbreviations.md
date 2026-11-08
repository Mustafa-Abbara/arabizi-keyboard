# ADR 0035: Keep chat abbreviations as typed

- **Status:** Accepted, 8 Nov 2026
- **Date:** 2026-11-08
- **Deciders:** Moustafa Abbara
- **Stage:** P7 (reliability), engine and Windows keyboard

## Context

On 269 real WhatsApp messages (a private test sheet, 8 Nov 2026), 9% of v3's wrong words were English words or chat abbreviations written in Arabic letters: `idk` → إيدك, `tho` → شو, `mins` → مين, `tbh` → تبح, `qa` → قا. The writers kept them in Latin. Most of these abbreviations never appear in the training data, so the model reads them as Arabizi. The English guard (ADR 0031) only decides whole English sentences; inside an Arabizi sentence English words are the model's job, and the rules keep only the words the training data kept (`keep_latin`, generated).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **A hand-made list, `data/rules/chat_abbreviations.json`:** about 120 common chat abbreviations and short English words (`idk`, `tbh`, `btw`, `lol`, `mins`, `pdf`, `ok`…), matched as whole words, case-insensitive, without the punctuation around them. The user asked for the most common ones. | User; list **Recommendation** |
| 2 | **Left out: anything that is also Arabizi:** `ya` (يا), `min` (مين), `ye`, `y`, `fyi` (فيي), `hb`, `bruh`, `dm` (دم), `fam`, `def`, `ez`, `eta`, `2b`, and single letters. `eval/tests/test_chat_abbreviations.py` checks that no listed word is converted to Arabic more often than kept in the training data. | **Recommendation** |
| 3 | **The rules** get each abbreviation as a placeholder (ProtectedSpans), put back after conversion, in the engine's fallbacks and in the Windows core's own rules (live preview, fallback). The rule converter itself (B0 and its Python parity) is unchanged. | **Recommendation** |
| 4 | **The model sees abbreviations as typed.** After its answer passes the checks, the word that comes from an abbreviation (WordAlignment) is written as typed, with its punctuation; a second word from the same abbreviation (`yea` → يا ياه) is dropped. Placeholders for the model were tried first and dropped: each cost 400–500 ms, and 6 of the 18 messages with an abbreviation went past their deadline (2 before), so they got the rules. | **Recommendation**, measured |
| 5 | The Mac's engine service gets the list too (`scripts/build_ime.sh`); the Mac keyboard's own fallback rules do not use it yet. The Python evaluation of the model (B1) does not apply it: its numbers stay comparable with earlier runs. | **Recommendation** |

## Consequences

- WhatsApp sheet (269 messages, 1,440 words, 18 with an abbreviation), v3 with the keyboard's deadlines, Windows laptop CPU: word accuracy 0.854 before, 0.856 / 0.860 / 0.861 over three runs after; exact sentences 48.7% → 49.4%; English words or abbreviations written in Arabic 18 → 9 (the 9 left are words not on the list: `parameter`, `model`, `extract`, `shared`). Rows without an abbreviation are untouched; timeouts 2 before, 5 / 2 / 0 after (the machine's load).
- **Cost:** a word pass before the rules and an alignment after the model when the message holds an abbreviation; no model time.
- **Limit:** an abbreviation the alignment cannot trace to one word of the answer (merged into a neighbour) stays as the model wrote it. A new abbreviation needs a line in the list and a passing data check.
