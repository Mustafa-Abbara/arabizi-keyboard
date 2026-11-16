# ADR 0038: Model v4 (synthetic rows aimed at v3's weak spots, in two steps)

- **Status:** Accepted, 16 Nov 2026
- **Date:** 2026-11-16
- **Deciders:** Moustafa Abbara
- **Stage:** P4 (data, model), P5 (engine)

## Context

`arabizi-llama3.2-1b-v3` (ADR 0030) gets about one word in six wrong on real typing. Its errors on dev are mostly known words in forms it has not seen, words it has seen once or twice or never, and common words misread from context. There is no more real data at hand, so this round generated training data aimed at those errors. The full account, with every number: [docs/MODEL_V4.md](../MODEL_V4.md).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Synthetic training data in two steps**, each aimed at errors measured on the model before it: step 1 (rounds of new word forms, rare and new words, context words, spelling traps, plus breaker rows that v3 was run on) against v3's dev errors; step 2 (the same kinds plus heavy letters and English/French, in real phone-chat style checked with code) against the errors of an interim model trained after step 1. Written by four models: sol-6.1, fable-5.2, opus-5.5 and sonnet-5.5. | **Moustafa**; prompts and mixes **Recommendation** |
| 2 | **Nothing generated goes straight into training.** `scripts/build_synthetic_dataset.py` normalises (é → e; 6/9 used as letters → the plain letter for the Arabic letter), applies the repository's row checks, drops leaks to dev/test and repeats, and holds out a test slice by target word; 46,104 generated rows → 39,340 training rows and 5,342 held-out rows. | **Recommendation** |
| 3 | **Every kept row is checked by Moustafa** (`checked_by: moustafa`). | **Moustafa** |
| 4 | **ADR 0010's cap of half AI-generated training rows no longer applies.** The v4 export is 67% AI-derived. | **Moustafa** (15 Nov 2026) |
| 5 | **Training:** the v3 recipe unchanged on the new export (122,492 examples; 448 minutes on a Kaggle T4; best epoch 2; Q4_K_M, SHA-256 `26fcc756…ab06`). | **Recommendation** |
| 6 | **Naming:** the interim model is kept on record as `arabizi-llama3.2-1b-v4-interim` and not shipped; the model trained after step 2 (under the tag `v5`) is **v4**. | **Moustafa** |
| 7 | **Evaluation:** dev, the held-out synthetic test and 1,642 private real messages (senzi, WhatsApp) for the decision; then each test set once (16 Nov 2026). v4 is clearly better than v3 on both test sets: frozen +0.028 [+0.013, +0.044] (0.864), others +0.022 [+0.009, +0.036] (0.848). | **Recommendation** |
| 8 | **Shipped model:** `config/engine.json` selects `arabizi-llama3.2-1b-v4`; it is published as the `model-v4` release (8 parts), and the app version is 0.4.0. v3 stays in the manifest. | **Moustafa** |
| 9 | **`idek` is no longer a chat abbreviation:** in Lebanese Arabizi it is also إيديك ("your hands"), as every generated row that used it meant. | **Recommendation** |

## Consequences

- Rebuilt from the new rows because their tests require it: the Python–Swift parity fixture, the spelling odds, the suggestion ranker and its fixture.
- Not rebuilt (follow-up): the rule dictionary, which also feeds the unsure-word hints, and the ranker's model signal, fit on v3's guesses.
- The gains on real typing (2–3 points) are much smaller than on the synthetic test (11.5 points); the generated Arabizi is still more regular than real typing. More real writers remain the best next source.
- The weights are not in the repo (808 MB); they may be published under the Llama 3.2 Community License (ADR 0028 #4).
- On the 8 GB Air (docs/EVAL.md, "Speed on the Mac"): frozen dev 0.849 at p50 442 / p95 847 ms, others dev 0.844 at 735 / 1,274 ms (v3: 387 / 753 and 671 / 1,154); the engine's physical footprint peaks at 901 MB. Others dev is now 74 ms over the p95 budget.
