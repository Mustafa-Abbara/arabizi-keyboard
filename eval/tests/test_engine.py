"""The Swift-engine system (eval/src/arabizi_eval/engine.py) against a fake arabizi-cli: no Swift build needed."""

import json
import stat

import pytest

from arabizi_eval import engine

FAKE_CLI = r'''#!/usr/bin/env python3
import json, sys
model = "--model" in sys.argv and sys.argv[sys.argv.index("--model") + 1]
status = {"state": "ready" if model else "off", "model": model or None, "load_ms": 1}
print(json.dumps(status), file=sys.stderr, flush=True)
for n, line in enumerate(sys.stdin, 1):
    request = json.loads(line)
    fallback = request["text"] == "kifak how"
    print(json.dumps({"v": 1, "id": request["id"], "latencyMs": 3, "text": "كيفك",
                      "outcome": "fallbackCheckFailed" if fallback else "model"}), flush=True)
    if fallback:
        print(json.dumps({"line": n, "reason": "check: new Latin words (1)"}), file=sys.stderr, flush=True)
'''


@pytest.fixture
def fake_cli(tmp_path, monkeypatch):
    path = tmp_path / "arabizi-cli"
    path.write_text(FAKE_CLI)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setattr(engine, "cli_path", lambda: path)
    return path


def test_engine_system_sends_requests_and_counts_outcomes(fake_cli):
    system = engine.EngineSystem("arabizi-llama3.2-1b-v1")
    system.start()
    assert system.describe["status"]["state"] == "ready"
    assert system.convert({"arabizi": "kifak"}) == "كيفك"
    assert system.convert({"arabizi": "kifak how"}) == "كيفك"
    system.close()
    assert system.describe["outcomes"] == {"model": 1, "fallbackCheckFailed": 1}
    assert system.describe["fallback_reasons"] == {"check: new Latin words (1)": 1}


def test_engine_system_refuses_a_model_that_is_not_ready(fake_cli, monkeypatch):
    monkeypatch.setattr(engine.subprocess, "Popen", _popen_with_status({"state": "unavailable", "reason": "SHA-256"}))
    with pytest.raises(SystemExit, match="SHA-256"):
        engine.EngineSystem("arabizi-llama3.2-1b-v1").start()


def _popen_with_status(status):
    class FakeProcess:
        def __init__(self, *args, **kwargs):
            import io
            self.stderr = io.StringIO(json.dumps(status) + "\n")
    return FakeProcess


def test_rules_system_runs_the_cli_without_a_model(fake_cli):
    system = engine.EngineSystem(None)
    system.start()
    assert system.name == "engine-rules" and system.describe["status"]["state"] == "off"
    system.close()
