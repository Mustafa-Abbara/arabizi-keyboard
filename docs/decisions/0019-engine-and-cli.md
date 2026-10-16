# ADR 0019: The conversion engine and arabizi-cli (P5)

- **Status:** accepted
- **Date:** 2026-10-16
- **Deciders:** Moustafa Abbara (Claude's recommendation where marked)
- **Stage:** P5

## Context

The pieces exist: the rule fallback and protected spans (ADR 0016), the llama.cpp wrapper (ADR 0017), the contracts, output checks and settings (ADR 0018), and the chosen model with its saved prompt (ADR 0005). P5 steps 5–6 need one engine that the keyboard's sandboxed service and a command-line tool both run, so that the evaluation measures the real Swift engine. The P5 gate asks `arabizi-cli` to reproduce the P4 accuracy within 1 point.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | `Packages/ArabiziEngine`: one `Engine` class. Order: no Latin letter → `passthrough`; no model or input over `max_input_chars` → rules (`fallbackModelUnavailable`); else ProtectedSpans → saved prompt → model with the request's deadline → `clean` (as the eval harness: `<think>` removed, first line, no wrapping quotes) → OutputChecks → spans restored (`model`). Deadline → rules (`fallbackTimeout`); token limit or failed check → rules (`fallbackCheckFailed`); a generation error → rules (`fallbackModelUnavailable`). Never an error, never logs text. | Roadmap P5; outcome mapping **Claude's recommendation** |
| 2 | Token limit per request: `min(10 × words + 32, max_output_tokens)`, the eval harness's formula capped by the setting. | **Claude's recommendation** |
| 3 | At load, the model file's SHA-256 is checked against `config/models.json`; a missing file, a wrong hash or a load failure leaves the engine on the rules with the reason in `modelState` (counts and file names only). Cold, the check reads 0.8 GB (about 14 s); warm about 1 s; the service must therefore not block typing while it loads (P5 step 5). | **Claude's recommendation** |
| 4 | The model is reached through a small `TextGenerator` protocol (ArabiziLLM), so every path is unit-tested with a scripted stand-in; one test runs the real fine-tuned model through the whole engine when `models/` has it. | **Claude's recommendation** |
| 5 | `arabizi-cli` is an executable target of the engine package (not a separate `Tools/` folder): ConvertRequest JSON lines in, ConvertResponse lines out; status as one JSON line on stderr; `--model ID` / `--no-model` override the settings for evaluation; `--explain` writes why each fallback happened (counts only). Invalid lines are reported by line number, never echoed. | Roadmap P5 step 6; layout and flags **Claude's recommendation** |
| 6 | The harness drives it as `engine-<id>` / `engine-rules` (`eval/src/arabizi_eval/engine.py`), with a 10 s deadline for accuracy runs (a busy Mac should not turn answers into fallbacks); latencies are recorded as the engine reports them. | **Claude's recommendation** |

## Consequences

- **Dev (104 rows), 16 Oct 2026:** `engine-arabizi-llama3.2-1b-v1` 0.770 [0.74, 0.81], numbers 100%, p50/p95 509/853 ms; Python raw model 0.768, Python with numbers protected 0.774: within 1 point (the P5 gate figure, on dev; the gate's test check uses the P4 test result, 0.783). 98 answers from the model, 6 fallbacks, all "new Latin word" (the model invented a mixed word such as `زوajan`); on those 6 sentences the rules got 19 of 38 words against the model's 21, the price of never showing an invented mixed word.
- No placeholder broke on dev, but one hand-made sentence with a number **and** an emoji lost a placeholder (the model never saw placeholders in training). Watch the `placeholders` count in `--explain`; if it grows, protect fewer kinds (numbers and links only).
- The XPC service (P5 step 5) hosts this same `Engine`; the keyboard switches to it when `config/engine.json` names the model (ADR 0005 #3).
