"""Operational metrics from conversion traces (docs/OBSERVABILITY.md): the three input formats, the rates, and a run
that saves each sentence's trace."""

import json

from arabizi_eval import ops, systems
from arabizi_eval import pairs as P
from arabizi_eval import run as R


def trace(route="model", outcome="model", reason=None, repaired=None, generate=200.0, total=None, tokens=8,
          deadline=1500):
    spans = [{"name": "route", "ms": 1.0}]
    if route == "model":
        spans += [{"name": "protect", "ms": 0.5}, {"name": "generate", "ms": generate}]
        spans += [{"name": "check", "ms": 0.5}] if outcome != "fallbackTimeout" else []
        spans += [{"name": "repair", "ms": 0.2}] if repaired or reason == "check: new Latin words (N)" else []
        spans += [{"name": "restore" if outcome == "model" else "rules", "ms": 1.0}]
    elif route == "noModel":
        spans += [{"name": "rules", "ms": 2.0}]
    t = {"v": 1, "route": route, "outcome": outcome, "reason": reason, "inputWords": 5, "outputWords": 5,
         "deadlineMs": deadline, "spans": spans, "totalMs": total or sum(s["ms"] for s in spans)}
    if route == "model":
        t |= {"promptTokens": 12, "generatedTokens": tokens, "stop": "endOfTurn", "repairedTokens": repaired}
    return t


TRACES = [
    trace(), trace(), trace(repaired=1, reason="repaired: 1 token(s)"),
    trace(outcome="fallbackTimeout", reason="deadline after 12 tokens", generate=1500.0),
    trace(outcome="fallbackCheckFailed", reason="check: new Latin words (1)"),
    trace(route="passthrough", outcome="passthrough"),
    trace(route="noModel", outcome="fallbackModelUnavailable", reason="no model"),
]


def test_rates_follow_the_conversions_the_model_was_asked():
    s = ops.summarise(TRACES)
    assert s["requests"] == 7 and s["routes"]["model"] == 5
    assert s["rates"]["model_answer_kept"] == 0.6  # 3 of 5
    assert s["rates"]["timeout"] == 0.2 and s["rates"]["check_failed"] == 0.2
    assert s["rates"]["recovered_by_repair"] == 0.5  # 1 repaired, 1 not
    assert s["rates"]["fallback_any"] == round(3 / 7, 4) and s["rates"]["passthrough"] == round(1 / 7, 4)
    assert s["fallback_reasons"] == {"deadline after N tokens": 1, "check: new Latin words (N)": 1, "no model": 1}
    assert s["spans_ms"]["generate"]["n"] == 5 and s["spans_ms"]["generate"]["max"] == 1500.0
    assert s["tokens"]["generated_per_second"]["p50"] == 40.0  # 8 tokens in 200 ms
    assert s["deadline"]["over_80_percent"] == 1
    assert "cost" not in s  # no scores without a run folder


def test_the_three_input_formats(tmp_path):
    windows = tmp_path / "traces.jsonl"
    windows.write_text("".join(json.dumps({"at": "2026-11-25T10:00:00Z", "trace": t}) + "\n" for t in TRACES)
                       + "not json\n", encoding="utf-8")
    mac = tmp_path / "traces.ndjson"
    mac.write_text("".join(json.dumps({"subsystem": "lb.aub.arabizi", "eventMessage": json.dumps(t)}) + "\n"
                           for t in TRACES) + json.dumps({"eventMessage": "engine ready"}) + "\n", encoding="utf-8")
    assert ops.summarise_source(windows)["requests"] == ops.summarise_source(mac)["requests"] == 7
    assert "7 conversions" in ops.render(ops.summarise_source(windows))


class Traced(systems.System):
    """A system that answers with the reference and leaves a trace, as EngineSystem does."""

    def __init__(self):
        super().__init__("traced")
        self.last_trace = None

    def convert(self, row):
        self.last_trace = trace()
        return row["arabic"]


def test_a_run_saves_each_trace_and_ops_reads_quality_and_cost(tmp_path, monkeypatch):
    pairs_dir = tmp_path / "pairs"
    pairs_dir.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", pairs_dir)
    rows = [{"id": f"hw-000{i}", "arabizi": "kifak", "arabic": "كيفك", "accepted": {}, "method": "hand",
             "writer": "moustafa", "checked_by": None, "source": "hand-written", "split": "dev", "date": "2026-10-13"}
            for i in (1, 2)]
    (pairs_dir / "dev.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                                         encoding="utf-8")
    monkeypatch.setitem(systems.REGISTRY, "traced", Traced)
    results = tmp_path / "results"
    assert R.main(["run", "--system", "traced", "--split", "dev", "--results", str(results)]) == 0
    (run,) = results.iterdir()
    records = [json.loads(line) for line in (run / "predictions.jsonl").open(encoding="utf-8")]
    assert all(r["trace"]["route"] == "model" for r in records)
    s = ops.summarise_source(run)
    assert s["quality_by_outcome"]["model"] == {"messages": 2, "word_accuracy": 1.0, "exact": 1.0}
    assert s["cost"] == {"usd_per_message": 0.0, "successful_messages": 2, "usd_per_successful_message": 0.0,
                         "model_calls_per_message": 1.0}
    assert R.main(["ops", str(run)]) == 0
