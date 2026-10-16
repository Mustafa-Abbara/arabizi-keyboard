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


def example(arabizi, arabic, system="Convert."):
    return {"messages": [{"role": "system", "content": system}, {"role": "user", "content": arabizi},
                         {"role": "assistant", "content": arabic}]}


class DatedTokenizer(FakeTokenizer):
    """Like Llama 3.2: the template writes the date into the system header."""

    def apply_chat_template(self, messages, **kwargs):
        return "<|date|>16 Oct 2026" + super().apply_chat_template(messages, **kwargs)


class TrimmingTokenizer(FakeTokenizer):
    """A template that changes the user text (strips it), so prefix + Arabizi + suffix is not the real prompt."""

    def apply_chat_template(self, messages, **kwargs):
        return super().apply_chat_template([m | {"content": m["content"].strip()} for m in messages], **kwargs)


def test_prompt_template_is_exactly_the_training_prompt_around_the_arabizi():
    examples = [example("kifak?", "كيفك؟"), example("shu 3am ta3mel", "شو عم تعمل")]
    for tokenizer in (FakeTokenizer(), DatedTokenizer()):
        template = finetune.prompt_template(tokenizer, examples)
        for e in examples:
            assert template["prefix"] + e["messages"][1]["content"] + template["suffix"] == \
                finetune.render(tokenizer, e["messages"])["prompt"]
        assert template["suffix"].endswith("</think>\n\n") and finetune.PROMPT_MARKER not in str(template)
    assert finetune.prompt_template(DatedTokenizer(), examples)["prefix"].startswith("<|date|>16 Oct 2026")


def test_prompt_template_refuses_what_the_engine_could_not_reproduce():
    with pytest.raises(SystemExit, match="differs"):
        finetune.prompt_template(TrimmingTokenizer(), [example(" kifak ", "كيفك")])
    with pytest.raises(SystemExit, match="system prompts"):
        finetune.prompt_template(FakeTokenizer(), [example("a", "ا"), example("b", "ب", system="Other.")])


def test_warmup_is_a_whole_number_of_steps():
    # 7957 examples, effective batch 32, 3 epochs: 249 steps per epoch, 747 in all; 3% is 22 steps.
    assert finetune.warmup_steps(7957, 8, 4, 3, 0.03) == 22
    assert finetune.warmup_steps(200, 8, 4, 1, 0.03) == 1  # smoke run: at least one step
    assert finetune.parse_args(["--base", "qwen3-1.7b", "--data", "d", "--out", "o"]).warmup == 0.03
    assert "warmup_ratio=" not in (P.ROOT / "train" / "finetune_lora.py").read_text()  # removed in transformers 5


def test_unused_packages_look_uninstalled(monkeypatch):
    import importlib.util
    import sys

    monkeypatch.delitem(sys.modules, "torchao", raising=False)
    finetune.hide_unused_packages()
    try:
        assert importlib.util.find_spec("torchao") is None  # what peft and transformers check
    finally:
        sys.modules.pop("torchao", None)


def test_bf16_only_where_the_gpu_does_it_natively():
    assert finetune.use_bf16((7, 5)) is False  # Kaggle T4: fp16 (emulated bf16 breaks TRL's loss kernel)
    assert finetune.use_bf16((6, 0)) is False  # P100
    assert finetune.use_bf16((8, 0)) is True and finetune.use_bf16((8, 9)) is True  # A100, L4
    assert "is_bf16_supported" not in (P.ROOT / "train" / "finetune_lora.py").read_text().split("def main")[1]
