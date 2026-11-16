# Harfi: an Arabizi keyboard

Lebanese users chat in Arabizi (`b3at 100$ la mohammad`) but often need Arabic script: formal messages, older relatives, work.
Today that means word-by-word web tools and copy-paste, which get context wrong (`لا محمد` instead of `لمحمد`) and send typed text to a server.
This project builds **Harfi, a local, private keyboard for macOS and Windows**: type Arabizi, press Enter, and the whole message becomes Lebanese Arabic script. The conversion is done by a **small open model we fine-tune ourselves**, running only on your computer, with a rule-based fallback. Agentic features (asking about ambiguous words, learning personal habits) are a possible Phase 2.

> EECE 503N/798S — Agentic Systems, Fall 2026. Path A (application). Phase 1 scope approved by Dr. Mohanna (see [ADR 0010](docs/decisions/0010-phase1-pivot.md)).

**Status:** Harfi 0.4.0 for Mac and Windows, with model v4. Install: [docs/INSTALL.md](docs/INSTALL.md). Plan and gates: [docs/ROADMAP.md](docs/ROADMAP.md).

## Results

Word accuracy of the shipped keyboard engine (words right ÷ words in the longer of reference and output), on held-out messages the models never trained on; 95% bootstrap intervals; each test set run once per model.

| Test set | Rules only | Model v3 | **Model v4** | v4 − v3 (paired) |
|---|---|---|---|---|
| Frozen test (243 messages) | 0.594 | 0.836 | **0.864** | **+0.028** [+0.013, +0.044] |
| Others test (299 messages by other writers) | 0.607 | 0.826 | **0.848** | **+0.022** [+0.009, +0.036] |
| Real chats by new writers (1,642 messages, private; aggregates only) | 0.820 | 0.892 | **0.912** | **+0.020** [+0.014, +0.025] |
| Held-out synthetic test (5,342 messages) | 0.721 | 0.802 | **0.918** | +0.115 [+0.111, +0.119] |

| Messages with every word right | v3 | **v4** |
|---|---|---|
| Frozen test | 41% | **44%** |
| Others test | 16% | **22%** |
| Real chats by new writers | 59% | **65%** |

v4 is v3's model trained again with 39,340 synthetic training pairs, written by four AI models in two steps aimed at v3's measured errors (word forms it had not seen, rarely seen words, short words read from context, ط ص ض ظ typed as t s d z, English and French kept in Latin), then cleaned, filtered and checked by hand. How each weakness was closed, the cleaning steps and every comparison: [docs/MODEL_V4.md](docs/MODEL_V4.md). Decision: [ADR 0038](docs/decisions/0038-model-v4.md). Earlier models and metrics: [docs/EVAL.md](docs/EVAL.md).

When a word is wrong, the ↑ list offers the right one among its 6 for 78% of v4's wrong words on the real chats, and puts it first 55% of the time (50% with 0.4.0's ranker). With the model's guesses turned on, that becomes 85% and 62%. "Spell it" is needed for 2.9% of all words (2.5% with guesses). What was tried and what limits it: [docs/RANKER_V4.md](docs/RANKER_V4.md), [ADR 0039](docs/decisions/0039-ranker-v4.md).

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
