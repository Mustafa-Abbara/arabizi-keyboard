"""Build the fine-tuning files for Kaggle (roadmap P4, ADR 0015).

Only training rows leave this Mac: dev and test never do. Each row becomes a chat with the same instruction as B1
and the keyboard (`b1.SYSTEM_PROMPT`): system instruction, the Arabizi as the user turn, the Arabic as the answer.

The ADR 0010 cap (AI-derived rows at most half of the training set) is met by keeping only `ai_variants` spelling
variants per AI-drafted row; human rows keep all their variants. 5% of sentence groups (a row and its variants)
are held back for the validation loss, so no variant of a validation sentence is trained on.
"""

from __future__ import annotations

import hashlib
import json
import random
from collections import Counter
from pathlib import Path

from arabizi_eval import pairs as P
from arabizi_eval.b1 import PROMPT_VERSION, SYSTEM_PROMPT

EXPORT_DIR = P.ROOT / "build" / "train-export"


def training_rows(include_private: bool = True) -> list[tuple[dict, bool]]:
    """(row, private) for every training row, public and (optionally) private."""
    out = []
    for path in P.pair_files(include_private=include_private):
        private = P.is_private(path)
        out += [(row, private) for _, row, err in P.read_jsonl(path) if not err and row.get("split") == "train"]
    return out


def origin(row: dict, by_id: dict[str, dict]) -> str:
    """'ai' or 'human': where the sentence comes from (a variant inherits its parent's origin)."""
    source = by_id.get(row.get("parent"), row) if row["method"] == "rule_variant" else row
    return "ai" if source["method"] == "ai_checked" else "human"


def select(rows: list[tuple[dict, bool]], ai_variants: int) -> list[tuple[dict, bool]]:
    """Keep every non-variant row, all variants of human rows, and the first `ai_variants` variants per AI row."""
    by_id = {row["id"]: row for row, _ in rows}
    kept, per_parent = [], Counter()
    for row, private in rows:
        if row["method"] == "rule_variant" and origin(row, by_id) == "ai":
            if per_parent[row["parent"]] >= ai_variants:
                continue
            per_parent[row["parent"]] += 1
        kept.append((row, private))
    return kept


def to_example(row: dict) -> dict:
    return {"id": row["id"], "group": row.get("parent") or row["id"],
            "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                         {"role": "user", "content": row["arabizi"]},
                         {"role": "assistant", "content": row["arabic"]}]}


def export(out_dir: Path = EXPORT_DIR, ai_variants: int = 1, val_share: float = 0.05, seed: int = 2026,
           include_private: bool = True) -> dict:
    rows = training_rows(include_private)
    if any(row["split"] != "train" for row, _ in rows):
        raise ValueError("only training rows may be exported")
    by_id = {row["id"]: row for row, _ in rows}
    kept = select(rows, ai_variants)
    groups = sorted({row.get("parent") or row["id"] for row, _ in kept})
    val_groups = set(random.Random(seed).sample(groups, round(len(groups) * val_share)))

    out_dir.mkdir(parents=True, exist_ok=True)
    files = {(split, private): [] for split in ("train", "val") for private in (False, True)}
    for row, private in kept:
        split = "val" if (row.get("parent") or row["id"]) in val_groups else "train"
        files[(split, private)].append(to_example(row))
    written = {}
    for (split, private), examples in files.items():
        if private and not include_private:
            continue
        name = f"{split}-{'private' if private else 'public'}.jsonl"
        text = "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in examples)
        (out_dir / name).write_text(text, encoding="utf-8")
        written[name] = {"rows": len(examples), "sha256": hashlib.sha256(text.encode()).hexdigest()}

    origins = Counter(origin(row, by_id) for row, _ in kept)
    summary = {
        "_comment": "Written by `pairs export-train`. Training rows only (never dev/test). Upload this folder as a "
                    "PRIVATE Kaggle dataset (ADR 0014, ADR 0015).",
        "prompt_version": PROMPT_VERSION, "system_prompt": SYSTEM_PROMPT, "seed": seed,
        "ai_variants_per_row": ai_variants, "val_share": val_share,
        "rows_total": len(kept), "rows_ai_derived": origins["ai"], "rows_human": origins["human"],
        "ai_share": round(origins["ai"] / max(len(kept), 1), 3),
        "by_method": dict(Counter(row["method"] for row, _ in kept)),
        "files": written,
    }
    (out_dir / "export.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary
