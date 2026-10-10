# Contributing

These rules exist so that the repository history is evidence: of reviews, tests, and decisions. Follow them from the first commit.

## One-time setup

```bash
python scripts/doctor.py          # checks your tools
pip install pre-commit && pre-commit install
```

macOS members also need Xcode, SwiftLint and SwiftFormat (see `docs/process/S0_SETUP.md`). Windows members can work on everything under `eval/`, `data/`, `research/`, `docs/` and `scripts/`. Swift code is built and tested by CI on macOS runners.

## Workflow

1. **Every task is a GitHub Issue** with one owner, a `stage:Sx` label and a milestone (`W1`–`W10`). No issue, no branch.
2. **Branch from `main`**, short-lived (≤ 2 days):
   - `feat/S5-tokenizer`, `fix/S7-timeout-fallback`, `docs/S1-proposal`, `eval/S6-bootstrap`, `chore/S0-board`
3. **Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/):
   `feat(core): add clitic segmentation`, `fix(llm): enforce 700 ms deadline`, `docs: add ADR 0003`, `test(eval): bootstrap CI on synthetic data`.
4. **Open a pull request** into `main` using the template. Link the issue (`Closes #12`).
   - PRs over **400 changed lines** need a sentence explaining why they could not be split.
   - **1 approving review** is required, from someone in a *different* owner area.
   - Merge with **squash merge** only. `main` is protected: no direct pushes, no force-pushes.
5. The reviewer checks the template boxes are honest, runs the code if it touches behaviour, and leaves at least one substantive comment or an explicit "LGTM: ran X, checked Y".

## AI-assisted code

AI coding tools are allowed (course policy), but:

- The PR template asks **"AI-assisted: yes/no"** and what the tool did. Answer honestly.
- The author must be able to explain every line in review. If you cannot, do not submit it.
- AI-generated code gets the same tests as hand-written code. Delete unused generated code: the rubric penalises dead code.

## Data, privacy and secrets (hard rules)

- **Never commit** model weights, `.env` files, signed consent forms, raw observation notes, or anything derived from **MADAR** (internal-research licence, no redistribution). `.gitignore` and pre-commit block most of these. Do not work around them.
- **Never log or commit raw user text** from real people unless that person ticked "publish" on their consent form.
- **Never generate Arabizi with an AI model or copy Yamli output** into datasets or references.
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

If a PR changes how the system behaves on failure, update `docs/FAILURE_MATRIX.md` (from S11). If it changes prompts, models or thresholds, attach a before/after eval table to the PR.
