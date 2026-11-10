"""Word suggestions v2 (ADR 0036): the ↑ list's candidates, their signals and the learned order. The reference for
the Swift port (ArabiziCore), which is checked against fixtures written from here.

For the word being fixed, candidates come from seven sources:
  1. the model's own guesses for that spot (given; the engine computes them);
  2. spellings of the typed word ranked by letter odds, unknown words kept;
  3. known spellings of the typed word (the same options, known words only);
  4. the training data's own spellings of the typed word;
  5. a prefix typed joined to the word (w, b, l, el, bel…) split off, the rest spelled, the Arabic prefix put back;
  6. long-vowel, emphatic and ending variants of the model's word, unknown kept;
  7. the first list (ADR 0027, Suggestions.swift).
Each candidate gets the signals in FEATURES; a logistic ranker (candidate_ranker.json) orders them.

The letter odds (data/rules/spelling_odds.json) come from public training rows only (`pairs spelling-odds`).
"""

from __future__ import annotations

import json
import math
from collections import Counter, defaultdict
from functools import cache, lru_cache
from pathlib import Path

import numpy as np

from arabizi_eval import b0
from arabizi_eval import pairs as P

ODDS_PATH = P.ROOT / "data" / "rules" / "spelling_odds.json"
RANKER_PATH = P.ROOT / "data" / "rules" / "candidate_ranker.json"
LIST_LENGTH = 7  # places on the keyboard; the last keeps the typed word

# ----------------------------------------------------------------------------------------------- spelling options

# What each Arabizi unit may stand for, most usual first ('' = not written). The odds file counts how often each was
# used in the training pairs; these lists only say what is possible.
HAMZA = ["ء", "أ", "ئ", "ؤ", "إ"]
CONSONANTS = {
    "sh": ["ش"], "ch": ["ش"], "kh": ["خ"], "gh": ["غ"], "th": ["ت", "ث", "ذ"], "dh": ["ذ", "ض", "ظ"],
    "3'": ["غ"], "7'": ["خ"],
    "b": ["ب"], "p": ["ب"], "t": ["ت", "ط"], "j": ["ج"], "g": ["ج", "غ", "ق"], "d": ["د", "ض"], "r": ["ر"],
    "z": ["ز", "ظ", "ذ"], "s": ["س", "ص"], "f": ["ف"], "v": ["ف"], "q": ["ق", "ك"], "k": ["ك", "ق"],
    "c": ["ك", "س", "ش"], "l": ["ل"], "m": ["م"], "n": ["ن"], "h": ["ه", "ح", "ة"], "w": ["و"], "y": ["ي"],
    "x": ["كس"], "2": ["ق"] + HAMZA, "3": ["ع"], "5": ["خ"], "6": ["ط"], "7": ["ح"], "8": ["غ", "ق"],
    "9": ["ص", "ق"],
}
VOWELS = {
    "initial": {"a": ["ا", "أ", "ع", "آ", "إ"], "aa": ["ع", "ا", "آ"], "e": ["إ", "ا", "أ", "ع", "ي"],
                "i": ["إ", "ا", "ي"], "o": ["أ", "ا", "و", "ع"], "u": ["أ", "ا", "و"], "ee": ["إي", "ي"],
                "oo": ["أو", "و"], "ou": ["أو", "و"], "ai": ["أي", "عي"], "ay": ["أي", "عي"], "ei": ["إي", "أي"]},
    "medial": {"a": ["", "ا", "ع"], "aa": ["ا", "ع", "اع"], "e": ["", "ي", "ا"], "i": ["ي", ""],
               "o": ["و", ""], "u": ["و", ""], "ee": ["ي"], "ei": ["ي", "اي"], "ai": ["ي", "اي"],
               "ay": ["ي", "اي"], "oo": ["و"], "ou": ["و"]},
    "final": {"a": ["ا", "ة", "ى", "ه", "", "ع"], "aa": ["ا", "اء", "ع"], "e": ["ة", "ي", "ه", "ا", ""],
              "i": ["ي"], "o": ["و", "ه"], "u": ["و"], "ee": ["ي"], "ei": ["ي"], "ai": ["ي", "اي"],
              "ay": ["ي", "اي"], "oo": ["و"], "ou": ["و"]},
}
LONG_VOWELS = ["ي", "و", "ا"]  # written after a consonant the typist left them out after (kfk -> كيفك)
PAIRS = sorted({u for u in CONSONANTS if len(u) == 2} | {u for t in VOWELS.values() for u in t if len(u) == 2},
               key=len, reverse=True)
SMOOTH = 0.5  # added to every option's count


def units(word: str) -> list[str]:
    """A lowercase Arabizi word in units: two-letter units first (sh, kh, aa, ee…), else one character."""
    out, i = [], 0
    while i < len(word):
        pair = word[i:i + 2]
        if len(pair) == 2 and pair in PAIRS and (pair in CONSONANTS or pair[0] in "aeiou"):
            out.append(pair)
            i += 2
        else:
            out.append(word[i])
            i += 1
    return out


def position(k: int, n: int) -> str:
    return "initial" if k == 0 else "final" if k == n - 1 else "medial"


def options(unit: str, pos: str, previous: str, following: str | None) -> list[str]:
    """What `unit` may be written as at `pos`; a doubled consonant may be written once; a consonant followed by a
    consonant may get a long vowel the typist left out."""
    if unit[0] in "aeiou":
        return VOWELS[pos].get(unit, [""])
    letters = CONSONANTS.get(unit)
    if letters is None:
        return [] if unit.isalnum() else [""]
    out = letters + ([""] if unit == previous else [])
    if following is not None and following[0] not in "aeiou" and following in CONSONANTS:
        out += [letter + vowel for letter in letters for vowel in LONG_VOWELS]
    return out


def trace(typed: str, word: str) -> list[tuple[str, str, str]] | None:
    """The first path of options that writes `word` exactly from `typed`: (unit, position, letters) per unit."""
    parts = units(typed)
    path: list[tuple[str, str, str]] = []

    def walk(k: int, at: int, previous: str) -> bool:
        if k == len(parts):
            return at == len(word)
        pos, following = position(k, len(parts)), parts[k + 1] if k + 1 < len(parts) else None
        for letters in options(parts[k], pos, previous, following):
            if word.startswith(letters, at):
                path.append((parts[k], pos, letters))
                if walk(k + 1, at + len(letters), parts[k]):
                    return True
                path.pop()
        return False

    return path if walk(0, 0, "") else None


def word_pairs(rows: list[dict]) -> Counter:
    """(typed word, Arabic word) counts from rows typed word for word as their Arabic."""
    pairs: Counter = Counter()
    for row in rows:
        typed = [w.lower().strip(".,!?;:\"()") for w in row["arabizi"].split()]  # keeps 3' and 7' whole
        arabic = [P.normalize_arabic(w).strip(".,!?؟،؛:\"'()«»") for w in row["arabic"].split()]
        if len(typed) == len(arabic):
            for t, a in zip(typed, arabic, strict=True):
                if t and a and t.isascii() and P.ARABIC_LETTER.search(a):
                    pairs[(t.lower(), a)] += 1
    return pairs


def build_odds(rows: list[dict]) -> dict:
    """The letter odds and the training spellings of ambiguous typed words, from training rows."""
    counts: dict[str, Counter] = defaultdict(Counter)
    spellings: dict[str, Counter] = defaultdict(Counter)
    pairs = word_pairs(rows)
    traced = 0
    for (typed, arabic), n in sorted(pairs.items()):
        spellings[typed][arabic] += n
        path = trace(typed, arabic)
        if path:
            traced += n
            for unit, pos, letters in path:
                counts[f"{unit}|{pos}"][letters] += n
    return {
        "_comment": "Letter odds for word suggestions v2 (ADR 0036): for each Arabizi unit and position, how often "
                    "the public training pairs wrote each Arabic option. Generated by `pairs spelling-odds`.",
        "version": 1,
        "built_from": {"word_pairs": sum(pairs.values()), "traced": traced},
        "odds": {key: dict(sorted(c.items())) for key, c in sorted(counts.items())},
        "typed_spellings": {t: dict(c.most_common(5)) for t, c in sorted(spellings.items()) if len(c) > 1},
    }


# ----------------------------------------------------------------------------------------------- the sources

def edit_similarity(a: str, b: str) -> float:
    """1 - edit distance / the longer length (WordAlignment.similarity)."""
    if not a and not b:
        return 1.0
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i] + [0] * len(b)
        for j, y in enumerate(b, 1):
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x != y))
        previous = current
    return 1 - previous[len(b)] / max(len(a), len(b))


def is_arabic_word(word: str) -> bool:
    return bool(word) and all("ء" <= ch <= "ي" for ch in word)


# Suggestions.swift's one-edit variants: long vowels, emphatic swaps, endings, the first alif.
SWAPS = [("ت", "ط"), ("س", "ص"), ("د", "ض"), ("ز", "ظ"), ("ذ", "ز"), ("ذ", "د"), ("ث", "ت"), ("ث", "س"), ("ك", "ق")]
ENDINGS = [("ه", "ة"), ("ة", "ا"), ("ى", "ي"), ("ا", "ى")]
STARTS = ["ا", "أ", "إ"]
ARABIC_LETTERS = [chr(c) for c in range(0x0621, 0x064B) if c != 0x0640]


def variants(word: str) -> list[str]:
    out = []
    for i, ch in enumerate(word):
        if ch in "اوي" and i > 0:
            out.append(word[:i] + word[i + 1:])
    for i in range(1, len(word)):
        for vowel in "اوي":
            out.append(word[:i] + vowel + word[i:])
    for i, ch in enumerate(word):
        for a, b in SWAPS:
            if ch in (a, b):
                out.append(word[:i] + (b if ch == a else a) + word[i + 1:])
    if word:
        for a, b in ENDINGS:
            if word[-1] in (a, b):
                out.append(word[:-1] + (b if word[-1] == a else a))
        if word[0] in STARTS:
            out += [other + word[1:] for other in STARTS if other != word[0]]
    return out


def one_letter_changes(word: str) -> set[str]:
    if not is_arabic_word(word):
        return set()
    out = set()
    for i in range(len(word)):
        out.add(word[:i] + word[i + 1:])
        out.update(word[:i] + ch + word[i + 1:] for ch in ARABIC_LETTERS if ch != word[i])
    for i in range(len(word) + 1):
        out.update(word[:i] + ch + word[i:] for ch in ARABIC_LETTERS)
    out.discard(word)
    return out


def one_edit_apart(a: str, b: str) -> bool:
    if abs(len(a) - len(b)) > 1 or a == b:
        return False
    if len(a) == len(b):
        return sum(x != y for x, y in zip(a, b, strict=True)) == 1
    short, long = (a, b) if len(a) < len(b) else (b, a)
    return any(long[:i] + long[i + 1:] == short for i in range(len(long)))


FEATURES = [
    "model_lp", "in_model", "model_rank", "model_gap",
    "spell_lp", "in_spell", "spell_rank",
    "known", "log_freq", "in_known_spell",
    "in_first", "first_rank",
    "in_train", "train_rank", "train_count", "is_dict",
    "clitic_lp", "in_clitic",
    "in_variant", "variant_rank",
    "sim_shown", "sim_rules", "is_rules", "len_diff",
    "typing_lp", "typing_lp_per_letter", "typed_matches", "shape_lp",
    "n_sources",
]


class Candidates:
    """Builds the ↑ list's candidates and their signals for one word, and orders them."""

    def __init__(self, odds: dict | None = None, lexicon: dict | None = None, ranker: dict | None = None):
        odds = odds if odds is not None else json.loads(ODDS_PATH.read_text(encoding="utf-8"))
        lexicon = lexicon if lexicon is not None else b0.load_lexicon()
        self.rules = b0.RuleConverter(lexicon=lexicon)
        self.dictionary: dict[str, str] = lexicon["words"]
        self.arabic_words: dict[str, int] = lexicon.get("arabic_words", {})
        self.known = set(self.dictionary.values()) | set(self.arabic_words)
        self.odds = {key: Counter(v) for key, v in odds["odds"].items()}
        self.typed_spellings = {t: Counter(v) for t, v in odds["typed_spellings"].items()}
        self.ranker = ranker
        self.by_length: dict[int, list[tuple[str, str]]] = defaultdict(list)
        for key, value in self.dictionary.items():
            self.by_length[len(key)].append((key, value))
        self.trie: dict = {}
        for w in self.known:
            node = self.trie
            for ch in w:
                node = node.setdefault(ch, {})
            node["$"] = True
        tri: Counter = Counter()
        bi: Counter = Counter()
        for w, c in self.arabic_words.items():
            padded = "^^" + w + "$"
            for i in range(2, len(padded)):
                tri[padded[i - 2:i + 1]] += c
                bi[padded[i - 2:i]] += c
        self.tri, self.bi = tri, bi
        clitics = b0._clean(self.rules.rules["clitics"])
        # Longest first, then alphabetical (Swift reads the rules into an unordered dictionary).
        self.clitics = sorted(((k, v) for k, v in clitics.items() if " " not in v), key=lambda kv: (-len(kv[0]), kv[0]))
        self._typing_lp = lru_cache(maxsize=100_000)(self._typing_lp_uncached)

    # -- letter odds
    def probability(self, unit: str, pos: str, letters: str, previous: str, following: str | None) -> float:
        choices = options(unit, pos, previous, following)
        seen = self.odds.get(f"{unit}|{pos}", Counter())
        total = sum(seen[o] for o in choices) + SMOOTH * len(choices)
        return (seen[letters] + SMOOTH) / total if total else 1.0 / max(len(choices), 1)

    def spellings(self, typed: str, keep: int = 30, beam: int = 200) -> list[tuple[str, float]]:
        """Source 2: the most likely spellings of a typed word, known or not, best first, with log-scores; a known
        word gets a bonus of log 4 (first among equals, never alone)."""
        parts = units(typed.lower())
        if not parts:
            return []
        beams = [(0.0, "", "")]
        for k, unit in enumerate(parts):
            pos, following = position(k, len(parts)), parts[k + 1] if k + 1 < len(parts) else None
            grown = []
            for lp, written, previous in beams:
                for letters in options(unit, pos, previous, following):
                    p = self.probability(unit, pos, letters, previous, following)
                    grown.append((lp + math.log(p), written + letters, unit))
            beams = sorted(grown, key=lambda b: (-b[0], b[1]))[:beam]
        best: dict[str, float] = {}
        for lp, written, _ in beams:
            if is_arabic_word(written):
                score = lp + (math.log(4) if written in self.known else 0.0)
                best[written] = max(best.get(written, -1e9), score)
        return sorted(best.items(), key=lambda x: (-x[1], x[0]))[:keep]

    def known_spellings(self, typed: str, cap: int = 400) -> list[str]:
        """Source 3: every known word the options can write from `typed`, most often written first."""
        parts = units(typed.lower())
        found: set[str] = set()

        def walk(k: int, node: dict, written: str, previous: str) -> None:
            if len(found) >= cap:
                return
            if k == len(parts):
                if node.get("$") and written:
                    found.add(written)
                return
            pos, following = position(k, len(parts)), parts[k + 1] if k + 1 < len(parts) else None
            for letters in options(parts[k], pos, previous, following):
                n = node
                for ch in letters:
                    n = n.get(ch)
                    if n is None:
                        break
                if n is not None:
                    walk(k + 1, n, written + letters, parts[k])

        if parts:
            walk(0, self.trie, "", "")
        return sorted(found, key=lambda w: (-self.arabic_words.get(w, 0), w))

    def _typing_lp_uncached(self, typed: str, word: str) -> float:
        parts = units(typed.lower())
        n = len(parts)

        @cache
        def best(k: int, at: int, previous: str) -> float:
            if k == n:
                return 0.0 if at == len(word) else -1e9
            pos, following = position(k, n), parts[k + 1] if k + 1 < n else None
            top = -1e9
            for letters in options(parts[k], pos, previous, following):
                if word.startswith(letters, at):
                    rest = best(k + 1, at + len(letters), parts[k])
                    if rest > -1e9:
                        p = self.probability(parts[k], pos, letters, previous, following)
                        top = max(top, math.log(p) + rest)
            return top

        value = best(0, 0, "") if n else -1e9
        return value if value > -1e9 else -60.0

    def typing_lp(self, typed: str, word: str) -> float:
        """log P(word | typed) along the best path of options that writes `word` exactly; -60 when none does."""
        return self._typing_lp(typed.lower(), word)

    def shape_lp(self, word: str) -> float:
        """How Arabic-like a word looks: average log-probability per letter, character 3-grams of known words."""
        padded = "^^" + word + "$"
        total = sum(math.log((self.tri[padded[i - 2:i + 1]] + 1) / (self.bi[padded[i - 2:i]] + 40))
                    for i in range(2, len(padded)))
        return total / max(len(padded) - 2, 1)

    def clitic_spellings(self, typed: str, keep: int = 8) -> dict[str, float]:
        """Source 5: a small word typed joined to the next (wamen, bleyle)."""
        out: dict[str, float] = {}
        for latin, arabic in self.clitics:
            if typed.startswith(latin) and len(typed) - len(latin) >= 2:
                for w, lp in self.spellings(typed[len(latin):], keep=keep):
                    word = b0.join_clitic(arabic, w)
                    out[word] = max(out.get(word, -1e9), lp)
        return out

    def first_list(self, shown: str, typed: str) -> list[str]:
        """Source 7: today's list (Suggestions.candidates, ADR 0027), without its limit and the typed word."""
        out: list[str] = []

        def add(c: str) -> None:
            if c and c != shown and c not in out:
                out.append(c)

        if typed:  # as Suggestions.swift: no typed word, no rules' spelling and no dictionary neighbours
            ruled = b0.ARABIC_CORE.sub("", self.rules.convert(typed))
            if P.ARABIC_LETTER.search(ruled):
                add(ruled)
            near = []
            lengths = self.by_length[len(typed) - 1] + self.by_length[len(typed)] + self.by_length[len(typed) + 1]
            for key, value in lengths:
                if key != typed and one_edit_apart(key, typed):
                    close = edit_similarity(value, shown)
                    if close >= 0.5:
                        near.append((-close, value))
            for _, value in sorted(near):
                add(value)
        for v in variants(shown):
            if v in self.known:
                add(v)
        for o in sorted((o for o in one_letter_changes(shown) if o in self.known),
                        key=lambda o: (-self.arabic_words.get(o, 0), o)):
            add(o)
        return out

    # -- the pool and its signals
    def pool(self, shown: str, typed_words: list[str],
             guesses: list[tuple[str, float]] = ()) -> tuple[list[str], np.ndarray]:
        """Every candidate for the word `shown`, written by the model from the typed word(s), with its signals."""
        typed = "".join(w.lower() for w in typed_words)
        model = {w: (lp, i + 1) for i, (w, lp) in enumerate(guesses) if w != shown}
        spelled = {w: (lp, i + 1) for i, (w, lp) in enumerate(self.spellings(typed)) if w != shown}
        known_spelled = self.known_spellings(typed)
        first = {w: i + 1 for i, w in enumerate(self.first_list(shown, typed))}
        ruled = b0.ARABIC_CORE.sub("", self.rules.convert(" ".join(typed_words)))
        trained = self.typed_spellings.get(typed, Counter())
        if not trained and typed in self.dictionary:
            trained = Counter({self.dictionary[typed]: 1})
        train_list = {w: i + 1 for i, (w, _) in enumerate(trained.most_common(5))}
        clitic = self.clitic_spellings(typed)
        variant = {w: i + 1 for i, w in enumerate(variants(shown)[:40])}
        sources = [model, spelled, known_spelled, train_list, clitic, variant, first]
        cands: list[str] = []
        for source in sources:
            for w in source:
                if w != shown and is_arabic_word(w) and w not in cands:
                    cands.append(w)
        best_model = max((lp for lp, _ in model.values()), default=0.0)
        rows = []
        for w in cands:
            mlp, mrank = model.get(w, (-30.0, 11))
            slp, srank = spelled.get(w, (-60.0, 31))
            tlp = self.typing_lp(typed, w)
            rows.append([
                mlp, w in model, mrank, (mlp - best_model) if w in model else -30.0,
                slp, w in spelled, srank,
                w in self.known, math.log1p(self.arabic_words.get(w, 0)), w in known_spelled,
                w in first, first.get(w, 50),
                w in train_list, train_list.get(w, 6), math.log1p(trained.get(w, 0)), self.dictionary.get(typed) == w,
                clitic.get(w, -60.0), w in clitic,
                w in variant, variant.get(w, 41),
                edit_similarity(w, shown), edit_similarity(w, ruled), w == ruled, abs(len(w) - len(shown)),
                tlp, tlp / max(len(w), 1), tlp > -60.0, self.shape_lp(w),
                sum(w in s for s in sources),
            ])
        return cands, np.array(rows, dtype=float).reshape(len(cands), len(FEATURES))

    def order(self, cands: list[str], signals: np.ndarray) -> list[str]:
        """The candidates best first, by the ranker (or as built when there is none)."""
        if not cands or not self.ranker:
            return list(cands)
        return [cands[i] for i in np.argsort(-score(self.ranker, signals), kind="stable")]

    def suggestions(self, shown: str, typed_words: list[str], guesses: list[tuple[str, float]] = (),
                    limit: int = LIST_LENGTH) -> list[str]:
        """The ↑ list for one word: the best `limit - 1` Arabic candidates, then the typed word to keep it in Latin."""
        cands, signals = self.pool(shown, typed_words, guesses)
        out = self.order(cands, signals)[: limit - 1]
        latin = " ".join(typed_words)
        return out + ([latin] if latin else [])


# ----------------------------------------------------------------------------------------------- the ranker

def score(ranker: dict, signals: np.ndarray) -> np.ndarray:
    mean, scale, weights = (np.array(ranker[k], dtype=float) for k in ("mean", "scale", "weights"))
    return ((signals - mean) / scale) @ weights + float(ranker["bias"])


def train_ranker(examples: list[tuple[list[str], np.ndarray, str]], l2: float = 1.0, steps: int = 3000) -> dict:
    """Logistic regression (numpy, full-batch gradient descent): is this candidate the right word? Classes are
    balanced, signals standardized; deterministic."""
    X = np.vstack([s for c, s, _ in examples if len(c)])
    y = np.concatenate([[w == right for w in c] for c, _, right in examples if len(c)]).astype(float)
    mean, scale = X.mean(axis=0), X.std(axis=0)
    scale[scale == 0] = 1.0
    Z = (X - mean) / scale
    weight_of = np.where(y == 1, 0.5 / max(y.mean(), 1e-9), 0.5 / max(1 - y.mean(), 1e-9))
    w, b = np.zeros(Z.shape[1]), 0.0
    learning_rate = 0.5
    for _ in range(steps):
        p = 1 / (1 + np.exp(-(Z @ w + b)))
        g = (p - y) * weight_of
        w -= learning_rate * (Z.T @ g / len(y) + l2 * w / len(y))
        b -= learning_rate * g.mean()
    return {"_comment": "Word suggestions v2 ranker (ADR 0036): logistic regression on standardized signals. "
                        "Generated by `pairs train-ranker` from public rows only.",
            "version": 1, "features": FEATURES, "mean": mean.round(6).tolist(), "scale": scale.round(6).tolist(),
            "weights": w.round(6).tolist(), "bias": round(float(b), 6), "trained_on": len(examples)}


def load_ranker(path: Path = RANKER_PATH) -> dict | None:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


# ----------------------------------------------------------------------------------------------- evaluation helpers

def align(latin: list[str], shown: list[str], rules: b0.RuleConverter, max_run: int = 3) -> list[range | None]:
    """For each shown (Arabic) word, the range of typed words it came from, or None (WordAlignment.align)."""
    if len(latin) == len(shown):
        return [range(i, i + 1) for i in range(len(latin))]
    typed = [w.lower() for w in latin]
    n, m = len(latin), len(shown)
    ruled: list[list[str | None]] = [[None] * max_run for _ in range(n)]
    for i in range(n):
        for length in range(1, max_run + 1):
            if i + length <= n:
                out = b0.ARABIC_CORE.sub("", rules.convert(" ".join(typed[i:i + length])))
                ruled[i][length - 1] = out if length == 1 or " " not in out else None

    def fit(i: int, length: int, j: int) -> float:
        if length == 1 and shown[j] == typed[i]:
            return 1.0
        out = ruled[i][length - 1]
        return edit_similarity(out, shown[j]) if out is not None else 0.0

    best = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            value = max(best[i + 1][j], best[i][j + 1])
            for length in range(1, max_run + 1):
                if i + length <= n and (s := fit(i, length, j)) >= 0.4:
                    value = max(value, s + best[i + length][j + 1])
            best[i][j] = value
    result: list[range | None] = [None] * m
    i = j = 0
    while i < n and j < m:
        for length in range(max_run, 0, -1):
            if i + length <= n and (s := fit(i, length, j)) >= 0.4 \
                    and abs(best[i][j] - (s + best[i + length][j + 1])) < 1e-9:
                result[j] = range(i, i + length)
                i, j = i + length, j + 1
                break
        else:
            if abs(best[i][j] - best[i + 1][j]) < 1e-9:
                i += 1
            else:
                j += 1
    return result


def wrong_words(row: dict, rules: b0.RuleConverter):
    """Each wrong Arabic word of a scored row that can be traced to its typed word(s): (k, kind, typed words, the
    model's word at that spot, the answer the model continues from, the right word)."""
    import difflib

    def words(text: str) -> list[str]:
        return [w for w in (b0.ARABIC_CORE.sub("", P.normalize_arabic(x)) if P.ARABIC_LETTER.search(x)
                            else x.strip(".,!?;:\"'()").lower() for x in text.split()) if w]

    raw_typed, raw_pred = row["arabizi"].split(), row["prediction"].split()
    typed = [w.lower().strip(".,!?;:\"()") for w in raw_typed]
    ref, pred = words(row["reference"]), words(row["prediction"])
    if len(pred) != len(raw_pred):
        return
    sources = align(raw_typed, ref, rules)
    for op, r1, r2, p1, p2 in difflib.SequenceMatcher(a=ref, b=pred, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        kind = "one-for-one" if op == "replace" and r2 - r1 == p2 - p1 else "merged/split/dropped"
        for k in range(r1, r2):
            if not is_arabic_word(ref[k]) or sources[k] is None:
                continue
            if kind == "one-for-one":
                shown, before = pred[p1 + k - r1], raw_pred[: p1 + k - r1]
            else:
                shown, before = (pred[p1] if p1 < len(pred) else ""), raw_pred[:p1] + ref[r1:k]
            yield k, kind, [typed[x] for x in sources[k]], shown, " ".join(before), ref[k]



# ----------------------------------------------------------------------------------------------- Swift parity

FIXTURE = P.ROOT / "Packages" / "ArabiziCore" / "Tests" / "ArabiziCoreTests" / "Fixtures" / "candidates_parity.json"
GUESSES = P.ROOT / "eval" / "results" / "candidates" / "guesses-v3.jsonl"
# Edge cases: a missing vowel, an unknown word with a model guess, a prefix typed joined, a run of typed words,
# digits for letters, a doubled consonant, a word no option can write, and no typed word at all.
FIXTURE_CASES = [
    ("كفك", ["kfk"], []), ("فوتا", ["fota"], [("فوطة", -1.25), ("فوت", -2.5)]), ("ومن", ["wamen"], []),
    ("وانا", ["w", "ana"], []), ("الغرض", ["l8rad"], [("الغراض", -0.9)]), ("ساكر", ["sakkar"], []),
    ("شو", ["shu"], [("شوي", -3.0)]), ("خطر", ["5atar"], []), ("", ["xyz"], []), ("سلام", [], []),
]


def fixture_cases() -> list[tuple[str, list[str], list[tuple[str, float]]]]:
    rows = [json.loads(line) for line in GUESSES.read_text("utf-8").splitlines() if line.strip()]
    sample = rows[::max(len(rows) // 15, 1)][:15]
    return [(r["shown"], r["typed_words"], [tuple(g) for g in r["guesses"][:5]]) for r in sample] + FIXTURE_CASES


def write_fixture(path: Path = FIXTURE) -> dict:
    """Every candidate and signal for each case, the order with the committed ranker, and some spellings and typing
    likelihoods, for the Swift port (ArabiziCore CandidateList) to reproduce."""
    cands = Candidates(ranker=load_ranker())
    cases = []
    for shown, typed_words, guesses in fixture_cases():
        found, signals = cands.pool(shown, typed_words, guesses)
        cases.append({"shown": shown, "typed_words": typed_words, "guesses": [[w, lp] for w, lp in guesses],
                      "candidates": {w: [round(float(x), 6) for x in row]
                                     for w, row in zip(found, signals, strict=True)},
                      "order": cands.order(found, signals)})
    typed = ["kfk", "fota", "kifak", "3ade", "sha3'el", "aandak", "2alle", "sakkar"]
    fixture = {
        "_comment": "Written by arabizi_eval.candidates.write_fixture (`pairs train-ranker` rewrites it). The Swift "
                    "port must give the same candidates, signals (to 1e-6) and order.",
        "features": FEATURES,
        "cases": cases,
        "spellings": {t: [[w, round(lp, 6)] for w, lp in cands.spellings(t)] for t in typed},
        "typing": [[t, w, round(cands.typing_lp(t, w), 6)] for t, w in
                   [("kifak", "كيفك"), ("kifak", "كيفاك"), ("kifak", "كفيك"), ("kfk", "كيفك"), ("2alle", "قلي")]],
        "units": {t: units(t) for t in typed},
    }
    path.write_text(json.dumps(fixture, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    return fixture
