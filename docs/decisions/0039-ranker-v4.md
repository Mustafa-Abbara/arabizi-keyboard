# ADR 0039: The ↑ list's ranker retrained for model v4

- **Status:** Accepted, 16 Nov 2026
- **Date:** 2026-11-16
- **Deciders:** Moustafa Abbara
- **Stage:** P5 (engine), P6 (keyboards)

## Context

The ↑ list (ADR 0036) shows 6 candidates for a wrong word, in an order set by a linear ranker. Its weights were fit on v3's wrong words, with the model's guesses always offered. Two things changed with v4 (ADR 0038). The model makes different mistakes, and neither keyboard asks for the model's guesses yet (ADR 0036 #5). The goal is that **Spell it** (typing a word letter by letter) is needed for fewer than 1% of words. The full study: [docs/RANKER_V4.md](../RANKER_V4.md).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Retrain the linear ranker on v4's wrong words:** public dev and dev-others (392) plus held-out synthetic-test words (448), each offered **with 10 guesses and with none**. One ranker then ranks well in both cases. | **Recommendation** |
| 2 | **Choose on private real messages, split in two halves:** choose on one half and score the chosen configurations once on the other. Only aggregates are kept. | **Recommendation** |
| 3 | **Keep the linear ranker.** Trees port to Swift only if they beat it by 2 points in the top 6 on the final half. They tie (84.9% / 84.9%) and stay a follow-up. Listwise training was unstable. | **Moustafa** (rule), result |
| 4 | **Keep dictionary v3.** Rebuilding it from the v4 training rows (46,480 words) did not help the list. | **Moustafa** (rule), result |
| 5 | **5 guesses when they are turned on, not 10.** 10 guesses add 118 ms at the median (p95 383 → 494 ms on the Windows laptop's processor) and nothing on the final half. | **Moustafa** (rule), result |
| 6 | `model_guesses` reads the shipped model from `config/engine.json`. `pairs train-ranker` trains on `guesses-v4.jsonl` and `guesses-v4-synthetic.jsonl` and records the files and guess counts in `candidate_ranker.json`. | **Recommendation** |

## Results (final half, 352 real wrong words; Spell it over all 8,803 real words)

| | Top 6 | First | Spell it, of all words |
|---|---|---|---|
| 0.4.0 ranker, no guesses (the app today) | 78.4% | 50.0% | 3.00% |
| **new ranker, no guesses** | 78.4% | **55.1%** | **2.93%** |
| **new ranker, 5 guesses** | **84.9%** | **62.2%** | **2.51%** |

## Consequences

- The right word comes first more often today (+5 points). The top 6 only improves once the guesses are on.
- **Spell it is still needed for 2.5–2.9% of words, not 1%.** The limit is which words are candidates at all (87% of the scored wrong words without guesses, 92% with them), and the ranker cannot change that. More ranker data barely helps: 10× the words adds 2 points.
- **Follow-ups, by size:**
  - wire the 5 guesses into both keyboards, after measuring them on the 8 GB Air. **Done on 16 Nov 2026** (ADR 0036, update): both keyboards ask for 5 guesses, with a 600 ms deadline; on in Windows, off on the Mac until the Air is measured (docs/EVAL.md);
  - add candidates for merged and split words and a wider guess beam;
  - fix fewer wrong words in the model itself;
  - try trees again if the candidates grow.
- `guesses-v3.jsonl` stays as a record. The private real words and the experiment scripts stay outside the repository.
