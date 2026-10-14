"""B1: base models through llama.cpp's llama-server (roadmap P3 step 4, ADR 0003).

One server per model keeps the model loaded, so per-sentence latency is the conversion time a keyboard would see
(after the first warm-up request). Temperature 0. Qwen3 "thinking" is switched off (it only adds delay).
Few-shot examples come from the public training split, never from dev or test, so no scored sentence is shown to
the model (Claude's recommendation; the roadmap said "from dev").
"""

from __future__ import annotations

import json
import re
import shutil
import socket
import subprocess
import time
import urllib.request
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

from arabizi_eval import pairs as P

MODELS_DIR = P.ROOT / "models"
MANIFEST = P.ROOT / "config" / "models.json"
PROMPT_VERSION = 1
SYSTEM_PROMPT = (
    "You convert Lebanese Arabizi (Lebanese Arabic typed in Latin letters and digits) into Lebanese Arabic script. "
    "Write Lebanese spelling, not Modern Standard Arabic. Keep English and French words, numbers, links and emoji "
    "exactly as typed. Reply with the converted message only, on one line."
)
# Five public training pairs, fixed for every model (ids from data/pairs/train-ai_checked.jsonl).
FEW_SHOT_IDS = ("ai-0001", "ai-0003", "ai-0004", "ai-0010", "ai-0502")
THINK = re.compile(r"<think>.*?</think>", re.DOTALL)


def manifest_entry(model_id: str) -> dict:
    for entry in json.loads(MANIFEST.read_text(encoding="utf-8"))["models"]:
        if entry["id"] == model_id:
            return entry
    raise KeyError(f"unknown model {model_id!r} (see config/models.json)")


def few_shot_examples(ids: tuple[str, ...] = FEW_SHOT_IDS) -> list[dict]:
    by_id = {}
    for path in P.pair_files(include_private=False):
        for _, row, err in P.read_jsonl(path):
            if not err and row.get("id") in ids:
                by_id[row["id"]] = row
    missing = [i for i in ids if i not in by_id]
    if missing or any(by_id[i]["split"] != "train" for i in by_id):
        raise ValueError(f"few-shot examples must be public training rows; missing or not train: {missing}")
    return [by_id[i] for i in ids]


def build_messages(arabizi: str, examples: list[dict]) -> list[dict]:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    for example in examples:
        messages += [{"role": "user", "content": example["arabizi"]},
                     {"role": "assistant", "content": example["arabic"]}]
    return messages + [{"role": "user", "content": arabizi}]


def clean_output(text: str) -> str:
    """First non-empty line, without thinking blocks or wrapping quotes."""
    text = THINK.sub("", text).strip()
    line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return line.strip('"“”«»').strip()


def free_port() -> int:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def rss_mb(pid: int) -> float | None:
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) / 1024 if out else None


@dataclass
class LlamaServer:
    model_path: Path
    context: int = 2048
    port: int = field(default_factory=free_port)
    process: subprocess.Popen | None = None
    peak_rss_mb: float = 0.0
    load_seconds: float = 0.0

    def start(self, timeout: float = 120) -> None:
        if not shutil.which("llama-server"):
            raise RuntimeError("llama-server not found: brew install llama.cpp (docs/MODELS.md)")
        if not self.model_path.exists():
            raise RuntimeError(f"{self.model_path} not found: python3 scripts/fetch_models.py")
        command = ["llama-server", "-m", str(self.model_path), "--host", "127.0.0.1", "--port", str(self.port),
                   "-c", str(self.context), "-np", "1", "-cram", "0", "--no-webui",
                   "--chat-template-kwargs", '{"enable_thinking": false}']
        started = time.perf_counter()
        self.process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        while time.perf_counter() - started < timeout:
            if self.process.poll() is not None:
                raise RuntimeError(f"llama-server exited with code {self.process.returncode}")
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=2) as response:
                    if response.status == 200:
                        self.load_seconds = time.perf_counter() - started
                        return
            except OSError:
                time.sleep(0.5)
        self.stop()
        raise RuntimeError("llama-server did not become ready")

    def chat(self, messages: list[dict], max_tokens: int) -> tuple[str, float]:
        body = json.dumps({"messages": messages, "temperature": 0, "max_tokens": max_tokens,
                           "chat_template_kwargs": {"enable_thinking": False}}).encode()
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}/v1/chat/completions", data=body,
                                         headers={"Content-Type": "application/json"})
        started = time.perf_counter()
        with urllib.request.urlopen(request, timeout=120) as response:
            reply = json.load(response)
        elapsed_ms = (time.perf_counter() - started) * 1000
        if self.process is not None:
            self.peak_rss_mb = max(self.peak_rss_mb, rss_mb(self.process.pid) or 0.0)
        return reply["choices"][0]["message"]["content"] or "", elapsed_ms

    def stop(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None


def llama_version() -> str:
    try:
        out = subprocess.run(["llama-server", "--version"], capture_output=True, text=True, timeout=30)
        return (out.stdout + out.stderr).strip().splitlines()[0]
    except (OSError, subprocess.TimeoutExpired, IndexError):
        return "unknown"
