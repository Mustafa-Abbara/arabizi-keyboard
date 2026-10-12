"""Write, check and count Arabizi pairs.

  uv run --project eval pairs add      # type new hand-written pairs
  uv run --project eval pairs check    # delayed self-check of rows written >= 24 h ago
  uv run --project eval pairs stats    # counts and progress towards the P2 targets
  uv run --project eval pairs validate # same checks as the test suite
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

from arabizi_eval import pairs as P

WRITER = "moustafa"
CHECKER = "moustafa-delayed"
DEV_SLOTS = {2, 5, 8}  # of every 10 hand-written held-out rows, 3 go to dev: 70/30 (roadmap P2 step 3)
TARGETS = {"held_out": 300, "held_out_goal": 350, "train": 2000, "train_hand_or_public": 400}  # ADR 0011
SMALL_WORDS = re.compile(r"(?<![a-z0-9])(la|ma|3a|3al|w|b|bi|bel|bil)(?![a-z0-9])", re.IGNORECASE)


def path_for(split: str, method: str = "hand") -> Path:
    return P.PAIRS_DIR / (f"{split}.jsonl" if split in ("test", "dev") else f"train-{method}.jsonl")


def all_rows() -> list[dict]:
    return [row for path in P.pair_files() for _, row, err in P.read_jsonl(path) if not err]


def next_id(method: str, rows: list[dict]) -> str:
    prefix = P.ID_PREFIX[method]
    numbers = [int(r["id"].split("-")[1]) for r in rows if r.get("id", "").startswith(prefix + "-")]
    return f"{prefix}-{max(numbers, default=0) + 1:04d}"


def default_split(rows: list[dict]) -> str:
    """Held-out rows until the test set is frozen, then train."""
    if P.MANIFEST_PATH.exists():
        return "train"
    held_out = sum(r.get("split") in ("test", "dev") for r in rows)
    return "dev" if held_out % 10 in DEV_SLOTS else "test"


def parse_accepted(text: str) -> dict[str, list[str]]:
    """'هلق=هلأ; إمتى=إيمتى|إمتا' -> {'هلق': ['هلأ'], 'إمتى': ['إيمتى', 'إمتا']}"""
    accepted: dict[str, list[str]] = {}
    for part in filter(None, (p.strip() for p in text.split(";"))):
        primary, _, variants = part.partition("=")
        if primary.strip() and variants.strip():
            accepted[primary.strip()] = [v.strip() for v in variants.split("|") if v.strip()]
    return accepted


def append(path: Path, row: dict) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def rewrite(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def ask(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except EOFError:
        return "q"


def cmd_add(args: argparse.Namespace) -> int:
    print("New pairs. Empty Arabizi or 'q' to stop. Spelling rules: docs/SPELLING.md")
    added = 0
    while True:
        rows = all_rows()
        split = args.split or default_split(rows)
        arabizi = ask(f"\n[{split}] Arabizi: ")
        if arabizi in ("", "q"):
            break
        arabic = ask("Arabic:  ")
        if arabic in ("", "q"):
            break
        accepted = parse_accepted(ask("Accepted variants (primary=variant; ... or Enter): "))
        row = {"id": next_id("hand", rows), "arabizi": arabizi, "arabic": arabic, "accepted": accepted,
               "method": "hand", "writer": WRITER, "checked_by": None, "source": "hand-written",
               "split": split, "date": date.today().isoformat()}
        errors, warnings = P.row_errors(row, split, "hand"), P.row_warnings(row)
        for message in errors:
            print(f"  ERROR: {message}")
        for message in warnings:
            print(f"  warning: {message}")
        if errors:
            print("  Not saved. Type the pair again.")
            continue
        duplicate = _duplicate_of(row, rows)
        if duplicate:
            print(f"  Not saved: same sentence as {duplicate}.")
            continue
        if warnings and ask("  Save anyway? [y/N] ").lower() != "y":
            continue
        append(path_for(split), row)
        added += 1
        print(f"  saved {row['id']} -> {path_for(split).name}")
    print(f"\n{added} pair(s) added.")
    return 0


def _duplicate_of(row: dict, rows: list[dict]) -> str | None:
    keys = P._dedupe_keys(row)
    for other in rows:
        if keys & P._dedupe_keys(other):
            return other["id"]
    return None


def cmd_check(args: argparse.Namespace) -> int:
    """Delayed self-check (ADR 0011) of unchecked rows.

    Rows only carry a date, so "at least N days" means written before the date N days ago: with --days 1, a row
    from yesterday waits until tomorrow, which guarantees >= 24 hours whatever time it was written.
    """
    cutoff = date.today() - timedelta(days=args.days)
    print(f"Self-check of rows written before {cutoff}. Re-read docs/SPELLING.md first.")
    print("Enter = correct, e = edit Arabic, a = edit accepted, s = skip, q = quit\n")
    checked = 0
    for path in P.pair_files():
        lines = P.read_jsonl(path)
        if any(err for _, _, err in lines):
            print(f"Skipping {path.name}: it has broken lines. Run `pairs validate` and fix them first.")
            continue
        rows = [row for _, row, _ in lines]
        changed = False
        for row in rows:
            if row.get("checked_by") or date.fromisoformat(row["date"]) >= cutoff:
                continue
            print(f"{row['id']}  {row['arabizi']}\n         {row['arabic']}  {row['accepted'] or ''}")
            answer = ask("  > ").lower()
            if answer == "q":
                if changed:
                    rewrite(path, rows)
                print(f"\n{checked} row(s) checked.")
                return 0
            if answer == "s":
                continue
            original = dict(row)
            if answer == "e":
                row["arabic"] = ask("  Arabic: ") or row["arabic"]
            if answer == "a":
                row["accepted"] = parse_accepted(ask("  Accepted (primary=variant; ...): "))
            errors = P.row_errors(row)
            if errors:
                print("  Not marked as checked, edit discarded: " + "; ".join(errors))
                row.clear()
                row.update(original)
                continue
            row["checked_by"] = CHECKER
            changed = True
            checked += 1
        if changed:
            rewrite(path, rows)
    print(f"\n{checked} row(s) checked.")
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    rows = all_rows()
    by_split = Counter(r["split"] for r in rows)
    by_method = Counter((r["split"], r["method"]) for r in rows)
    held_out = [r for r in rows if r["split"] in ("test", "dev")]
    train = [r for r in rows if r["split"] == "train"]
    unchecked = sum(not r["checked_by"] for r in rows)
    today = sum(r["date"] == date.today().isoformat() for r in rows)

    print(f"Rows: {len(rows)}  (test {by_split['test']}, dev {by_split['dev']}, train {by_split['train']})")
    for (split, method), n in sorted(by_method.items()):
        print(f"  {split:5} {method:12} {n}")
    print(f"Unchecked: {unchecked}   Written today: {today}")
    print(f"Held-out: {len(held_out)} / {TARGETS['held_out']} (goal {TARGETS['held_out_goal']})")
    hand_train = sum(r["method"] in ("hand", "public") for r in train)
    print(f"Train: {len(train)} / {TARGETS['train']}  (hand or public: {hand_train} / "
          f"{TARGETS['train_hand_or_public']})")
    if held_out:
        share = lambda pred: f"{100 * sum(map(pred, held_out)) // len(held_out)}%"  # noqa: E731
        print("Held-out coverage (SPELLING.md 11):")
        print(f"  Latin words kept      {share(lambda r: re.search('[A-Za-z]', r['arabic']) is not None)}"
              "  (aim ~1/3 with Latin, names or numbers)")
        print(f"  numbers               {share(lambda r: bool(P.NUMBER.search(r['arabizi'])))}")
        print(f"  hard small words      {share(lambda r: bool(SMALL_WORDS.search(r['arabizi'])))}  (aim ~1/5)")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    report = P.validate()
    for problem in report.errors:
        print(f"{problem.where}: {problem.message}")
    print(f"{len(report.rows)} rows, {len(report.errors)} problem(s).")
    return 0 if report.ok else 1


def main(argv: list[str] | None = None) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(prog="pairs", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    add = sub.add_parser("add", help="type new hand-written pairs")
    add.add_argument("--split", choices=["test", "dev", "train"], help="override the automatic split")
    check = sub.add_parser("check", help="delayed self-check")
    check.add_argument("--days", type=int, default=1,
                       help="only rows written before the date this many days ago (default 1: >= 24 h)")
    sub.add_parser("stats", help="counts and progress")
    sub.add_parser("validate", help="run all checks")
    args = parser.parse_args(argv)
    return {"add": cmd_add, "check": cmd_check, "stats": cmd_stats, "validate": cmd_validate}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
