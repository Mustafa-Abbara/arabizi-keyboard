# ADR 0022: Ship the v2 model trained with the real rows

- **Status:** accepted (17 Oct 2026)
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara
- **Stage:** P4 (accuracy plan)

## Context

The shipped model `arabizi-llama3.2-1b-v1` (ADR 0005) was trained without real messages by other people and scores far lower on them. On 17 Oct 2026, 4,994 real training rows by friends and family were added and a separate "others" held-out set was frozen (ADR 0021). Two Llama 3.2 1B runs were trained on the new export (`train/finetune_v2.ipynb`): `v2` with rank 32 (the sweep's best setting, TRAINING.md) and `v2-r16` with the shipped settings. Everything else matches the shipped run. The model was chosen on dev; then both test sets were run **once**.

## Dev (choice of model; numbers protected as the engine runs it)

| Model | Frozen dev (104) | vs shipped | Others dev (200) | vs shipped |
|---|---|---|---|---|
| **`v2`** (rank 32) | **0.812** [0.78, 0.85] | +0.038 [+0.008, +0.068] | **0.811** [0.79, 0.83] | +0.175 [+0.155, +0.195] |
| `v2-r16` (rank 16) | 0.803 [0.77, 0.84] | +0.029 [+0.001, +0.056] | 0.797 [0.78, 0.82] | +0.160 [+0.139, +0.182] |
| shipped `v1` | 0.774 | — | 0.636 [0.62, 0.66] | — |
| B0 rules | 0.543 | — | 0.591 [0.57, 0.61] | — |

`v2` − `v2-r16`: +0.010 [−0.011, +0.030] on frozen dev, +0.015 [−0.001, +0.030] on others dev. The gain comes from the data; rank 32 adds a little, within noise. `v2` was chosen for the test run because it was best on both sets.

## Test, run once (17 Oct 2026)

| System | Frozen test (243) | CER | Keep-Latin F1 | Halluc. | p50 / p95 ms | Others test (299) | CER | Keep-Latin F1 | Halluc. |
|---|---|---|---|---|---|---|---|---|---|
| **`v2`, numbers protected** | **0.820** [0.80, 0.84] | 0.066 | 0.84 | 4.9% | **423 / 824** | **0.800** [0.78, 0.82] | 0.082 | 0.73 | 13.4% |
| `v2`, raw | 0.826 [0.80, 0.85] | 0.063 | 0.85 | 4.9% | 507 / 963 | 0.802 [0.79, 0.82] | 0.080 | 0.74 | 13.0% |
| shipped `v1`, protected | 0.783 [0.76, 0.81] (16 Oct run) | 0.091 | 0.81 | 7.0% | 487 / 1,013 | 0.656 [0.64, 0.67] | 0.147 | 0.53 | 11.0% |
| B0 rules | 0.594 [0.57, 0.62] (16 Oct run) | 0.167 | 0.33 | 0% | < 1 | 0.607 [0.59, 0.62] | 0.163 | 0.13 | 0% |

**Paired bootstrap (word accuracy):**

- Frozen test, `v2` − shipped: protected **+0.037 [+0.015, +0.059]**; raw +0.043 [+0.022, +0.064].
- Frozen test, `v2` protected − B0: +0.225 [+0.198, +0.253].
- Others test, `v2` − shipped: protected **+0.144 [+0.125, +0.163]**; raw +0.147 [+0.128, +0.165].
- Others test, `v2` protected − B0: +0.194 [+0.174, +0.213].

**Public rows of the frozen test (113):** `v2` raw 0.803 [0.77, 0.83], protected 0.794 [0.76, 0.82]. The shipped model scored 0.757 raw and 0.756 protected.

**Other measures:**

- Numbers were kept unchanged in every `v2` run (100%). The shipped model's raw output lost some on the others test (94.7%).
- On the frozen test, protection costs `v2` 0.7 points (−0.007 [−0.015, −0.001]), because a few placeholders fell back to rules. On the others test the cost is within noise.
- The others shipped and B0 runs are the first runs on the others test. The frozen test results for the shipped model and B0 come from their single run on 16 Oct; they were not run again.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Ship `arabizi-llama3.2-1b-v2`**. It is better than the shipped model on both test sets, with intervals above 0, and much better on other people's typing (+14 points). It has the same size (808 MB GGUF, same architecture) and stays within the latency budget on the frozen test (p95 824 ms ≤ 1,200). | **Recommendation** |
| 2 | Switch the engine: `config/engine.json` `"model": "arabizi-llama3.2-1b-v2"`, then rebuild and reinstall the keyboard (`scripts/install_ime.sh`). Done on acceptance (17 Oct 2026). | ADR 0005 #3 pattern |
| 3 | Keep `v1` registered as the fallback model; `v2-r16` stays registered for the record. | **Recommendation** |

## Consequences

- **The others set is now used up as a test once for `v2`.** A future candidate is tuned on others dev and runs others test once, like `testset-v1.0`.
- **In the real Swift engine** (others dev, 200 rows, 10 s deadline), `v2` scores **0.770** and `v1` 0.635: +0.134 [+0.112, +0.157], the same gain as the raw models. The engine is below the raw model (0.811) because its output checks sent 31 of 200 sentences to the rules (25 for an invented Latin word such as `program` or `video`, 6 for a broken placeholder). On those 31 sentences the model had 351 of 455 words right and the rules 262, so a word-level fallback (replace only the invented word) could recover most of the 4 points.
- **Hallucination on other people's typing is still high (13%):** the model invents a word, usually for a name or a rare word. The engine's output checks catch invented Latin and mixed words and answer with the rules; this is the next accuracy target.
- **Latency:** on the others set's longer sentences, p95 is about 1.1–1.2 s (the shipped model's is the same), close to the 1,500 ms engine deadline. Some long sentences may fall back to the rules; to be watched in dogfooding (P6).
- **Limitation:** the others test rows come from the same group of writers as the 4,994 training rows (ADR 0021), so +14 points likely overstates the gain for complete strangers.
- The Llama 3.2 Community License applies as for `v1` (ADR 0005). The weights were kept private because they were trained partly on private messages (ADR 0014); since ADR 0028 all that data is public and the weights may be published.
