"""Run and score systems on a split (roadmap P3).

  uv run --project eval evalrun run --system identity --split dev
  uv run --project eval evalrun score predictions.jsonl --split dev --name qwen-0.5b-kaggle
  uv run --project eval evalrun compare eval/results/RUN_A eval/results/RUN_B

Tune on dev; the test split needs --final and should be run once per final candidate (roadmap §4).
Each run writes eval/results/<run_id>/predictions.jsonl (per sentence: output + scores) and metrics.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from arabizi_eval import bootstrap, metrics, systems
from arabizi_eval import pairs as P

RESULTS_DIR = P.ROOT / "eval" / "results"
PRIVATE_RESULTS_DIR = RESULTS_DIR / "private"  # .gitignore: runs that include private rows (ADR 0014)


def split_rows(split: str, limit: int | None = None, subset: str = "all") -> tuple[list[dict], str]:
    """Rows of a split (public, private or all) and the SHA-256 of the files they came from."""
    digest = hashlib.sha256()
    rows: list[dict] = []
    for path in P.pair_files():
        if (subset == "public" and P.is_private(path)) or (subset == "private" and not P.is_private(path)):
            continue
        lines = [row for _, row, err in P.read_jsonl(path) if not err and row.get("split") == split]
        if lines:
            digest.update(path.read_bytes())
            rows += lines
    return (rows[:limit] if limit else rows), digest.hexdigest()


def git_sha() -> str:
    try:
        out = subprocess.run(["git", "-C", str(P.ROOT), "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, check=True)
        dirty = subprocess.run(["git", "-C", str(P.ROOT), "status", "--porcelain", "--", "eval", "data"],
                               capture_output=True, text=True).stdout.strip()
        return out.stdout.strip() + ("-dirty" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def score_outputs(rows: list[dict], outputs: dict[str, dict]) -> tuple[list[dict], dict]:
    """Score `outputs` ({id: {"prediction": str, "latency_ms": float?}}) for every row."""
    records, scores = [], []
    for row in rows:
        result = outputs.get(row["id"])
        if result is None:
            raise ValueError(f"no prediction for {row['id']}")
        score = metrics.score_sentence(row, result["prediction"], result.get("latency_ms"))
        scores.append(score)
        records.append({"id": row["id"], "arabizi": row["arabizi"], "reference": row["arabic"],
                        "prediction": result["prediction"], **metrics.to_dict(score)})
    summary = metrics.aggregate(scores)
    if scores:
        _, low, high = bootstrap.ratio_ci([s.words_correct for s in scores], [s.words_total for s in scores])
        summary["word_accuracy_ci95"] = [low, high]
    return records, summary


def write_run(name: str, split: str, rows: list[dict], data_sha: str, records: list[dict], summary: dict,
              describe: dict, results_dir: Path | None = None, subset: str = "all") -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    sha = git_sha()
    private_ids = {r["id"] for path in P.pair_files() if P.is_private(path) for _, r, e in P.read_jsonl(path) if not e}
    has_private = any(r["id"] in private_ids for r in rows)
    default_dir = PRIVATE_RESULTS_DIR if has_private else RESULTS_DIR
    suffix = "" if subset == "all" else f"-{subset}"
    run_dir = (results_dir or default_dir) / f"{stamp}-{name}-{split}{suffix}"
    run_dir.mkdir(parents=True, exist_ok=False)
    with (run_dir / "predictions.jsonl").open("w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    meta = {"run_id": run_dir.name, "system": name, "describe": describe, "split": split, "subset": subset,
            "private_sentences": sum(r["id"] in private_ids for r in rows), "sentences": len(rows),
            "data_sha256": data_sha, "git_sha": sha, "created": datetime.now().isoformat(timespec="seconds"),
            "metrics": summary}
    (run_dir / "metrics.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return run_dir


def print_summary(run_dir: Path, summary: dict) -> None:
    def fmt(value):
        return "—" if value is None else (f"{value:.3f}" if isinstance(value, float) else str(value))
    print(f"\n{run_dir.relative_to(P.ROOT) if run_dir.is_relative_to(P.ROOT) else run_dir}")
    for key, value in summary.items():
        shown = "[" + ", ".join(fmt(v) for v in value) + "]" if isinstance(value, list) else fmt(value)
        print(f"  {key:24} {shown}")


def guard_split(split: str, final: bool) -> None:
    if split == "test" and not final:
        sys.exit("The test split is for final results only: tune on dev, then rerun with --final (roadmap §4).")


def cmd_run(args: argparse.Namespace) -> int:
    guard_split(args.split, args.final)
    rows, data_sha = split_rows(args.split, args.limit, args.subset)
    if not rows:
        print(f"No rows in the {args.split} split yet (write them with `pairs add`).")
        return 1
    system = systems.get(args.system)
    outputs = {}
    for row in rows:
        start = time.perf_counter()
        prediction = system.convert(row)
        outputs[row["id"]] = {"prediction": prediction, "latency_ms": (time.perf_counter() - start) * 1000}
    records, summary = score_outputs(rows, outputs)
    run_dir = write_run(system.name, args.split, rows, data_sha, records, summary, system.describe, args.results,
                        args.subset)
    print_summary(run_dir, summary)
    return 0


def cmd_score(args: argparse.Namespace) -> int:
    """Score predictions made elsewhere (e.g. a Kaggle notebook): JSONL with id, prediction, latency_ms?."""
    guard_split(args.split, args.final)
    rows, data_sha = split_rows(args.split, args.limit, args.subset)
    outputs = {r["id"]: r for _, r, err in P.read_jsonl(Path(args.predictions)) if not err}
    records, summary = score_outputs(rows, outputs)
    describe = {"kind": "external", "predictions_file": Path(args.predictions).name}
    run_dir = write_run(args.name, args.split, rows, data_sha, records, summary, describe, args.results, args.subset)
    print_summary(run_dir, summary)
    return 0


def load_run(run_dir: Path) -> tuple[dict, dict[str, dict]]:
    meta = json.loads((run_dir / "metrics.json").read_text(encoding="utf-8"))
    records = {r["id"]: r for _, r, err in P.read_jsonl(run_dir / "predictions.jsonl") if not err}
    return meta, records


def cmd_compare(args: argparse.Namespace) -> int:
    (meta_a, a), (meta_b, b) = load_run(Path(args.run_a)), load_run(Path(args.run_b))
    if meta_a["split"] != meta_b["split"] or meta_a["data_sha256"] != meta_b["data_sha256"]:
        print("Warning: the runs used different data (split or data version); the comparison is not paired.")
    ids = sorted(a.keys() & b.keys())
    if not ids:
        print("No sentences in common.")
        return 1
    rows = lambda run, key: [run[i][key] for i in ids]  # noqa: E731
    diff, low, high = bootstrap.paired_difference_ci(
        (rows(a, "words_correct"), rows(a, "words_total")), (rows(b, "words_correct"), rows(b, "words_total")))
    verdict = "A is better" if low > 0 else "B is better" if high < 0 else "no clear difference (CI contains 0)"
    print(f"A = {meta_a['run_id']}\nB = {meta_b['run_id']}\n{len(ids)} sentences in common")
    print(f"word accuracy A - B = {diff:+.3f}, 95% CI [{low:+.3f}, {high:+.3f}]: {verdict}")
    return 0


def main(argv: list[str] | None = None) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(prog="evalrun", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, helptext in (("run", "run a system on a split and score it"),
                           ("score", "score a predictions file made elsewhere")):
        p = sub.add_parser(name, help=helptext)
        if name == "run":
            p.add_argument("--system", required=True, help=f"one of: {', '.join(sorted(systems.REGISTRY))}")
        else:
            p.add_argument("predictions")
            p.add_argument("--name", required=True, help="name for the run, e.g. qwen0.5b-lora-v1")
        p.add_argument("--split", choices=["dev", "test", "train"], default="dev")
        p.add_argument("--final", action="store_true", help="allow the test split (final results only)")
        p.add_argument("--limit", type=int, help="only the first N rows (smoke runs)")
        p.add_argument("--subset", choices=["all", "public", "private"], default="all",
                       help="public rows only give results that can be published; runs with private rows are "
                            "saved under eval/results/private (never committed)")
        p.add_argument("--results", type=Path, help="results folder (default eval/results)")
    compare = sub.add_parser("compare", help="paired bootstrap on word accuracy between two runs")
    compare.add_argument("run_a", type=Path)
    compare.add_argument("run_b", type=Path)
    args = parser.parse_args(argv)
    return {"run": cmd_run, "score": cmd_score, "compare": cmd_compare}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
