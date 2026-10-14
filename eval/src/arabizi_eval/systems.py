"""Systems the harness can run. Each takes Arabizi text and returns Arabic text.

P3 adds B0 (rules) and B1 (base models through llama.cpp); P4 the fine-tuned model; P5 the Swift engine
through arabizi-cli. Two sanity systems prove the scoring itself: `identity` must score near 0 and
`reference` must score 1.0.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass, field
from functools import partial
from pathlib import Path

from arabizi_eval import pairs as P


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


MODELS_MANIFEST = P.ROOT / "config" / "models.json"


def _b1(model_id: str, shots: str) -> System:
    from arabizi_eval import b1  # imported on use: b1 subclasses System

    return b1.B1(model_id, shots)


def b1_systems(manifest: Path = MODELS_MANIFEST) -> dict[str, Callable[[], System]]:
    """B1 (b1.py): b1-<model id>-zero and b1-<model id>-5shot for every model pinned in config/models.json."""
    models = json.loads(manifest.read_text(encoding="utf-8"))["models"]
    return {f"b1-{m['id']}-{shots}": partial(_b1, m["id"], shots) for m in models for shots in ("zero", "5shot")}


REGISTRY: dict[str, Callable[[], System]] = {
    "b0": B0,
    "identity": lambda: Identity("identity", {"kind": "sanity", "note": "input returned unchanged"}),
    "reference": lambda: Reference("reference", {"kind": "sanity", "note": "oracle: returns the reference"}),
    **b1_systems(),
}


def get(name: str) -> System:
    if name not in REGISTRY:
        raise KeyError(f"unknown system {name!r}; available: {', '.join(sorted(REGISTRY))}")
    return REGISTRY[name]()
