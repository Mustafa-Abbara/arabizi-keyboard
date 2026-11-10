# Engine contracts and settings

The messages between the keyboard, the engine and `arabizi-cli`, and the engine's settings file (roadmap P5 steps 1, 3 and 8). Decisions in [ADR 0018](decisions/0018-engine-contracts-checks-config.md).

| What | Swift | JSON |
|---|---|---|
| Request | `ArabiziContracts.ConvertRequest` | [convert_request.v1.schema.json](schemas/convert_request.v1.schema.json), [example](schemas/examples/convert_request.json) |
| Response | `ArabiziContracts.ConvertResponse` | [convert_response.v1.schema.json](schemas/convert_response.v1.schema.json), [example](schemas/examples/convert_response.json) |
| Word guesses (↑ list, ADR 0036) | `ArabiziContracts.WordGuessRequest`, `WordGuessResponse` | [word_guess_request.v1.schema.json](schemas/word_guess_request.v1.schema.json), [word_guess_response.v1.schema.json](schemas/word_guess_response.v1.schema.json), [examples](schemas/examples/) |
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
| `text` | What to insert: Arabic script, with links, numbers and emoji exactly as typed (links and numbers through placeholders, emoji checked; ADR 0025). |
| `outcome` | Which path made `text` (below). |
| `latencyMs` | From receiving the request to answering it. |
| `wordConfidence` | Optional, for a `model` answer: how sure the model was of each word of `text` (split at spaces), 0 to 1 (the lowest token probability in the word). Absent when unknown, or when the answer's words no longer line up with the model's. The keyboard's ↑ starts on the least sure word. |

| `outcome` | When |
|---|---|
| `model` | The model answered in time and the output checks passed. |
| `fallbackTimeout` | The model did not finish before the deadline: rule fallback. |
| `fallbackCheckFailed` | The model's answer failed an output check: rule fallback. |
| `fallbackModelUnavailable` | No model (switched off, missing file, wrong checksum, failed to load): rule fallback. |
| `passthrough` | Nothing to convert: `text` has no Latin letter, or is plain English (ADR 0031); it is returned unchanged. |

`arabizi-cli` (P5 step 6, `Packages/ArabiziEngine`) reads requests and writes responses as one JSON object per line, keys sorted (`Contract.encoder()`); its status goes to stderr as one JSON line, and `--explain` adds why each fallback happened (counts only). In the engine ([ADR 0019](decisions/0019-engine-and-cli.md)), `fallbackModelUnavailable` also covers input longer than `max_input_chars` and a generation error, and `fallbackCheckFailed` also covers an answer that hit the token limit.

```bash
swift build -c release --package-path Packages/ArabiziEngine
echo '{"v":1,"id":"0D7A4C3E-2B1F-4E8A-9C6D-5F3B2A1E0D9C","text":"kifak?","deadlineMs":1500}' | Packages/ArabiziEngine/.build/release/arabizi-cli --model arabizi-llama3.2-1b-v1
```

## Word guesses (v1, ADR 0036)

The model's other spellings for one word of its answer: the ↑ list's first source. The request goes on the same Windows pipe or Mac service as conversions; `"kind": "wordGuesses"` tells it apart (`WordGuessRequest.isWordGuessRequest`). `arabizi-cli` answers both kinds, line by line.

```json
{"before":"شو","count":5,"deadlineMs":400,"id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","kind":"wordGuesses","text":"shu 3am ta3mel","v":1}
{"guesses":[{"logProbability":-0.125,"word":"عم"},{"logProbability":-2.5,"word":"عام"}],"id":"5B1E9C2A-7D3F-4A6B-8E1C-9F2D4A7B3C6E","latencyMs":180,"outcome":"model","v":1}
```

| Field | Meaning |
|---|---|
| `kind` | Always `wordGuesses`. |
| `text` | The message as typed, as it was converted. |
| `before` | The model's answer up to the word being fixed; empty for the first word. Spans the conversion masked (links, numbers) are masked here too. |
| `count` | Guesses wanted, 1–10 (the keyboard asks for 5). |
| `deadlineMs` | How long the caller waits; past it the answer has no guesses. |
| `guesses` | Whole Arabic words (no diacritics), best first, with the model's log-probability of writing each there. |
| `outcome` | `model` (it answered; the list may be empty), `fallbackTimeout` (the deadline passed), `fallbackModelUnavailable` (no model, input too long, or an error). Never an error: the keyboard keeps the list it shows. |

The engine searches with a small beam: the prompt and the answer so far are decoded once (usually only the answer: a conversion leaves its prompt and answer in the model's cache, and the search reuses them), then one decode per step holds every branch, and it stops once no open branch can beat the words already found. Conversions still start from an empty cache, so they give exactly the answers they gave before. On the Windows laptop (CPU), right after a conversion: median 280 ms, 90th percentile 400 ms, slowest 541 ms over 102 dev words.

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
