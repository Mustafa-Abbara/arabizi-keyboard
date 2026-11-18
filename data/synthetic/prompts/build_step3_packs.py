"""Round 6: training pairs aimed at everything the smaller model (Qwen3-0.6B Q4, trained on v4's data) still gets
wrong, built into a standalone pack per machine (A, B, C).

The kinds and their share come from a word-by-word analysis of Qwen Q4's errors on all five scored sets (comparison
set, 1,642 real chats, others dev, frozen dev, synthetic test), with the scorer's accepted spellings counted as right
(docs/SIZE_STUDY_ERRORS.md). On the four real-typing sets, Qwen's extra errors over v4 were: common words misread 20%,
new forms of known words 19%, words seen 1-3 times 16%, words joined or split 10%, stretched letters 9%, never-seen
words 9%, plural endings 8%, who is speaking 5%, English or French not kept 4%. Inside the misread words, the biggest
causes were one typed word becoming several or the reverse (27% on real chats), invented spellings of rare words
(23%), and long vowels added or dropped (19%; 33% on the synthetic test). By kind of message, Qwen lost most on
stretched letters (-9.5 points on others dev), several English or French words (-5.0), vowelless words (-4.1),
long messages (-3.7), digits as letters (-2.3 on real chats, -2.9 on the comparison set) and short messages (-1.4).

  uv run --project eval python data/synthetic/prompts/build_step3_packs.py .

Reads the round 5 task file (build/harfi_round5_A/chats5/chat_1.md) for the shared head: the real-chat examples, the
MSA list and the spelling guide. Word lists skip every word earlier rounds gave to the same kind.
"""
import collections
import json
import random
import re
import shutil
import sys
import zipfile
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(REPO / "eval" / "src"))
from arabizi_eval import metrics as M
from arabizi_eval.pairs import normalize_arabic
from arabizi_eval.spelling_v2 import Converter

PAIRS = 50
lk = lambda w: normalize_arabic(w, lenient=True)
jl = lambda p: [json.loads(l) for l in Path(p).read_text(encoding="utf-8").splitlines() if l.strip()]

# ---- the training vocabulary (v4's data, which the smaller models were trained on) ----
train = [r for f in sorted((REPO / "data/pairs").glob("train-*.jsonl")) for r in jl(f)] + \
        jl(REPO / "build/v4_data/train-ai_checked.synthetic.jsonl")
ar, shown, az = collections.Counter(), collections.defaultdict(collections.Counter), collections.Counter()
for r in train:
    for w in M.tokens(normalize_arabic(r["arabic"])):
        ar[lk(w)] += 1
        shown[lk(w)][w] += 1
    az.update(w.lower() for w in M.tokens(r["arabizi"]))
disp = {k: c.most_common(1)[0][0] for k, c in shown.items()}
pure = [k for k in ar if re.fullmatch("[ء-ي]{3,}", disp[k])]

# ---- words earlier rounds already gave to each kind ----
KIND = {"new forms": "inflect", "low-frequency": "low", "rare words": "low", "heavy letters": "letters"}
used = collections.defaultdict(set)
for pattern in ("harfi_pack_*/chats*/*.md", "harfi_round5_*/chats5/*.md"):
    for f in (REPO / "build").glob(pattern):
        for kind, block in re.findall(r"\*\*Kind: (new forms|low-frequency|rare words|heavy letters)[^\n]*\n\n([^\n]+)\n\n",
                                      f.read_text(encoding="utf-8")):
            used[KIND[kind]].update(lk(w.strip()) for w in block.split("،"))
rng = random.Random(2030)
TAKEN: set = set()


def take(pool, n):
    picked = rng.sample(sorted(pool - TAKEN), n)
    TAKEN.update(picked)
    return [disp[k] for k in picked]


inflect_pool = {k for k in pure if 2 <= ar[k] <= 40} - used["inflect"]
low_pool = {k for k in pure if ar[k] <= 3} - used["low"]
mid_pool = {k for k in pure if 4 <= ar[k] <= 10}
letters_pool = {k for k in pure if ar[k] >= 3 and re.search("[طصضظثذ]", k)} - used["letters"]
print("used before: inflect", len(used["inflect"]), "low", len(used["low"]), "letters", len(used["letters"]),
      "| pools left: inflect", len(inflect_pool), "low", len(low_pool), "mid", len(mid_pool), "letters",
      len(letters_pool))

SHORT = ("Mix the lengths as real chat does: about a third of the messages short (3 to 7 words), the rest 8 to 20 "
         "words.")


def rule(kind, x):
    if kind == "glued":
        return ("**Kind: words typed glued together or split apart.** Real people often type without the space "
                "between words, or put a space inside a word. Each message has at least two such spots, for example: "
                "`3ambitarjem` → عم بيترجم, `mabya3ref` → ما بيعرف, `ma3ende` → ما عندي, `3ambe7ke` → عم بحكي, "
                "`kelshi` → كل شي, `ya ret` → ياريت, `l7amdella` → الحمدلله, `bl bet` → بالبيت, "
                "`3hl 7ale` → عهالحالة, `bt fatess` → بتفطس, `la e3ref` → لإعرف, `3a swesra` → ع سويسرا, `l 30` → ال "
                "30. The Arabic follows the spelling guide's rules for small and attached words (section 3), whatever "
                "the typing did. Use a different glued or split word in every pair. " + SHORT +
                " Put the Arabic of the glued or split words in \"rare_words\".")
    if kind == "vowels":
        return ("**Kind: vowels typed loosely.** Arabizi does not show which vowels are long: the model must decide "
                "ا / و / ي from the word and the sentence. Each message has at least two words where the typed vowels "
                "do not match the Arabic letters, for example: `ba3ed` → بعد next to `b3id` → بعيد, `tool` → طول "
                "next to `tawil` → طويل, `3ala` → على, `akkid` → أكد next to `akid` → أكيد, `mreye` → مراية, `rfe2e` → "
                "رفيقي, `l3ale2a` → العلاقة, `masri` → مصري next to `masare` → مصاري; and participles next to verbs: "
                "`fahem` / `fehim` → فاهم vs `fhemet` → فهمت, `3aref` / `3erif` → عارف vs `3refet` → عرفت, `mashe` / "
                "`meshe` → ماشي vs `msheet` → مشيت, `nazel` → نازل vs `nezlet` → نزلت, `7ader` → حاضر, `sarli` → "
                "صرلي. " + SHORT +
                " Put those words' Arabic in \"rare_words\".")
    if kind == "context":
        return ("**Kind: the same typing, two different words.** Each message has at least two short words whose "
                "Arabic depends on the sentence, placed where the wrong reading is tempting: `min` (من / مين), `ma3` / "
                "`maa` (مع / ما), `ba3d` (بعد / بعض), `wala` (ولا / والله), `la` (لا / لـ), `3am` (عم / عام), `ha` "
                "(رح future / ها), `el` / `l` before a word, which is the article (`l sene` → السنة, `l "
                "she` → الشي, `bel lel` → بالليل), `aya` (أيا / إيا), `ela` (إلا / إلها / إلو). " + SHORT +
                " Put those words' Arabic in \"rare_words\".")
    if kind == "digits":
        return ("**Kind: digits as letters and dropped vowels.** Messages typed fast: many digits for letters (2 = ء "
                "or ق, 3 = ع, 5 = خ, 7 = ح, 8 = غ), used inconsistently (`8ali` and `ghali`, `5alas` and `khalas`), "
                "and many words with no vowels at all (`msh`, `bs`, `ktr`, `mbrh`, `3nde`, `hl2`, `shbb`, `bkhbrk`, "
                "`mn`, `7lwe`). At least 3 vowelless words per message. Include real hamza words (`la2`, `2ana`, "
                "`so2al`, `e3mel` → إعمل, `a3mel` → أعمل as typed) and ط ص ض ظ typed as t s d z. " + SHORT +
                " Put the 2 or 3 hardest words in \"rare_words\".")
    if kind == "long":
        return (f"**Kind: long messages.** One person typing a long message about {x}: several sentences run "
                "together, with few or no commas, the subject changing halfway, repeated words, and an English or "
                "French word or two. **Every message has 18 to 35 words; the round's average is at least 22.** "
                "Put the 2 or 3 words you think are hardest to read in \"rare_words\".")
    if kind == "latin":
        return (f"**Kind: many English and French words that stay Latin.** Messages about {x} with **at least three** "
                "English or French words or short phrases each, kept in Latin exactly as typed in the Arabic "
                "(everyday words, foods, brands, set phrases like `a demain`, `ca va`, `by the way`, `i love u`, "
                "`agressif`, `regime`). Foreign names and places typed in Latin stay Latin (`canada`, `romania`, "
                "`nutella`, `nescafe`, `ps4`); Lebanese places and people's names are written in Arabic (`antelias` → "
                "أنطلياس, `saida` → صيدا, `tony` → طوني). Mix in English words with Arabic prefixes (`el meeting` → ال "
                "meeting, `bl car` → بال car, `3al school` → عال school, `w el wifi` → وال wifi) and a few loanwords "
                "with Arabic grammar written in Arabic (`talfanetlak` → تلفنتلك, `fasakht` → فسخت). Never write a "
                "Latin word in Arabic letters unless Arabic grammar is on it. Put the Latin words in \"rare_words\".")
    if kind == "comment":
        return (f"**Kind: comments under a post.** Comments people write under {x}: reacting, teasing, praising or "
                "complaining, sometimes speaking to the show, the channel or the person directly, sometimes tagging "
                "a friend by first name. Use the French-influenced spelling many Lebanese use: `ch` for ش (chou, chi, "
                "chabeb), `ou` for و (bou2, nouss), final `-e` (helwe, ktire), and short forms (plz, tnx, btw, cz, "
                "idk). 6 to 30 words each. Put the 2 or 3 hardest words in \"rare_words\".")
    if kind == "stretch":
        return ("**Kind: stretched letters, repeated words and laughter.** Real-chat messages where people stretch "
                "letters for emphasis (`ktiiiir`, `laaa`, `yiiii`, `walaaa`, `eeeh`, `shbbb`), repeat words (`la la`, "
                "`eh eh`, `yalla yalla`, `aghani aghani`) and laugh (`hahaha`, `hhhh`, `wahahaha`). Follow the "
                "spelling guide exactly: an elongation is written with the letter repeated as often as typed "
                "(`ktiiiir` → كتيييير, `laaa` → لااا); laughter `hahaha` → ههههه. In the same messages, use words that "
                "end in a doubled ي that is NOT a stretch (`3alayye` → عليي, `jayi` → جايي, `hiye` → هيي, `fiye` → "
                "فيي) and short words typed once that must not be stretched (`yi` → يي, `la` → لا). Each pair has at "
                "least two stretched or repeated words. " + SHORT + " Put the stretched words, in Arabic, in "
                "\"rare_words\".")
    if kind == "person":
        return ("**Kind: who is speaking to whom.** Messages where the Arabic depends on whether the speaker or the "
                "listener is a man or a woman, or on who did something: `kenet` (كانت she was / كنت I was), `kent` / "
                "`knt` (كنت), `kenti` (كنتي), `ente` (إنتي) vs `enta` (إنت), `3endak` / `3endik` (عندك), `baddik` "
                "(بدك), `bta3rfe` (بتعرفي) vs `bta3ref` (بتعرف), `shefte` (شفتي) vs `sheft` (شفت), endings -e / -i "
                "on verbs for a woman (`bta3mle` → بتعملي). Each pair has at least two such words, and the sentence "
                "makes the right reading clear (a name, an adjective ending, or the other words). " + SHORT +
                " Put those words' Arabic in \"rare_words\".")
    if kind == "inflect":
        return ("**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it "
                "hasn't seen:\n\n" + "، ".join(x) + "\n\nEach pair uses one of these words in a form the training "
                "data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), an object pronoun on "
                "a verb (إبعتها، يعطوه، إحكيا), a plural or dual (كاميرات، الدراسات), another person or tense of a verb, "
                "or with attached و / بـ / لـ / الـ / عالـ, inside a real-chat message. " + SHORT + " Use as many "
                "different words from the list as you can; skip any you are not sure of. Put the new form in "
                "\"rare_words\". The form must not be in reference/known_words.tsv.")
    if kind == "letters":
        return ("**Kind: letters and endings that trip the model.** These words contain ط ص ض ظ ث ذ:\n\n" +
                "، ".join(x) + "\n\nEach pair uses one or two of them, typed with plain t, s, d, z (never 6 or 9), "
                "next to words that test the v2.0 spelling decisions: a hamza on alif written ا (`2ana` → انا, `eza` "
                "→ اذا, `sa2alt` → سالت), a real ء / ؤ / ئ kept (`shi2` → شيء, `so2al` → سؤال), a feminine ending "
                "in ة (`syyara` → سيارة, `7elwe` → حلوة) next to a word whose ه belongs to it (`safeh` → سفيه, `wejh` "
                "→ وجه), and a plural verb in و (`2alo` → قالو, `byeshtaghlo` → بيشتغلو). Use at least 25 "
                "different words from the list; skip any you are not sure of. " + SHORT + " Put the list words you "
                "used in \"rare_words\".")
    if kind == "mid":
        return ("**Kind: words the model has seen only a few times.** These words appear 4 to 10 times in the "
                "training data:\n\n" + "، ".join(x) + "\n\nEach pair uses one or two of them naturally, in the "
                "form listed or another form (another ending, with و / بـ / لـ / الـ attached), inside a real-chat "
                "message, typed the way different people would (with and without vowels, with digits or letters). " +
                SHORT + " Use at least 40 different words from the list; skip any you are not sure of. Put the "
                "list words you used in \"rare_words\".")
    if kind == "low":
        return ("**Kind: rare words.** These words appear only 1 to 3 times in the training data:\n\n" + "، ".join(x) +
                "\n\nEach pair uses one or two of them naturally, in the form listed or a natural variation, inside a "
                "real-chat message. " + SHORT + " Use at least 40 different words from the list. Skip any word you "
                "are not sure of (a name, a typo, a word you don't know). Put the list words you used in "
                "\"rare_words\".")
    return (f"**Kind: new vocabulary. Topic: {x}.** Each pair contains at least one less common word about the topic "
            "that is not in reference/known_words.tsv (and is not just a word from that file with a prefix added), "
            "inside a real-chat message. " + SHORT + " Put it in \"rare_words\". Never invent a word.")


MACHINES = {
    "A": {"long": ["a family visit that went wrong", "a wedding: the food, the music, who said what"],
          "latin": ["kids' school and activities", "food, recipes and restaurants", "series, films and music"],
          "comment": ["a cooking show on TV", "a TV channel changing a show's time"],
          "new": ["Lebanese towns, neighbourhoods and roads", "traditional food, sweets and drinks",
                  "the house: rooms, furniture, the basement and the roof"]},
    "B": {"long": ["a day at the office and a difficult manager", "a road trip with traffic and a flat tyre"],
          "latin": ["office, meetings and emails", "university and online classes", "phones, apps and gaming"],
          "comment": ["a football match result", "a news story about electricity cuts"],
          "new": ["government paperwork and errands", "the garage, car parts and driving",
                  "feelings, moods and how people treat each other"]},
    "C": {"long": ["a night out that ended badly", "a break-up told to a best friend"],
          "latin": ["going out, bars and cafes", "travel, airports and hotels", "social media and influencers"],
          "comment": ["an influencer's post", "a dating show episode"],
          "new": ["the sea, the mountains, snow and camping", "nightlife, desserts and late-night snacks",
                  "slang and expressions young people use"]},
}
MIX = {"vowels": 4, "inflect": 4, "low": 4, "new": 3, "latin": 3, "long": 2, "comment": 2, "glued": 2, "stretch": 2,
       "person": 2, "context": 2, "digits": 2, "letters": 2, "mid": 2}
assert sum(MIX.values()) == 36

CHECK = (
    "\n## Check your own work in every round\n\n"
    "Do this checking silently: never write out drafts, reasoning, explanations or notes about your thinking, in the "
    "chat or in any file. The output files contain only the final pairs.\n\n"
    "Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:\n\n"
    "1. Is every Arabic word what the Arabizi word means in this sentence? (Watch la, ma3, wala, men / min, ba3d, "
    "3amel, kenet, ente, w, b, l, ma.)\n"
    "2. Nothing added, dropped, translated or explained? Count the words on both sides; glued typing still maps word "
    "for word.\n"
    "3. Is every word a real, current Lebanese word, used the Lebanese way?\n"
    "4. No standard Arabic (MSA) where Lebanese is spoken?\n"
    "5. Spelling exactly by the guide v2.0: no أ or إ anywhere (always ا), ء / ؤ / ئ kept, a plural verb ending in "
    "و (never وا), a feminine ending in ة, `leh` → ليه, `lesh` → ليش, `hay` → هي; then long vowels, the article, "
    "attached words, elongations and the word list in section 8?\n"
    "6. English, French, numbers, times and emoji exactly as typed, in Latin, in the same place?\n"
    "7. Does the Arabizi look like a real phone message (Rule 2): messy, no 6 or 9, no final punctuation?\n"
    "8. No diacritics, no tatweel?\n\n"
    "Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.\n")

RUN_ALL = """# RUN ALL, round 6 (machine {M})

You are working in this folder on the user's computer. Your job is to produce 1,800 training pairs (Lebanese Arabizi → Lebanese Arabic script) by working through the six task files in `chats6/`, one after another, saving everything in `output/`. The person who started you is only helping; they don't know the details. **Do not ask them anything. Work until all six are done.** If you need permission to write files, ask for it once.

This round is aimed at everything a smaller model still gets wrong on real typing: vowels typed loosely, new forms of known words, rare and new words, words typed glued or split, English and French that must stay Latin, long messages, comments in French-influenced spelling, stretched letters, who is speaking to whom, words that need the sentence to decide, and fast typing with digits and no vowels, and words seen only a few times.

## The folder

```
RUN_ALL_6.md                   this file
chats6/chat_1.md … chat_6.md   the six tasks, each 6 rounds of 50 pairs
reference/known_words.tsv      every Arabic word the model has trained on, with counts (tab-separated)
reference/known_arabizi.tsv    every Arabizi spelling the model has trained on, with counts
output/                        where you save your work (create it if missing)
```

## Comparing words

When this file or a task says a word is "in" or "not in" a reference file, compare without diacritics or tatweel, and treat أ / إ / آ / ا, final ى / ي and final ة / ه as the same in Arabic; compare Arabizi in lowercase. Use code to look words up, not memory.

## The loop

For N = 1 to 6:

1. **Skip what's done.** If `output/{M}6_chat_N.jsonl` already has 300 valid lines, go to the next N. If it has fewer, this chat was interrupted: continue it from the id after the last valid line.
2. **Read what exists.** Read every `output/{M}6_chat_*.jsonl` written so far. Don't write a pair close to any earlier pair, and for rounds of kind "new" don't reuse an earlier pair's rare word.
3. **Read the task.** Read `chats6/chat_N.md` completely and follow it exactly: its rules, the real-chat style, the spelling guide, examples, rounds and self-check.
4. **Work round by round.** For each round:
   - write the round's 50 pairs and check them as the task file says;
   - **check the real-chat style with code**, and rewrite pairs until the round passes:
     - message lengths as the round's kind asks: for kind long, every message 18 to 35 words with an average of at least 22; for kind comment, 6 to 30 words; for every other kind, 3 to 20 words with at least 15 of the 50 messages at 3 to 7 words;
     - between 7 and 20 of the 50 messages contain emoji;
     - no Arabizi word contains the digit 6 or 9;
     - at most 2 of the 50 messages end with `.` `?` or `!`;
     - at least 3% of the round's Arabizi words (of 3+ letters) have no vowel (a, e, i, o, u); for kind digits, at least 3 such words in every message;
     - no accented Latin letter (é, è, à, ç...) in the Arabizi;
     - **spelling v2.0**: no أ or إ anywhere in the Arabic, and no Arabic word ends in وا except سوا، دوا، هوا، جوا (with or without ال / و / بـ in front);
   - **check the round's own rule with code**, and replace any pair that fails it:
     - kind **inflect**: each rare word (the new form) is not in `known_words.tsv`;
     - kinds **letters** and **mid**: the rare words come from the round's list;
     - kind **low**: the rare words come from the round's list;
     - kind **new**: each rare word is not in `known_words.tsv`, and isn't one of its words with only a prefix added (و، ف، ب، ل، ع، ك، ال، بال، وال، لل، عال);
     - kind **latin**: each pair has at least three Latin words that appear exactly, as typed, in both the Arabizi and the Arabic;
     - kind **comment**: at least 20 of the 50 messages use `ch` for ش;
     - kind **stretch**: each pair has at least two words with a letter typed three or more times in a row, or a word typed twice in a row, and every stretched word keeps its repeated letters in the Arabic;
     - kind **glued**: each pair has at least two Arabizi tokens whose Arabic is two words, or two Arabizi tokens whose Arabic is one word;
     - kinds **vowels**, **context** and **person**: each pair has at least two of the kind's words in "rare_words";
   - **append** the 50 lines to `output/{M}6_chat_N.jsonl` (UTF-8, one JSON object per line, nothing else in the file);
   - check that every line parses as JSON and that the ids run in order with no gaps or repeats; fix the file if not;
   - update `output/{M}6_progress.txt` with one line: `chat_N round R done: <lines in file> lines`.
5. Go on to the next round, then the next chat, **without stopping to report or ask**.

If you run out of room in one turn, stop at the end of a round. When you are told to continue (or started again with this file), the loop above picks up exactly where you stopped.

## At the very end

When all six files have 300 valid lines, write `output/{M}6_DONE.txt` with:

- the number of lines in each file and in total, and per kind;
- the style numbers over all 1,800 pairs: average words per message, share of short messages (3 to 7 words), share with emoji, share ending in punctuation, share of vowelless words;
- how many pairs passed their round's rule check, per kind;
- a plain list of words you skipped or were unsure about, with no explanations.

Then tell the person: "All done. Send the `output` folder back."

## Never

- Never edit anything outside `output/`.
- Never print the pairs in the chat; they go in the files.
- Never write out your reasoning, drafts or explanations, in the chat or in any file. The only output is the pairs, plus the short status lines in the progress and DONE files.
- Never invent a word or a spelling to satisfy a rule. If you can't meet a round's rule with certain words, write fewer pairs of that kind, fill the round with ordinary real-chat pairs, and note it in the DONE file.
"""

# ---- the shared head, from round 5 ----
r5 = (REPO / "build/harfi_round5_A/chats5/chat_1.md").read_text(encoding="utf-8")
head = r5[:r5.index("## What to write")]
old_intro = head[head.index("The model has been trained once already."):head.index("## Rule 1")]
head = head.replace(old_intro, (
    "The model has been trained twice already. A smaller version of it, measured word by word on real messages, "
    "still fails on: **vowels typed loosely** (بعد / بعيد, فاهم / فهمت), **new forms of words it knows**, **rare and "
    "new words** (it invents spellings), **words typed glued together or split apart**, **English and French words** "
    "(it writes them in Arabic letters), **long messages**, **comments in French-style spelling**, **stretched "
    "letters**, **who is speaking to whom** (إنتي / إنت, كنت / كانت), **words that need the sentence to decide**, and "
    "**fast typing with digits and no vowels**. It also does worse than the big model on **short messages**. This "
    "round targets exactly those.\n\n"))
head = (head.replace("(round 5)", "(round 6)").replace("RUN_ALL_5.md", "RUN_ALL_6.md")
        .replace("write **8 to 25 words** per message, about 12 on average; a few up to 30",
                 "write the lengths each round's kind asks for: short messages (3 to 7 words) and long ones (18 to 35) "
                 "both matter"))
assert "(round 6)" in head and "both matter" in head and "round 5" not in head.lower()
# Spelling v2.0 (18 Nov 2026): the current guide replaces round 5's copy, and the examples, the MSA list and the round
# texts are converted (no أ / إ, plural و); the decisions are then stated once, in their own words.
CONV = Converter()
g0, g1 = head.index("<spelling_guide>"), head.index("</spelling_guide>")
head = (CONV.text(head[:g0]) + "<spelling_guide>\n" + (REPO / "docs/SPELLING.md").read_text(encoding="utf-8").strip()
        + "\n" + CONV.text(head[g1:]))
V2 = ("- **Spelling decisions v2.0 (strict, they override anything older):** never write أ or إ, always a plain ا "
      "(`ana` → انا, `eza` → اذا, `sa2al` → سال, `la2` → لا); ء, ؤ and ئ are written as they are and never become ا "
      "(`shi2` → شيء, `so2al` → سؤال); a verb's plural ending is always و, never وا (`2alo` → قالو, `ya3mlo` → يعملو), "
      "while سوا، دوا، هوا، جوا keep their ا; a feminine ending is ة (`syyara` → سيارة), and ه only when it is part of "
      "the word (`safeh` → سفيه, `allah` → الله); `leh` → ليه and `lesh` → ليش; `hay` → هي.\n")
rule3 = "## Rule 3: what the Arabic must do\n\n"
assert rule3 in head
head = head.replace(rule3, rule3 + V2)

known_w = "".join(f"{disp[k]}\t{n}\n" for k, n in ar.most_common())
known_a = "".join(f"{w}\t{n}\n" for w, n in az.most_common())

for Mn, cfg in MACHINES.items():
    rounds = [("long", t) for t in cfg["long"]] + [("latin", t) for t in cfg["latin"]]
    rounds += [("comment", t) for t in cfg["comment"]] + [("new", t) for t in cfg["new"]]
    rounds += [("inflect", take(inflect_pool, 30)) for _ in range(MIX["inflect"])]
    rounds += [("low", take(low_pool, 60)) for _ in range(MIX["low"])]
    rounds += [("mid", take(mid_pool, 60)) for _ in range(MIX["mid"])]
    rounds += [("letters", take(letters_pool, 30)) for _ in range(MIX["letters"])]
    rounds += [(k, None) for k in ("vowels", "glued", "stretch", "person", "context", "digits") for _ in range(MIX[k])]
    assert collections.Counter(k for k, _ in rounds) == collections.Counter(MIX), Mn
    rng.shuffle(rounds)
    out = REPO / "build" / f"harfi_round6_{Mn}"
    shutil.rmtree(out, ignore_errors=True)
    for d in ("chats6", "reference", "output"):
        (out / d).mkdir(parents=True)
    for c in range(6):
        parts = []
        for r, (kind, x) in enumerate(rounds[c * 6:(c + 1) * 6], 1):
            n = c * 6 + r
            parts.append(f"### Round {r}: ids {Mn}6-T{n:02d}-001 to {Mn}6-T{n:02d}-{PAIRS:03d}\n\n{CONV.text(rule(kind, x))}\n")
        task = ("## What to write\n\n300 pairs in 6 rounds of 50. Each round has its own kind and ids. Write a field "
                "\"kind\" in every line (vowels, inflect, low, mid, new, latin, long, comment, glued, stretch, "
                "person, context, digits or letters). Every pair follows Rule 2 (real phone chat).\n\n" + "\n".join(parts) +
                "\nIn every round: every pair must differ in vocabulary and structure, with no templates, no repeated "
                "openings and no near-copies of any earlier pair or of the examples above. No real people's full names, "
                "phone numbers or private details; common first names only. No politics or religion.\n" + CHECK +
                f"\n## How to deliver\n\nSave the pairs in **output/{Mn}6_chat_{c + 1}.jsonl**, appending each round as "
                "soon as it is checked, exactly as `RUN_ALL_6.md` says. Do not print the pairs in the chat.\n\n"
                "## Line format\n\nOne JSON object per line, nothing else on the line:\n\n"
                f'{{"id": "{Mn}6-T{c * 6 + 1:02d}-001", "kind": "{rounds[c * 6][0]}", "arabizi": "...", '
                '"arabic": "...", "rare_words": ["..."], "check": ["<word>: <short reason>"]}\n\n'
                "\"check\" lists every word a careful native speaker might spell differently or not know, each with a "
                "reason of at most five words; it may be empty only if you have no doubt about any word.\n")
        (out / "chats6" / f"chat_{c + 1}.md").write_text(head + task, encoding="utf-8")
    (out / "reference/known_words.tsv").write_text(known_w, encoding="utf-8")
    (out / "reference/known_arabizi.tsv").write_text(known_a, encoding="utf-8")
    (out / "RUN_ALL_6.md").write_text(RUN_ALL.replace("{M}", Mn), encoding="utf-8")
    (out / "output/.keep").write_text("", encoding="utf-8")
    zp = REPO / "build" / f"harfi_round6_{Mn}.zip"
    zp.unlink(missing_ok=True)
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, Path(f"harfi_round6_{Mn}") / p.relative_to(out))
    print(zp.name, dict(collections.Counter(k for k, _ in rounds)))
