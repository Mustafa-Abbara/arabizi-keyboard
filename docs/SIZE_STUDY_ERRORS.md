# What Qwen3-0.6B gets wrong (size study, 18 Nov 2026)

Every word Qwen3-0.6B Q4 (`arabizi-qwen3-0.6b-v1`, trained on v4's recipe and data) gets wrong, against v4 (`arabizi-llama3.2-1b-v4`), on all five scored sets. It decided the round 6 prompts (`data/synthetic/prompts/build_step3_packs.py`).

**Method.**
- A word is wrong when the scorer counts it wrong: it is left out of the best match between the output and the reference. The scorer's accepted spellings count as right, as in EVAL.md (ـا / ـها, ع attached or not, هلق / هلأ…).
- Each wrong word is then sorted the way [MODEL_V4.md](MODEL_V4.md) sorted v3's errors: by how often the expected word appears in the training data both models learned from.
- Slips that show in the output form their own kinds: a plural ending, stretched letters, words joined or split, who is speaking, one similar letter, and letters from another script.
- Runs used: keyboard deadline. The dev sets were run on 16 Nov (v4) and 18 Nov (Qwen). The real chats were rescored for v4 on 18 Nov. The comparison and synthetic test outputs are the saved ones.

## Totals

| Set | Words | v4 wrong | Qwen wrong |
|---|---|---|---|
| Comparison set (300) | 2,316 | 211 | 234 |
| Real chats (1,642) | 8,760 | 736 | 833 |
| Others dev (200) | 2,187 | 330 | 386 |
| Frozen dev (104) | 665 | 97 | 100 |
| Synthetic test | 17,278 | 1,808 | 1,823 |

## Where Qwen's extra errors come from

These counts cover the four real-typing sets together: comparison, real chats, others dev and frozen dev.

| The expected word… | v4 wrong | Qwen wrong | Qwen − v4 | Share of Qwen's extra errors |
|---|---|---|---|---|
| is a common word, misread | 503 | 540 | +37 | 20% |
| is a new form of a known word | 163 | 198 | +35 | 19% |
| was seen only 1–3 times | 102 | 132 | +30 | 16% |
| was typed glued to, or split from, its neighbour | 55 | 73 | +18 | 10% |
| has stretched letters | 36 | 53 | +17 | 9% |
| was never seen, in any form | 88 | 105 | +17 | 9% |
| has a plural ending (و / وا) | 29 | 45 | +16 | 8% |
| depends on who is speaking (إنتي / إنت, كنت / كانت) | 43 | 53 | +10 | 5% |
| is English or French, not kept in Latin | 70 | 77 | +7 | 4% |
| came out in another script (Chinese, Cyrillic) | 0 | 2 | +2 | 1% |
| was seen 4–10 times | 113 | 113 | 0 | |
| differs by one similar letter (س/ص, ت/ط, ة/ه) | 170 | 161 | −9 | |

### Inside the misread words

These are the words that were common, rare, never seen, or new forms. Each is sorted by what went wrong between the expected word and Qwen's word.

| What went wrong | Real-typing sets | Synthetic test |
|---|---|---|
| One typed word became several, or several became one | 27% | 19% |
| A misspelled or invented word (mostly rare words) | 23% | 28% |
| A long vowel added or dropped (بعد / بعيد, طول / طويل, مصري / مصاري) | 19% | 33% |
| Another real, common word (context or spelling read wrong) | 12% | 11% |
| A dialect word swapped (ليش / ليه, هاي / هي, يلي / اللي) | 7% | 1% |
| A participle against a verb (فاهم / فهمت, عارف, ماشي) | 5% | 5% |
| The article added, dropped or changed (السنة / سنة) | 3% | 1% |

## By kind of message

Each figure is the gap in word accuracy, in points (Qwen − v4).

| Kind of message | Comparison | Real chats | Others dev | Frozen dev | Synthetic |
|---|---|---|---|---|---|
| Stretched letters | −2.1 | −1.0 | **−9.5** | −5.0 | −1.2 |
| English or French words in it | −1.0 | −0.6 | **−5.0** | +0.5 | +0.3 |
| Vowelless words (msh, bs, ktr) | −2.2 | −1.8 | **−4.1** | −3.7 | 0.0 |
| Long (15+ words) | −1.3 | −1.3 | **−3.7** | −7.1 | +2.6 |
| French-style spelling (ch, ou) | −1.4 | −0.4 | −2.9 | −2.3 | +0.6 |
| Digits for خ / غ / ق (5, 8, 9) | **−2.9** | **−2.3** | 0.0 | −1.7 | +0.5 |
| Short (≤5 words) | −1.2 | −1.4 | | 0.0 | −0.9 |
| All | −1.0 | −1.1 | −2.6 | −0.5 | −0.2 |

**How the training data compares:**
- Only 12% of training messages have 15+ words, against 26% in others dev. Only 0.2% have 25+ words.
- 3% have stretched letters, against 9% in others dev.

## Examples

- **English kept in Latin:** `agressif` → أجرسيف, `regime` → رجيمة, `nutella` → النوتلا, `tatra w nido` → تطاطر ونضوي.
- **Long message lost halfway:** `ne7na b2frica … sarna chaher 3hl 7ale` → بقفريكا … سرنا … عهل حالي.
- **Glued typing:** `3ambitarjem` → من العمبرومين, where the expected words are عم بيترجم.
- **Long vowels:** `ba3ed` → بعيد instead of بعد, `masri` → المصاري instead of المصري.
- **Who is speaking:** `kenet` → كانت where كنت was meant, 16 times, and the other way round 13 times.
- **Another script:** `lmodel` → الم模型, `oussalik` → إس出了ك. This happened 6 times in all.

## What the prompts cannot fix, and what was done instead ([ADR 0040](decisions/0040-spelling-v2.md))

- **Letters from another script.** The engine now rejects letters outside Arabic and Latin that were not typed, and the rules answer instead (`OutputChecks.otherScript`).
- **Inconsistent references.** Spelling v2.0 settled the conventions, and every row was converted:
  - `leh` → ليه, `lesh` → ليش, `hay` → هي;
  - أ and إ are written ا;
  - a verb's plural ending is و.

  Some disagreements remain, and are left to the data checks: `kenet` is كانت or كنت by meaning, and `elli` is اللي where `yalli` is يلي.
- **Round 6 also has two kinds for errors where Qwen is no worse than v4 but still often wrong:**
  - `letters`: ط ص ض ظ ث ذ typed plain, and the v2.0 endings;
  - `mid`: words seen 4 to 10 times.
