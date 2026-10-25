# Arabizi Keyboard (working title)

Lebanese users chat in Arabizi (`b3at 100$ la mohammad`) but often need Arabic script: formal messages, older relatives, work.
Today that means word-by-word web tools and copy-paste, which get context wrong (`لا محمد` instead of `لمحمد`) and send typed text to a server.
This project builds a **local, private macOS input method**: type Arabizi, press Enter, and the whole message becomes Lebanese Arabic script. The conversion is done by a **small open model we fine-tune ourselves**, running only on the Mac, with a rule-based fallback. Agentic features (asking about ambiguous words, learning personal habits) are a possible Phase 2.

> EECE 503N/798S — Agentic Systems, Fall 2026. Path A (application). Phase 1 scope approved by Dr. Mohanna (see [ADR 0010](docs/decisions/0010-phase1-pivot.md)).

**Status:** Phase 1, stage P0 (setup). See [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository map

| Path | Purpose |
|---|---|
| `docs/ROADMAP.md` | Phase 1 build plan (P0–P7) with gates and rubric mapping |
| `docs/archive/ROADMAP_v1_agentic.md` | The original agentic plan (S0–S12), kept for reference and Phase 2 |
| `docs/QUESTIONS_BEFORE_BUILDING.md` | 100 design questions with recommended answers (written for v1; ADR 0010 overrides where they conflict) |
| `docs/ASSUMPTIONS.md` | Every unconfirmed assumption and its status |
| `docs/decisions/` | Architecture decision records (ADRs) |
| `docs/process/S0_SETUP.md` | Runbook for setting up tools, GitHub, and the S0 gate |
| `scripts/doctor.py` | Checks that your machine has the required tools |
| `scripts/github/bootstrap.py` | Creates labels, milestones, issues (from the roadmap) and branch rules on GitHub |

More folders arrive as the stages need them: `Apps/ArabiziIME` (P1), `data/` (P2), `eval/` (P3), `train/` (P4), `Packages/` and `config/` (P5).

## Team

Built by **Moustafa Abbara** (all stages; see [ADR 0011](docs/decisions/0011-solo-build.md)). Omar Al Itani and Mohamad Al Masri took part in the planning and setup (S0).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[MIT](LICENSE). Model weights and third-party datasets have their own licences and are never committed. See `docs/MODELS.md` and `docs/DATA.md` (added in P3 and P2).
