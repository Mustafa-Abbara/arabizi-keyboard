"""B1: the base models with no fine-tuning, through llama.cpp's llama-server (roadmap P3 step 4, ADR 0003).

  uv run --project eval evalrun run --system b1-qwen2.5-0.5b-zero  --split dev
  uv run --project eval evalrun run --system b1-qwen2.5-0.5b-5shot --split dev

Each model in config/models.json gets two systems: `-zero` (instruction only) and `-5shot` (instruction plus five
fixed public training pairs). Greedy decoding (temperature 0, seed 0); Qwen3 thinking is turned off.

Two ways to reach the model:
- **Managed (default, the official runs on the 8 GB Air):** the system checks the pinned file on disk (size and
  SHA-256), starts its own llama-server, measures load time and peak memory (RSS), and stops it afterwards.
- **External (`ARABIZI_LLAMA_URL=http://127.0.0.1:8081`):** use a llama-server started by hand, e.g. for smoke
  runs on Windows; the system checks that it holds the pinned file. Memory is then not measured.

Combined from Mohamad's version (external server, checks and messages, P4 prompt, documented few-shot rows, fake-
server tests) and a managed-server version (automatic memory and load time), 14 Oct 2026.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request
from contextlib import closing
from pathlib import Path

from arabizi_eval import pairs as P
from arabizi_eval.systems import MODELS_MANIFEST, System

MODELS_DIR = P.ROOT / "models"
TIMEOUT_S = 120
PROMPT_VERSION = 1
# The P4 system prompt (roadmap P4 step 1), so the base and fine-tuned models get the same instruction.
SYSTEM_PROMPT = ("Convert Lebanese Arabizi to Lebanese Arabic script. "
                 "Keep English words, numbers, links and emoji as they are.")
# Five fixed public training pairs, never dev or test: few-shot examples from dev would put their own answers in the
# prompt of the split being scored [Recommendation; the roadmap says "from dev", see docs/EVAL.md].
# Chosen (Mohamad) to show English kept in Latin, numbers and %, ؟ and ،, and joined clitics (bel, b, 3al).
SHOT_IDS = ("ai-0004", "ai-0022", "ai-0056", "ai-0116", "ai-0050")
SHOTS = ("zero", "5shot")
WARMUP = "kifak, shu 3am ta3mel?"
THINK = re.compile(r"<think>.*?(?:</think>|$)", re.DOTALL)  # Qwen3 reasoning, even with thinking turned off
SERVER_FLAGS = ["-c", "2048", "-np", "1", "-cram", "0", "--no-webui", "--jinja",
                "--chat-template-kwargs", '{"enable_thinking": false}']  # -cram 0: no 8 GB prompt cache on 8 GB


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
    """Remove thinking blocks; keep the first non-empty line without wrapping quotes (models add explanations)."""
    text = THINK.sub("", text).strip()
    line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return line.strip('"“”«»').strip()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while block := f.read(1 << 20):
            digest.update(block)
    return digest.hexdigest()


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

    def complete(self, prompt: str, limit: int) -> str:
        """Raw completion of an already rendered prompt (no chat template applied by the server)."""
        body = {"prompt": prompt, "temperature": 0, "seed": 0, "n_predict": limit, "stream": False,
                "cache_prompt": True}
        return self._request("/completion", body).get("content") or ""


class ManagedServer:
    """A llama-server process started and stopped by the harness, with load time and peak RSS."""

    def __init__(self, model_path: Path) -> None:
        self.model_path = model_path
        self.process: subprocess.Popen | None = None
        self.load_seconds = 0.0
        self.peak_rss_mb = 0.0
        with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
            s.bind(("127.0.0.1", 0))
            self.port = s.getsockname()[1]
        self.url = f"http://127.0.0.1:{self.port}"

    def start(self, timeout: float = TIMEOUT_S) -> None:
        if not shutil.which("llama-server"):
            raise SystemExit("llama-server not found: brew install llama.cpp (docs/MODELS.md)")
        started = time.perf_counter()
        command = ["llama-server", "-m", str(self.model_path), "--host", "127.0.0.1", "--port", str(self.port),
                   *SERVER_FLAGS]
        self.process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        while time.perf_counter() - started < timeout:
            if self.process.poll() is not None:
                raise SystemExit(f"llama-server exited with code {self.process.returncode} while loading "
                                 f"{self.model_path.name}")
            try:
                with opener.open(f"{self.url}/health", timeout=2) as response:
                    if response.status == 200:
                        self.load_seconds = time.perf_counter() - started
                        return
            except OSError:
                time.sleep(0.5)
        self.stop()
        raise SystemExit(f"llama-server did not become ready in {timeout:.0f} s")

    def sample_memory(self) -> None:
        if self.process is None:
            return
        out = subprocess.run(["ps", "-o", "rss=", "-p", str(self.process.pid)], capture_output=True, text=True)
        if out.stdout.strip():
            self.peak_rss_mb = max(self.peak_rss_mb, int(out.stdout) / 1024)

    def stop(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None


class B1(System):
    """One base model and prompt. Starts (or checks) the server, warms it up untimed, then converts."""

    def __init__(self, model_id: str, shots: str, url: str | None = None) -> None:
        if shots not in SHOTS:
            raise ValueError(f"shots must be one of {SHOTS}, not {shots!r}")
        self.entry = next(m for m in load_manifest() if m["id"] == model_id)
        self.external_url = url or os.environ.get("ARABIZI_LLAMA_URL")
        self.managed: ManagedServer | None = None
        self.server: LlamaServer | None = None
        self.shots = load_shots() if shots == "5shot" else []
        shot_text = json.dumps([[s["arabizi"], s["arabic"]] for s in self.shots], ensure_ascii=False)
        super().__init__(f"b1-{model_id}-{shots}", {
            "kind": "llm", "model": model_id, "file": self.entry["file"], "sha256": self.entry["sha256"],
            "params": self.entry["params"], "quant": self.entry["quant"], "licence": self.entry["licence"],
            "runtime": "llama.cpp llama-server", "server": "external" if self.external_url else "managed",
            "prompt_version": PROMPT_VERSION, "shots": shots, "shot_ids": [s["id"] for s in self.shots],
            "shots_sha256_16": hashlib.sha256(shot_text.encode("utf-8")).hexdigest()[:16],
            "decoding": "greedy (temperature 0, seed 0), max_tokens 10 per word + 32",
            "postprocess": "<think> blocks removed; first non-empty line; wrapping quotes stripped",
        })

    def start(self) -> None:
        if self.external_url:
            self.server = LlamaServer(self.external_url)
            served = self.server.model_file()
            if served != self.entry["file"]:
                raise SystemExit(f"llama-server has {served} loaded, but {self.name} needs {self.entry['file']}. "
                                 "Restart it with the right model (one model at a time on the 8 GB Air).")
            self.describe["memory"] = "not measured (external server)"
        else:
            path = MODELS_DIR / self.entry["file"]
            if not path.exists():
                raise SystemExit(f"{path} not found: python3 scripts/fetch_models.py (docs/MODELS.md)")
            if path.stat().st_size != self.entry["size"] or file_sha256(path) != self.entry["sha256"]:
                raise SystemExit(f"{path.name} does not match the pinned SHA-256: fetch it again")
            self.managed = ManagedServer(path)
            self.managed.start()
            self.server = LlamaServer(self.managed.url)
        self.describe["build_info"] = self.server.build_info()
        self.convert({"arabizi": WARMUP})  # the first request is slower; keep it out of the latency numbers

    def convert(self, row: dict) -> str:
        if self.server is None:
            raise RuntimeError("call start() first")
        text = row["arabizi"]
        reply = self.server.chat(build_messages(text, self.shots), max_tokens(text))
        if self.managed is not None:
            self.managed.sample_memory()
        return clean(reply)

    def close(self) -> None:
        if self.managed is not None:
            self.describe["load_seconds"] = round(self.managed.load_seconds, 2)
            self.describe["peak_rss_mb"] = round(self.managed.peak_rss_mb, 1)
            self.managed.stop()


class FineTuned(B1):
    """A fine-tuned model (P4): zero-shot with the exact prompt saved by its training run (`prompt` in
    config/models.json), sent as text to llama-server's /completion, so no chat template is re-rendered (Llama 3.2's
    would put today's date in it). The server tokenizes the text as training did, BOS included: Llama 3.2 training
    saw two BOS tokens (the template's and the tokenizer's), and only that reproduces the run's samples."""

    def __init__(self, model_id: str, url: str | None = None) -> None:
        super().__init__(model_id, "zero", url)
        self.prompt = self.entry["prompt"]
        self.name = f"ft-{model_id}"
        self.describe.update({
            "kind": "llm-finetuned", "base": self.entry["base"], "run": self.entry["run"], "shots": "zero",
            "prompt": "saved by the training run (config/models.json), sent to /completion",
            "prompt_sha256_16": hashlib.sha256(json.dumps(self.prompt, ensure_ascii=False, sort_keys=True)
                                               .encode("utf-8")).hexdigest()[:16],
            "postprocess": "first non-empty line; wrapping quotes stripped",
        })
        self.describe.pop("shot_ids", None)
        self.describe.pop("shots_sha256_16", None)
        self.describe.pop("prompt_version", None)

    def convert(self, row: dict) -> str:
        if self.server is None:
            raise RuntimeError("call start() first")
        text = row["arabizi"]
        reply = self.server.complete(self.prompt["prefix"] + text + self.prompt["suffix"], max_tokens(text))
        if self.managed is not None:
            self.managed.sample_memory()
        return clean(reply)


PLACEHOLDER = re.compile(r"⟦(\d+)⟧")


def protect_numbers(text: str) -> tuple[str, list[str]]:
    """Standalone numbers (pairs.NUMBER: 100$, 2pm, 7:30, not the 3 of 3am) become ⟦0⟧, ⟦1⟧… as in the engine's
    ProtectedSpans (ADR 0016), so the model cannot read a number as a letter (`2` is also ق in Arabizi)."""
    spans: list[str] = []

    def placeholder(match: re.Match) -> str:
        spans.append(match.group())
        return f"⟦{len(spans) - 1}⟧"

    return P.NUMBER.sub(placeholder, text), spans


def restore_numbers(output: str, spans: list[str]) -> str | None:
    """Put the numbers back; None if a placeholder was lost, repeated or invented (the engine then uses the rules)."""
    found = PLACEHOLDER.findall(output)
    if sorted(found, key=int) != [str(i) for i in range(len(spans))] or output.count("⟦") != len(spans) \
            or output.count("⟧") != len(spans):
        return None
    return PLACEHOLDER.sub(lambda m: spans[int(m.group(1))], output)


class ProtectedFineTuned(FineTuned):
    """`ft-<id>-protect`: the fine-tuned model with standalone numbers protected as the P5 engine does; if the
    model breaks a placeholder, the sentence gets the rule baseline (B0), as the engine's fallback would."""

    def __init__(self, model_id: str, url: str | None = None) -> None:
        super().__init__(model_id, url)
        from arabizi_eval import b0

        self.rules = b0.RuleConverter()
        self.name = f"ft-{model_id}-protect"
        self.fallbacks = 0
        self.describe.update({"protect": "standalone numbers -> placeholders, restored after; B0 if broken"})

    def convert(self, row: dict) -> str:
        masked, spans = protect_numbers(row["arabizi"])
        output = super().convert({"arabizi": masked})
        if not spans:
            return output
        restored = restore_numbers(output, spans)
        if restored is None:
            self.fallbacks += 1
            return self.rules.convert(row["arabizi"])
        return restored

    def close(self) -> None:
        self.describe["fallbacks_to_rules"] = self.fallbacks
        super().close()
