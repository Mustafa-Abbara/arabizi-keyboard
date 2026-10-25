"""The runner end to end on a temporary data folder: sanity systems, test-split guard, external scores, compare."""

import json

import pytest

from arabizi_eval import pairs as P
from arabizi_eval import run as R


@pytest.fixture
def data(monkeypatch, tmp_path):
    pairs_dir = tmp_path / "pairs"
    pairs_dir.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", pairs_dir)
    rows = [
        ("hw-0001", "kifak, shu 3am ta3mel?", "كيفك، شو عم تعمل؟", "dev"),
        ("hw-0002", "ma 3ndi meeting today", "ما عندي meeting today", "dev"),
        ("hw-0003", "b3at 100$ la mohammad", "بعت 100$ لمحمد", "dev"),
        ("hw-0004", "halla2 ana bel beit", "هلق أنا بالبيت", "test"),
    ]
    for split in ("dev", "test"):
        lines = [{"id": i, "arabizi": z, "arabic": a, "accepted": {}, "method": "hand", "writer": "moustafa",
                  "checked_by": None, "source": "hand-written", "split": s, "date": "2026-10-13"}
                 for i, z, a, s in rows if s == split]
        (pairs_dir / f"{split}.jsonl").write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in lines), encoding="utf-8")
    return tmp_path


def run_dir(results, system):
    (found,) = [p for p in results.iterdir() if p.name.endswith(f"-{system}-dev")]
    return found


def test_reference_scores_one_and_identity_scores_low(data):
    results = data / "results"
    assert R.main(["run", "--system", "reference", "--split", "dev", "--results", str(results)]) == 0
    assert R.main(["run", "--system", "identity", "--split", "dev", "--results", str(results)]) == 0
    reference = json.loads((run_dir(results, "reference") / "metrics.json").read_text(encoding="utf-8"))
    identity = json.loads((run_dir(results, "identity") / "metrics.json").read_text(encoding="utf-8"))
    assert reference["metrics"]["word_accuracy"] == 1.0
    assert identity["metrics"]["word_accuracy"] < 0.3
    assert reference["sentences"] == 3 and reference["data_sha256"] == identity["data_sha256"]
    lines = (run_dir(results, "reference") / "predictions.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3 and json.loads(lines[0])["prediction"] == "كيفك، شو عم تعمل؟"


def test_test_split_needs_final(data):
    with pytest.raises(SystemExit):
        R.main(["run", "--system", "reference", "--split", "test", "--results", str(data / "results")])
    assert R.main(["run", "--system", "reference", "--split", "test", "--final", "--results",
                   str(data / "results")]) == 0


def test_score_external_predictions_and_compare(data, capsys):
    results = data / "results"
    predictions = data / "kaggle.jsonl"
    predictions.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in [
        {"id": "hw-0001", "prediction": "كيفك شو عم تعمل", "latency_ms": 300},
        {"id": "hw-0002", "prediction": "ما عندي ميتنغ today", "latency_ms": 500},
        {"id": "hw-0003", "prediction": "بعت 100$ لا محمد", "latency_ms": 400},
    ]) + "\n", encoding="utf-8")
    assert R.main(["score", str(predictions), "--name", "kaggle", "--split", "dev", "--results", str(results)]) == 0
    meta = json.loads((run_dir(results, "kaggle") / "metrics.json").read_text(encoding="utf-8"))
    assert 0 < meta["metrics"]["word_accuracy"] < 1 and meta["metrics"]["latency_ms_p50"] == 400
    assert R.main(["run", "--system", "reference", "--split", "dev", "--results", str(results)]) == 0
    capsys.readouterr()
    assert R.main(["compare", str(run_dir(results, "reference")), str(run_dir(results, "kaggle"))]) == 0
    assert "3 sentences in common" in capsys.readouterr().out


def test_missing_prediction_is_an_error(data):
    predictions = data / "partial.jsonl"
    predictions.write_text(json.dumps({"id": "hw-0001", "prediction": "x"}) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="no prediction for hw-0002"):
        R.main(["score", str(predictions), "--name", "partial", "--split", "dev", "--results", str(data / "r")])
