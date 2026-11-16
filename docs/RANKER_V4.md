# The ↑ list's ranker for model v4

What was tried, what won and what it means for "Spell it". Decision: [ADR 0039](decisions/0039-ranker-v4.md). The list itself is ADR 0036.

## The question

When Harfi writes a word wrong, the user presses ↑ and picks the right word from a list of 6. If the right word is not in the list, the only way out is **Spell it**, which means typing the Arabic letter by letter. The goal is that Spell it becomes a last resort, needed for fewer than 1% of words.

The list comes from 7 sources: the model's guesses, spellings, typing, units, the dictionary and others. Each candidate carries 29 signals. A ranker turns those signals into an order, and the list shows the top 6. The ranker shipped with 0.4.0 was trained on v3's guesses, with the model's guesses always offered. Two things changed with v4. The model makes different mistakes now, and the keyboards never asked for the model's guesses (ADR 0036 #5 was waiting on a speed measurement). So the shipped list is ordered by a ranker that learned from a source the app does not use.

## How it was measured

- **Training words:** v4's wrong words on public dev and dev-others (392), plus a sample of the held-out synthetic test (448). For each one, the engine's 10 guesses are in `eval/results/candidates/guesses-v4*.jsonl`.
- **Judging words:** v4's wrong words on the 1,642 private real messages (senzi, WhatsApp; new writers, never trained on). That is 777 wrong words out of 8,803; 670 of them line up one for one with the reference and can be scored. They are split by `sha256(id) % 2` into a **select** half (318), used to choose, and a **final** half (352), scored once at the end. Only aggregates leave the machine.
- **Measures:** whether the right word is offered at all (*offered*), whether it comes first, and whether it is in the top 3 or the top 6 shown. **Needing Spell it** means the right word is not in the 6 shown. The 107 wrong words that cannot be lined up are counted as needing it.

## Step 1: the list as shipped (no model guesses), select half

| Configuration | First | Top 3 | **Top 6** | Offered |
|---|---|---|---|---|
| S0b no ranker (the order the candidates were built in) | 32.4% | 49.7% | 54.1% | 86.5% |
| S0 0.4.0 ranker (trained on v3, with guesses) | 48.1% | 62.6% | 74.5% | 86.5% |
| S1 linear, trained without guesses, v4 dev + synthetic | 53.5% | 68.9% | **77.0%** | 86.5% |
| S2 same, rebuilt dictionary | 54.4% | 68.9% | 76.7% | 86.8% |
| S3 listwise (softmax over each list), rebuilt dictionary | 55.3% | 70.1% | 76.4% | 86.8% |
| S4 gradient-boosted trees, rebuilt dictionary | 51.6% | 72.3% | 78.9% | 86.8% |
| S5 linear, rebuilt dictionary, L2 = 10 / 100 | 54.7% / 53.8% | 68.2% / 70.1% | 77.4% / 76.1% | 86.8% |

Any ranker helps a lot: 54% → 75–79% in the top 6. Retraining on v4 without guesses adds about 5 points at first place and 2.5 in the top 6. The rest are within a point or two of each other, and none of them changes *offered*.

## Step 2: with the model's guesses (if they are turned on), select half

| Configuration | First | Top 3 | **Top 6** | Offered |
|---|---|---|---|---|
| E0b no ranker, 5 guesses | 28.0% | 63.5% | 76.4% | 90.6% |
| E0 0.4.0 ranker, 5 guesses | 60.4% | 72.6% | 79.6% | 90.6% |
| E1 linear, v4 dev only | 60.7% | 73.3% | 79.9% | 90.6% |
| E2 linear, v4 dev + synthetic | 60.7% | 72.6% | 81.1% | 90.6% |
| E3 same, L2 = 0.1 / 10 / 100 | 60.7% / 61.0% / 61.0% | 72.6% / 72.3% / 74.2% | 81.1% / 81.1% / 81.4% | 90.6% |
| E4 linear, 10 guesses | 61.0% | 77.4% | 84.0% | 92.8% |
| E5 linear, 5 guesses, rebuilt dictionary | 60.1% | 75.2% | 81.1% | 90.9% |
| E6 linear, 10 guesses, rebuilt dictionary | 60.4% | 77.0% | 85.8% | 92.8% |
| E7 listwise, 10 guesses, rebuilt dictionary | 62.9% | 76.7% | 84.3% | 92.8% |
| E8 trees, 10 guesses, rebuilt dictionary | 62.9% | 79.9% | 85.8% | 92.8% |
| E9 listwise, 5 guesses | 60.1% | 72.3% | 79.6% | 90.6% |
| E10 trees, 5 guesses | 64.5% | 75.2% | 82.7% | 90.6% |

The guesses raise *offered* by 4 points (5 guesses) to 6 points (10 guesses). That is the only change in this study that moves the ceiling.

## Step 3: one ranker for both cases

The app may run with guesses or without them, and the guesses may be late. So the shipped ranker should rank well both ways. Training on every word twice, once with 10 guesses offered and once with none ("mixed"), gives one ranker that does:

| Mixed ranker, select half | Guesses | First | Top 3 | Top 6 | Offered |
|---|---|---|---|---|---|
| linear, dictionary v3 | 0 | 52.8% | 68.2% | 76.4% | 86.5% |
| linear, dictionary v3 | 5 | 61.0% | 73.9% | 80.8% | 90.6% |
| linear, dictionary v3 | 10 | 61.3% | 77.0% | 84.0% | 92.8% |
| trees, dictionary v3 | 0 / 5 / 10 | 50.6 / 63.2 / 63.8% | 68.2 / 75.8 / 77.4% | 79.2 / 82.7 / 84.6% | same |
| linear, rebuilt dictionary | 0 / 5 / 10 | 53.1 / 60.4 / 59.7% | 68.9 / 75.2 / 78.0% | 75.5 / 81.1 / 85.2% | 86.8 / 90.9 / 92.8% |
| trees, rebuilt dictionary | 0 / 5 / 10 | 51.3 / 59.1 / 60.1% | 72.0 / 76.7 / 78.3% | 78.6 / 83.0 / 85.5% | same |

The mixed linear ranker loses at most 0.6 points against rankers trained for one case alone. It is the one chosen.

## Step 4: the final half, scored once

| Configuration | First | Top 3 | **Top 6** | Offered |
|---|---|---|---|---|
| no ranker, no guesses | 33.0% | 47.4% | 56.8% | 87.2% |
| 0.4.0 ranker, no guesses (the app today) | 50.0% | 64.2% | 78.4% | 87.2% |
| **new ranker, no guesses** | **55.1%** | **69.9%** | 78.4% | 87.2% |
| **new ranker, 5 guesses** | **62.2%** | **78.4%** | **84.9%** | 92.0% |
| new ranker, 10 guesses | 61.9% | 78.4% | 84.7% | 92.6% |
| trees, 10 guesses, rebuilt dictionary (the best on select) | 59.4% | 79.8% | 84.9% | 92.9% |

How much Spell it is needed, over all 777 real wrong words (8,803 words, 1,642 messages):

| Configuration | Wrong words fixed from the list | Needing Spell it: of wrong words | **of all words** | of messages |
|---|---|---|---|---|
| no ranker, no guesses | 55.5% | 44.5% | 4.60% | 16.9% |
| 0.4.0 ranker, no guesses (today) | 76.6% | 23.4% | 3.00% | 8.8% |
| **new ranker, no guesses** | 77.5% | 22.5% | **2.93%** | 8.4% |
| **new ranker, 5 guesses** | 83.0% | 17.0% | **2.51%** | 6.6% |
| new ranker, 10 guesses | 84.3% | 15.7% | 2.41% | 6.2% |
| trees, 10 guesses, rebuilt dictionary | 85.2% | 14.8% | 2.34% | 5.7% |

## The choices

- **Linear, not trees.** Trees had to beat the linear ranker by 2 points in the top 6 on the final half to be worth porting to Swift. They tie (84.9% against 84.9%). Trees stay a follow-up.
- **Dictionary v3, not rebuilt.** Rebuilding the dictionary from the v4 training rows (22,307 → 46,480 words) adds 0.3 points to *offered* and nothing reliable to the top 6. So the dictionary, its parity fixture and the unsure-word hints stay as they are.
- **5 guesses, not 10.** Speed was measured with the engine on this laptop's processor (124 wrong words on dev-others, after the message's conversion, as the keyboard would ask): 5 guesses take p50 255 ms, p95 383 ms and at most 539 ms; 10 guesses take p50 372 ms, p95 494 ms and at most 571 ms. 10 guesses add 118 ms at the median and nothing on the final half (84.7% against 84.9%). 5 guesses also meet ADR 0036's 400 ms target at p95.
- **Shipped:** `data/rules/candidate_ranker.json` and its Swift fixture are retrained with `pairs train-ranker`: 1,680 examples (840 wrong words × 0 and 10 guesses). The strongest signals are the source's rank (−1.69) and the typing odds (+1.25).

## Would more ranker data help?

Not much. Training on part of the words (dev + synthetic, 10 guesses, rebuilt dictionary; top 6 on select, average of 3 random draws):

| Share | Words | Linear top 6 | Linear first |
|---|---|---|---|
| 10% | 84 | 83.8% | 58.3% |
| 25% | 210 | 84.8% | 59.6% |
| 50% | 420 | 85.1% | 60.1% |
| 75% | 630 | 85.4% | 59.3% |
| 100% | 840 | 85.8% | 60.4% |

Ten times the words adds 2 points, and the curve is nearly flat after 25%. The listwise ranker was unstable (at 50% one draw fell to 77.4%). The ranker is not what limits the list. What limits it is whether the right word is a candidate at all.

## Why Spell it is still needed for 2.5% of words, and what would get it to 1%

Of the real wrong words needing Spell it with 5 guesses:

- **The right word is not a candidate** for 8% of the scored wrong words, and the 107 wrong words that cannot be lined up (merged or split words, a word dropped or added) are not reachable by a list of single words at all. Together these are most of what is left. No ranker can fix them.
- **The right word is a candidate but below the 6th place** for about 7% of the scored wrong words. A better ranker can still win some of these, but every method tried here lands within a point or two.

So the ranker gets the list close to what its candidates allow. For Spell it to be needed for fewer than 1% of words (today 2.93%; 2.51% with guesses), these would have to move, in order of size:

1. **Turn the model's guesses on in both keyboards** (5 guesses; −0.4 points of all words). This is measured on Windows (p95 383 ms) and still needs measuring on the 8 GB Air. Since 16 Nov 2026 both keyboards can ask for them (ADR 0036, update): on in Windows, off on the Mac until the Air is measured.
2. **New candidates for what cannot be a candidate now:** merging two typed words into one Arabic word and splitting one into two, a wider beam for the model's guesses, and a second page of the list.
3. **Fewer wrong words in the first place:** v4 gets 8.8% of words wrong on real messages. At today's rate, each point of model accuracy removes about 0.3 points of Spell it.

## Reproducing

```
uv run --project eval --with llama-cpp-python python -m arabizi_eval.model_guesses \
    eval/results/<v4 dev run>/predictions.jsonl --set dev --out eval/results/candidates/guesses-v4.jsonl
uv run --project eval --with llama-cpp-python python -m arabizi_eval.model_guesses \
    <764 sampled rows of v4's synthetic-test predictions> --set synthetic-test --out eval/results/candidates/guesses-v4-synthetic.jsonl
uv run --project eval pairs train-ranker   # candidate_ranker.json (0 and 10 guesses) and the Swift parity fixture
```

The experiment scripts and the private real words stay outside the repository.
