"""Private data (ADR 0014): own chat messages stay in data/private, and nothing derived from them is public."""

import json

import pytest

from arabizi_eval import b0, run
from arabizi_eval import pairs as P
from arabizi_eval.pairs_cli import held_out_quota, main


@pytest.fixture
def folders(monkeypatch, tmp_path):
    public, private = tmp_path / "pairs", tmp_path / "private" / "pairs"
    public.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", public)
    monkeypatch.setattr(P, "PRIVATE_DIR", private)
    monkeypatch.setattr(P, "MANIFEST_PATH", public / "manifest.json")
    monkeypatch.setattr(b0, "LEXICON_PATH", tmp_path / "lexicon.json")
    monkeypatch.setattr(run, "RESULTS_DIR", tmp_path / "results")
    monkeypatch.setattr(run, "PRIVATE_RESULTS_DIR", tmp_path / "results" / "private")
    public_row = {"id": "ai-0001", "arabizi": "shu 3am ta3mel ya 7abibi", "arabic": "شو عم تعمل يا حبيبي",
                  "accepted": {}, "method": "ai_checked", "writer": "x", "checked_by": "moustafa", "source": "batch",
                  "split": "train", "date": "2026-10-13"}
    (public / "train-ai_checked.jsonl").write_text(json.dumps(public_row, ensure_ascii=False) + "\n", encoding="utf-8")
    chats = tmp_path / "chats.jsonl"
    lines = [{"arabizi": f"sirrewordzz {n} bas kif", "arabic": f"سرية {n} بس كيف", "source": "private chat 1",
              "year": 2025} for n in range(1, 31)]
    lines += [{"arabizi": f"wlek ya grp{n}", "arabic": f"ولك يا جماعة {n}", "source": "group chat"}
              for n in range(1, 11)]
    chats.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in lines) + "\n", encoding="utf-8")
    return tmp_path, public, private, chats


def test_held_out_quota_is_proportional_and_exact():
    assert held_out_quota({"a": 1017, "b": 891, "c": 79}, 300) == {"a": 154, "b": 134, "c": 12}
    assert sum(held_out_quota({"a": 3, "b": 3, "c": 3}, 4).values()) == 4


def test_import_chats_writes_only_to_the_private_folder(folders, capsys):
    tmp, public, private, chats = folders
    before = sorted(p.name for p in public.iterdir())
    assert main(["import-chats", str(chats), "--held-out", "10"]) == 0
    assert sorted(p.name for p in public.iterdir()) == before  # nothing new in the public folder
    rows = {s: [json.loads(x) for x in (private / f).read_text(encoding="utf-8").splitlines()]
            for s, f in (("test", "test.jsonl"), ("dev", "dev.jsonl"), ("train", "train-hand.jsonl"))}
    assert (len(rows["test"]), len(rows["dev"]), len(rows["train"])) == (7, 3, 30)
    groups = [r["source"] for r in rows["test"] + rows["dev"]]
    assert sum("group chat" in g for g in groups) == 2  # 10 of 40 rows -> 2 of 10 held out
    assert all(r["method"] == "hand" and r["writer"] == "moustafa" for r in rows["train"])
    assert "sirrewordzz" not in capsys.readouterr().out  # no message text printed
    assert P.validate().ok
    assert main(["import-chats", str(chats)]) == 1  # refuses to import twice


def test_variants_of_private_rows_stay_private(folders):
    tmp, public, private, chats = folders
    main(["import-chats", str(chats), "--held-out", "10"])
    assert main(["variants", "--per-row", "1", "--show", "0"]) == 0
    public_text = (public / "train-rule_variant.jsonl").read_text(encoding="utf-8")
    private_text = (private / "train-rule_variant.jsonl").read_text(encoding="utf-8")
    assert "sirrewordzz" not in public_text and "sirrewordzz" in private_text.lower()
    ids = [json.loads(x)["id"] for x in (public_text + private_text).splitlines()]
    assert len(ids) == len(set(ids))
    assert P.validate().ok


def test_public_dictionary_never_learns_private_words(folders):
    tmp, public, private, chats = folders
    main(["import-chats", str(chats), "--held-out", "10"])
    assert main(["lexicon"]) == 0
    lexicon = (tmp / "lexicon.json").read_text(encoding="utf-8")
    assert "sirrewordzz" not in lexicon and "shu" in json.loads(lexicon)["words"]


def test_runs_with_private_rows_go_to_the_private_results_folder(folders):
    tmp, public, private, chats = folders
    main(["import-chats", str(chats), "--held-out", "10"])
    assert run.main(["run", "--system", "identity", "--split", "dev"]) == 0
    assert run.main(["run", "--system", "identity", "--split", "dev", "--subset", "public"]) == 1  # no public dev
    (found,) = (tmp / "results" / "private").iterdir()
    meta = json.loads((found / "metrics.json").read_text(encoding="utf-8"))
    assert meta["private_sentences"] == 3 and not (tmp / "results" / found.name).exists()


def test_import_chats_with_nothing_importable_reports_instead_of_crashing(folders, capsys):
    tmp, public, private, chats = folders
    empty = tmp / "empty.jsonl"
    empty.write_text(json.dumps({"arabizi": "shu 3am ta3mel ya 7abibi", "arabic": "شو عم تعمل يا حبيبي"}) + "\n",
                     encoding="utf-8")  # repeats the public training row
    assert main(["import-chats", str(empty)]) == 1
    assert "every row was skipped" in capsys.readouterr().out
