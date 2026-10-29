# ADR 0030: Model v3 (second friends-and-family batch)

- **Status:** Accepted, 29 Oct 2026
- **Date:** 2026-10-29
- **Deciders:** Moustafa Abbara
- **Stage:** P4 (model), P5 (engine)

## Context

`arabizi-llama3.2-1b-v2` (ADR 0022) was trained on 21,565 examples. ADR 0029 added 9,358 real training rows, so the export grew to 44,445 examples (42,244 train, 2,201 validation).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Training:** the v2 recipe unchanged (Llama 3.2 1B Instruct, LoRA rank 32, alpha 64, lr 2e-4, 3 epochs, completion-only loss, seed 2026) on the new export, on a Kaggle T4 (154 minutes, `train/runs/20261029-054800-llama3.2-1b-lora-v3.json`). Best validation loss 0.268 (v2: 0.431; the validation sets differ, so it is not a comparison). Q4_K_M GGUF, 807,694,016 bytes, SHA-256 `8441e6e0…fd1d`. | **Recommendation** |
| 2 | **Evaluation:** dev for the choice (v3 against v2, both dev sets, keyboard engine), then each test set once per system (model only and keyboard engine), `docs/EVAL.md`. v3 is at least as accurate as v2 on every set and clearly better on the others test set (+0.034 [+0.021, +0.047]); on frozen test the difference is within noise (+0.009 to +0.016). It invents less (hallucination 1.7% against 13.4% on others test) and keeps English words better (F1 0.84 against 0.68). | **Recommendation** |
| 3 | **Shipped model:** `config/engine.json` selects `arabizi-llama3.2-1b-v3`; its entry in `config/models.json` pins the file, SHA-256 and the training prompt (which carries the training date, `29 Oct 2026`). v2 stays in the manifest. | **Moustafa** |

## Consequences

- **Limitation:** the others test set was written by the same group as most of the 14,000 friends-and-family training rows, so part of the gain on it comes from shared habits (ADR 0021). The frozen test set, written mostly by one person who is not among the new training writers, shows no loss and no clear gain.
- The weights are not in the repo (808 MB); they may be published under the Llama 3.2 Community License (ADR 0028 #4).
- The rule dictionary (B0 v2, ADR 0026) was built from the earlier training rows and is not rebuilt here.
