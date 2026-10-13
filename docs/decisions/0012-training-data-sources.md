# ADR 0012: Training data sources: generated Arabizi, a Claude-drafted batch, no scraping

- **Status:** accepted
- **Date:** 2026-10-13
- **Deciders:** Moustafa Abbara
- **Stage:** P2

## Context

Writing thousands of pairs by hand is too slow for one person (ADR 0011). Moustafa asked whether the project could instead use AI-generated lists, online datasets, or scraped Arabizi discussions, with him writing only the Arabic. He also supplied a 500-pair file that Claude drafted and he then revised heavily.

Constraints: test and dev data must show how real people type (ADR 0010); the course guardrail requires "public, authorized, or synthetic data with provenance" and respect for terms of service; no outside participants before IRB approval (A8).

## Options considered

| Option | Pros | Cons |
|---|---|---|
| Everything AI-generated, including test | Fastest | Circular evaluation: the test would measure how well the model copies the generator, not real typing |
| Scrape Arabizi from X, Facebook, Reddit, YouTube | Real, messy typing | Against those sites' terms; other people's text in a public repo; close to the IRB line |
| **Hand-written test/dev; generated + AI-drafted training data; licensed datasets only** | Honest evaluation; enough training data | Training Arabizi may be cleaner than real typing (the test set measures this) |

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | Test and dev stay hand-written by Moustafa (~300 pairs). | **Claude's recommendation**, accepted by Moustafa ("A", 13 Oct 2026) |
| 2 | Training data comes mainly from Lebanese Arabic sentences (Moustafa's, Baladi, other licensed text) turned into Arabizi by the rule-based generator (`data/tools/variants.py`, roadmap P2 step 5), which now works from Arabic alone. Its rows are deterministic and need no row-by-row check. | **Claude's recommendation**, accepted by Moustafa |
| 3 | No scraping. Real Arabizi from others only comes from published datasets with a usable licence (e.g. AladdinBench, local only), never committed unless the licence allows it. | **Claude's recommendation**, accepted by Moustafa |
| 4 | The 500-pair file `lebanese_arabizi_dataset.jsonl` (drafted by Claude, revised by Moustafa) is imported as `method: ai_checked`, `writer: claude+moustafa-edited`, `checked_by: moustafa`, `source: claude-draft-revised-2026-10`, train split only. Moustafa's revision of every row is the native-speaker check required by ADR 0010 #7. The generation prompt was not kept. | Classification: **Claude's recommendation**; revision and "prompt not kept": **Moustafa** |
| 5 | Anthropic's terms are recorded and read as allowing this use (see `docs/DATA.md`, "Terms of service"). | **Moustafa** (option A, 13 Oct 2026); Claude flagged the clause and is not a legal authority |
| 6 | The only automatic change on import is removing diacritics and tatweel from the Arabic (202 of 500 rows), as SPELLING.md 2.3 requires. The English column is dropped. | **Claude's recommendation** |
| 7 | The 10% spot-check proposal is **not** adopted: every AI-drafted row is still checked in full (ADR 0010 #7 unchanged). | **Moustafa** |

## Consequences

- P4 already trains with and without the `ai_checked` rows, so the reported results never depend on them; if the terms reading is challenged, they can be dropped and the model retrained.
- The rule-based generator becomes the main training source, so it needs careful review against real typing; its spelling table is checked against Moustafa's own chats before use.
- The training set may be cleaner than real typing. The hand-written test set and the AladdinBench check are what show whether this hurts.
