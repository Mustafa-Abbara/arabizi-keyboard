# Contributing

These rules exist so that the repository history is evidence: of reviews, tests, and decisions. Follow them from the first commit.

## One-time setup

```bash
python scripts/doctor.py          # checks your tools
pip install pre-commit && pre-commit install
```

You also need Xcode, SwiftLint and SwiftFormat (see `docs/process/S0_SETUP.md`). Swift code is built and tested locally and by CI on macOS runners. Since 12 Oct 2026 Moustafa builds the project alone ([ADR 0011](docs/decisions/0011-solo-build.md)); the rules below are written for that.

## Workflow

1. **Every task is a GitHub Issue** with one owner, a `stage:Px` label (Phase 1 stages P0–P7, see `docs/ROADMAP.md`) and a milestone (`W1`–`W10`). No issue, no branch.
2. **Branch from `main`**, short-lived (≤ 2 days):
   - `feat/P5-protected-spans`, `fix/P5-timeout-fallback`, `docs/P2-spelling-guide`, `eval/P3-bootstrap`, `train/P4-lora`, `chore/P0-board`
3. **Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/):
   `feat(core): protect URLs and numbers`, `fix(llm): enforce conversion deadline`, `docs: add ADR 0003`, `test(eval): bootstrap CI on synthetic data`.
4. **Open a pull request** into `main` using the template. Link the issue (`Closes #12`).
   - PRs over **400 changed lines** need a sentence explaining why they could not be split.
   - **Review before merge** (solo, ADR 0011): the `protect-main` ruleset requires a PR but no approval. Before merging, (a) tick the template's self-review boxes honestly, (b) run a code review on the branch and reply to each finding in the PR (fixed / won't fix and why), and (c) wait until the next day for PRs over 200 lines and re-read the diff once. An AI review is not a human review; the report says so.
   - Merge with **squash merge** only. `main` is protected: no direct pushes, no force-pushes.
5. The merge comment states what was run and checked, e.g. "ran `swift test` and the P1 matrix in Slack; checked placeholders round-trip".

## Data, privacy and secrets (hard rules)

- **Never commit** model weights, `.env` files, signed consent forms, raw observation notes, or anything derived from **MADAR** (internal-research licence, no redistribution). `.gitignore` and pre-commit block most of these. Do not work around them.
- **Never log or commit raw user text** from real people unless that person ticked "publish" on their consent form.
- **Never copy Yamli output** into datasets or references, and never automate Yamli.
- **AI-generated pairs are training data only** ([ADR 0010](docs/decisions/0010-phase1-pivot.md)): a native speaker checks every row (`checked_by`), the provider's terms must allow training on its outputs (recorded in `docs/DATA.md`), the prompt is saved in `data/prompts/`, and rows are tagged `method: ai_checked`. **Dev and test data are always human-written.**
- **Fine-tune in the cloud, run locally.** Only team-written or licensed public data is uploaded to Kaggle/Colab. Real users' text is never uploaded.
- Dev-only secrets (e.g. Langfuse keys) go in `.env`. Add the variable name, with no value, to `.env.example`.
- If you commit a secret by accident, tell the team immediately and rotate it. Removing it from git history is not enough.

## Decisions

Write an **ADR** (`docs/decisions/NNNN-short-title.md`, copy `0000-template.md`) when you choose between real alternatives: runtime, model, storage, protocol, UX rule. Keep it to one page.

## Assumptions

If you rely on something not yet confirmed, add it to `docs/ASSUMPTIONS.md`. Update its status when it is confirmed or rejected.

## Bugs and regressions

Every bug found becomes:

1. an issue labelled `type:bug` (+ `regression` once it is fixed),
2. a **failing test or eval case added before the fix**,
3. a fix PR that references the issue.

## Behaviour changes

If a PR changes how the system behaves on failure, update `docs/FAILURE_MATRIX.md` (from S11). If it changes prompts, models, training data or thresholds, attach a before/after **dev** eval table to the PR.
