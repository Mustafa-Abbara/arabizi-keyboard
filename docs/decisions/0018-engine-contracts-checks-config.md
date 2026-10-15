# ADR 0018: Engine contracts, output checks and settings (P5)

- **Status:** accepted
- **Date:** 2026-10-15
- **Deciders:** Moustafa Abbara (Claude's recommendation where marked)
- **Stage:** P5

## Context

The roadmap fixes the shape of P5 steps 1, 3 and 8: versioned request and response types mirrored as JSON Schemas; output checks (placeholders, 0.5–2× word count, no new Latin text) that send a bad answer to the rule fallback; a typed `config/engine.json` checked at start-up with no magic numbers in code. The details below were not fixed. Everything is documented in [API_CONTRACTS.md](../API_CONTRACTS.md).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | `Packages/ArabiziContracts` holds `ConvertRequest`, `ConvertResponse` and `Outcome` exactly as in the roadmap, with the roadmap's camelCase JSON keys. Decoding rejects any `v` other than 1, a `deadlineMs` below 1 and a negative `latencyMs`. JSON Schemas (draft 2020-12) and one example per message are in `docs/schemas/`; Swift re-encodes the examples byte for byte (sorted keys) and pytest validates them against the schemas, so the three cannot drift. | Roadmap; checks and examples **Claude's recommendation** |
| 2 | `passthrough` means "nothing to convert" (no Latin letter in the text). | **Claude's recommendation** (the roadmap names it without defining it) |
| 3 | **Word-count check with a slack:** the answer may have `0.5 × n − 1` to `2 × n + 1` words for n input words. On the 2,015 public train/dev pairs and 4,689 private rows (counts only, ADR 0014), the roadmap's strict 0.5–2× rejects no correct answer, but none of those rows has three words or fewer; a keyboard message like `w el bet` → `والبيت` (3 → 1) would fail. One word of slack keeps such messages and still rejects no correct answer in the data. | Roadmap ratio; slack **Claude's recommendation** |
| 4 | **New-Latin check by word:** a word of the answer that contains a Latin letter must be (case-insensitively, without surrounding punctuation) a word of the masked input. This allows English the user typed and catches made-up words and half-converted ones (`تaعمل`). Links and emails are placeholders at that point, so they never count. | Roadmap rule; word-level reading **Claude's recommendation** |
| 5 | `config/engine.json` names the model by its id in `config/models.json` instead of repeating its path and SHA-256; fine-tuned entries there get a `prompt` (prefix, suffix) as ADR 0017 #3 requires. `features.use_model` is false and `model` null until ADR 0005, so the engine serves the rule fallback only. A model id is checked even while switched off. Ranges: deadline and input length 1–10000, `context_length > max_output_tokens`, `0 < min_word_ratio < 1 < max_word_ratio`, slack ≥ 0. | Roadmap fields; id reference, flag and ranges **Claude's recommendation** |
| 6 | `EngineConfig` and `OutputChecks` live in `ArabiziCore` (no llama.cpp dependency), so the rule-only engine and `arabizi-cli` can use them without loading the model. | **Claude's recommendation** |

## Consequences

- P4's step "add the fine-tuned models to `config/models.json`" now includes their `prompt`, taken from training (`train/finetune_lora.py` renders it); switching the model on is one line in `config/engine.json` plus `use_model: true`.
- The XPC service (P5 step 5) and `arabizi-cli` (step 6) build on these types: request in, `ProtectedSpans` → model with deadline → `OutputChecks` → response with the outcome, or `RuleConverter` on any failure.
- The word-count slack and the new-Latin rule are measured again on dev once the fine-tuned model exists: how often each check fires on the model's real answers goes into the P5 gate notes.
