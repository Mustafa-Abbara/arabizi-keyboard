# Engine contracts and settings

The messages between the keyboard, the engine and `arabizi-cli`, and the engine's settings file (roadmap P5 steps 1, 3 and 8). Decisions in [ADR 0018](decisions/0018-engine-contracts-checks-config.md).

| What | Swift | JSON |
|---|---|---|
| Request | `ArabiziContracts.ConvertRequest` | [convert_request.v1.schema.json](schemas/convert_request.v1.schema.json), [example](schemas/examples/convert_request.json) |
| Response | `ArabiziContracts.ConvertResponse` | [convert_response.v1.schema.json](schemas/convert_response.v1.schema.json), [example](schemas/examples/convert_response.json) |
| Settings | `ArabiziCore.EngineConfig` | [config/engine.json](../config/engine.json) |

The Swift tests decode and re-encode the examples byte for byte; `eval/tests/test_contracts.py` checks them against the schemas. A change to a message changes all three in the same PR.

## Request (v1)

```json
{"deadlineMs":1500,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"kifak, shu 3am ta3mel? b3at 100$ 😂","v":1}
```

| Field | Meaning |
|---|---|
| `v` | Contract version, always 1. Any other version is rejected, never guessed at. |
| `id` | A UUID chosen by the caller; the response carries it back. |
| `text` | The Latin text as typed. The engine refuses more than `max_input_chars` (settings). |
| `deadlineMs` | How long the caller waits for the model (at least 1). After it, the rule fallback answers. |

## Response (v1)

```json
{"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","latencyMs":842,"outcome":"model","text":"كيفك، شو عم تعمل؟ بعت 100$ 😂","v":1}
```

| Field | Meaning |
|---|---|
| `v`, `id` | As in the request. |
| `text` | What to insert: Arabic script, with links, numbers and emoji exactly as typed. |
| `outcome` | Which path made `text` (below). |
| `latencyMs` | From receiving the request to answering it. |

| `outcome` | When |
|---|---|
| `model` | The model answered in time and the output checks passed. |
| `fallbackTimeout` | The model did not finish before the deadline: rule fallback. |
| `fallbackCheckFailed` | The model's answer failed an output check: rule fallback. |
| `fallbackModelUnavailable` | No model (switched off, missing file, wrong checksum, failed to load): rule fallback. |
| `passthrough` | Nothing to convert (no Latin letter): `text` is returned unchanged. |

`arabizi-cli` (P5 step 6) reads requests and writes responses as one JSON object per line, keys sorted (`Contract.encoder()`).

## Output checks (`ArabiziCore.OutputChecks`)

The model gets the text with protected spans replaced by `⟦0⟧`, `⟦1⟧`… (`ProtectedSpans`, ADR 0016). Its answer is used only if all of these hold; otherwise the rule fallback answers with `fallbackCheckFailed`:

1. It is not empty (after trimming whitespace).
2. Every placeholder comes back exactly once, and nothing that looks like one is invented.
3. Every word containing a Latin letter was a word of the input (case does not matter): English kept as typed (`el meeting` → `ال meeting`) passes; a made-up English word or a half-converted word (`تaعمل`) fails.
4. For an input of n words, the answer has between `min_word_ratio × n − word_slack` and `max_word_ratio × n + word_slack` words (0.5, 2.0 and 1 by default). The slack lets short messages join words: `w el bet` (3 words) is `والبيت` (1 word).

## Settings (`config/engine.json`)

| Key | Default | Meaning |
|---|---|---|
| `version` | 1 | File format version. |
| `model` | `null` | Id of the model in `config/models.json`; its `file`, `sha256` and `prompt` (prefix and suffix around the Arabizi, as rendered at training time, ADR 0017) come from there. Only fine-tuned entries have a `prompt`. Checked even while switched off. |
| `features.use_model` | `false` | Use the model. Off until ADR 0005 picks the fine-tuned model; until then every answer is the rule fallback. |
| `deadline_ms` | 1500 | Default deadline for the model (1–10000). |
| `max_input_chars` | 500 | Longest text the engine accepts (1–10000). |
| `max_output_tokens` | 128 | Longest answer the model may generate. |
| `context_length` | 512 | Model context (prompt plus answer); must exceed `max_output_tokens`. |
| `output_checks` | 0.5 / 2.0 / 1 | `min_word_ratio`, `max_word_ratio`, `word_slack` (above). |

A setting out of range stops the engine at start-up with a message naming it (`EngineConfig.InvalidError`).
