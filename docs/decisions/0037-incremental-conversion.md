# ADR 0037: Incremental conversion while typing

- **Status:** Proposed, 11 Nov 2026
- **Date:** 2026-11-11
- **Deciders:** Moustafa Abbara
- **Stage:** Phase 2, Windows port (ADR 0032)

## Context

The live preview asks the engine for the whole message again after each word, and the model writes its whole answer again, one token at a time. On the Windows laptop (processor only) a message takes 0.7 to 1.7 s that way even with the instruction kept decoded (EVAL.md, "Speed on Windows"), so the preview falls behind typing and Enter often has to wait.

While someone types, each text is the last one plus a word, and the answer is mostly the last answer plus a word.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| Keep converting every text on its own | The same text always gives the same answer | Time grows with the length of the message |
| Convert only the new word, and add it to the last answer | Fastest | Earlier words can no longer change when later words give them context; not what the model was trained to do |
| **Check the last answer in one decode call, then go on from the first token the model would now write differently** (chosen) | The answer is still the model's greedy answer for the whole text; earlier words can change | A few answers differ by a word from the same text converted on its own (see below) |

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **A text that continues the last one reuses it** (`LlamaModel.pin(_:incrementalSuffix:)`). The text the two prompts share stays decoded. The last answer is decoded in one call as a draft: each of its tokens the model would also choose now is kept, and writing goes on token by token from the first one it would not. | **Recommendation** |
| 2 | **"Continues" means:** the same text but for its last 3 tokens at most, or with more after it. Any other text, and the same text again, is converted on its own, from the instruction alone, as before. A conversion that ran out of time leaves no draft. | **Recommendation** |
| 3 | **On by default in the engine** (Windows and the Mac), with `arabizi-cli --no-incremental` to switch it off. The evaluation harness sends unrelated messages, so its runs are not affected: accuracy numbers stay the ones of texts converted on their own. | **Recommendation** |
| 4 | **The difference in answers is accepted.** Decoding several tokens in one call rounds differently from decoding them one at a time, and where the model was almost undecided between two tokens the other one can win. Measured below: about one message in seven differs by a word or two, and accuracy is the same. | **Recommendation**; the user decides |

## Measured (11 Nov 2026)

`scripts/typing_simulation.py`: 200 dev messages (both dev sets, shuffled with seed 2026), each sent one word longer at a time (2,018 requests), on the Windows laptop, with a 10 s deadline so nothing falls back. One run.

| | Every step: p50 / p95 | Whole message (last step): p50 / p95 / max | Word accuracy of the whole messages |
|---|---|---|---|
| Every text on its own | 515 / 1,318 ms | 843 / 1,686 / 2,106 ms | 0.817 |
| **Incremental** | 260 / 684 ms | 360 / 1,049 / 1,441 ms | 0.818 |

- **28 of the 200** whole-message answers differ between the two (54 words in the answers of equal length). One message followed by hand: the differences are between close alternatives (a comma or none, `عم` or `عام`), and the answers of texts converted on their own change in the same way from one word to the next.
- What the preview shows is what Enter sends (the keyboard keeps the preview's answer for the exact text), so the user never sees an answer change at Enter because of this.

## Consequences

- Tests (ArabiziLLM, with a model file): the same typing gives the same answers; a text that does not continue the last one, and the same text again, get the answer they get on their own; a conversion that ran out of time leaves no draft.
- The preview and Enter are about twice as fast while typing on Windows. A long message whose draft stops early (the model changes an early word) still takes as long as before from that word on.
- **The Mac** (11 Nov 2026, M2 Air, Metal, the same 200 messages): a whole message p50 612 → 207 ms and p95 1,173 → 667 ms; word accuracy 0.8206 → 0.8180; 9 of the 200 answers differ from the same text converted on its own (fewer than on the Windows processor). Kept on there too ([EVAL.md](../EVAL.md), "Speed on the Mac").
- **Not measured:** the real keyboard, which also asks in the middle of a word.
- Drop it (`incremental: false` in `Engine.load`) if a later measurement shows accuracy falling.
