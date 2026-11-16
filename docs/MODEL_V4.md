# Model v4: from v3 to v4, step by step

How `arabizi-llama3.2-1b-v4` was made and how it compares with v3: what v3 got wrong, the two data steps that targeted those weaknesses, how the generated data was cleaned and filtered, how the model was trained, and every evaluation. Decision record: [ADR 0038](decisions/0038-model-v4.md).

**In one paragraph.** v3 was trained on 18,039 rows of real and hand-checked pairs. v4 adds **39,340 synthetic training pairs** written by four AI models in two steps and checked by Moustafa, each step aimed at errors measured on the model before it. Nothing generated went straight into training: 46,104 generated rows passed through cleaning, filtering, de-duplication and a held-out split, and 39,340 of them were kept for training (5,342 more were held out as a test set). With the same training recipe as v3, v4 is **clearly better than v3 on both frozen test sets** (+2.8 and +2.2 points of word accuracy), on both dev sets, on 1,642 real messages from writers outside every other set (+2.0 points), and on the held-out synthetic test (+11.5 points).

**Name.** Two models were trained on the way. The first was a measurement after step 1 (trained as tag `v4`, now `v4-interim`); it was never shipped. The shipped model was trained after step 2 under the tag `v5` and is called **v4** from now on. The interim results appear below because they decided step 2.

---

## 1. Where v3 stood

| Set | v3 word accuracy [95% CI] | Sentences fully right |
|---|---|---|
| Frozen test (243, run once 29 Oct) | 0.836 [0.815, 0.857] | 41% |
| Others test (299, run once 29 Oct) | 0.826 [0.811, 0.840] | 16% |
| Frozen dev (104) | 0.824 | 42% |
| Others dev (200) | 0.826 | 22.5% |

### What v3 got wrong (dev only)

The 480 words v3 wrote wrongly on the two dev sets, by how often the expected Arabic word occurs in v3's training data (v3's saved dev predictions, 11 Nov runs; the test sets were not used for this):

| The expected word… | Share of v3's wrong words |
|---|---|
| is a **new form of a word it knows** (another ending or attached prefix: مطاعم → مطاعمنا) | ~26% |
| was **never seen**, in any form | ~19% |
| was seen only **1–3 times** | ~17% |
| was seen 4–10 times | ~9% |
| is a **common word** misread (context, unusual spelling) | ~25% |
| is an English word wrongly converted | ~4% |

"New form" is a prefix-and-ending match, so the split is approximate. The point it made: v3's weakness was less "unknown words" than **known words in forms or spellings it had not seen**, plus words it had barely seen.

---

## 2. Step 1: synthetic rows aimed at v3's weak spots

### What was generated

Each generator worked through a task file with a fixed mix of **kinds**, every kind aimed at one row of the table above:

| Kind | What a round asked for | Aimed at |
|---|---|---|
| `inflect` | 30 words from the training data (seen 5–24 times), used in forms the data does not have | new forms of known words |
| `low` | 60 words seen only 1–3 times, used naturally | rarely seen words |
| `new` | a topic (food, places, slang, loanwords…), with every rare word outside the training vocabulary | never-seen words |
| `common` | 25 frequent words typed in unusual but real spellings | common words misread |
| `context` | short words whose meaning depends on the sentence (لا / لـ, من / مين…) | common words misread |
| `traps` | hamza, ة/ه/ا endings, long vowels, attached words | spelling conventions |

Every word list was drawn from the training vocabulary by a script (`scripts/known_words.py`), each word given to one round only, so machines and rounds never shared a list. The generators checked their own work silently before saving: meaning, nothing added or dropped, real Lebanese, no Modern Standard Arabic, spelling by `docs/SPELLING.md`, English and numbers kept, realistic Arabizi. They then checked each round's rule with code against the training vocabulary (`reference/known_words.tsv`, `known_arabizi.tsv`).

Two more sources joined step 1:

- **Breaker rows** (5,204): sentences generated and then **run through v3**, recording whether v3 broke on them (2,338 broke, 2,700 passed, 166 differed only by a spelling convention). Rows v3 gets wrong carry the most information. Their own `probe` rows were kept apart as a test.
- The packs ran on several machines (A, B, C) at once, with different topics and disjoint word lists, so the outputs would not repeat each other.

**Models.** The rows were written by four models: **sol-6.1, fable-5.2, opus-5.5 and sonnet-5.5**. Which run used which model was not recorded per run, so every row names all four.

**Prompts.** `data/synthetic/prompts/`: a full task file and the run instructions for step 1 (`step1_*`), and the scripts that built the packs from the training data.

### Step 1 output

| Group | Rows generated | Runs |
|---|---|---|
| A1 (machine A, round 1) | 9,000 | 5 |
| B1 | 5,400 | 3 |
| B2 (machine B, round 2: rarer words and new topics) | 1,800 | 1 |
| C1 | 7,200 | 4 |
| C2 | 1,300 | 1 (stopped early) |
| Breaker | 5,204 | 7 batches |
| **Step 1 total** | **29,904** | |

Several runs of the same pack are separate generations with the same word lists: they share 1 sentence in all, and the build below removes near-copies between them.

### The interim measurement (v4-interim)

To see whether step 1 helped before writing more, a model was trained on the v3 rows plus step 1's 25,169 cleaned training rows (94,150 examples, 280 minutes on a Kaggle T4):

| Set | v3 | v4-interim | Difference [95% CI] |
|---|---|---|---|
| Frozen dev | 0.824 | 0.852 | **+0.028** [+0.002, +0.055] |
| Others dev | 0.826 | 0.825 | −0.001 [−0.018, +0.015] |
| Synthetic test (3,528) | 0.782 | 0.893 | **+0.110** [+0.104, +0.116] |

It learned the targeted skills (sentences fully right on the synthetic test went from 29% to 58%, on new-vocabulary sentences from 12% to 47%), but **gained nothing on others dev**, other people's real typing.

### Why step 1 did not reach others dev

Comparing the step 1 data with real dev messages showed it did not look like real chat:

| | Real dev messages | Step 1 synthetic |
|---|---|---|
| Words per message | 10.4 | **6.2** |
| Messages with emoji | 19% | **1.4%** |
| Words with no vowels (`kfk`, `msh`) | 4.8% | **0.4%** |
| Messages ending in `.` `?` `!` | 0.3% | **7.5%** |
| ط typed as `6` | **0%** | 16% |

And the rule baseline scored 0.70 on the synthetic test against 0.60 on real tests, another sign that the generated Arabizi was more regular than real typing.

v4-interim's remaining errors on real typing (dev only):

| v4-interim's wrong words on others dev | Share |
|---|---|
| Common word misread in context (لا/ل, مع, ولا, عامل/عمل) | **28%** |
| New form of a known word | 20% |
| Seen 1–3 times | 18% |
| Never seen | 15% |
| Seen 4–10 times | 11% |
| English or French wrongly converted (`school`, `chevre`) | **6%** (it converted words v3 had kept) |

Many misreadings were heavy letters typed as plain letters (`tyour` → تيور for طيور); real typists write ط and ص as `t` and `s` 92–95% of the time. One suspicion was tested and **ruled out**: capitalised first words (first-word accuracy 89% either way).

---

## 3. Step 2: real-chat style, aimed at what was still wrong

One prompt design replaced the three fixed packs (`data/synthetic/prompts/step2_*`). Two changes:

**1. Real phone-chat style, checked with code after every round** (rewrite until the round passes):

| Rule | Set from |
|---|---|
| 8–30 words per message, average ≥ 10 | real 10.4 |
| 7 to 15 of every 50 messages with emoji | real 19% |
| ≥ 3% of words without vowels | real 4.8% |
| at most 2 of 50 ending in `.` `?` `!` | real 0.3% |
| never the digits 6 or 9; ط ص ض ظ as `t s d z` | real 0% |
| no accented letters | real 0% |

The style examples shown to the generator were 15 long real training messages with emoji.

**2. A mix aimed at v4-interim's errors**, 36 rounds per machine:

| Kind | Rounds | Aimed at |
|---|---|---|
| `context` | 9 | the largest gap: long messages where لا/لـ, مع, ولا/والله, من/مين, عامل/عمل… must be read from the sentence |
| `heavy` | 5 | 30 known words with ط ص ض ظ per round, typed with plain letters |
| `latin` | 5 | English and French kept in Latin next to loanwords written in Arabic |
| `inflect` | 7 | new forms of words seen 2–40 times, not yet used for this kind |
| `low` | 6 | words seen once |
| `new` | 4 | new topics per machine |

The training vocabulary was rebuilt from everything v4-interim had learned, so "new" meant new to it, and every list again excluded the words earlier rounds had used for the same kind.

**Output:** 9 runs (machines A, B and C three times each), **16,200 rows**, 1 sentence shared between runs.

| | Real dev | Step 1 | **Step 2** |
|---|---|---|---|
| Words per message | 10.4 | 6.2 | 14.6 |
| Messages with emoji | 18% | 1% | **22%** |
| Ending in `.` `?` `!` | 0.3% | 7.5% | **0%** |
| Words with no vowels | 4.9% | 0.4% | **3.3%** |
| 6/9 as letters, accents | 0% | some | **0%** |

Per-kind checks on the kept step 2 rows: 90% of `context` pairs have two or more ambiguous short words; every `heavy` pair has ط ص ض ظ (about 2 per message), all typed with plain letters; every `latin` pair keeps two or more Latin words (3.7 on average).

**Where step 2 overshot**, measured: messages are longer than real ones (median 14 words against 10, no messages of 5 words or fewer against 13.5% in real chat); French spellings, chat abbreviations and laughter are rarer than in real chat; and by character patterns it is no closer to real dev messages than step 1 (Jensen-Shannon distance of character trigrams 0.181 against 0.168; another set of real messages is at 0.111). The step 1 rows still supply short messages.

---

## 4. Cleaning and filtering (`scripts/build_synthetic_dataset.py`)

Generated rows never went into training directly. Every row from both steps passed through one rerunnable build (inputs: every run's files and the breaker file; output: the rows below, plus `data/synthetic/BUILD_REPORT.md`):

1. **Read and label** each row with its group (A1, B2, C5…, breaker) and kind.
2. **Normalise the Arabizi:** a Latin letter with a mark becomes the plain letter (é → e, ç → c; 2,224 messages; real typing has none). Each digit **6 or 9 used as a letter** is lined up with the Arabic letter it stands for and replaced by the plain letter for it: ط/ت → t, ظ/ز/ذ → z, ض/د → d, ص/س/ث → s, ق → 2 (696 messages: 672 × ط, 25 × ص, 8 × ت, 8 × ض, 3 × د, 2 × ظ, 1 × ق; 49 doubled letters or attached words used the default t/s, each checked by hand and correct). Numbers are left alone.
3. **Normalise the Arabic:** diacritics and tatweel removed, Arabic-Indic digits to Western, an Arabic prefix glued to a Latin word written apart (`ال video`, SPELLING.md 4).
4. **Drop rows that fail a check:** the repository's own row checks (numbers and links kept as typed, no Arabic letters in the Arabizi…); a Latin word in the Arabic that was not typed; a word count outside 0.5–2× of the Arabizi's; breaker rows where v3 differed only by a spelling convention; context rows of round 1 on machine C that used two words from the test-set error table.
5. **Drop any leak or repeat:** the same as, or 80% of the words of, any dev or test row; the same Arabizi as an existing training row; repeats inside the synthetic data.
6. **Hold out a test slice:** about 10% of the target words (by a hash of the word, so it never moves when data is added), and every row about a held-out word goes to test, whatever its group. The breaker's own probe rows are test too. A train row that near-copies a test row, or another train row, is dropped. When the build ran again with step 2, step 1's split was frozen (`--previous`): every row kept its side, and no new test row was allowed to repeat a word or sentence the interim model had trained on.
7. **Write the rows** in the pair schema: `method: ai_checked`, `checked_by: moustafa`, `writer` naming the four models, and a `source` that records the group, run, original id and kind.

| Dropped | Rows |
|---|---|
| train row near-copies a held-out test row | 862 |
| train row near-copies another train row | 234 |
| breaker: v3 differed only by spelling convention | 166 |
| word count outside 0.5–2× | 70 |
| round-1 context row with a test-set word | 47 |
| repeat inside the synthetic data | 41 |
| number not kept as typed | 2 |
| same as or near a dev/test row | **0** |

| | Generated | Kept for training | Held out (test) |
|---|---|---|---|
| Step 1 | 29,904 | 25,173 | 3,528 |
| Step 2 | 16,200 | 14,167 | 1,814 |
| **Total** | **46,104** | **39,340** | **5,342** |

The training rows are in `data/pairs/train-ai_checked.jsonl` (after the 2,000 earlier rows); the held-out rows in `data/synthetic/synthetic_test.jsonl`. `pairs validate` passes on all 58,225 rows (0 problems). Moustafa checked every row.

---

## 5. Training

| | v3 | v4 |
|---|---|---|
| Recipe | Llama 3.2 1B Instruct, LoRA rank 32 / alpha 64, lr 2e-4, 3 epochs, completion-only loss, seed 2026 | **the same** |
| Training rows | 18,039 | 57,379 (18,039 + 39,340) |
| Examples with spelling variants (`pairs export-train`) | 44,445 | 122,492 (1 variant per AI row) |
| AI-derived share of the examples | 9% | 67% (the 50% cap of ADR 0010 dropped, ADR 0038) |
| Kaggle T4 time | 154 min | 448 min |
| Validation loss per epoch | 0.293, **0.268**, 0.279 | 0.215, **0.183**, 0.190 (sets differ: not comparable) |
| Training loss at the end | 0.008 | 0.0096 |
| Best checkpoint | epoch 2 | epoch 2 |
| File | Q4_K_M, 807,694,016 bytes | Q4_K_M, 807,694,016 bytes, SHA-256 `26fcc756…ab06` |

The training loss still reaches about 0.01 with 2.8 times the examples, so the adapter is not short of capacity; the remaining gap is in carrying what it learns over to real typing. Notebook: `train/finetune_v4.ipynb`; run record: `train/runs/20261115-160254-llama3.2-1b-lora-v5.json` (trained under the tag v5).

---

## 6. Results: v4 against v3

Word accuracy (strict), keyboard engine with its own deadline, paired bootstrap over sentences (10,000 resamples).

### Final test sets, run once (16 Nov 2026)

| Set | v3 | **v4** | Difference [95% CI] | Sentences fully right |
|---|---|---|---|---|
| **Frozen test** (243) | 0.836 [0.815, 0.857] | **0.864** [0.845, 0.883] | **+0.028** [+0.013, +0.044] | 41% → **44%** |
| **Others test** (299) | 0.826 [0.811, 0.840] | **0.848** [0.833, 0.863] | **+0.022** [+0.009, +0.036] | 16% → **22%** |

| Other metrics (frozen / others test) | v3 | v4 |
|---|---|---|
| Character error rate | 0.053 / 0.070 | **0.042 / 0.058** |
| English kept in Latin (F1) | 0.931 / 0.841 | **0.936 / 0.867** |
| Numbers kept | 100% / 100% | 100% / 100% |
| Hallucination (invented text) | 0% / 1.7% | 0% / 2.0% |

### Dev sets and new real messages

| Set | v3 | v4-interim | **v4** | v4 − v3 [95% CI] |
|---|---|---|---|---|
| Frozen dev (104) | 0.824 | 0.852 | **0.854** | +0.029 [+0.003, +0.056] |
| Others dev (200) | 0.826 | 0.825 | **0.841** | +0.015 [−0.001, +0.030] |
| **senzi + WhatsApp** (1,642 real messages, new writers) | 0.892 | 0.902 | **0.912** | **+0.020** [+0.014, +0.025] |
| of which senzi (1,378) | 0.899 | 0.907 | 0.916 | +0.017 [+0.011, +0.023] |
| of which WhatsApp (264) | 0.856 | 0.877 | 0.888 | +0.031 [+0.015, +0.049] |

senzi and WhatsApp are private sets (not in the repository; aggregates only). 28 of their 1,670 rows that matched or nearly matched any training row were removed first, so all three models are scored on messages none of them trained on. Sentences fully right there: v3 59%, v4-interim 62%, **v4 65%**. One WhatsApp writer (36 messages) scored lower with v4 (−2.5 points); the other writer and senzi gained.

### Held-out synthetic test (5,342)

| | Rules | v3 | v4-interim | **v4** |
|---|---|---|---|---|
| All | 0.721 (12%) | 0.802 (24%) | 0.883 (48%) | **0.918 (57%)** |
| Step 2 rows (1,814) | 0.740 | 0.815 | 0.876 | **0.931** |
| Step 1 rows (3,528) | 0.697 | 0.786 | 0.893 | **0.900** |

(word accuracy; sentences fully right in brackets.) By kind, v4 against v4-interim: `latin` +0.055, `heavy` +0.052, `context` +0.049, new vocabulary +0.034, `low` +0.029, `inflect` +0.025, all clear; `common` and `traps` level. v4 − v3 overall: +0.115 [+0.111, +0.119].

### How the gaps closed, step by step

Synthetic test by kind, all models on the same 5,342 rows (v3 → after step 1 → after step 2):

| v3's weakness | Step 1 | Step 2 | Synthetic test (rules / v3 / v4-interim / **v4**) | Real typing |
|---|---|---|---|---|
| New forms of known words | `inflect` rounds | more `inflect` (rarer words) | `inflect` 0.713 / 0.791 / 0.883 / **0.908** | — |
| Rarely seen words | `low` | `low` (words seen once) | `low` 0.736 / 0.811 / 0.886 / **0.915** | — |
| Never-seen words | `new` | `new` (new topics) | `new` 0.690 / 0.727 / 0.833 / **0.866** | — |
| Common words misread in context | `context`, `common` | `context` in long messages (the largest share) | `context` 0.734 / 0.817 / 0.889 / **0.938** | — |
| Heavy letters typed as `t s d z` | (not targeted) | `heavy` + the no-6/9 style rule | `heavy` 0.778 / 0.842 / 0.890 / **0.942** | — |
| English and French converted | (got slightly worse) | `latin` rounds | `latin` 0.675 / 0.882 / 0.915 / **0.970** | keep-Latin F1, others dev 0.913 → 0.901 → **0.929**; others test 0.841 → **0.867** |
| Spelling conventions | `traps` | (style rules only) | `traps` 0.677 / 0.766 / 0.925 / 0.923 | — |
| Synthetic text unlike real chat | — | real-chat style rules | — | others dev +0.0 after step 1, **+1.6** after step 2; new writers **+1.0** after each step |

The pattern: step 1 taught the skills (big gains on synthetic text, a gain on frozen dev), but real typing from other writers moved only once step 2 made the data look like real chat and targeted the errors that remained.

### Speed

Same model size and quantisation as v3, so the cost per token is the same. On this Windows laptop's processor, v4 and v4-interim on the same 304 dev messages: median 1,024 ms against 1,118 ms, about 8% faster at every message length, which points to the laptop's speed varying between days rather than the model. **The Mac (the reference machine) has not been measured with v4.**

---

## 7. Other changes that came with the data

- **`idek` removed from the chat abbreviations** (`data/rules/chat_abbreviations.json`). In Lebanese Arabizi `idek` is also إيديك, "your hands"; every generated row that used it meant the hands, and the list would have kept "ghassel idek" in Latin. The test that compares the list with the training data caught it.
- **Rebuilt from the new training rows**, because their tests require it: the Python–Swift parity fixture (`b0_parity.json`), the spelling odds (`spelling_odds.json`) and the word-suggestion ranker with its fixture (`candidate_ranker.json`, `candidates_parity.json`).
- **Not rebuilt (follow-up):** the rule dictionary (`arabizi_lexicon.json`), which also decides which words get the "unsure word" hint, still holds v3's training vocabulary; the ranker's model signal was fit on v3's guesses (`eval/src/arabizi_eval/model_guesses.py`). Both work with v4 and are worth refreshing.

## 8. Limitations

- **67% of the training examples are AI-derived.** The gains on real typing are real but modest (2–3 points); the synthetic test overstates them (11.5 points).
- **The synthetic Arabizi is still not real typing**, by its wording and spelling habits (section 3).
- **Writers:** the frozen and others sets share writers with older training rows (ADR 0021, 0030); senzi and WhatsApp are the new-writer check.
- **One model per step and one seed**; the interim model was trained on step 1 only, so step 2's effect is measured as v4 against v4-interim.
- **The breaker generator's prompt is not in the repository**, and which of the four models wrote which run was not recorded.
- **Mac speed and memory** with v4 are not measured yet.

## Files

| What | Where |
|---|---|
| Training rows (the 39,340 new ones after the first 2,000) | `data/pairs/train-ai_checked.jsonl` |
| Held-out synthetic test | `data/synthetic/synthetic_test.jsonl` |
| Build report | `data/synthetic/BUILD_REPORT.md` |
| Prompts and pack builders | `data/synthetic/prompts/` |
| Build, vocabulary and scoring scripts | `scripts/build_synthetic_dataset.py`, `scripts/known_words.py`, `scripts/score_synthetic_test.py` |
| Notebooks | `train/finetune_v4.ipynb` (v4), `train/finetune_v4_interim.ipynb` |
| Run records | `train/runs/20261115-160254-llama3.2-1b-lora-v5.json` (v4), `train/runs/20261115-030439-llama3.2-1b-lora-v4.json` (interim) |
| Results | `eval/results/2026111[56]-*-v4*` |
