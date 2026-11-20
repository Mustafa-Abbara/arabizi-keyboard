"""Word suggestions v2 (ADR 0036): spelling options, letter odds, the sources, the signals and the ranker."""

import json

import numpy as np
import pytest

from arabizi_eval import candidates as C
from arabizi_eval import pairs_cli


@pytest.fixture(scope="module")
def cands():
    return C.Candidates(ranker=None)


def test_units_take_two_letter_units_first():
    assert C.units("sha3'el") == ["sh", "a", "3'", "e", "l"]
    assert C.units("kifak") == ["k", "i", "f", "a", "k"]
    assert C.units("aandak") == ["aa", "n", "d", "a", "k"]


def test_options_cover_short_vowels_emphatics_and_missing_vowels():
    assert "" in C.options("a", "medial", "f", "k")  # kifak: the a is not written
    assert {"ت", "ط"} <= set(C.options("t", "medial", "", "a"))
    assert "كي" in C.options("k", "initial", "", "f")  # kfk: a long vowel the typist left out
    assert "كي" not in C.options("k", "initial", "", "i")  # not before a typed vowel
    assert "" in C.options("s", "medial", "s", "a")  # a doubled consonant written once


def test_trace_finds_the_path_that_spells_the_word():
    path = C.trace("kifak", "كيفك")
    assert [letters for _, _, letters in path] == ["ك", "ي", "ف", "", "ك"]
    assert C.trace("kifak", "قلم") is None


def test_build_odds_counts_paths_and_keeps_ambiguous_typed_words():
    rows = [{"arabizi": "kifak", "arabic": "كيفك"}, {"arabizi": "kifak", "arabic": "كيفك"},
            {"arabizi": "sa7", "arabic": "صح"}, {"arabizi": "sa7", "arabic": "سح"}]
    odds = C.build_odds(rows)
    assert odds["odds"]["a|medial"] == {"": 4}
    assert odds["typed_spellings"] == {"sa7": {"سح": 1, "صح": 1}}
    assert odds == C.build_odds(rows)  # deterministic


def test_spellings_rank_unknown_words_and_insert_missing_vowels(cands):
    assert "كيفك" in [w for w, _ in cands.spellings("kfk")]
    found = dict(cands.spellings("fota"))
    assert "فوطة" in dict(cands.spellings("fota", keep=200)) or "فوطة" in found
    assert all(C.is_arabic_word(w) for w in found)


def test_typing_likelihood(cands):
    assert cands.typing_lp("kifak", "كيفك") > cands.typing_lp("kifak", "كيفاك") > -60  # a middle a: usually unwritten
    assert cands.typing_lp("kifak", "كفيك") == -60.0  # letters out of order: no path writes it
    assert cands.typing_lp("kifak", "قلم") == -60.0


def test_clitic_spellings_put_the_prefix_back(cands):
    assert any(w.startswith("و") for w in cands.clitic_spellings("wamen"))
    assert cands.clitic_spellings("w") == {}


def test_known_spellings_are_known_words(cands):
    found = cands.known_spellings("3ade")
    assert "عادي" in found and all(w in cands.known for w in found)


def test_pool_has_one_signal_row_per_candidate_and_never_offers_the_shown_word(cands):
    found, signals = cands.pool("سوانة", ["sawene"], [("ثواني", -1.0), ("سوانة", -0.2)])
    assert found and "سوانة" not in found and found[0] == "ثواني"
    assert signals.shape == (len(found), len(C.FEATURES))
    assert np.isfinite(signals).all()


def test_suggestions_end_with_the_typed_word(cands):
    out = cands.suggestions("سوانة", ["sawene"], limit=7)
    assert len(out) <= 7 and out[-1] == "sawene"


def test_train_ranker_learns_to_put_the_right_word_first():
    rng = np.random.default_rng(1)
    examples = []
    for _ in range(40):
        signals = rng.normal(size=(5, len(C.FEATURES)))
        signals[2, 0] += 3  # the right word has a higher model score
        examples.append((["a", "b", "c", "d", "e"], signals, "c"))
    ranker = C.train_ranker(examples)
    assert ranker == C.train_ranker(examples)  # deterministic
    c = C.Candidates(ranker=ranker)
    assert c.order(["a", "b", "c", "d", "e"], examples[0][1])[0] == "c"


def test_align_traces_a_run_of_typed_words(cands):
    assert C.align(["w", "ana"], ["وأنا"], cands.rules) == [range(0, 2)]
    assert C.align(["shu", "3am"], ["شو", "عم"], cands.rules) == [range(0, 1), range(1, 2)]


def test_a_word_from_two_typed_words_can_be_split(cands):
    # The model joined و to the next word: the split puts the space back in its own letters.
    assert cands.span_entry(["وانا", "رايح"], 0, lambda j: [["w", "ana"], ["rayi7"]][j]) == ("و انا", 0)
    assert not C.Candidates.wants_split("كيفك", ["kifak"])  # one typed word: never split


def test_two_words_can_be_merged_with_either_one_selected(cands):
    typed = [["3a"], ["sate7"]]
    assert cands.span_entry(["ع", "سطح"], 0, lambda j: typed[j]) == ("عالسطح", 1)
    assert cands.span_entry(["ع", "سطح"], 1, lambda j: typed[j]) == ("عالسطح", -1)
    assert cands.merge_options("رح", "شوف", ["7a", "shof"]) == ["حشوف"]  # the future particle is joined as ح


def test_words_always_written_apart_are_never_merged(cands):
    assert cands.span_entry(["شو", "عم", "تعمل"], 1, lambda j: [["shu"], ["3am"], ["ta3mel"]][j]) is None
    assert not C.Candidates.wants_merge("ال", "balcony", ["el"], ["balcony"])  # a Latin word stays apart


def test_the_swift_fixture_has_the_merge_and_split_cases():
    fixture = json.loads(C.FIXTURE.read_text(encoding="utf-8"))
    assert len(fixture["spans"]) == len(C.SPAN_CASES)
    assert fixture["spans"][0]["entry"] == ["و انا", 0]


def test_committed_letter_odds_are_up_to_date():
    train = [r for r in pairs_cli.all_rows(include_private=False) if r.get("split") == "train"]
    committed = json.loads(C.ODDS_PATH.read_text(encoding="utf-8"))
    assert committed == json.loads(json.dumps(C.build_odds(train), ensure_ascii=False)), \
        "run `pairs spelling-odds` and commit data/rules/spelling_odds.json"


def test_committed_ranker_is_up_to_date():
    fresh = C.train_ranker(pairs_cli.ranker_examples(C.Candidates(ranker=None)))
    committed = C.load_ranker()
    assert committed is not None
    for key in ("features", "mean", "scale", "weights", "bias"):
        assert committed[key] == pytest.approx(fresh[key], abs=1e-5), "run `pairs train-ranker` and commit it"


def test_swift_parity_fixture_is_up_to_date(tmp_path):
    fresh = C.write_fixture(tmp_path / "candidates_parity.json")
    committed = json.loads(C.FIXTURE.read_text(encoding="utf-8"))
    assert committed == json.loads(json.dumps(fresh, ensure_ascii=False)), "run `pairs train-ranker` and commit it"
