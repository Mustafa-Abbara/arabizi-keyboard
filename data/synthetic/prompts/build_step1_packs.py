"""Agent pack v2: rounds aimed at v3's measured dev errors (new forms of known words, low-frequency words, new
vocabulary, common words in unusual spellings, context words, spelling traps). Train files only."""
import collections, json, random, re, shutil, sys, zipfile
from pathlib import Path

REPO = Path(sys.argv[1])
SCR = Path(__file__).parent
sys.path.insert(0, str(REPO / "eval" / "src"))
from arabizi_eval import metrics as M
from arabizi_eval.pairs import normalize_arabic

PAIRS, PER_CHAT = 50, 6
rng = random.Random(2026)

# --- vocabulary from the training files only ---
ar, shown, az = collections.Counter(), collections.defaultdict(collections.Counter), collections.Counter()
for f in sorted((REPO / "data/pairs").glob("train-*.jsonl")):
    for line in f.read_text(encoding="utf-8").splitlines():
        r = json.loads(line)
        for w in M.tokens(normalize_arabic(r["arabic"])):
            k = normalize_arabic(w, lenient=True); ar[k] += 1; shown[k][w] += 1
        az.update(w.lower() for w in M.tokens(r["arabizi"]))
disp = {k: c.most_common(1)[0][0] for k, c in shown.items()}
pure = [k for k in ar if re.fullmatch("[ء-ي]{3,}", disp[k])]


USED = set()  # a word goes to one round only, across all pools and machines


def take(pool, n):
    picked = rng.sample(sorted(pool - USED), n)
    USED.update(picked)
    return [disp[k] for k in picked]


low = {k for k in pure if 1 <= ar[k] <= 3}
mid = {k for k in pure if 5 <= ar[k] <= 24}
common = {k for k in pure if ar[k] >= 25}


MACHINES = {
    "A": {"theme": "family, home and the neighbourhood",
          "new": ["Lebanese dishes and home cooking", "towns and villages of Mount Lebanon and the North",
                  "slang for teasing, joking and complimenting", "French words Lebanese use every day",
                  "the house: furniture, repairs, the building, the generator, water tanks",
                  "family occasions: weddings, baptisms, condolences, visits", "kids, school and parents' talk"]},
    "B": {"theme": "work, university and money",
          "new": ["sweets, bakeries, snacks and street food", "Beirut neighbourhoods, streets and landmarks",
                  "slang for complaining, anger and being tired", "English words adapted with Arabic grammar (talfanetlak, masajtak)",
                  "work, the office, salaries, banks, dollars and lira", "university life, exams, majors, registration",
                  "phones, apps, the internet and social media"]},
    "C": {"theme": "going out, travel and health",
          "new": ["drinks, coffee, juices, cafés and argileh", "the South, the Bekaa and trips around Lebanon",
                  "slang for surprise, excitement and love", "Turkish and old loanwords in Lebanese",
                  "health, the doctor, the pharmacy, hospitals", "cars, the mechanic, taxis, service and traffic",
                  "travel, the airport, visas and relatives abroad"]},
}
TRAPS = ["hamza (أ / إ / ء / ؤ / ئ), final ة vs ه vs ا, long vowels the Arabizi drops",
         "the article الـ with sun letters, attached words (و، بـ، لـ، عالـ), English words with an Arabic prefix (ال wifi, عم ب check)"]
plans = {}
for M, cfg in MACHINES.items():
    rounds = []
    rounds += [("inflect", None, take(mid, 30)) for _ in range(11)]
    rounds += [("low", None, take(low, 60)) for _ in range(9)]
    rounds += [("new", t, None) for t in cfg["new"]]
    rounds += [("common", None, take(common, 25)) for _ in range(5)]
    rounds += [("context", cfg["theme"], None) for _ in range(2)]
    rounds += [("traps", t, None) for t in TRAPS]
    assert len(rounds) == 36
    rng.shuffle(rounds)
    plans[M] = rounds

SPELLINGS = ("aa or a for ع instead of 3; q, k or 2 for ق; 8 or gh for غ; 6 or t for ط; 5 or kh for خ; ch or sh for ش; "
             "ou or u for و; y, yy, ie or ye endings; doubled letters for emphasis; vowels dropped")


def rule(kind, topic, words):
    w = "، ".join(words) if words else ""
    if kind == "inflect":
        return ("**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it "
                f"hasn't seen:\n\n{w}\n\nEach pair uses one of these words in a form the training data does NOT have: "
                "another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, another person or tense "
                "of a verb, or with attached و / بـ / لـ / الـ / عالـ. Use as many different words from the list as you "
                "can; skip any word you are not sure of (a name, a typo, a word you don't know). Put the new form in \"rare_words\". The form must not be in reference/known_words.tsv.")
    if kind == "low":
        return ("**Kind: low-frequency words.** These words appear only 1 to 3 times in the training data, so the "
                f"model barely knows them:\n\n{w}\n\nEach pair uses one or two of them naturally, in the form listed or "
                "a natural variation. Use at least 40 different words from the list. Skip any word you are not sure of "
                "(a name, a typo, a word you don't know). Type them in varied, real Arabizi spellings. Put the list "
                "words you used in \"rare_words\".")
    if kind == "new":
        return (f"**Kind: new vocabulary. Topic: {topic}.** Each pair contains at least one less common word about "
                "the topic that is not in reference/known_words.tsv (and is not just a word from that file with a "
                "prefix added). Put it in \"rare_words\". Never invent a word to meet this rule.")
    if kind == "common":
        return ("**Kind: common words in unusual spellings.** These are frequent words the model knows, but it "
                f"fails when they are typed in a spelling it hasn't seen:\n\n{w}\n\nEach pair uses two or more of "
                f"them, typed in less common but real Arabizi spellings: {SPELLINGS}. At least one typed spelling per "
                "pair must not be in reference/known_arabizi.tsv. Only spellings real Lebanese people use; skip any listed word you are not sure of. Put the "
                "Arabic words whose spelling is unusual in \"rare_words\".")
    if kind == "context":
        return ("**Kind: words that need the sentence to decide.** Everyday chat where a short or ambiguous word's "
                "meaning depends on context: la (لا / لـ), men (من / مين), ma, w, b, l, 3al, 3a, and words often "
                "confused with a similar-looking word (one letter apart in Arabizi, or a verb with and without its b- prefix). "
                "Make the context decide clearly. "
                f"Set the conversations mostly around {topic}. Put the ambiguous words' Arabic in \"rare_words\".")
    return (f"**Kind: spelling traps: {topic}.** Everyday vocabulary, with conversations about {THEME}; every pair contains at least two of these "
            "traps, spelled exactly by the guide. Put the trap words in \"rare_words\".")



base = (REPO / "build/harfi_generator_pack/1_generator_prompt.md").read_text(encoding="utf-8")
head = base[: base.index("## What to write about")]
head = "# Task file\n\nThis is one of six task files. Follow it as part of `RUN_ALL.md`. Do not ask anything.\n\n" + head
known_w = "".join(f"{disp[k]}\t{n}\n" for k, n in ar.most_common())
known_a = "".join(f"{w}\t{n}\n" for w, n in az.most_common())
run_all = (SCR / "RUN_ALL.md").read_text(encoding="utf-8")

for M, rounds in plans.items():
    THEME = MACHINES[M]["theme"]
    name = f"harfi_pack_{M}"
    OUT = REPO / "build" / name
    if OUT.exists():
        shutil.rmtree(OUT)
    for d in ("chats", "reference", "output"):
        (OUT / d).mkdir(parents=True)
    for c in range(6):
        chat = c + 1
        parts = []
        for r, (kind, topic, words) in enumerate(rounds[c * PER_CHAT:(c + 1) * PER_CHAT], 1):
            n = c * PER_CHAT + r
            parts.append(f"### Round {r}: ids {M}-T{n:02d}-001 to {M}-T{n:02d}-{PAIRS:03d}\n\n{rule(kind, topic, words)}\n")
            task = (
                f"## What to write\n\n{PER_CHAT * PAIRS} pairs in {PER_CHAT} rounds of {PAIRS}, 4 to 20 words each. Each round "
                "has its own kind and ids. Write a field \"kind\" in every line (inflect, low, new, common, context or traps).\n\n"
                + "\n".join(parts) +
                "\nIn every round: every pair must differ in vocabulary and structure, with no templates, no repeated openings "
                "and no near-copies of any earlier pair or of the examples above. Use the styles A to E about equally. No real "
                "people's full names, phone numbers or private details; common first names only.\n\n"
                "## Check your own work in every round\n\n"
                "Do this checking silently: never write out drafts, reasoning, explanations or notes about your "
                "thinking, in the chat or in any file. The output files contain only the final pairs.\n\n"
                "Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:\n\n"
                "1. Is every Arabic word what the Arabizi word means in this sentence? (Watch la, men, w, b, l, ma.)\n"
                "2. Nothing added, dropped, translated or explained?\n"
                "3. Is every word a real, current Lebanese word, used the Lebanese way?\n"
                "4. No standard Arabic (MSA) where Lebanese is spoken?\n"
                "5. Spelling exactly by the guide (hamza, ة / ه, long vowels, the article, attached words)?\n"
                "6. English, French, numbers, times and emoji exactly as typed?\n"
                "7. Would a Lebanese person really type the Arabizi this way?\n"
                "8. No diacritics, no tatweel?\n\n"
                "Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.\n\n"
                f"## How to deliver\n\nSave the pairs in **output/{M}_chat_{chat}.jsonl**, appending each round as soon as it is "
                "checked, exactly as `RUN_ALL.md` says. Do not print the pairs in the chat.\n\n"
                "## Line format\n\nOne JSON object per line, nothing else on the line:\n\n"
                f'{{"id": "{M}-T{c * PER_CHAT + 1:02d}-001", "kind": "low", "style": "A", "arabizi": "...", "arabic": "...", '
                '"rare_words": ["..."], "check": ["<word>: <short reason>"]}\n\n'
                "\"style\" is A to E. \"check\" lists every word a careful native speaker might spell differently or not "
                "know, each with a reason of at most five words (for example \"rare word\" or \"hamza unsure\"); it may "
                "be empty only if you have no doubt about any word.\n")
        (OUT / "chats" / f"chat_{chat}.md").write_text(head + task, encoding="utf-8")
    (OUT / "reference/known_words.tsv").write_text(known_w, encoding="utf-8")
    (OUT / "reference/known_arabizi.tsv").write_text(known_a, encoding="utf-8")
    ra = run_all.replace("output/chat_N.jsonl", f"output/{M}_chat_N.jsonl").replace("output/chat_*.jsonl", f"output/{M}_chat_*.jsonl")
    ra = ra.replace("output/DONE.txt", f"output/{M}_DONE.txt").replace("output/progress.txt", f"output/{M}_progress.txt")
    ra = ra.replace("# RUN ALL: your instructions", f"# RUN ALL: your instructions (machine {M})")
    (OUT / "RUN_ALL.md").write_text(ra, encoding="utf-8")
    (OUT / "output/.keep").write_text("", encoding="utf-8")
    zp = REPO / "build" / f"{name}.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.rglob("*")):
            if p.is_file():
                z.write(p, Path(name) / p.relative_to(OUT))
    print(zp, collections.Counter(k for k, _, _ in rounds))
