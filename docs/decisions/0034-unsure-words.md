# ADR 0034: Words the model is unsure of

- **Status:** Proposed, 7 Nov 2026
- **Date:** 2026-11-07
- **Deciders:** Moustafa Abbara
- **Stage:** Phase 2, Windows port (ADR 0032)

## Context

Rare or unseen words are the largest group of v3's wrong words (EVAL.md, final report). A cheap signal marks most of them: a word the model wrote that was never written in the training sentences (the lexicon's `arabic_words`). On the v3 keyboard-engine dev runs (frozen dev and others dev, 86 sentences whose typed, reference and output word counts match, 598 Arabic words; 7 Nov 2026), such an "unsure" word is wrong 54% of the time against 6% for a known word, and unsure words hold 56% of the wrong words. The question was what to do with them.

## Options considered (measured on the same words; fixed = wrong became right, broke = right became wrong)

| Option for an unsure word | Fixed | Broke |
|---|---|---|
| The rules' word | 6 | 20 |
| The nearest known word (one letter changed) | 5 | 32 |
| The rules' word, only if it is a known word | 4 | 1 |
| **The rule dictionary's spelling of the typed word** (chosen) | 4 | 1 |
| Nothing, but point the word out to the user (chosen, as well) | — | — |

A second check on 1,401 sentences no model has seen (`senzi_all.xlsx`, 4,619 comparable words): v3's wrong words are mostly close to the right ones (41% have three quarters of the letters right, 49% half; 10% less), and replacing a word with the rules' spelling whenever it strays from the typed letters breaks more right words than it fixes at every threshold tried (at best 5 fixed, 26 broken).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **The dictionary swap:** after the model, an unsure word that came from one typed word in the rule dictionary is written the dictionary's way, punctuation kept (`UnsureWords.swap`, ArabiziCore). Applied to the model's answers only (Enter, ↑ and the preview's engine conversions), before the user's habits (ADR 0033), which win. | **Recommendation** (measured above) |
| 2 | **Point it out instead of guessing:** when Enter sends a conversion that still holds an unsure word, a tip says "Not sure about سيت · Alt+Tab to fix it" (Alt+Tab starts on the doubtful word, ADR 0027). Not for a word the user has chosen themself, and each word once per app session, so a name the user keeps is not pointed out again. | **Recommendation** |
| 3 | **No other fallback:** neither the rules' word nor the nearest known word replaces an unsure word (they break more than they fix). | **Recommendation** (measured above) |

## Consequences

- Tests: what counts as unsure (Arabic, never in training, punctuation ignored), the swap (only dictionary words, punctuation kept, known words untouched) in ArabiziCore.
- The gain is small (4 of 42 unsure errors on dev); the tip is the larger part: a word the model never saw is best spelled by the user, and each fix feeds their habits.
- The Mac applies both too (8 Nov 2026). On the Mac's v3 dev outputs the swap fixed 8 words and broke 1, and on 1,401 unseen messages (`senzi`) it fixed 12 and broke 2 (`arabizi-suggestions-report --unsure`).
- The sample is small; re-measure on the next dev runs and drop #1 if it stops paying.
