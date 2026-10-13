"""Scoring a system's Arabic output against the references (roadmap P3, definitions in docs/EVAL.md)."""

from __future__ import annotations

import json
import re
from collections import Counter
from dataclasses import asdict, dataclass, field
from functools import cache
from statistics import median

from arabizi_eval import pairs as P

RULES_DIR = P.ROOT / "data" / "rules"
PUNCTUATION = "?,;.!:\"'()[]{}…؟،؛«»-–—"
LATIN_WORD = re.compile(r"[A-Za-z]")
# Sentence punctuation the spelling guide converts (SPELLING.md 7); compared in order, outside numbers and links.
SCORED_PUNCTUATION = re.compile(r"[?,;!.؟،؛]")
MAX_REFERENCES = 16  # cap on references expanded from multi-word variants


@cache
def global_variants() -> dict[str, list[str]]:
    return json.loads((RULES_DIR / "accepted_variants.json").read_text(encoding="utf-8"))["variants"]


@cache
def msa_words() -> frozenset[str]:
    words = json.loads((RULES_DIR / "msa_words.json").read_text(encoding="utf-8"))["words"]
    return frozenset(P.normalize_arabic(w, lenient=True) for w in words)


def tokens(text: str) -> list[str]:
    """Whitespace words without surrounding punctuation; punctuation-only tokens are dropped."""
    return [t for t in (w.strip(PUNCTUATION) for w in text.split()) if t]


def norm(token: str, lenient: bool) -> str:
    token = P.normalize_arabic(token, lenient=lenient)
    return token.lower() if lenient else token


def _variants(accepted: dict[str, list[str]]) -> dict[str, set[str]]:
    merged: dict[str, set[str]] = {}
    for source in (global_variants(), accepted):
        for primary, others in source.items():
            merged.setdefault(primary, set()).update(others)
    return merged


def reference_texts(arabic: str, accepted: dict[str, list[str]]) -> list[str]:
    """The primary reference plus one text per multi-word variant (عنجد / عن جد)."""
    texts = [arabic]
    for primary, others in _variants(accepted).items():
        multi = [o for o in others if len(o.split()) != len(primary.split())]
        if not multi:
            continue
        pattern = re.compile(rf"(?<!\S){re.escape(primary)}(?=[\s{re.escape(PUNCTUATION)}]|$)")
        texts += [pattern.sub(o, t) for t in texts for o in multi if pattern.search(t)]
        texts = list(dict.fromkeys(texts))[:MAX_REFERENCES]
    return texts


def references(arabic: str, accepted: dict[str, list[str]], lenient: bool) -> list[list[frozenset[str]]]:
    """Every acceptable reference as a list of word positions, each a set of accepted spellings."""
    variants = _variants(accepted)
    single = {norm(p, lenient): {norm(o, lenient) for o in others if len(o.split()) == len(p.split()) == 1}
              for p, others in variants.items()}
    out = []
    for text in reference_texts(arabic, accepted):
        positions = []
        for word in tokens(text):
            key = norm(word, lenient)
            positions.append(frozenset({key} | single.get(key, set())))
        out.append(positions)
    return out


def lcs(hypothesis: list[str], reference: list[frozenset[str]]) -> int:
    """Longest common subsequence where a hypothesis word matches any accepted spelling at a position."""
    previous = [0] * (len(reference) + 1)
    for word in hypothesis:
        current = [0]
        for j, allowed in enumerate(reference, 1):
            current.append(previous[j - 1] + 1 if word in allowed else max(previous[j], current[j - 1]))
        previous = current
    return previous[-1]


def edit_distance(a: str, b: str) -> int:
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


@dataclass
class SentenceScore:
    id: str
    words_correct: int  # strict
    words_total: int  # max(len(reference), len(output)) for the best reference
    words_correct_lenient: int
    words_total_lenient: int
    exact: bool  # every word right (punctuation not included)
    punctuation_match: bool  # the same punctuation marks, in order, as the reference
    char_edits: int
    ref_chars: int
    latin_tp: int
    latin_output: int
    latin_reference: int
    numbers_total: int
    numbers_kept: int
    msa_words: list[str] = field(default_factory=list)
    hallucination: str | None = None  # reason, or None
    latency_ms: float | None = None


def _word_score(output: list[str], refs: list[list[frozenset[str]]]) -> tuple[int, int]:
    """(correct, total) for the reference that gives the best accuracy."""
    best = (0, max(len(output), 1))
    for ref in refs:
        total = max(len(ref), len(output), 1)
        correct = lcs(output, ref)
        if correct / total > best[0] / best[1]:
            best = (correct, total)
    return best


def score_sentence(row: dict, output: str, latency_ms: float | None = None) -> SentenceScore:
    out_tokens = tokens(output)
    strict_refs = references(row["arabic"], row.get("accepted", {}), lenient=False)
    lenient_refs = references(row["arabic"], row.get("accepted", {}), lenient=True)
    strict = _word_score([norm(t, False) for t in out_tokens], strict_refs)
    lenient = _word_score([norm(t, True) for t in out_tokens], lenient_refs)

    out_words = [norm(t, False) for t in out_tokens]
    out_text = " ".join(out_words)
    ref_texts = [" ".join(norm(t, False) for t in tokens(text))
                 for text in reference_texts(row["arabic"], row.get("accepted", {}))]
    edits, ref_chars = min(((edit_distance(out_text, r), len(r)) for r in ref_texts),
                           key=lambda pair: pair[0] / max(pair[1], 1))
    exact = any(len(ref) == len(out_words) == lcs(out_words, ref) for ref in strict_refs)

    latin_out = Counter(t.lower() for t in out_tokens if LATIN_WORD.search(t))
    latin_ref = Counter(t.lower() for t in tokens(row["arabic"]) if LATIN_WORD.search(t))
    numbers = Counter(P.NUMBER.findall(row["arabizi"]))
    kept = numbers & Counter(P.NUMBER.findall(output))

    ref_lenient = {norm(t, True) for t in tokens(row["arabic"])}
    msa = [t for t in out_tokens if norm(t, True) in msa_words() and norm(t, True) not in ref_lenient]

    input_words = len(tokens(row["arabizi"]))
    input_latin = {t.lower() for t in tokens(row["arabizi"])}
    invented_latin = [t for t in latin_out if t not in input_latin]
    hallucination = None
    if input_words and not 0.5 <= len(out_tokens) / input_words <= 2:
        hallucination = f"length {len(out_tokens)} words for {input_words} input words"
    elif invented_latin:
        hallucination = "Latin words not in the input: " + ", ".join(sorted(invented_latin))

    return SentenceScore(
        id=row["id"], words_correct=strict[0], words_total=strict[1],
        words_correct_lenient=lenient[0], words_total_lenient=lenient[1], exact=exact,
        punctuation_match=punctuation_marks(output) == punctuation_marks(row["arabic"]),
        char_edits=edits, ref_chars=ref_chars,
        latin_tp=sum((latin_out & latin_ref).values()), latin_output=sum(latin_out.values()),
        latin_reference=sum(latin_ref.values()),
        numbers_total=sum(numbers.values()), numbers_kept=sum(kept.values()),
        msa_words=msa, hallucination=hallucination, latency_ms=latency_ms,
    )


def punctuation_marks(text: str) -> list[str]:
    hidden = P.NUMBER.sub(" ", P.UNTOUCHED.sub(" ", text))
    return SCORED_PUNCTUATION.findall(hidden)


def _ratio(numerator: float, denominator: float) -> float | None:
    return numerator / denominator if denominator else None


def _percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(q * (len(ordered) - 1))))
    return ordered[index]


def aggregate(scores: list[SentenceScore]) -> dict:
    """Corpus-level metrics (micro-averaged over words, characters, numbers and Latin words)."""
    n = len(scores)
    total = lambda attr: sum(getattr(s, attr) for s in scores)  # noqa: E731
    precision = _ratio(total("latin_tp"), total("latin_output"))
    recall = _ratio(total("latin_tp"), total("latin_reference"))
    f1 = (2 * precision * recall / (precision + recall)) if precision and recall else (
        None if precision is None and recall is None else 0.0)
    latencies = [s.latency_ms for s in scores if s.latency_ms is not None]
    return {
        "sentences": n,
        "word_accuracy": _ratio(total("words_correct"), total("words_total")),
        "word_accuracy_lenient": _ratio(total("words_correct_lenient"), total("words_total_lenient")),
        "exact_match": _ratio(sum(s.exact for s in scores), n),
        "punctuation_match": _ratio(sum(s.punctuation_match for s in scores), n),
        "cer": _ratio(total("char_edits"), total("ref_chars")),
        "keep_latin_precision": precision,
        "keep_latin_recall": recall,
        "keep_latin_f1": f1,
        "number_preservation": _ratio(total("numbers_kept"), total("numbers_total")),
        "msa_rewrite_rate": _ratio(sum(bool(s.msa_words) for s in scores), n),
        "hallucination_rate": _ratio(sum(s.hallucination is not None for s in scores), n),
        "latency_ms_p50": median(latencies) if latencies else None,
        "latency_ms_p95": _percentile(latencies, 0.95) if latencies else None,
    }


def to_dict(score: SentenceScore) -> dict:
    return asdict(score)
