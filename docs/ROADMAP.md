# Build Roadmap, Phase 1: Fine-tuned Arabizi Translator + macOS Keyboard (EECE 503N/798S, Fall 2026)

> **This roadmap replaces the v1 agentic roadmap for now** ([ADR 0010](decisions/0010-phase1-pivot.md)). **Moustafa builds Phase 1 alone** ([ADR 0011](decisions/0011-solo-build.md)), so every stage is owned by Moustafa and stages run mostly one after another. The v1 plan is kept unchanged in [archive/ROADMAP_v1_agentic.md](archive/ROADMAP_v1_agentic.md) and is still a valid reference for anything this file does not cover (IME details, CI, security). Choices tagged `[Claude's recommendation]` came from the assistant, not from the team, the instructor or the course brief.

**Goal of Phase 1:** a macOS input method where you type Lebanese Arabizi (`kifak, shu 3am ta3mel?`), press **Enter**, and the whole text becomes Lebanese Arabic script (`كيفك، شو عم تعمل؟`). A second Enter sends the message. The conversion is done by a **small open model that we fine-tune ourselves** and that runs **only on the Mac**. Nothing the user types leaves the machine.

**Phase 2 (later, optional):** the agentic parts from v1 (sentence resolver that can ask, memory curator). They are only considered after the Phase 1 gates pass. See Section 6.

## TL;DR

- **Weeks 1–2:** prove the risky parts first: an IME that works in WhatsApp/Slack (P1), and data + a frozen test set (P2).
- **Weeks 2–3:** measure baselines: a rule-based transliterator and the base models with no fine-tuning (P3).
- **Weeks 3–5:** fine-tune in the cloud (free Kaggle/Colab GPU), export to GGUF, and prove on the frozen test set that fine-tuning beats the baselines (P4).
- **Weeks 4–8:** wrap the model in a local Swift engine with no network access, then wire it into the keyboard (P5, P6).
- **Weeks 9–10:** final evaluation, hardening, docs, demo (P7).
- **Three rules that never change:** inference is local only; the test set is human-written and frozen; English words, digits, URLs and emoji come out exactly as typed.

---

## 0. Assumptions and decisions (read first)

All assumptions live in [ASSUMPTIONS.md](ASSUMPTIONS.md); the decisions behind this plan are in [ADR 0010](decisions/0010-phase1-pivot.md). The ones that shape this roadmap:

- **Scope approved.** Dr. Mohanna approved the Phase 1 scope (reported by Moustafa, 12 Oct 2026).
- **Calendar (A1, open).** Project Week 1 = 12–18 Oct 2026; poster pitch ≈ end of W5; final demo ≈ W10 (14–18 Dec).
- **Hardware (A4).** The reference machine is Moustafa's **M2 MacBook Air, 8 GB**. Latency and memory budgets are measured there.
- **Training happens in the cloud, inference happens locally.** Free Kaggle (about 30 GPU hours a week) or Google Colab GPUs are used for fine-tuning only. Only hand-written or licensed public text is uploaded; real users' text never is.
- **Data rule (changed by ADR 0010).** AI-generated pairs are allowed **in training only**, after a native speaker checks each row, and only from a provider whose terms allow training on its outputs. Dev and test data are written by humans.
- **No outside participants** until IRB approval (A8). All Phase 1 data is hand-written or from licensed public sources.

### Budgets (on the 8 GB Air) [Claude's recommendation; P3 verifies them]

| Budget | Value |
|---|---|
| Engine peak memory (RSS) | ≤ 1.5 GB |
| Conversion latency, sentence ≤ 15 words, warm | p50 ≤ 600 ms, p95 ≤ 1.2 s |
| Model file | ≤ 1.2 GB (0.5B–1.5B model at Q4_K_M) |
| Fallback when the model times out or fails a check | rule-based transliteration, never an error |

---

## 1. Overview: stages, weeks, owners, dependencies

Moustafa owns every stage (ADR 0011). Work is sequential except **P2 data writing, which runs every day from W1 to W4** (about 30–45 minutes a day) alongside the other stages.

| Stage | What it delivers | Project week (assumed dates) | Lead | Depends on |
|---|---|---|---|---|
| P0 | Setup, project board, tools (the old S0) | W1 (12–18 Oct) | Moustafa | – |
| P1 | IME spike: hello-world input method + per-app Enter matrix | W1–W2 | Moustafa | P0 |
| P2 | Data: spelling guide, hand-written pairs, frozen test set, training pairs | W1–W4 (test freeze end of W3) | Moustafa | P0 |
| P3 | Eval harness + baselines: rules (B0) and base models without fine-tuning (B1) | W3 | Moustafa | P2 |
| P4 | Fine-tuning in the cloud, GGUF export, comparison with baselines | W4–W5 | Moustafa | P2, P3 |
| P5 | Local engine: Swift package + XPC service (no network), rule fallback, CI | W5–W7 | Moustafa | P1, P4 |
| P6 | Keyboard integration: Enter-to-convert, marked text, undo, settings | W7–W8 | Moustafa | P1, P5 |
| P7 | Final evaluation, hardening, docs, demo and submission | W9–W10 (14–18 Dec) | Moustafa | P6 |

**Critical path:** P2 → P3 → P4 → P5 → P6. Data is the biggest risk, so it starts on day 1 alongside the IME spike. Working alone, the second risk is time: Section 5 lists what to cut first.

**Weekly rhythm.** One-week sprints: plan on Monday (move issues to *This sprint*), a short written retro on Friday (went well / went badly / change) in a pinned Discussion. Every task is a GitHub Issue on the Projects board.

---

## 2. Learning ramp (week 1, in parallel with P0–P2)

About 8–12 hours in W1, spread over the week:

1. **Swift basics:** "A Swift Tour", then small command-line programs with `swift package init --type executable`. Learn `struct`, `enum` with associated values, `Codable`, `async/await`, `actor`.
2. **Testing:** write 5 tests with Swift Testing or XCTest in a toy package and run `swift test`.
3. **macOS IME concepts:** the client is the app's text field; the IME is a background app receiving key events; **marked text** is the temporary underlined text (`setMarkedText`); **commit** sends final text (`insertText`). Apple's NumberInput sample shows both.
4. **Fine-tuning concepts:** what a chat template is; **LoRA** (train small adapter matrices instead of the whole model); train/dev loss and overfitting; **GGUF** and **Q4 quantization** for llama.cpp; greedy decoding at temperature 0.
5. **Evaluation concepts:** word accuracy with several accepted spellings, character error rate (CER), why the test set is frozen, and the paired bootstrap for confidence intervals.

**Gate (ramp):** A toy package with at least 5 passing tests is pushed to a branch. You can explain, in a few sentences each, marked text vs commit, LoRA and what quantization costs in accuracy, and multi-reference word accuracy.

---

## 3. The stages

### P0 — Setup, project board and tools (W1)

**What this stage does (simple):** Set up the "factory": repo, board, branch rules and tools. This is the old S0; only the stage name changed. The runbook is [process/S0_SETUP.md](process/S0_SETUP.md).

**Steps:**
1. **(Moustafa)** Record the scope decisions: ADR 0001 (team answers) and ADR 0010 (Phase 1 pivot, approved by Dr. Mohanna).
2. **(Moustafa)** Turn on **branch protection** on `main` with `scripts/github/bootstrap.py protect`: require a PR, 1 approving review, linear history, no force-push. Status checks are added in P5 once they exist.
3. **(Moustafa)** Fill in `scripts/github/team.json` and `.github/CODEOWNERS`, and run `bootstrap.py labels milestones issues` so the board matches this roadmap.
4. **(Moustafa)** Install tools: full **Xcode** (not only the Command Line Tools), then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`; Homebrew packages from `S0_SETUP.md`; Colima (`colima start --cpu 2 --memory 2`) for Docker on 8 GB Macs. Run `python scripts/doctor.py` until it reports no missing or broken tools.
5. **(Moustafa)** Create a free **Kaggle** account (phone-verified, needed for GPU access) and a Hugging Face account. Base models are downloaded from Hugging Face; fine-tuned weights are stored in a **private** Hugging Face repo or Kaggle dataset, never in git.

**Deliverables:** protected `main`, board with P0–P7 issues, ADR 0001, ADR 0010, ADR 0011, `doctor.py` clean.

**Gate (pass before P1–P4 merge anything):**
- [ ] A test PR was opened, reviewed (self-review checklist + `/code-review`, see CONTRIBUTING) and merged. A direct push to `main` is rejected (try it).
- [ ] Push protection blocks a fake secret (commit a dummy AWS-style key on a branch; GitHub should block it, then delete the branch).
- [ ] `swift --version`, `xcodebuild -version` and `docker run hello-world` work.
- [ ] A GPU notebook starts on Kaggle or Colab.

**Rubric mapping:** Bonus (project management, PRs, reviews, branch protection, secret scanning); Software engineering 10%.

---

### P1 — IME spike: hello-world input method + per-app Enter matrix (W1–W2)

**What this stage does (simple):** Prove that a macOS input method can show temporary text and replace it on Enter in real apps (WhatsApp, Slack, browsers) before building anything on top. The conversion here is a toy letter map; the real engine arrives in P5.

**Steps:**
1. **(Moustafa)** Build the spike exactly as in v1 S2, steps 1–6 ([archive](archive/ROADMAP_v1_agentic.md), "S2 — IME spike"): an AppKit app `ArabiziIME` (built from a Swift package by `scripts/build_ime.sh` instead of an Xcode project, [ADR 0013](decisions/0013-ime-build-with-swiftpm.md)), bundle id containing `inputmethod`, Info.plist keys, `IMKServer`, a thin `IMKInputController`, `scripts/install_ime.sh`, and testing on a **second macOS user account**.
2. **(Moustafa)** Implement the **Phase 1 key behaviour** in the spike:
   - Letters, digits and punctuation go into a buffer shown as **marked text in Latin** (what the user typed).
   - **Enter with a non-empty buffer:** replace the buffer with the converted text and commit it. The message is **not** sent.
   - **Enter with an empty buffer:** pass through, so the app sends.
   - **Esc:** commit the buffer unchanged (Latin).
   - **Secure input** (`IsSecureEventInputEnabled()`): pass every key through, show nothing.
3. **(Moustafa)** Fill the **per-app Enter matrix** in `docs/spikes/ime_app_matrix.md` for TextEdit, Safari, Chrome, Slack desktop, WhatsApp desktop, Outlook and Notes, with the 8 cases from v1 S2 step 8 (marked text shows, Enter converts without sending, second Enter sends, Backspace edits the buffer, click-away commits once, Cmd+Z, password fields, long marked text in Electron apps).
4. **(Moustafa)** Measure what a **long buffer** does: type a 25-word sentence as marked text in each app and note glitches. Phase 1 converts whole sentences, so long marked text matters more than in v1.

**Deliverables:** `Apps/ArabiziIME` spike, `scripts/install_ime.sh`, `docs/SETUP_IME.md`, `docs/spikes/ime_app_matrix.md`, a short screen recording.

**Gate:**
- [ ] The IME installs on a clean second user account by following only `docs/SETUP_IME.md` (do it yourself on a **fresh** second user account, reading only the doc).
- [ ] At least 5 of 7 apps pass cases 1–5. Each failure has a written per-app workaround.
- [ ] Password fields in Safari and Chrome: no marked text, keys pass through.
- [ ] No crash in 10 minutes of continuous typing.

**Rubric mapping:** Reliability & security 15% (secure fields, Enter safety); real-world constraint identified (app compatibility).

---

### P2 — Data: spelling guide, pairs, frozen test set, training data (W1–W4)

**What this stage does (simple):** A fine-tuned model is only as good as its examples, and there is no public Lebanese Arabizi→Arabic dataset. We build one: Lebanese sentences in Arabic script paired with how Lebanese people really type them in Arabizi. A **test set** is written by hand and frozen before any fine-tuning. The **training set** is grown with three helpers: rule-made spelling variants, licensed public Lebanese text, and AI-generated pairs that a native speaker checks.

**Steps:**
1. **(Moustafa) Spelling guide** `docs/SPELLING.md`, written before any data, so the Arabic side is spelled consistently:
   - Lebanese spelling, not MSA: `شو`, `هيك`, `كتير`, `عم`, `بدي`, `منيح`.
   - Which variants are both accepted (e.g. `هلق` / `هلأ`), recorded per word in the pair file.
   - **English words stay in Latin** (`ma 3ndi meeting today` → `ما عندي meeting today`). Brand names and people's names written in English stay Latin unless the writer clearly meant Arabic.
   - **Numbers stay as typed.** A digit inside a word is a letter (`3am` → `عم`, `7abibi` → `حبيبي`); a standalone number is kept (`100$`, `2pm`).
   - Punctuation: `?` → `؟` and `,` → `،` [Claude's recommendation; change it here if the team prefers to keep Latin punctuation].
2. **(Moustafa) Pair format** `data/pairs/*.jsonl`, one row per pair, schema in `data/schema/pair.schema.json`, documented in [DATA.md](DATA.md):
   ```json
   {"id": "hw-0001", "arabizi": "ma 3ndi meeting today", "arabic": "ما عندي meeting today",
    "accepted": {}, "method": "hand", "writer": "moustafa", "checked_by": "moustafa-delayed",
    "source": "hand-written", "split": "test", "date": "2026-10-14"}
   ```
   `method` is one of `hand`, `rule_variant`, `public` (with the dataset name in `source`) or `ai_checked`. Every row must say who wrote it and who checked it. `eval/tests/test_pairs.py` validates the schema and the automatic spelling rules; `uv run --project eval pairs add|check|stats` writes and checks rows.
3. **(Moustafa) Test and dev sets (human-written only).** Target **350 sentences** by the end of W3 (gate passes at 300), about 20 a day [Claude's recommendation for a solo writer]:
   - Topics: plans, money, family, work, food, university, greetings, complaints, jokes; include English code-switching, names, numbers and prices.
   - Write the Arabizi **the way you actually type it in WhatsApp**, before writing the Arabic, and do not "clean up" your spelling.
   - **Delayed self-check** [Claude's recommendation]: at least 24 hours later, re-read each pair against `docs/SPELLING.md` and fix the Arabic side; set `checked_by` to `moustafa-delayed`.
   - Split: **test 70% / dev 30%** by sentence [Claude's recommendation]. With one writer, test and dev share a writer and a spelling habit; this is reported as a limitation, and the external check in step 8 measures how the model does on other people's typing.
4. **(Moustafa) Freeze the test set** with `pairs freeze` (docs/DATA.md, "The test-set freeze"), before any fine-tuning; planned for the end of W3: `data/pairs/manifest.json` with the SHA-256 of `test.jsonl` and `dev.jsonl`, git tag `testset-v1.0`. A test in CI fails if a test file changes; a deliberate change needs the `testset-change` label and a written reason in the PR and in `docs/DATA.md`. Prompts, hyperparameters and checkpoints are only ever chosen on **dev**.
5. **(Moustafa) Rule-based Arabizi generator** `data/tools/variants.py` — **the main training source** ([ADR 0012](decisions/0012-training-data-sources.md)). Implemented as `pairs variants` (`eval/src/arabizi_eval/variants.py`): it **re-spells the Arabizi** of each training pair rather than building Arabizi from Arabic alone (ADR 0012 amendment), produces 2 spellings per row by default from a table of real alternatives (`3`/`a`/`aa` for ع, `7`/`h` for ح, `sh`/`ch` for ش, `ou`/`u`/`o`, doubled letters, dropped vowels). The table lives in `data/rules/arabizi_variants.json` and is reviewed against real examples from your own chats before use. Variants go to **train only** with `method: rule_variant`.
6. **(Moustafa) Licensed public text** (check and record each licence in `docs/DATA.md` first):
   - **Baladi** (Lebanese, CC BY 4.0, Birzeit "Curras + Baladi" portal): Lebanese Arabic-script sentences. The team writes the Arabizi side. Credit the authors.
   - **LanguageWave / LebEval** (Lebanese podcast sentences, arXiv 2505.00114): use only if the repo's licence allows it.
   - **ATAR** (25K Jordanian pairs): email the authors about the licence; if allowed, use for train only, tagged as Jordanian.
   - **MADAR** stays local for evaluation only and is never committed or trained on.
   - **No scraping** of X, Facebook, Reddit, YouTube or similar (their terms, other people's text) [ADR 0012].
7. **(Moustafa) AI-generated pairs, train only** [Moustafa's decision, ADR 0010]:
   - Before generating, record in `docs/DATA.md` which provider and model you use, and a quote of the part of its terms that allows training another model on its outputs. If the terms forbid it, use a different provider or skip this step.
   - Save the exact prompt in `data/prompts/`. Generate in small batches (≤ 100 rows). (The first batch, 500 Claude-drafted rows revised by Moustafa, has no saved prompt; recorded in ADR 0012.)
   - A native speaker checks **every row** and fixes or deletes it; `checked_by` is filled in. Unchecked rows are never used.
   - Run a near-duplicate check against dev and test (exact match after normalisation and ≥ 0.9 character similarity) and drop any hits.
   - Cap AI rows at **half of the training set used in P4** (the cap applies once the rule-generated rows exist), and in P4 train once with and once without them to show what they add [Claude's recommendation].
8. **(Moustafa) External real-typing check (local only).** AladdinBench (Hugging Face `palmaoui/AladdinBench`) has 268 real Lebanese WhatsApp Arabizi segments, but its references are MSA and its licence is CC BY-NC-ND. Keep it **outside the repo**; a team member writes Lebanese Arabic-script references locally, and we report results on it as a secondary, unpublished check.
9. **(Moustafa) Datasheet** `docs/DATA.md`: sources, licences, counts per method and split, writers, known biases (a single writer for test/dev, Beirut-centric spelling), and what may be published.

**Targets:** test + dev ≥ 300 sentences (frozen end of W3); training set ≥ 2,000 pairs by end of W4, of which ≥ 400 are hand-written or `public` rows with hand-written Arabizi.

**Deliverables:** `docs/SPELLING.md`, `docs/DATA.md`, `data/pairs/` + `manifest.json` + tag `testset-v1.0`, `data/tools/variants.py`, `data/rules/arabizi_variants.json`.

**Gate:**
- [ ] Test + dev ≥ 300 human-written sentences, each with a delayed self-check; the freeze check fails CI when one test line is edited on a branch.
- [ ] Training set ≥ 2,000 pairs with `method` and `checked_by` on every row; the schema test passes.
- [ ] No training row matches a dev/test row (duplicate check in CI).
- [ ] Every source in `docs/DATA.md` has a licence line, and every `ai_checked` batch has its provider-terms note.

**Rubric mapping:** Agent performance/evaluation 20% (data, held-out test, provenance); guardrail "public/authorised data, respect ToS"; Documentation 10%.

---

### P3 — Eval harness and baselines (W2–W3)

**What this stage does (simple):** Before fine-tuning, measure where we start. B0 is a simple rule-based transliterator (also the engine's fallback later). B1 is each base model with no fine-tuning, given a short prompt and a few examples. Fine-tuning in P4 must beat both.

**Steps:**
1. **(Moustafa) Eval harness** `eval/` (Python, uv, ruff, pytest). Built as `evalrun` (`eval/src/arabizi_eval/run.py`, `metrics.py`, `bootstrap.py`); definitions and choices in [EVAL.md](EVAL.md), plus a punctuation-match metric for SPELLING.md §7:
   - `eval/run.py` runs a system on a split and writes `results/<run_id>/predictions.jsonl` + `metrics.json` (with git SHA, model, quantization, prompt version).
   - `eval/metrics.py`:
     - **Word accuracy** against the reference and its accepted variants, after normalising tatweel and diacritics.
     - **CER** (character error rate).
     - **Keep-Latin F1:** English words kept in Latin when they should be, and only then.
     - **Number preservation:** standalone numbers come out identical (target 100%).
     - **MSA-rewrite rate:** output words from a small MSA list (e.g. `ماذا`, `الآن`, `لكن`) where the reference has the Lebanese word.
     - **Hallucination rate:** output length outside 0.5–2× the input word count, or words added that are not in the input.
     - Latency p50/p95 and peak RSS, for model runs.
   - `eval/bootstrap.py`: paired bootstrap over sentences (10,000 resamples, 95% CI of the difference between two systems).
   - Tests with hand-computed toy examples (accuracy 3/4 = 0.75, a perfect system scores CER 0).
2. **(Moustafa) B0 rule transliterator** in Python (`eval/src/arabizi_eval/b0.py`, system `b0`), driven by `data/rules/arabizi_to_arabic.json` (hand-written: letter rules, clitics, punctuation) and `data/rules/arabizi_lexicon.json` (dictionary generated from the train split by `pairs lexicon`: `shu` → `شو`, `kifak` → `كيفك` …). The same JSON table is later read by the Swift fallback in P5, so both stay identical.
3. **(Moustafa) Runtime:** llama.cpp (`llama-cli` / `llama-server`) with GGUF Q4_K_M models, run one at a time on the 8 GB Air. This keeps the v1 runtime choice (ADR 0003, to be written here) because the same XCFramework works from Swift.
4. **(Moustafa; code with Mohamad) B1 base models, no fine-tuning**, zero-shot and with 5 fixed examples from the public training split [Claude's recommendation: this said "from dev", which would score dev rows whose answers are in the prompt; see EVAL.md, "B1"]. Built as `b1-<model>-zero` / `b1-<model>-5shot` (`eval/src/arabizi_eval/b1.py`):
   - Qwen2.5-0.5B-Instruct and Qwen2.5-1.5B-Instruct (Apache-2.0)
   - Gemma 3 1B (Gemma terms)
   - Llama 3.2 1B Instruct (Llama community licence)

   Never Qwen2.5-3B (non-commercial licence; v1 D2). Record each licence in `docs/MODELS.md`. Temperature 0.
5. **(Moustafa) Pick the base model(s) for fine-tuning** in ADR 0004: the best one or two by dev word accuracy that fit the budgets in Section 0. A model that is weak zero-shot can still be the best base after fine-tuning, so carry two forward if they are close.

**Deliverables:** `eval/` with tests, `results/` for B0 and B1 on dev, `docs/MODELS.md`, ADR 0003 (runtime), ADR 0004 (base model choice).

**Gate:**
- [ ] `pytest eval/tests` passes in CI.
- [ ] Baseline table on **dev**: B0 and each B1 model, word accuracy with 95% CI, CER, Keep-Latin F1, number preservation, latency p50/p95 and RSS on the 8 GB Air.
- [ ] Re-running one baseline from a fresh clone gives the same accuracy (temperature 0) and latency within 20%.
- [ ] At least one model fits the memory budget. If none fits the latency budget, write it down and plan for the smaller model in P4.

**Rubric mapping:** Agent performance/evaluation 20% (baselines, held-out evaluation); real-world constraint (latency/RAM) measured.

---

### P4 — Fine-tuning in the cloud and GGUF export (W3–W5)

**What this stage does (simple):** Teach the chosen base model to convert Lebanese Arabizi using our training pairs. Training runs on a free cloud GPU because the 8 GB Air is too small to train comfortably. The result is turned into one GGUF file that runs locally, and is compared with the baselines on the frozen test set exactly once per candidate.

**Steps:**
1. **(Moustafa) Training notebook** `train/finetune_lora.ipynb` (plus a script version `train/finetune_lora.py` so it can be reviewed in PRs). Built: data from `pairs export-train`, guide in [TRAINING.md](TRAINING.md), decisions in [ADR 0015](decisions/0015-fine-tuning-setup.md):
   - Hugging Face `transformers` + `peft` (LoRA) + `trl` `SFTTrainer`, on Kaggle or Colab.
   - Input format: the base model's chat template, a one-line system prompt ("Convert Lebanese Arabizi to Lebanese Arabic script. Keep English words, numbers, links and emoji as they are."), the Arabizi as the user turn, the Arabic as the assistant turn. Loss on the assistant turn only.
   - Starting hyperparameters [Claude's recommendation; tune on dev only]: LoRA rank 16, alpha 32, dropout 0.05 on all attention and MLP projections; learning rate 2e-4; 3 epochs; effective batch 32; max length 256 tokens.
   - Fixed random seed. Log train/dev loss and dev word accuracy each epoch; keep the best checkpoint by dev accuracy.
2. **(Moustafa) Reproducibility.** Pin package versions in `train/requirements.txt`. Each run writes `train/runs/<run_id>.json` (base model, data commit SHA, hyperparameters, dev metrics, GPU type, training time). The notebook pulls data from the repo at a given commit, so every run is tied to a data version.
3. **(Moustafa) Export:** merge the LoRA adapter into the base model, convert with llama.cpp `convert_hf_to_gguf.py`, quantize to **Q4_K_M** (and Q8_0 for the 0.5B model if it fits the budget). Record the SHA-256 of each GGUF in `docs/MODELS.md`. Weights go to a private Hugging Face repo or Kaggle dataset; `scripts/fetch_models.sh` downloads them and checks the hash.
4. **(Moustafa) Experiments, all scored on dev:**
   - Fine-tuned vs B0 and B1.
   - With vs without the `ai_checked` rows (does AI-generated data help?).
   - With vs without the `rule_variant` rows (do spelling variants help on real typing?).
   - Q4_K_M vs the unquantized model (how much accuracy quantization costs).
5. **(Moustafa) Final test run.** Run the chosen model **once** on the frozen test set and on the local AladdinBench check. Report with 95% CIs against B0 and the best B1.
6. **(Moustafa) Poster pitch (≈ end of W5, assumed):** problem, the 8 GB local constraint, data method, baseline vs fine-tuned table, IME demo GIF from P1.

**Deliverables:** `train/` notebook + script, `train/runs/*.json`, GGUF on private storage with hashes in `docs/MODELS.md`, `scripts/fetch_models.sh`, results table, ADR 0005 (fine-tuning setup and chosen model).

**Gate:**
- [ ] The fine-tuned model beats B0 **and** the best B1 on test word accuracy, with the 95% CI of the difference above 0.
- [ ] Number preservation ≥ 99% and Keep-Latin F1 reported; hallucination rate reported.
- [ ] The quantized model meets the Section 0 budgets on the 8 GB Air.
- [ ] Re-running training in a fresh Kaggle/Colab session at the same data SHA gives dev accuracy within 2 points.
- **If the gate fails:** see Section 7, C2.

**Rubric mapping:** Agent performance/evaluation 20% (model improvement with evidence); real-world constraint (on-device size and latency); reproducibility.

---

### P5 — Local engine, rule fallback, CI (W4–W6)

**What this stage does (simple):** Put the model behind a small Swift engine that the keyboard can call. The engine runs in its own sandboxed process with **no network permission**, so even a bug cannot send text anywhere. It also protects things the model must not touch (numbers, links, emoji) and falls back to the rules if the model is slow or produces something suspicious.

**Repo structure** (core logic in Swift packages; the IME stays thin):
```
arabizi-keyboard/
├─ Packages/
│  ├─ ArabiziContracts/   # Codable request/response types, versioned (v1)
│  ├─ ArabiziCore/        # protected spans, rule fallback (reads data/rules/*.json), output checks
│  └─ ArabiziLLM/         # llama.cpp wrapper: load GGUF, generate with timeout
├─ Apps/
│  ├─ ArabiziIME/         # thin IMK layer (from P1)
│  └─ ArabiziEngineXPC/   # XPC service hosting Core + LLM; sandboxed, NO network entitlement
├─ Tools/arabizi-cli/     # same engine over JSON lines, used by eval/ and CI
├─ eval/  train/  data/  config/  scripts/  docs/  .github/
```

**Steps:**
1. **(Moustafa) Contracts** in `Packages/ArabiziContracts`, mirrored as JSON Schemas in `docs/schemas/`:
   ```swift
   public struct ConvertRequest: Codable { public let v: Int; public let id: UUID; public let text: String; public let deadlineMs: Int }
   public struct ConvertResponse: Codable { public let v: Int; public let id: UUID; public let text: String;
                                            public let outcome: Outcome; public let latencyMs: Int }
   public enum Outcome: String, Codable { case model, fallbackTimeout, fallbackCheckFailed, fallbackModelUnavailable, passthrough }
   ```
   Built, with the output checks (step 3) and `config/engine.json` (step 8): [API_CONTRACTS.md](API_CONTRACTS.md), [ADR 0018](decisions/0018-engine-contracts-checks-config.md).
2. **(Moustafa) Protected spans** in `ArabiziCore` [Claude's recommendation]: before calling the model, replace URLs, emails, `@mentions`, emoji and **standalone numbers** with placeholders (`⟦0⟧`, `⟦1⟧` …) and put them back afterwards. A digit inside a word (`3am`, `7elo`) is **not** protected; it is a letter.
   Built with the rule fallback (a Swift port of B0 with a parity test against Python): `ArabiziCore/ProtectedSpans.swift` and `RuleConverter.swift`, decisions in [ADR 0016](decisions/0016-swift-rule-fallback.md).
3. **(Moustafa) Output checks:** every placeholder comes back exactly once; output length is within 0.5–2× the input word count; no Latin text appears that was not in the input. If any check fails, use the rule fallback and set `outcome = fallbackCheckFailed`.
   Built as `ArabiziCore/OutputChecks.swift`, with one word of slack on the length check so short messages can join words (ADR 0018 #3).
4. **(Moustafa) `ArabiziLLM`:** llama.cpp XCFramework as a Swift Package `binaryTarget`; load the GGUF once and keep it warm; greedy decoding; stop at end of turn; hard deadline from config (default 1,500 ms) → rule fallback with `outcome = fallbackTimeout`.
   Checked 15 Oct 2026 ([ADR 0017](decisions/0017-llama-cpp-from-swift.md)): the XCFramework of release b11429 matches the export commit; prompts are pre-rendered because the framework has no Jinja templates; a Swift prototype ran Llama 3.2 1B and Qwen3-1.7B within the memory budget.
5. **(Moustafa) `ArabiziEngineXPC`:** sandboxed XPC service with **no** `com.apple.security.network.client` entitlement. The IME talks to it over a small XPC protocol (`convert`, `status`). If the service crashes, the IME restarts it and uses the rules meanwhile.
6. **(Moustafa) `arabizi-cli`:** reads `ConvertRequest` JSON lines on stdin, writes `ConvertResponse` lines. `eval/run.py` uses it, so the eval measures the **real Swift engine**, not only Python.
   Built with the engine (`Packages/ArabiziEngine`, [ADR 0019](decisions/0019-engine-and-cli.md)); evalrun's `engine-<id>` systems drive it. Dev: 0.770 vs the Python model's 0.768.
7. **(Moustafa) CI** `.github/workflows/ci.yml` (see v1 S4 step 3 for the full YAML): `lint` (SwiftLint, ruff), `build-test` (`swift test` for the packages, `xcodebuild` build for the apps with `CODE_SIGNING_ALLOWED=NO`), `eval-smoke` (`pytest eval/tests` + the test-set freeze check + a 20-sentence regression run with the rule fallback only, since CI has no model), `secrets` (gitleaks). Add CodeQL and Dependabot as in v1 S4 steps 4–5. Then require these checks on `main` with `bootstrap.py protect --checks lint,build-test,eval-smoke`.
8. **(Moustafa) Config** `config/engine.json` (typed `EngineConfig: Codable`, validated at startup): model path and SHA-256, deadline, max input length, feature flags. No magic numbers in code.
   Built: the model is named by its id in `config/models.json` (file, SHA-256, prompt come from there); `use_model` stays false until ADR 0005 (ADR 0018 #5).

**Deliverables:** packages + XPC service + CLI compiling, `docs/API_CONTRACTS.md`, schemas, CI green and required, CodeQL first scan, Dependabot.

**Gate:**
- [ ] `arabizi-cli` reproduces the P4 test accuracy within 1 point (Swift engine = Python numbers).
- [ ] Unit tests: placeholders survive round trips (URLs, emoji, `100$`, `2pm`); `3am` is not protected; a forced timeout and a forced bad output both return the rule fallback.
- [ ] The XPC service has no network entitlement (`codesign -d --entitlements -` output saved in the PR), and a test request to the network from inside it fails.
- [ ] CI is required on `main`; a PR with a failing test cannot merge (prove it once).

**Rubric mapping:** Software engineering 10% (modular, contracts, config); Reliability & security 15% (sandbox, fallback); Bonus (CI/CD, CodeQL, Dependabot).

---

### P6 — Keyboard integration (W6–W8)

**What this stage does (simple):** Connect the P1 keyboard to the P5 engine so that typing feels natural: you see what you type, Enter converts it, a second Enter sends, and you can always undo or escape.

**Steps:**
1. **(Moustafa) Enter-to-convert flow:**
   - While typing: Latin marked text, as in P1.
   - **Enter (buffer not empty):** send the buffer to the engine. While waiting, show a subtle "…" after the marked text. Commit the converted text when it arrives; the message is **not** sent.
   - **Enter (buffer empty):** pass through, so the app sends.
   - **Esc:** commit the Latin text unchanged.
   - Keys typed while a conversion is running are queued, not lost.
2. **(Moustafa) Undo the conversion:** right after a commit, **Cmd+Z** in the app should undo it (check per app in the P1 matrix); in addition, a configurable shortcut (default **Option+Backspace**) replaces the last converted text with the original Latin if the cursor has not moved [Claude's recommendation].
3. **(Moustafa) Per-app profiles** `config/app_profiles.json`: from the P1 matrix, apps that need a workaround (e.g. commit at space, or a maximum marked-text length).
4. **(Moustafa) Menu-bar settings:** turn conversion on/off, show engine status (model loaded / rules only), a "Convert punctuation" toggle, and a link to the privacy note ("nothing leaves this Mac").
5. **(Moustafa) Warm start:** the XPC service loads the model at login (or on first keypress) so the first Enter is not slow; measure cold and warm latency.
6. **(Moustafa) Dogfooding:** use the keyboard for your own real chats for at least 5 days. Every wrong conversion you are happy to share is rewritten as a new **dev** sentence (never test), and every bug becomes an issue with a failing test first.

**Deliverables:** working IME + engine, `config/app_profiles.json`, updated `docs/spikes/ime_app_matrix.md`, demo recording, dogfooding log (counts only, no private text).

**Gate:**
- [ ] The P1 matrix re-run with the real engine: at least 5 of 7 apps pass, and WhatsApp desktop and Slack both pass.
- [ ] Latency on the 8 GB Air, warm, ≤ 15 words: p95 ≤ 1.2 s, measured in the real IME (not only the CLI).
- [ ] Killing the XPC service mid-conversion still commits text (rules), and the next Enter uses the model again.
- [ ] Password fields: still pass-through.
- [ ] No text from the user appears in any log (grep the unified log during a 5-minute session).

**Rubric mapping:** Reliability & security 15%; user-facing quality; real-world deployment constraint.

---

### P7 — Final evaluation, hardening, docs, demo (W9–W10)

**Steps:**
1. **(Moustafa) Final evaluation report** `docs/EVAL.md`: B0 vs B1 vs fine-tuned on the frozen test set (with CIs), the data ablations from P4, latency/RSS on the 8 GB Air, per-app results, error analysis of 50 wrong outputs grouped by cause (MSA rewrite, English word converted, rare word, ambiguous word like `la`).
2. **(Moustafa) Failure matrix** `docs/FAILURE_MATRIX.md`: model missing, model corrupt (hash mismatch), timeout, XPC crash, very long input, secure input, unsupported app. For each: what the user sees, which test covers it.
3. **(Moustafa) Threat model** `docs/THREAT_MODEL.md` (short): what data exists, where it goes (nowhere), the sandbox, model file integrity, logging rules.
4. **(Moustafa) Reproducibility drill:** on a fresh Mac user account, follow only `README.md` + `docs/SETUP_IME.md` to install, fetch the model, run `eval` and get the reported numbers, writing down every step that was missing.
5. **(Moustafa) Report, poster update and demo** rehearsed three times, with a recorded backup video.

**Deliverables:** `docs/EVAL.md`, `docs/FAILURE_MATRIX.md`, `docs/THREAT_MODEL.md`, report, demo video, tagged release `v1.0`.

**Gate (final):**
- [ ] Every P1–P6 gate is ticked with linked evidence.
- [ ] The reproducibility drill passes using only the docs.
- [ ] Every failure-matrix row has a passing test.

**Rubric mapping:** all categories; Documentation 10%.

---

## 4. Cross-cutting rules

- **Privacy:** inference is local; the engine has no network entitlement; user text is never logged (log lengths, latencies and outcomes only).
- **Data:** every row has provenance (`method`, `writer`, `checked_by`, `source`). Dev and test are human-written. AI rows: train only, checked, provider terms recorded. Never Yamli, never MADAR in git or in training. Never commit weights.
- **Evaluation discipline:** tune on dev, report on test, once per final candidate. Every model or prompt change in a PR comes with a before/after dev table.
- **AI coding tools:** allowed; PRs say "AI-assisted: yes/no" (see CONTRIBUTING.md).

## 5. Timeline variants

- **Poster earlier than W5:** present P1 + P3 (IME demo + baselines) and the first fine-tuning run on dev; the test result comes later.
- **What to cut first when behind (solo)** [Claude's recommendation], in this order: (1) CodeQL and Dependabot in P5; (2) per-app profiles and menu settings in P6, keeping Enter-to-convert in WhatsApp, Slack and Safari only; (3) the Q8_0 and rule-variant ablations in P4; (4) the XPC service: run the engine inside the IME process, which is also sandboxed with no network entitlement, and say so in the threat model.

## 6. Phase 2 (after Phase 1 passes): agentic features

Only if the team decides to continue after P7, or earlier if P4–P6 finish ahead of time. Candidates, from the [v1 roadmap](archive/ROADMAP_v1_agentic.md):

- **Sentence resolver agent (v1 S7/S9):** when the model is unsure about a word (low token probability), show a small chooser instead of guessing.
- **Memory curator agent (v1 S10):** learn a user's own spellings and corrections locally, encrypted, and only keep a habit after replaying it against past corrections.
- **Observability (v1 S9):** local traces, shipped to Jaeger by a developer-only script.

Starting Phase 2 needs a new ADR and a revised roadmap section.

## 7. Risks and contingencies

| # | Risk | Detected at | Plan |
|---|---|---|---|
| C1 | IME fails in key apps | P1 gate | Per-app workaround (commit at space, shorter buffers); if WhatsApp desktop fails, demo in Slack + Safari and document it. |
| C2 | Fine-tuning does not beat the baselines | P4 gate | Check data quality first (error analysis on dev); add more hand-written pairs; try the other base model; try a larger LoRA rank. If still no gain, ship the best B1 + rule fallback and report the negative result honestly. |
| C3 | Too slow on the 8 GB Air | P3/P6 | Use the 0.5B model; shorter prompt (no system text after fine-tuning); convert per clause (split at `,` `.` `?`) in parallel with typing. |
| C4 | Not enough training data by W4 | P2 gate | Pause other work and write pairs for two days; raise rule variants per pair; use ATAR if its licence is confirmed. |
| C5 | Free GPU quota runs out | P4 | Kaggle and Colab alternate; the 0.5B model can be fine-tuned on the 8 GB Air with MLX LoRA as a last resort (slow, small batch). |
| C6 | AI provider terms forbid training on outputs | P2 step 7 | Skip AI rows; rely on hand-written + rule variants + public data (option A). |
| C7 | The model rewrites Lebanese into MSA | P3/P4 | More hand-written pairs with Lebanese-only words; MSA-rewrite rate is a tracked metric and goes in the error analysis. |

## 8. Final submission checklist

- [ ] Repo: README with install steps, licence, `docs/` complete, CI green, tagged `v1.0`.
- [ ] Model: GGUF hash in `docs/MODELS.md`, `scripts/fetch_models.sh` works, licences listed.
- [ ] Data: `docs/DATA.md` datasheet, frozen test set + manifest, provenance on every row.
- [ ] Evaluation: `docs/EVAL.md` with CIs, ablations, latency/RSS on the 8 GB Air.
- [ ] Demo: live demo in WhatsApp/Slack + backup video.
