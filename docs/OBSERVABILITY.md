# Observability: conversion traces and operational metrics

Every conversion the engine makes leaves a **trace**: the path it took, the time of each step and the model's token
counts. A trace never holds text (what was typed or what it became), so it can be kept on the user's computer and
summarised without breaking Harfi's privacy rule (THREAT_MODEL.md). This is the lecture C9 idea of traces and spans,
applied to a pipeline with one model call per message.

## What a trace holds

```json
{"v": 1, "route": "model", "outcome": "model", "reason": null,
 "inputWords": 6, "outputWords": 5, "deadlineMs": 1500,
 "promptTokens": 14, "generatedTokens": 11, "stop": "endOfTurn", "repairedTokens": null,
 "spans": [{"name": "route", "ms": 0.4}, {"name": "protect", "ms": 0.1}, {"name": "generate", "ms": 182.3},
           {"name": "check", "ms": 0.3}, {"name": "restore", "ms": 0.1}],
 "totalMs": 183.2}
```

| Field | Meaning |
|---|---|
| `route` | `passthrough` (no Latin letter), `english` (EnglishGuard), `noModel` (no usable model), `tooLong` (over `max_input_chars`), or `model` (the model was asked) |
| `outcome` | The response's outcome (API_CONTRACTS.md): `model`, `fallbackTimeout`, `fallbackCheckFailed`, `fallbackModelUnavailable`, `passthrough` |
| `reason` | Why a fallback happened, or how many tokens were repaired (ADR 0023). Counts only, as `arabizi-cli --explain` gives it |
| `inputWords`, `outputWords` | Word counts of the request and the answer |
| `deadlineMs` | The request's deadline |
| `promptTokens`, `generatedTokens`, `stop` | The model call: the prompt's length in tokens (the saved instruction included, although a kept instruction is not decoded again, ADR 0037), tokens written, and how it ended (`endOfTurn`, `maxTokens`, `deadline`) |
| `repairedTokens` | Tokens fixed by token repair, when the answer was saved that way |
| `spans` | One per step, each timed from the end of the one before: `route` (the guards), `protect` (placeholders), `generate` (the model), `check` (output checks), `repair`, `restore` (abbreviations kept as typed), `rules` (the rule converter) |
| `totalMs` | The whole conversion, as the response's `latencyMs` |

Code: `Packages/ArabiziEngine/Sources/ArabiziEngine/ConversionTrace.swift`, made by `Engine.convertTraced`. Tests:
`ConversionTraceTests.swift` (the spans of every path, the counts, and that a trace holds none of the words typed or
written).

## Where traces go

| Where | How to read them |
|---|---|
| Evaluation runs | `evalrun run` with an `engine-…` system passes `--trace` to `arabizi-cli` and saves each sentence's trace in `predictions.jsonl` |
| Windows engine | `%LOCALAPPDATA%\Harfi\traces.jsonl`, one `{"at": time, "trace": …}` line per conversion. Past 2 MB it becomes `traces.1.jsonl` and the one before is dropped: at most about 4 MB, some 10,000 conversions |
| Mac engine | The system log, subsystem `lb.aub.arabizi`, category `trace`, at the default level so macOS keeps it: `log show --last 1d --predicate 'subsystem == "lb.aub.arabizi" AND category == "trace"' --style ndjson > traces.ndjson` |

Nothing leaves the computer: the Mac engine has no network entitlement, and neither engine makes requests.

## The summary: `evalrun ops`

```
uv run --project eval evalrun ops eval/results/<run>     # a run folder: adds quality and cost
uv run --project eval evalrun ops traces.jsonl           # the Windows engine's file
uv run --project eval evalrun ops traces.ndjson          # the Mac's log export
```

`--json` prints the same summary as JSON. It gives the lecture's reliability and efficiency metrics:

| Metric | Meaning |
|---|---|
| Model answer kept | Of the conversions the model was asked, the share whose answer was used (task success at the step level) |
| Timeout rate | Of those, the share that missed the deadline and fell back to the rules |
| Check-failed rate | The share whose answer failed an output check |
| Recovered by repair | Of the answers that failed a check, the share token repair saved (the lecture's recovery rate) |
| Fallback reasons | Each kind of reason with its count (numbers replaced by N) |
| Latency | End to end and for the model route: p50, p95, max |
| Steps | p50 and p95 of each span, and its share of all time: where the time goes |
| Tokens | Prompt and generated tokens per message, generated tokens per second |
| Deadline used | Each model conversion's time as a share of its deadline; how many used over 80% |
| Quality by outcome (runs) | Word accuracy and exact-match rate of the model's answers against the rules' fallbacks |
| Cost (runs) | Dollars per message and per successful (exactly right) message, and model calls per message |

**Cost.** The model runs on the user's computer, so there is no API and no charge per message: $0 per message and
per successful message. The costs that exist are one-off: about 41 GPU-hours of free Kaggle and Colab training, and
the user's own electricity, which is not measured.

## Results: model v5 with the keyboard's deadline (25 Nov 2026, Windows)

`engine-arabizi-llama3.2-1b-v5-kb` on the two dev sets, on the Windows laptop (Intel i7-10870H, model on the
processor), with the deadline the keyboard gives each message (1.5 s, +120 ms per word over 8, at most 3 s).

| | Others dev (200) | Frozen dev (104) |
|---|---|---|
| Word accuracy | 0.851 | 0.870 |
| Model answer kept | 97.5% | 99.0% |
| Timeouts | 2.5% (5) | 0 |
| Failed checks | 0 | 1.0% (1, invented Latin) |
| Saved by token repair | 7 answers | 0 |
| Latency p50 / p95 | 1,348 / 2,441 ms | 783 / 1,444 ms |
| Generation's share of time | 100% | 100% |
| Every other step, p95 | ≤ 2.5 ms | ≤ 2.4 ms |
| Prompt / generated tokens, p50 | 83 / 21 | 72 / 12 |
| Generated tokens per second, p50 | 15.8 | 15.2 |
| Deadline used, p50 / p95 | 72% / 93% (44 over 80%) | 51% / 75% (3 over 80%) |
| Word accuracy, model answers | 0.860 | 0.875 |
| Word accuracy, rule fallbacks | 0.626 (5 messages) | 0.615 (1 message) |
| Cost per successful message | $0 (57 exactly right) | $0 (54 exactly right) |

What the traces show:

- **All the time is the model's.** The guards, placeholders, checks, repair and restore together take under 3 ms
  (p95). Making Harfi faster means fewer or faster tokens, not a lighter pipeline: a shorter instruction, a smaller
  or faster model, or a faster processor (the Mac's GPU is about 4 times faster, EVAL.md "Speed on the Mac").
- **The deadline is close on this laptop.** Other people's messages are longer (21 generated tokens against 12), at
  about 16 tokens a second, so 44 of 200 conversions used over 80% of their deadline, and 5 missed it. That cost
  accuracy: a fallback scores about 0.63 against 0.86 for the model. On the same laptop two days earlier the same run
  had no timeouts and a p50 of 1,045 ms: the laptop's speed varies, and the traces show by how much.
- **Repair earns its place.** On others dev, 7 answers that invented a Latin word were saved by token repair, and none
  fell back for it.

The run folders are `eval/results/20261125-072719-…-v5-kb-dev-others` and `20261125-072904-…-v5-kb-dev`; the
summaries come from `evalrun ops` on each.

## What is not done, on purpose

**No telemetry.** Harfi never sends traces anywhere, and there is no dashboard of real use: monitoring real use would
mean collecting data about what people type. The traces stay on the computer, and a user can share them by hand. The
next step, if wanted, is an opt-in export of the summary alone (no traces, no text).

**No OpenTelemetry or Langfuse.** Those tools send traces to a collector over the network, which the Mac engine
cannot reach by design. The trace format follows the same idea (a trace per request, a span per step), so a
developer could convert `traces.jsonl` into one offline if needed.
