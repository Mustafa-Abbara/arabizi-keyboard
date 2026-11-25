"""Operational metrics from the engine's conversion traces (docs/OBSERVABILITY.md, lecture C9).

  uv run --project eval evalrun ops eval/results/<run>          a run made with the engine (traces saved per sentence)
  uv run --project eval evalrun ops %LOCALAPPDATA%\\...\\traces.jsonl   the Windows engine's own trace file
  log show --predicate 'subsystem == "lb.aub.arabizi" AND category == "trace"' --style ndjson > traces.ndjson
  uv run --project eval evalrun ops traces.ndjson               the Mac engine's traces from the system log

A trace holds the route a conversion took, the time of each step and the model's token counts, never text. The
summary gives the lecture's reliability and efficiency metrics: how often the model's answer was kept, the timeout,
check-failure and recovery (token repair) rates, the fallback reasons, latency end to end and per step, tokens and
generation speed, and how close conversions came to their deadline. A run folder adds quality per outcome (word
accuracy of the model's answers against the rules' fallbacks) and the cost per successful message.
"""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median

from arabizi_eval.metrics import _percentile

SPANS = ("route", "protect", "generate", "check", "repair", "restore", "rules")


def read_traces(source: Path) -> tuple[list[dict], list[dict]]:
    """(traces, scored records) from a run folder, a traces.jsonl file or `log show --style ndjson` output. Records
    (a run's predictions with their scores) are empty unless `source` is a run folder; lines without a trace are
    skipped (runs made before traces existed, other log lines)."""
    if source.is_dir():
        records = [json.loads(line) for line in (source / "predictions.jsonl").open(encoding="utf-8")
                   if line.strip()]
        records = [r for r in records if r.get("trace")]
        return [r["trace"] for r in records], records
    traces = []
    for line in source.open(encoding="utf-8"):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict) and "eventMessage" in item:  # macOS `log show --style ndjson`
            try:
                item = json.loads(item["eventMessage"])
            except (TypeError, ValueError):
                continue
        trace = item.get("trace", item) if isinstance(item, dict) else None
        if isinstance(trace, dict) and "route" in trace and "spans" in trace:
            traces.append(trace)
    return traces, []


def _stats(values: list[float]) -> dict:
    if not values:
        return {"n": 0}
    return {"n": len(values), "p50": round(median(values), 1), "p95": round(_percentile(values, 0.95), 1),
            "max": round(max(values), 1), "mean": round(mean(values), 1)}


def _rate(part: int, whole: int) -> float | None:
    return round(part / whole, 4) if whole else None


def _reason_kind(reason: str) -> str:
    """A fallback reason with its numbers replaced (`deadline after 12 tokens` -> `deadline after N tokens`)."""
    return re.sub(r"\d+", "N", reason)


def summarise(traces: list[dict], records: list[dict] | None = None) -> dict:
    records = records or []
    outcomes = Counter(t["outcome"] for t in traces)
    routes = Counter(t["route"] for t in traces)
    asked = [t for t in traces if t["route"] == "model"]  # the conversions the model was asked to answer
    kept = [t for t in asked if t["outcome"] == "model"]
    repaired = [t for t in kept if t.get("repairedTokens")]
    timeouts = sum(t["outcome"] == "fallbackTimeout" for t in asked)
    check_failures = sum(t["outcome"] == "fallbackCheckFailed" for t in asked)
    reasons = Counter(_reason_kind(t["reason"]) for t in traces
                      if t.get("reason") and t["outcome"] not in ("model", "passthrough"))

    spans: dict[str, list[float]] = defaultdict(list)
    for t in traces:
        for span in t["spans"]:
            spans[span["name"]].append(span["ms"])
    all_time = sum(t["totalMs"] for t in traces) or 1.0
    span_stats = {name: {**_stats(spans[name]), "share_of_time": round(sum(spans[name]) / all_time, 3)}
                  for name in SPANS if spans.get(name)}

    generated = [t for t in asked if t.get("generatedTokens") is not None]
    speeds = []
    for t in generated:
        generate_ms = sum(s["ms"] for s in t["spans"] if s["name"] == "generate")
        if generate_ms > 0 and t["generatedTokens"]:
            speeds.append(t["generatedTokens"] / generate_ms * 1000)
    headroom = [100 * t["totalMs"] / t["deadlineMs"] for t in asked if t.get("deadlineMs")]  # percent

    summary = {
        "requests": len(traces),
        "routes": dict(routes.most_common()),
        "outcomes": dict(outcomes.most_common()),
        "rates": {
            # Of the conversions the model was asked to answer:
            "model_answer_kept": _rate(len(kept), len(asked)),
            "timeout": _rate(timeouts, len(asked)),
            "check_failed": _rate(check_failures, len(asked)),
            # Answers that failed a check only for invented Latin and were saved by token repair (ADR 0023):
            "recovered_by_repair": _rate(len(repaired), len(repaired) + check_failures),
            # Of all requests:
            "fallback_any": _rate(sum(n for o, n in outcomes.items() if o.startswith("fallback")), len(traces)),
            "passthrough": _rate(outcomes.get("passthrough", 0), len(traces)),
        },
        "fallback_reasons": dict(reasons.most_common()),
        "latency_ms": {"all": _stats([t["totalMs"] for t in traces]),
                       "model_route": _stats([t["totalMs"] for t in asked])},
        "spans_ms": span_stats,
        "tokens": {
            "prompt_per_message": _stats([t["promptTokens"] for t in generated if t.get("promptTokens") is not None]),
            "generated_per_message": _stats([t["generatedTokens"] for t in generated]),
            "generated_per_second": _stats(speeds),
        },
        "deadline": {
            "percent_used": _stats(headroom),
            "over_80_percent": sum(h > 80 for h in headroom),
        },
    }
    if records:
        summary["quality_by_outcome"] = _quality(records)
        exact = sum(bool(r.get("exact")) for r in records)
        summary["cost"] = {
            # Inference runs on the user's own computer: no API, no per-request charge (docs/OBSERVABILITY.md).
            "usd_per_message": 0.0,
            "successful_messages": exact,
            "usd_per_successful_message": 0.0,
            "model_calls_per_message": round(len(asked) / len(records), 3),
        }
    return summary


def _quality(records: list[dict]) -> dict:
    by: dict[str, list[dict]] = defaultdict(list)
    for r in records:
        by[r["trace"]["outcome"]].append(r)
    out = {}
    for outcome, rows in sorted(by.items(), key=lambda item: -len(item[1])):
        words = sum(r["words_total"] for r in rows)
        out[outcome] = {"messages": len(rows),
                        "word_accuracy": round(sum(r["words_correct"] for r in rows) / words, 3) if words else None,
                        "exact": round(sum(bool(r.get("exact")) for r in rows) / len(rows), 3)}
    return out


def summarise_source(source: Path) -> dict:
    traces, records = read_traces(source)
    return {"source": str(source), **summarise(traces, records)}


def render(summary: dict) -> str:
    if not summary["requests"]:
        return f"{summary['source']}: no traces (runs made before traces existed have none: rerun with the engine)"
    lines = [f"{summary['source']}: {summary['requests']} conversions"]
    lines.append("routes    " + ", ".join(f"{k} {v}" for k, v in summary["routes"].items()))
    lines.append("outcomes  " + ", ".join(f"{k} {v}" for k, v in summary["outcomes"].items()))
    lines.append("rates")
    for key, value in summary["rates"].items():
        lines.append(f"  {key:22} {'—' if value is None else f'{value:.1%}'}")
    if summary["fallback_reasons"]:
        lines.append("fallback reasons")
        lines += [f"  {n:5d}  {reason}" for reason, n in summary["fallback_reasons"].items()]

    def row(label: str, s: dict, unit: str = "") -> str:
        if not s.get("n"):
            return f"  {label:22} —"
        return f"  {label:22} p50 {s['p50']}{unit}  p95 {s['p95']}{unit}  max {s['max']}{unit}  (n {s['n']})"
    lines.append("latency")
    lines.append(row("end to end", summary["latency_ms"]["all"], " ms"))
    lines.append(row("model route", summary["latency_ms"]["model_route"], " ms"))
    lines.append("steps")
    for name, s in summary["spans_ms"].items():
        lines.append(row(name, s, " ms") + f"  {s['share_of_time']:.0%} of all time")
    lines.append("tokens")
    lines.append(row("prompt per message", summary["tokens"]["prompt_per_message"]))
    lines.append(row("generated per message", summary["tokens"]["generated_per_message"]))
    lines.append(row("generated per second", summary["tokens"]["generated_per_second"]))
    deadline = summary["deadline"]
    lines.append(row("deadline used", deadline["percent_used"], "%")
                 + f"  ({deadline['over_80_percent']} over 80%)")
    if "quality_by_outcome" in summary:
        lines.append("quality by outcome")
        for outcome, q in summary["quality_by_outcome"].items():
            accuracy = "—" if q["word_accuracy"] is None else f"{q['word_accuracy']:.3f}"
            lines.append(f"  {outcome:22} {q['messages']:5d} messages  word accuracy {accuracy}  "
                         f"exact {q['exact']:.1%}")
        cost = summary["cost"]
        lines.append(f"cost      ${cost['usd_per_message']:.2f} per message, "
                     f"${cost['usd_per_successful_message']:.2f} per successful (exactly right) message "
                     f"({cost['successful_messages']}); {cost['model_calls_per_message']} model calls per message")
    return "\n".join(lines)
