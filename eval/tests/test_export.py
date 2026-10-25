"""Fine-tuning export (P4, ADR 0015): training rows only, the AI cap, validation groups kept whole."""

import json

import pytest

from arabizi_eval import export
from arabizi_eval import pairs as P
from arabizi_eval.b1 import SYSTEM_PROMPT


def row(id_, method, split="train", parent=None, n=0):
    r = {"id": id_, "arabizi": f"shu {n} 3am", "arabic": f"شو {n} عم", "accepted": {}, "method": method,
         "writer": "x", "checked_by": "moustafa" if method != "rule_variant" else None, "source": "s",
         "split": split, "date": "2026-10-14"}
    if parent:
        r["parent"] = parent
    return r


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


@pytest.fixture
def data(monkeypatch, tmp_path):
    public, private = tmp_path / "pairs", tmp_path / "private" / "pairs"
    monkeypatch.setattr(P, "PAIRS_DIR", public)
    monkeypatch.setattr(P, "PRIVATE_DIR", private)
    ai = [row(f"ai-{i:04d}", "ai_checked", n=i) for i in range(1, 21)]
    ai_variants = [row(f"rv-{i:04d}", "rule_variant", parent=f"ai-{(i + 1) // 2:04d}", n=i) for i in range(1, 41)]
    human = [row(f"hw-{i:04d}", "hand", n=100 + i) for i in range(1, 21)]
    human_variants = [row(f"rv-{40 + i:04d}", "rule_variant", parent=f"hw-{(i + 1) // 2:04d}", n=200 + i)
                      for i in range(1, 41)]
    write(public / "train-ai_checked.jsonl", ai)
    write(public / "train-rule_variant.jsonl", ai_variants)
    write(public / "test.jsonl", [row("hw-0900", "hand", split="test", n=900)])
    write(private / "train-hand.jsonl", human)
    write(private / "train-rule_variant.jsonl", human_variants)
    write(private / "dev.jsonl", [row("hw-0901", "hand", split="dev", n=901)])
    return tmp_path


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def test_export_keeps_one_variant_per_ai_row_and_every_human_variant(data):
    summary = export.export(data / "out", ai_variants=1, val_share=0.0)
    assert summary["by_method"] == {"ai_checked": 20, "rule_variant": 20 + 40, "hand": 20}
    assert summary["rows_ai_derived"] == 40 and summary["rows_human"] == 60 and summary["ai_share"] == 0.4


def test_dev_and_test_rows_never_leave_the_mac(data):
    export.export(data / "out", val_share=0.2)
    text = "".join(p.read_text(encoding="utf-8") for p in (data / "out").glob("*.jsonl"))
    assert "hw-0900" not in text and "hw-0901" not in text and "900 عم" not in text


def test_examples_use_the_b1_instruction_and_private_rows_stay_in_private_files(data):
    export.export(data / "out", val_share=0.0)
    public, private = read(data / "out" / "train-public.jsonl"), read(data / "out" / "train-private.jsonl")
    assert {e["id"][:2] for e in public} == {"ai", "rv"} and all(e["id"] != "hw-0001" for e in public)
    assert any(e["id"] == "hw-0001" for e in private)
    roles = [m["role"] for m in public[0]["messages"]]
    assert roles == ["system", "user", "assistant"] and public[0]["messages"][0]["content"] == SYSTEM_PROMPT


def test_a_sentence_and_its_variants_are_all_train_or_all_validation(data):
    export.export(data / "out", val_share=0.3, seed=7)
    where = {}
    for name in ("train-public", "train-private", "val-public", "val-private"):
        for example in read(data / "out" / f"{name}.jsonl"):
            where.setdefault(example["group"], set()).add(name.split("-")[0])
    assert where and all(len(sides) == 1 for sides in where.values())
    assert any(sides == {"val"} for sides in where.values())


def test_public_only_export_has_no_private_file(data):
    export.export(data / "out", val_share=0.0, include_private=False)
    assert not (data / "out" / "train-private.jsonl").exists()
