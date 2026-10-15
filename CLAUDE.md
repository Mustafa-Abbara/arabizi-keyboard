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

## Current state (update when it changes; last update 15 Oct 2026)

**Project:** Phase 1 (ADR 0010). Moustafa is the main contributor and owns every stage and issue; Mohamad contributes by PR on tasks agreed first (ADR 0011 + amendment). Board: GitHub Project #1. `protect-main` ruleset: PR required, approvals 0 (restore with `bootstrap.py protect`). CI on every PR: python, swift, hygiene, testset guard.

| Stage | Status |
|---|---|
| P0 | Done except the push-protection test and the learning ramp. Kaggle account `MustafaAbbara2003` (phone-verified). |
| P1 | Keyboard spike works (Enter converts, ⌘Z restores, ⌥Enter converts a selection, password fields safe). Gate open: `docs/spikes/ime_app_matrix.md` not filled app by app. |
| P2 | SPELLING.md v1.2. Held-out: **350 hand-written** (public 35 test + 15 dev; private 210 test + 90 dev from Moustafa's chats, ADR 0014). Training: 2,000 Claude-drafted rows revised by Moustafa (ADR 0012) + 1,687 private chat rows + generated variants. **Not frozen yet.** |
| P3 | Harness `evalrun` (docs/EVAL.md). B0 rules **0.547** on 105 dev rows; B1 best **0.169** (Llama 3.2 1B, 5-shot). ADR 0004: fine-tune Llama 3.2 1B + Qwen3-1.7B (fallback Qwen3-0.6B). Gate open: re-run one baseline from a fresh clone. |
| P4 | Pipeline merged (ADR 0015, docs/TRAINING.md): `pairs export-train` → private Kaggle dataset → `train/finetune_lora.ipynb` → GGUF back to `models/`. **Training not run yet.** |
| P5 | Started (ADR 0016): Swift rule fallback `RuleConverter` (B0 port, exact parity with Python via `b0_parity.json`) and `ProtectedSpans`; the keyboard now uses the rule converter. Next: output checks, llama.cpp from Swift, XPC, CLI, config. |
| P6–P7 | Not started. |

**Next steps, in order:**
1. **Moustafa, 15 Oct:** `uv run --project eval pairs check` (delayed self-check; the 50 sheet pairs become eligible on 15 Oct, the 300 private ones on 16 Oct).
2. **Moustafa:** `uv run --project eval pairs freeze` (or `--allow-unchecked`; the count is recorded). Then Claude commits `data/pairs/manifest.json` in a PR with the **testset-change** label; after merge, tag `testset-v1.0`.
3. **Optional before the freeze:** Kaggle smoke run with `pairs export-train --public-only` and `--limit 200 --epochs 1` (TRAINING.md), to catch setup problems.
4. **Moustafa, after the freeze:** `pairs variants`, `pairs export-train` (with private rows), upload `build/train-export/` as a **private** Kaggle dataset, run the notebook (GPU T4, Internet on), download the two `.gguf` (→ `models/`) and `run.json` (→ `train/runs/`).
5. **Claude, then:** verify hashes, add the fine-tuned models to `config/models.json`, score on dev against B0/B1 (paired bootstrap), write ADR 0005 (final model).
6. **Claude, can start any time (no fine-tuned model needed):** rest of P5: output checks (step 3), check how to call llama.cpp from Swift in 2026 (its release packaging changed; ADR 0003), then `ArabiziLLM`. The Swift rule fallback and protected spans are done (ADR 0016).

**Practical notes:**
- Claude's sandbox cannot reach Hugging Face or Kaggle: Moustafa runs downloads (`scripts/fetch_models.py`) and Kaggle himself. Models are in `models/` (all six B1 models downloaded and verified).
- Private data (ADR 0014): `data/private/` and `eval/results/private/` are never committed; the public B0 dictionary is built from public rows only; quote only aggregate numbers from private runs; never print private message text.
- Rules or dictionary changes: regenerate the Swift parity fixture (`uv run --project eval python -m arabizi_eval.parity`; `pairs lexicon` does it) in the same PR.
- `pairs` CLI: add, import, import-batch, import-chats, variants, lexicon, export-train, check, stats, freeze, validate. Variants (`pairs variants`) are generated, not committed.
- Before adding commits to a PR branch, check the PR is still open: Moustafa merges quickly.
