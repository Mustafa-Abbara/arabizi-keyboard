# ADR 0004: Base models to fine-tune in P4

- **Status:** accepted (final pick after P4)
- **Date:** 2026-10-14
- **Deciders:** Moustafa Abbara
- **Stage:** P3

## Context

Roadmap P3 step 5: pick the base model(s) for fine-tuning, "the best one or two by dev word accuracy that fit the budgets; a model that is weak zero-shot can still be the best base after fine-tuning, so carry two forward if they are close". B1 measured six base models on dev (105 rows) with the same instruction P4 will use, alone and with 5 examples (docs/EVAL.md, "B1"). Budgets on the 8 GB Air (ROADMAP §0): engine RSS ≤ 1.5 GB; ≤ 15 words p50 ≤ 600 ms, p95 ≤ 1.2 s.

## Evidence (5-shot, the better setting for every model)

| Model | Word acc. [95% CI] | Peak RSS | p50 / p95 ms | Licence |
|---|---|---|---|---|
| Llama 3.2 1B | 0.169 [0.15, 0.19] | 1,002 MB | 530 / 1,091 | Llama 3.2 Community License (accepted 14 Oct) |
| Qwen3-1.7B | 0.144 [0.12, 0.17] | 1,438 MB | 300 / 591 | Apache-2.0 |
| Qwen2.5-1.5B | 0.125 [0.09, 0.16] | 1,275 MB | 308 / 625 | Apache-2.0 |
| Qwen3-0.6B | 0.070 [0.05, 0.09] | 751 MB | 167 / 301 | Apache-2.0 |
| Gemma 3 1B | 0.072 [0.05, 0.10] | 990 MB | 633 / 1,964 | Gemma Terms of Use (accepted 14 Oct) |
| Qwen2.5-0.5B | 0.052 [0.03, 0.08] | 641 MB | 161 / 304 | Apache-2.0 |

All are far below B0 (0.547): no base model knows Lebanese Arabizi, so B1 says little about which one learns it best. The top three overlap.

## Decision

**Fine-tune two models in P4, and keep a small fallback** [Recommendation]:

1. **Llama 3.2 1B**: best B1 score, about 1 GB of memory (comfortable on 8 GB), within the latency budget.
2. **Qwen3-1.7B**: second-best score, the lowest error rate (CER) among the Qwen models and the fastest of the strong models; Apache-2.0. Its 1,438 MB peak leaves almost no margin under 1.5 GB, so P4 must re-measure it with the fine-tuned prompt (no examples, shorter context).
3. **Fallback: Qwen3-0.6B** (751 MB, fastest), fine-tuned only if both of the above miss the memory or latency budget, or if time allows a size comparison.

Qwen2.5-1.5B is the reserve if one of the two fails to train. Gemma 3 1B is dropped (lowest of the 1B-class models and slowest).

**The final model is chosen after P4**, by dev word accuracy of the fine-tuned versions within the budgets, and recorded in ADR 0005.

## Consequences

- P4 trains with the same instruction as B1 (`b1.SYSTEM_PROMPT`), so the gain from fine-tuning is measured fairly.
- Llama 3.2 conditions apply if the fine-tuned Llama ships: the acceptable-use policy, "Built with Llama" attribution, and a model name starting with "Llama" (Llama 3.2 Community License). Arabic is not among Meta's officially supported languages; that is part of what P4 tests.
- Two fine-tuning runs (plus a possible third) fit easily in Kaggle's free weekly GPU quota at this data size; the private own-chat rows go as a private Kaggle dataset (ADR 0014).
