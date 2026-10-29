# ADR 0029: Second batch of friends-and-family training rows

- **Status:** Accepted, 29 Oct 2026
- **Date:** 2026-10-29
- **Deciders:** Moustafa Abbara
- **Stage:** P4 (training data for the next model)

## Context

The shipped model (`arabizi-llama3.2-1b-v2`, ADR 0022) was trained on 8,681 rows. A second batch of 9,466 real messages written by friends and family is available, with an Arabic side drafted with Claude and checked row by row. The held-out sets (`testset-v1.1`, `others-v1.1`) are frozen and must not change.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | The batch becomes **training rows only** in `data/pairs/train-hand.jsonl` (`method: hand`, `writer: friends-and-family`, `checked_by: moustafa`, `source: friends-and-family, Arabic drafted with Claude and checked (ADR 0029)`), public (ADR 0028). The Arabizi is human-written; the AI-drafted Arabic is allowed in training once checked (ADR 0010, 0012). | **Moustafa** |
| 2 | `pairs import-real --train` without `--held-out` imports training rows alone after the others set is frozen. Besides the existing checks (spelling rules, repeated sentences), it skips a training row that nearly repeats a held-out sentence (≥ 4 words, ≥ 80% word overlap), so no held-out sentence leaks into training. | **Recommendation** |
| 3 | The rule dictionary (B0 v2, ADR 0026) is **not** rebuilt here: it would change B0 and the keyboard's fallback. A separate change can rebuild it with the parity fixture. | **Recommendation** |
| 4 | The next model (v3) is trained with the same recipe as v2 (rank 32, ADR 0022) on the new export, compared with v2 on both dev sets, and run once on each test set only if it is the final candidate. | **Recommendation** |

## Consequences

- Imported 29 Oct 2026: 9,358 rows; 108 skipped (107 repeat a sentence already in the data, 2 of them held-out sentences; 1 number not kept as typed). Training grows from 8,681 to 18,039 rows (16,039 hand-written, 2,000 AI-drafted).
- The batch is shorter than the first one (median 5 words against 8; 3% with emoji against 33%), closer to Moustafa's own chats; the others set measures how well this transfers to other writers.
- A new Kaggle export (`pairs variants`, `pairs export-train`) is needed before training v3.
