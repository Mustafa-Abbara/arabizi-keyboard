"""Systems the harness can run. Each takes Arabizi text and returns Arabic text.

P3 adds B0 (rules) and B1 (base models through llama.cpp); P4 the fine-tuned model; P5 the Swift engine
through arabizi-cli. Two sanity systems prove the scoring itself: `identity` must score near 0 and
`reference` must score 1.0.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field


@dataclass
class System:
    name: str
    describe: dict = field(default_factory=dict)  # recorded in metrics.json (model, quantisation, prompt version…)

    def start(self) -> None:
        """Load whatever the system needs (a model server); called once before the first sentence."""

    def close(self) -> None:
        """Release resources and record measurements in `describe`; called after the last sentence."""

    def convert(self, row: dict) -> str:
        raise NotImplementedError


class Identity(System):
    """Returns the Arabizi unchanged: a floor that only scores on kept Latin words and numbers."""

    def convert(self, row: dict) -> str:
        return row["arabizi"]


class Reference(System):
    """Returns the primary reference (an oracle): must score 1.0 on every metric."""

    def convert(self, row: dict) -> str:
        return row["arabic"]


class B0(System):
    """Rule baseline: clitics, keep-Latin list, dictionary from the training split, letter rules (b0.py)."""

    def __init__(self) -> None:
        from arabizi_eval import b0

        self.converter = b0.RuleConverter()
        lexicon = b0.load_lexicon()
        super().__init__("b0", {
            "kind": "rules", "rules_version": self.converter.rules["version"],
            "lexicon_words": len(lexicon["words"]), "lexicon_keep_latin": len(lexicon["keep_latin"]),
            "lexicon_built_from": lexicon.get("built_from", {}),
        })

    def convert(self, row: dict) -> str:
        return self.converter.convert(row["arabizi"])


class B1(System):
    """A base model without fine-tuning, through llama-server (llm.py). Name: b1:<model id>:<shots>."""

    def __init__(self, model_id: str, shots: int) -> None:
        from arabizi_eval import llm

        self.llm = llm
        entry = llm.manifest_entry(model_id)
        self.examples = llm.few_shot_examples()[:shots]
        self.server = llm.LlamaServer(llm.MODELS_DIR / entry["file"])
        super().__init__(f"b1-{model_id}-{shots}shot", {
            "kind": "base model (no fine-tuning)", "model": model_id, "file": entry["file"],
            "sha256": entry["sha256"], "params": entry["params"], "quant": entry["quant"],
            "licence": entry["licence"], "shots": shots, "few_shot_ids": [e["id"] for e in self.examples],
            "prompt_version": llm.PROMPT_VERSION, "temperature": 0, "runtime": llm.llama_version(),
        })

    def start(self) -> None:
        self.server.start()
        warm_up = self.llm.build_messages("kifak?", self.examples)
        self.server.chat(warm_up, 16)  # the first request is slower; keep it out of the latency numbers

    def convert(self, row: dict) -> str:
        words = len(row["arabizi"].split())
        reply, _ = self.server.chat(self.llm.build_messages(row["arabizi"], self.examples), 4 * words + 16)
        return self.llm.clean_output(reply)

    def close(self) -> None:
        self.describe["load_seconds"] = round(self.server.load_seconds, 2)
        self.describe["peak_rss_mb"] = round(self.server.peak_rss_mb, 1)
        self.server.stop()


REGISTRY: dict[str, Callable[[], System]] = {
    "b0": B0,
    "identity": lambda: Identity("identity", {"kind": "sanity", "note": "input returned unchanged"}),
    "reference": lambda: Reference("reference", {"kind": "sanity", "note": "oracle: returns the reference"}),
}


def get(name: str) -> System:
    if name.startswith("b1:"):  # b1:<model id>:<shots>, e.g. b1:qwen2.5-0.5b:5
        _, model_id, shots = name.split(":")
        return B1(model_id, int(shots))
    if name not in REGISTRY:
        raise KeyError(f"unknown system {name!r}; available: {', '.join(sorted(REGISTRY))}")
    return REGISTRY[name]()
