"""Error analysis: word alignment, suggested types, and the spreadsheet written by `evalrun errors`."""

import json

import openpyxl
import pytest

from arabizi_eval import errors as E
from arabizi_eval import pairs as P
from arabizi_eval import run as R


def row(arabic, arabizi="x", accepted=None):
    return {"id": "hw-0001", "arabizi": arabizi, "arabic": arabic, "accepted": accepted or {}}


def found(arabic, prediction, accepted=None):
    return [(e.reference, e.output, e.type) for e in E.sentence_errors(row(arabic, accepted=accepted), prediction)]


def test_correct_sentence_has_no_errors():
    assert found("شو عم تعمل هلق", "شو عم تعمل هلق") == []


def test_substitution_dropped_and_added_words():
    assert found("شو عم تعمل هلق", "شو عم بتعمل هلق") == [("تعمل", "بتعمل", "one letter off")]
    assert found("شو عم تعمل هلق", "شو تعمل هلق") == [("عم", "", "dropped word")]
    assert found("شو عم تعمل", "شو عم تعمل يا") == [("", "يا", "added word")]


def test_error_count_matches_word_accuracy():
    # word accuracy 3/4 for this example (docs/EVAL.md): one wrong word
    assert len(E.sentence_errors(row("شو عم تعمل هلق"), "شو عم بتعمل هلق")) == 1


def test_latin_types():
    assert found("ما عندي meeting", "ما عندي ميتينغ") == [("meeting", "ميتينغ", "English converted")]
    assert found("ما عندي وقت", "ما عندي wa2et") == [("وقت", "wa2et", "left in Latin")]


def test_spelling_convention_msa_and_different_word():
    assert found("أنا بالبيت", "انا بالبيت") == [("أنا", "انا", "spelling convention")]
    assert found("هلق جاي", "الآن جاي") == [("هلق", "الآن", "MSA word")]
    assert found("أين انت", "اين انت") == [("أين", "اين", "spelling convention")]  # MSA list word, spelling only
    assert found("القلم هون", "القلامة هون") == [("القلم", "القلامة", "different word")]


def test_joined_and_split_words():
    assert found("بعت لمحمد", "بعت ل محمد") == [("لمحمد", "ل محمد", "joined/split")]
    assert found("عم بحكي مع عن جد", "عم بحكي مع عنجد") == [("عن جد", "عنجد", "joined/split")]


def test_accepted_variant_is_not_an_error():
    assert found("عنجد حلو", "عن جد حلو", accepted={"عنجد": ["عن جد"]}) == []


@pytest.fixture
def scored_run(monkeypatch, tmp_path):
    pairs_dir = tmp_path / "pairs"
    pairs_dir.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", pairs_dir)
    rows = [("hw-0001", "kifak", "كيفك", "dev"), ("hw-0002", "ma 3ndi meeting", "ما عندي meeting", "dev"),
            ("hw-0003", "halla2 ana bel beit", "هلق أنا بالبيت", "test")]
    for split in ("dev", "test"):
        lines = [{"id": i, "arabizi": z, "arabic": a, "accepted": {}, "method": "hand", "writer": "moustafa",
                  "checked_by": None, "source": "hand-written", "split": s, "date": "2026-10-13"}
                 for i, z, a, s in rows if s == split]
        (pairs_dir / f"{split}.jsonl").write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in lines), encoding="utf-8")
    predictions = tmp_path / "predictions.jsonl"
    predictions.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in (
        {"id": "hw-0001", "prediction": "كيفك"}, {"id": "hw-0002", "prediction": "ما عندي ميتينغ"},
        {"id": "hw-0003", "prediction": "هلق انا بالبيت"})), encoding="utf-8")
    results = tmp_path / "results"
    for split, extra in (("dev", []), ("test", ["--final"])):
        assert R.main(["score", str(predictions), "--name", "sys", "--split", split, "--results", str(results),
                       *extra]) == 0
    return {split: next(results.glob(f"*-sys-{split}")) for split in ("dev", "test")}


def test_errors_sheet_lists_wrong_words_and_counts_types(scored_run, capsys):
    assert R.main(["errors", str(scored_run["dev"])]) == 0
    out = capsys.readouterr().out
    assert "1 error rows in 1 of 2 sentences" in out
    assert "Warning" not in out
    book = openpyxl.load_workbook(scored_run["dev"] / "errors.xlsx")
    assert book.sheetnames == ["summary", "words", "sentences"]
    words = list(book["words"].iter_rows(values_only=True))
    assert words[1][:4] == ("hw-0002", "meeting", "ميتينغ", "English converted")
    assert [r[0] for r in book["sentences"].iter_rows(min_row=2, values_only=True)] == ["hw-0002"]
    counts = {r[0].value: r[1].value for r in book["summary"].iter_rows() if r[0].value in E.TYPES}
    assert list(counts) == list(E.TYPES)
    for name, formula in counts.items():  # each count looks up its own row's type
        cell = formula.removeprefix("=COUNTIF(words!D:D,").removesuffix(")")
        assert book["summary"][cell].value == name


def test_rows_and_word_accuracy_errors_are_both_reported(tmp_path):
    # one dropped and one added word in the same gap: two rows, one wrong word in the score (1/2)
    record = {"id": "hw-0001", "arabizi": "x", "reference": "شو عم", "prediction": "عم كيفك",
              "words_correct": 1, "words_total": 2}
    out = tmp_path / "e.xlsx"
    assert E.write_sheet({"metrics": {}}, [record], {}, out) == (2, 1)
    summary = {r[0]: r[1] for r in openpyxl.load_workbook(out)["summary"].iter_rows(values_only=True) if r}
    assert summary["wrong words (word accuracy)"] == 1
    assert summary["error rows in this sheet"] == 2


def test_text_is_never_a_formula_and_control_characters_are_dropped(tmp_path):
    record = {"id": "hw-0001", "arabizi": "=) ok", "reference": "شو", "prediction": "=D\x1bشي",
              "words_correct": 0, "words_total": 1}
    out = tmp_path / "e.xlsx"
    E.write_sheet({"metrics": {}}, [record], {}, out)
    cells = list(openpyxl.load_workbook(out)["sentences"].iter_rows(min_row=2))[0]
    assert [(c.value, c.data_type) for c in cells[3:]] == [("=) ok", "s"), ("شو", "s"), ("=Dشي", "s")]


def test_warns_when_the_data_changed_or_a_row_is_gone(scored_run, capsys):
    dev = P.PAIRS_DIR / "dev.jsonl"
    lines = dev.read_text(encoding="utf-8").splitlines()
    dev.write_text(lines[0] + "\n", encoding="utf-8")  # hw-0002 removed after the run
    assert R.main(["errors", str(scored_run["dev"])]) == 0
    out = capsys.readouterr().out
    assert "Warning: the data changed since this run" in out
    assert "not in the dev split any more (no accepted variants): hw-0002" in out
    summary = [r for r in openpyxl.load_workbook(scored_run["dev"] / "errors.xlsx")["summary"].iter_rows(
        values_only=True) if r and r[0] == "warning"]
    assert len(summary) == 2


def test_private_run_sheet_stays_in_a_private_folder(scored_run, tmp_path):
    meta_path = scored_run["dev"] / "metrics.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta_path.write_text(json.dumps({**meta, "private_sentences": 1}), encoding="utf-8")
    with pytest.raises(SystemExit, match="private"):
        R.main(["errors", str(scored_run["dev"]), "--out", str(tmp_path / "anywhere.xlsx")])
    inside = R.PRIVATE_RESULTS_DIR / "errors.xlsx"
    assert R.main(["errors", str(scored_run["dev"]), "--out", str(inside)]) == 0
    assert inside.exists()


def test_errors_on_a_test_run_needs_final(scored_run, tmp_path):
    with pytest.raises(SystemExit, match="--final"):
        R.main(["errors", str(scored_run["test"])])
    out = tmp_path / "final.xlsx"
    assert R.main(["errors", str(scored_run["test"]), "--final", "--out", str(out)]) == 0
    words = list(openpyxl.load_workbook(out)["words"].iter_rows(min_row=2, values_only=True))
    assert words[0][1:4] == ("أنا", "انا", "spelling convention")
