# ADR 0024: One spelling for an English word with an Arabic prefix (split), applied to all data

- **Status:** accepted (Moustafa, 17 Oct 2026: "Keep SPELLING.md §4: split")
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara
- **Stage:** P4 (accuracy plan)

## Context

SPELLING.md 4 (confirmed in v1.0) writes an Arabic prefix apart from an English word: `el wifi` → ال wifi, "Do not mix scripts inside one token". The engine's token repair (ADR 0023) writes it that way too. An error review of the keyboard on others dev (17 Oct 2026) found that the real rows of ADR 0021 glue them instead (`الvideo`, `عالenglish`, `وbravo`):

| Source | Glued (`الvideo`) | Split (`ال video`) |
|---|---|---|
| Real training rows (ADR 0021) | 518 | 85 |
| Others dev / test references | 29 / 53 | 3 / 7 |
| AI-drafted training rows | 2 | 329 |
| Private training rows (ADR 0014) | 1 | 317 |
| `testset-v1.0` (public + private test and dev) | 3 | 62 |

So the model was trained on both spellings, and the others references scored the keyboard's split answers as wrong.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Split is the rule** (SPELLING.md 4 unchanged; v1.3 records the decision). | **Moustafa** |
| 2 | `pairs split-prefixes` rewrites every training file (public and private) and, with `--others`, the others set: Arabic letters directly followed by a Latin letter get a space (`pairs.split_glued_prefixes`; links and mentions untouched; accepted variants too). 1,453 rows changed: 471 real training rows, 2 AI-drafted, 1 private, 65 others references (24 dev, 41 test), and generated variants (rebuilt). | Moustafa (normalize); tool **Claude's recommendation** |
| 3 | The others set is re-frozen as **`others-v1.1`** (same 499 rows and splits; only spaces added). | **Claude's recommendation** |
| 4 | `testset-v1.0` is **not** changed (3 glued tokens in 347 rows); changing it would need a new freeze and makes earlier results incomparable. | **Claude's recommendation** |
| 5 | New imports split automatically (`import-real`), and `pairs` warns on a glued token (SPELLING.md 4). | **Claude's recommendation** |
| 6 | Retrain as `v3` with v2's settings on the normalized export (`train/finetune_v3.ipynb`), then compare with v2 on frozen dev and others dev. | **Moustafa** |

## Results so far: the same outputs re-scored against `others-v1.1`

No model was run again; only the references changed (`evalrun score --others`, 17 Oct 2026):

| System | Others dev v1.0 | **Others dev v1.1** | Others test v1.0 | **Others test v1.1** |
|---|---|---|---|---|
| **Keyboard engine, v2 + repair** (installed) | 0.788 | **0.806** | — | — |
| Engine v2 without repair | 0.771 | 0.772 | — | — |
| v2 model, numbers protected | 0.811 | 0.799 | 0.800 | 0.792 |
| v1 model, numbers protected | 0.636 | 0.647 | 0.656 | 0.668 |
| B0 rules | 0.591 | 0.591 | 0.607 | 0.604 |

- With one spelling, the repair is worth **+0.034 [+0.019, +0.051]** on others dev (was +0.017), and the keyboard (0.806) is now level with the raw model (0.799): +0.007 [−0.004, +0.018].
- The raw v2 model loses a little under v1.1, because it learned the glued form from the real rows; that is what `v3` should fix.
- The others test results above are re-scores of the single test run of 17 Oct, not new runs.

## Consequences

- Results on `others-v1.0` and `others-v1.1` are not comparable; EVAL.md and ADR 0022 keep their v1.0 numbers, with this table for v1.1.
- The real rows now follow the same guide as every other source; the model can learn one form.
