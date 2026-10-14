"""B1: the base models with no fine-tuning, through llama.cpp's llama-server (roadmap P3 step 4, ADR 0003).

Start the server with one pinned model, then run that model's systems (docs/EVAL.md, "Running B1"):

  llama-server -m models/qwen2.5-0.5b-instruct-q4_k_m.gguf -c 2048 -np 1 --jinja --port 8080
  uv run --project eval evalrun run --system b1-qwen2.5-0.5b-zero --split dev

Each model in config/models.json gets two systems: `-zero` (instruction only) and `-5shot` (instruction plus five
fixed training pairs). Decoding is greedy (temperature 0). Standard library only, so the same code runs on the 8 GB
Air (the reference for latency and memory) and on Windows or Linux (smoke runs only).
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path

from arabizi_eval import pairs as P
from arabizi_eval.systems import MODELS_MANIFEST, System

DEFAULT_URL = "http://127.0.0.1:8080"
TIMEOUT_S = 120

PROMPT_VERSION = 1
# The P4 system prompt (roadmap P4 step 1), so the base and fine-tuned models get the same instruction.
SYSTEM_PROMPT = ("Convert Lebanese Arabizi to Lebanese Arabic script. "
                 "Keep English words, numbers, links and emoji as they are.")
# Five fixed public training pairs, never dev or test: few-shot examples from dev would put their own answers in the
# prompt of the split being scored [Claude's recommendation; the roadmap says "from dev", see docs/EVAL.md].
# Chosen to show English kept in Latin, numbers and %, ؟ and ،, and joined clitics (bel, b, 3al).
SHOT_IDS = ("ai-0004", "ai-0022", "ai-0056", "ai-0116", "ai-0050")
SHOTS = ("zero", "5shot")
WARMUP = "kifak, shu 3am ta3mel?"
THINK = re.compile(r"<think>.*?(?:</think>|$)", re.DOTALL)  # Qwen3 reasoning, even with thinking turned off


def load_manifest(path: Path | None = None) -> list[dict]:
    return json.loads((path or MODELS_MANIFEST).read_text(encoding="utf-8"))["models"]


def load_shots(ids: tuple[str, ...] = SHOT_IDS) -> list[dict]:
    """The few-shot pairs, from public training files only, in the order of `ids`."""
    found = {row["id"]: row for path in P.pair_files(include_private=False) for _, row, err in P.read_jsonl(path)
             if not err and row.get("split") == "train" and row.get("id") in ids}
    missing = [i for i in ids if i not in found]
    if missing:
        raise SystemExit(f"few-shot rows not found in the public training files: {', '.join(missing)}")
    return [found[i] for i in ids]


def build_messages(arabizi: str, shots: list[dict]) -> list[dict]:
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    for shot in shots:
        messages += [{"role": "user", "content": shot["arabizi"]}, {"role": "assistant", "content": shot["arabic"]}]
    return messages + [{"role": "user", "content": arabizi}]


def max_tokens(arabizi: str) -> int:
    """Room for about 10 tokens per input word: enough for any honest answer, a cap on run-away output."""
    return 10 * len(arabizi.split()) + 32


def clean(text: str) -> str:
    return THINK.sub("", text).strip()


class LlamaServer:
    """Minimal client for llama-server's OpenAI-compatible endpoints."""

    def __init__(self, url: str) -> None:
        self.url = url.rstrip("/")
        # The server is local: never route it through a system proxy (Windows reads one from the registry).
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def _request(self, path: str, body: dict | None = None) -> dict:
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(self.url + path, data=data, headers={"Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=TIMEOUT_S) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise SystemExit(f"{self.url}{path} answered HTTP {exc.code}: is that llama-server? If another program "
                             "uses the port, start llama-server with --port 8081 and set "
                             "ARABIZI_LLAMA_URL=http://127.0.0.1:8081") from exc
        except urllib.error.URLError as exc:
            raise SystemExit(f"llama-server is not answering at {self.url} ({exc}). Start it first: "
                             "llama-server -m models/<file> -c 2048 -np 1 --jinja --port 8080") from exc

    def model_file(self) -> str:
        """File name of the model the server has loaded (the -m path; an --alias would hide it)."""
        return Path(self._request("/v1/models")["data"][0]["id"]).name

    def build_info(self) -> str | None:
        try:
            return self._request("/props").get("build_info")
        except SystemExit:
            return None

    def chat(self, messages: list[dict], limit: int) -> str:
        body = {"messages": messages, "temperature": 0, "seed": 0, "max_tokens": limit, "stream": False,
                "cache_prompt": True, "chat_template_kwargs": {"enable_thinking": False}}
        return self._request("/v1/chat/completions", body)["choices"][0]["message"].get("content") or ""


class B1(System):
    """One base model and prompt. Checks that the server holds the pinned file, then warms it up (not timed)."""

    def __init__(self, model_id: str, shots: str, url: str | None = None) -> None:
        if shots not in SHOTS:
            raise ValueError(f"shots must be one of {SHOTS}, not {shots!r}")
        entry = next(m for m in load_manifest() if m["id"] == model_id)
        self.server = LlamaServer(url or os.environ.get("ARABIZI_LLAMA_URL", DEFAULT_URL))
        served = self.server.model_file()
        if served != entry["file"]:
            raise SystemExit(f"llama-server has {served} loaded, but b1-{model_id} needs {entry['file']}. "
                             "Restart it with the right model (one model at a time on the 8 GB Air).")
        self.shots = load_shots() if shots == "5shot" else []
        shot_text = json.dumps([[s["arabizi"], s["arabic"]] for s in self.shots], ensure_ascii=False)
        super().__init__(f"b1-{model_id}-{shots}", {
            "kind": "llm", "model": model_id, "file": entry["file"], "sha256": entry["sha256"],
            "quant": entry["quant"], "licence": entry["licence"], "runtime": "llama.cpp llama-server",
            "build_info": self.server.build_info(), "prompt_version": PROMPT_VERSION, "shots": shots,
            "shot_ids": [s["id"] for s in self.shots],
            "shots_sha256_16": hashlib.sha256(shot_text.encode("utf-8")).hexdigest()[:16],
            "decoding": "greedy (temperature 0, seed 0), max_tokens 10 per word + 32",
            "postprocess": "<think> blocks removed, whitespace stripped",
            "memory": "peak RSS is measured outside the harness (docs/EVAL.md, Running B1)",
        })
        self.convert({"arabizi": WARMUP})

    def convert(self, row: dict) -> str:
        text = row["arabizi"]
        return clean(self.server.chat(build_messages(text, self.shots), max_tokens(text)))
