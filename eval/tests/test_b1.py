"""B1 base-model systems (roadmap P3 step 4) against a fake llama-server: no model or llama.cpp needed.

Written by Mohamad (fake server, checks and messages); adapted by Claude for the start/close lifecycle and the
managed-server mode (14 Oct 2026).
"""

import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from arabizi_eval import b1, systems
from arabizi_eval import pairs as P
from arabizi_eval import run as R

MODEL_FILE = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
ANSWERS = {
    "kifak, shu 3am ta3mel?": "كيفك، شو عم تعمل؟",
    "ma 3ndi meeting today": "ما عندي meeting today",
    "b3at 100$ la mohammad": "بعت 100$ لمحمد",
}


class FakeLlamaServer(BaseHTTPRequestHandler):
    """Answers like llama-server: /v1/models, /props and /v1/chat/completions (Qwen3-style empty think block)."""

    model_path = f"/Users/me/arabizi-keyboard/models/{MODEL_FILE}"
    requests: list[dict] = []

    def _send(self, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/v1/models":
            self._send({"object": "list", "data": [{"id": self.model_path, "object": "model"}]})
        else:
            self._send({"build_info": "b9999-test"})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])).decode("utf-8"))
        type(self).requests.append(body)
        if self.path == "/completion":  # raw prompt (fine-tuned models): answer the Arabizi found inside it
            answer = next((a for q, a in ANSWERS.items() if q in body["prompt"]), "؟")
            self._send({"content": f"{answer}\n"})
            return
        answer = ANSWERS.get(body["messages"][-1]["content"], "؟")
        self._send({"choices": [{"message": {"role": "assistant", "content": f"<think>\n\n</think>\n\n{answer}\n"}}]})

    def log_message(self, *args):
        pass


@pytest.fixture
def server(monkeypatch):
    FakeLlamaServer.requests = []
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), FakeLlamaServer)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{httpd.server_address[1]}"
    monkeypatch.setenv("ARABIZI_LLAMA_URL", url)
    yield url
    httpd.shutdown()
    httpd.server_close()


def test_two_systems_per_pinned_model():
    ids = [m["id"] for m in b1.load_manifest() if "prompt" not in m]  # base models only
    names = [name for name in systems.REGISTRY if name.startswith("b1-")]
    assert sorted(names) == sorted(f"b1-{i}-{s}" for i in ids for s in ("zero", "5shot"))


def test_one_system_per_fine_tuned_model():
    fine_tuned = [m["id"] for m in b1.load_manifest() if "prompt" in m]
    assert fine_tuned  # P4 added at least one
    assert sorted(n for n in systems.REGISTRY if n.startswith("ft-")) == \
        sorted([f"ft-{i}" for i in fine_tuned] + [f"ft-{i}-protect" for i in fine_tuned])


def test_fine_tuned_sends_the_saved_prompt_unchanged(server, monkeypatch):
    entry = next(m for m in b1.load_manifest() if "prompt" in m)
    monkeypatch.setattr(FakeLlamaServer, "model_path", f"/x/models/{entry['file']}")
    system = b1.FineTuned(entry["id"])
    system.start()
    assert system.convert({"arabizi": "b3at 100$ la mohammad"}) == "بعت 100$ لمحمد"
    request = FakeLlamaServer.requests[-1]
    assert request["prompt"] == entry["prompt"]["prefix"] + "b3at 100$ la mohammad" + entry["prompt"]["suffix"]
    assert request["temperature"] == 0 and "messages" not in request  # no chat template re-rendered
    assert system.name == f"ft-{entry['id']}" and system.describe["kind"] == "llm-finetuned"


def test_shots_are_public_training_rows_never_held_out():
    shots = b1.load_shots()
    assert [s["id"] for s in shots] == list(b1.SHOT_IDS)
    assert all(s["split"] == "train" for s in shots)
    held_out = {P.normalize_arabizi(row["arabizi"]) for path in P.pair_files(include_private=False)
                for _, row, err in P.read_jsonl(path) if not err and row["split"] in ("dev", "test")}
    assert not {P.normalize_arabizi(s["arabizi"]) for s in shots} & held_out


def test_messages_zero_and_five_shot():
    zero = b1.build_messages("shu?", [])
    assert [m["role"] for m in zero] == ["system", "user"] and zero[0]["content"] == b1.SYSTEM_PROMPT
    five = b1.build_messages("shu?", b1.load_shots())
    assert [m["role"] for m in five] == ["system"] + ["user", "assistant"] * 5 + ["user"]
    assert five[-1]["content"] == "shu?"


@pytest.mark.parametrize(("raw", "clean"), [
    ("<think>\n\n</think>\n\nشو؟\n", "شو؟"),
    ("<think>hmm, Arabizi…</think>شو؟", "شو؟"),
    ("<think>never closed because max_tokens ran out", ""),
    ("  شو؟  ", "شو؟"),
    ("«شو؟»\nExplanation: shu means what", "شو؟"),  # first line only, quotes stripped
])
def test_clean_removes_think_blocks(raw, clean):
    assert b1.clean(raw) == clean


def test_max_tokens_grows_with_input():
    assert b1.max_tokens("a b c") == 62 and b1.max_tokens("w " * 15) > b1.max_tokens("w")


def test_greedy_request_without_thinking_and_warmup(server):
    system = b1.B1("qwen2.5-0.5b", "zero")
    system.start()
    assert system.convert({"arabizi": "ma 3ndi meeting today"}) == "ما عندي meeting today"
    warmup, request = FakeLlamaServer.requests
    assert warmup["messages"][-1]["content"] == b1.WARMUP
    assert request["temperature"] == 0 and request["seed"] == 0 and request["stream"] is False
    assert request["chat_template_kwargs"] == {"enable_thinking": False}
    assert request["max_tokens"] == b1.max_tokens("ma 3ndi meeting today")


def test_five_shot_sends_the_fixed_pairs_and_records_them(server):
    system = b1.B1("qwen2.5-0.5b", "5shot")
    system.start()
    assert system.name == "b1-qwen2.5-0.5b-5shot"
    assert system.describe["shot_ids"] == list(b1.SHOT_IDS) and len(system.describe["shots_sha256_16"]) == 16
    assert system.describe["build_info"] == "b9999-test" and system.describe["file"] == MODEL_FILE
    assert len(FakeLlamaServer.requests[0]["messages"]) == 12


def test_refuses_when_the_server_holds_another_model(server, monkeypatch):
    monkeypatch.setattr(FakeLlamaServer, "model_path", "C:\\models\\Qwen3-0.6B-Q4_K_M.gguf")
    with pytest.raises(SystemExit, match="Qwen3-0.6B-Q4_K_M.gguf loaded"):
        b1.B1("qwen2.5-0.5b", "zero").start()


def test_clear_message_when_another_program_has_the_port(server, monkeypatch):
    # Seen on a Windows machine where Apache (XAMPP) listens on 8080 and answers 404.
    monkeypatch.setattr(FakeLlamaServer, "do_GET", lambda self: self.send_error(404))
    with pytest.raises(SystemExit, match="answered HTTP 404: is that llama-server"):
        b1.B1("qwen2.5-0.5b", "zero").start()


def test_clear_message_when_no_server(monkeypatch):
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    monkeypatch.setenv("ARABIZI_LLAMA_URL", f"http://127.0.0.1:{port}")
    with pytest.raises(SystemExit, match="Start it first"):
        b1.B1("qwen2.5-0.5b", "zero").start()


def test_evalrun_end_to_end(server, monkeypatch, tmp_path):
    pairs_dir = tmp_path / "pairs"
    pairs_dir.mkdir()
    monkeypatch.setattr(P, "PAIRS_DIR", pairs_dir)
    rows = [{"id": f"hw-000{n}", "arabizi": z, "arabic": a, "accepted": {}, "method": "hand", "writer": "moustafa",
             "checked_by": None, "source": "hand-written", "split": "dev", "date": "2026-10-14"}
            for n, (z, a) in enumerate(ANSWERS.items(), 1)]
    (pairs_dir / "dev.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                                         encoding="utf-8")
    results = tmp_path / "results"
    assert R.main(["run", "--system", "b1-qwen2.5-0.5b-zero", "--split", "dev", "--results", str(results)]) == 0
    (run_dir,) = results.iterdir()
    meta = json.loads((run_dir / "metrics.json").read_text(encoding="utf-8"))
    assert meta["system"] == "b1-qwen2.5-0.5b-zero" and meta["describe"]["kind"] == "llm"
    assert meta["metrics"]["word_accuracy"] == 1.0 and meta["metrics"]["latency_ms_p50"] is not None


def test_external_server_records_that_memory_is_not_measured(server):
    system = b1.B1("qwen2.5-0.5b", "zero")
    system.start()
    system.close()
    assert system.describe["server"] == "external" and "not measured" in system.describe["memory"]


def test_managed_mode_refuses_a_missing_or_wrong_model_file(monkeypatch, tmp_path):
    monkeypatch.delenv("ARABIZI_LLAMA_URL", raising=False)
    monkeypatch.setattr(b1, "MODELS_DIR", tmp_path)
    with pytest.raises(SystemExit, match="fetch_models"):
        b1.B1("qwen2.5-0.5b", "zero").start()
    (tmp_path / MODEL_FILE).write_bytes(b"not the real model")
    with pytest.raises(SystemExit, match="does not match the pinned SHA-256"):
        b1.B1("qwen2.5-0.5b", "zero").start()


def test_convert_before_start_is_an_error():
    with pytest.raises(RuntimeError, match="start"):
        b1.B1("qwen2.5-0.5b", "zero").convert({"arabizi": "shu"})


@pytest.mark.parametrize(("text", "masked", "spans"), [
    ("w baddak 2 recom letters", "w baddak ⟦0⟧ recom letters", ["2"]),  # the dev row the raw model got wrong
    ("b3at 100$ 3al 7:30", "b3at ⟦0⟧ 3al ⟦1⟧", ["100$", "7:30"]),
    ("3am ta3mel 2alb", "3am ta3mel 2alb", []),  # digits inside words are letters
])
def test_protect_numbers(text, masked, spans):
    assert b1.protect_numbers(text) == (masked, spans)
    assert b1.restore_numbers(masked, spans) == text


@pytest.mark.parametrize("output", ["بعت", "بعت ⟦0⟧ ⟦0⟧", "بعت ⟦1⟧", "بعت ⟦0⟧ ⟧"])
def test_restore_refuses_broken_placeholders(output):
    assert b1.restore_numbers(output, ["100$"]) is None


def test_protected_system_falls_back_to_rules_when_a_placeholder_breaks(server, monkeypatch):
    entry = next(m for m in b1.load_manifest() if "prompt" in m)
    monkeypatch.setattr(FakeLlamaServer, "model_path", f"/x/models/{entry['file']}")
    system = b1.ProtectedFineTuned(entry["id"])
    system.start()
    # The fake server answers "؟" to an unknown prompt, losing the placeholder: the rules answer, numbers intact.
    assert "100$" in system.convert({"arabizi": "b3at 100$ la rami"})
    assert system.fallbacks == 1 and system.name.endswith("-protect")
