"""Metrics on hand-computed toy examples (roadmap P3 gate)."""

import pytest

from arabizi_eval import metrics as M


def row(arabic: str, arabizi: str = "x", accepted: dict | None = None, id_: str = "hw-0001") -> dict:
    return {"id": id_, "arabizi": arabizi, "arabic": arabic, "accepted": accepted or {}}


def test_word_accuracy_three_of_four():
    s = M.score_sentence(row("شو عم تعمل هلق", "shu 3am ta3mel halla2"), "شو عم بتعمل هلق")
    assert (s.words_correct, s.words_total) == (3, 4)
    assert M.aggregate([s])["word_accuracy"] == 0.75


def test_perfect_output_scores_one_and_cer_zero():
    s = M.score_sentence(row("كيفك، شو عم تعمل؟", "kifak, shu 3am ta3mel?"), "كيفك، شو عم تعمل؟")
    summary = M.aggregate([s])
    assert summary["word_accuracy"] == 1.0 and summary["cer"] == 0.0 and summary["exact_match"] == 1.0


def test_extra_invented_words_lower_accuracy():
    s = M.score_sentence(row("شو عم تعمل", "shu 3am ta3mel"), "شو عم تعمل يا حبيبي هلق")
    assert (s.words_correct, s.words_total) == (3, 6)


def test_diacritics_tatweel_and_punctuation_are_ignored_for_words_but_punctuation_is_scored():
    s = M.score_sentence(row("كيفك، شو؟", "kifak, shu?"), "كَيفـك شو")
    assert s.words_correct == 2 and s.exact
    assert not s.punctuation_match  # ، and ؟ are missing


def test_punctuation_match_needs_the_arabic_marks_in_order():
    reference = row("كيفك، شو؟ 89,500", "kifak, shu? 89,500")
    assert M.score_sentence(reference, "كيفك، شو؟ 89,500").punctuation_match
    assert not M.score_sentence(reference, "كيفك, شو? 89,500").punctuation_match  # Latin marks left
    assert not M.score_sentence(reference, "كيفك؟ شو، 89,500").punctuation_match  # wrong order


def test_global_and_row_variants_are_accepted():
    s = M.score_sentence(row("هلق أنا بالبيت", "halla2 ana bel beit"), "هلأ أنا بالبيت")
    assert s.words_correct == 3  # هلق=هلأ is in data/rules/accepted_variants.json
    s = M.score_sentence(row("بيتا كبير", "beta kbir", {"بيتا": ["بيتها"]}), "بيتها كبير")
    assert s.words_correct == 2


def test_variants_work_in_both_directions():
    # The reference may use the accepted spelling (إذا) while the model uses the primary one (إزا).
    s = M.score_sentence(row("إذا بدك", "iza badak"), "إزا بدك")
    assert s.words_correct == 2


def test_multi_word_variant_expands_the_reference():
    s = M.score_sentence(row("عنجد حلو", "3anjad 7elo"), "عن جد حلو")
    assert (s.words_correct, s.words_total) == (3, 3)


def test_lenient_merges_alif_and_ta_marbuta_but_strict_does_not():
    s = M.score_sentence(row("أنا حلوة", "ana 7elwe"), "انا حلوه")
    assert s.words_correct == 0 and s.words_correct_lenient == 2


def test_cer_counts_character_edits():
    s = M.score_sentence(row("شو", "shu"), "شي")
    assert (s.char_edits, s.ref_chars) == (1, 2)
    assert M.aggregate([s])["cer"] == 0.5


def test_keep_latin_precision_recall():
    good = M.score_sentence(row("ما عندي meeting", "ma 3ndi meeting"), "ما عندي meeting")
    converted = M.score_sentence(row("ما عندي meeting", "ma 3ndi meeting"), "ما عندي ميتنغ")
    leaked = M.score_sentence(row("ما عندي شي", "ma 3ndi shi"), "ما عندي shi")
    summary = M.aggregate([good, converted, leaked])
    assert summary["keep_latin_precision"] == 0.5  # 1 right of 2 Latin words output
    assert summary["keep_latin_recall"] == 0.5  # 1 kept of 2 that should stay
    assert summary["keep_latin_f1"] == 0.5


def test_number_preservation():
    kept = M.score_sentence(row("بعت 100$ عال 2pm", "b3at 100$ 3al 2pm"), "بعت 100$ عال 2pm")
    lost = M.score_sentence(row("بعت 100$", "b3at 100$"), "بعت مية")
    summary = M.aggregate([kept, lost])
    assert summary["number_preservation"] == pytest.approx(2 / 3)


def test_msa_rewrite_only_counts_words_not_in_the_reference():
    msa = M.score_sentence(row("شو بدك هلق", "shu badak halla2"), "ماذا تريد الآن")
    ok = M.score_sentence(row("بس لكن", "bas laken"), "بس لكن")  # لكن is in the reference
    assert msa.msa_words == ["ماذا", "تريد", "الآن"] and ok.msa_words == []
    assert M.aggregate([msa, ok])["msa_rewrite_rate"] == 0.5


def test_hallucination_length_and_invented_latin():
    too_long = M.score_sentence(row("شو", "shu"), "شو عم تعمل يا حبيبي")
    invented = M.score_sentence(row("ما عندي شي", "ma 3ndi shi"), "ما عندي problem")
    fine = M.score_sentence(row("ما عندي meeting", "ma 3ndi meeting"), "ما عندي meeting")
    assert too_long.hallucination and invented.hallucination and fine.hallucination is None
    assert "problem" in invented.hallucination


def test_empty_output_is_scored_not_crashing():
    s = M.score_sentence(row("شو عم تعمل", "shu 3am ta3mel"), "")
    assert s.words_correct == 0 and s.hallucination


def test_latency_percentiles():
    scores = [M.score_sentence(row("شو", "shu", id_=f"hw-{i:04d}"), "شو", latency_ms=float(i)) for i in range(1, 21)]
    summary = M.aggregate(scores)
    assert summary["latency_ms_p50"] == 10.5 and summary["latency_ms_p95"] == 19.0
