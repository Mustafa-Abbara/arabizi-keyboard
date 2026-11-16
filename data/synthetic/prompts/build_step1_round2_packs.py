"""Round-2 add-ons for the three machine packs: chats2/ + RUN_ALL_2.md, dropped into each machine's existing folder.
Word lists exclude every word round 1 gave the same kind of round, and are exclusive across machines."""
import re, sys
from pathlib import Path

REPO = Path(sys.argv[1])
SCR = Path(__file__).parent
v3 = (SCR / "build_agent_v3.py").read_text(encoding="utf-8")
sys.argv = [sys.argv[0], str(REPO)]
exec(v3[: v3.index("MACHINES = {")])            # vocabulary, pools, take(), rng
exec(v3[v3.index("SPELLINGS ="): v3.index("\nbase = (REPO")])  # rule()
import collections, random, shutil, zipfile     # noqa: E402  (also imported by the exec'd code)

# --- what round 1 used, per kind, read from the round-1 packs ---
KIND_OF = {"new forms": "inflect", "low-frequency": "low", "common words": "common"}
used1 = collections.defaultdict(set)
lenient = {disp[k]: k for k in disp}
for M in "ABC":
    for f in (REPO / f"build/harfi_pack_{M}/chats").glob("*.md"):
        for kind, block in re.findall(r"\*\*Kind: (new forms|low-frequency|common words)[^\n]*\n\n([^\n]+)\n\n",
                                      f.read_text(encoding="utf-8")):
            used1[KIND_OF[kind]].update(lenient[w.strip()] for w in block.split("،"))
print({k: len(v) for k, v in used1.items()})

rng.seed(2027)
USED.clear()
common_pool = common - used1["common"] - used1["inflect"]
inflect_pool = (mid | common) - used1["inflect"] - common_pool  # new forms of known words not inflected in round 1
low_pool = low - used1["low"]
print("left: inflect", len(inflect_pool), "low", len(low_pool), "common", len(common_pool))

MACHINES2 = {
    "A": {"theme": "school, kids, grandparents and the village",
          "new": ["breakfast, the bakery, the butcher and the grocer", "the coast: Jbeil, Batroun, Jounieh, the beach",
                  "slang for gossip, flirting and nicknames", "French phrases and expressions in Lebanese chat",
                  "cleaning, laundry, the kitchen and appliances", "religious and national holidays and their customs",
                  "babies, pregnancy and raising children"]},
    "B": {"theme": "jobs, studying abroad and paperwork",
          "new": ["fast food, delivery apps and ordering", "Achrafieh, Hamra, Gemmayzeh, Mar Mikhael and Beirut life",
                  "slang for money, being broke and prices", "English tech and office words in Lebanese",
                  "government paperwork, passports, the municipality, the electricity bill",
                  "sports, football teams, the gym and diets", "TV series, music, concerts and celebrities (no real names)"]},
    "C": {"theme": "friends, nights out and weekend plans",
          "new": ["fruit, vegetables, the market and seasonal produce", "hiking, nature, snow, the cedars and camping",
                  "slang for fights, making up and friendship", "Armenian, Turkish and Persian loanwords in Lebanese",
                  "clothes, fashion, malls, the tailor and the hairdresser", "weather, storms, heat waves and the sea",
                  "animals, pets, farm animals and birds"]},
}
TRAPS = ["hamza (أ / إ / ء / ؤ / ئ), final ة vs ه vs ا, long vowels the Arabizi drops",
         "the article الـ with sun letters, attached words (و، بـ، لـ، عالـ), English words with an Arabic prefix (ال wifi, عم ب check)"]
plans = {}
for M, cfg in MACHINES2.items():
    rounds = [("inflect", None, take(inflect_pool, 30)) for _ in range(10)]
    rounds += [("low", None, take(low_pool, 60)) for _ in range(14)]
    rounds += [("new", t, None) for t in cfg["new"]]
    rounds += [("common", None, take(common_pool, 20)) for _ in range(1)]
    rounds += [("context", cfg["theme"], None) for _ in range(2)]
    rounds += [("traps", t, None) for t in TRAPS]
    assert len(rounds) == 36
    rng.shuffle(rounds)
    plans[M] = rounds

base = (REPO / "build/harfi_generator_pack/1_generator_prompt.md").read_text(encoding="utf-8")
head = base[: base.index("## What to write about")]
head = ("# Task file (round 2)\n\nThis is one of six round-2 task files. Follow it as part of `RUN_ALL_2.md`. "
        "Do not ask anything.\n\n" + head)
round1_task = (REPO / "build/harfi_pack_A/chats/chat_1.md").read_text(encoding="utf-8")
tail_tmpl = round1_task[round1_task.index("\nIn every round:"):]
run_all = (REPO / "build/harfi_pack_A/RUN_ALL.md").read_text(encoding="utf-8")

for M, rounds in plans.items():
    THEME = MACHINES2[M]["theme"]
    out = REPO / "build" / f"harfi_pack_{M}_round2"
    if out.exists():
        shutil.rmtree(out)
    (out / "chats2").mkdir(parents=True)
    for c in range(6):
        chat = c + 1
        parts = []
        for r, (kind, topic, words) in enumerate(rounds[c * 6:(c + 1) * 6], 1):
            n = c * 6 + r
            parts.append(f"### Round {r}: ids {M}2-T{n:02d}-001 to {M}2-T{n:02d}-050\n\n{rule(kind, topic, words)}\n")
        tail = (tail_tmpl.replace("output/A_chat_1.jsonl", f"output/{M}2_chat_{chat}.jsonl")
                .replace("`RUN_ALL.md`", "`RUN_ALL_2.md`").replace('"id": "A-T01-001"', f'"id": "{M}2-T{c * 6 + 1:02d}-001"')
                .replace("of any earlier pair", "of any earlier pair (round 1's included)"))
        assert f"{M}2_chat_{chat}" in tail and f'"{M}2-T' in tail
        text = (head + "## What to write\n\n300 pairs in 6 rounds of 50, 4 to 20 words each. Each round has its own "
                "kind and ids. Write a field \"kind\" in every line (inflect, low, new, common, context or traps).\n\n"
                + "\n".join(parts) + tail)
        (out / "chats2" / f"chat_{chat}.md").write_text(text, encoding="utf-8")
    ra = (run_all.replace("# RUN ALL: your instructions (machine A)", f"# RUN ALL, round 2 (machine {M})")
          .replace("six task files in `chats/`", "six round-2 task files in `chats2/`")
          .replace("chats/chat_1.md … chat_6.md    the six tasks", "chats2/chat_1.md … chat_6.md   the six round-2 tasks")
          .replace("`chats/chat_N.md`", "`chats2/chat_N.md`")
          .replace("Read every `output/A_chat_*.jsonl` written so far.",
                   f"Read every `output/{M}_chat_*.jsonl` (round 1, already done) and `output/{M}2_chat_*.jsonl` written so far.")
          .replace("output/A_chat_N.jsonl", f"output/{M}2_chat_N.jsonl")
          .replace("output/A_DONE.txt", f"output/{M}2_DONE.txt").replace("output/A_progress.txt", f"output/{M}2_progress.txt"))
    ra = ra.replace("## The folder", "Round 1 is already done: its files in `output/` must not be changed.\n\n## The folder")
    assert "A_" not in ra.replace(f"{M}_", "") or M == "A", M
    (out / "RUN_ALL_2.md").write_text(ra, encoding="utf-8")
    zp = REPO / "build" / f"harfi_pack_{M}_round2.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(out))
    print(zp, dict(collections.Counter(k for k, _, _ in rounds)))
