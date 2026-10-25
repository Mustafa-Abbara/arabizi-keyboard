# Spelling guide: Lebanese Arabizi → Lebanese Arabic script

This guide fixes **how the Arabic side of every data pair is written**, so the test set, the training data and the model all agree. Read it before writing any pair, and re-read it during the delayed self-check (roadmap P2, [ADR 0011](decisions/0011-solo-build.md)).

> **Status: v1.3, 17 Oct 2026.** v1.3: Section 4's split rule for an English word with an Arabic prefix (`ال video`, never `الvideo`) re-confirmed and applied to the real rows and the others set, which had glued them (ADR 0024). v1.2: the "her" ending (ـا / ـها) and `3a` before a word (ع جونيه / عجونيه) are correct both ways, and the scorer accepts both (EVAL.md). v1.1: `eza`/`iza` is written **إذا** (a special word), إزا accepted. v1.0 (12 Oct 2026): drafted from the roadmap (P2 step 1) and common Lebanese chat spelling; all nine choices marked **[confirm]** were confirmed (Section 9). Changing a rule means fixing every existing pair, so bump the version and say why in the PR.

---

## 1. The one principle

**Write what a Lebanese person would type in Arabic script on WhatsApp**: Lebanese words, Lebanese pronunciation where Lebanese people write it that way, and no MSA. When two spellings are both common, pick **one primary spelling** (listed in this guide) and record the other in the row's `accepted` list.

| ✅ Lebanese | ❌ Not this (MSA) |
|---|---|
| شو بدك؟ | ماذا تريد؟ |
| هلق أنا بالبيت | الآن أنا في البيت |
| كتير منيح | جيد جداً |
| ما بعرف | لا أعرف |

The Arabic side is the **intended** sentence. If the Arabizi has a typo (`kifkak`), the Arabic is still the intended word (`كيفك`).

---

## 2. Letters

### Digits used as letters

A digit **inside or attached to a word** is a letter. A digit standing alone (or as part of a number) stays a number (Section 6).

| Arabizi | Arabic | Example |
|---|---|---|
| `2` | ء / أ / إ, or ق (see 2.2) | `la2` → لأ, `2alb` → قلب |
| `3` | ع | `3am` → عم |
| `3'`, `gh` | غ | `ghayr` → غير |
| `5`, `kh` | خ | `5alas` → خلص |
| `7` | ح | `7abibi` → حبيبي |
| `6` | ط | `6ayyeb` → طيب |
| `9` | ص (rare in Lebanon) | `9a7` → صح |
| `8` | ق (rare) | `8alb` → قلب |

### Letter groups

| Arabizi | Arabic | Notes |
|---|---|---|
| `sh`, `ch` | ش | `shu`, `chou` → شو |
| `s` | س or ص | Pick by the word: `sa7` → صح, `sa3a` → ساعة |
| `t` | ت or ط | `ta3ban` → تعبان, `tayyeb` → طيب |
| `d` | د or ض | `dahar` → ضهر |
| `z` | ز or ظ | `zaher` → ظاهر (MSA-origin words keep ظ) |
| `j`, `g` | ج | `jem3a` → جامعة |
| `w`, `ou`, `oo`, `u` | و | `ween` → وين |
| `y`, `ee`, `i`, `ay`, `ei` | ي | `bayt`, `beit` → بيت |

### 2.1 Sounds Lebanese pronounce differently [confirm]

Write them the way Lebanese people **say and type** them, not the MSA letter:

| Sound | Write | Example |
|---|---|---|
| ث pronounced t | ت | `tleteh` → تلاتة, `ktir` → كتير |
| ذ pronounced d | د | `hayda` → هيدا, `dahab` → دهب |
| ذ pronounced z | ز | `zaki` → ذكي keeps ذ; but `iza`/`eza` → **إذا** (a special word; إزا accepted) |
| ظ pronounced d | ض | `dahar` → ضهر |

Rule of thumb: everyday Lebanese words follow the pronunciation (تلاتة، هيدا، كتير); learned or MSA-origin words keep their letter even when said with s or z (ثورة، مثلاً، ذكي).

### 2.2 The glottal stop (`2`) [confirm]

Lebanese pronounce most ق as a glottal stop, typed `2`. The rule:

- **Etymological ق is written ق**: `2alb` → قلب, `2elt` → قلت, `2ahwe` → قهوة. Accepted variant: the أ spelling (أهوة) only for the words listed in Section 8.
- **A real hamza is written with hamza**: `la2` → لأ, `2ana` → أنا, `so2al` → سؤال.

### 2.3 Vowels

- **Short vowels are not written** and no diacritics (no ـَ ـُ ـِ ـّ): `ktir` → كتير, `3ndi` → عندي.
- **Long vowels are written** with ا و ي: `bayt` → بيت, `rou7` → روح, `kteb` → كتاب.
- **Initial vowel**: أ for `a`/`o` (`ana` → أنا), إ for `e`/`i` (`enta` → إنت, `eza` → إذا).
- **Final `-e`/`-a` on a feminine noun or adjective**: ة: `7elwe` → حلوة, `sa3a` → ساعة, `kbire` → كبيرة. **[confirm]** (ه is common too; scoring treats ة/ه as equal in the lenient metric, Section 10.)
- **Final `-e` meaning "my"**: ي: `bade` → بدي, `beite` → بيتي.
- **Final `-a`/`-e` in other words**: ا or ي as Lebanese write them: `hayda` → هيدا, `hayde` → هيدي, `bukra` → بكرا, `emta` → إمتى.
- **Elongation for emphasis**: repeat the letter as often as typed: `ktiiiir` → كتيييير, `yaaa` → يااا.

---

## 3. Small words and attached letters

These decide most of the hard cases (the "la mohammad" problem).

| Arabizi | Arabic | Rule |
|---|---|---|
| `w` (and) | و **attached** to the next word | `w enta?` → وإنت؟ |
| `b` / `bi` / `be` (in, with) | بـ **attached** | `bel beit` → بالبيت, `b Beirut` → ببيروت |
| `b` (verb prefix) | بـ **attached** | `b7ebak` → بحبك, `ba3ref` → بعرف |
| `la` (to, for) + noun/name | لـ **attached** | `la mohammad` → لمحمد, `la ekhte` → لأختي |
| `la` (no) | لا **separate** | `la la` → لا لا (rare in Lebanese; the usual "no" is `la2` → لأ) |
| `la2ennu` / `la2anno` (because) | لأنو | |
| `3al` (on/to the) | عالـ **attached** | `3al beit` → عالبيت |
| `3a` (on/to) + word without "the" | ع separate **or** attached, both correct (v1.2) | `3a Jounieh` → ع جونيه / عجونيه |
| `ma` (not) | ما **separate** | `ma ba3ref` → ما بعرف |
| `ma3` (with) | مع **separate** | `ma3ak` → معك |
| `mish` / `mesh` / `msh` | مش **separate** | `mesh 3aref` → مش عارف |
| `3am` (progressive) | عم **separate** | `3am ekol` → عم آكل |
| `ra7` (will) | رح **separate** | `ra7 ruh` → رح روح |
| `ta` (in order to) | تـ **attached** [confirm] | `ta shoufak` → تشوفك (accepted: تا شوفك) |
| `el` / `il` / `l` (the) | الـ **attached**; do not double sun letters | `el shams`, `esh shams` → الشمس |
| `fi` (there is / in) | في **separate** | `fi shi?` → في شي؟ |

**Pronoun endings:**

| Arabizi | Arabic | Example |
|---|---|---|
| `-ak` (your, m.) | ـك | `kifak` → كيفك |
| `-ik` (your, f.) | ـك | `kifik` → كيفك |
| `-o` / `-u` (his) | ـو | `beto` → بيتو, `2eltello` → قلتلو |
| `-a` (her) | ـا **or** ـها, both correct (v1.2) | `beta` → بيتا / بيتها |
| `-kon` / `-kun` (your, pl.) | ـكن | `kifkon` → كيفكن |
| `-on` / `-un` (their) | ـن | `bayton` → بيتن |
| `-na` (our) | ـنا | `baytna` → بيتنا |

---

## 4. English, French and other Latin words

- **Non-Arabic words stay in Latin exactly as typed**, including capitalisation: `ma 3ndi meeting today` → ما عندي meeting today, `merci` → merci, `bonjour` → bonjour, `sorry` → sorry, `ok` → ok, `lol` → lol.
- **Exception: a loanword with Arabic grammar on it** is written in Arabic: `talfanetlak` → تلفنتلك, `masajtak` → مسجتك.
- **English word with an Arabic prefix** (`bstudy`, `3am bcheck`, `el meeting`) [confirmed again in v1.3, ADR 0024]: write the Arabic prefix in Arabic, **separated by a space**, and keep the English word: `3am bcheck` → عم ب check, `el wifi mesh 3am yemshi` → ال wifi مش عم يمشي. Do not mix scripts inside one token.
- **Brand and app names** stay Latin: Netflix, Instagram, WhatsApp, Uber.
- **People's names:** Arabic names in Arabic (`mohammad` → محمد, `rami` → رامي, `nour` → نور); non-Arabic names stay Latin (`Chris`, `Joelle`). **Places in Lebanon** in Arabic (`beirut` → بيروت, `hamra` → الحمرا, `jounieh` → جونيه); places abroad in Arabic if Lebanese say them in Arabic (`dubai` → دبي, `paris` → باريس), otherwise Latin.

---

## 5. Laughter, interjections, emoji

| Arabizi | Arabic |
|---|---|
| `hahaha`, `hhhh` | ههههه (same number of ه as typed laughs, at least 3) [confirm] |
| `lol`, `lmao` | stays Latin |
| `yalla` | يلا |
| `ya3ne` / `ya3ni` | يعني |
| `wallah` / `walla` | والله |
| `inshallah` | إن شاء الله |
| `mashallah` | ما شاء الله |
| emoji, `:)`, `<3` | unchanged |

---

## 6. Numbers, links, symbols

- **Standalone numbers stay as typed, in Western digits**: `100$`, `$100`, `2pm`, `5k`, `10:30`, `2026`. Never write Arabic-Indic digits (٠١٢٣).
- A number next to a Lebanese word is still a number when it means a quantity: `ba3d 2 se3at` → بعد 2 ساعات.
- **Links, emails, `@mentions`, `#hashtags`**: unchanged.

---

## 7. Punctuation [confirm]

| Typed | Written |
|---|---|
| `?` | ؟ |
| `,` | ، |
| `;` | ؛ |
| `.` `!` `:` `"` `(` `)` | unchanged |

Spacing stays as typed. Do not add punctuation that was not typed.

---

## 8. Word list (primary spelling + accepted variants)

The most frequent words. Add a word here the first time you are unsure about it, so later pairs stay consistent.

| Arabizi (common forms) | Primary | Also accepted |
|---|---|---|
| shu, shou, chou | شو | |
| kif, keef | كيف | |
| kifak, kifik | كيفك | |
| hayda / hayde / hawde | هيدا / هيدي / هودي | |
| hek, heik | هيك | |
| hon / honik | هون / هونيك | |
| halla2, halla | هلق | هلأ |
| bade, baddak, baddik | بدي، بدك | |
| ktir, kteer | كتير | |
| mni7, mnee7 | منيح | |
| la2 | لأ | |
| eh, ee | إيه | |
| lesh, leh | ليش | |
| wen, ween | وين | |
| min | مين | |
| emta, aymta | إمتى | إيمتى |
| addesh, 2addesh | قديش | أديش |
| bukra, bokra | بكرا | |
| mbere7 | مبارح | |
| ba3den, ba3dein | بعدين | |
| 3anjad, 3an jad | عنجد | عن جد |
| shi | شي | |
| kamen | كمان | |
| 2ahwe | قهوة | أهوة |
| 2al(lo), 2elt | قال، قلت | أل، ألت |
| tayyeb, 6ayyeb | طيب | |
| sa7, s7 | صح | |
| khalas, 5alas | خلص | |
| iza, eza | إذا | إزا |
| la2ennu, la2anno | لأنو | |
| ennu, enno | إنو | |

---

## 9. Confirmed decisions

| # | Rule | Decision (confirmed) | Alternative (not chosen) |
|---|---|---|---|
| 1 | ث/ذ/ظ in everyday words (2.1) | Pronunciation (تلاتة، هيدا، ضهر) | Always the MSA letter (ثلاثة، هذا) |
| 2 | Glottal-stop ق (2.2) | ق (قلب، قهوة), أ accepted for listed words | أ (ألب، أهوة) |
| 3 | Feminine ending (2.3) | ة (حلوة) | ه (حلوه) |
| 4 | "her" ending (3) | **v1.2: both ـا and ـها are correct** (both are used) | — |
| 5 | `ta` + verb (3) | attached (تشوفك) | separate (تا شوفك) |
| 6 | English word with Arabic prefix (4) | prefix in Arabic + space (عم ب check) | whole token Latin (bcheck) |
| 7 | Laughter (5) | ههههه | keep Latin (hahaha) |
| 8 | Punctuation (7) | Arabic ؟ ، ؛ | keep Latin ? , ; |
| 9 | `3a` before a word without "the" (3) | **v1.2: separate or attached, both correct** | — |

All nine defaults were recommendations and were **confirmed on 12 Oct 2026**. The "Alternative" column is kept for the record.

---

## 10. How this guide is used in scoring (for P3)

- **Always removed before scoring**: diacritics, tatweel (ـ), and extra spaces.
- **Strict word accuracy**: the output word must equal the primary spelling or one listed in the row's `accepted`.
- **Lenient word accuracy** (reported next to strict) also treats these as equal: أ / إ / آ / ا, final ى / ي, and final ة / ه. This shows how many errors are only spelling conventions rather than wrong words.

---

## 11. Writing a pair: checklist

1. Write the **Arabizi first**, the way you really type in WhatsApp. Do not clean it up.
2. Write the Arabic following this guide. If a word is not covered, decide, then **add it to Section 8**.
3. One message per row, about **2–25 words**.
4. **Only your own words.** Never copy messages written by other people (they would be outside participants, A8), and leave out anything private (real addresses, phone numbers, health details).
5. Mix topics: plans, money, family, work, food, university, greetings, complaints, jokes. About a third of rows should include English or French, names, numbers or prices, and about a fifth should contain a hard small word from Section 3 (`la`, `ma`, `3a`, `b`, `w`).
6. **Delayed self-check** (≥ 24 hours later): re-read each pair against this guide, fix it, and set `checked_by` to `moustafa-delayed`.
