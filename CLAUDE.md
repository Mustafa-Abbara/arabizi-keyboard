# Notes for AI coding assistants (Claude Code)

This repo is a course project (EECE 503N/798S, Fall 2026): a local, private macOS input method that converts Lebanese Arabizi to Arabic script. The team uses AI coding tools openly and stays responsible for every line (see CONTRIBUTING.md, "AI-assisted code").

## Read first

- `docs/ROADMAP.md`: the **Phase 1** stage plan (P0–P7) with gates. This is the primary source.
- `docs/decisions/0010-phase1-pivot.md`: why Phase 1 replaced the v1 agentic plan, and what still applies from v1.
- `docs/archive/ROADMAP_v1_agentic.md`: the v1 plan (S0–S12). Still a reference for IME, CI and security details, and the basis for an optional Phase 2.
- `docs/QUESTIONS_BEFORE_BUILDING.md`: 100 design questions with recommended answers, written for v1. ADR 0010 overrides it and ADR 0009 where they conflict (e.g. Q57, Q70). Flag any new conflict instead of silently picking a side.
- `docs/ASSUMPTIONS.md` and `docs/decisions/`: what is confirmed, what is not, and why.

## Working rules

- **Say where a choice comes from.** When applying something the assistant itself recommended (not from the roadmap, the questions doc, the course brief or a team member), say so explicitly in the reply and record it as "Claude's recommendation" in the relevant ADR or doc (example: ADR 0008).
- Do not commit or push unless asked. Follow CONTRIBUTING.md: branches, Conventional Commits, PR template.
- Never commit model weights, `.env`, signed consent forms, raw participant text, or MADAR-derived files.
- Never automate Yamli. AI-generated Arabizi pairs are allowed **in training only**, each row checked by a native speaker, provider terms recorded (ADR 0010). Dev and test data are always human-written.
- Inference stays local. Fine-tuning may run on Kaggle/Colab with team-written or licensed public data only.
- Main dev machine: M2 MacBook Air, **8 GB RAM** (see the "8 GB consequences" section in ASSUMPTIONS.md). Keep memory use in mind.

## Current state (update when it changes)

- **Phase 1 pivot (12 Oct 2026, ADR 0010):** goal is a fine-tuned local Arabizi→Arabic translator + the macOS keyboard; agents are an optional Phase 2. Stages renamed P0–P7; v1 roadmap archived.
- **Stage P0 (was S0) in progress.** Scaffold, CONTRIBUTING, templates, pre-commit, ASSUMPTIONS, ADR 0001, ADR 0008 and ADR 0010 are written.
- **ADR 0001 answered by the team** (Moustafa, 10 Oct 2026), not by the instructor: Path A, no VoiceType code reuse, public repo, local unsigned install, interviews and the user study deferred (no outside participants until IRB approval).
- **Waiting on:** branch protection on `main`, teammate invites, and GitHub usernames for `scripts/github/team.json` and `.github/CODEOWNERS`, full Xcode on Moustafa's Mac, and replacing the 104 v1 GitHub issues with P0–P7 issues.
