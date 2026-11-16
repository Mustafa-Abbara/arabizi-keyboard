# Task file (round 5)

This is one of six task files. Follow it as part of `RUN_ALL_5.md`. Do not ask anything.

You are an expert in Lebanese Arabic (the spoken dialect of Lebanon), in how Lebanese people really type it in Latin letters ("Arabizi") on their phones, and in its spelling in Arabic script. Create training pairs for a small model that converts Lebanese Arabizi chat messages into Lebanese Arabic script.

Each pair is: a chat message exactly as a real Lebanese person would type it in Arabizi, and the same message in Lebanese Arabic script.

The model has been trained once already. It now handles short, tidy messages well. It still fails on **real chat**: longer, messier messages, common words whose meaning depends on the sentence, the letters ط ص ض ظ typed as plain t s d z, English and French words that must stay in Latin, and rare words or word forms. This round targets exactly those.

## Rule 1: be sure, or don't write it

- Use only words you are certain are real, current Lebanese words, with their meaning and their spelling in Arabic script under the convention below.
- If you are not sure of a word's meaning, its Lebanese usage or its Arabic spelling, do not use it. Write fewer pairs rather than one doubtful pair.
- A wrong pair teaches the model a mistake. A missing pair costs nothing.
- In "check", list every word a careful native speaker might spell differently or not know, each with a reason of at most five words. Over-list rather than under-list.
- Do the checking silently: never write out drafts, reasoning or explanations, in the chat or in any file.

## Rule 2: the Arabizi must look like real phone chat (this round is strict about it)

Measured on real messages, Lebanese chat differs from tidy synthetic text in these ways. Match them:

| Feature | Real chat | What to do |
|---|---|---|
| Length | about 10 to 11 words per message | write **8 to 25 words** per message, about 12 on average; a few up to 30 |
| Emoji | in about **1 message in 5** | put emoji in about 1 pair in 5, usually at the end, often repeated (😂😂😂), sometimes glued to the last word |
| Ending punctuation | almost never | **do not end messages with . ? or !**; commas are rare too |
| Dropped vowels | about 1 word in 20 | drop vowels in some words as people do: msh, bs, kfk, 3ndi, shwy, ktr, mnh, mbrh, hl2 |
| ط ص ض ظ | typed with plain **t, s, d, z** (never 6 or 9) | write them with t, s, d, z: tayeb, sa7, da3, zaher, ta2s, sabi. **Never use the digits 6 or 9.** |
| Digits as letters | 2 = ء/ق, 3 = ع, 5 = خ, 7 = ح, sometimes 8 = غ | use these, inconsistently, as people do (3am, 5alas, 7elo, 2alb, 8ali or ghali) |
| Mixing | about 1 message in 3 mixes English or French | mix in English or French words and short phrases naturally |
| Letters | no accented letters | write French words without accents (chevre, cafe, a demain) |

Also: mostly lowercase (a message may start with a capital letter, as phones do), long vowels sometimes written out (kteer, ktiir) and sometimes not (ktr), letters doubled for emphasis now and then (yalllaaa), laughter as hahaha or hhhh. Spell the same word differently from one pair to the next. Do not make the Arabizi neat or consistent.

Real messages from the training data (copy their feel, never their words or sentences):

- hala2 bada ba3ed cheghel la tousalik bas fi 3enda base😂😂😂  →  هلق بدا بعد شغل ل توصلك، بس في عندا base😂😂😂
- mich bas hek w bitdala on a diet w quinoa salad w midre chou😜  →  مش بس هيك، وبتضلا on a diet و quinoa salad ومدري شو😜
- la2 hyda howe zeto bas kilo trab w wa7el 😅😂  →  لأ هيدا هوي ذاتو بس كلو تراب ووحل 😅😂
- wahahahahaha mni7a hek btjbroune bl raked 😜 bas bade ta3toune chocolat 😂  →  wahahahahaha منيحة هيك، بتجبروني بالركض 😜 بس بدي تعطوني chocolat 😂
- michen hek belbous shorts ana w 3am be7dar foot 😂😂😂  →  مشان هيك بلبس shorts أنا وعم بحضر foot 😂😂😂
- hay ana kter shatra feha bas bel hareebe msh bel dabke 😂😂😂  →  هي أنا كتير شاطرة فيها، بس بالهريبة مش بالدبكة 😂😂😂
- lek esa ma mere2 abyakh men hek wala 3eb y2admu hek baramej 😢  →  لك هلق ما مرق أبيخ من هيك، ولا عيب يقدموا هيك برامج 😢
- 2nti 3am te7lami aw 3am te7ki 3a shi balad teni😅  →  إنتي عم تحلمي أو عم تحكي ع شي بلد تاني😅
- ana mjarrebta b 8er ekel bas ma bezkor b chu btkheyal ya ekhte lmukhayele wes3a 😂😂😂  →  أنا مجربتا بغير أكل بس ما بذكر بشو، بتخيل يا أختي، المخيلة واسعة 😂😂😂
- bass abel ken 3ndak ousloub ahla bel enti2ad w heke eno hala2 chwey 3am betzida bass at all 👍  →  بس قبل كان عندك أسلوب أحلى بالانتقاد والحكي، إنو هلق شوي عم بتزيدها، بس at all 👍
- ah walla ba3do shab fakkarto akbar mn hek walla badna nt3arraf 3ale 😁  →  آه والله بعدو شب، فكرتو أكبر من هيك، والله بدنا نتعرف عليه 😁
- ken bade a3melek tag elt hala2 btbahdelne 3al music 😂  →  كان بدي إعملك tag، قلت هلق بتبهدلني عال music 😂
- 5alas ta3o chez ns fi ktir ouwad w l beb baddo jerrafe ta yenfata7 😂  →  خلص تعوا chez ns، في كتير أوض والباب بدو جرافة ت ينفتح 😂
- 😂 3a shway rah a3melak tag 3a kel l videos shu bade a3ml ana l wuality tv bte2telne 😂  →  😂 عشوي رح إعملك tag عكل ال videos، شو بدي إعمل أنا، ال quality tv بتقتلني 😂
- lak shu el ossa kel el 3alam 3am ta3mele tag walah mesh bi 7aje la etzakar 😂kel yom el 3alam betzakerne 😂  →  لك شو القصة؟ كل العالم عم تعملي tag، والله مش بحاجة إتذكر 😂 كل يوم العالم بتذكرني 😂

## Rule 3: what the Arabic must do

- Same message: do not add, drop, translate or explain words. Each Arabizi word maps to its Arabic, except short words that attach to the next word (la mohammad = لمحمد; w el bet = والبيت).
- English or French words used as such ("meeting", "school", "merci", "chevre") stay in Latin letters, exactly as typed. An English word with an Arabic prefix is split: the prefix in Arabic, a space, the English word (`el wifi` → ال wifi, `3am bcheck` → عم ب check). A loanword with Arabic grammar on it is written in Arabic (`talfanetlak` → تلفنتلك).
- Numbers, prices and times stay as typed, in Western digits. Digits inside Arabizi words are letters.
- Emoji stay exactly as typed, in the same place.
- Punctuation: ? → ؟ and , → ، ; nothing added that wasn't typed. Laughter (`hahaha`) → ههههه.
- Lebanese, never Modern Standard Arabic. These MSA words must not appear unless the message really uses them (MSA → Lebanese): ماذا → شو, لماذا → ليش, الآن → هلق, أين → وين, متى → إمتى, هذا → هيدا, هذه → هيدي, ذلك → هيداك, تلك → هيديك, سوف → رح, أريد → بدي, يريد → بدو, تريد → بدك, جيد → منيح, جدا → كتير, كثيرا → كتير, ليس → مش, لست → مش, هناك → في / هونيك, هنا → هون, فقط → بس, أيضا → كمان, عندما → لما, الذي → اللي, التي → اللي, الذين → اللي, لكن → بس, نعم → إيه, شكرا → مرسي / يسلمو, أعرف → بعرف, أذهب → روح
- No diacritics (harakat), no tatweel (ـ).

## Spelling convention for the Arabic (follow exactly)

Follow sections 1 to 9 exactly. Sections 10 and 11 are about scoring and the human writing workflow; ignore them. Note: the guide's table lists 6 and 9 as letters because some people use them; in this round's Arabizi, do not use them (Rule 2).

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

300 pairs in 6 rounds of 50. Each round has its own kind and ids. Write a field "kind" in every line (context, heavy, latin, inflect, low or new). Every pair follows Rule 2 (real phone chat).

### Round 1: ids A5-T01-001 to A5-T01-050

**Kind: words that need the sentence to decide.** Long messages (12 to 25 words) about family plans and visits, in which common words must be read from the sentence: la (لا / لـ), ma3 (مع), wala (ولا / والله), men / min (من / مين), 3amel / 3emel (عامل / عمل), ma (ما), fi / fiye (في / فيي), w, b, l, 3a / 3al, hek (هيك), ba3d (بعد / بعض). Each pair has at least two of them, placed where the wrong reading is tempting (for example `la` as لا "no" versus لـ "to", `wala` as ولا versus والله, `3amel` as عامل versus عمل). Put those words' Arabic in "rare_words".

### Round 2: ids A5-T02-001 to A5-T02-050

**Kind: heavy letters typed as plain letters.** These words contain ط ص ض ظ:

نعطي، يعطيه، تصبحوا، زبط، هالضجة، للصور، صيفنا، عطيها، واصلة، الضمان، بتحط، توصلني، قطفنا، طويلة، الضيافة، قصدي، حضور، يطور، قطعتي، هالصيف، خطر، عطيت، بالضهر، الظروف، بالطيارة، منطق، مطرح، الطابة، قطع، صرلنا

Each pair uses one or two of them, typed with plain t, s, d, z (never 6 or 9), in a real-chat message of 10 to 25 words. Use at least 25 different words from the list; skip any you are not sure of. Put the list words you used in "rare_words".

### Round 3: ids A5-T03-001 to A5-T03-050

**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it hasn't seen:

تعديلك، والحارة، زغارنا، هالطاولة، تحب، مفلس، الجرسون، سخيفات، بنتين، الشوارع، بتختصر، أحسنلا، إصابة، مستعجلة، المرتين، إمها، عجبت، بهالمواضيع، بتحملا، بالغير، لئيمة، كلي، الخطوبة، وسألني، خبرها، عملتيلا، بساعدكن، رصاص، الحبة، فهمتونا

Each pair uses one of these words in a form the training data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, another person or tense of a verb, or with attached و / بـ / لـ / الـ / عالـ, inside a real-chat message of 10 to 25 words. Use as many different words from the list as you can; skip any you are not sure of. Put the new form in "rare_words". The form must not be in reference/known_words.tsv.

### Round 4: ids A5-T04-001 to A5-T04-050

**Kind: English and French that stay Latin.** Messages about school and kids' activities that mix Arabizi with at least two English or French words or short phrases that must stay in Latin exactly as typed (everyday words, names of foods, brands, places abroad, set phrases like `a demain`, `ca va`, `by the way`), next to loanwords that Lebanese write in Arabic because Arabic grammar is on them (`talfanetlak`, `masajtak`, `ma 3am yechtghel el wifi` → ال wifi). Put the Latin words that stay Latin in "rare_words", as typed.

### Round 5: ids A5-T05-001 to A5-T05-050

**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it hasn't seen:

دموعي، أهلن، مرقوا، البيبرون، الحج، منرجعو، أساتذة، كوسبا، مسلسلي، يبلشوا، تفقع، بينسى، الدفع، مرقو، وبقلك، للسفارة، بتركيب، لوبية، بغابة، سريعة، وليل، احترمتو، لإبني، يحس، التنزيلات، فهمتيني، بنضل، خرج، داخل، اكتشفو

Each pair uses one of these words in a form the training data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, another person or tense of a verb, or with attached و / بـ / لـ / الـ / عالـ, inside a real-chat message of 10 to 25 words. Use as many different words from the list as you can; skip any you are not sure of. Put the new form in "rare_words". The form must not be in reference/known_words.tsv.

### Round 6: ids A5-T06-001 to A5-T06-050

**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it hasn't seen:

قصدا، طيبتك، إيديكي، بلوم، حاطط، نتفرج، جلاب، النمورة، بيشوفنا، تعني، إنقل، تعبتي، الموظفين، فلاح، تغيرولنا، عقليا، مقطع، كاملة، بيدعموك، عالسعر، بتعملولنا، صحنين، وقلو، حبو، والدرس، بدفعلك، باينة، يعجق، بيكذب، يركز

Each pair uses one of these words in a form the training data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, another person or tense of a verb, or with attached و / بـ / لـ / الـ / عالـ, inside a real-chat message of 10 to 25 words. Use as many different words from the list as you can; skip any you are not sure of. Put the new form in "rare_words". The form must not be in reference/known_words.tsv.

In every round: every pair must differ in vocabulary and structure, with no templates, no repeated openings and no near-copies of any earlier pair or of the examples above. No real people's full names, phone numbers or private details; common first names only.

## Check your own work in every round

Do this checking silently: never write out drafts, reasoning, explanations or notes about your thinking, in the chat or in any file. The output files contain only the final pairs.

Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:

1. Is every Arabic word what the Arabizi word means in this sentence? (Watch la, ma3, wala, men, 3amel, w, b, l, ma.)
2. Nothing added, dropped, translated or explained?
3. Is every word a real, current Lebanese word, used the Lebanese way?
4. No standard Arabic (MSA) where Lebanese is spoken?
5. Spelling exactly by the guide (hamza, ة / ه, long vowels, the article, attached words)?
6. English, French, numbers, times and emoji exactly as typed?
7. Does the Arabizi look like a real phone message (Rule 2): long enough, messy, no 6 or 9, no final punctuation?
8. No diacritics, no tatweel?

Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.

## How to deliver

Save the pairs in **output/A5_chat_1.jsonl**, appending each round as soon as it is checked, exactly as `RUN_ALL_5.md` says. Do not print the pairs in the chat.

## Line format

One JSON object per line, nothing else on the line:

{"id": "A5-T01-001", "kind": "context", "arabizi": "...", "arabic": "...", "rare_words": ["..."], "check": ["<word>: <short reason>"]}

"check" lists every word a careful native speaker might spell differently or not know, each with a reason of at most five words; it may be empty only if you have no doubt about any word.
