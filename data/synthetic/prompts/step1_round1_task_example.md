# Task file

This is one of six task files. Follow it as part of `RUN_ALL.md`. Do not ask anything.

You are an expert in Lebanese Arabic (the spoken dialect of Lebanon), in how Lebanese people really type it in Latin letters ("Arabizi"), and in its spelling in Arabic script. Create training pairs for a small model that converts Lebanese Arabizi chat messages into Lebanese Arabic script.

Each pair is: a chat message as a real Lebanese person would type it in Arabizi, and the same message in Lebanese Arabic script.

## Rule 1: be sure, or don't write it

- Use only words you are certain are real, current Lebanese words, with their meaning and their spelling in Arabic script under the convention below.
- If you are not sure of a word's meaning, its Lebanese usage or its Arabic spelling, do not use it. Write fewer pairs rather than one doubtful pair.
- A wrong pair teaches the model a mistake. A missing pair costs nothing.
- In "check", list every word a careful native speaker might spell differently or not know. Over-list rather than under-list.

## Rule 2: the Arabizi must look like real chat, not a textbook

Real Lebanese Arabizi is mostly lowercase, has little punctuation, drops vowels and spells the same word differently from person to person. Digits stand for letters: 2 = ء or ق (Lebanese pronounce most ق as a glottal stop), 3 = ع, 3' = غ, 5 = خ, 6 = ط, 7 = ح, and, varying by writer, 8 = غ or ق and 9 = ص or ق (less common). Emoji are common.

Vary the writer from pair to pair. Use each style about equally:

- A. heavy digits, short vowels dropped: "kifak 3am tshte8el lyom?"
- B. French-influenced: ch for ش, ou for و, é: "chou 3am ta3mlou?"
- C. long vowels written out, letters doubled for emphasis: "keefak, ktiiir mechta2lak"
- D. lots of English mixed in: "ma 3ndi meeting today, bas bukra fine"
- E. very short, few vowels, abbreviated: "wn? ana b l bet"

Do not make the Arabizi "correct" or consistent. Do not use the same spelling of a common word (kifak, shu, hek, bas) in every pair.

Real messages from the training data, written by Lebanese people (copy their feel, never their words or sentences):

- shefet ya zaleme ba3do houwe houwe  →  شفت يا زلمة، بعدو هوي هوي
- shu el ossa fe 7ada yfaser  →  شو القصة؟ في حدا يفسر
- ana nza3ajet w plz ma t2ele shu a3mol  →  أنا انزعجت و plz ما تقلي شو إعمول
- hay ba3atellik terwi2tik l mofaddali bas ma tekli ktir kermel ma tzidi ktir 😜  →  هي بعتلك ترويقتك المفضلة، بس ما تاكلي كتير كرمال ما تزيدي كتير 😜
- ya rabi dakhlak chu 3am bisirr  →  يا ربي دخلك شو عم بيصير
- w ente li 3am ta3mli shou esmo😏  →  وإنتي يلي عم تعملي شو إسمو😏
- walla te3tir chou be2yin na3mel bhal balad ma ba3ref  →  والله تعتير، شو باقيين نعمل بهالبلد ما بعرف
- 3anjad baladna ktir 7elwe bass l asaff cha3ba 5aless medidou😂😂  →  عنجد بلدنا كتير حلوة بس للأسف شعبا خالص مديدو😂😂
- eh khayye ma 3am besma3 el connection mesh mni7 hon 😎🙋🏽  →  إيه خيي ما عم بسمع، ال connection مش منيح هون 😎🙋🏽
- yalla shed hemtak badna nefra7 fik barke mnle2ilak shi 3arous hon sabaya yalla  →  يلا شد همتك، بدنا نفرح فيك، بركي منلاقيلك شي عروس هون، صبايا يلا
- saraha el mousalsal ma 3ejebne ma3 enno 3am ohdaro  →  صراحة المسلسل ما عجبني، مع إنو عم إحضرو
- shi 8areb walla be hayda balad 3m bser ashya mesh belbeel  →  شي غريب والله، بهيدا البلد عم بيصير أشيا مش بالبال
- lek kif mbayan bl soura ra7 tfer dam3a min 3ayno 7otolo chi soura 7elwe  →  لك كيف مبين بالصورة رح تفر دمعة من عينو، حطولو شي صورة حلوة
- shefta ken badi a3melek tag then medri shu ltahet nsit 😂  →  شفتا، كان بدي إعملك tag then مدري شو لتهيت نسيت 😂
- eh kman bya3rf yer2us mni7 msh 2alil😂😂  →  إيه كمان بيعرف يرقص منيح، مش قليل😂😂

## Rule 3: what the Arabic must do

- Same message: do not add, drop, translate or explain words. Each Arabizi word maps to its Arabic, except short words that attach to the next word (la mohammad = لمحمد; w el bet = والبيت).
- English or French words used as such ("meeting", "bro", "merci") stay in Latin letters, exactly as typed in the Arabizi. An English word with an Arabic prefix is split: the prefix in Arabic, a space, the English word (`el wifi` → ال wifi, `3am bcheck` → عم ب check).
- Punctuation: ? → ؟ and , → ، ; everything else as typed. Do not add punctuation that wasn't typed. Laughter (`hahaha`) → ههههه.
- Numbers, prices and times stay as typed, in Western digits ("3 pm", "100$"). Digits inside Arabizi words are letters: 3am = عم.
- Emoji stay exactly as typed, in the same place.
- Lebanese, never Modern Standard Arabic. These MSA words must not appear unless the message really uses them (MSA → Lebanese): ماذا → شو, لماذا → ليش, الآن → هلق, أين → وين, متى → إمتى, هذا → هيدا, هذه → هيدي, ذلك → هيداك, تلك → هيديك, سوف → رح, أريد → بدي, يريد → بدو, تريد → بدك, جيد → منيح, جدا → كتير, كثيرا → كتير, ليس → مش, لست → مش, هناك → في / هونيك, هنا → هون, فقط → بس, أيضا → كمان, عندما → لما, الذي → اللي, التي → اللي, الذين → اللي, لكن → بس, نعم → إيه, شكرا → مرسي / يسلمو, أعرف → بعرف, أذهب → روح
- No diacritics (harakat), no tatweel (ـ).

## Spelling convention for the Arabic (follow exactly)

The full guide follows. Follow sections 1 to 9 exactly. Sections 10 and 11 are about scoring and the human writing workflow; ignore them (in particular, section 11's "only your own words" is for human writers).

<spelling_guide>
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
</spelling_guide>

## What to write

300 pairs in 6 rounds of 50, 4 to 20 words each. Each round has its own kind and ids. Write a field "kind" in every line (inflect, low, new, common, context or traps).

### Round 1: ids A-T01-001 to A-T01-050

**Kind: low-frequency words.** These words appear only 1 to 3 times in the training data, so the model barely knows them:

ذنبي، الأبد، لعيوني، وقلم، بتحضري، عالبنك، كملت، غالبا، عقلو، تشيل، لتوصل، تتركو، بتحاول، بهالمطعم، وبشتغل، أكلو، وبتنام، وحامض، فهمتها، تلاقيني، بحدن، تختفي، أعلنوا، آسف، حبيناها، وبتكبرن، منين، لأشيا، تيم، سارو، بتقرر، يلعبلو، ويضل، إنارة، بنجاح، وجا، التاريخ، هالصوت، جاهلة، صيانة، هربوه، سجلا، السويد، أديش، ينبسط، تظبطوه، منتغير، الشمال، تتملكو، هادي، بدلك، قاسم، عالسطح، تركتو، ورفيقي، حالمين، ضعت، بيضوي، عصاية، عالدورة

Each pair uses one or two of them naturally, in the form listed or a natural variation. Use at least 40 different words from the list. Skip any word you are not sure of (a name, a typo, a word you don't know). Type them in varied, real Arabizi spellings. Put the list words you used in "rare_words".

### Round 2: ids A-T02-001 to A-T02-050

**Kind: low-frequency words.** These words appear only 1 to 3 times in the training data, so the model barely knows them:

تلخصو، كذابة، استعملت، الشاي، أيامنا، تزيدوا، أعصابنا، ركزي، بتاكلوا، أنواع، وخيك، وعن، طرزان، زوجين، مستغني، يحطوا، يفوتكن، يستلما، البيدر، قدوتو، سؤالك، يحمل، تاعت، وهضامة، معاشي، لطريق، بإنو، عراس، نطيت، تفليت، غيرني، خشب، عاشها، الشحنة، لموظف، اعمليلو، حسمنا، شدوا، خبرتني، بتؤمر، دانيال، كفيت، سبقنا، وماشي، أصلي، وبتبكي، صورلنا، بيركبوا، وخلي، السنان، بالفكرة، بشيب، يصمد، بتاخديلو، بالو، البلدي، بتتيسر، هبلة، طيوبة، ويضحكوا

Each pair uses one or two of them naturally, in the form listed or a natural variation. Use at least 40 different words from the list. Skip any word you are not sure of (a name, a typo, a word you don't know). Type them in varied, real Arabizi spellings. Put the list words you used in "rare_words".

### Round 3: ids A-T03-001 to A-T03-050

**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it hasn't seen:

عمو، بالكتاب، فايق، بيجوا، أوصل، هالسنة، يقولوا، عطول، وهيدي، عملوا، ليرة، تبعي، محطة، شوفا، وله، حاطين، مأخر، وبس، قديمة، يقعد، غيري، عاش، بعرفك، ثقة، تعادل، إجباري، إطلب، ببعتلك، وزغير، نار

Each pair uses one of these words in a form the training data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, another person or tense of a verb, or with attached و / بـ / لـ / الـ / عالـ. Use as many different words from the list as you can; skip any word you are not sure of (a name, a typo, a word you don't know). Put the new form in "rare_words". The form must not be in reference/known_words.tsv.

### Round 4: ids A-T04-001 to A-T04-050

**Kind: low-frequency words.** These words appear only 1 to 3 times in the training data, so the model barely knows them:

صداقة، تمثال، البيض، نكبر، بتعيش، اعرضلك، نسيوا، عقليا، تنقلوها، مهمين، بيعني، عمرن، حطا، والأخلاق، كذاب، زنخك، تحبنا، يتعادلو، السمكات، لصحابو، العواميد، وإجمع، وبيفيدك، رفعوا، نصلح، انقهرت، وأخدوا، وإيام، يشرحلي، صادق، نقلنا، شايفتن، طلبتو، عدد، بولادا، المطمر، وكانت، بنتك، جابك، وبطرقا، والميكانيك، فطار، بالصالون، يموتوا، تتعصر، الآخر، منلتقي، تعيس، تانيا، متصنعة، وإبكي، وبخلص، بتركيا، والبلدية، تبلشوا، حراك، نقرر، بتكمل، وفيقة، صباط

Each pair uses one or two of them naturally, in the form listed or a natural variation. Use at least 40 different words from the list. Skip any word you are not sure of (a name, a typo, a word you don't know). Type them in varied, real Arabizi spellings. Put the list words you used in "rare_words".

### Round 5: ids A-T05-001 to A-T05-050

**Kind: common words in unusual spellings.** These are frequent words the model knows, but it fails when they are typed in a spelling it hasn't seen:

الليلة، نام، بعدك، كان، عمي، إني، إنسى، غريب، عليي، إجا، تعملي، بكرا، الحلقة، جيب، بعد، معي، حالو، عارف، الواحد، تنسى، بشي، أكتر، بيمشي، وين، نشوف

Each pair uses two or more of them, typed in less common but real Arabizi spellings: aa or a for ع instead of 3; q, k or 2 for ق; 8 or gh for غ; 6 or t for ط; 5 or kh for خ; ch or sh for ش; ou or u for و; y, yy, ie or ye endings; doubled letters for emphasis; vowels dropped. At least one typed spelling per pair must not be in reference/known_arabizi.tsv. Only spellings real Lebanese people use; skip any listed word you are not sure of. Put the Arabic words whose spelling is unusual in "rare_words".

### Round 6: ids A-T06-001 to A-T06-050

**Kind: low-frequency words.** These words appear only 1 to 3 times in the training data, so the model barely knows them:

بيقلها، بمستوى، تقارنو، تزبيط، هالعجيبة، تتكبر، فاضيلك، بعدلي، ودليل، مبرر، متأملين، منندب، عمرها، تتأخر، سلمتا، مطبات، ومجلوق، يومها، نفتحلن، أوضتين، تترددوا، بيعطي، ببالي، المقال، عبعضا، بعتنالها، بايت، بنايات، بينلقى، مزعج، بيزهق، محروق، الأصوات، وطينا، بدبرا، حسبا، دقني، عنصر، كمادات، إخسر، نشيط، وبشعين، مهاب، حلقتك، عبودي، نيالكن، بتنصدق، بالفاتورة، بخرف، ومرة، ترجف، عسيارة، منطارة، فشرت، يعجق، الدولاب، ومعزومين، صوبكن، جارتي، مواعيد

Each pair uses one or two of them naturally, in the form listed or a natural variation. Use at least 40 different words from the list. Skip any word you are not sure of (a name, a typo, a word you don't know). Type them in varied, real Arabizi spellings. Put the list words you used in "rare_words".

In every round: every pair must differ in vocabulary and structure, with no templates, no repeated openings and no near-copies of any earlier pair or of the examples above. Use the styles A to E about equally. No real people's full names, phone numbers or private details; common first names only.

## Check your own work in every round

Do this checking silently: never write out drafts, reasoning, explanations or notes about your thinking, in the chat or in any file. The output files contain only the final pairs.

Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:

1. Is every Arabic word what the Arabizi word means in this sentence? (Watch la, men, w, b, l, ma.)
2. Nothing added, dropped, translated or explained?
3. Is every word a real, current Lebanese word, used the Lebanese way?
4. No standard Arabic (MSA) where Lebanese is spoken?
5. Spelling exactly by the guide (hamza, ة / ه, long vowels, the article, attached words)?
6. English, French, numbers, times and emoji exactly as typed?
7. Would a Lebanese person really type the Arabizi this way?
8. No diacritics, no tatweel?

Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.

## How to deliver

Save the pairs in **output/A_chat_1.jsonl**, appending each round as soon as it is checked, exactly as `RUN_ALL.md` says. Do not print the pairs in the chat.

## Line format

One JSON object per line, nothing else on the line:

{"id": "A-T01-001", "kind": "low", "style": "A", "arabizi": "...", "arabic": "...", "rare_words": ["..."], "check": ["<word>: <short reason>"]}

"style" is A to E. "check" lists every word a careful native speaker might spell differently or not know, each with a reason of at most five words (for example "rare word" or "hamza unsure"); it may be empty only if you have no doubt about any word.
