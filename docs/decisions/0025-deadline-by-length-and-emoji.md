# ADR 0025: A deadline that grows with the message, and emoji left to the model

- **Status:** accepted (17 Oct 2026)
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara
- **Stage:** P5 (engine), accuracy plan

## Context

An error review of the installed keyboard on others dev (`others-v1.1`, 17 Oct 2026) found two causes of avoidable fallbacks to the rules:

1. **The fixed 1,500 ms deadline.** Accuracy runs use a 10 s deadline (ADR 0019), but the keyboard gives the model 1,500 ms. Other people write longer messages: 26 of 200 others dev sentences (8–22 words) took longer than 1,500 ms, so in the real keyboard they got the rules. Replacing those answers with the rules' answers gives an estimated **0.764** for the keyboard instead of the 0.806 measured with 10 s. On frozen dev no sentence took longer.
2. **Emoji as placeholders.** ProtectedSpans replaced emoji with ⟦n⟧ placeholders, which the model never saw in training; 6 of 200 others dev sentences fell back because a placeholder came back broken. 52 of 200 others dev sentences have emoji, against 8 with numbers. Without masking (the Python runs), v2 kept every emoji exactly in all 151 dev and test sentences that have them (236 emoji, 0 lost).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | Each message's deadline is `min(max_deadline_ms, deadline_ms + deadline_per_word_ms × max(0, words − deadline_free_words))`, with **1,500 ms, +120 ms per word beyond 8, at most 3,000 ms** (`config/engine.json`; `EngineConfig.deadlineMs(for:)`). The keyboard (`EngineClient`) sends that deadline and waits for it plus 500 ms. On the dev latencies this formula would time out 2 of 304 sentences. | Moustafa (scale it, up to ~2.5–3 s); numbers **Recommendation** from the dev latencies |
| 2 | Emoji are **no longer placeholders**; links, emails, mentions, hashtags and standalone numbers still are. A new output check requires the answer's emoji to equal the input's, in order (skin tones and flags whole); otherwise the rules answer (`check: emoji changed`). | Moustafa (stop masking emoji); check **Recommendation** |
| 3 | `arabizi-cli --keyboard-deadline` gives each request the keyboard's deadline, and the harness's `engine-<id>-kb` uses it, so the real keyboard's accuracy is measured, not only the model's. | **Recommendation** |

## Results (dev, Swift engine with v2 and the token repair, 17 Oct 2026)

| Keyboard engine | Others dev (`others-v1.1`, 200) | Frozen dev (104) |
|---|---|---|
| Before: fixed 1,500 ms, emoji masked | ≈ **0.764** (estimated: 26 sentences past 1,500 ms get the rules) | 0.814 |
| Emoji unmasked, 10 s deadline | 0.811 [0.79, 0.83] | 0.815 [0.78, 0.85] |
| **After: emoji unmasked, keyboard deadline** (`-kb`) | **0.809** [0.79, 0.83] | **0.815** [0.78, 0.85] |

- **Emoji:** +0.005 [+0.001, +0.010] on others dev; sentences sent to the rules by a broken placeholder fell from 6 to 1; no emoji check failed.
- **Deadline:** with the keyboard's own deadlines only 2 of 200 others sentences timed out, and accuracy is within noise of the 10 s run (−0.002 [−0.006, +0.000]); frozen dev identical. Against the estimated 0.764, the real keyboard gains about **4.5 points** on other people's typing.
- Latency with the keyboard deadline: others dev p50 / p95 882 / 2,086 ms (long messages now wait up to about 2–3 s instead of getting the rules); frozen dev 611 / 1,096 ms.

## Consequences

- Enter can take up to 3.5 s (3,000 ms + 500 ms margin) on a very long message; speed is acceptable, so Enter stays synchronous. P6 dogfooding should confirm it feels fine.
- The model must copy emoji itself; the emoji check catches any loss, so an emoji never disappears from what the keyboard types.
- The test sets are not touched; the P5 gate's engine-on-test run should use `engine-<id>-kb`, the real keyboard.
