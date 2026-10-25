# ADR 0014: Moustafa's own chat messages as private test and training data

- **Status:** accepted; **superseded by [ADR 0028](0028-all-data-public.md)** (25 Oct 2026: all rows made public)
- **Date:** 2026-10-14
- **Deciders:** Moustafa Abbara
- **Stage:** P2

## Context

Moustafa provided 1,987 of his own chat messages (2024–2026, from one group chat and two private chats) with his own Arabic-script spelling of each, kept private at first. They are the most realistic data the project has: real typing, not sentences written for a dataset. The repository is public, ADR 0010 allows uploading only team-written or licensed public text for fine-tuning, and A8 forbids outside participants' text until IRB approval.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | Only messages **Moustafa wrote himself**, with **his own Arabic**, are used. Messages by other people in those chats are not (A8). | **Moustafa** |
| 2 | The rows live in `data/private/pairs/` (same format and checks as public pairs, `.gitignore`d) and are **never committed**. | **Moustafa** ("better if kept private"); storage design **Recommendation** |
| 3 | 300 rows become held-out data, drawn in proportion from each chat (210 test, 90 dev, the usual 7:3 cycle); the other 1,687 become training rows (`method: hand`, `writer: moustafa`, `source: own-chats (chat, year)`). | Split and sizes: **Recommendation**; using them for both: **Moustafa** |
| 4 | Spelling variants of private rows are written to the private folder; the committed B0 dictionary is built from **public training rows only**, so no private word is published. | **Recommendation** |
| 5 | Evaluation runs that include private rows are saved under `eval/results/private/` (`.gitignore`d); `--subset public` gives publishable numbers. Only aggregate metrics from private runs may be quoted in docs. | **Recommendation** |
| 6 | For fine-tuning (P4), the private rows go to Kaggle as a **private dataset** (option b), because real typing in training is the biggest expected quality gain. This fits ADR 0010 ("team-written text may be uploaded"); the trade-off is that the data sits on Kaggle's (Google's) servers, visible only to Moustafa's account. | **Recommendation**; confirmed when P4 started |

## Consequences

- The held-out set reaches **349 hand-written pairs** (gate: 300). The test set now reflects real typing, not only sentences written for the sheet.
- **Limitation:** test and training messages come from the same chats (same people, topics and habits), so they are not fully independent; whole chats were not held out because three chats are too few to split. Reported in DATA.md and the final report.
- Human-written training rows (1,687 + their variants) reduce the AI share of training; the ADR 0010 cap is re-checked when the P4 training set is assembled.
- Anyone cloning the repo cannot reproduce results on the private rows; public-subset results (`--subset public`) and the public test rows remain reproducible.
- The test-set freeze (P2 step 4) must include the private files' SHA-256 hashes in the committed manifest (hashes only, no text).

## Amendment (15 Oct 2026): publishing chosen held-out rows

With only 35 public test rows, anyone checking the results from the repo gets a margin of about ±8 points on the difference between two systems. Before the freeze, selected private test/dev messages are published (chosen over writing new sentences).

| # | Decision | Source |
|---|---|---|
| 7 | `pairs publish` shows each private test/dev row only to Moustafa, in a spreadsheet kept in `data/private/` (`--sheet`, then `--apply`; terminals often cannot display Arabic) or in the terminal; he approves rows one by one. Approved rows move to the public files unchanged except `source`, which becomes `own-chat-published` (the chat labels may name people). Declined ids are kept in `data/private/` so they are not asked again. Training rows are never published. It refuses after the freeze. | Mechanism **Recommendation** |
| 8 | Published rows keep their split, so the public set stays close to 70/30, and keep their id, date and `checked_by`; `pairs check` still covers them if they are unchecked. | **Recommendation** |

Consequence: the public held-out set grows by the number of rows published; results on the published rows become reproducible from the repo, and the private remainder stays aggregate-only.
