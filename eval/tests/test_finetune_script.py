"""train/finetune_lora.py without a GPU: pinned bases, data loading, prompt rendering (heavy imports stay lazy)."""

import importlib.util
import json
import re

import pytest

from arabizi_eval import pairs as P

spec = importlib.util.spec_from_file_location("finetune_lora", P.ROOT / "train" / "finetune_lora.py")
finetune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finetune)


def test_bases_are_the_adr_0004_models_pinned_to_commits():
    manifest_ids = {m["id"] for m in json.loads((P.ROOT / "config" / "models.json").read_text())["models"]}
    assert set(finetune.BASES) <= manifest_ids
    assert {"llama3.2-1b", "qwen3-1.7b"} <= set(finetune.BASES)  # ADR 0004
    for repo, revision in finetune.BASES.values():
        assert "/" in repo and re.fullmatch(r"[0-9a-f]{40}", revision)


def test_load_examples_reads_public_and_private_files(tmp_path):
    for name, ids in (("train-public", ["ai-0001"]), ("train-private", ["hw-0100", "rv-0002"]), ("val-public", ["x"])):
        (tmp_path / f"{name}.jsonl").write_text("".join(json.dumps({"id": i}) + "\n" for i in ids))
    assert [e["id"] for e in finetune.load_examples(tmp_path, "train")] == ["hw-0100", "rv-0002", "ai-0001"]
    with pytest.raises(SystemExit):
        finetune.load_examples(tmp_path / "missing", "train")


class FakeTokenizer:
    eos_token = "<|im_end|>"

    def apply_chat_template(self, messages, tokenize, add_generation_prompt, enable_thinking):
        assert tokenize is False and add_generation_prompt is True and enable_thinking is False
        body = "".join(f"<|{m['role']}|>{m['content']}" for m in messages)
        return body + "<|assistant|><think>\n\n</think>\n\n"


def test_render_matches_the_run_time_prompt_and_trains_on_the_answer_only():
    messages = [{"role": "system", "content": "Convert."}, {"role": "user", "content": "shu"},
                {"role": "assistant", "content": "شو"}]
    rendered = finetune.render(FakeTokenizer(), messages)
    assert "شو" not in rendered["prompt"] and rendered["prompt"].endswith("</think>\n\n")
    assert rendered["completion"] == "شو<|im_end|>"


def test_arguments_and_defaults():
    args = finetune.parse_args(["--base", "qwen3-1.7b", "--data", "d", "--out", "o"])
    assert (args.rank, args.alpha, args.lr, args.epochs, args.max_length) == (16, 32, 2e-4, 3, 256)
    with pytest.raises(SystemExit):
        finetune.parse_args(["--base", "gemma3-1b", "--data", "d", "--out", "o"])  # dropped in ADR 0004
