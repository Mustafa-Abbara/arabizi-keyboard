"""Rule-made spelling variants (roadmap P2 step 5, ADR 0012): realistic, meaning-preserving, reproducible."""

import dataclasses
import json
import random
from collections import Counter

import pytest

from arabizi_eval import pairs as P
from arabizi_eval import variants as V
from arabizi_eval.pairs_cli import main


def parent(**overrides) -> dict:
    row = {"id": "ai-0001", "arabizi": "kifak, shu 3am ta3mel?", "arabic": "كيفك، شو عم تعمل؟", "accepted": {},
           "method": "ai_checked", "writer": "claude+moustafa-edited", "checked_by": "moustafa",
           "source": "batch", "split": "train", "date": "2026-10-13"}
    row.update(overrides)
    return row


def always(*names: str) -> V.Rules:
    """Only the named word rules, each firing every time; no sentence rules."""
    rules = V.load_rules()
    chosen = tuple(dataclasses.replace(r, p=1.0) for r in rules.word_rules if r.name in names)
    assert len(chosen) == len(names)
    return V.Rules(rules.version, chosen, {})


def respell(word: str, *names: str) -> str:
    return V.respell_word(word, always(*names), random.Random(0), Counter())


def test_rules_file_is_valid():
    rules = V.load_rules()
    assert rules.word_rules and all(0 < r.p <= 1 and r.replace for r in rules.word_rules)
    assert set(rules.sentence_p) == {"lowercase", "drop_punctuation"}


@pytest.mark.parametrize(("word", "rule", "expected"), [
    ("shu", "sh_to_ch", "chu"),
    ("7abibi", "7_to_h", "habibi"),
    ("khalas", "kh_to_5", "5alas"),
    ("halla2", "2_final_dropped", None),  # "halla" or "halla'"
    ("kteer", "ee_to_i", "ktir"),
    ("ma7all", "double_consonant_single", "ma7al"),
    ("3am", "3am_to_3m", "3m"),
    ("el", "article_el", None),  # "il" or "l"
])
def test_each_rule_does_what_its_example_says(word, rule, expected):
    result = respell(word, rule)
    assert result != word
    if expected:
        assert result == expected


def test_7_never_forms_sh_ch_kh_gh():
    # s7i7 -> shi7 would read ح as ش; the final 7 may still become h (s7ih), which keeps the meaning.
    for word in ("s7i7", "k7al", "c7", "g7", "d7", "t7"):
        assert not any(pair in respell(word, "7_to_h") for pair in ("sh", "kh", "ch", "gh", "dh", "th"))


@pytest.mark.parametrize(("word", "rule"), [
    ("min", "i_to_ee"),  # "from" would become "who" (meen)
    ("meen", "ee_to_i"),  # "who" would become "from"
    ("la2", "2_final_dropped"),  # لأ would become la
    ("3am", "3_initial_before_vowel_dropped"),  # عم would become "am"
])
def test_meaning_guards(word, rule):
    assert respell(word, rule) == word


def test_latin_words_numbers_links_and_emoji_are_never_touched():
    row = parent(arabizi="Shoufak bel LAU meeting 3al 7:30, 100$ www.lau.edu 😂",
                 arabic="شوفك بال LAU meeting عال 7:30، 100$ www.lau.edu 😂")
    rules = V.load_rules()
    forced = V.Rules(rules.version, tuple(dataclasses.replace(r, p=1.0) for r in rules.word_rules),
                     {"lowercase": 1.0, "drop_punctuation": 0.0})
    for seed in range(20):
        arabizi, _ = V.make_variant(row, forced, random.Random(seed), Counter())
        for kept in ("LAU", "meeting", "7:30", "100$", "www.lau.edu", "😂"):
            assert kept in arabizi


def test_drop_punctuation_keeps_numbers_and_links():
    arabizi, arabic = V.drop_punctuation("ya3te 89,500 lira, shuf www.x.com/?a=1 ok?",
                                         "يعطي 89,500 ليرة، شوف www.x.com/?a=1 ok؟")
    assert arabizi == "ya3te 89,500 lira shuf www.x.com/?a=1 ok"
    assert arabic == "يعطي 89,500 ليرة شوف www.x.com/?a=1 ok"


def test_generate_is_valid_reproducible_and_new():
    parents = [parent(id=f"ai-{n:04d}", arabizi=f"shu 3am ta3mel ya 7abibi, bel beit {n}?",
                      arabic=f"شو عم تعمل يا حبيبي، بالبيت {n}؟") for n in range(1, 30)]
    rows, used, _ = V.generate(parents, per_row=2, seed=7)
    again, _, _ = V.generate(parents, per_row=2, seed=7)
    other, _, _ = V.generate(parents, per_row=2, seed=8)
    assert rows == again and rows != other
    assert used
    by_id = {p["id"]: p for p in parents}
    for row in rows:
        assert P.row_errors(row, "train", "rule_variant") == []
        assert P.normalize_arabizi(row["arabizi"]) != P.normalize_arabizi(by_id[row["parent"]]["arabizi"]) \
            or row["arabic"] != by_id[row["parent"]]["arabic"]
    assert len({r["id"] for r in rows}) == len(rows)


def test_cli_writes_a_valid_variants_file(monkeypatch, tmp_path):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    rows = [parent(id=f"ai-{n:04d}", arabizi=f"shu 3am ta3mel ya 7abibi {n}", arabic=f"شو عم تعمل يا حبيبي {n}")
            for n in range(1, 6)]
    (tmp_path / "train-ai_checked.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    assert main(["variants", "--per-row", "2", "--show", "0"]) == 0
    written = (tmp_path / "train-rule_variant.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(written) == 10
    assert P.validate(tmp_path).ok
