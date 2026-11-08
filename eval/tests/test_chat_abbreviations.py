"""data/rules/chat_abbreviations.json (ADR 0035): no abbreviation the training data mostly converts to Arabic
(Arabizi that looks like an abbreviation: ya = يا, min = مين, fyi = فيي), no single letter, no duplicates."""

import json
import re
from collections import Counter

from arabizi_eval import pairs as P

PATH = P.ROOT / "data" / "rules" / "chat_abbreviations.json"


def bare(token: str) -> str:
    return re.sub(r"^\W+|\W+$", "", token.lower())


def test_the_list_is_lower_case_unique_and_has_no_single_letter():
    words = json.loads(PATH.read_text("utf-8"))["words"]
    assert words == [w.lower() for w in words]
    assert len(words) == len(set(words))
    assert all(len(w) > 1 for w in words)


def test_no_abbreviation_is_mostly_converted_to_arabic_in_the_training_data():
    words = set(json.loads(PATH.read_text("utf-8"))["words"])
    converted, kept = Counter(), Counter()
    for pair_file in P.pair_files():
        for _, row, err in P.read_jsonl(pair_file):
            if err or not row or row.get("split") != "train":
                continue
            latin_out = {bare(t) for t in row["arabic"].split()}
            for token in {bare(t) for t in row["arabizi"].split()} & words:
                (kept if token in latin_out else converted)[token] += 1
    mostly_arabic = sorted(w for w in words if converted[w] > kept[w])
    assert not mostly_arabic, f"converted to Arabic more often than kept: {mostly_arabic}"
