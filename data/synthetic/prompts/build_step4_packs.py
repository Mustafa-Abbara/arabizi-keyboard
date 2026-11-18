"""Round 6, second half: packs D, E and F for the same generator models as A, B and C, with nothing taken from an
evaluation set (ADR 0040 #9).

What changed from build_step3_packs.py (packs A, B, C):
- **Weights from analysis data only.** Qwen3-0.6B Q4's errors were measured again against v4 on the frozen dev set,
  others dev and one half of the real chats (half "a": the SHA-256 of the id is even). The comparison set, the frozen
  tests, the held-out synthetic test and the other half of the real chats were not looked at. Qwen's extra errors
  there: common words misread 32%, new forms of known words 21%, stretched letters 10%, plural endings 8% (now fixed
  by spelling v2.0), words seen 1-3 times 8%, never-seen words 7%, English/French not kept 6%, who is speaking 4%,
  joined or split 3%. Words seen 4-10 times and similar-letter slips were not worse than v4, so those kinds are gone.
  Kinds of message where Qwen lost most: stretched letters, Latin-heavy, vowelless words, long, digits as letters.
- **Every example word is checked with code**: it is in the training data, or is a regular form found nowhere; never a
  word found only in an evaluation set. The build fails if any Arabizi word or 4-word sequence in a task file appears
  in an evaluation set and never in training.
- **New content:** new example words for every kind, new topics, new real-chat examples in the head, and word lists
  that skip every word rounds 1 to 6 gave out.

  uv run --project eval python data/synthetic/prompts/build_step4_packs.py . [<more evaluation jsonl> ...]

Extra arguments are further evaluation files to check against, such as the real chats (not in the repository).
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
EXTRA_EVAL = [Path(x) for x in sys.argv[2:]]
sys.path.insert(0, str(REPO / "eval" / "src"))
from arabizi_eval import metrics as M
from arabizi_eval.pairs import normalize_arabic
from arabizi_eval.spelling_v2 import Converter

PAIRS = 50
lk = lambda w: normalize_arabic(w, lenient=True)
jl = lambda p: [json.loads(l) for l in Path(p).read_text(encoding="utf-8").splitlines() if l.strip()]

# ---- the training vocabulary (rounds 1 to 6 included; generated spelling variants left out) ----
train = [r for f in sorted((REPO / "data/pairs").glob("train-*.jsonl")) if "variant" not in f.name for r in jl(f)]
ar, shown, az = collections.Counter(), collections.defaultdict(collections.Counter), collections.Counter()
for r in train:
    for w in M.tokens(normalize_arabic(r["arabic"])):
        ar[lk(w)] += 1
        shown[lk(w)][w] += 1
    az.update(w.lower() for w in M.tokens(r["arabizi"]))
disp = {k: c.most_common(1)[0][0] for k, c in shown.items()}
pure = [k for k in ar if re.fullmatch("[ء-ي]{3,}", disp[k])]

# ---- the leak check: Arabizi words and 4-word sequences found in an evaluation set and never in training ----
LATIN = re.compile(r"[a-z0-9']*[a-z][a-z0-9']*")
latin_words = lambda t: LATIN.findall(t.lower())


def grams(text, n=4):
    w = latin_words(text)
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


EVAL = [REPO / "data/pairs/dev.jsonl", REPO / "data/pairs/test.jsonl", REPO / "data/pairs/others/dev.jsonl",
        REPO / "data/pairs/others/test.jsonl", REPO / "data/synthetic/synthetic_test.jsonl",
        REPO / "build/comparison/comparison_key.jsonl", *EXTRA_EVAL]
ev_words, ev_grams = set(), set()
for f in EVAL:
    if f.exists():
        for r in jl(f):
            ev_words |= set(latin_words(r["arabizi"]))
            ev_grams |= grams(r["arabizi"])
tr_words, tr_grams = set(), set()
for r in train:
    tr_words |= set(latin_words(r["arabizi"]))
    tr_grams |= grams(r["arabizi"])
EVAL_ONLY_WORDS, EVAL_ONLY_GRAMS = ev_words - tr_words, ev_grams - tr_grams
EXAMPLE = re.compile(r"`([^`]+)`")


def leaks(text):
    """Eval-only words inside `examples` and in the head's example messages, and eval-only 4-word sequences anywhere."""
    examples = " ".join(EXAMPLE.findall(text)) + " " + " ".join(re.findall(r"^- (.+?)  →  ", text, re.M))
    return sorted(set(latin_words(examples)) & EVAL_ONLY_WORDS), sorted(grams(text) & EVAL_ONLY_GRAMS)


# ---- words earlier rounds already gave out (rounds 1 to 6, every kind) ----
KIND = {"new forms": "inflect", "low-frequency": "low", "rare words": "low", "heavy letters": "letters",
        "letters and endings": "letters", "words the model has seen only": "mid"}
used = collections.defaultdict(set)
for pattern in ("harfi_pack_*/chats*/*.md", "harfi_round5_*/chats5/*.md", "harfi_round6_[ABC]/chats6/*.md"):
    for f in (REPO / "build").glob(pattern):
        for kind, block in re.findall(r"\*\*Kind: (" + "|".join(KIND) + r")[^\n]*\n\n([^\n]+)\n\n",
                                      f.read_text(encoding="utf-8")):
            used[KIND[kind]].update(lk(w.strip()) for w in block.split("،"))
ALL_USED = set().union(*used.values())
rng = random.Random(2031)
TAKEN: set = set()


def take(pool, n):
    picked = rng.sample(sorted(pool - TAKEN), n)
    TAKEN.update(picked)
    return [disp[k] for k in picked]


inflect_pool = {k for k in pure if 2 <= ar[k] <= 40} - ALL_USED
low_pool = {k for k in pure if ar[k] <= 3} - ALL_USED
print("given out before:", {k: len(v) for k, v in sorted(used.items())}, "| pools left: inflect", len(inflect_pool),
      "low", len(low_pool))

SHORT = ("Mix the lengths as real chat does: about a third of the messages short (3 to 7 words), the rest 8 to 20 "
         "words.")


def rule(kind, x):
    if kind == "glued":
        return ("**Kind: words typed glued together or split apart.** Real people often drop the space between "
                "words, or put one inside a word. Each message has at least two such spots, for example: `3amb2ol` → "
                "عم بقول, `mab3ref` → ما بعرف, `mabade` → ما بدي, `msh3aref` → مش عارف, `kelyom` → كل يوم, `mafina` → "
                "ما فينا, `3ambe2ra` → عم بقرا, `shubek` → شو بك, and the other way, `3al ba7er` → عالبحر, `bl jem3a` "
                "→ بالجامعة, `mnl bet` → من البيت. The Arabic follows the spelling guide's rules for small and attached "
                "words (section 3), whatever the typing did. Use a different glued or split word in every pair. " +
                SHORT + " Put the Arabic of the glued or split words in \"rare_words\".")
    if kind == "vowels":
        return ("**Kind: vowels typed loosely.** Arabizi does not show which vowels are long: the model must decide "
                "ا / و / ي from the word and the sentence. Each message has at least two words where the typed vowels "
                "do not match the Arabic letters, for example: `jdid` → جديد, `2adim` → قديم, `rkhis` → رخيص, `nadif` "
                "→ نضيف, `t2il` → تقيل, `bared` → بارد, `zghir` → زغير, `kbire` → كبيرة; and participles next to "
                "verbs: `nayem` → نايم vs `nemet` → نمت, `2a3ed` → قاعد vs `2a3adt` → قعدت, `ta3ban` → تعبان vs "
                "`t3ebet` → تعبت, `shayef` → شايف vs `shefet` → شفت, `rayi7` → رايح vs `re7t` → رحت, `sakne` → "
                "ساكنة. " + SHORT + " Put those words' Arabic in \"rare_words\".")
    if kind == "context":
        return ("**Kind: the same typing, two different words.** Each message has at least two short words whose "
                "Arabic depends on the sentence, placed where the wrong reading is tempting: `elak` (الك / قلك), "
                "`2alle` (قلي / قالي), `3ala` (على / عالـ), `l` (the article الـ, or لـ \"to\": "
                "`2elt l rami` → قلت لرامي next to `l beit` → البيت), `w` (و joined to the next word), `b` (بـ \"in\", "
                "or the بـ of a present verb: `b beirut` → ببيروت, `bshoufak` → بشوفك), `ma` (ما \"not\", or \"what\" in "
                "ما بعرف شو), `fi` (في \"there is\", or \"in\"), `hal` (هال \"this\", attached: هالقد، هالشي). " +
                SHORT + " Put those words' Arabic in \"rare_words\".")
    if kind == "digits":
        return ("**Kind: digits as letters and dropped vowels.** Messages typed fast: many digits for letters (2 = ء "
                "or ق, 3 = ع, 5 = خ, 7 = ح, 8 = غ), used inconsistently (`5ayye` and `khayye`, `3njd` and `3anjad`), "
                "and many words with no vowels at all (`bkra`, `shwy`, `kfk`, `bdk`, `lsh`, `5ls`, `mtl`, `hk`, "
                "`3ndo`, `mnyh`). At least 3 vowelless words per message. Include real hamza words (`2ahwe` → قهوة, "
                "`sa2alt` → سالت, `mas2oul` → مسؤول, `as2ile` → اسئلة) and ط ص ض ظ typed as t s d z. " + SHORT +
                " Put the 2 or 3 hardest words in \"rare_words\".")
    if kind == "long":
        return (f"**Kind: long messages.** One person typing a long message about {x}: several sentences run "
                "together, with few or no commas, the subject changing halfway, repeated words, and an English or "
                "French word or two. **Every message has 18 to 35 words; the round's average is at least 22.** "
                "Put the 2 or 3 words you think are hardest to read in \"rare_words\".")
    if kind == "latin":
        return (f"**Kind: many English and French words that stay Latin.** Messages about {x} with **at least three** "
                "English or French words or short phrases each, kept in Latin exactly as typed in the Arabic "
                "(everyday words, brands, set phrases like `bonne nuit`, `no worries`, `plz`, `omg`, `btw`). Foreign "
                "names and places typed in Latin stay Latin; Lebanese places and people's names are written in Arabic "
                "(`jounieh` → جونية, `zahle` → زحلة, `rami` → رامي). Mix in English words with Arabic prefixes (`el "
                "charger` → ال charger, `bl parking` → بال parking, `3al group` → عال group) and a few loanwords with "
                "Arabic grammar written in Arabic (`chayyakt` → شيكت, `kansalt` → كنسلت). Never write a Latin word "
                "in Arabic letters unless Arabic grammar is on it. Put the Latin words in \"rare_words\".")
    if kind == "comment":
        return (f"**Kind: comments under a post.** Comments people write under {x}: reacting, teasing, praising or "
                "complaining, sometimes speaking to the person directly, sometimes tagging a friend by first name. "
                "Use the French-influenced spelling many Lebanese use: `ch` for ش (`chou`, `chway`, `cheft`, "
                "`chabeb`, `bchouf`), `ou` for و (`rou7`, `bchoufak`), `mich` for مش, final `-e` (`kbire`), and short "
                "forms (`plz`, `omg`, `btw`). 6 to 30 words each. Put the 2 or 3 hardest words in \"rare_words\".")
    if kind == "stretch":
        return ("**Kind: stretched letters, repeated words and laughter.** Real-chat messages where people stretch "
                "letters for emphasis (`shuuuu`, `baaaas`, `yaaaa`, `7abibiii`, `laaaa`), repeat words (`ok ok`, "
                "`bas bas`, `tayeb tayeb`) and laugh (`hhhhh`, `hahahaha`). Follow the spelling guide exactly: an "
                "elongation is written with the letter repeated **exactly as many times as typed** (`shuuuu` → شوووو, "
                "`baaaas` → بااااس, `7abibiii` → حبيبييي), and a word that is not stretched keeps its normal spelling; "
                "laughter → ههههه. In the same messages, use words whose doubled ي is part of the word, not a stretch "
                "(`5ayye` → خيي, `3layye` → عليي). Each pair has at least two stretched or repeated words. " + SHORT +
                " Put the stretched words, in Arabic, in \"rare_words\".")
    if kind == "person":
        return ("**Kind: who is speaking to whom.** Messages where the Arabic depends on whether the speaker or the "
                "listener is a man or a woman, or on who did something: `ra7et` (راحت she went) vs `re7t` (رحت I "
                "went), `2alet` (قالت) vs `2elt` (قلت), `jeye` (جاية a woman coming, جايي a man coming), `ta3bene` "
                "(تعبانة) vs `ta3ban` (تعبان), `mabsoota` (مبسوطة) vs `mabsout` (مبسوط), `ta3e` (تعي) vs `ta3a` "
                "(تعا), `rou7e` (روحي) vs `rou7` (روح). Each pair has at least two such words, and the sentence makes "
                "the right reading clear (a name, an adjective ending, or the other words). " + SHORT +
                " Put those words' Arabic in \"rare_words\".")
    if kind == "inflect":
        return ("**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it "
                "hasn't seen:\n\n" + "، ".join(x) + "\n\nEach pair uses one of these words in a form the training "
                "data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), an object pronoun on "
                "a verb, a plural or dual, another person or tense of a verb, or with attached و / بـ / لـ / الـ / "
                "عالـ, inside a real-chat message. " + SHORT + " Use as many different words from the list as you "
                "can; skip any you are not sure of. Put the new form in \"rare_words\". The form must not be in "
                "reference/known_words.tsv.")
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
    "D": {"long": ["planning a surprise birthday", "a fight with the neighbours over parking"],
          "latin": ["the gym, diets and sports", "shopping, clothes and online orders", "working from home and calls"],
          "comment": ["a celebrity's wedding photos"],
          "new": ["the doctor, the pharmacy and being sick", "weather, storms and the seasons"]},
    "E": {"long": ["moving to a new flat", "a weekend in the village"],
          "latin": ["cars, fuel and the mechanic", "banks, money and prices", "football and big tournaments"],
          "comment": ["a funny video of a cat"],
          "new": ["the garden, farming and fruit trees", "family relations, in-laws and visits"]},
    "F": {"long": ["a job interview", "getting ready for a wedding"],
          "latin": ["hair, make-up and beauty", "laptops, phones and repairs", "concerts, festivals and DJs"],
          "comment": ["a restaurant's page"],
          "new": ["the kitchen: tools, cooking and spices", "childhood: games, school and memories"]},
}
MIX = {"inflect": 6, "vowels": 5, "context": 4, "stretch": 3, "low": 3, "latin": 3, "digits": 3, "new": 2, "long": 2,
       "person": 2, "glued": 2, "comment": 1}
assert sum(MIX.values()) == 36

CHECK = (
    "\n## Check your own work in every round\n\n"
    "Do this checking silently: never write out drafts, reasoning, explanations or notes about your thinking, in the "
    "chat or in any file. The output files contain only the final pairs.\n\n"
    "Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:\n\n"
    "1. Is every Arabic word what the Arabizi word means in this sentence? (Watch l, b, w, ma, fi, 3ala, elak, 2alle, "
    "jeye, ra7et.)\n"
    "2. Nothing added, dropped, translated or explained? Count the words on both sides; glued typing still maps word "
    "for word.\n"
    "3. Is every word a real, current Lebanese word, used the Lebanese way?\n"
    "4. No standard Arabic (MSA) where Lebanese is spoken?\n"
    "5. Spelling exactly by the guide v2.0: no أ or إ anywhere (always ا), ء / ؤ / ئ kept, a plural verb ending in "
    "و (never وا), a feminine ending in ة, `leh` → ليه, `lesh` → ليش, `hay` → هي; a stretched letter repeated "
    "exactly as often as typed; then long vowels, the article, attached words and the word list in section 8?\n"
    "6. English, French, numbers, times and emoji exactly as typed, in Latin, in the same place?\n"
    "7. Does the Arabizi look like a real phone message (Rule 2): messy, no 6 or 9, no final punctuation?\n"
    "8. No diacritics, no tatweel?\n\n"
    "Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.\n")

RUN_ALL = """# RUN ALL, round 6 (machine {M})

You are working in this folder on the user's computer. Your job is to produce 1,800 training pairs (Lebanese Arabizi → Lebanese Arabic script) by working through the six task files in `chats6/`, one after another, saving everything in `output/`. The person who started you is only helping; they don't know the details. **Do not ask them anything. Work until all six are done.** If you need permission to write files, ask for it once.

This round is aimed at what a smaller model still gets wrong on real typing: new forms of known words, vowels typed loosely, short words that need the sentence to decide, stretched letters, rare and new words, English and French that must stay Latin, fast typing with digits and no vowels, long messages, who is speaking to whom, words typed glued or split, and comments in French-influenced spelling.

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
     - **no copying**: no 4 words in a row repeat an example given in the task file;
   - **check the round's own rule with code**, and replace any pair that fails it:
     - kind **inflect**: each rare word (the new form) is not in `known_words.tsv`;
     - kind **low**: the rare words come from the round's list;
     - kind **new**: each rare word is not in `known_words.tsv`, and isn't one of its words with only a prefix added (و، ف، ب، ل، ع، ك، ال، بال، وال، لل، عال);
     - kind **latin**: each pair has at least three Latin words that appear exactly, as typed, in both the Arabizi and the Arabic;
     - kind **comment**: at least 20 of the 50 messages use `ch` for ش;
     - kind **stretch**: each pair has at least two words with a letter typed three or more times in a row, or a word typed twice in a row; every stretched word has the same number of repeated letters in the Arabic as typed;
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

# ---- the shared head, from round 6's packs, with new real-chat examples ----
r6 = (REPO / "build/harfi_round6_A/chats6/chat_1.md").read_text(encoding="utf-8")
head = r6[:r6.index("## What to write")]
old_intro = head[head.index("The model has been trained"):head.index("## Rule 1")]
head = head.replace(old_intro, (
    "The model has been trained several times already. A smaller version of it, measured word by word on real "
    "messages, still fails most on: **common short words that need the sentence to decide**, **new forms of words it "
    "knows**, **vowels typed loosely** (جديد / قديم, نايم / نمت), **stretched letters**, **rare and new words** (it "
    "invents spellings), **English and French words** (it writes them in Arabic letters), **fast typing with digits "
    "and no vowels**, **long messages**, **who is speaking to whom** (راحت / رحت, جاية / جايي) and **words typed "
    "glued together or split apart**. This round targets exactly those.\n\n"))
ex_old = head[head.index("Real messages from the training data"):head.index("## Rule 3")]
CONV = Converter()
real = [r for r in train if r["source"].startswith("friends-and-family (ADR 0021)")
        and 6 <= len(r["arabizi"].split()) <= 22 and not re.search("[A-Za-z]{4,}", re.sub(r"[A-Za-z]+", "", r["arabic"]) or "")
        and not re.search(r"(ha){2,}", r["arabic"].lower()) and r["arabic"] == CONV.text(r["arabic"])
        and not set(latin_words(r["arabizi"])) & EVAL_ONLY_WORDS and not grams(r["arabizi"]) & EVAL_ONLY_GRAMS
        and r["arabizi"] not in ex_old
        # clean examples only: one Arabic word per typed word, no stretched letters (the data writes them both ways),
        # no times or prices
        and len(M.tokens(r["arabizi"])) == len(M.tokens(r["arabic"])) and not re.search(r"([a-z])\1\1", r["arabizi"].lower())
        and not re.search(r"\d[:.,]\d|\d{2,}", r["arabizi"])]
picked = random.Random(2031).sample(real, 15)
head = head.replace(ex_old, "Real messages from the training data (copy their feel, never their words or sentences):\n\n"
                    + "".join(f"- {r['arabizi']}  →  {r['arabic']}\n" for r in picked) + "\n")
assert "(round 6)" in head and "RUN_ALL_6.md" in head
# The guide's own example `la2ennu` is found only in the held-out synthetic test; the training data types it la2enno.
head = head.replace("la2ennu", "la2enno")

known_w = "".join(f"{disp[k]}\t{n}\n" for k, n in ar.most_common())
known_a = "".join(f"{w}\t{n}\n" for w, n in az.most_common())

problems = []
for Mn, cfg in MACHINES.items():
    rounds = [("long", t) for t in cfg["long"]] + [("latin", t) for t in cfg["latin"]]
    rounds += [("comment", t) for t in cfg["comment"]] + [("new", t) for t in cfg["new"]]
    rounds += [("inflect", take(inflect_pool, 30)) for _ in range(MIX["inflect"])]
    rounds += [("low", take(low_pool, 60)) for _ in range(MIX["low"])]
    rounds += [(k, None) for k in ("vowels", "context", "stretch", "digits", "person", "glued") for _ in range(MIX[k])]
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
                "\"kind\" in every line (inflect, vowels, context, stretch, low, latin, digits, new, long, person, "
                "glued or comment). Every pair follows Rule 2 (real phone chat).\n\n" + "\n".join(parts) +
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
        text = head + task
        w, g = leaks(text)
        if w or g:
            problems.append(f"{Mn} chat_{c + 1}: eval-only words {w}, eval-only 4-word sequences {g}")
        (out / "chats6" / f"chat_{c + 1}.md").write_text(text, encoding="utf-8", newline="\n")
    (out / "reference/known_words.tsv").write_text(known_w, encoding="utf-8", newline="\n")
    (out / "reference/known_arabizi.tsv").write_text(known_a, encoding="utf-8", newline="\n")
    (out / "RUN_ALL_6.md").write_text(RUN_ALL.replace("{M}", Mn), encoding="utf-8", newline="\n")
    (out / "output/.keep").write_text("", encoding="utf-8")
    print(Mn, dict(collections.Counter(k for k, _ in rounds)))

if problems:
    print("LEAK CHECK FAILED: nothing zipped\n" + "\n".join(problems))
    sys.exit(1)
for Mn in MACHINES:
    out = REPO / "build" / f"harfi_round6_{Mn}"
    zp = REPO / "build" / f"harfi_round6_{Mn}.zip"
    zp.unlink(missing_ok=True)
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, Path(f"harfi_round6_{Mn}") / p.relative_to(out))
    print(zp.name, "written")
print(f"leak check passed: {len(EVAL_ONLY_WORDS):,} eval-only words and {len(EVAL_ONLY_GRAMS):,} eval-only 4-word "
      "sequences, none in any task file")
