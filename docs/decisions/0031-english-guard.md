# ADR 0031: Leave plain English alone, and repair by position

- **Status:** Accepted, 29 Oct 2026
- **Date:** 2026-10-29
- **Deciders:** Moustafa Abbara
- **Stage:** P5 (engine)

## Context

Latin letters are all the keyboard sees, so a sentence typed in English looks like Arabizi. The model keeps single English words inside an Arabizi sentence, but it was never trained on whole English sentences. Its answer for such a sentence often fails the output checks (new Latin words, ADR 0018), and the engine then falls back to the letter rules, which turn every word outside a short keep-Latin list into Arabic letters (`converting` → كونفرتينج).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | **`EnglishGuard` (ArabiziCore):** a text is plain English when it has at least 3 words, at least 2 and at least 40% of them common English function words (`data/rules/english_stopwords.json`), and nothing that looks like Arabizi: no digit inside a word (`3am`), no word of the rule dictionary that the training data does not also keep in Latin, no Arabic script. Links, emails, mentions and one-letter words are not counted. The engine returns such a text unchanged (`passthrough`, reason `english`) before the model or the rules run. | **Recommendation** |
| 2 | **The function words** are a short hand-written list. A word the training data converts to Arabic at least as often as it keeps it in Latin is left out (`she`, `be`, `may`, `he`, `am`, `into`, `a`, `we`, `an`, `had`, `much`, `say`: Arabizi for شي, بي, عم…); `eval/tests/test_english_stopwords.py` checks the list against the data. | **Recommendation** |
| 3 | **Repair by position:** when the model's answer has a word that cannot be traced to one input word (ADR 0023) and has as many words as the input, that word is replaced by the rule conversion of the input word in the same position, and the model's other words are kept. Before, the whole sentence went to the rules. | **Recommendation** |
| 4 | Mixed sentences are not changed: English words inside Arabizi are still the model's job. The guard only decides for sentences that are plain English. | **Recommendation** |

## Consequences

- **False alarms:** none in 46,000 real sentences (all training, dev and test rows, 2,000 other chat messages): no Arabizi sentence is left unchanged. The only hit was one generated variant that contains an unknown word (`hll'`).
- **Cost:** a pass over the words before the model; no model time for English text.
- **Limit:** English with an Arabizi-looking word in it (`ana`, `bas`) goes to the model as before. A two-word English phrase is not decided by the guard (3 words minimum).
- Dev accuracy is unchanged (no dev sentence is plain English); the position repair changes only answers that failed the check before.
