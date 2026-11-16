# Synthetic data for v4: build report

Inputs: 46,104 rows read (5,204 from the breaker file). Kept 44,682: **39,340 train**, **5,342 held out for testing**. Latin letters with marks replaced by the plain letter (é -> e, ç -> c) in 2,224 Arabizi messages. Digits 6 and 9 used as letters replaced by the plain letter for the Arabic letter they stand for (in 696 messages).

Each 6 or 9 was lined up with the Arabic letter it stands for: 6 = ط -> t (672), no matching Arabic letter (default used) (49), 9 = ص -> s (25), 6 = ت -> t (8), 6 = ض -> d (8), 6 = د -> d (3), 6 = ظ -> z (2), 9 = ق -> 2 (1), 6 = ص -> s (1).

## Dropped

| Reason | Rows |
|---|---|
| train row near-copies a held-out test row | 862 |
| train row near-copies another train row | 234 |
| breaker: v3 differed only by spelling convention | 166 |
| word count outside 0.5x-2x | 70 |
| context round used a test-set example word | 47 |
| repeat inside the synthetic data | 41 |
| repo row check: numbers not kept as typed (SPELLING.md 6) | 2 |

## Train / held-out test by group and kind

| Group | common | context | heavy | inflect | latin | low | new | plain | traps | total |
|---|---|---|---|---|---|---|---|---|---|---|
| A1 | 1114/133 | 436/59 |  | 2466/264 |  | 2007/231 | 1567/178 |  | 421/67 | 8,011/932 |
| A5 |  | 1146/203 | 707/43 | 928/122 | 692/58 | 851/49 | 531/69 |  |  | 4,855/544 |
| B1 | 671/78 | 263/37 |  | 1454/175 |  | 1228/111 | 917/125 |  | 259/37 | 4,792/563 |
| B2 | 48/2 | 83/15 |  | 428/72 |  | 638/62 | 306/44 |  | 87/13 | 1,590/208 |
| B5 |  | 1102/248 | 650/100 | 927/123 | 684/66 | 830/70 | 523/77 |  |  | 4,716/684 |
| C1 | 886/111 | 311/42 |  | 1933/252 |  | 1596/188 | 1228/169 |  | 355/43 | 6,309/805 |
| C2 |  | 42/8 |  | 261/39 |  | 545/53 | 224/25 |  | 87/13 | 1,159/138 |
| C5 |  | 1148/194 | 653/60 | 820/142 | 679/69 | 774/46 | 522/75 |  |  | 4,596/586 |
| breaker | 187/21 | 51/0 |  | 971/367 |  | 702/162 | 779/300 | 622/32 |  | 3,312/882 |

Cells are train/test. Groups: A1 = machine A round 1, B2 = machine B round 2, and so on; breaker = the breaker file (its `probe` rows are all in test, as `breaker-probe`). About 10% of the target words are held out, chosen by a hash of the word, and every row with a held-out target word is in test, whatever its group: no train row targets a test word (0 rows moved to test for that). Rows without a target word are held out by a hash of the sentence.

## ADR 0010 cap (AI-generated rows at most half of the training rows)

Current training rows: 18,039 (2,000 ai_checked, 16,039 other). Adding all 39,340 new train rows gives an AI share of **72%**. The most new rows that keep it at or under 50% is **14,039**.

`train-ai_checked.synthetic.capped.jsonl` holds that many: first every breaker row v3 got wrong, then the rest shared out by kind in proportion to v3's measured dev errors (new forms 28%, rarely seen words 28%, new vocabulary 22%, unusual spellings 12%, traps 5%, context 3%, plain 2%), breaker rows v3 already got right last within each kind. By kind: inflect 4,020, low 3,782, new 3,293, common 1,568, traps 635, context 385, plain 356.

## Before training

- Every train row: checked_by `moustafa`, writer `ai: sol-6.1, fable-5.2, opus-5.5, sonnet-5.5 (per-run model not recorded)`.
- Record the prompts and the four models in `docs/DATA.md`.
- 47 kept rows contain a word from the MSA list; worth a look.
- 366 kept rows are agent 'fallback' pairs (ordinary pairs where the round's rule could not be met); their `source` ends in `fallback`.
- Keep `ai_variants` at 1 (the export default) so the AI rows don't get two rule-made variants each.
