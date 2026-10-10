# Arabizi Keyboard (working title)

Lebanese users chat in Arabizi (`b3at 100$ la mohammad`) but often need Arabic script: formal messages, older relatives, work.
Today that means word-by-word web tools and copy-paste, which get context wrong (`لا محمد` instead of `لمحمد`) and send typed text to a server.
This project builds a **local, private macOS input method** that converts Arabizi at the sentence level. Deterministic rules and a dictionary do most of the work. Two bounded agents handle the rest: one resolves ambiguous words or asks the user, and the other learns personal habits only after testing them.

> EECE 503N/798S — Agentic Systems, Fall 2026. Path A (application), pending instructor confirmation (see [ADR 0001](docs/decisions/0001-instructor-confirmations.md)).

**Status:** Stage S0 (setup). See [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository map

| Path | Purpose |
|---|---|
| `docs/ROADMAP.md` | Stage-by-stage build plan (S0–S12) with gates and rubric mapping |
| `docs/QUESTIONS_BEFORE_BUILDING.md` | 100 design questions with recommended answers (team research) |
| `docs/ASSUMPTIONS.md` | Every unconfirmed assumption and its status |
| `docs/decisions/` | Architecture decision records (ADRs) |
| `docs/process/S0_SETUP.md` | Runbook for setting up tools, GitHub, and the S0 gate |
| `scripts/doctor.py` | Checks that your machine has the required tools |
| `scripts/github/bootstrap.py` | Creates labels, milestones, issues (from the roadmap) and branch rules on GitHub |

More folders (`Packages/`, `Apps/`, `eval/`, `config/` …) arrive in stage S4.

## Team

| Member | Area |
|---|---|
| Omar Al Itani | IME / macOS, CI |
| Mohamad Al Masri | Model, resolver, benchmarks |
| Moustafa Abbara | Users, data, evaluation, memory; project coordination |

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[MIT](LICENSE). Model weights and third-party datasets have their own licences and are never committed. See `docs/MODELS.md` and `docs/DATA.md` (added in S3 and S6).
