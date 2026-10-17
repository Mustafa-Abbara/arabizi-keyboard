# ADR 0023: Repair invented Latin token by token instead of discarding the whole answer

- **Status:** proposed (results below)
- **Date:** 2026-10-17
- **Deciders:** Moustafa Abbara (Claude's recommendation)
- **Stage:** P5 (engine), accuracy plan

## Context

The engine (ADR 0019) sends a whole sentence to the rules when the model's answer has a Latin word the input did not have (OutputChecks' "new Latin" rule). With the v2 model (ADR 0022) on the others dev set, 25 of 200 sentences fell back for that reason, and the engine scored 0.770 against the raw model's 0.811. On the sentences that fell back, the model had 351 of 455 words right and the rules 262.

Most "invented" tokens were not invented words. They were **an Arabic prefix glued to an English word of the input** (`الvideo`, `عالfacebook`, `بالcomment`), which SPELLING.md 4 writes with a space (`ال video`). The rest were half-converted input words (`program` for `programe`, `قadir`) and a few real inventions (`the`, `moms`).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | When the **only** failed check is "new Latin", the engine repairs the answer token by token, then runs every check again; a repaired answer that passes is used (`model`), anything else gives the rules as before. Every other failure (placeholders, word count, token limit, deadline) still gives the rules for the whole sentence. | **Claude's recommendation** |
| 2 | **Split:** a token of Arabic letters followed by Latin letters, whose Latin part was typed, becomes `<Arabic> <Latin>` (SPELLING.md 4: "Do not mix scripts inside one token"). | SPELLING.md 4; repair **Claude's recommendation** |
| 3 | **Replace:** any other token with Latin letters that were not typed is replaced by the rule converter's spelling of the **single** input word that contains those letters (`program` → the rules for `programe`). No such word, or more than one: no repair, rules for the sentence. | **Claude's recommendation** |
| 4 | "Typed" includes an English word glued to an Arabizi prefix in the input (`lvideo`, `3alfacebook` → `video`, `facebook`), for the check and the repair alike (`OutputChecks.gluedPrefixes`: l, el, il, al, b, bi, be, bel, bil, w, wel, wil, 3a, 3al, hal, la, lal). Other leading letters do not count (`salon` does not allow `alon`). | **Claude's recommendation** |
| 5 | `arabizi-cli --explain` now writes **one line per request** (the fallback reason, `repaired: N token(s)`, or null); the harness records repairs separately (`describe.repairs`). `--no-repair` (harness system `engine-<id>-norepair`) turns the repair off, to measure it. | **Claude's recommendation** |

## Results (dev; the test sets are not touched)

Swift engine with `arabizi-llama3.2-1b-v2`, 10 s deadline, same build, repair on vs off (`--no-repair`), 17 Oct 2026:

| Set | With repair | Without | Paired difference | Sentences to the rules (with / without) | Repaired answers |
|---|---|---|---|---|---|
| Others dev (200, public) | **0.788** [0.77, 0.81] | 0.771 [0.75, 0.80] | **+0.017 [+0.007, +0.029]** | 10 / 30 | 20 (17 with 1 token, 2 with 2, 1 with 3) |
| Frozen dev (104) | **0.814** [0.78, 0.85] | 0.809 [0.77, 0.84] | +0.004 [+0.000, +0.014] | 0 / 1 | 1 |

- Others dev: sentences sent to the rules fall from 30 to 10 (the rest: 6 broken placeholders, 4 Latin that could not be traced to one input word). The engine now scores 0.788 against the raw model's 0.811 (ADR 0022).
- Frozen dev: no loss; the engine with v2 (0.814) matches the Python model with numbers protected (0.812), within the P5 gate's 1 point, and is above the engine with v1 (0.770): +0.044 [+0.014, +0.074].
- Latency is unchanged (the repair is string work after generation).
- The fallback reason in these runs read "new Latin words (0)"; it now gives the count again (fixed after the runs, outputs unaffected).

## Consequences

- The keyboard shows the model's answer more often; a repaired answer never contains a token that mixes scripts, and never a Latin word that was not typed.
- A replaced token can disagree with the model's choice for neighbouring words (the rules spell one word alone); the paired comparison above is the check that this costs less than it gains.
- Placeholders are untouched by the repair, and the full checks run again after it.
