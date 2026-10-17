# ADR 0026: Rebuild the rule dictionary with the real rows (B0 v2)

- **Status:** accepted (Moustafa, 17 Oct 2026: "Yes, rebuild the rule dictionary from the training rows")
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara (on Claude's recommendation)
- **Stage:** P5 (engine), accuracy plan

## Context

The rule converter (B0 in Python, `RuleConverter` in Swift with exact parity, ADR 0016) uses a word dictionary built from the public training rows (`pairs lexicon`). It was last built before the 4,994 real training rows were imported (ADR 0021) and written with one spelling for English words (ADR 0024). The keyboard uses the rules whenever the model cannot answer:

- during the ~30 s after login while the model loads;
- for a sentence whose model answer fails a check or times out;
- for a token replaced by the token repair (ADR 0023);
- whenever the engine service does not answer (the keyboard's own copy).

A search for fixes that need no retraining (17 Oct 2026) tried two dictionary uses on dev. A correction of model words to the dictionary's most common spelling made the keyboard slightly worse at every threshold tried (others dev −0.1 to −0.3 points), so it was dropped. Rebuilding the rule dictionary was the one that helped.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | Rebuild `data/rules/arabizi_lexicon.json` with `pairs lexicon` from the **public** training rows (unchanged rule: no private words, ADR 0014), now including the real rows: 16,025 words (949 kept in Latin), from 16,725 of 20,296 rows that line up word for word. The Swift parity fixture (`b0_parity.json`) is regenerated with it, and the Swift converter matches Python on every public row. | Moustafa (rebuild); **Claude's recommendation** |
| 2 | Earlier B0 results stay as they were measured, with **B0 v1** (the old dictionary). Results from now on use **B0 v2**. The P3/P4 gate comparisons (fine-tuned model vs B0) were made against v1 and are not re-run. | **Claude's recommendation** |

## Results (dev; the test sets are not touched)

| System | Others dev (`others-v1.1`, 200) | Frozen dev (104) |
|---|---|---|
| B0 v1 (old dictionary) | 0.591 [0.57, 0.61] | 0.543 |
| **B0 v2 (rebuilt)** | **0.725** [0.71, 0.74] (+0.134 [+0.116, +0.152]) | **0.628** [0.59, 0.67] (+0.085 [+0.058, +0.112]) |
| Real keyboard (engine v2 + repair, keyboard deadlines), B0 v1 | 0.809 | 0.815 |
| **Real keyboard, B0 v2** | **0.817** (+0.008 [+0.003, +0.015]) | 0.815 (no change) |

- The rules alone improve by 8–13 points, which is what a user sees during the first ~30 s after login and if the engine service ever fails.
- In the keyboard the gain is smaller (+0.8 on others dev), because the model answers almost every sentence. On frozen dev the model answered all 104, so nothing changed there.
- Keep-Latin F1 of the rules on others dev: 0.79 (v1: 0.13). The rules now keep the English words that the real rows keep.

## Consequences

- B0 is a stronger baseline from now on. Report which version a B0 number comes from.
- Rules or dictionary changes always ship with a regenerated parity fixture (CLAUDE.md); this one does.
