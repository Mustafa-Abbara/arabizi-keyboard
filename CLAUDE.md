# Notes for AI coding assistants (Claude Code)

This repo is a course project (EECE 503N/798S, Fall 2026): a local, private macOS input method that converts Lebanese Arabizi to Arabic script. The team uses AI coding tools openly and stays responsible for every line (see CONTRIBUTING.md, "AI-assisted code").

## Read first

- `docs/ROADMAP.md`: the stage plan (S0–S12) with gates. This is the primary source.
- `docs/QUESTIONS_BEFORE_BUILDING.md`: 100 design questions with recommended answers. Where it conflicts with the roadmap, `docs/decisions/0009-plan-conflict-resolutions.md` decides (D1–D25, all Claude's recommendations, already applied in the roadmap). Flag any new conflict instead of silently picking a side.
- `docs/ASSUMPTIONS.md` and `docs/decisions/`: what is confirmed, what is not, and why.

## Working rules

- **Say where a choice comes from.** When applying something the assistant itself recommended (not from the roadmap, the questions doc, the course brief or a team member), say so explicitly in the reply and record it as "Claude's recommendation" in the relevant ADR or doc (example: ADR 0008).
- Do not commit or push unless asked. Follow CONTRIBUTING.md: branches, Conventional Commits, PR template.
- Never commit model weights, `.env`, signed consent forms, raw participant text, or MADAR-derived files.
- Never automate Yamli, and never generate Arabizi with an AI model for datasets.
- Main dev machine: M2 MacBook Air, **8 GB RAM** (see the "8 GB consequences" section in ASSUMPTIONS.md). Keep memory use in mind.

## Current state (update when it changes)

- **Stage S0 in progress.** Scaffold, CONTRIBUTING, templates, pre-commit, ASSUMPTIONS, ADR 0001 (instructor email) and ADR 0008 (S0 conventions) are written.
- **Waiting on:** the instructor reply (ADR 0001), the IRB exemption with Dr. Mohanna as PI, CITI training for all three members, and GitHub usernames for `scripts/github/team.json` and `.github/CODEOWNERS`.
