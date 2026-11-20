# ADR 0041: Merge and split entries in the ↑ list, and the ranker kept for model v5

- **Status:** Accepted, 20 Nov 2026
- **Date:** 2026-11-20
- **Deciders:** Moustafa Abbara
- **Stage:** P5 (engine), P6 (keyboards)

## Context

The ↑ list (ADR 0036) offers single words for a single word. When the model writes two words where one was meant (ع سطح for عالسطح, رح شوف for حشوف) or one where two were meant (هالكتر for هال كتير, وانا for و انا), the list cannot offer the fix, and the user has to spell it letter by letter.

With model v5 (ADR 0040), these spans are a large share of its wrong words: 14% on the real chats, 23% on the frozen test and 16% on the others test. About a third of them are only a space too many or too few.

Two questions came with v5:
- Does the ranker, trained on v4's mistakes (ADR 0039), still suit v5?
- How much would merge and split entries give?

## The ranker for v5: kept

v5's guesses for its wrong words were collected on dev and others dev (340 words, `eval/results/candidates/guesses-v5.jsonl`) and on all 6,549 held-out synthetic rows (3,217 words). Rankers retrained on them, alone or with v4's 840 words, with three L2 settings, and gradient-boosted trees were all judged on v5's 1,139 real wrong words (570 real chats, 167 frozen test, 402 others test).

| Right word in the 6 shown, all 1,139 | No guesses | 5 guesses | 10 guesses |
|---|---|---|---|
| Shipped ranker (v4's guesses) | 69.2% | 77.4% | 80.1% |
| Best retrained (v5 dev + synthetic) | 68.5% | 78.0% | 80.9% |

The best retrained ranker gains 0.5 points with 5 guesses, under the 1-point bar set in advance, and loses 0.7 points without guesses. Trees are within a point either way, not the 2 points ADR 0039 asks before porting them. **The shipped ranker stays.**

The synthetic guesses (1.3 MB, over the repository's file limit) are not committed. They come back with:

```
uv run --project eval --with llama-cpp-python python -m arabizi_eval.model_guesses \
    <v5's predictions on data/synthetic/synthetic_test.jsonl> --set synthetic-test --out eval/results/candidates/guesses-v5-synthetic.jsonl
```

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **The ↑ list offers at most one merge or split entry**, in its last Arabic place (the typed word stays last). Where it goes does not change how often a right one-word fix stays in the 6. Two entries gave nothing more than one. | **Recommendation**, measured on dev |
| 2 | **A split** (one shown word → two) is offered only when the word came from two or more typed words. It is the word's own letters with the space put back (cut where the first part spells the first typed word, or after و، ب، ل، ع، ف، ك), else each typed word spelled on its own. | **Recommendation** |
| 3 | **A merge** (two shown words → one) is offered only when both came from the same typed word(s), or the first was typed as a small joined word (3a, b, l, 7a, bhal…) and written as one (ع، ب، رح، بهال…). It is the two words' own letters joined first (رح + verb as ح + verb, a prefix joined with its article), then ال put in after a one-letter prefix, then the typed words spelled as one. | **Recommendation** |
| 4 | **Words always written apart are never merged:** عم، شو، بس، مش، لا، في، ما، يا. | **Recommendation** (spelling rule) |
| 5 | **Taking a merge or split entry records no correction:** it is not a spelling of one typed word. | **Recommendation** |
| 6 | **Where it lives:** `candidates.py` (`span_entry`) is the reference. `MergeSplit.swift` ports it and is checked against `candidates_parity.json`. `Composer` places the entry, shows it in place (a merge selects the merged word) and applies it. Both keyboards give `Suggester.spanEntry`. | **Recommendation** |

The rules were tuned on dev and others dev only (30 merge/split spans). The judging sets were scored once with the rules as tuned, and once more after decision 4, a spelling rule that also helped dev.

## Results (v5's wrong words; "fixable": the right fix is in the 6 shown)

| Set | Guesses | One-word fixes in the 6 | Merge/split fixes in the 6 | Wrong words fixable |
|---|---|---|---|---|
| Real chats (8,801 words) | 0 | 74.6% → 74.2% | 17.2% → **46.9%** | 364 → **385** of 565 |
| | 5 | 81.2% → 81.0% | 28.1% → **53.1%** | 402 → **421** |
| Frozen test (1,613 words) | 0 | 65.5% → 64.6% | 7.4% → **59.3%** | 76 → **95** of 155 |
| | 5 | 73.5% → 73.5% | 22.2% → **59.3%** | 89 → **105** |
| Others test (3,373 words) | 0 | 61.9% → 61.5% | 7.7% → **28.8%** | 189 → **202** of 378 |
| | 5 | 70.2% → 69.6% | 17.3% → **28.8%** | 219 → **226** |

Across the three sets, 42–53 more wrong words can be fixed from the list. Retraining the ranker on v5 gave 6. "Spell it" falls by about 0.2 points of all words on the real chats and 1 point on the frozen test.

## Consequences

- Some merge/split mistakes are spelling conventions rather than errors (و انا against وانا). The list offers both; the model's answer is unchanged.
- The rest of what the list cannot offer is mostly words the sources never produce: about 9% of the real chats' wrong words and 17% of the others test's, with 5 guesses. Turning the model's guesses on in the Mac keyboard is the next largest gain (about 8 points in the top 6). It waits on a speed check on the 8 GB Air.
