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
- **Private rows** ([ADR 0014](decisions/0014-private-own-chat-data.md)): **since [ADR 0028](decisions/0028-all-data-public.md) there are none**: every row and every run is public, including the 38 earlier runs that were kept in `eval/results/private/` (now in `eval/results/`; superseded B1 runs in `eval/results/superseded/`). Tables below keep their public/private split as a record of what was run. Before ADR 0028: runs that include them are saved under `eval/results/private/` (not committed); `--subset public` scores only public rows (publishable), `--subset private` only private ones. Docs quote only aggregate numbers from private runs.
- **Others set versions:** `others-v1.1` (ADR 0024) only adds spaces between Arabic prefixes and English words in 65 references; numbers on v1.0 and v1.1 are not comparable (ADR 0024 has both).
- **Swift engine runs** (`engine-<id>`, 10 s deadline) include the token repair (ADR 0023); `engine-<id>-norepair` measures without it; **`engine-<id>-kb` uses the keyboard's own deadline per message** (ADR 0025), so it measures the real keyboard. `describe` records outcomes, fallback reasons and repairs (counts only).
- **The others set** ([ADR 0021](decisions/0021-real-rows-others-set.md)): `--others` scores the separate held-out set of real messages by other people (`data/pairs/others/`) instead of `testset-v1.0`, with the same `--split`/`--final` rules; results are named `…-others`.
- External predictions (`score`): JSONL with `id`, `prediction`, optional `latency_ms`; every row of the split needs a prediction.
- Sanity systems: `reference` returns the answer and must score 1.0 everywhere; `identity` returns the input and scores near 0 (first check, 200 training rows: word accuracy 0.05, from Latin words that should stay Latin).

## Systems

| System | What it is | Files |
|---|---|---|
| `reference`, `identity` | Sanity checks (1.0 and near 0) | `systems.py` |
| **`b0`** | Rule baseline (P3): clitics joined to the next word (`w el bet` → والبيت, never a double article), words kept in Latin when the training Arabic keeps them, the word dictionary, then letter rules; numbers, links and emoji untouched. Also the logic the Swift fallback will copy in P5. | `b0.py`, `data/rules/arabizi_to_arabic.json` (hand-written), `data/rules/arabizi_lexicon.json` (generated) |

**B0 versions:** B0 v1 is the dictionary used until 17 Oct 2026 (every earlier B0 number); **B0 v2** was rebuilt with the real rows (ADR 0026): others dev 0.725 (v1 0.591), frozen dev 0.628 (v1 0.543).

**Rebuilding the B0 dictionary** (train split only; the variants file is generated, so build it first):

```bash
uv run --project eval pairs variants && uv run --project eval pairs lexicon
```

| **`ft-<model id>`** | A fine-tuned model (P4): zero-shot, with the exact prompt saved by its training run (`prompt` in `config/models.json`), sent as text to `llama-server`'s `/completion` so no chat template is re-rendered. | `b1.py` (`FineTuned`), `config/models.json`, `train/runs/` |
| **`ft-<model id>-protect`** | The same, with standalone numbers replaced by `⟦0⟧`, `⟦1⟧`… before the model and restored after, as the P5 engine's `ProtectedSpans` does; a broken placeholder sends the sentence to B0. | `b1.py` (`ProtectedFineTuned`) |

| **`engine-<model id>`**, `engine-rules` | The Swift engine through `arabizi-cli` (P5): protected spans, saved prompt, model with deadline, output checks, rules on fallback; outcomes and fallback reasons recorded. Dev: `engine-arabizi-llama3.2-1b-v1` 0.770, numbers 100%, 98 model answers and 6 fallbacks ([ADR 0019](decisions/0019-engine-and-cli.md)). | `engine.py`, `Packages/ArabiziEngine` |

**Word suggestions v2 (↑ list, [ADR 0036](decisions/0036-candidate-list-v2.md)).** The reference is `candidates.py`. Its generated files are rebuilt from public rows only:

```bash
uv run --project eval pairs spelling-odds      # data/rules/spelling_odds.json: letter odds from the train split
uv run --project eval --with llama-cpp-python python -m arabizi_eval.model_guesses \
    eval/results/<run>/predictions.jsonl --set dev --out eval/results/candidates/guesses-v3.jsonl
uv run --project eval pairs train-ranker       # data/rules/candidate_ranker.json, from dev and dev-others
uv run --project eval pairs candidates-report  # right word first / top 3 / top 7, today's list against v2
```

`model_guesses` needs the model file and llama-cpp-python, which is not an eval dependency. Guesses for private sheets stay outside the repo; `candidates-report --guesses FILE` scores them as counts only.

Known limits of the letter rules (tested in `test_b0.py`): a medial `a` can be a long vowel (`8ali` → غلي, not غالي) and final `-e` can be ي or ة (`2alle` → قلة, not قلي). Words in the dictionary avoid both.

## Results so far (dev)

| System | Dev rows | Word acc. | Lenient | CER | Punct. | Keep-Latin F1 (P / R) | Numbers | Run |
|---|---|---|---|---|---|---|---|---|
| B0 rules v1 | 15 public | 0.549 [0.47, 0.62] | 0.556 | 0.159 | 1.00 | 0.50 (1.00 / 0.33) | 1.00 | `eval/results/20261013-155728-b0-dev` |
| B0 rules v1 | 105 (15 public + 90 private) | 0.547 | 0.556 | 0.187 | 0.94 | 0.18 (1.00 / 0.10) | 1.00 | private run, 14 Oct 2026 |

### B1: base models without fine-tuning (dev, 105 rows: 15 public + 90 private; 14 Oct 2026)

`b1-<model>-zero` / `b1-<model>-5shot` (`eval/src/arabizi_eval/b1.py`, combined from two versions). llama.cpp 0.6.0 build b11429 (`llama-server`, Metal on the M2 GPU), Q4_K_M, greedy decoding (temperature 0, seed 0), Qwen3 thinking off, the **P4 instruction** (so base and fine-tuned models get the same input), prompt v1. **5-shot** = 5 fixed public training pairs chosen to show English kept in Latin, numbers and %, ؟ and ، and joined clitics (`ai-0004`, `ai-0022`, `ai-0056`, `ai-0116`, `ai-0050`); never dev or test rows [Recommendation; the roadmap said "from dev"]. Peak memory = the server's RSS; latency per sentence after an untimed warm-up.

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
- An earlier run on the same day with a longer instruction and different examples scored higher (best 0.169) but is superseded: base and fine-tuned models must get the same instruction to be compared.
- Gemma 3 1B and Llama 3.2 1B were run after their licences were accepted (14 Oct 2026).
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

### P4 final: the frozen test set, run once (16 Oct 2026)

`testset-v1.0` test split, **243 rows** (113 public + 130 private), each system run **once** (`evalrun run --split test --final`); the public numbers re-score those same outputs (`evalrun score --subset public`), so no model saw the test set twice. Model chosen beforehand on dev ([ADR 0005](decisions/0005-final-model.md)).

| System (all 243 rows) | Word acc. | 95% CI | CER | Keep-Latin F1 | Numbers | Halluc. | Peak RSS | p50 / p95 ms |
|---|---|---|---|---|---|---|---|---|
| **Llama 3.2 1B fine-tuned, numbers protected** (`-protect`, as the engine runs it) | **0.783** | [0.76, 0.81] | 0.091 | 0.81 | 24/24 | 0.070 | 830 MB | **487 / 1,013** |
| Llama 3.2 1B fine-tuned, raw | 0.783 | [0.76, 0.81] | 0.090 | 0.81 | 24/24 | 0.070 | 988 MB | 755 / 2,618 * |
| B0 rules | 0.594 | [0.57, 0.62] | 0.167 | 0.33 | 24/24 | 0.000 | — | < 1 |
| Llama 3.2 1B, 5-shot (best B1) | 0.147 | [0.13, 0.16] | 0.527 | 0.22 | 16/24 | 0.374 | — | 629 / 1,170 |

Public rows only (113; `eval/results/20261016-1312*-test-public`): fine-tuned raw 0.757 [0.72, 0.80], protected 0.756 [0.72, 0.79], B0 0.572 [0.54, 0.61], best B1 0.151 [0.13, 0.18].

**Paired bootstrap** (word accuracy): fine-tuned − B0 = **+0.189 [+0.159, +0.219]** (public **+0.185 [+0.142, +0.229]**); fine-tuned − best B1 = **+0.636 [+0.607, +0.665]** (public +0.606 [+0.563, +0.649]); protected − B0 = +0.188 [+0.158, +0.219]; protected − raw = −0.000 [−0.004, +0.003] (the raw model kept all 24 test numbers here; protection fell back to B0 on 2 sentences whose placeholder the model broke).

\* The raw run hit a temporary slowdown of the Mac in the middle (25-sentence block medians rose from about 0.5–0.9 s to 1.3–1.8 s for sentences 100–175, then fell back), so its latency is not representative; the protected run of the same model just after was steady (blocks about 0.42–0.44 s after warm-up), as was the raw model on dev (421 / 853 ms).

**P4 gate** (roadmap):

- [x] The fine-tuned model beats B0 **and** the best B1 on test word accuracy with the 95% CI of the difference above 0: +0.189 [+0.159, +0.219] and +0.636 [+0.607, +0.665].
- [x] Number preservation ≥ 99%: 24/24 (100%) raw and protected (dev: raw 13/14, protected 14/14). Keep-Latin F1 0.81 and hallucination rate 7.0% reported.
- [x] The quantized model meets the budgets on the 8 GB Air: 830–988 MB (≤ 1.5 GB); p50 487 ms (≤ 600), p95 1,013 ms (≤ 1,200) in the protected run; dev raw 421 / 853 ms.
- [x] Re-running training in a fresh Kaggle session at the same data SHA gives dev accuracy within 2 points: the sweep's `base` run (17 Oct 2026, fresh session, same data and package versions, seed 2026) produced a GGUF **bit-for-bit identical** to the shipped model (same SHA-256 `807121d8…60eb13`), so its dev score is the shipped one exactly (0 points apart). TRAINING.md, "Sweep results".

Not done from P4 step 4–5 (optional in the solo plan, roadmap §5): the data ablations (with/without AI rows, with/without variants), Q4_K_M vs unquantized, and the local AladdinBench check on other people's typing.

### v2: trained with the real rows, test sets run once (17 Oct 2026)

Full tables and the decision: [ADR 0022](decisions/0022-model-v2-real-rows.md) (proposed). Numbers protected, as the engine runs it:

| System | Frozen test (243) | Others test (299, ADR 0021) |
|---|---|---|
| **`arabizi-llama3.2-1b-v2`** | **0.820** [0.80, 0.84] | **0.800** [0.78, 0.82] |
| shipped `v1` | 0.783 [0.76, 0.81] | 0.656 [0.64, 0.67] |
| B0 rules | 0.594 [0.57, 0.62] | 0.607 [0.59, 0.62] |

`v2` − `v1` (paired): **+0.037 [+0.015, +0.059]** on frozen test and **+0.144 [+0.125, +0.163]** on others test. Raw `v2`: 0.826 frozen, 0.802 others. Public frozen-test rows: `v2` 0.803 raw, 0.794 protected. Others-set runs are public and committed (`eval/results/20261017-*-others`).

### v3: second friends-and-family batch, test sets run once (29 Oct 2026)

Decision and training: [ADR 0030](decisions/0030-model-v3.md). Each system was run once per test set; the v2 rows are the recorded 17 Oct runs, the others-test v2 row rescored on the current set (`others-v1.1`).

| System | Frozen test (243) | Others test (299) |
|---|---|---|
| **v3, keyboard engine** (`engine-arabizi-llama3.2-1b-v3-kb`) | **0.836** [0.815, 0.857] | **0.826** [0.811, 0.840] |
| v3, model only (`ft-arabizi-llama3.2-1b-v3`) | 0.836 [0.816, 0.857] | 0.827 [0.813, 0.842] |
| v2, protected spans (`v2-protect`) | 0.820 [0.80, 0.84] | 0.792 |
| v2, model only | 0.826 [0.805, 0.848] | 0.802 (`others-v1.0`) |

Paired word accuracy, v3 engine − v2: **+0.034 [+0.021, +0.047]** on others test (against v2 protected spans, same set); **+0.016 [−0.001, +0.033]** on frozen test against v2 protected spans and **+0.009 [−0.007, +0.026]** against v2 model only: no clear difference. Keep-Latin F1 on others test 0.84 against 0.68 (v2 protected spans), hallucination rate 1.7% against 13.4%; on frozen test 0.93 and 0% against 0.84 and 4.9%. Dev (v3 − v2, keyboard engine): +0.009 frozen dev, +0.017 others dev; v3 never fell back to the rules on others dev (v2: 7 of 200).

## Final report (P7, 1 Nov 2026)

The shipped system is **v3 through the keyboard engine** (`engine-arabizi-llama3.2-1b-v3-kb`): **0.836** [0.815, 0.857] on the frozen test set and **0.826** [0.811, 0.840] on the others test set, each run once (29 Oct 2026, table above). Against the rules (B0: 0.594 / 0.607) that is about +0.24 and +0.22; against the best model without fine-tuning (5-shot Llama 3.2 1B, 0.147 on frozen test) +0.69.

**Speed and memory on the 8 GB M2 Air** (same test runs, the keyboard's own deadline per message): p50 604 ms / p95 945 ms on frozen test, p50 922 ms / p95 1,423 ms on others test (longer messages; the deadline grows with length, ADR 0025). Peak memory was measured for v1 (830 MB with protected spans, P4); v3 has the same size and quantisation (Q4_K_M, 808 MB) and was not measured again.

**Errors by cause.** Wrong words of both v3 test runs, in sentences with as many words as their reference (220 words): grouped automatically, and a random sample of 50 (seed 2026) read and grouped by hand.

| Cause | All 220, automatic | 50, read by hand | Examples (typed → shown, expected) |
|---|---|---|---|
| Rare or unseen word read wrongly | 118 (54%) | 14 | `flfoul` → فلوفول (فليفلة), `aarbyye` → قريبة (عربية), `sha5sen` → شخسان (شخصين) |
| Spelling convention, one letter or ending off (hamza, alif, ة/ه, long vowel, article) | 42 (19%) | 18 | `ymkn` → ممكن (يمكن), `alef` → إلف (ألف), `sobo7` → صبح (الصبح) |
| Word moved one place: not a model error, an artefact of comparing by position | (in "other") | 9 | `heik` paired with أكل, `ma3` with هيك |
| Different word or form | 37 (17%) | 2 | `talli3` → تلعب (طلع), `sawene` → سويني (ثواني) |
| Small ambiguous word (`la`, `w`, `men`, `l`) | 12 (5%) | 4 | `la` → ل (لا), `men` → من (مين) |
| English word or name converted, or Arabizi left in Latin | 11 (5%) | 3 | `tea` converted, `pampam` left in Latin |

The largest group is words the model never saw in training: 53% of the automatic count and the second group by hand. More training rows with those words (v4) is the main lever; one-letter spelling differences are the next, and the ⌥Tab / ↑ suggestions offer most of them (50% / 42% of wrong words on dev).

**Not done:** the per-app results (the app matrix, `docs/spikes/ime_app_matrix.md`); the P4 data ablations (with and without the AI-drafted rows and the rule variants) and Q4_K_M against the unquantised model; a peak-memory measurement of v3.

## Speed on Windows (11 Nov 2026)

The first measurement of the engine on Windows: the development laptop (Intel i7-10870H, 8 cores, 16 GB), where the
model runs on the processor only (llama.cpp with AVX2, one thread per core). The Swift engine through `arabizi-cli`
with the keyboard's own deadline per message, on the two **dev** sets (the test sets were not run), one run each.

| System | Frozen dev (104): word acc. | p50 / p95 ms | Others dev (200): word acc. | p50 / p95 ms | Rule fallbacks (deadline) |
|---|---|---|---|---|---|
| Whole prompt decoded for every conversion, as until now (`engine-arabizi-llama3.2-1b-v3-kb-nopin`) | 0.827 | 817 / 1,432 | 0.824 | 1,393 / 2,165 | 0 + 4 |
| **Instruction decoded once and kept** (`engine-arabizi-llama3.2-1b-v3-kb`) | 0.826 | 659 / 1,287 | 0.824 | 1,021 / 1,707 | 0 + 0 |

- **What changed:** every prompt starts with the same instruction (about 45 tokens). `LlamaModel.pin` keeps it decoded
  between conversions, so a conversion decodes only its own text: 160 to 460 ms less per message here. The instruction
  is always decoded on its own and the text after it, so an answer still depends only on its text.
- **Accuracy:** splitting the prompt in two decode calls changes the arithmetic a little, and a few greedy answers with
  it: 0.827 → 0.826 on frozen dev (one word), 0.824 → 0.824 on others dev. No real difference.
- **Fallbacks:** a message that misses its deadline is converted by the rules. An earlier pass over the same 304
  messages on the same laptop, before the change, missed 23 deadlines (p50 1,427 ms, p95 2,456 ms), against 4 in the
  run above: the speed of this laptop varies between runs, and the slower it is the more messages fall back.
- **Budgets:** the Mac budgets (p50 ≤ 600 ms, p95 ≤ 1.2 s) are still not met on this laptop's processor; long
  messages are the slow ones. **Not measured:** the Mac after this change (the same code runs there), the graphics
  card on Windows, peak memory.
- `arabizi-cli --no-pin` (system `…-kb-nopin`) decodes the whole prompt every time, to repeat the comparison.
- **While typing** ([ADR 0037](decisions/0037-incremental-conversion.md)): a text that continues the last one reuses it and checks the last answer in one decode call. Typing 200 dev messages one word at a time (`scripts/typing_simulation.py`): a whole message p50 843 → 360 ms and p95 1,686 → 1,049 ms, word accuracy 0.817 → 0.818; 28 of the 200 answers differ by a word or two from the same text converted on its own. The runs above send unrelated messages and are not affected.

## Speed on the Mac (11 Nov 2026)

The same two changes measured on the 8 GB M2 MacBook Air (Metal), with the Swift engine through `arabizi-cli`, the
keyboard's own deadline per message, the two **dev** sets (the test sets were not run), one run each, nothing else
running.

| System | Frozen dev (104): word acc. | p50 / p95 ms | Others dev (200): word acc. | p50 / p95 ms | Rule fallbacks (deadline) |
|---|---|---|---|---|---|
| Whole prompt decoded for every conversion (`engine-arabizi-llama3.2-1b-v3-kb-nopin`) | 0.824 | 713 / 1,272 | 0.826 | 801 / 1,511 | 0 + 0 |
| **Instruction decoded once and kept** (`engine-arabizi-llama3.2-1b-v3-kb`) | 0.824 | **387 / 753** | 0.826 | **671 / 1,154** | 0 + 0 |

- **Accuracy:** unchanged on both sets (every answer came from the model).
- **Speed:** 130 to 330 ms less per message at the median. The Mac budgets (p50 ≤ 600 ms, p95 ≤ 1.2 s) are met on frozen
  dev; on others dev (longer messages) p95 1,154 ms is within budget and p50 671 ms is just above it.
- **While typing** ([ADR 0037](decisions/0037-incremental-conversion.md), `scripts/typing_simulation.py`, the same 200
  dev messages one word at a time): a whole message p50 612 → **207 ms** and p95 1,173 → **667 ms** (every step
  p50 379 → 170 ms); word accuracy 0.8206 → 0.8180; **9 of the 200** answers differ from the same text converted on its
  own (28 words where the lengths match), against 28 of 200 on the Windows processor.

## Reproducing a baseline from a fresh clone (11 Nov 2026)

`git clone` of `main` at `0b8ca02`, then `uv run --project eval evalrun run --system b0 --split dev`, against the committed run of 29 Oct (`20261029-153707-b0-dev`): the same data (`data_sha256` 08b3a640…), and every accuracy metric identical (word accuracy 0.756, lenient 0.762). Latency p50 0.019 → 0.021 ms (+10%), p95 0.047 → 0.051 ms (+9%), within the 20% the P3 gate allows. Run: `eval/results/20261111-221425-b0-dev`.

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

All are recommendations (13 Oct 2026), open to change in a PR that re-scores existing runs:

- Word accuracy divides by the **longer** of reference and output, so insertions count against a system.
- Punctuation is scored **separately** (punctuation match), not inside word accuracy or CER.
- The MSA word list is a starting list of 31 common words; extend it when the error analysis finds others.
