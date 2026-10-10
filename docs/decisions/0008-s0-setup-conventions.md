# ADR 0008: Repository and process conventions chosen in S0

- **Status:** accepted
- **Date:** 2026-10-10
- **Deciders:** Moustafa (on Claude's recommendation; see "Origin" column)
- **Stage:** S0

> Numbering: ADRs 0002–0007 are reserved by the roadmap for the candidate panel, runtime, model, contacts, Keychain and SQLCipher decisions.

## Context

The roadmap fixes most of S0, but it leaves some choices open and says nothing about others. This ADR records those choices and **where each came from**, so the team can tell roadmap decisions from tool-suggested ones when defending them.

## Decisions

| # | Decision | Alternatives | Origin |
|---|---|---|---|
| 1 | **MIT licence** | Apache-2.0 (patent grant, longer) | Roadmap allowed either. **MIT was Claude's recommendation**, accepted by Moustafa. |
| 2 | Repo owned by **Moustafa's personal GitHub account**, with Omar and Mohamad as collaborators | GitHub organization (all three as owners) | **Moustafa's decision**, which overrides Claude's recommendation of an organization. Consequence: only Moustafa can change repo settings (rulesets, security, Actions secrets), so S4's required status checks are applied by Moustafa. |
| 3 | **LF line endings** enforced via `.gitattributes` (CRLF only for `.ps1/.bat/.cmd`) | Rely on each member's `core.autocrlf` | **Claude's recommendation**: the team mixes Windows and macOS |
| 4 | **pre-commit** hooks (gitleaks, large-file limit 1 MB, YAML/JSON checks) | gitleaks in CI only | Roadmap requires gitleaks. Running it locally via pre-commit was **Claude's recommendation**. |
| 5 | **Ruleset** (not classic branch protection) on the default branch: PR + 1 review, linear history, no force-push or deletion, no bypass actors. Squash merge only. | Classic branch protection | Roadmap requires the protections. Rulesets and squash-only were **Claude's recommendation**. |
| 6 | Required status checks added in **S4**, not S0 | Add them now | **Claude's recommendation**: GitHub can only require a check after it has run at least once |
| 7 | Secret-blocking gate is proven by a local gitleaks refusal plus a screenshot of the push-protection setting, not by pushing a fake AWS key | Roadmap's fake-AWS-key push test | **Claude's recommendation**: GitHub ignores well-known example keys, so that test can pass without proving anything |
| 8 | One merged instructor email (ADR 0001) combining the roadmap's and `QUESTIONS_BEFORE_BUILDING.md`'s questions, plus two extra: macOS-only scope and compute time as "cost per successful task" | Send the two drafts separately; roadmap questions only | Merging and the two extra questions were **Claude's recommendation** |
| 9 | Roadmap issues created by script (`scripts/github/bootstrap.py`), one per numbered step plus one gate checklist per stage | Create issues by hand | Roadmap requires the issues. Generating them by script was **Claude's recommendation**. |

## Consequences

- Any of these can be revisited with a new ADR. None is load-bearing for the product architecture.
- Items marked as Claude's recommendation should be explained in our own words if the instructor asks about them.
