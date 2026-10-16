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
- Never scrape social media for data; training data sources and the Anthropic-terms reading are in ADR 0012 and docs/DATA.md.
- Inference stays local. Fine-tuning may run on Kaggle/Colab with team-written or licensed public data only.
- **Team (ADR 0011 + amendment):** Moustafa is the main contributor and owns every stage, issue, official measurement and download decision. Mohamad Al Masri (Windows) contributes code **by PR**, on tasks agreed with Moustafa first; his machine gives smoke runs only. PR review = self-review + `/code-review`, plus Moustafa's review of Mohamad's PRs when possible.
- Main dev machine: M2 MacBook Air, **8 GB RAM** (see the "8 GB consequences" section in ASSUMPTIONS.md). Keep memory use in mind.

## Current state (update when it changes; last update 16 Oct 2026)

**Project:** Phase 1 (ADR 0010). Moustafa is the main contributor and owns every stage and issue; Mohamad contributes by PR on tasks agreed first (ADR 0011 + amendment). Board: GitHub Project #1. `protect-main` ruleset: PR required, approvals 0 (restore with `bootstrap.py protect`). CI on every PR: python, swift, hygiene, testset guard.

| Stage | Status |
|---|---|
| P0 | Done except the push-protection test and the learning ramp. Kaggle account `MustafaAbbara2003` (phone-verified). |
| P1 | Keyboard spike works (Enter converts, ⌘Z restores, ⌥Enter converts a selection, password fields safe). Gate open: `docs/spikes/ime_app_matrix.md` not filled app by app. |
| P2 | SPELLING.md v1.2. **Frozen: `testset-v1.0`** (16 Oct): 347 held-out rows, public 113 test + 48 dev, private 130 test + 56 dev (111 chat rows published, ADR 0014 amendment); every row self-checked in a spreadsheet. Training: 2,000 Claude-drafted rows revised by Moustafa (ADR 0012) + 1,687 private chat rows + generated variants. |
| P3 | Harness `evalrun` (docs/EVAL.md). B0 rules **0.547** on 105 dev rows; B1 best **0.169** (Llama 3.2 1B, 5-shot). ADR 0004: fine-tune Llama 3.2 1B + Qwen3-1.7B (fallback Qwen3-0.6B). Gate open: re-run one baseline from a fresh clone. |
| P4 | **Trained** on Kaggle 16 Oct (ADR 0015): Llama 3.2 1B and Qwen3-1.7B. Fine-tuned Llama on dev: **0.768** (B0 0.543, best B1 0.166; +0.225 [0.18, 0.27] over B0), p50/p95 421/853 ms, 956 MB (docs/EVAL.md, `ft-<id>` systems). Qwen `.gguf` still to download. Next: score Qwen, ADR 0005, final test run. |
| P5 | Started (ADR 0016): Swift rule fallback `RuleConverter` (B0 port, exact parity with Python via `b0_parity.json`) and `ProtectedSpans`; the keyboard now uses the rule converter. `ArabiziLLM` (ADR 0017): llama.cpp XCFramework b11429 (= export commit) as a SwiftPM binary target, `LlamaModel` with deadline. Contracts, output checks and `config/engine.json` (ADR 0018, docs/API_CONTRACTS.md). Next: XPC service, `arabizi-cli`. |
| P6–P7 | Not started. |

**Next steps, in order:**
1. **Moustafa:** get `arabizi-qwen3-1.7b-v1-Q4_K_M.gguf` into `models/` (re-download if the Kaggle session lives, else re-run only the Qwen cells; in a session, the notebook's own download-link cell or split parts). Llama's file is in `models/` and verified.
2. **Claude:** add Qwen to `config/models.json` (prompt from its `train/runs/` file), score it on dev like Llama, then ADR 0005 (final model: accuracy **and** latency on the Air), then the final test run, once (`--final`).
3. **Claude, then:** rest of P5: the XPC service (copies `llama.framework` and the model into the bundle, ADR 0017; no network entitlement) and `arabizi-cli` (both on the ADR 0018 contracts); P5 measures the engine with protected spans and output checks (raw model numbers: 93%, 6% hallucinations).

**Practical notes:**
- GitHub release downloads are slow and stall here; SwiftPM's own download of the llama.cpp XCFramework timed out. Fetch it with a resuming `curl` and place it in SwiftPM's cache (`~/Library/Caches/org.swift.swiftpm/artifacts/`, file name from `swift package resolve -vv`); SwiftPM still checks the checksum.
- Claude's sandbox cannot reach Hugging Face or Kaggle: Moustafa runs downloads (`scripts/fetch_models.py`) and Kaggle himself. Models are in `models/` (all six B1 models downloaded and verified).
- Private data (ADR 0014): `data/private/` and `eval/results/private/` are never committed; the public B0 dictionary is built from public rows only; quote only aggregate numbers from private runs; never print private message text.
- Rules or dictionary changes: regenerate the Swift parity fixture (`uv run --project eval python -m arabizi_eval.parity`; `pairs lexicon` does it) in the same PR.
- Kaggle notebook: runs `train/finetune_lora.py` from a fresh clone of `main` (merge fixes first); Kaggle has the newest transformers/TRL/peft. `/kaggle/working` is wiped when an interactive session ends: download outputs before leaving, or use Save & Run All.
- `pairs` CLI: add, import, import-batch, import-chats, variants, lexicon, export-train, check, stats, publish, freeze, validate. Variants (`pairs variants`) are generated, not committed.
- Before adding commits to a PR branch, check the PR is still open: Moustafa merges quickly.
- The app's terminal panel cannot display Arabic (unjoined, reversed): anything Moustafa must read in Arabic goes through a spreadsheet (`pairs check --sheet`, `pairs publish --sheet`), never the terminal.
