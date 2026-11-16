"""How long the model's guesses for the ↑ list take on this machine (ADR 0036 #5), as the keyboard asks for them.

For each row of a public dev set, the Swift engine (arabizi-cli) converts the message with the keyboard's deadline;
then, for each word the model wrote wrong, it is asked for that word's guesses, right after the conversion, with the
keyboard's count. The deadline given is long, so the true time is measured, not the cut. Prints counts and times
only, never text.

  swift build -c release --package-path Packages/ArabiziEngine --product arabizi-cli
  uv run --project eval python scripts/word_guess_latency.py              # dev-others, 5 guesses
  uv run --project eval python scripts/word_guess_latency.py --set dev --count 10

The model file named in config/engine.json must be in models/. Dev sets only: the test sets are run once per final
system, never for this.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import subprocess
import sys
import time
import uuid
from pathlib import Path

from arabizi_eval import b0
from arabizi_eval import candidates as C

ROOT = Path(__file__).resolve().parents[1]
SETS = {"dev": ROOT / "data" / "pairs" / "dev.jsonl", "dev-others": ROOT / "data" / "pairs" / "others" / "dev.jsonl"}
CLI = ROOT / "Packages" / "ArabiziEngine" / ".build" / "release" / ("arabizi-cli.exe" if sys.platform == "win32" else "arabizi-cli")
if sys.platform == "win32":  # SwiftPM on Windows keeps release builds under the target triple
    CLI = ROOT / "Packages" / "ArabiziEngine" / ".build" / "x86_64-unknown-windows-msvc" / "release" / "arabizi-cli.exe"
# The keyboard's own numbers (Packages/ArabiziCore/Sources/ArabiziCore/WordGuesses.swift).
KEYBOARD_COUNT, KEYBOARD_DEADLINE_MS = 5, 600


def percentile(values: list[int], p: float) -> int:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, round(p / 100 * (len(ordered) - 1))))]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--set", choices=sorted(SETS), default="dev-others")
    parser.add_argument("--count", type=int, default=KEYBOARD_COUNT, help="guesses per word (the keyboard asks 5)")
    parser.add_argument("--limit", type=int, default=0, help="stop after this many wrong words (0: all)")
    parser.add_argument("--cli", type=Path, default=CLI)
    args = parser.parse_args(argv)
    if not args.cli.exists():
        print(f"no {args.cli}: build it first (see the top of this script)", file=sys.stderr)
        return 2

    env = dict(os.environ)
    llama = ROOT / "build" / "llama.cpp" / "build" / "bin" / "Release"  # Windows: llama.dll, built from source
    if sys.platform == "win32" and llama.is_dir():
        env["PATH"] = f"{llama}{os.pathsep}{env.get('PATH', '')}"
    rules = b0.RuleConverter()
    rows = [json.loads(line) for line in SETS[args.set].read_text("utf-8").splitlines() if line.strip()]
    engine = subprocess.Popen([str(args.cli), "--keyboard-deadline", "--config", str(ROOT / "config"),
                               "--rules", str(ROOT / "data" / "rules"), "--models", str(ROOT / "models")],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, encoding="utf-8", bufsize=1, env=env)
    status = json.loads(engine.stderr.readline())
    if status.get("state") != "ready":
        print(f"the model is not ready: {status}", file=sys.stderr)
        return 2

    def ask(request: dict) -> tuple[dict, int]:
        started = time.perf_counter()
        engine.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        engine.stdin.flush()
        answer = json.loads(engine.stdout.readline())
        return answer, round((time.perf_counter() - started) * 1000)

    engine_ms, wall_ms, outcomes, converted = [], [], {}, 0
    for row in rows:
        conversion, _ = ask({"v": 1, "id": str(uuid.uuid4()).upper(), "text": row["arabizi"], "deadlineMs": 1500})
        if conversion.get("outcome") != "model":
            continue
        converted += 1
        scored = {"arabizi": row["arabizi"], "reference": row["arabic"], "prediction": conversion["text"]}
        for _k, _kind, _typed, _shown, before, _right in C.wrong_words(scored, rules):
            answer, ms = ask({"v": 1, "kind": "wordGuesses", "id": str(uuid.uuid4()).upper(), "text": row["arabizi"],
                              "before": before, "count": args.count, "deadlineMs": 5000})
            outcomes[answer["outcome"]] = outcomes.get(answer["outcome"], 0) + 1
            engine_ms.append(answer["latencyMs"])
            wall_ms.append(ms)
            if args.limit and len(engine_ms) >= args.limit:
                break
        if args.limit and len(engine_ms) >= args.limit:
            break
    engine.stdin.close()
    engine.wait(timeout=30)

    if not engine_ms:
        print("no wrong words were asked about", file=sys.stderr)
        return 1
    late = sum(ms > KEYBOARD_DEADLINE_MS for ms in engine_ms)
    report = {
        "machine": f"{platform.system()} {platform.machine()} ({platform.processor() or 'cpu unknown'})",
        "model": status.get("model"), "set": args.set, "count": args.count,
        "rows_converted_by_model": converted, "words": len(engine_ms), "outcomes": outcomes,
        "engine_ms": {"p50": round(statistics.median(engine_ms)), "p90": percentile(engine_ms, 90),
                      "p95": percentile(engine_ms, 95), "max": max(engine_ms)},
        "round_trip_ms": {"p50": round(statistics.median(wall_ms)), "p95": percentile(wall_ms, 95)},
        "over_400ms": f"{sum(ms > 400 for ms in engine_ms) / len(engine_ms):.1%}",
        f"over_keyboard_deadline_{KEYBOARD_DEADLINE_MS}ms": f"{late / len(engine_ms):.1%}",
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
