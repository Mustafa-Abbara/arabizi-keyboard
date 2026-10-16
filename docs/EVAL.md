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

| **`ft-<model id>`** | A fine-tuned model (P4): zero-shot, with the exact prompt saved by its training run (`prompt` in `config/models.json`), sent as text to `llama-server`'s `/completion` so no chat template is re-rendered. | `b1.py` (`FineTuned`), `config/models.json`, `train/runs/` |
| **`ft-<model id>-protect`** | The same, with standalone numbers replaced by `⟦0⟧`, `⟦1⟧`… before the model and restored after, as the P5 engine's `ProtectedSpans` does; a broken placeholder sends the sentence to B0. | `b1.py` (`ProtectedFineTuned`) |

| **`engine-<model id>`**, `engine-rules` | The Swift engine through `arabizi-cli` (P5): protected spans, saved prompt, model with deadline, output checks, rules on fallback; outcomes and fallback reasons recorded. Dev: `engine-arabizi-llama3.2-1b-v1` 0.770, numbers 100%, 98 model answers and 6 fallbacks ([ADR 0019](decisions/0019-engine-and-cli.md)). | `engine.py`, `Packages/ArabiziEngine` |

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
| Llama 3.2 1B, 5-shot | 0.169 | [0.15, 0.19] | 0.531 | 0.18 | 0.71 | 0.47 | 1,002 MB | 530 / 1,091 |
| Qwen3-1.7B, 5-shot | 0.144 | [0.12, 0.17] | 0.578 | 0.16 | 0.71 | 0.32 | 1,438 MB | 300 / 591 |
| Qwen2.5-1.5B, 5-shot | 0.125 | [0.09, 0.16] | 0.890 | 0.21 | 1.00 | 0.12 | 1,275 MB | 308 / 625 |
| Qwen3-1.7B, zero | 0.088 | [0.06, 0.11] | 0.758 | 0.12 | 1.00 | 0.06 | 1,424 MB | 295 / 739 |
| Qwen3-0.6B, 5-shot | 0.070 | [0.05, 0.09] | 0.764 | 0.18 | 0.50 | 0.26 | 751 MB | 167 / 301 |
| Qwen3-0.6B, zero | 0.068 | [0.05, 0.09] | 0.979 | 0.14 | 0.86 | 0.25 | 745 MB | 173 / 759 |
| Qwen2.5-0.5B, 5-shot | 0.052 | [0.03, 0.08] | 1.038 | 0.11 | 0.57 | 0.14 | 641 MB | 161 / 304 |
| Qwen2.5-0.5B, zero | 0.029 | [0.02, 0.04] | 1.440 | 0.04 | 0.86 | 0.69 | 637 MB | 169 / 1,257 |
| Gemma 3 1B, 5-shot | 0.072 | [0.05, 0.10] | 1.004 | 0.08 | 0.36 | 0.19 | 990 MB | 633 / 1,964 |
| Llama 3.2 1B, zero | 0.034 | [0.02, 0.05] | 1.243 | 0.05 | 0.50 | 0.64 | 990 MB | 986 / 3,486 |
| Qwen2.5-1.5B, zero | 0.022 | [0.01, 0.03] | 2.511 | 0.02 | 0.43 | 0.48 | 1,265 MB | 460 / 1,695 |
| Gemma 3 1B, zero | 0.016 | [0.01, 0.02] | 2.568 | 0.02 | 0.36 | 0.78 | 946 MB | 2,706 / 4,630 |

- **No base model comes close to B0** (best 0.169, Llama 3.2 1B with 5 examples, vs 0.547). They do not know Lebanese Arabizi: digits stay unconverted, words are invented, and without examples they often explain or answer instead of converting (CER above 1 means outputs much longer than the reference). This is the gap fine-tuning (P4) must close.
- With 5 examples, Llama 3.2 1B (0.169), Qwen3-1.7B (0.144) and Qwen2.5-1.5B (0.125) are the best; their intervals overlap. Llama invents text most often (47% of sentences flagged). Examples help every model; without them Gemma and Llama mostly answer or explain instead of converting.
- **Memory:** all fit the 1.5 GB budget, but Qwen3-1.7B (1,438 MB) leaves almost no margin. **Latency:** with the prompt cache, the 5-shot runs are within budget (p95 ≤ 625 ms); runs without examples have long run-away outputs and higher p95.
- An earlier run on the same day with Claude's longer instruction and different examples scored higher (best 0.169) but is superseded: base and fine-tuned models must get the same instruction to be compared.
- Gemma 3 1B and Llama 3.2 1B were run after Moustafa accepted their licences (14 Oct 2026).
- The choice of base models for fine-tuning is in [ADR 0004](decisions/0004-base-model-choice.md).

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

### P4: fine-tuned models (dev, `testset-v1.0`: 104 rows = 48 public + 56 private; 16 Oct 2026)

Same harness, llama.cpp b11429, greedy decoding; the fine-tuned model is zero-shot with its training prompt (`ft-<id>`). B0 and the best B1 were re-run on the frozen dev set so all three see the same sentences. All dev rows (private: aggregate numbers only, runs not committed):

| System | Word acc. | 95% CI | CER | Keep-Latin F1 | Numbers | Halluc. | Peak RSS | p50 / p95 ms |
|---|---|---|---|---|---|---|---|---|
| **Llama 3.2 1B fine-tuned** (`ft-arabizi-llama3.2-1b-v1`) | **0.768** | [0.73, 0.80] | 0.097 | 0.86 | 0.93 | 0.06 | 956 MB | 421 / 853 |
| Qwen3-1.7B fine-tuned (`ft-arabizi-qwen3-1.7b-v1`) | 0.723 | [0.68, 0.76] | 0.111 | 0.85 | 1.00 | 0.05 | 1,333 MB | 576 / 1,481 |
| B0 rules | 0.543 | [0.51, 0.58] | 0.189 | 0.17 | 1.00 | 0.00 | — | < 1 |
| Llama 3.2 1B, 5-shot (best B1) | 0.166 | [0.14, 0.19] | 0.529 | 0.17 | 0.71 | 0.48 | 971 MB | 583 / 1,110 |

Public dev rows only (48; reproducible from the repo: `eval/results/20261016-112328-b0-dev-public`, `…-112354-ft-arabizi-llama3.2-1b-v1-dev-public`, `…-112431-b1-llama3.2-1b-5shot-dev-public`):

| System | Word acc. | 95% CI | CER | Keep-Latin F1 | Numbers | Halluc. |
|---|---|---|---|---|---|---|
| **Llama 3.2 1B fine-tuned** | **0.733** | [0.68, 0.78] | 0.124 | 0.70 | 0.88 | 0.10 |
| Qwen3-1.7B fine-tuned (`eval/results/20261016-124744-ft-arabizi-qwen3-1.7b-v1-dev-public`) | 0.680 | [0.62, 0.74] | 0.129 | 0.79 | 1.00 | 0.06 |
| B0 rules | 0.555 | [0.50, 0.61] | 0.179 | 0.27 | 1.00 | 0.00 |
| Llama 3.2 1B, 5-shot | 0.143 | [0.11, 0.17] | 0.531 | 0.10 | 0.50 | 0.50 |

**Paired bootstrap** (word accuracy, 10,000 resamples): fine-tuned − B0 = **+0.225 [+0.179, +0.270]** on all dev rows and **+0.178 [+0.113, +0.245]** on the public rows; fine-tuned − best B1 = **+0.602 [+0.560, +0.643]**; Llama − Qwen (both fine-tuned) = **+0.045 [+0.017, +0.075]** (public rows +0.053 [+0.006, +0.103]); Qwen − B0 = +0.180 [+0.130, +0.229]. Both intervals are above 0, on dev; the P4 gate is decided on the frozen test set, once, for the final model (ADR 0005).

- **What fine-tuning fixed:** Lebanese spelling and joined clitics (CER halves against B0), and English kept in Latin (keep-Latin F1 0.17 → 0.86: the rules miss most English in real chats).
- **What still needs the engine:** standalone numbers come out unchanged only 93% of the time (the P4 gate asks ≥ 99% on test) and 6% of answers are flagged as hallucinations. Both are what P5's protected spans (numbers become `⟦0⟧`) and output checks are for; the raw model is measured here, the engine (`arabizi-cli`) will be measured in P5.
- **Speed and memory** fit the budgets on the 8 GB Air: p50 421 ms (≤ 600), p95 853 ms (≤ 1,200), 956 MB (≤ 1.5 GB), load 1.5 s.
- **Prompt detail found while wiring this up:** the Llama run trained with **two BOS tokens** (the chat template's `<|begin_of_text|>` text plus the one the tokenizer adds). Sending the saved prompt as text lets `llama-server` do the same, and reproduces the run's own samples exactly; with a single BOS the output degrades (`سبيقة` became `سبquina`). See MODELS.md.
- **Numbers to 100%:** the raw Llama lost 1 of the 14 standalone numbers in dev (`w baddak 2 recom letters` → `و بدك قيم ال letters`: it read the number 2 as the letter ق, which Arabizi also uses). Protecting numbers (`ft-arabizi-llama3.2-1b-v1-protect`) keeps **all 14** and scores **0.774 [0.74, 0.81]** (public 0.745 [0.70, 0.80]): +0.006 [0.000, +0.014] over the raw model, no placeholder broken (0 fallbacks), although training never showed placeholders. The alternative, falling back to B0 whenever a number is lost, also reaches 100% but loses 0.3 points. The gain is small because numbers are rare (13 of 104 sentences). P5's engine protects numbers this way (ADR 0016).
- **Why Qwen scored lower** (measured symptoms; the cause is not proven): both tokenizers split Arabic and Arabizi almost identically (≈ 2.0 tokens per Arabic word, 2.2 per Arabizi word), so the validation losses are comparable and Qwen's is really lower (0.163 vs 0.170 per character). Yet on dev Qwen gets 187 words wrong against Llama's 156; Llama is better on 29 sentences, Qwen on 11 (64 ties). The difference is in unfamiliar words: Llama writes what the letters sound like (`بسعت` for `بصوت`), Qwen tends to put in a real but different Arabic word (`عضوية` for `عيد زواجن`, `القلامة` for `القلم`, `جرة` for `جرافة`). Lower validation loss with worse held-out accuracy points to Qwen fitting the training sentences' style more closely and transferring less to new real typing; Qwen3's mostly-MSA pretraining may also pull it towards standard words. One run per model, so run-to-run variation is not measured.
- **Llama or Qwen:** Llama is more accurate (interval above 0), faster and lighter; Qwen keeps every number (1.00 vs 0.93) but its p95 (1,481 ms) is over the 1.2 s budget and it uses 1,333 MB. [ADR 0005](decisions/0005-final-model.md) (accepted) ships Llama; the frozen test set is run once for it.

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
