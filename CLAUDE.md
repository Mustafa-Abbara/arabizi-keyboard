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

## Current state (update when it changes)

- **Phase 1 (ADR 0010), solo build (ADR 0011).** Stages P0–P7; v1 roadmap archived. Board: GitHub Project #1; Moustafa (`Mustafa-Abbara`) owns every issue. `protect-main` ruleset: PR required, approvals set to 0 (restore with `bootstrap.py protect`).
- **P0** mostly done: Kaggle account `MustafaAbbara2003` (phone-verified, 14 Oct 2026); left: push-protection test, learning ramp. **CI** (`.github/workflows/ci.yml`: python, swift, hygiene) runs on every PR. **P1** keyboard spike works (Enter converts, ⌘Z restores, ⌥Enter converts a selection, password fields safe; per-app matrix not filled app by app).
- **P2 data:** SPELLING.md v1.2; `pairs` CLI (add, import, import-batch, import-chats, variants, lexicon, check, stats, validate). Training: 2,000 Claude-drafted rows revised by Moustafa (ADR 0012) + 1,687 private own-chat rows (ADR 0014) + generated variants (not committed). Held-out: **349 hand-written** (50 public from the sheet, 300 private from own chats).
- **Private data (ADR 0014):** `data/private/` and `eval/results/private/` are never committed; the public B0 dictionary is built from public rows only; quote only aggregate numbers from private runs.
- **P3 done except the gate review:** scoring harness (`evalrun`, docs/EVAL.md); B0 rules = 0.547 on 105 dev rows; B1 base models (all six pinned models downloaded and verified) best 0.169 (Llama 3.2 1B 5-shot). **ADR 0004:** fine-tune Llama 3.2 1B and Qwen3-1.7B in P4 (fallback Qwen3-0.6B); final pick after P4 (ADR 0005). Downloads: Moustafa runs `scripts/fetch_models.py` in his own terminal (Claude's sandbox cannot reach Hugging Face). Next: **P4 fine-tuning on Kaggle** (private dataset for the own-chat rows).
- **P4 tooling (ADR 0015, docs/TRAINING.md):** `pairs export-train` → private Kaggle dataset → `train/finetune_lora.ipynb` (LoRA, then GGUF via `train/export_gguf.sh`) → GGUF back to `models/`, `run.json` to `train/runs/`. Order: Moustafa's `pairs check`, `pairs freeze`, then Kaggle.
