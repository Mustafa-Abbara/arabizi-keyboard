"""Round 5: one prompt design aimed at v4's measured gaps, built into a standalone pack per machine (A, B, C).
Word lists come from v4's training vocabulary, are exclusive across machines, and skip words earlier rounds already
gave to the same kind of round."""
import collections, json, random, re, shutil, sys, zipfile
from pathlib import Path

REPO = Path(sys.argv[1]); SCR = Path(__file__).parent
sys.path.insert(0, str(REPO / "eval" / "src"))
from arabizi_eval import metrics as M
from arabizi_eval.pairs import normalize_arabic

PAIRS = 50
STYLE_IDS = ["hw-2502", "hw-2271", "hw-2402", "hw-4854", "hw-6190", "hw-4541", "hw-6126", "hw-5569", "hw-3652",
             "hw-3430", "hw-6691", "hw-6525", "hw-2405", "hw-2281", "hw-6290"]
lk = lambda w: normalize_arabic(w, lenient=True)
jl = lambda p: [json.loads(l) for l in Path(p).read_text(encoding="utf-8").splitlines() if l.strip()]

# ---- v4's training vocabulary ----
train = [r for f in sorted((REPO / "data/pairs").glob("train-*.jsonl")) for r in jl(f)] + \
        jl(REPO / "build/v4_data/train-ai_checked.synthetic.jsonl")
ar, shown, az = collections.Counter(), collections.defaultdict(collections.Counter), collections.Counter()
for r in train:
    for w in M.tokens(normalize_arabic(r["arabic"])):
        ar[lk(w)] += 1; shown[lk(w)][w] += 1
    az.update(w.lower() for w in M.tokens(r["arabizi"]))
disp = {k: c.most_common(1)[0][0] for k, c in shown.items()}
pure = [k for k in ar if re.fullmatch("[ء-ي]{3,}", disp[k])]

# ---- what earlier rounds already gave to each kind ----
KIND = {"new forms": "inflect", "low-frequency": "low", "common words": "common"}
used = collections.defaultdict(set)
for d in ["harfi_pack_{M}/chats", "harfi_pack_{M}_round2/chats2", "harfi_pack_{M}_round3/chats3"]:
    for m in "ABC":
        for f in (REPO / "build" / d.format(M=m)).glob("*.md"):
            for kind, block in re.findall(r"\*\*Kind: (new forms|low-frequency|common words)[^\n]*\n\n([^\n]+)\n\n",
                                          f.read_text(encoding="utf-8")):
                used[KIND[kind]].update(lk(w.strip()) for w in block.split("،"))
rng = random.Random(2029)
TAKEN = set()


def take(pool, n):
    picked = rng.sample(sorted(pool - TAKEN), n)
    TAKEN.update(picked)
    return [disp[k] for k in picked]


inflect_pool = {k for k in pure if 2 <= ar[k] <= 40} - used["inflect"]
low_pool = {k for k in pure if ar[k] == 1} - used["low"]
heavy_pool = {k for k in pure if ar[k] >= 3 and re.search("[طصضظ]", k)}
print("pools: inflect", len(inflect_pool), "low", len(low_pool), "heavy", len(heavy_pool))

CONTEXT_WORDS = ("la (لا / لـ), ma3 (مع), wala (ولا / والله), men / min (من / مين), 3amel / 3emel (عامل / عمل), "
                 "ma (ما), fi / fiye (في / فيي), w, b, l, 3a / 3al, hek (هيك), ba3d (بعد / بعض)")
MACHINES = {
    "A": {"themes": ["family plans and visits", "kids, school and homework", "the neighbourhood and the building",
                     "food, cooking and inviting people over", "weddings, birthdays and occasions",
                     "health, the doctor and the pharmacy", "complaining about prices and bills",
                     "the village, the garden and summer", "phone calls and voice notes"],
          "latin": ["school and kids' activities", "food, cafes and restaurants", "shopping and clothes",
                    "TV, series and music", "the house and appliances"],
          "new": ["the souk, the butcher, the baker and small shops", "old Lebanese sayings and grandparents' words",
                  "kitchen tools, pots, spices and preserves", "trees, flowers, birds and the countryside"]},
    "B": {"themes": ["work, the office and colleagues", "university, exams and projects",
                     "money, banks, dollars and lira", "traffic, taxis and directions",
                     "online shopping and deliveries", "freelancing, clients and deadlines",
                     "sports, the gym and diets", "news and gossip among friends", "group chats and plans"],
          "latin": ["office and meetings", "university and online classes", "phones, apps and gaming",
                    "sports and the gym", "banks, payments and cards"],
          "new": ["government paperwork and official errands", "car parts, the garage and driving",
                  "the internet, routers, chargers and devices", "jobs, trades and workshops"]},
    "C": {"themes": ["nights out and weekend plans", "road trips, the mountains and the sea",
                     "friends teasing each other", "relationships, crushes and break-ups",
                     "travel, the airport and family abroad", "parties, music and dancing",
                     "pets and animals", "the weather and the seasons", "fashion, hair and getting ready"],
          "latin": ["going out, bars and cafes", "travel, airports and hotels", "fashion and beauty",
                    "music, concerts and parties", "French expressions Lebanese use"],
          "new": ["beaches, boats, fishing and the coast", "nightlife, desserts and late-night snacks",
                  "hiking, snow, camping and nature", "beauty salons, barbers and cosmetics"]},
}


def rule(kind, x):
    if kind == "context":
        return (f"**Kind: words that need the sentence to decide.** Long messages (12 to 25 words) about {x}, in which "
                f"common words must be read from the sentence: {CONTEXT_WORDS}. Each pair has at least two of them, "
                "placed where the wrong reading is tempting (for example `la` as لا \"no\" versus لـ \"to\", `wala` as "
                "ولا versus والله, `3amel` as عامل versus عمل). Put those words' Arabic in \"rare_words\".")
    if kind == "heavy":
        return ("**Kind: heavy letters typed as plain letters.** These words contain ط ص ض ظ:\n\n" + "، ".join(x) +
                "\n\nEach pair uses one or two of them, typed with plain t, s, d, z (never 6 or 9), in a real-chat "
                "message of 10 to 25 words. Use at least 25 different words from the list; skip any you are not sure "
                "of. Put the list words you used in \"rare_words\".")
    if kind == "latin":
        return (f"**Kind: English and French that stay Latin.** Messages about {x} that mix Arabizi with at least two "
                "English or French words or short phrases that must stay in Latin exactly as typed (everyday words, "
                "names of foods, brands, places abroad, set phrases like `a demain`, `ca va`, `by the way`), next to "
                "loanwords that Lebanese write in Arabic because Arabic grammar is on them (`talfanetlak`, `masajtak`, "
                "`ma 3am yechtghel el wifi` → ال wifi). Put the Latin words that stay Latin in \"rare_words\", as typed.")
    if kind == "inflect":
        return ("**Kind: new forms of known words.** The model knows these words in some forms but fails on forms it "
                f"hasn't seen:\n\n" + "، ".join(x) + "\n\nEach pair uses one of these words in a form the training "
                "data does NOT have: another pronoun ending (ـي، ـك، ـو، ـا / ـها، ـنا، ـكن، ـن), a plural or dual, "
                "another person or tense of a verb, or with attached و / بـ / لـ / الـ / عالـ, inside a real-chat "
                "message of 10 to 25 words. Use as many different words from the list as you can; skip any you are "
                "not sure of. Put the new form in \"rare_words\". The form must not be in reference/known_words.tsv.")
    if kind == "low":
        return ("**Kind: rare words.** These words appear only once in the training data:\n\n" + "، ".join(x) +
                "\n\nEach pair uses one or two of them naturally, in the form listed or a natural variation, inside a "
                "real-chat message of 10 to 25 words. Use at least 40 different words from the list. Skip any word you "
                "are not sure of (a name, a typo, a word you don't know). Put the list words you used in \"rare_words\".")
    return (f"**Kind: new vocabulary. Topic: {x}.** Each pair contains at least one less common word about the topic "
            "that is not in reference/known_words.tsv (and is not just a word from that file with a prefix added), "
            "inside a real-chat message of 10 to 25 words. Put it in \"rare_words\". Never invent a word.")


CHECK = (
    "\n## Check your own work in every round\n\n"
    "Do this checking silently: never write out drafts, reasoning, explanations or notes about your thinking, in the "
    "chat or in any file. The output files contain only the final pairs.\n\n"
    "Draft the round's pairs, then re-read every pair as a strict reviewer who assumes there are mistakes:\n\n"
    "1. Is every Arabic word what the Arabizi word means in this sentence? (Watch la, ma3, wala, men, 3amel, w, b, l, ma.)\n"
    "2. Nothing added, dropped, translated or explained?\n"
    "3. Is every word a real, current Lebanese word, used the Lebanese way?\n"
    "4. No standard Arabic (MSA) where Lebanese is spoken?\n"
    "5. Spelling exactly by the guide (hamza, ة / ه, long vowels, the article, attached words)?\n"
    "6. English, French, numbers, times and emoji exactly as typed?\n"
    "7. Does the Arabizi look like a real phone message (Rule 2): long enough, messy, no 6 or 9, no final punctuation?\n"
    "8. No diacritics, no tatweel?\n\n"
    "Fix what you are sure how to fix. Remove any pair you still doubt and write a replacement you are sure of.\n")

head = (SCR / "round5_head.md").read_text(encoding="utf-8")
style_rows = {r["id"]: r for r in jl(REPO / "data/pairs/train-hand.jsonl") if r["id"] in STYLE_IDS}
style = "\n".join(f"- {style_rows[i]['arabizi']}  →  {style_rows[i]['arabic']}" for i in STYLE_IDS)
msa = json.loads((REPO / "data/rules/msa_words.json").read_text(encoding="utf-8"))["words"]
head = (head.replace("{{STYLE}}", style).replace("{{MSA}}", ", ".join(f"{k} → {v}" for k, v in msa.items()))
        .replace("{{SPELLING}}", (REPO / "docs/SPELLING.md").read_text(encoding="utf-8").strip()))
assert "{{" not in head
known_w = "".join(f"{disp[k]}\t{n}\n" for k, n in ar.most_common())
known_a = "".join(f"{w}\t{n}\n" for w, n in az.most_common())
run_all_t = (SCR / "RUN_ALL_5.md").read_text(encoding="utf-8")

for Mn, cfg in MACHINES.items():
    rounds = [("context", t) for t in cfg["themes"]]
    rounds += [("heavy", take(heavy_pool, 30)) for _ in range(5)]
    rounds += [("latin", t) for t in cfg["latin"]]
    rounds += [("inflect", take(inflect_pool, 30)) for _ in range(7)]
    rounds += [("low", take(low_pool, 60)) for _ in range(6)]
    rounds += [("new", t) for t in cfg["new"]]
    assert len(rounds) == 36
    rng.shuffle(rounds)
    out = REPO / "build" / f"harfi_round5_{Mn}"
    shutil.rmtree(out, ignore_errors=True)
    for d in ("chats5", "reference", "output"):
        (out / d).mkdir(parents=True)
    for c in range(6):
        parts = []
        for r, (kind, x) in enumerate(rounds[c * 6:(c + 1) * 6], 1):
            n = c * 6 + r
            parts.append(f"### Round {r}: ids {Mn}5-T{n:02d}-001 to {Mn}5-T{n:02d}-{PAIRS:03d}\n\n{rule(kind, x)}\n")
        task = (f"## What to write\n\n300 pairs in 6 rounds of 50. Each round has its own kind and ids. Write a field "
                "\"kind\" in every line (context, heavy, latin, inflect, low or new). Every pair follows Rule 2 (real "
                "phone chat).\n\n" + "\n".join(parts) +
                "\nIn every round: every pair must differ in vocabulary and structure, with no templates, no repeated "
                "openings and no near-copies of any earlier pair or of the examples above. No real people's full names, "
                "phone numbers or private details; common first names only.\n" + CHECK +
                f"\n## How to deliver\n\nSave the pairs in **output/{Mn}5_chat_{c + 1}.jsonl**, appending each round as "
                "soon as it is checked, exactly as `RUN_ALL_5.md` says. Do not print the pairs in the chat.\n\n"
                "## Line format\n\nOne JSON object per line, nothing else on the line:\n\n"
                f'{{"id": "{Mn}5-T{c * 6 + 1:02d}-001", "kind": "context", "arabizi": "...", "arabic": "...", '
                '"rare_words": ["..."], "check": ["<word>: <short reason>"]}\n\n'
                "\"check\" lists every word a careful native speaker might spell differently or not know, each with a "
                "reason of at most five words; it may be empty only if you have no doubt about any word.\n")
        (out / "chats5" / f"chat_{c + 1}.md").write_text(head + task, encoding="utf-8")
    (out / "reference/known_words.tsv").write_text(known_w, encoding="utf-8")
    (out / "reference/known_arabizi.tsv").write_text(known_a, encoding="utf-8")
    (out / "RUN_ALL_5.md").write_text(run_all_t.replace("{{M}}", Mn), encoding="utf-8")
    (out / "output/.keep").write_text("", encoding="utf-8")
    zp = REPO / "build" / f"harfi_round5_{Mn}.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, Path(f"harfi_round5_{Mn}") / p.relative_to(out))
    print(zp, dict(collections.Counter(k for k, _ in rounds)))
