"""config/models.json and scripts/fetch_models.py (docs/MODELS.md). No network: only the plan and the checks."""

import hashlib
import importlib.util
import json
import re

import pytest

from arabizi_eval import pairs as P

spec = importlib.util.spec_from_file_location("fetch_models", P.ROOT / "scripts" / "fetch_models.py")
fetch_models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch_models)


def test_manifest_entries_are_complete_and_pinned():
    entries = fetch_models.load_manifest()
    assert len({e["id"] for e in entries}) == len(entries)
    for e in entries:
        assert re.fullmatch(r"[0-9a-f]{64}", e["sha256"]), e["id"]
        assert e["file"].endswith(".gguf") and e["size"] > 100_000_000
        assert e["licence"] and e["licence_acceptance"] in (None, "gemma", "llama")
        assert "3B" not in e["params"] or not e["id"].startswith("qwen2.5")  # never Qwen2.5-3B (v1 D2)
        if "repo" in e:  # base model from Hugging Face
            assert re.fullmatch(r"[0-9a-f]{40}", e["revision"]), e["id"]  # a commit, not a branch
            assert fetch_models.url_for(e).endswith(f"/resolve/{e['revision']}/{e['file']}")


def test_fine_tuned_entries_point_to_their_run_and_prompt():
    entries = fetch_models.load_manifest()
    base_ids = {e["id"] for e in entries if "repo" in e}
    for e in [e for e in entries if "repo" not in e]:
        run = json.loads((P.ROOT / e["run"]).read_text(encoding="utf-8"))  # committed in train/runs/
        assert e["base"] in base_ids and run["base"] == e["base"]
        assert e["prompt"] == run["prompt"] and e["prompt"]["prefix"] and e["prompt"]["suffix"]


def test_plan_needs_explicit_licence_acceptance():
    entries = fetch_models.load_manifest()
    chosen, skipped = fetch_models.plan(entries, [], set())
    assert {e["id"] for e in chosen} == {"qwen2.5-0.5b", "qwen2.5-1.5b", "qwen3-0.6b", "qwen3-1.7b"}
    fine_tuned = sum("repo" not in e for e in entries)
    assert len(skipped) == 2 + fine_tuned
    chosen, skipped = fetch_models.plan(entries, [], {"gemma", "llama"})
    assert len(chosen) == 6 and len(skipped) == fine_tuned and all("fine-tuned" in s for s in skipped)
    chosen, _ = fetch_models.plan(entries, ["qwen3-0.6b"], set())
    assert [e["id"] for e in chosen] == ["qwen3-0.6b"]
    with pytest.raises(SystemExit):
        fetch_models.plan(entries, ["no-such-model"], set())


def test_fetch_skips_a_file_that_is_already_verified(tmp_path):
    content = b"pretend gguf"
    (tmp_path / "x.gguf").write_bytes(content)
    entry = {"id": "x", "file": "x.gguf", "sha256": hashlib.sha256(content).hexdigest(), "size": len(content),
             "repo": "r/x", "revision": "0" * 40}
    assert fetch_models.fetch(entry, tmp_path) == "already present"  # no network needed
