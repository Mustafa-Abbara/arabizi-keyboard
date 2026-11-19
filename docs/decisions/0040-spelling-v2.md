# ADR 0040: Spelling v2.0, a round of training data aimed at the smaller model, and a check for other scripts

- **Status:** Accepted, 18 Nov 2026
- **Date:** 2026-11-18
- **Deciders:** Moustafa Abbara
- **Stage:** P2 (data), P4 (model), P5 (engine)

## Context

The size study (PR #104, #105) found that Qwen3-0.6B Q4 keeps most of v4's accuracy at half the size: 0.900 against 0.912 on 1,642 real chats. It is 2.6 points behind on others dev. A word-by-word analysis of its errors on all five sets is in [SIZE_STUDY_ERRORS.md](../SIZE_STUDY_ERRORS.md).

Part of what both models lose comes from the data rather than the models. The data disagrees with itself:
- `leh` is written ليه 133 times and ليش 71 times.
- `hay` is written هي 83 times and هاي 20 times.
- The verb plural ending appears as both و and وا.
- Hamza on alif is written in some words and dropped in others.

The model is trained and then scored against these conventions, so an inconsistent rule counts as an error either way.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **أ and إ are written ا** everywhere (انا، اذا، سال، لا for `la2`). ء, ؤ, ئ and آ are unchanged, and ء is never merged with ا. | **Moustafa** |
| 2 | **A verb's plural ending is always و**, never وا (قالو، يعملو). Words where وا belongs to the word keep it (سوا، دوا، هوا، جوا). | **Moustafa** |
| 3 | **A feminine ending is ة** (سيارة), and ه only where it is part of the word (سفيه، الله). The data already followed this: a dry run found 7 words to change, some of them names, so no rows were rewritten for it. | **Moustafa** |
| 4 | **`leh` is ليه, `lesh` is ليش; `hay` is هي.** | **Moustafa** |
| 5 | **Every pair, reference and rule file is converted** by one script (`eval/src/arabizi_eval/spelling_v2.py`). This covers training, dev and test, the others set, the synthetic test, the rule dictionary, the letter odds, the accepted spellings, the ⌥Tab letter options and the word-guess files. The ranker is retrained on the converted guesses (`pairs train-ranker`). The held-out sets are re-frozen as **testset-v1.2** and **others-v1.2**: same rows and splits. The letter rules write a first vowel as ا. | Recommendation |
| 6 | **The accepted spellings هلأ، أل، ألت are dropped.** Without the hamza they would read as other words (هلا، ال، الت). | Recommendation |
| 7 | **Round 6 of AI-written training data** (`data/synthetic/prompts/build_step3_packs.py`): 3 packs of 1,800 pairs in 14 kinds, weighted by the measured errors (SIZE_STUDY_ERRORS.md). Every task states spelling v2.0, and the dataset build applies the converter to whatever comes back. | Recommendation |
| 8 | **The engine rejects letters of another script** (Chinese, Cyrillic, Hebrew…) that were not typed (`OutputChecks.otherScript`), and the rules answer instead. Qwen wrote such letters 6 times across the five sets (الم模型). | Recommendation |
| 9 | **Generated rows may not use evaluation words.** The round 6 prompts took 14 example words from Qwen's errors on the evaluation sets (others dev and test, the comparison set, the real chats, the synthetic test). The dataset build now drops any new row with an Arabizi word found in an evaluation set and never in training (820 of round 6's 13,450 rows). Round 6's last pack, D (`build_step4_packs.py`), already follows the rule below for any later round: its example words and topics are new, and the builder refuses to write the pack if an example uses an evaluation-only word or 4 words in a row from an evaluation set. For any later round, the weak spots are found on dev, others dev and one half of the real chats only; the other half, the frozen tests and the comparison set are kept for the final scores, and the pack builder checks its example words against the same list. | Recommendation |
| 10 | **Llama v5 is shipped** (19 Nov 2026): v4's recipe with 2 epochs on the converted data plus round 6. It is level with v4 on every set of real messages and writes spelling v2.0 itself; Qwen v2 stays 0.017 behind v4 on the others test and is not shipped. `config/engine.json` selects `arabizi-llama3.2-1b-v5`, it is published as the `model-v5` release (8 parts), and the app version is 0.5.0. | **Moustafa** |

## Consequences

- **Scores before and after this change are not directly comparable on the strict metric.** The shipped v4 writes أ / إ, and the references no longer do. Lenient accuracy already treats أ / إ / ا as equal, so it is unaffected. Compare old models with the lenient score, or rescore them after converting their outputs.
- **v4 wrote أ / إ** until v5, trained on v2.0 data, replaced it in 0.5.0. The rule fallback and the ⌥Tab letter options already write ا.
- **The Mac and Windows apps both read these rule files**, so both change together. Neither has its own spelling.
- **The plan:** train Qwen v2 on the converted data plus round 6. Round 6 is the last round of training: a round 7 was planned and dropped (19 Nov 2026). Qwen v2's scores are in [EVAL.md](../EVAL.md#qwen-v2-against-v4-19-nov-2026).
