"""The "others" held-out set (ADR 0021): import, separation from training, freeze and evalrun --others."""

import json

import pytest

from arabizi_eval import pairs as P
from arabizi_eval import run
from arabizi_eval.pairs_cli import main


def sheet(path, rows):
    path.write_text("".join(json.dumps({"id": i, "arabizi": az, "arabic": ar}, ensure_ascii=False) + "\n"
                            for i, (az, ar) in enumerate(rows, 1)), encoding="utf-8")
    return str(path)


@pytest.fixture
def data(monkeypatch, tmp_path):
    public = tmp_path / "pairs"
    public.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", public)
    monkeypatch.setattr(P, "MANIFEST_PATH", public / "manifest.json")
    monkeypatch.setattr(P, "OTHERS_DIR", public / "others")
    monkeypatch.setattr(P, "OTHERS_MANIFEST_PATH", public / "others" / "manifest.json")
    train = sheet(tmp_path / "train.jsonl", [
        ("shu 3am ta3mel", "شو عم تعمل"),
        ("ana bel bet", "أنا بالـ بيت"),            # tatweel after the article is removed
        ("ma3e 5 dollar", "معي ٥ دولار"),           # Arabic-Indic digit: skipped
        ("shu 3am ta3mel", "شو عم تعمل"),           # repeat: skipped
    ])
    held = sheet(tmp_path / "held.jsonl", [
        ("wen rayi7 hala2", "وين رايح هلق"),
        ("kifak ya habibi", "كيفك يا حبيبي"),
        ("shu 3am ta3mel", "شو عم تعمل"),           # same as a training row: skipped
        ("yalla mnetla2a bokra 3al 8", "يلا منتلاقى بكرا عال 8"),
        ("yalla mnetla2a bokra 3al 8 ok", "يلا منتلاقى بكرا عال 8 ok"),  # nearly the row above: both held out
    ])
    return public, train, held


def test_import_real_splits_freezes_and_keeps_others_out_of_training(data, capsys):
    public, train, held = data
    assert main(["import-real", "--train", train, "--held-out", held, "--dev", "1"]) == 0
    train_rows = [r for _, r, _ in P.read_jsonl(public / "train-hand.jsonl")]
    assert [r["arabic"] for r in train_rows] == ["شو عم تعمل", "أنا بالبيت"]
    assert {r["writer"] for r in train_rows} == {"friends-and-family"} and train_rows[0]["checked_by"] == "moustafa"
    others = [r for path in P.pair_files(others=True) for _, r, _ in P.read_jsonl(path)]
    assert len(others) == 4 and sum(r["split"] == "dev" for r in others) == 1
    assert all(r["split"] == "train" for path in P.pair_files() for _, r, _ in P.read_jsonl(path))
    manifest = json.loads(P.OTHERS_MANIFEST_PATH.read_text(encoding="utf-8"))
    assert manifest["version"] == "others-v1.0" and manifest["files"]["others/test.jsonl"]["rows"] == 3
    assert P.validate().ok
    out = capsys.readouterr().out
    assert "عم" not in out  # counts only, never text
    assert main(["import-real", "--train", train, "--held-out", held]) == 1  # frozen: no second import


def test_near_duplicate_of_training_is_not_held_out(data):
    public, train, _ = data
    train = sheet(public.parent / "train5.jsonl", [("ana w enta mnrou7 bokra", "أنا وانت منروح بكرا")])
    held = sheet(public.parent / "near.jsonl", [("ana w enta mnrou7 bokra ok", "أنا وانت منروح بكرا ok"),
                                                ("ana w enta mnrou7 lyom", "أنا وانت منروح اليوم")])
    assert main(["import-real", "--train", train, "--held-out", held]) == 0
    assert [r["arabizi"] for path in P.pair_files(others=True) for _, r, _ in P.read_jsonl(path)] == [
        "ana w enta mnrou7 lyom"]  # 5 of 6 words shared: too close; 4 of 6: kept


def test_changing_others_after_the_freeze_fails_and_train_leaks_are_caught(data):
    public, train, held = data
    main(["import-real", "--train", train, "--held-out", held, "--dev", "1"])
    test_file = P.OTHERS_DIR / "test.jsonl"
    leaked = next(r for _, r, _ in P.read_jsonl(test_file))
    with (public / "train-hand.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({**leaked, "id": "hw-9999", "split": "train"}, ensure_ascii=False) + "\n")
    messages = [p.message for p in P.validate().errors]
    assert any("leaks held-out row others/" in m for m in messages)
    test_file.write_text("", encoding="utf-8")
    assert any("changed after the freeze" in p.message and p.where.startswith("others/")
               for p in P.validate().errors)


def test_evalrun_others_reads_only_the_others_set(data, tmp_path):
    public, train, held = data
    main(["import-real", "--train", train, "--held-out", held, "--dev", "2"])
    rows, _ = run.split_rows("dev", others=True)
    assert len(rows) == 2 and not run.split_rows("dev")[0]
    assert run.main(["run", "--system", "identity", "--split", "dev", "--others", "--results", str(tmp_path)]) == 0
    (run_dir,) = tmp_path.glob("*-identity-dev-others")
    assert json.loads((run_dir / "metrics.json").read_text(encoding="utf-8"))["set"] == "others"


def test_split_glued_prefixes_follows_spelling_section_4():
    assert P.split_glued_prefixes("شفت الvideo عالfacebook وbravo") == "شفت ال video عال facebook و bravo"
    assert P.split_glued_prefixes("ال video كيفك") == "ال video كيفك"  # already apart
    assert P.split_glued_prefixes("شوف www.x.com/الvideo") == "شوف www.x.com/الvideo"  # links untouched
    row = {"arabizi": "el video", "arabic": "الvideo"}
    assert any("SPELLING.md 4" in w for w in P.row_warnings(row))


def test_split_prefixes_rewrites_training_and_others_then_refreeze(data):
    public, train, held = data
    glued_train = sheet(public.parent / "glued.jsonl", [("shefet el video", "شفت الvideo")])
    glued_held = sheet(public.parent / "glued_held.jsonl",
                       [("3al facebook hala2 ya habibi", "عالfacebook هلق يا حبيبي")])
    # import-real already writes new rows apart; glue them again (and freeze that) to test the rewrite
    assert main(["import-real", "--train", glued_train, "--held-out", glued_held]) == 0
    assert [r["arabic"] for _, r, _ in P.read_jsonl(public / "train-hand.jsonl")] == ["شفت ال video"]
    for path in [public / "train-hand.jsonl", *P.pair_files(others=True)]:
        path.write_text(path.read_text(encoding="utf-8").replace("ال video", "الvideo").replace(
            "عال facebook", "عالfacebook"), encoding="utf-8")
    assert main(["freeze", "--others", "--version", "others-v1.0b", "--reason", "glued, as imported before"]) == 0
    assert main(["split-prefixes"]) == 0  # training only: the frozen others set is untouched
    assert P.validate().ok
    assert main(["split-prefixes", "--others"]) == 0
    assert any("changed after the freeze" in p.message for p in P.validate().errors)
    assert main(["freeze", "--others", "--version", "others-v1.1", "--reason", "SPELLING.md 4"]) == 0
    assert P.validate().ok
    assert [r["arabic"] for path in P.pair_files(others=True) for _, r, _ in P.read_jsonl(path)] == [
        "عال facebook هلق يا حبيبي"]


def test_training_rows_alone_after_the_freeze(data, tmp_path, capsys):
    public, train, held = data
    assert main(["import-real", "--train", train, "--held-out", held, "--dev", "1"]) == 0
    frozen = P.OTHERS_MANIFEST_PATH.read_text(encoding="utf-8")
    more = sheet(tmp_path / "more.jsonl", [
        ("wen kenet mbere7", "وين كنت مبارح"),
        ("yalla mnetla2a bokra 3al 8 tamem", "يلا منتلاقى بكرا عال 8 تمام"),  # nearly a held-out sentence: skipped
        ("kifak ya habibi", "كيفك يا حبيبي"),                                  # a held-out sentence: skipped
    ])
    assert main(["import-real", "--train", more, "--source", "batch 2"]) == 0
    train_rows = [r for _, r, _ in P.read_jsonl(public / "train-hand.jsonl")]
    assert [r["arabic"] for r in train_rows][-1] == "وين كنت مبارح" and train_rows[-1]["source"] == "batch 2"
    assert len(train_rows) == 3
    assert P.OTHERS_MANIFEST_PATH.read_text(encoding="utf-8") == frozen  # held-out sets untouched
    assert P.validate().ok
    assert "nearly repeats a held-out sentence (1)" in capsys.readouterr().out
