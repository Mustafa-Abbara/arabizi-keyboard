"""B0: the rule-based baseline (roadmap P3 step 2), and the reference for the Swift fallback (P5).

Each Arabizi word is converted by, in order:
1. small attached words (clitics: w, bel, la, 3al…) joined to the converted next word;
2. words the Arabic keeps in Latin (English, names), kept exactly as typed;
3. the word dictionary learned from the training split (data/rules/arabizi_lexicon.json);
4. letter rules (data/rules/arabizi_to_arabic.json).
Numbers, links, mentions and emoji are never changed; ? , ; become ؟ ، ؛.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter, defaultdict
from functools import cache
from pathlib import Path

from arabizi_eval import metrics as M
from arabizi_eval import pairs as P

RULES_PATH = P.ROOT / "data" / "rules" / "arabizi_to_arabic.json"
LEXICON_PATH = P.ROOT / "data" / "rules" / "arabizi_lexicon.json"
TOKEN = re.compile(r"^(\W*)(.*?)(\W*)$")
WORD = re.compile(r"^[a-z0-9']+$")
LATIN = re.compile(r"[A-Za-z]")
VOWELS = set("aeiou")
MIN_SHARE = 0.5  # a dictionary entry needs at least half of a word's aligned occurrences


def _clean(table: dict) -> dict:
    return {k: v for k, v in table.items() if not k.startswith("_")}


@cache
def load_rules(path: Path = RULES_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@cache
def load_lexicon(path: Path = LEXICON_PATH) -> dict:
    if not path.exists():
        return {"words": {}, "keep_latin": [], "built_from": {}}
    return json.loads(path.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- letter rules

def letters(word: str, rules: dict) -> str:
    """Convert one lowercase word letter by letter (used only for words not in the dictionary)."""
    table = rules["letters"]
    for ending, arabic in _clean(table.get("word_endings", {})).items():
        if word.endswith(ending) and len(word) > len(ending) + 2:
            return letters(word[: -len(ending)], rules) + arabic
    sequences, consonants, vowels = table["sequences"], table["consonants"], table["vowels"]
    short = len(word) <= table["short_word_max_len"]
    out, i = "", 0
    previous = ""  # the last single consonant written, for collapsing doubles (not a letter inside "sh", "kh"…)
    while i < len(word):
        pair = word[i:i + 2]
        if len(pair) == 2 and pair in sequences:
            if i == 0 and pair[0] in VOWELS:  # initial long vowel: alif with hamza, then the vowel letter
                out += vowels["initial"][pair[0]] + ("" if sequences[pair] == "ا" else sequences[pair])
            else:
                out += sequences[pair]
            previous = ""
            i += 2
            continue
        char = word[i]
        if char in VOWELS:
            if i == 0:
                out += vowels["initial"][char]
            elif i == len(word) - 1:
                out += vowels["final_e_short_word"] if char == "e" and short else vowels["final"][char]
            else:
                out += vowels["medial"][char]
        elif char in consonants:
            doubled = table["collapse_doubled_consonants"] and previous == char
            out += "" if doubled else consonants[char]
            previous = char
            i += 1
            continue
        elif char != "'":
            out += char
        previous = ""
        i += 1
    return out


# --------------------------------------------------------------------------- conversion

def join_clitic(prefix: str, word: str) -> str:
    """Attach a clitic without doubling the article: بال + البيت = بالبيت, ل + البيت = للبيت, لل + بيت = للبيت."""
    if word.startswith("ال"):
        if prefix.endswith("ال") or prefix == "لل":
            return prefix + word[2:]
        if prefix == "ل":
            return prefix + word[1:]
    return prefix + word

class RuleConverter:
    def __init__(self, rules: dict | None = None, lexicon: dict | None = None):
        self.rules = rules or load_rules()
        lexicon = lexicon or load_lexicon()
        self.words: dict[str, str] = lexicon["words"]
        self.keep_latin = set(lexicon["keep_latin"])
        self.clitics = _clean(self.rules["clitics"])
        self.punctuation = self.rules["punctuation"]

    def _punct(self, text: str) -> str:
        return "".join(self.punctuation.get(c, c) for c in text)

    def _untouched(self, token: str, core: str) -> bool:
        return (not core or P.NUMBER.fullmatch(core) is not None or P.UNTOUCHED.fullmatch(token) is not None
                or not core.isascii())

    def _is_latin_kept(self, core: str) -> bool:
        return core.lower() in self.keep_latin and not any(ch.isdigit() for ch in core)

    def word(self, core: str) -> str:
        lower = core.lower()
        if self._is_latin_kept(core):
            return core
        if lower in self.words:
            return self.words[lower]
        return letters(lower, self.rules) if WORD.match(lower) else core

    def convert(self, text: str) -> str:
        tokens = text.split(" ")
        out: list[str] = []
        i = 0
        while i < len(tokens):
            token = tokens[i]
            lead, core, trail = TOKEN.match(token).groups()
            if self._untouched(token, core):
                out.append(self._punct(lead) + core + self._punct(trail) if core and not P.UNTOUCHED.fullmatch(token)
                           else token)
                i += 1
                continue
            if core.lower() in self.clitics and not trail:
                # Collect a run of clitics (w el bet: و + ال) and attach them to the next real word.
                prefixes, j = [], i
                while j < len(tokens):
                    j_lead, j_core, j_trail = TOKEN.match(tokens[j]).groups()
                    if j_core.lower() not in self.clitics or (j > i and j_lead) or j_trail:
                        break
                    prefixes.append(self.clitics[j_core.lower()])
                    j += 1
                attached = None
                if j < len(tokens):
                    n_lead, n_core, n_trail = TOKEN.match(tokens[j]).groups()
                    if not n_lead and n_core and not self._untouched(tokens[j], n_core) \
                            and not self._is_latin_kept(n_core):
                        attached = self.word(n_core)
                        for prefix in reversed(prefixes):
                            attached = join_clitic(prefix, attached)
                        out.append(self._punct(lead) + attached + self._punct(n_trail))
                        i = j + 1
                        continue
                # Before an English word, a number or the end of the text, the clitics stay a separate word.
                joined = ""
                for prefix in reversed(prefixes):
                    joined = join_clitic(prefix, joined) if joined else prefix
                out.append(self._punct(lead) + joined)
                i = j
                continue
            out.append(self._punct(lead) + self.word(core) + self._punct(trail))
            i += 1
        return " ".join(out)


# --------------------------------------------------------------------------- dictionary building

def _aligned(arabizi_tokens: list[str], arabic_tokens: list[str], clitics: dict) -> list[tuple[str, str]] | None:
    """Word pairs when the two sides line up, directly or after joining clitics to the next word."""
    if len(arabizi_tokens) == len(arabic_tokens):
        return list(zip(arabizi_tokens, arabic_tokens, strict=True))
    merged, i = [], 0
    while i < len(arabizi_tokens):
        word = arabizi_tokens[i]
        if word in clitics and i + 1 < len(arabizi_tokens):
            merged.append((clitics[word], arabizi_tokens[i + 1]))
            i += 2
        else:
            merged.append(("", word))
            i += 1
    if len(merged) != len(arabic_tokens):
        return None
    pairs = []
    for (prefix, word), arabic in zip(merged, arabic_tokens, strict=True):
        if prefix == "ل" and arabic.startswith("لل"):
            pairs.append((word, "ال" + arabic[2:]))  # la beit -> للبيت = ل + البيت: the word keeps its article
            continue
        if prefix and not arabic.startswith(prefix):
            continue
        pairs.append((word, arabic[len(prefix):] if prefix else arabic))
    return pairs


def build_lexicon(rows: list[dict], rules: dict | None = None) -> dict:
    """Learn the word dictionary and the keep-Latin list from training rows only."""
    if any(r.get("split") != "train" for r in rows):
        raise ValueError("the B0 dictionary may only be built from the train split")
    rules = rules or load_rules()
    clitics = _clean(rules["clitics"])
    seen: dict[str, Counter] = defaultdict(Counter)
    latin_kept: Counter = Counter()
    latin_converted: Counter = Counter()
    aligned_rows = 0
    for row in rows:
        arabizi = [t.lower() for t in M.tokens(row["arabizi"])]
        pairs = _aligned(arabizi, M.tokens(row["arabic"]), clitics)
        if pairs is None:
            continue
        aligned_rows += 1
        for word, arabic in pairs:
            if not WORD.match(word) or not arabic or P.NUMBER.fullmatch(word):
                continue
            if LATIN.search(arabic):
                if arabic.lower() == word:
                    latin_kept[word] += 1
                continue
            latin_converted[word] += 1
            seen[word][arabic] += 1
    words = {}
    for word, candidates in seen.items():
        best, count = candidates.most_common(1)[0]
        if word not in clitics and count / sum(candidates.values()) >= MIN_SHARE:
            words[word] = best
    keep = sorted(w for w, n in latin_kept.items() if n > latin_converted[w])
    methods = Counter(r["method"] for r in rows)
    digest = hashlib.sha256("".join(sorted(r["id"] for r in rows)).encode()).hexdigest()[:16]
    return {
        "_comment": "Generated by `pairs lexicon` from the train split only (never dev or test). Do not edit by hand; "
                    "change the data or data/rules/arabizi_to_arabic.json and rebuild.",
        "version": 1,
        "built_from": {"rows": len(rows), "aligned_rows": aligned_rows, "by_method": dict(sorted(methods.items())),
                       "row_ids_sha256_16": digest, "min_share": MIN_SHARE},
        "keep_latin": keep,
        "words": dict(sorted(words.items())),
    }
