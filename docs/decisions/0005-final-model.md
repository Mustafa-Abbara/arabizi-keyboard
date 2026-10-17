# ADR 0005: The model the keyboard ships (P4)

- **Status:** accepted (Moustafa, 16 Oct 2026: "i accept llama")
- **Date:** 2026-10-16
- **Deciders:** Moustafa Abbara (on Claude's recommendation)
- **Stage:** P4

## Context

ADR 0004 carried two base models into fine-tuning, Llama 3.2 1B and Qwen3-1.7B (fallback Qwen3-0.6B). Both were fine-tuned on Kaggle on 16 Oct 2026 with the same data and settings (ADR 0015) and scored on the frozen dev set (`testset-v1.0`, 104 rows) with the same harness (`ft-<id>`, docs/EVAL.md). The roadmap's budgets on the 8 GB Air (Section 0): engine peak memory ≤ 1.5 GB, latency p50 ≤ 600 ms and p95 ≤ 1.2 s for warm sentences of ≤ 15 words. Prompts, checkpoints and the model are chosen on dev; the test set is run once, for the chosen model (roadmap §4).

## Options considered (dev, all 104 rows; private rows as aggregates only)

| Option | Word acc. [95% CI] | CER | Keep-Latin F1 | Numbers | Halluc. | Peak RSS | p50 / p95 ms | Budgets |
|---|---|---|---|---|---|---|---|---|
| **Llama 3.2 1B fine-tuned** (`arabizi-llama3.2-1b-v1`) | **0.768** [0.73, 0.80] | **0.097** | 0.86 | 0.93 | 0.06 | **956 MB** | **421 / 853** | all met |
| Qwen3-1.7B fine-tuned (`arabizi-qwen3-1.7b-v1`) | 0.723 [0.68, 0.76] | 0.111 | 0.85 | **1.00** | **0.05** | 1,333 MB | 576 / 1,481 | p95 over 1.2 s; memory close to the limit |
| B0 rules (the fallback in any case) | 0.543 [0.51, 0.58] | 0.189 | 0.17 | 1.00 | 0.00 | — | < 1 | — |

Paired bootstrap on word accuracy: Llama − Qwen = **+0.045 [+0.017, +0.075]** (public rows: +0.053 [+0.006, +0.103]); Llama − B0 = +0.225 [+0.179, +0.270]; Qwen − B0 = +0.180 [+0.130, +0.229]. Qwen had the lower validation loss in training (0.379 vs 0.401), but validation loss is measured on training-style rows; dev word accuracy on held-out real typing decides.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Ship `arabizi-llama3.2-1b-v1`**: more accurate than Qwen with an interval above 0, faster (p95 853 ms vs 1,481 ms) and lighter (956 MB vs 1,333 MB); the only model of the two inside every budget. Qwen's one advantage, numbers kept unchanged (1.00 vs 0.93), is what the engine's protected spans guarantee anyway (numbers become placeholders, ADR 0016). | **Claude's recommendation** from the dev results |
| 2 | Run the **frozen test set once** for this model, raw (`ft-arabizi-llama3.2-1b-v1`) and with numbers protected as the engine does (`ft-arabizi-llama3.2-1b-v1-protect`), `--split test --final`, all rows and `--subset public`, with B0 and the best B1 for the paired comparison; that run decides the P4 gate. Added after acceptance: on dev, protecting numbers keeps 14/14 numbers (raw 13/14) and scores 0.774 (raw 0.768). | Roadmap P4 step 5; protected variant **Claude's recommendation** |
| 3 | Switch it on in the engine when P5 can run it: `config/engine.json` `"model": "arabizi-llama3.2-1b-v1"`, `features.use_model: true`. Until then the keyboard keeps the rule converter. | ADR 0018 #5 |
| 4 | Keep Qwen as the documented alternative (its file stays in `models/`); not trained further for now. | **Claude's recommendation** |

## Consequences

- **Test result (run once, 16 Oct 2026):** 0.783 [0.76, 0.81] on the 243 test rows (B0 0.594, best B1 0.147; +0.189 [+0.159, +0.219] over B0), numbers 24/24, p50/p95 487/1,013 ms with numbers protected. Three of the four P4 gate items passed then; the fourth, a training re-run, passed on 17 Oct 2026 (the sweep's `base` run gave a bit-identical model; EVAL.md, "P4 final"). The sweep found no setting clearly better (TRAINING.md, "Sweep results").

- The Llama 3.2 Community License applies to the shipped model ("Built with Llama" if distributed; acceptable-use policy), already accepted (14 Oct 2026). The weights stay private: they were trained partly on private messages (ADR 0014).
- The P4 gate's number-preservation target (≥ 99%) is not met by the raw model on dev (13/14 numbers) but is met with numbers protected (14/14, `-protect`), which is how the engine runs it; the report states both.
- The engine must feed the exact saved prompt with both BOS tokens (fixed in #195); `FineTunedParityTests` guards it.
- If the test run fails the gate (roadmap §7, C2), the fallbacks are: Qwen (also above B0 on dev), more hand-written pairs, or a larger LoRA rank.
