# ADR 0028: All project data is public

- **Status:** accepted (25 Oct 2026)
- **Date:** 2026-10-25
- **Deciders:** Moustafa Abbara
- **Stage:** P7 (reproducibility); supersedes ADR 0014 #2, #4, #5 and #6

## Context

ADR 0014 kept Moustafa's own chat messages private: 1,987 messages he wrote himself, with his own Arabic. 111 held-out rows were published before the freeze (ADR 0014 amendment). The other 1,873 stayed in `data/private/` (130 test, 56 dev, 1,687 training rows), with 38 evaluation runs in `eval/results/private/`. As a result, nobody could reproduce the main results from the repository, and the fine-tuned weights could not be shared. The course grades reproducibility ("another technically competent person should be able to … reproduce the main results"), and Mohamad's public-only run (PR #210) showed what is lost without these rows.

Before publishing, every row was scanned for other people's details (25 Oct 2026). No phone numbers, emails, links or @handles were found. 25 rows had a capitalised Latin word (a possible name), and 22 had words such as "code" or "pass". All were reviewed in a sheet (flagged rows first) and kept.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **Every row is public.** `pairs publish-all` moved the 1,873 private rows into the public files of their split: 130 test, 56 dev, 1,687 training. The source label became `own-chat-published`, as for the 111 rows published earlier; ids, text, dates and checks are unchanged. Generated variants are rebuilt with `pairs variants`. | **Moustafa** |
| 2 | **The held-out data is re-frozen as `testset-v1.1`:** the same 347 rows and splits (243 test, 104 dev), now all in `data/pairs/test.jsonl` and `dev.jsonl`. Results on v1.0 and v1.1 are the same rows and stay comparable; only the file hashes changed. | **Recommendation** |
| 3 | **Every evaluation run is public:** the 38 runs from `eval/results/private/` moved to `eval/results/` (8 superseded B1 runs to `eval/results/superseded/`). Their `private_sentences` count records what was private when they ran. | **Moustafa** |
| 4 | **The fine-tuned weights may be published.** No private data remains in their training. They are not committed (808 MB each), but may be shared as a GitHub Release or on Kaggle/Hugging Face under the Llama 3.2 Community License ("Built with Llama", licence text included). | **Moustafa**; channel **Recommendation** |
| 5 | The Kaggle training dataset (`arabizi-train`) may be made public; `train-private.jsonl` in new exports is empty. | **Moustafa** |
| 6 | The code keeps its support for a `data/private/` folder (empty now), for any future data that must stay private; `.gitignore` still excludes it, so local working sheets and backups are never committed by accident. | **Recommendation** |
| 7 | The rule dictionary (B0 v2, ADR 0026) is **not** rebuilt here: it would change B0 and the keyboard's fallback again. A later change can rebuild it with the published rows and its parity fixture. | **Recommendation** |

## Consequences

- The main results (frozen test 0.820, others test 0.800, ADR 0022) can now be re-scored from the committed predictions. Retraining v2 needs only the repository and a free GPU.
- Earlier docs that say "private rows", "never committed" or "aggregates only" describe the situation before this ADR. EVAL.md tables keep their public/private split as a record of what was run.
- Publishing cannot be undone: git history, forks and caches keep the text even if it is later removed.
- The keyboard's own privacy promise is unchanged: what a *user* types stays on their Mac (sandboxed engine, no network, corrections encrypted locally).
