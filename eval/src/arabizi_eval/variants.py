"""Make extra Arabizi spellings of training pairs (roadmap P2 step 5, ADR 0012).

Each variant re-spells the Arabizi side of an existing pair with alternatives real typists use
(data/rules/arabizi_variants.json) and keeps the same Arabic. It never touches words that stay in
Latin in the Arabic (English, names like LAU), numbers, links, mentions or emoji. Output is
deterministic for a given seed, so the file is regenerated rather than committed.
"""

from __future__ import annotations

import json
import random
import re
from collections import Counter
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from arabizi_eval import pairs as P

RULES_PATH = P.ROOT / "data" / "rules" / "arabizi_variants.json"
GENERATOR = "arabizi_eval.variants"
TOKEN = re.compile(r"^(\W*)(.*?)(\W*)$")  # leading punctuation, core, trailing punctuation
WORD = re.compile(r"^[a-z0-9']+$")
LATIN_IN_ARABIC = re.compile(r"[A-Za-z][A-Za-z0-9'&.-]*")
# Punctuation dropped by the drop_punctuation rule, with the Arabic forms it maps to (SPELLING.md 7).
DROPPABLE = re.compile(r"[?,;.!؟،؛]")
PLACEHOLDER_BASE = 0xE000  # Unicode private-use area: never in real text


@dataclass(frozen=True)
class WordRule:
    name: str
    pattern: re.Pattern
    replace: tuple[str, ...]
    p: float
    min_len: int


@dataclass(frozen=True)
class Rules:
    version: int
    word_rules: tuple[WordRule, ...]
    sentence_p: dict[str, float]


@cache
def load_rules(path: Path = RULES_PATH) -> Rules:
    data = json.loads(path.read_text(encoding="utf-8"))
    word_rules = tuple(
        WordRule(r["name"], re.compile(r["pattern"]), tuple(r["replace"]), float(r["p"]), int(r.get("min_len", 0)))
        for r in data["word_rules"]
    )
    return Rules(int(data["version"]), word_rules, {r["name"]: float(r["p"]) for r in data["sentence_rules"]})


def protected_words(arabic: str) -> set[str]:
    """Latin words that the Arabic keeps as typed; their Arabizi spelling must not change."""
    return {w.lower().strip(".'") for w in LATIN_IN_ARABIC.findall(arabic)}


def _mask(text: str, slots: list[str]) -> str:
    """Hide numbers and links behind placeholders so punctuation inside them survives."""
    def hide(match: re.Match) -> str:
        slots.append(match.group(0))
        return chr(PLACEHOLDER_BASE + len(slots) - 1)  # one private-use character: no digits for NUMBER to match
    return P.NUMBER.sub(hide, P.UNTOUCHED.sub(hide, text))


def _unmask(text: str, slots: list[str]) -> str:
    return "".join(slots[ord(c) - PLACEHOLDER_BASE] if PLACEHOLDER_BASE <= ord(c) < PLACEHOLDER_BASE + len(slots)
                   else c for c in text)


def drop_punctuation(arabizi: str, arabic: str) -> tuple[str, str]:
    """Remove ? , ; . ! (and ؟ ، ؛) from both sides, outside numbers and links."""
    out = []
    for text in (arabizi, arabic):
        slots: list[str] = []
        stripped = DROPPABLE.sub(" ", _mask(text, slots))
        out.append(" ".join(_unmask(stripped, slots).split()))
    return out[0], out[1]


def respell_word(word: str, rules: Rules, rng: random.Random, used: Counter) -> str:
    """Apply each word rule in a random order; each match fires with the rule's probability."""
    for rule in rng.sample(rules.word_rules, len(rules.word_rules)):
        if len(word) < rule.min_len:
            continue

        def fire(match: re.Match, rule: WordRule = rule) -> str:
            if rng.random() >= rule.p:
                return match.group(0)
            used[rule.name] += 1
            return match.expand(rng.choice(rule.replace))

        word = rule.pattern.sub(fire, word)
    return word


def make_variant(row: dict, rules: Rules, rng: random.Random, used: Counter) -> tuple[str, str]:
    """One re-spelling of `row`. Returns (arabizi, arabic); the Arabic only changes when punctuation is dropped."""
    arabizi, arabic = row["arabizi"], row["arabic"]
    if rng.random() < rules.sentence_p.get("drop_punctuation", 0):
        new_arabizi, new_arabic = drop_punctuation(arabizi, arabic)
        if new_arabizi != arabizi:
            used["drop_punctuation"] += 1
            arabizi, arabic = new_arabizi, new_arabic
    keep = protected_words(arabic)
    lowercase = rng.random() < rules.sentence_p.get("lowercase", 0)
    tokens = []
    for token in arabizi.split(" "):
        lead, core, trail = TOKEN.match(token).groups()
        if not core or core.lower() in keep or P.NUMBER.fullmatch(core) or P.UNTOUCHED.fullmatch(token):
            tokens.append(token)
            continue
        if lowercase and core != core.lower():
            used["lowercase"] += 1
            core = core.lower()
        if WORD.match(core):
            core = respell_word(core, rules, rng, used)
        tokens.append(lead + core + trail)
    return " ".join(tokens), arabic


def generate(parents: list[dict], per_row: int, seed: int, rules: Rules | None = None,
             max_tries: int = 12, first_id: int = 1) -> tuple[list[dict], Counter, int]:
    """Variants for every parent. Returns (rows, rule usage counts, parents that got fewer than per_row)."""
    rules = rules or load_rules()
    used: Counter = Counter()
    rows: list[dict] = []
    short = 0
    for parent in parents:
        rng = random.Random(f"{seed}:{parent['id']}")  # stable per parent, whatever the order
        # A variant is new only if its (Arabizi, Arabic) pair is: dropping punctuation changes the Arabic too.
        seen = {(P.normalize_arabizi(parent["arabizi"]), parent["arabic"])}
        made = 0
        for _ in range(max_tries):
            if made == per_row:
                break
            arabizi, arabic = make_variant(parent, rules, rng, used)
            key = (P.normalize_arabizi(arabizi), arabic)
            if key in seen:
                continue
            row = {"id": f"rv-{first_id + len(rows):04d}", "arabizi": arabizi, "arabic": arabic, "accepted": {},
                   "method": "rule_variant", "writer": f"{GENERATOR} v{rules.version}", "checked_by": None,
                   "source": f"rule-variants-v{rules.version}-seed{seed}", "split": "train",
                   "date": parent["date"], "parent": parent["id"]}
            if P.row_errors(row, "train", "rule_variant"):
                continue
            seen.add(key)
            rows.append(row)
            made += 1
        short += made < per_row
    return rows, used, short
