"""B1 plumbing (llm.py): prompts, output cleaning, few-shot guard, system names. No model or server needed."""

import pytest

from arabizi_eval import llm, systems


def test_few_shot_examples_are_public_training_rows():
    examples = llm.few_shot_examples()
    assert [e["id"] for e in examples] == list(llm.FEW_SHOT_IDS)
    assert all(e["split"] == "train" for e in examples)


def test_few_shot_examples_refuse_missing_or_held_out_ids():
    with pytest.raises(ValueError):
        llm.few_shot_examples(("ai-9999",))
    with pytest.raises(ValueError):
        llm.few_shot_examples(("hw-0001",))  # a public dev/test row


def test_messages_put_examples_as_turns_before_the_input():
    examples = [{"arabizi": "shu", "arabic": "شو"}]
    messages = llm.build_messages("kifak?", examples)
    assert [m["role"] for m in messages] == ["system", "user", "assistant", "user"]
    assert messages[-1]["content"] == "kifak?" and messages[2]["content"] == "شو"
    assert len(llm.build_messages("kifak?", [])) == 2


@pytest.mark.parametrize(("raw", "clean"), [
    ("كيفك؟", "كيفك؟"),
    ("<think>\nhmm\n</think>\n\nكيفك؟", "كيفك؟"),
    ("\n\n«كيفك؟»\nExplanation: ...", "كيفك؟"),
    ("", ""),
])
def test_clean_output(raw, clean):
    assert llm.clean_output(raw) == clean


def test_b1_system_names_are_parsed_and_described():
    system = systems.get("b1:qwen2.5-0.5b:5")
    assert system.name == "b1-qwen2.5-0.5b-5shot"
    assert system.describe["shots"] == 5 and len(system.describe["few_shot_ids"]) == 5
    assert system.describe["sha256"] == llm.manifest_entry("qwen2.5-0.5b")["sha256"]
    assert systems.get("b1:qwen3-0.6b:0").examples == []
    with pytest.raises(KeyError):
        systems.get("b1:no-such-model:0")


def test_server_start_explains_a_missing_model(tmp_path):
    server = llm.LlamaServer(tmp_path / "missing.gguf")
    with pytest.raises(RuntimeError, match="fetch_models|llama-server"):
        server.start()
