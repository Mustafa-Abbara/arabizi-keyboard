# ADR 0011: Moustafa builds Phase 1 alone

- **Status:** accepted
- **Date:** 2026-10-12
- **Deciders:** Moustafa Abbara
- **Stage:** P0

## Context

The Phase 1 roadmap ([ADR 0010](0010-phase1-pivot.md)) split the work between three people: Omar (IME, CI), Mohamad (model, engine) and Moustafa (data, evaluation). On 12 Oct 2026 Moustafa decided to build the whole project alone. Several parts of the plan assumed more than one person: review approvals, a second annotator for every data row, a teammate re-running results, and parallel stages.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| A. Keep the three-person plan | Parallel work; real peer review; two annotators | Not the situation any more |
| B. Same Phase 1 scope, re-planned for one person | One owner, no coordination cost; scope unchanged | Sequential stages; no human second annotator or reviewer; less time per stage |
| C. Cut scope now (e.g. drop the XPC service and CI) | More slack | Loses reliability/security and process marks before knowing whether it is needed |

## Decision

**Option B**, with a ranked list of cuts (roadmap Section 5) to apply only if a stage slips. Sources:

| # | Decision | Source |
|---|---|---|
| 1 | Moustafa owns every stage; all 57 issues are assigned to him; teammates are removed from `team.json` and CODEOWNERS. | **Moustafa** |
| 2 | Stages run mostly in sequence (P3 W3, P4 W4–W5, P5 W5–W7, P6 W7–W8); data writing runs daily W1–W4. | **Claude's recommendation** |
| 3 | Smaller data targets: test + dev ≥ 300 sentences (target 350, about 20 a day), training ≥ 2,000 pairs by end of W4. | **Claude's recommendation** |
| 4 | The second-annotator check becomes a **delayed self-check** (≥ 24 h later, against `docs/SPELLING.md`). Single-writer test data is reported as a limitation; AladdinBench (local only) is the check on other people's typing. | **Claude's recommendation** |
| 5 | Review on every PR: the author's self-review checklist plus an AI review (`/code-review` in Claude Code), with findings answered in the PR. Approvals stay at 0 in the `protect-main` ruleset; PRs stay required. | 0 approvals: **Moustafa** (12 Oct 2026). Self-review + AI review: **Claude's recommendation** |
| 6 | "A teammate re-runs it" checks become "re-run from a fresh clone / fresh notebook session / fresh macOS user account, using only the docs". | **Claude's recommendation** |
| 7 | Ranked cuts if behind: CodeQL/Dependabot → per-app profiles and menu settings → extra ablations → XPC service (engine runs in the sandboxed IME process instead). | **Claude's recommendation** |

## Consequences

- **Course risk:** the brief describes a team project, and the bonus for process rewards reviews between people. An AI review is not a human review; the report should say so plainly. Whether Omar and Mohamad stay on the course team is between Moustafa and Dr. Mohanna; nothing in the repo removes their earlier commits or credit.
- **Data risk:** one writer means one spelling habit in test and dev. Accuracy on the test set may overstate accuracy on other people's typing; the AladdinBench check and the error analysis must be reported next to it.
- **Time risk:** about 10 weeks for one person. The weekly retro checks the roadmap dates, and the first cut in Section 5 is applied as soon as a stage is a week late.
- `bootstrap.py` now has a single owner (`OWNERS = ("moustafa",)`); `owner:omar` and `owner:mohamad` labels are no longer created.

## Amendment (14 Oct 2026): Mohamad contributes code

| # | Decision | Source |
|---|---|---|
| 8 | Mohamad Al Masri contributes code through pull requests, starting with the B1 base-model systems (P3 step 4, `eval/src/arabizi_eval/b1.py`). Moustafa still owns every stage and issue, runs the official measurements on the 8 GB Air, and gives the go for downloads. | **Moustafa** (agreement reported by Mohamad, 14 Oct 2026) |
| 9 | Mohamad works on Windows, so runs on that machine are smoke runs only: latency, memory and private-data results come from Moustafa's Air (EVAL.md, "B1"). | **Claude's recommendation** |
| 10 | Moustafa reviews Mohamad's PRs when possible, in addition to the self-review and `/code-review`: a review between people counts for the process bonus. Not yet agreed. | **Claude's recommendation** (proposal) |
