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
| `data/pairs/test.jsonl` | Held-out test rows. Hand-written only. Frozen at the end of W3 (P2 step 4). |
| `data/pairs/dev.jsonl` | Held-out dev rows for tuning. Hand-written only. |
| `data/pairs/train-hand.jsonl` | Hand-written training rows (after the freeze). |
| `data/pairs/train-rule_variant.jsonl`, `train-public.jsonl`, `train-ai_checked.jsonl` | Training rows from the other methods. |

### Rules checked automatically

`uv run --project eval pytest` (and `pairs validate`) fails when any of these break:

- the row matches the schema, its `split`/`method` match the file, and its id prefix matches the method;
- test and dev rows are hand-written; `ai_checked` rows have `checked_by`; `rule_variant` rows have a `parent` that is a train row;
- the Arabic has no diacritics, tatweel or Arabic-Indic digits, has Arabic letters, and the Arabizi has none;
- **every standalone number** in the Arabizi (`100$`, `2pm`, `10:30`, `2`) appears unchanged in the Arabic; digits inside words (`3am`, `7elo`, `la2`) are letters and are not checked;
- links, emails, `@mentions` and `#hashtags` are unchanged;
- ids are unique, no two held-out rows are the same sentence, and **no train row repeats a test or dev sentence** (compared after normalising: Arabic with the lenient rules of SPELLING.md §10, Arabizi lowercased without punctuation).

## Writing pairs: the `pairs` tool

```bash
uv sync --project eval                 # once
uv run --project eval pairs add        # type pairs: Arabizi, then Arabic, then optional variants
uv run --project eval pairs import list.txt   # add a list: one 'arabizi | arabic' per line
uv run --project eval pairs check      # delayed self-check of rows written before yesterday (>= 24 h)
uv run --project eval pairs stats      # counts, progress towards the P2 targets, coverage
uv run --project eval pairs validate   # all checks above
```

- `add` fills in `id`, `writer`, `date` and `split`. Until the test set is frozen, rows go to **test and dev in a fixed 7:3 cycle**; after the freeze (`data/pairs/manifest.json` exists) they go to `train-hand.jsonl`. `--split` overrides this.
- It refuses a row that breaks a rule above or repeats an existing sentence, and warns (asks before saving) when `?` `,` `;` were left in Latin.
- `import` reads one pair per line: `arabizi | arabic`, optionally `| primary=variant; ...` (spaces around `|`; blank lines and `#` comments are skipped). Valid lines are saved in order with the same automatic ids and splits as `add`; lines that break a rule, repeat a sentence or leave `?` `,` `;` in Latin are **rejected and listed, never changed**. `--dry-run` checks without saving. Both sides must be written by a person: test and dev data are human-written (ADR 0010).
- Variants are typed as `primary=variant` separated by `;`, with `|` between several variants: `هلق=هلأ; إمتى=إيمتى`.
- Typing Arabic: add the **Arabic** input source in System Settings → Keyboard → Input Sources and switch with Ctrl+Space. The terminal may show Arabic right-to-left oddly; the saved text is still correct (check with `pairs check`).
