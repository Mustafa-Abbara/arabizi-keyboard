# ADR 0021: Real messages by other people (training rows and the "others" held-out set)

- **Status:** accepted (Moustafa, 17 Oct 2026: option a)
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara (Claude's recommendation where marked)
- **Stage:** P4 (accuracy plan)

## Context

The shipped model (ADR 0005) scores 0.783 on the frozen test set, but only **0.684** on a 400-row sample of real messages typed by other people (rules: 0.631). Its errors come from typing habits it never saw: `a` for ق, French-style `ch`/`ou`, names, words glued together, and ambiguous words (TRAINING.md). On 17 Oct 2026 Moustafa provided **5,000 training rows and 500 test rows** (Arabizi with an Arabic-script spelling), stating:

- the rows were **written by friends and family**. The files' `source` column says "social media comments (corpus_filter_1)"; Moustafa says that label is wrong ("these were written by friends and family, not taken from social media");
- they are **all public** ("all public no problem");
- he **reviewed every row** and all are correct as they are ("Treat all 5,500 rows as checked by me"). The check sheet came back unmarked; the check is recorded on his statement.

`testset-v1.0` is frozen (P2 step 4) and must not change, so the 500 rows cannot join it.

## Conflict to resolve: A8 (human-subjects rule)

ASSUMPTIONS.md A8 requires AUB IRB review and written consent "before any interview, data donation or user study with outside participants", and ROADMAP.md says "No outside participants until IRB approval (A8)". ADR 0014 used only Moustafa's own messages for this reason. Messages written by friends and family are a data donation by outside participants; publishing them in a public repository goes further than ADR 0014's private storage. The options:

| Option | Effect |
|---|---|
| a. Moustafa records that A8 does not apply to these rows (or that consent was obtained), and the rows are published as below | Fully reproducible; the course report must state the basis |
| b. Keep the rows private (`data/private/`), like ADR 0014, until consent or IRB approval | Training still possible through the private Kaggle dataset; results quoted as aggregates only |
| c. Do not use the rows until IRB approval | No gain on other people's typing for now |

**Moustafa's decision (17 Oct 2026): option a.** "the friends and family agreed to their messages being used and published." The rows are published on that basis: consent was given by the writers, as reported by Moustafa; no IRB review was made for this data. Claude flagged the conflict as CLAUDE.md asks and did not choose a side. The course report should state this basis.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | The 5,000 rows become training rows in `data/pairs/train-hand.jsonl` (`method: hand`, `writer: friends-and-family`, `checked_by: moustafa`, `source: friends-and-family (ADR 0021)`). | **Moustafa** (data, public, checked); fields **Claude's recommendation** |
| 2 | The 500 rows become a separate **"others" held-out set** in `data/pairs/others/` (200 dev, 299 test, random with seed 2026), frozen as `others-v1.0` by its own manifest (`data/pairs/others/manifest.json`). Its own folder means training, variants and the main splits never read it; `pairs validate` checks it for leaks into training and for changes after the freeze; the CI guard requires the `testset-change` label for either manifest. | Split and folder **Claude's recommendation** |
| 3 | `evalrun run/score --others` scores the others set (results named `…-others`, `"set": "others"` in metrics.json). Tune on others dev; others test is run once per final candidate, like `testset-v1.0`. | **Claude's recommendation** |
| 4 | `pairs import-real` does the import: Arabic cleaned (diacritics, tatweel, `الـ X` → `الX`), rows that break a rule or repeat a sentence skipped, and a held-out row that repeats or nearly repeats a training sentence (≥ 4 words, ≥ 80% word overlap) skipped. | **Claude's recommendation** |
| 5 | Pair files are excluded from the pre-commit size check (`data/pairs/*.jsonl`); `train-hand.jsonl` is 1.7 MB of text, checked by `pairs validate`. | **Claude's recommendation** |
| 6 | The B0 dictionary is **not** rebuilt in this change (it would change B0 and the keyboard's rule fallback); a separate change can rebuild it with the parity fixture. | **Claude's recommendation** |

## Consequences

- **Imported 17 Oct 2026:** 4,994 training rows and 499 held-out rows; 7 rows skipped because a number was not kept as typed (SPELLING.md 6). No row repeated a sentence already in the data or in `testset-v1.0`, and no held-out row nearly repeated a training row. 1,966 rows of the earlier 2,000-row file are among them.
- Others dev baseline (200 rows, 17 Oct 2026): shipped model 0.636 [0.62, 0.66], B0 0.591 [0.57, 0.61]; +0.046 [+0.027, +0.065]. The shipped model invents text in 15% of these sentences (frozen dev: 6%).
- Training data grows from 2,000 AI-drafted + 1,687 private rows to include 4,994 human-written public rows; the next Kaggle run needs a new export (`pairs variants`, `pairs export-train`) and a new version of the private Kaggle dataset.
- The others set measures typing by people other than Moustafa, which `testset-v1.0` (mostly Moustafa's own writing) cannot.
- **Limitation:** the 500 test rows were written by the same group of people as the 5,000 training rows, so habits overlap even though no sentence does.
