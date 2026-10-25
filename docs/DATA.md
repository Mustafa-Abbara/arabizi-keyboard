# Data

How the project's data is stored and checked. The full datasheet (sources, licences, counts, biases) is added by issue #126 (roadmap P2 step 9). Spelling rules for the Arabic side: [SPELLING.md](SPELLING.md).

## Pair format

Every Arabizi → Arabic pair is one JSON object on one line in `data/pairs/*.jsonl`. The schema is [`data/schema/pair.schema.json`](../data/schema/pair.schema.json).

```json
{"id": "hw-0001", "arabizi": "ma 3ndi meeting today", "arabic": "ما عندي meeting today",
 "accepted": {}, "method": "hand", "writer": "moustafa", "checked_by": "moustafa-delayed",
 "source": "hand-written", "split": "test", "date": "2026-10-14"}
```

(Shown on two lines here; in the file it is one line.)

| Field | Meaning |
|---|---|
| `id` | Unique. Prefix by method: `hw` hand, `rv` rule_variant, `pb` public, `ai` ai_checked, then at least 4 digits. |
| `arabizi` | The Latin message exactly as typed. No Arabic letters. |
| `arabic` | The primary spelling, following SPELLING.md. No diacritics, no tatweel, Western digits only. |
| `accepted` | Row-specific accepted spellings: `{"primary text": ["variant", ...]}`. Every key must appear in `arabic`. Variants that apply to every row (SPELLING.md §8) live in [`data/rules/accepted_variants.json`](../data/rules/accepted_variants.json) instead. |
| `method` | `hand`, `rule_variant`, `public` or `ai_checked` ([ADR 0010](decisions/0010-phase1-pivot.md)). |
| `writer` | Who wrote the Arabizi: `moustafa`, a generator name, or the AI provider/model. |
| `checked_by` | Who checked it, e.g. `moustafa-delayed` (the ≥ 24 h self-check, [ADR 0011](decisions/0011-solo-build.md)); `null` until checked. |
| `source` | `hand-written`, the dataset name, the generator name, or the prompt file in `data/prompts/`. |
| `split` | `test`, `dev` or `train`. Must match the file. |
| `date` | Date written, `YYYY-MM-DD`. |
| `parent` | `rule_variant` only: the train row the variant was made from. |

### Files

| File | Holds |
|---|---|
| `data/pairs/test.jsonl` | Held-out test rows (243). Hand-written only. Frozen (P2 step 4); `testset-v1.1` since ADR 0028 made every row public. |
| `data/pairs/dev.jsonl` | Held-out dev rows for tuning (104). Hand-written only. |
| `data/pairs/train-hand.jsonl` | Hand-written training rows (6,681): 4,994 real messages by friends and family (ADR 0021) and 1,687 of Moustafa's own chat messages (ADR 0014, public since ADR 0028). |
| `data/pairs/others/test.jsonl`, `dev.jsonl`, `manifest.json` | The **"others" held-out set** (ADR 0021): 299 test + 200 dev real messages by other people, frozen as `others-v1.0`. Its own folder: training, variants and the main splits never read it; scored with `evalrun ... --others`. |
| `data/pairs/train-ai_checked.jsonl`, `train-public.jsonl` | Training rows from AI-drafted batches and licensed datasets. |
| `data/pairs/train-rule_variant.jsonl` | **Generated, not committed** (`.gitignore`): rule-made spelling variants of the training rows. Rebuild with `pairs variants`; the same seed gives the same file. |

### Rules checked automatically

`uv run --project eval pytest` (and `pairs validate`) fails when any of these break:

- the row matches the schema, its `split`/`method` match the file, and its id prefix matches the method;
- test and dev rows are hand-written; `ai_checked` rows have `checked_by`; `rule_variant` rows have a `parent` that is a train row;
- the Arabic has no diacritics, tatweel or Arabic-Indic digits, has Arabic letters, and the Arabizi has none;
- **every standalone number** in the Arabizi (`100$`, `2pm`, `10:30`, `2`) appears unchanged in the Arabic; digits inside words (`3am`, `7elo`, `la2`) are letters and are not checked;
- links, emails, `@mentions` and `#hashtags` are unchanged;
- ids are unique, no two held-out rows are the same sentence (the others set included), and **no train row repeats a test or dev sentence** (compared after normalising: Arabic with the lenient rules of SPELLING.md §10, Arabizi lowercased without punctuation).

## Sources and terms of service

Sources so far (the full datasheet comes with #126). Decisions: [ADR 0010](decisions/0010-phase1-pivot.md), [ADR 0012](decisions/0012-training-data-sources.md).

| Source | Rows | File | Method | Provenance |
|---|---|---|---|---|
| `claude-draft-revised-2026-10` | 500 | `train-ai_checked.jsonl` (ai-0001 – ai-0500) | `ai_checked`, train only | Drafted by Claude (Anthropic) on claude.ai, then revised and checked row by row by Moustafa (Oct 2026). Generation prompt not kept. On import, diacritics/tatweel were removed from 202 rows and the English translation column was dropped; nothing else was changed. |
| `claude-draft-revised-2026-10-batch02` | 500 | `train-ai_checked.jsonl` (ai-0501 – ai-1000) | `ai_checked`, train only | Same process as above (Claude draft, revised by Moustafa, prompt not kept). Diacritics/tatweel removed from 247 rows. |
| `claude-draft-revised-2026-10-batch03` | 500 | `train-ai_checked.jsonl` (ai-1001 – ai-1500) | `ai_checked`, train only | Same process. Diacritics/tatweel removed from 279 rows. |
| `claude-draft-revised-2026-10-batch04` | 500 | `train-ai_checked.jsonl` (ai-1501 – ai-2000) | `ai_checked`, train only | Same process. Diacritics/tatweel removed from 342 rows. |

### Real messages by friends and family ([ADR 0021](decisions/0021-real-rows-others-set.md))

5,500 rows (Arabizi with an Arabic-script spelling) added on 17 Oct 2026: real messages written by friends and family, published with their agreement (ADR 0021), every row checked. Imported with `pairs import-real`: 4,994 training rows (`writer: friends-and-family`, `source: friends-and-family (ADR 0021)`) and 499 rows for the others held-out set; 7 skipped (a number not kept as typed).

### Moustafa's own chats ([ADR 0014](decisions/0014-private-own-chat-data.md); public since [ADR 0028](decisions/0028-all-data-public.md))

**All 1,987 rows are public since 25 Oct 2026** (ADR 0028): `pairs publish-all` moved the 1,873 that were still private into the public files (source `own-chat-published`), after a scan for other people's details and a manual review. `data/private/` is empty of data now; the rest of this section records how the rows were handled while private.

| Source | Rows | Where | Split |
|---|---|---|---|
| `own-chats` (1 group chat, 2 private chats, 2023–2026) | 1,987 | `data/pairs/` (public since ADR 0028; was `data/private/pairs/`) | 210 test, 90 dev, 1,687 train (held-out drawn in proportion from each chat; 3 held-out removed before the freeze) |

- Only messages Moustafa wrote himself, with his own Arabic; imported with `pairs import-chats FILE --held-out 300` (diacritics/tatweel removed, nothing else changed; no message text is printed).
- Variants of these rows are written to `data/private/pairs/train-rule_variant.jsonl`; the public B0 dictionary ignores private rows.
- Limitation: held-out and training messages come from the same chats, so they share people, topics and habits.
- **Publishing some of them (before the freeze):** `pairs publish --sheet` writes `data/private/publish_review.xlsx` (never committed) to mark `y`/`n` in Numbers or Excel, which lay out Arabic correctly, and `pairs publish --apply data/private/publish_review.xlsx` applies it (plain `pairs publish` asks in the terminal instead, but many terminals cannot display Arabic). Approved rows (nothing personal: no names, places, other people or private details) move to the public `test.jsonl`/`dev.jsonl` with the same id, split, text, date and check, and `source: own-chat-published` (the chat label is never published). Declined rows are remembered in `data/private/publish_review.json` (never committed). Only held-out rows can be published; private training rows stay private. Why: 35 public test rows are too few for others to check results ([ADR 0014](decisions/0014-private-own-chat-data.md), amendment).

### Rule-made spelling variants

`uv run --project eval pairs variants` (default: 2 per training row, seed 2026) re-spells the **Arabizi** of every non-variant training row with alternatives real typists use, from [`data/rules/arabizi_variants.json`](../data/rules/arabizi_variants.json): `sh`↔`ch`, `7`→`h`, `kh`↔`5`, `gh`→`3'`, dropped `2`/`3`, vowel spellings (`ou`/`u`/`o`, `ee`/`i`, `ei`/`ay`/`e`), single for double consonants, `el`/`il`/`l`, `3am`↔`3m`, `bas`→`bs`, lowercase, and no punctuation (the Arabic then loses the matching ، ؟ too). The Arabic stays the same otherwise.

- **Never changed:** words kept in Latin in the Arabic (English, names like LAU), numbers, links, mentions, emoji.
- **Meaning guards:** no rule may change which word it is (no `bade`/`badda`); short words are skipped where a re-spelling is ambiguous (`min`/`meen`, `la2`/`la`, `3am`/`am`), and `7` never becomes `h` after `s k c g d t` (no `s7i7` → `shi7`). Tests: `eval/tests/test_variants.py`.
- First run (13 Oct 2026): 3,969 variants of 2,000 rows (27 rows had too few distinct re-spellings). Rows: `method: rule_variant`, `writer: arabizi_eval.variants v1`, `source: rule-variants-v1-seed2026`, `parent` = the original row, `checked_by: null` (deterministic, no row check, ADR 0012).
- **They do not count as non-AI data for the ADR 0010 cap:** a variant of an AI-drafted sentence is still that sentence. They add spelling robustness; P4 trains with and without them.

**Balance note:** all 2,000 training rows are `ai_checked`. ADR 0010 caps AI rows at half of the training set used in P4, so P4 needs at least as many rule-generated, hand-written or public rows (roadmap P2 steps 5–6), or the cap must be revisited in an ADR.

### Terms of service: Anthropic (Claude)

- **Clause** (Anthropic Consumer Terms, effective 8 Oct 2025, section 3 "Use of our Services", among prohibited uses): *"To develop any products or services that compete with our Services, including to develop or train any artificial intelligence or machine learning algorithms or models"*.
- **Reading** (13 Oct 2026): the prohibition covers training models for products or services that compete with Anthropic's. This project is a small, offline Arabizi → Arabic transliteration keyboard for macOS and does not compete with Claude, so training on these rows is allowed. This is the project's own reading, not legal advice.
- **Safeguard:** P4 trains with and without the `ai_checked` rows, so reported results never depend on them, and they can be removed if this reading is challenged.

## The test-set freeze (roadmap P2 step 4)

Before any fine-tuning, the held-out data is frozen so no later change can make results look better.

```bash
uv run --project eval pairs check --sheet   # delayed self-check of the held-out rows first (ADR 0011), in a spreadsheet
uv run --project eval pairs check --apply data/private/check_review.xlsx
uv run --project eval pairs freeze    # writes data/pairs/manifest.json (testset-v1.0)
```

- `manifest.json` records the SHA-256 and row count of `test.jsonl` and `dev.jsonl` (until ADR 0028 also of the private files, as a hash and a count only).
- After the freeze, `pairs validate` (and so the tests and CI) fails if a frozen file changes. Private files are checked where they exist (Moustafa's Mac); on CI and fresh clones they are skipped.
- After the freeze, `pairs add` and `pairs import` send new hand-written rows to training, and `pairs import-chats` refuses to hold rows out (`--held-out 0`).
- `pairs freeze` refuses while held-out rows are unchecked, unless `--allow-unchecked` (the count is recorded in the manifest).
- **A deliberate change** (e.g. a typo found in a test row) needs `pairs freeze --version testset-v1.1 --reason "..."` in a PR with the **`testset-change` label**; CI's `testset guard` fails a PR that changes the manifest without that label. Results before and after a change are not comparable; say so in EVAL.md.
- After the freeze PR is merged, tag the merge commit: `git tag testset-v1.0 && git push origin testset-v1.0`.

Design: **Recommendation** (14 Oct 2026), from roadmap P2 step 4.

### Freeze log

| Version | Date | Held-out rows | What happened before it |
|---|---|---|---|
| `testset-v1.0` | 16 Oct 2026 | 347: public 113 test + 48 dev, private 130 test + 56 dev; 0 unchecked | First freeze, before any fine-tuning. 111 of Moustafa's chat test/dev rows were made public with `pairs publish` (public test 35 → 113, ADR 0014 amendment); 3 unsuitable private held-out rows were removed (350 → 347); every row had the delayed self-check in a spreadsheet (`pairs check --sheet`), because the terminal could not display Arabic, which also corrected the Arabic of 3 public rows; the terminal checks of 15 Oct were discarded. |
| `others-v1.0` (separate set, `data/pairs/others/manifest.json`) | 17 Oct 2026 | 499: 299 test + 200 dev, public; 0 unchecked | First import of the others set (ADR 0021); `testset-v1.0` unchanged. |
| `others-v1.1` (separate set) | 17 Oct 2026 | 499, same rows and splits | SPELLING.md 4 applied: Arabic prefixes written apart from Latin words in 65 references (24 dev, 41 test), with `pairs split-prefixes --others` (ADR 0024). |
| `testset-v1.1` | 25 Oct 2026 | 347: 243 test + 104 dev, all public; 0 unchecked | The 130 private test and 56 private dev rows were made public with `pairs publish-all` (ADR 0028): the same rows and splits, no text changed, so results on v1.0 and v1.1 are comparable. |

## Writing pairs: the `pairs` tool

```bash
uv sync --project eval                 # once
uv run --project eval pairs add        # type pairs: Arabizi, then Arabic, then optional variants
uv run --project eval pairs import list.txt   # add a list: one 'arabizi | arabic' per line
uv run --project eval pairs import-batch F.jsonl --method ai_checked --writer W --checked-by C --source S
uv run --project eval pairs check --sheet   # delayed self-check (>= 24 h) in a spreadsheet; then --apply FILE
uv run --project eval pairs stats      # counts, progress towards the P2 targets, coverage
uv run --project eval pairs validate   # all checks above
```

- `add` fills in `id`, `writer`, `date` and `split`. Until the test set is frozen, rows go to **test and dev in a fixed 7:3 cycle**; after the freeze (`data/pairs/manifest.json` exists) they go to `train-hand.jsonl`. `--split` overrides this.
- It refuses a row that breaks a rule above or repeats an existing sentence, and warns (asks before saving) when `?` `,` `;` were left in Latin.
- `import` reads one pair per line: `arabizi | arabic`, optionally `| primary=variant; ...` (spaces around `|`; blank lines and `#` comments are skipped). Valid lines are saved in order with the same automatic ids and splits as `add`; lines that break a rule, repeat a sentence or leave `?` `,` `;` in Latin are **rejected and listed, never changed**. `--dry-run` checks without saving. Both sides must be written by a person: test and dev data are human-written (ADR 0010).
- `import-batch` adds **training** rows from a JSONL file with `arabizi` and `arabic` keys (other keys are ignored). It records `--method` (`ai_checked` or `public`), `--writer`, `--checked-by` and `--source`, removes diacritics and tatweel from the Arabic, and rejects anything else that breaks a rule. Add the source to the table above.
- Variants are typed as `primary=variant` separated by `;`, with `|` between several variants: `هلق=هلأ; إمتى=إيمتى`.
- Typing Arabic: add the **Arabic** input source in System Settings → Keyboard → Input Sources and switch with Ctrl+Space. The terminal may show Arabic right-to-left oddly (the app's terminal panel shows it unjoined and reversed); the saved text is still correct.
- **Self-check in a spreadsheet** (recommended, because terminals often cannot display Arabic): `pairs check --sheet` writes `data/private/check_review.xlsx` (never committed; it can hold private rows) with the unchecked test/dev rows written at least a day ago (`--train` adds hand-written training rows; generated variants are never offered). In Numbers or Excel, fix the `arabic` (and `accepted`, as `primary=variant; ...`) where needed and type `y` in `ok`; leave `ok` blank to check later; do not change the `arabizi`. Export as .xlsx and run `pairs check --apply data/private/check_review.xlsx`: rows that would break a rule, have a changed Arabizi or are too new are listed and not checked. The terminal check (`pairs check`) still works where Arabic displays properly.
- The 49 checks made on 15 Oct in the app's terminal (unreadable Arabic) were set aside unsaved and are redone with the spreadsheet.
