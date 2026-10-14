# Evaluation

How every system (rules B0, base models B1, the fine-tuned model, the Swift engine) is scored. The final results table is added in P7. Code: `eval/src/arabizi_eval/` (`metrics.py`, `bootstrap.py`, `run.py`, `systems.py`); tests: `eval/tests/`.

## Running

```bash
uv run --project eval evalrun run --system identity --split dev            # run a system and score it
uv run --project eval evalrun score preds.jsonl --name qwen0.5b --split dev  # score predictions made elsewhere (Kaggle)
uv run --project eval evalrun compare eval/results/RUN_A eval/results/RUN_B # is A better than B?
```

- **Dev for everything, test once.** `--split test` refuses to run without `--final`. Prompts, hyperparameters and checkpoints are chosen on dev only; the test set is run once per final candidate (roadmap §4).
- Each run writes `eval/results/<date-time>-<system>-<split>/`: `predictions.jsonl` (per sentence: input, reference, output, every score) and `metrics.json` (corpus metrics, git SHA, SHA-256 of the data files, system description such as model and quantisation). Runs on dev/test are committed as evidence.
- **Private rows** ([ADR 0014](decisions/0014-private-own-chat-data.md)): runs that include them are saved under `eval/results/private/` (not committed); `--subset public` scores only public rows (publishable), `--subset private` only private ones. Docs quote only aggregate numbers from private runs.
- External predictions (`score`): JSONL with `id`, `prediction`, optional `latency_ms`; every row of the split needs a prediction.
- Sanity systems: `reference` returns the answer and must score 1.0 everywhere; `identity` returns the input and scores near 0 (first check, 200 training rows: word accuracy 0.05, from Latin words that should stay Latin).

## Systems

| System | What it is | Files |
|---|---|---|
| `reference`, `identity` | Sanity checks (1.0 and near 0) | `systems.py` |
| **`b0`** | Rule baseline (P3): clitics joined to the next word (`w el bet` → والبيت, never a double article), words kept in Latin when the training Arabic keeps them, the word dictionary, then letter rules; numbers, links and emoji untouched. Also the logic the Swift fallback will copy in P5. | `b0.py`, `data/rules/arabizi_to_arabic.json` (hand-written), `data/rules/arabizi_lexicon.json` (generated) |

**Rebuilding the B0 dictionary** (train split only; the variants file is generated, so build it first):

```bash
uv run --project eval pairs variants && uv run --project eval pairs lexicon
```

Known limits of the letter rules (tested in `test_b0.py`): a medial `a` can be a long vowel (`8ali` → غلي, not غالي) and final `-e` can be ي or ة (`2alle` → قلة, not قلي). Words in the dictionary avoid both.

## Results so far (dev)

| System | Dev rows | Word acc. | Lenient | CER | Punct. | Keep-Latin F1 (P / R) | Numbers | Run |
|---|---|---|---|---|---|---|---|---|
| B0 rules v1 | 15 public | 0.549 [0.47, 0.62] | 0.556 | 0.159 | 1.00 | 0.50 (1.00 / 0.33) | 1.00 | `eval/results/20261013-155728-b0-dev` |
| B0 rules v1 | 105 (15 public + 90 private) | 0.547 | 0.556 | 0.187 | 0.94 | 0.18 (1.00 / 0.10) | 1.00 | private run, 14 Oct 2026 |

### B1: base models without fine-tuning (dev, 105 rows: 15 public + 90 private; 14 Oct 2026)

`b1-<model>-zero` / `b1-<model>-5shot` (`eval/src/arabizi_eval/b1.py`, combined from Mohamad's and Claude's versions). llama.cpp 0.6.0 build b11429 (`llama-server`, Metal on the M2 GPU), Q4_K_M, greedy decoding (temperature 0, seed 0), Qwen3 thinking off, the **P4 instruction** (so base and fine-tuned models get the same input), prompt v1. **5-shot** = 5 fixed public training pairs chosen to show English kept in Latin, numbers and %, ؟ and ، and joined clitics (`ai-0004`, `ai-0022`, `ai-0056`, `ai-0116`, `ai-0050`); never dev or test rows [Claude's recommendation; the roadmap said "from dev"]. Peak memory = the server's RSS; latency per sentence after an untimed warm-up.

| System | Word acc. | 95% CI | CER | Keep-Latin F1 | Numbers | Halluc. | Peak RSS | p50 / p95 ms |
|---|---|---|---|---|---|---|---|---|
| **B0 rules** | **0.547** | [0.51, 0.59] | 0.187 | 0.18 | 1.00 | 0.00 | — | < 1 |
| Qwen3-1.7B, 5-shot | 0.144 | [0.12, 0.17] | 0.578 | 0.16 | 0.71 | 0.32 | 1,438 MB | 300 / 591 |
| Qwen2.5-1.5B, 5-shot | 0.125 | [0.09, 0.16] | 0.890 | 0.21 | 1.00 | 0.12 | 1,275 MB | 308 / 625 |
| Qwen3-1.7B, zero | 0.088 | [0.06, 0.11] | 0.758 | 0.12 | 1.00 | 0.06 | 1,424 MB | 295 / 739 |
| Qwen3-0.6B, 5-shot | 0.070 | [0.05, 0.09] | 0.764 | 0.18 | 0.50 | 0.26 | 751 MB | 167 / 301 |
| Qwen3-0.6B, zero | 0.068 | [0.05, 0.09] | 0.979 | 0.14 | 0.86 | 0.25 | 745 MB | 173 / 759 |
| Qwen2.5-0.5B, 5-shot | 0.052 | [0.03, 0.08] | 1.038 | 0.11 | 0.57 | 0.14 | 641 MB | 161 / 304 |
| Qwen2.5-0.5B, zero | 0.029 | [0.02, 0.04] | 1.440 | 0.04 | 0.86 | 0.69 | 637 MB | 169 / 1,257 |
| Qwen2.5-1.5B, zero | 0.022 | [0.01, 0.03] | 2.511 | 0.02 | 0.43 | 0.48 | 1,265 MB | 460 / 1,695 |

- **No base model comes close to B0** (best 0.144 vs 0.547). They do not know Lebanese Arabizi: digits stay unconverted, words are invented, and without examples they often explain or answer instead of converting (CER above 1 means outputs much longer than the reference). This is the gap fine-tuning (P4) must close.
- The 1.5–1.7B models with 5 examples are the best; examples help most for the larger models.
- **Memory:** all fit the 1.5 GB budget, but Qwen3-1.7B (1,438 MB) leaves almost no margin. **Latency:** with the prompt cache, the 5-shot runs are within budget (p95 ≤ 625 ms); runs without examples have long run-away outputs and higher p95.
- An earlier run on the same day with Claude's longer instruction and different examples scored higher (best 0.169) but is superseded: base and fine-tuned models must get the same instruction to be compared.
- Gemma 3 1B and Llama 3.2 1B: licences accepted, files not downloaded yet.

**Running B1.** Default (official runs, the 8 GB Air on AC power, other apps closed): the system checks the pinned file, starts its own `llama-server`, and records load time and peak memory.

```bash
uv run --project eval evalrun run --system b1-qwen2.5-0.5b-zero --split dev
```

Smoke runs on another machine (e.g. Windows) can use a server started by hand; memory is then not measured:

```bash
llama-server -m models/qwen2.5-0.5b-instruct-q4_k_m.gguf -c 2048 -np 1 --jinja --port 8081
ARABIZI_LLAMA_URL=http://127.0.0.1:8081 uv run --project eval evalrun run --system b1-qwen2.5-0.5b-zero --split dev --limit 5
```

Real typing (private chats) uses far more English than the sheet and AI rows: B0 keeps only 10% of the Latin words that should stay Latin.

## Metrics

Before comparing, diacritics, tatweel and extra spaces are removed ([SPELLING.md](SPELLING.md) §10). Words are whitespace-separated with surrounding punctuation stripped.

| Metric | Definition | Why |
|---|---|---|
| **Word accuracy** (strict) | Matched words ÷ max(reference words, output words), summed over all sentences. Matching = longest common subsequence, where an output word matches a reference position if it equals the primary spelling or an accepted variant (row `accepted` + `data/rules/accepted_variants.json`; multi-word variants such as عنجد/عن جد add a whole alternative reference, and the best one counts). Dividing by the longer side means extra invented words lower the score. Example: `شو عم بتعمل هلق` for `شو عم تعمل هلق` = 3/4. | The main number |
| Word accuracy, lenient | Same, but أ/إ/آ = ا, final ى = ي, final ة = ه, and Latin case ignored | Shows how many errors are only spelling conventions |
| 95% CI | Paired bootstrap over sentences, 10,000 resamples, recomputing the ratio of sums on each resample | Is a difference real? |
| Exact match | Share of sentences with every word right (punctuation not included) | Whole-message quality |
| Punctuation match | Share of sentences whose ? , ; ! . marks (Latin or Arabic) appear in the same order as in the reference, outside numbers and links | The ؟ ، ؛ rules of SPELLING.md §7 |
| CER | Character edits ÷ reference characters (best reference, punctuation stripped), summed over sentences | Partial credit for nearly-right words |
| Keep-Latin precision / recall / F1 | Over words with Latin letters: output Latin words that are in the reference ÷ all output Latin words (precision); reference Latin words found in the output ÷ all reference Latin words (recall); case-insensitive | English must stay English, and Arabizi must not stay Latin |
| Number preservation | Standalone numbers of the input (`100$`, `2pm`, `10:30`) found unchanged in the output ÷ all such numbers | Target 100% |
| MSA-rewrite rate | Share of sentences with at least one word from `data/rules/msa_words.json` (ماذا، الآن، لكن…) that is **not** in the reference | Catches standard Arabic instead of Lebanese |
| Hallucination rate | Share of sentences where the output has fewer than 0.5× or more than 2× the input's words, or contains Latin words not in the input | Catches invented text |
| Latency p50 / p95 | Per-sentence conversion time when the system reports it | Budgets: p50 ≤ 600 ms, p95 ≤ 1.2 s on the 8 GB Air |

Memory (peak RSS) is measured by the model runner, not by the scorer, and is recorded in the system description.

## Choices made here

All are **Claude's recommendation** (13 Oct 2026), open to change in a PR that re-scores existing runs:

- Word accuracy divides by the **longer** of reference and output, so insertions count against a system.
- Punctuation is scored **separately** (punctuation match), not inside word accuracy or CER.
- The MSA word list is a starting list of 31 common words; extend it when the error analysis finds others.
