# ADR 0016: Swift rule fallback and protected spans (P5)

- **Status:** accepted
- **Date:** 2026-10-15
- **Deciders:** Moustafa Abbara (Claude's recommendation)
- **Stage:** P5

## Context

P5 needs a rule fallback in Swift for when the model is slow, missing or produces a bad output (roadmap P5), and protected spans so the model never touches links, numbers or emoji (P5 step 2). B0 (`eval/src/arabizi_eval/b0.py`, 0.547 on dev) is already the rule system, and its rules file says the Swift fallback must behave the same. The P5 gate later asks the Swift engine to reproduce Python's numbers.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | The fallback is a **port of B0** (`ArabiziCore/RuleConverter.swift`) that reads the **same files** (`data/rules/arabizi_to_arabic.json`, `arabizi_lexicon.json`); nothing is copied into the package. `scripts/build_ime.sh` copies the two files into the app's Resources. | Rules file comment + **Claude's recommendation** (no copy) |
| 2 | **Exact parity, tested:** Python writes `Packages/ArabiziCore/Tests/ArabiziCoreTests/Fixtures/b0_parity.json` (`python -m arabizi_eval.parity`, also run by `pairs lexicon`): the rule files' hashes, full outputs for ~100 edge cases, a short hash of the output for every committed public train and dev row, and one hash over the letter rules applied to every dictionary word. Swift must match it; pytest fails if the fixture is stale. Test rows are left out (scored once, at the end); private rows are never read. | **Claude's recommendation** |
| 3 | Swift works on **Unicode scalars** with hand-written equivalents of Python's `\w`, `\s`, `NUMBER` and `UNTOUCHED`, not on Characters or ICU regexes: Characters merge marks and compare by canonical equivalence, and ICU's `\w` includes combining marks where Python's does not. | **Claude's recommendation** |
| 4 | The rules file is checked when loaded (one-character keys, all five vowels, rules version 1) and **word endings may not overlap** (`ne` and `e`), because Python tries them in file order and Swift dictionaries have none. | **Claude's recommendation** |
| 5 | **Python fix:** `TOKEN` uses `re.DOTALL`; a token with a newline between two words used to crash B0 (`TOKEN.match` returned None). No dev or test row has one, so B0's scores do not change. | **Claude's recommendation** |
| 6 | **Protected spans** (`ProtectedSpans.swift`): links, emails, @mentions and #hashtags, runs of emoji, and standalone numbers (B0's `NUMBER` pattern, so `2pm` is a number and `3am` is not) become `⟦0⟧`, `⟦1⟧`…; sentence punctuation after a link stays outside it; the brackets ⟦ ⟧ in the input are protected too, so every bracket in the masked text is ours. `restore` returns nil when a placeholder is lost, repeated, invented or malformed: the first output check of P5 step 3. | Roadmap P5 step 2 (Claude's recommendation); details **Claude's recommendation** |
| 7 | The keyboard now converts with `RuleConverter` instead of the P1 toy converter; if the rule files are missing from the app it logs an error and keeps the toy converter, so typing still works. | **Claude's recommendation** |

## Consequences

- Changing the rules or rebuilding the dictionary means regenerating the fixture in the same PR (`pairs lexicon` does it); CI fails otherwise, in both the Python and the Swift job.
- B0 has known gaps (letter rules drop long vowels, `LAU` is not on the committed keep-Latin list); the port keeps them on purpose, so the Swift fallback scores what B0 scores.
- B0 keeps a whole link token unchanged (`www.lau.edu,`), while protected spans leave the comma outside the link for the model to convert. Both are deliberate: B0 must match Python, and the model should convert the punctuation.
- Still to do in P5: output checks beyond placeholders (step 3), `ArabiziLLM` and how to call llama.cpp from Swift (step 4, ADR 0003), the XPC service, `arabizi-cli`, `config/engine.json`.
