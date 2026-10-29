"""data/rules/english_stopwords.json (ADR 0031): no word the training data mostly converts to Arabic (Arabizi that
looks like English: she = شي, be = بي, am = عم)."""

import json
import re
from collections import Counter

from arabizi_eval import pairs as P


def bare(token: str) -> str:
    return re.sub(r"^\W+|\W+$", "", token.lower().replace("'", ""))


def test_no_stopword_is_mostly_converted_to_arabic_in_the_training_data():
    path = P.ROOT / "data" / "rules" / "english_stopwords.json"
    words = {bare(w) for w in json.loads(path.read_text("utf-8"))["words"]}
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
