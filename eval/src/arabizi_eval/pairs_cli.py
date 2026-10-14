"""Write, check and count Arabizi pairs.

  uv run --project eval pairs add      # type new hand-written pairs
  uv run --project eval pairs import F # add a list of hand-written pairs: one 'arabizi | arabic' per line
  uv run --project eval pairs import-batch F --method ai_checked ...  # training rows from another source
  uv run --project eval pairs import-chats F.xlsx --held-out 300  # own chat messages, PRIVATE (ADR 0014)
  uv run --project eval pairs variants # regenerate rule-made spelling variants of the training rows
  uv run --project eval pairs lexicon  # rebuild the B0 word dictionary from the train split
  uv run --project eval pairs check    # delayed self-check of rows written >= 24 h ago
  uv run --project eval pairs stats    # counts and progress towards the P2 targets
  uv run --project eval pairs export-train  # training files for Kaggle (P4, ADR 0015)
  uv run --project eval pairs validate # same checks as the test suite
"""

from __future__ import annotations

import argparse
import json
import random
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


def path_for(split: str, method: str = "hand", private: bool = False) -> Path:
    folder = P.PRIVATE_DIR if private else P.PAIRS_DIR
    return folder / (f"{split}.jsonl" if split in ("test", "dev") else f"train-{method}.jsonl")


def all_rows(include_private: bool = True) -> list[dict]:
    return [row for path in P.pair_files(include_private=include_private)
            for _, row, err in P.read_jsonl(path) if not err]


def private_rows() -> list[dict]:
    return [row for path in P.pair_files() if P.is_private(path) for _, row, err in P.read_jsonl(path) if not err]


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
    """'هلق=هلأ; إمتى=إيمتى|إمتا' -> {'هلق': ['هلأ'], 'إمتى': ['إيمتى', 'إمتا']}

    Raises ValueError for a part that is not 'primary=variant', so a typo is never silently dropped.
    """
    accepted: dict[str, list[str]] = {}
    for part in filter(None, (p.strip() for p in text.split(";"))):
        primary, _, variants = part.partition("=")
        cleaned = [v.strip() for v in variants.split("|") if v.strip()]
        if not primary.strip() or not cleaned:
            raise ValueError(f"cannot read variant {part!r}: write primary=variant, e.g. هلق=هلأ")
        accepted[primary.strip()] = cleaned
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
        try:
            accepted = parse_accepted(ask("Accepted variants (primary=variant; ... or Enter): "))
        except ValueError as exc:
            print(f"  ERROR: {exc}\n  Not saved. Type the pair again.")
            continue
        row = new_hand_row(arabizi, arabic, accepted, split, rows)
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


def new_hand_row(arabizi: str, arabic: str, accepted: dict, split: str, rows: list[dict]) -> dict:
    return {"id": next_id("hand", rows), "arabizi": arabizi, "arabic": arabic, "accepted": accepted,
            "method": "hand", "writer": WRITER, "checked_by": None, "source": "hand-written",
            "split": split, "date": date.today().isoformat()}


def parse_list_line(line: str) -> tuple[str, str, dict] | None:
    """'arabizi | arabic' or 'arabizi | arabic | primary=variant; ...'. None for blank and # comment lines."""
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = [part.strip() for part in line.split(" | ")]
    if len(parts) not in (2, 3) or not parts[0] or not parts[1]:
        raise ValueError("expected 'arabizi | arabic' or 'arabizi | arabic | variants' (with spaces around |)")
    return parts[0], parts[1], parse_accepted(parts[2]) if len(parts) == 3 else {}


def cmd_import(args: argparse.Namespace) -> int:
    """Add hand-written pairs from a list. Rows that break a rule are reported and not saved; nothing is changed."""
    text = sys.stdin.read() if args.file == "-" else Path(args.file).read_text(encoding="utf-8")
    rows = all_rows()
    saved, rejected = [], []
    for n, line in enumerate(text.splitlines(), 1):
        try:
            parsed = parse_list_line(line)
        except ValueError as exc:
            rejected.append((n, line.strip(), [str(exc)]))
            continue
        if parsed is None:
            continue
        split = args.split or default_split(rows)
        row = new_hand_row(*parsed, split, rows)
        problems = P.row_errors(row, split, "hand")
        if not args.allow_warnings:
            problems += [f"{w} (use --allow-warnings to keep it)" for w in P.row_warnings(row)]
        duplicate = _duplicate_of(row, rows)
        if duplicate:
            problems.append(f"same sentence as {duplicate}")
        if problems:
            rejected.append((n, line.strip(), problems))
            continue
        if not args.dry_run:
            append(path_for(split), row)
        rows.append(row)
        saved.append(row)

    for row in saved:
        print(f"{'would save' if args.dry_run else 'saved'} {row['id']} [{row['split']}] {row['arabizi']}")
    for n, line, problems in rejected:
        print(f"\nREJECTED line {n}: {line}")
        for problem in problems:
            print(f"  - {problem}")
    print(f"\n{len(saved)} {'would be ' if args.dry_run else ''}saved, {len(rejected)} rejected.")
    return 1 if rejected else 0


def cmd_import_batch(args: argparse.Namespace) -> int:
    """Add training rows from a JSONL file with at least "arabizi" and "arabic" keys (other keys are ignored).

    The only change made to the text is removing diacritics and tatweel from the Arabic (SPELLING.md 2.3);
    rows that still break a rule or repeat a sentence are reported and not saved.
    """
    rows = all_rows()
    saved, rejected, normalized = [], [], 0
    for n, source_row, error in P.read_jsonl(Path(args.file)):
        if error or not isinstance(source_row.get("arabizi"), str) or not isinstance(source_row.get("arabic"), str):
            rejected.append((n, str(source_row)[:80], [error or "needs string 'arabizi' and 'arabic' keys"]))
            continue
        arabic = " ".join(P.DIACRITICS.sub("", source_row["arabic"]).replace(P.TATWEEL, "").split())
        normalized += arabic != source_row["arabic"].strip()
        row = {"id": next_id(args.method, rows), "arabizi": source_row["arabizi"].strip(), "arabic": arabic,
               "accepted": {}, "method": args.method, "writer": args.writer, "checked_by": args.checked_by,
               "source": args.source, "split": "train", "date": args.date or date.today().isoformat()}
        problems = P.row_errors(row, "train", args.method)
        if not args.allow_warnings:
            problems += [f"{w} (use --allow-warnings to keep it)" for w in P.row_warnings(row)]
        duplicate = _duplicate_of(row, rows)
        if duplicate:
            problems.append(f"same sentence as {duplicate}")
        if problems:
            rejected.append((n, row["arabizi"], problems))
            continue
        if not args.dry_run:
            append(path_for("train", args.method), row)
        rows.append(row)
        saved.append(row)

    for n, line, problems in rejected:
        print(f"REJECTED line {n}: {line}")
        for problem in problems:
            print(f"  - {problem}")
    verb = "would be saved" if args.dry_run else f"saved to {path_for('train', args.method).name}"
    print(f"{len(saved)} {verb} ({normalized} with diacritics/tatweel removed), {len(rejected)} rejected.")
    return 1 if rejected else 0


def cmd_variants(args: argparse.Namespace) -> int:
    """Regenerate the train-rule_variant.jsonl files (public and private) from the other training rows.

    Variants of private rows go to the private folder, so private text never lands in a public file.
    Deterministic for a seed. Examples are only printed from public rows.
    """
    from arabizi_eval import variants

    private_ids = {r["id"] for r in private_rows()}
    parents = [r for r in all_rows() if r.get("split") == "train" and r.get("method") != "rule_variant"]
    used_total: Counter = Counter()
    next_number = 1
    public_rows: list[dict] = []
    for private in (False, True):
        group = [r for r in parents if (r["id"] in private_ids) == private]
        if private and not group:
            continue
        rows, used, short = variants.generate(group, args.per_row, args.seed, first_id=next_number)
        next_number += len(rows)
        used_total.update(used)
        target = path_for("train", "rule_variant", private=private)
        if not args.dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            rewrite(target, rows)
        if not private:
            public_rows = rows
        verb = "would write" if args.dry_run else "wrote"
        print(f"{verb} {len(rows)} variants of {len(group)} {'private' if private else 'public'} training rows to "
              f"{'private/' if private else ''}{target.name} (seed {args.seed}, {args.per_row} per row; "
              f"{short} rows had fewer possible spellings)")
    print("Rules fired: " + ", ".join(f"{name} {n}" for name, n in used_total.most_common()))
    by_id = {r["id"]: r for r in parents}
    for row in random.Random(args.seed).sample(public_rows, min(args.show, len(public_rows))):
        print(f"\n  {by_id[row['parent']]['arabizi']}\n  {row['arabizi']}")
    return 0


def cmd_lexicon(args: argparse.Namespace) -> int:
    """Rebuild data/rules/arabizi_lexicon.json (B0 dictionary) from the PUBLIC train split only.

    The dictionary is committed, so it must not contain words learned from private chats (ADR 0014).
    """
    from arabizi_eval import b0

    train = [r for r in all_rows(include_private=False) if r.get("split") == "train"]
    if not any(r["method"] == "rule_variant" for r in train):
        print("Note: no rule variants found; run `pairs variants` first for a fuller dictionary.")
    lexicon = b0.build_lexicon(train)
    b0.LEXICON_PATH.write_text(json.dumps(lexicon, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    built = lexicon["built_from"]
    print(f"wrote {b0.LEXICON_PATH.name}: {len(lexicon['words'])} words, {len(lexicon['keep_latin'])} kept in Latin, "
          f"from {built['aligned_rows']} of {built['rows']} training rows that line up word for word")
    return 0


def read_sheet(path: Path) -> list[dict]:
    """Rows of an .xlsx (first sheet, header row) or .jsonl file, as dicts keyed by column name."""
    if path.suffix == ".jsonl":
        return [row for _, row, err in P.read_jsonl(path) if not err]
    import openpyxl

    sheet = openpyxl.load_workbook(path, read_only=True, data_only=True).worksheets[0]
    values = [r for r in sheet.iter_rows(values_only=True) if any(c not in (None, "") for c in r)]
    header = [str(c).strip().lower() if c is not None else "" for c in values[0]]
    return [{h: c for h, c in zip(header, r, strict=False) if h} for r in values[1:]]


def held_out_quota(sizes: dict[str, int], total: int) -> dict[str, int]:
    """Share `total` held-out rows between groups in proportion to their size (largest remainders)."""
    count = sum(sizes.values())
    exact = {g: total * n / count for g, n in sizes.items()}
    quota = {g: int(x) for g, x in exact.items()}
    for g in sorted(exact, key=lambda g: exact[g] - quota[g], reverse=True)[: total - sum(quota.values())]:
        quota[g] += 1
    return quota


def cmd_import_chats(args: argparse.Namespace) -> int:
    """Import Moustafa's own chat messages into the PRIVATE folder (ADR 0014).

    `--held-out` rows, drawn in proportion from each chat (column `source`), become test/dev in the usual 7:3
    cycle; the rest become training rows. Diacritics and tatweel are removed from the Arabic; rows that break a
    rule or repeat a sentence are skipped. Nothing printed contains message text.
    """
    if any(str(r.get("source", "")).startswith("own-chats") for r in all_rows()):
        print("Own chats are already imported; remove the private rows first to import again.")
        return 1
    existing = all_rows()
    accepted: list[tuple[dict, dict]] = []  # (sheet row, new row)
    reasons: Counter = Counter()
    for item in read_sheet(Path(args.file)):
        arabizi, arabic = str(item.get("arabizi") or "").strip(), str(item.get("arabic") or "")
        arabic = " ".join(P.DIACRITICS.sub("", arabic).replace(P.TATWEEL, "").split())
        group = str(item.get("source") or "unknown").strip()
        row = new_hand_row(arabizi, arabic, {}, "train", existing + [r for _, r in accepted])
        row["source"] = f"own-chats ({group}, {item.get('year') or 'year unknown'})"
        problems = [e.split(":")[0] for e in P.row_errors(row, "train", "hand")]
        if _duplicate_of(row, existing + [r for _, r in accepted]):
            problems.append("repeats a sentence already in the data")
        if problems:
            reasons.update(set(problems))
            continue
        accepted.append(({"group": group}, row))

    if not accepted:
        print("Nothing to import: every row was skipped. " + "; ".join(f"{r} ({n})" for r, n in reasons.most_common()))
        return 1
    sizes = Counter(meta["group"] for meta, _ in accepted)
    quota = held_out_quota(dict(sizes), min(args.held_out, len(accepted)))
    rng = random.Random(args.seed)
    chosen: set[str] = set()
    for group in sorted(quota):
        members = [row["id"] for meta, row in accepted if meta["group"] == group]
        chosen.update(rng.sample(members, quota[group]))
    held = 0
    counts: Counter = Counter()
    for _, row in accepted:  # keep the sheet order; held-out rows follow the 7:3 test/dev cycle
        if row["id"] in chosen:
            row["split"] = "dev" if held % 10 in DEV_SLOTS else "test"
            held += 1
        counts[row["split"]] += 1
        if not args.dry_run:
            target = path_for(row["split"], "hand", private=True)
            target.parent.mkdir(parents=True, exist_ok=True)
            append(target, row)
    verb = "would import" if args.dry_run else "imported"
    print(f"{verb} {len(accepted)} rows into data/private/pairs (never committed): "
          f"test {counts['test']}, dev {counts['dev']}, train {counts['train']}")
    print("held out per chat: " + ", ".join(f"{g} {quota[g]}/{sizes[g]}" for g in sorted(quota)))
    if reasons:
        print(f"skipped {sum(reasons.values())} problems: " + "; ".join(f"{r} ({n})" for r, n in reasons.most_common()))
    return 0


def cmd_export_train(args: argparse.Namespace) -> int:
    """Write build/train-export/ for a PRIVATE Kaggle dataset: training rows only, as chat examples."""
    from arabizi_eval import export

    if not any(r.get("method") == "rule_variant" for r in all_rows()):
        print("Note: no spelling variants found; run `pairs variants` first.")
    summary = export.export(ai_variants=args.ai_variants, val_share=args.val_share, seed=args.seed,
                            include_private=not args.public_only)
    print(f"wrote {export.EXPORT_DIR.relative_to(P.ROOT)}/: {summary['rows_total']} training examples, "
          f"AI-derived share {summary['ai_share']:.0%} (ADR 0010 cap: 50%)")
    for name, info in summary["files"].items():
        print(f"  {name:22} {info['rows']:>6} rows")
    if summary["ai_share"] > 0.5:
        print("WARNING: AI-derived rows are above half of the training set (ADR 0010); lower --ai-variants.")
        return 1
    print("Upload the whole folder as a PRIVATE Kaggle dataset (docs/TRAINING.md).")
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
                try:
                    row["accepted"] = parse_accepted(ask("  Accepted (primary=variant; ...): "))
                except ValueError as exc:
                    print(f"  Not marked as checked, edit discarded: {exc}")
                    continue
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
    unchecked = sum(not r["checked_by"] for r in rows if r["method"] != "rule_variant")  # variants: no check
    today = sum(r["date"] == date.today().isoformat() for r in rows)

    private = Counter(r["split"] for r in private_rows())
    print(f"Rows: {len(rows)}  (test {by_split['test']}, dev {by_split['dev']}, train {by_split['train']})")
    if private:
        print(f"  of which private: test {private['test']}, dev {private['dev']}, train {private['train']}")
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
    imp = sub.add_parser("import", help="add hand-written pairs from a list file ('-' for stdin)")
    imp.add_argument("file")
    imp.add_argument("--split", choices=["test", "dev", "train"], help="override the automatic split")
    imp.add_argument("--dry-run", action="store_true", help="check the list without saving")
    imp.add_argument("--allow-warnings", action="store_true", help="save rows that only have warnings")
    batch = sub.add_parser("import-batch", help="add training rows from another source (JSONL)")
    batch.add_argument("file")
    batch.add_argument("--method", required=True, choices=["ai_checked", "public"])
    batch.add_argument("--writer", required=True, help="e.g. claude+moustafa-edited, or the dataset authors")
    batch.add_argument("--checked-by", required=True, help="who checked every row, e.g. moustafa")
    batch.add_argument("--source", required=True, help="batch or dataset name, recorded in docs/DATA.md")
    batch.add_argument("--date", help="date the rows were written (default today)")
    batch.add_argument("--dry-run", action="store_true", help="check without saving")
    batch.add_argument("--allow-warnings", action="store_true", help="save rows that only have warnings")
    var = sub.add_parser("variants", help="regenerate rule-made spelling variants of the training rows")
    var.add_argument("--per-row", type=int, default=2, help="variants per training row (default 2)")
    var.add_argument("--seed", type=int, default=2026, help="random seed; the same seed gives the same file")
    var.add_argument("--show", type=int, default=8, help="print this many random examples")
    var.add_argument("--dry-run", action="store_true", help="generate and report without writing")
    chats = sub.add_parser("import-chats", help="import your own chat messages into the PRIVATE folder")
    chats.add_argument("file", help=".xlsx or .jsonl with columns arabizi, arabic, source (and optionally year)")
    chats.add_argument("--held-out", type=int, default=300, help="rows for test+dev, drawn evenly from each chat")
    chats.add_argument("--seed", type=int, default=2026)
    chats.add_argument("--dry-run", action="store_true", help="check and report without writing")
    sub.add_parser("lexicon", help="rebuild the B0 word dictionary from the public train split")
    exp = sub.add_parser("export-train", help="training files for Kaggle fine-tuning (P4)")
    exp.add_argument("--ai-variants", type=int, default=1, help="spelling variants kept per AI-drafted row")
    exp.add_argument("--val-share", type=float, default=0.05, help="share of sentence groups for validation loss")
    exp.add_argument("--seed", type=int, default=2026)
    exp.add_argument("--public-only", action="store_true", help="leave out the private rows")
    check = sub.add_parser("check", help="delayed self-check")
    check.add_argument("--days", type=int, default=1,
                       help="only rows written before the date this many days ago (default 1: >= 24 h)")
    sub.add_parser("stats", help="counts and progress")
    sub.add_parser("validate", help="run all checks")
    args = parser.parse_args(argv)
    commands = {"add": cmd_add, "import": cmd_import, "import-batch": cmd_import_batch,
                "import-chats": cmd_import_chats, "variants": cmd_variants, "lexicon": cmd_lexicon,
                "check": cmd_check, "stats": cmd_stats, "export-train": cmd_export_train,
                "validate": cmd_validate}
    return commands[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
