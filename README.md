# Harfi: an Arabizi keyboard

Lebanese users chat in Arabizi (`b3at 100$ la mohammad`) but often need Arabic script: formal messages, older relatives, work.
Today that means word-by-word web tools and copy-paste, which get context wrong (`لا محمد` instead of `لمحمد`) and send typed text to a server.
This project builds **Harfi, a local, private keyboard for macOS and Windows**: type Arabizi, press Enter, and the whole message becomes Lebanese Arabic script. The conversion is done by a **small open model we fine-tune ourselves**, running only on your computer, with a rule-based fallback. Agentic features (asking about ambiguous words, learning personal habits) are a possible Phase 2.

> EECE 503N/798S — Agentic Systems, Fall 2026. Path A (application). Phase 1 scope approved by Dr. Mohanna (see [ADR 0010](docs/decisions/0010-phase1-pivot.md)).

**Status:** Harfi 0.5.2 for Mac and Windows, with model v5. Install: [docs/INSTALL.md](docs/INSTALL.md). Plan and gates: [docs/ROADMAP.md](docs/ROADMAP.md).

## Results

Word accuracy of the shipped keyboard engine (words right ÷ words in the longer of reference and output), on held-out messages the models never trained on; 95% bootstrap intervals; each test set run once per model.

### Model v5 (0.5.0)

Both models' answers are scored in spelling v2.0 ([ADR 0040](docs/decisions/0040-spelling-v2.md)): v4's are converted first, so it is not marked wrong for writing أ or a plural وا.

| Test set | Model v4 | **Model v5** | v5 − v4 (paired) |
|---|---|---|---|
| Frozen test (243 messages) | 0.876 | **0.877** | +0.001 [−0.012, +0.014] |
| Others test (299 messages by other writers) | 0.857 | **0.854** | −0.003 [−0.013, +0.006] |
| Comparison set (300 messages) | 0.907 | **0.907** | −0.000 [−0.009, +0.009] |
| Real chats by new writers (1,642 messages, private; aggregates only) | 0.923 | **0.925** | +0.002 [−0.001, +0.006] |
| Held-out synthetic test (3,528 messages) | 0.901 | **0.915** | **+0.014** [+0.010, +0.018] |

v5 is v4's model trained again with the same recipe on the spelling v2.0 data plus a sixth round of AI-written pairs (11,393 rows, checked, with no word taken from an evaluation set). It is as accurate as v4 on real messages and writes the new spelling itself (ا for أ/إ, plural و, ليه/ليش), which v4 does not. The same size and speed. A smaller Qwen3-0.6B trained on the same data was 0.017 behind v4 on the others test and is not shipped. Every comparison: [docs/EVAL.md](docs/EVAL.md#llama-v5-against-v4-19-nov-2026).

**With the ↑ list (0.5.1).** Share of all words, model v5, the model's 5 guesses on (both keyboards):

| Set | Right first time | Right after one pick from the ↑ list | Needs "Spell it" (letter by letter) |
|---|---|---|---|
| Real chats by new writers | 92.4% | **97.2%** | **2.8%** |
| Frozen test | 87.7% | 94.2% | 5.8% |
| Others test | 85.4% | 92.1% | 7.9% |

"After one pick" counts a wrong word as fixed when its right form is among the 6 entries the list shows, including the merge and split entries ([ADR 0041](docs/decisions/0041-merge-split.md)). What each data step added to the model: [docs/EVAL.md](docs/EVAL.md#data-ablations-what-each-data-step-added-22-nov-2026).

### Model v4 (0.4.0)

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

## Reproduce the results

You need `git` and [uv](https://docs.astral.sh/uv/). The model runs need Swift 6 too, and on Windows Visual Studio's C++ build tools and CMake.

1. **Clone the repository.** On Windows, use a short folder such as `C:\src`, because the llama.cpp build refuses paths over 260 characters.
   ```
   git clone https://github.com/Mustafa-Abbara/arabizi-keyboard.git
   cd arabizi-keyboard
   ```
2. **Run the rules (no model).** This needs Python only, through uv:
   ```
   uv run --project eval evalrun run --system b0 --split dev
   ```
   Word accuracy 0.762 on dev.
3. **Get the model** (808 MB, checked part by part):
   ```
   python3 scripts/fetch_models.py --shipped --accept-licence llama
   ```
4. **Build the engine's command-line tool:**
   - **Mac:**
     ```
     swift build -c release --package-path Packages/ArabiziEngine --product arabizi-cli
     ```
   - **Windows:** first build llama.cpp as in [Apps/HarfiWindows/README.md](Apps/HarfiWindows/README.md), then:
     ```
     swift build -c release --package-path Packages/ArabiziEngine --product arabizi-cli -Xcc -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
     ```
5. **Run the model through the keyboard engine:**
   ```
   uv run --project eval evalrun run --system engine-arabizi-llama3.2-1b-v5-kb --split dev
   ```
   Word accuracy 0.870 on dev with nothing else running. This system uses the keyboard's own deadline, so a busy computer sends some messages to the rules and scores lower.

Each run writes its answers and scores to `eval/results/`. The test sets need `--final` and are run once per final system ([docs/EVAL.md](docs/EVAL.md)). Installing the keyboard itself: [docs/INSTALL.md](docs/INSTALL.md).

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
| `Apps/ArabiziIME` | The Mac keyboard (InputMethodKit) and its sandboxed engine service |
| `Apps/HarfiWindows` | The Windows keyboard (a text service), its installer and the Harfi window |
| `Packages/ArabiziCore` | What both keyboards share: rules, the composer, the ↑ list, your words |
| `Packages/ArabiziEngine`, `Packages/ArabiziLLM` | The conversion engine and the model runner (llama.cpp) |
| `config/` | The engine's settings and the pinned models (`models.json`, with each file's SHA-256) |
| `data/` | The training pairs, the frozen test set, the rule files (`data/pairs/`, `data/rules/`) |
| `eval/` | The evaluation harness and every run (`eval/results/`) |
| `train/` | The fine-tuning scripts and notebooks (Kaggle, Colab) and each run's record |
| `scripts/` | Builds, installers, data tools and `fetch_models.py` |
| `site/` | The website |

## Team

Built by **Moustafa Abbara** (all stages; see [ADR 0011](docs/decisions/0011-solo-build.md)). Omar Al Itani and Mohamad Al Masri took part in the planning and setup (S0).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[MIT](LICENSE). Model weights and third-party datasets have their own licences and are never committed. See `docs/MODELS.md` and `docs/DATA.md` (added in P3 and P2).
