"""Pair format (docs/DATA.md) and spelling rules that can be checked automatically (docs/SPELLING.md)."""

import json
from datetime import date, timedelta

import pytest
from jsonschema import Draft202012Validator

from arabizi_eval import pairs as P
from arabizi_eval.pairs_cli import default_split, main, next_id, parse_accepted


def make_row(**overrides) -> dict:
    row = {"id": "hw-0001", "arabizi": "ma 3ndi meeting today", "arabic": "ما عندي meeting today",
           "accepted": {}, "method": "hand", "writer": "moustafa", "checked_by": None,
           "source": "hand-written", "split": "test", "date": "2026-10-14"}
    row.update(overrides)
    return row


def write(directory, name, rows):
    (directory / name).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


# --------------------------------------------------------------------------- the real data

def test_schema_is_valid_json_schema():
    Draft202012Validator.check_schema(json.loads(P.SCHEMA_PATH.read_text(encoding="utf-8")))


def test_repository_pairs_are_valid():
    report = P.validate()
    assert report.ok, "\n".join(f"{p.where}: {p.message}" for p in report.errors)


def test_global_variants_are_arabic():
    variants = json.loads((P.ROOT / "data" / "rules" / "accepted_variants.json").read_text(encoding="utf-8"))
    for primary, others in variants["variants"].items():
        assert P.ARABIC_LETTER.search(primary) and others and primary not in others


# --------------------------------------------------------------------------- single-row rules

def test_good_row_has_no_errors():
    assert P.row_errors(make_row(), "test", None) == []


@pytest.mark.parametrize(("overrides", "fragment"), [
    ({"id": "tw-0001"}, "schema"),
    ({"extra": 1}, "schema"),
    ({"split": "dev"}, "file holds 'test'"),
    ({"method": "ai_checked", "id": "ai-0001", "checked_by": "moustafa"}, "hand-written"),
    ({"id": "rv-0001"}, "must start with hw-"),
    ({"arabic": "مَا عندي meeting today"}, "diacritics"),
    ({"arabic": "ما عنـدي meeting today"}, "tatweel"),
    ({"arabizi": "b3at 100$", "arabic": "بعت ١٠٠$"}, "Arabic-Indic"),
    ({"arabizi": "b3at 100$ la mohammad", "arabic": "بعت مية دولار لمحمد"}, "numbers not kept"),
    ({"arabic": "ma 3ndi meeting today"}, "no Arabic letters"),
    ({"arabizi": "ما 3ndi"}, "arabizi has Arabic letters"),
    ({"arabizi": "shuf @rami", "arabic": "شوف رامي"}, "mention"),
    ({"accepted": {"هلق": ["هلأ"]}}, "not in the arabic text"),
])
def test_row_errors(overrides, fragment):
    errors = P.row_errors(make_row(**overrides), "test", None)
    assert any(fragment in e for e in errors), errors


@pytest.mark.parametrize(("arabizi", "numbers"), [
    ("b3at 100$ la mohammad", ["100$"]),
    ("nchoufak 3al 2pm", ["2pm"]),
    ("ba3d 2 se3at", ["2"]),
    ("3am ekol w 7elo la2", []),  # digits inside words are letters
    ("bkon honik 3am", []),  # "3am" is the word عم, never "3 a.m."
    ("l meeting 3al 10:30", ["10:30"]),
])
def test_number_detection(arabizi, numbers):
    assert P.NUMBER.findall(arabizi) == numbers


def test_ai_rows_must_be_checked_and_variants_need_a_parent():
    ai = make_row(id="ai-0001", method="ai_checked", split="train", checked_by=None)
    assert any("must be checked" in e for e in P.row_errors(ai))
    variant = make_row(id="rv-0001", method="rule_variant", split="train")
    assert any("parent" in e for e in P.row_errors(variant))


def test_punctuation_warning():
    row = make_row(arabizi="kifak?", arabic="كيفك?")
    assert P.row_warnings(row)
    assert not P.row_warnings(make_row(arabizi="kifak?", arabic="كيفك؟"))


def test_normalize_arabic():
    assert P.normalize_arabic("كَتِير  منـيح") == "كتير منيح"
    assert P.normalize_arabic("إمتى حلوة أنا", lenient=True) == "امتي حلوه انا"
    assert P.normalize_arabic("إمتى حلوة", lenient=False) == "إمتى حلوة"


# --------------------------------------------------------------------------- cross-file rules

def test_duplicates_and_leakage(tmp_path):
    write(tmp_path, "test.jsonl", [make_row()])
    write(tmp_path, "dev.jsonl", [make_row(id="hw-0002", split="dev", arabizi="Ma 3ndi meeting today!",
                                           arabic="ما عندي meeting today")])
    write(tmp_path, "train-hand.jsonl", [make_row(id="hw-0001", split="train", arabizi="kifak",
                                                  arabic="كيفك")])
    write(tmp_path, "train-rule_variant.jsonl", [make_row(id="rv-0001", method="rule_variant", split="train",
                                                          arabizi="ma 3andi meeting today", parent="hw-0009")])
    messages = [p.message for p in P.validate(tmp_path).errors]
    assert any("duplicate id" in m for m in messages)
    assert any("duplicate of held-out" in m for m in messages)
    assert any("leaks held-out" in m for m in messages)
    assert any("parent hw-0009" in m for m in messages)


def test_bad_file_name(tmp_path):
    write(tmp_path, "mydata.jsonl", [make_row()])
    assert "unexpected pair file name" in P.validate(tmp_path).errors[0].message


def test_invalid_json_line(tmp_path):
    (tmp_path / "test.jsonl").write_text('{"id": \n', encoding="utf-8")
    assert "invalid JSON" in P.validate(tmp_path).errors[0].message


# --------------------------------------------------------------------------- CLI helpers

def test_parse_accepted():
    assert parse_accepted("هلق=هلأ; إمتى=إيمتى|إمتا") == {"هلق": ["هلأ"], "إمتى": ["إيمتى", "إمتا"]}
    assert parse_accepted("") == {}


def test_next_id_and_split_cycle(monkeypatch, tmp_path):
    rows = [make_row(id="hw-0007"), make_row(id="rv-0003")]
    assert next_id("hand", rows) == "hw-0008"
    assert next_id("ai_checked", rows) == "ai-0001"
    monkeypatch.setattr(P, "MANIFEST_PATH", tmp_path / "manifest.json")
    splits = [default_split([make_row()] * n) for n in range(10)]
    assert splits.count("dev") == 3 and splits.count("test") == 7
    (tmp_path / "manifest.json").write_text("{}")
    assert default_split([]) == "train"


# --------------------------------------------------------------------------- review fixes (PR #165)

def days_ago(n: int) -> str:
    return (date.today() - timedelta(days=n)).isoformat()


def answer(monkeypatch, *replies):
    replies = iter(replies)
    monkeypatch.setattr("builtins.input", lambda _prompt: next(replies))


def test_link_followed_by_converted_punctuation_is_kept():
    row = make_row(arabizi="shuf www.x.com? w https://a.b/c, ok", arabic="شوف www.x.com؟ و https://a.b/c، ok")
    assert P.row_errors(row, "test", None) == []


def test_non_object_line_is_reported_not_crashing(tmp_path):
    (tmp_path / "test.jsonl").write_text('[1]\n"text"\n', encoding="utf-8")
    messages = [p.message for p in P.validate(tmp_path).errors]
    assert messages == ["line is not a JSON object"] * 2


def test_check_skips_files_with_broken_lines(monkeypatch, tmp_path):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    content = json.dumps(make_row(date=days_ago(3)), ensure_ascii=False) + "\n{broken\n"
    (tmp_path / "test.jsonl").write_text(content, encoding="utf-8")
    answer(monkeypatch, "")
    main(["check"])
    assert (tmp_path / "test.jsonl").read_text(encoding="utf-8") == content


def test_check_discards_a_rejected_edit(monkeypatch, tmp_path):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    first = make_row(arabizi="b3at 100$", arabic="بعت 100$", date=days_ago(3))
    second = make_row(id="hw-0002", date=days_ago(3))
    write(tmp_path, "test.jsonl", [first, second])
    answer(monkeypatch, "e", "بعت مية", "")  # edit drops the number -> rejected; then confirm the second row
    main(["check"])
    rows = [json.loads(line) for line in (tmp_path / "test.jsonl").read_text(encoding="utf-8").splitlines()]
    assert rows[0] == first
    assert rows[1]["checked_by"] == "moustafa-delayed"


def test_check_waits_at_least_24_hours(monkeypatch, tmp_path):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    write(tmp_path, "test.jsonl", [make_row(date=days_ago(1)), make_row(id="hw-0002", date=days_ago(2))])
    answer(monkeypatch, "")  # only one row may be offered: the one from two days ago
    main(["check"])
    rows = [json.loads(line) for line in (tmp_path / "test.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [r["checked_by"] for r in rows] == [None, "moustafa-delayed"]


# --------------------------------------------------------------------------- pairs import

def test_import_saves_valid_lines_and_reports_the_rest(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    monkeypatch.setattr(P, "MANIFEST_PATH", tmp_path / "manifest.json")
    listing = tmp_path / "list.txt"
    listing.write_text("\n".join([
        "# comment line",
        "kifak, shu 3am ta3mel? | كيفك، شو عم تعمل؟",
        "halla2 ana bel beit | هلق أنا بالبيت | هلق=هلأ",
        "b3at 100$ la mohammad | بعت مية لمحمد",  # number changed
        "KIFAK shu 3am ta3mel | كيفك شو عم تعمل",  # duplicate of line 2
        "ma 3ndi meeting today? | ما عندي meeting today?",  # Latin ? left: warning
        "no separator here",
        "",
    ]), encoding="utf-8")
    assert main(["import", str(listing)]) == 1
    rows = [json.loads(line) for line in (tmp_path / "test.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [r["id"] for r in rows] == ["hw-0001", "hw-0002"]
    assert rows[1]["accepted"] == {"هلق": ["هلأ"]} and rows[0]["checked_by"] is None
    out = capsys.readouterr().out
    assert out.count("REJECTED") == 4 and "2 saved, 4 rejected." in out


def test_import_dry_run_writes_nothing(monkeypatch, tmp_path):
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    listing = tmp_path / "list.txt"
    listing.write_text("kifak | كيفك\n", encoding="utf-8")
    assert main(["import", str(listing), "--dry-run"]) == 0
    assert not (tmp_path / "test.jsonl").exists()


def test_malformed_variants_are_rejected_not_dropped(monkeypatch, tmp_path, capsys):
    with pytest.raises(ValueError):
        parse_accepted("هلق-هلأ")
    with pytest.raises(ValueError):
        parse_accepted("هلق=")
    monkeypatch.setattr(P, "PAIRS_DIR", tmp_path)
    listing = tmp_path / "list.txt"
    listing.write_text("halla2 ana bel beit | هلق أنا بالبيت | هلق-هلأ\n", encoding="utf-8")
    assert main(["import", str(listing)]) == 1
    assert not (tmp_path / "test.jsonl").exists()
    assert "cannot read variant" in capsys.readouterr().out
