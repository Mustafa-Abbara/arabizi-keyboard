"""Test-set freeze (roadmap P2 step 4): hashes of the held-out files, checked by validate and CI."""

import json

import pytest

from arabizi_eval import pairs as P
from arabizi_eval.pairs_cli import default_split, main


def row(id_, split, checked="moustafa-delayed"):
    return {"id": id_, "arabizi": f"shu {id_[-1]} 3am", "arabic": f"شو {id_[-1]} عم", "accepted": {},
            "method": "hand", "writer": "moustafa", "checked_by": checked, "source": "hand-written",
            "split": split, "date": "2026-10-13"}


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


@pytest.fixture
def data(monkeypatch, tmp_path):
    public, private = tmp_path / "pairs", tmp_path / "private" / "pairs"
    monkeypatch.setattr(P, "PAIRS_DIR", public)
    monkeypatch.setattr(P, "PRIVATE_DIR", private)
    monkeypatch.setattr(P, "MANIFEST_PATH", public / "manifest.json")
    write(public / "test.jsonl", [row("hw-0001", "test"), row("hw-0002", "test")])
    write(public / "dev.jsonl", [row("hw-0003", "dev")])
    write(private / "test.jsonl", [row("hw-0004", "test")])
    write(private / "dev.jsonl", [row("hw-0005", "dev")])
    return public, private


def test_freeze_records_hashes_and_validate_passes(data):
    public, _ = data
    assert main(["freeze"]) == 0
    manifest = json.loads((public / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == "testset-v1.0" and manifest["unchecked_rows"] == 0
    assert manifest["files"]["public/test.jsonl"]["rows"] == 2
    assert manifest["files"]["private/dev.jsonl"] == {
        "sha256": P.sha256_file(data[1] / "dev.jsonl"), "rows": 1, "private": True}
    assert "شو" not in (public / "manifest.json").read_text(encoding="utf-8")  # no text, only hashes
    assert P.validate().ok


def test_editing_a_frozen_file_fails_validation(data):
    public, private = data
    main(["freeze"])
    write(public / "test.jsonl", [row("hw-0001", "test")])  # a row removed
    messages = [p.where + " " + p.message for p in P.validate().errors]
    assert any("public/test.jsonl" in m and "changed after the freeze" in m for m in messages)
    write(private / "dev.jsonl", [row("hw-0006", "dev")])
    assert any("private/dev.jsonl" in m for m in (p.where for p in P.validate().errors))


def test_private_files_missing_elsewhere_are_not_an_error(data):
    _, private = data
    main(["freeze"])
    for f in private.iterdir():
        f.unlink()  # like CI or a fresh clone: private files are not there
    assert P.validate().ok


def test_freeze_refuses_unchecked_rows_unless_allowed(data):
    public, _ = data
    write(public / "dev.jsonl", [row("hw-0003", "dev", checked=None)])
    assert main(["freeze"]) == 1 and not (public / "manifest.json").exists()
    assert main(["freeze", "--allow-unchecked"]) == 0
    assert json.loads((public / "manifest.json").read_text(encoding="utf-8"))["unchecked_rows"] == 1


def test_refreeze_needs_a_new_version_and_a_reason(data):
    main(["freeze"])
    assert main(["freeze"]) == 1
    assert main(["freeze", "--version", "testset-v1.0", "--reason", "typo fixed"]) == 1
    assert main(["freeze", "--version", "testset-v1.1", "--reason", "typo fixed in hw-0002"]) == 0
    manifest = json.loads(P.MANIFEST_PATH.read_text(encoding="utf-8"))
    assert manifest["previous_version"] == "testset-v1.0" and manifest["reason"] == "typo fixed in hw-0002"


def test_after_the_freeze_new_rows_go_to_training(data, tmp_path):
    assert default_split([]) in ("test", "dev")
    main(["freeze"])
    assert default_split([]) == "train"
    chats = tmp_path / "chats.jsonl"
    chats.write_text(json.dumps({"arabizi": "wlek ya jame3a", "arabic": "ولك يا جماعة", "source": "chat"}) + "\n",
                     encoding="utf-8")
    assert main(["import-chats", str(chats)]) == 1  # held-out rows refused once frozen
    assert main(["import-chats", str(chats), "--held-out", "0"]) == 0
