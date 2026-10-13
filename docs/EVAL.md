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
- External predictions (`score`): JSONL with `id`, `prediction`, optional `latency_ms`; every row of the split needs a prediction.
- Sanity systems: `reference` returns the answer and must score 1.0 everywhere; `identity` returns the input and scores near 0 (first check, 200 training rows: word accuracy 0.05, from Latin words that should stay Latin).

## Metrics

Before comparing, diacritics, tatweel and extra spaces are removed ([SPELLING.md](SPELLING.md) §10). Words are whitespace-separated with surrounding punctuation and emoji stripped (emoji are not converted, so they are not counted). Spellings the guide accepts both ways are treated as equal in strict and lenient scoring: accepted variants in either direction (إذا = إزا), the "her" ending ـها = ـا (أساورها = أساورا), and a standalone ع joined to the next word (ع صيدا = عصيدا). Moustafa's references deliberately mix these forms.

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
