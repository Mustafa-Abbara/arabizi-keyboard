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

## Current state (update when it changes; last update 17 Oct 2026)

**Project:** Phase 1 (ADR 0010). Moustafa is the main contributor and owns every stage and issue; Mohamad contributes by PR on tasks agreed first (ADR 0011 + amendment). Board: GitHub Project #1. `protect-main` ruleset: PR required, approvals 0 (restore with `bootstrap.py protect`). CI on every PR: python, swift, hygiene, testset guard.

| Stage | Status |
|---|---|
| P0 | Done except the push-protection test and the learning ramp. Kaggle account `MustafaAbbara2003` (phone-verified). |
| P1 | Keyboard spike works (Enter converts, ⌘Z restores, ⌥Enter converts a selection, password fields safe). Gate open: `docs/spikes/ime_app_matrix.md` not filled app by app. |
| P2 | SPELLING.md v1.2. **Frozen: `testset-v1.0`** (16 Oct): 347 held-out rows, public 113 test + 48 dev, private 130 test + 56 dev (111 chat rows published, ADR 0014 amendment); every row self-checked in a spreadsheet. Training: 2,000 Claude-drafted rows revised by Moustafa (ADR 0012) + 1,687 private chat rows + generated variants. |
| P3 | Harness `evalrun` (docs/EVAL.md). B0 rules **0.547** on 105 dev rows; B1 best **0.169** (Llama 3.2 1B, 5-shot). ADR 0004: fine-tune Llama 3.2 1B + Qwen3-1.7B (fallback Qwen3-0.6B). Gate open: re-run one baseline from a fresh clone. |
| P4 | Trained 16 Oct (ADR 0015); **ADR 0005: ship the Llama 3.2 1B fine-tune.** **Frozen test (once): 0.783** vs B0 0.594 (+0.189 [0.16, 0.22]) and best B1 0.147; numbers 24/24; p50/p95 487/1,013 ms, 830 MB (numbers protected, `-protect`). **Gate passed 4/4** (17 Oct: the sweep's `base` rerun gave a bit-identical model). Sweep (TRAINING.md): rank32 0.784 dev (+0.009, within noise), lr1e-4 worse, ep2 no better; shipped model stays. |
| P5 | Rule fallback + protected spans (ADR 0016), `ArabiziLLM` (ADR 0017), contracts/checks/config (ADR 0018), engine + `arabizi-cli` (ADR 0019; dev 0.770), **sandboxed XPC service in the app, keyboard uses it, fine-tuned model switched on** (ADR 0020; network denied by the kernel sandbox; `arabizi-engine-check`). Gate open: engine accuracy on test; CI required on main. |
| P6–P7 | Not started. |

**Next steps, in order:**
0. **Accuracy plan, next:** clean and check the 2,000 real rows (local xlsx; Moustafa checks them in a sheet), import them as private data (ADR first), hold out 200 as an "other people" set (shipped model 0.684 on a 400-row sample), retrain on Kaggle with rank 32, compare on dev and the 200.
1. **Moustafa:** `scripts/install_ime.sh` (with the model in `models/`), switch to the keyboard, and type: Enter now uses the fine-tuned model (rules for the first ~30 s while it loads). Then fill the P1 app matrix (`docs/spikes/ime_app_matrix.md`), still the biggest unverified risk.
2. **Open P5 gate items:** one engine run on test (`evalrun run --system engine-arabizi-llama3.2-1b-v1 --split test --final`, needs Moustafa's OK: within 1 point of 0.783); CI required on `main` (`bootstrap.py protect --checks …`, prove a failing PR cannot merge).
3. **Then P6:** asynchronous Enter with a "…" while converting, per-app profiles, menu-bar settings, warm start, 2 weeks of dogfooding.
4. **Optional:** P4 ablations (no AI rows, no variants), AladdinBench check, accuracy work (ceiling measurement, training tweaks, more real data).

**Practical notes:**
- GitHub release downloads are slow and stall here; SwiftPM's own download of the llama.cpp XCFramework timed out. Fetch it with a resuming `curl` and place it in SwiftPM's cache (`~/Library/Caches/org.swift.swiftpm/artifacts/`, file name from `swift package resolve -vv`); SwiftPM still checks the checksum.
- Claude's sandbox cannot reach Hugging Face or Kaggle: Moustafa runs downloads (`scripts/fetch_models.py`) and Kaggle himself. Models are in `models/` (all six B1 models downloaded and verified).
- Private data (ADR 0014): `data/private/` and `eval/results/private/` are never committed; the public B0 dictionary is built from public rows only; quote only aggregate numbers from private runs; never print private message text.
- Rules or dictionary changes: regenerate the Swift parity fixture (`uv run --project eval python -m arabizi_eval.parity`; `pairs lexicon` does it) in the same PR.
- Kaggle notebook: runs `train/finetune_lora.py` from a fresh clone of `main` (merge fixes first); Kaggle has the newest transformers/TRL/peft. `/kaggle/working` is wiped when an interactive session ends: download outputs before leaving, or use Save & Run All.
- `pairs` CLI: add, import, import-batch, import-chats, variants, lexicon, export-train, check, stats, publish, freeze, validate. Variants (`pairs variants`) are generated, not committed.
- Before adding commits to a PR branch, check the PR is still open: Moustafa merges quickly.
- The app's terminal panel cannot display Arabic (unjoined, reversed): anything Moustafa must read in Arabic goes through a spreadsheet (`pairs check --sheet`, `pairs publish --sheet`), never the terminal.
