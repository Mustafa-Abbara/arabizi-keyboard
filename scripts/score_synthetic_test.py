"""Score a model on the held-out synthetic test set (build/v4_data/synthetic_test.jsonl), and compare two runs.

Runs the real keyboard engine (arabizi-cli, the keyboard's own deadline per message, as `engine-<id>-kb`) on every
held-out row and scores it with the eval harness's metrics, overall and by group (A1, B2, ..., breaker-probe) and kind.

  # score one model (results go to build/v4_eval/<model>/)
  uv run --project eval python scripts/score_synthetic_test.py run arabizi-llama3.2-1b-v3
  # compare two scored runs, paired bootstrap per group and kind
  uv run --project eval python scripts/score_synthetic_test.py compare arabizi-llama3.2-1b-v4 arabizi-llama3.2-1b-v3

On Windows the engine needs llama.dll: the script adds build/llama.cpp/build/bin/Release to PATH when it exists.
"""
import argparse
import collections
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "eval" / "src"))
from arabizi_eval import bootstrap as B
from arabizi_eval import metrics as M

TEST = ROOT / "build" / "v4_data" / "synthetic_test.jsonl"  # --test overrides
OUT = ROOT / "build" / "v4_eval"  # --out overrides


def rows():
    return [json.loads(line) for line in TEST.read_text(encoding="utf-8").splitlines() if line.strip()]


def same_text(pred, row):
    return pred["arabizi"] == row["arabizi"] and pred["reference"] == row["arabic"]


def cmd_run(model: str, reuse: list[Path]) -> None:
    from arabizi_eval import engine

    dll = ROOT / "build" / "llama.cpp" / "build" / "bin" / "Release"
    if dll.exists():
        os.environ["PATH"] = str(dll) + os.pathsep + os.environ["PATH"]
    out = OUT / model
    out.mkdir(parents=True, exist_ok=True)
    pred_path = out / "predictions.jsonl"
    data = rows()
    by_id = {r["id"]: r for r in data}
    done = {}
    # earlier predictions count only for rows whose text is unchanged (a cleaned row is scored again)
    for path in [*(d / model / "predictions.jsonl" for d in reuse), pred_path]:
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                r = json.loads(line)
                if r["id"] in by_id and same_text(r, by_id[r["id"]]):
                    done[r["id"]] = {**r, "group": by_id[r["id"]]["group"], "kind": by_id[r["id"]]["kind"]}
    pred_path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in done.values()), encoding="utf-8")
    print(f"{len(done):,} of {len(data):,} rows already scored; scoring {len(data) - len(done):,}", flush=True)
    # "rules": the engine with no model, i.e. the rule-based fallback (the Swift port of B0)
    system = engine.EngineSystem(None if model == "rules" else model, keyboard_deadline=True)
    system.start()
    start = time.time()
    with pred_path.open("a", encoding="utf-8") as f:
        for i, row in enumerate(data, 1):
            if row["id"] in done:
                continue
            pred = system.convert(row)
            s = M.score_sentence(row, pred)
            rec = {"id": row["id"], "group": row["group"], "kind": row["kind"], "arabizi": row["arabizi"],
                   "reference": row["arabic"], "prediction": pred, "words_correct": s.words_correct,
                   "words_total": s.words_total, "words_correct_lenient": s.words_correct_lenient,
                   "words_total_lenient": s.words_total_lenient, "exact": s.exact}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            if i % 250 == 0:
                print(f"{i}/{len(data)} in {time.time() - start:.0f} s", flush=True)
    system.close()
    summarize(model)


def load(model):
    """This model's scored rows that belong to the current test set, with its current text."""
    current = {r["id"]: r for r in rows()}
    path = OUT / model / "predictions.jsonl"
    preds = {r["id"]: r for r in map(json.loads, path.read_text(encoding="utf-8").splitlines())}
    return {i: {**r, "group": current[i]["group"], "kind": current[i]["kind"]}
            for i, r in preds.items() if i in current and same_text(r, current[i])}


def summarize(model: str) -> None:
    preds = list(load(model).values())
    lines = [f"# {model} on the synthetic test set", "",
             f"{len(preds):,} held-out rows. Word accuracy (strict) with 95% bootstrap interval; lenient ignores "
             "hamza, final ة/ه and ى/ي; exact = every word right.", "",
             "| Slice | Rows | Word acc. [95% CI] | Lenient | Exact |", "|---|---|---|---|---|"]

    def line(name, rs):
        est, lo, hi = B.ratio_ci([r["words_correct"] for r in rs], [r["words_total"] for r in rs])
        len_acc = sum(r["words_correct_lenient"] for r in rs) / max(sum(r["words_total_lenient"] for r in rs), 1)
        ex = sum(r["exact"] for r in rs) / len(rs)
        return f"| {name} | {len(rs):,} | {est:.3f} [{lo:.3f}, {hi:.3f}] | {len_acc:.3f} | {ex:.0%} |"

    lines.append(line("**all**", preds))
    for key in ("group", "kind"):
        by = collections.defaultdict(list)
        for r in preds:
            by[r[key]].append(r)
        lines.append(f"| *by {key}* | | | | |")
        lines += [line(k, v) for k, v in sorted(by.items())]
    (OUT / model / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


def cmd_compare(a: str, b: str) -> None:
    pa, pb = load(a), load(b)
    ids = sorted(set(pa) & set(pb))
    lines = [f"# {a} − {b} on the synthetic test set", "",
             f"{len(ids):,} rows scored by both. Paired bootstrap over rows (10,000 resamples); a gain is clear "
             "when its whole interval is above 0.", "",
             "| Slice | Rows | " + a + " | " + b + " | Difference [95% CI] |", "|---|---|---|---|---|"]

    def line(name, sel):
        ra = ([pa[i]["words_correct"] for i in sel], [pa[i]["words_total"] for i in sel])
        rb = ([pb[i]["words_correct"] for i in sel], [pb[i]["words_total"] for i in sel])
        d, lo, hi = B.paired_difference_ci(ra, rb)
        acc = lambda r: sum(r[0]) / max(sum(r[1]), 1)
        return f"| {name} | {len(sel):,} | {acc(ra):.3f} | {acc(rb):.3f} | {d:+.3f} [{lo:+.3f}, {hi:+.3f}] |"

    lines.append(line("**all**", ids))
    for key in ("group", "kind"):
        by = collections.defaultdict(list)
        for i in ids:
            by[pa[i][key]].append(i)
        lines.append(f"| *by {key}* | | | | |")
        lines += [line(k, v) for k, v in sorted(by.items())]
    (OUT / f"compare-{a}-vs-{b}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


def main():
    global TEST, OUT
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--test", type=Path, default=TEST, help="the held-out test file (default: v4's)")
    ap.add_argument("--out", type=Path, default=OUT, help="results folder (default: build/v4_eval)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run")
    run.add_argument("model")
    run.add_argument("--reuse", type=Path, action="append", default=[],
                     help="an earlier results folder whose predictions count for rows with unchanged text")
    c = sub.add_parser("compare")
    c.add_argument("a")
    c.add_argument("b")
    sub.add_parser("summary").add_argument("model")
    args = ap.parse_args()
    TEST, OUT = args.test, args.out
    if args.cmd == "run":
        cmd_run(args.model, args.reuse)
    elif args.cmd == "compare":
        cmd_compare(args.a, args.b)
    else:
        summarize(args.model)


if __name__ == "__main__":
    main()
