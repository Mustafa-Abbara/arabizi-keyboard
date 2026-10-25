"""The Swift engine through arabizi-cli (roadmap P5 step 6), so the harness measures what the keyboard runs.

  swift build -c release --package-path Packages/ArabiziEngine
  uv run --project eval evalrun run --system engine-arabizi-llama3.2-1b-v2 --split dev

`engine-<id>` runs the engine with that fine-tuned model switched on; `engine-rules` with the model off (the Swift
rule fallback). Each sentence is one ConvertRequest on the CLI's stdin; the response's text and latency are scored,
and the outcomes (model, fallbackTimeout, fallbackCheckFailed…) and fallback reasons (counts only) are recorded.
"""

from __future__ import annotations

import json
import subprocess
import uuid
from collections import Counter
from pathlib import Path

from arabizi_eval import pairs as P
from arabizi_eval.systems import System

PACKAGE = P.ROOT / "Packages" / "ArabiziEngine"
DEADLINE_MS = 10_000  # accuracy runs: generous, so a busy Mac does not turn answers into fallbacks; latency is recorded


def cli_path() -> Path:
    for config in ("release", "debug"):
        path = PACKAGE / ".build" / config / "arabizi-cli"
        if path.exists():
            return path
    raise SystemExit("arabizi-cli not built: swift build -c release --package-path Packages/ArabiziEngine")


class EngineSystem(System):
    def __init__(self, model_id: str | None, deadline_ms: int = DEADLINE_MS, repair: bool = True,
                 keyboard_deadline: bool = False) -> None:
        super().__init__(f"engine-{model_id or 'rules'}" + ("" if repair else "-norepair")
                         + ("-kb" if keyboard_deadline else ""), {
            "kind": "swift-engine", "cli": "arabizi-cli", "model": model_id,
            "deadline_ms": "keyboard (config/engine.json, ADR 0025)" if keyboard_deadline else deadline_ms,
            "pipeline": "ProtectedSpans, saved prompt, model with deadline, clean, OutputChecks"
                        + (", token repair (ADR 0023)" if repair else "") + "; rules on fallback",
        })
        self.model_id = model_id
        self.repair = repair
        self.keyboard_deadline = keyboard_deadline
        self.deadline_ms = deadline_ms
        self.process: subprocess.Popen | None = None
        self.outcomes: Counter = Counter()
        self.reasons: Counter = Counter()
        self.repairs: Counter = Counter()

    def start(self) -> None:
        args = [str(cli_path()), "--config", str(P.ROOT / "config"), "--rules", str(P.ROOT / "data" / "rules"),
                "--models", str(P.ROOT / "models"), "--explain"]
        args += ["--model", self.model_id] if self.model_id else ["--no-model"]
        args += [] if self.repair else ["--no-repair"]
        args += ["--keyboard-deadline"] if self.keyboard_deadline else []
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding="utf-8", bufsize=1)
        status = json.loads(self.process.stderr.readline())
        self.describe["status"] = status
        if self.model_id and status.get("state") != "ready":
            raise SystemExit(f"engine model not ready: {status.get('reason', status)}")

    def convert(self, row: dict) -> str:
        if self.process is None:
            raise RuntimeError("call start() first")
        request = {"v": 1, "id": str(uuid.uuid4()), "text": row["arabizi"], "deadlineMs": self.deadline_ms}
        self.process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        self.outcomes[response["outcome"]] += 1
        reason = json.loads(self.process.stderr.readline()).get("reason")  # --explain: one line per request
        if response["outcome"] not in ("model", "passthrough"):
            self.reasons[reason or "?"] += 1
        elif reason:  # a model answer repaired token by token (ADR 0023)
            self.repairs[reason] += 1
        return response["text"]

    def close(self) -> None:
        if self.process is not None:
            self.process.stdin.close()
            self.process.wait(timeout=30)
            self.process = None
        self.describe["outcomes"] = dict(self.outcomes)
        self.describe["fallback_reasons"] = dict(self.reasons.most_common())
        self.describe["repairs"] = dict(self.repairs.most_common())
