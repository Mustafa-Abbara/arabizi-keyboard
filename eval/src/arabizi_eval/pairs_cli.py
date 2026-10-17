"""Write, check and count Arabizi pairs.

  uv run --project eval pairs add      # type new hand-written pairs
  uv run --project eval pairs import F # add a list of hand-written pairs: one 'arabizi | arabic' per line
  uv run --project eval pairs import-batch F --method ai_checked ...  # training rows from another source
  uv run --project eval pairs import-chats F.xlsx --held-out 300  # own chat messages, PRIVATE (ADR 0014)
  uv run --project eval pairs variants # regenerate rule-made spelling variants of the training rows
  uv run --project eval pairs lexicon  # rebuild the B0 word dictionary from the train split
  uv run --project eval pairs check    # delayed self-check of rows written >= 24 h ago
  uv run --project eval pairs stats    # counts and progress towards the P2 targets
  uv run --project eval pairs publish  # choose private chat test/dev rows to make public (before the freeze)
  uv run --project eval pairs freeze   # freeze the test and dev sets (roadmap P2 step 4)
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
PUBLISHED_SOURCE = "own-chat-published"  # replaces the private chat label, which may name a person (ADR 0014)
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
    from arabizi_eval import parity

    parity.write()  # the Swift rule fallback is tested against B0's output with this dictionary
    print(f"wrote {parity.FIXTURE.name} (Swift parity fixture): commit it with the dictionary")
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
    if args.held_out and P.MANIFEST_PATH.exists():
        print("The test set is frozen: import with --held-out 0 (everything goes to training).")
        return 1
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


ARTICLE_TATWEEL = re.compile(r"الـ\s*")  # "الـ X" -> "الX" (SPELLING.md 2.3: no tatweel)


def clean_sheet_arabic(text: str) -> str:
    text = " ".join(P.DIACRITICS.sub("", ARTICLE_TATWEEL.sub("ال", str(text))).replace(P.TATWEEL, "").split())
    return P.split_glued_prefixes(text)


def _near_duplicate(arabizi: str, word_sets: list[set[str]]) -> bool:
    """Same sentence with small edits: at least 4 words and 80% word overlap with a training sentence."""
    words = set(P.normalize_arabizi(arabizi).split())
    return len(words) >= 4 and any(len(words & o) / len(words | o) >= 0.8 for o in word_sets if o)


def cmd_import_real(args: argparse.Namespace) -> int:
    """Import real messages written by other people (ADR 0021), all public: --train rows into
    data/pairs/train-hand.jsonl, --held-out rows into the "others" held-out set (data/pairs/others/), split into
    dev and test and frozen with its own manifest. Rows that break a rule or repeat a sentence are skipped; a
    held-out row that repeats or nearly repeats a training sentence is skipped too. Prints counts only.
    """
    if P.OTHERS_MANIFEST_PATH.exists():
        print("The others set is already frozen; importing again would change it.")
        return 1
    existing = all_rows() + [row for path in P.pair_files(others=True) for _, row, err in P.read_jsonl(path) if not err]
    new: list[dict] = []
    reasons: Counter = Counter()
    seen = set().union(*(P._dedupe_keys(r) for r in existing))
    next_number = int(next_id("hand", existing).split("-")[1])

    def take(path: str, split: str, train_words: list[set[str]] | None = None) -> list[dict]:
        nonlocal next_number
        taken = []
        for item in read_sheet(Path(path)):
            arabizi = " ".join(str(item.get("arabizi") or "").split())
            row = new_hand_row(arabizi, clean_sheet_arabic(item.get("arabic") or ""), {}, split, [])
            row.update(id=f"{P.ID_PREFIX['hand']}-{next_number:04d}", writer=args.writer,
                       checked_by=args.checked_by, source=args.source)
            problems = [e.split(":")[0] for e in P.row_errors(row, split if split == "train" else None, "hand")]
            keys = P._dedupe_keys(row)
            if keys & seen:
                problems.append("repeats a sentence already in the data")
            elif train_words is not None and _near_duplicate(arabizi, train_words):
                problems.append("nearly repeats a training sentence")
            if problems:
                reasons.update(f"{split}: {p}" for p in set(problems))
                continue
            seen.update(keys)
            next_number += 1
            new.append(row)
            taken.append(row)
        return taken

    train = take(args.train, "train")
    train_words = [set(P.normalize_arabizi(r["arabizi"]).split()) for r in existing + new if r.get("split") == "train"]
    held = take(args.held_out, "test", train_words)
    rng = random.Random(args.seed)
    dev_ids = {r["id"] for r in rng.sample(held, min(args.dev, len(held)))}
    for row in held:
        row["split"] = "dev" if row["id"] in dev_ids else "test"
    counts = Counter(r["split"] for r in train + held)
    print(f"{'would import' if args.dry_run else 'imported'}: train {counts['train']} (data/pairs/train-hand.jsonl), "
          f"others dev {counts['dev']} + test {counts['test']} (data/pairs/others/)")
    if reasons:
        print(f"skipped {sum(reasons.values())}: " + "; ".join(f"{r} ({n})" for r, n in reasons.most_common()))
    if args.dry_run:
        return 0
    for row in train:
        append(path_for("train", "hand"), row)
    P.OTHERS_DIR.mkdir(parents=True, exist_ok=True)
    for row in held:
        append(P.OTHERS_DIR / f"{row['split']}.jsonl", row)
    files = {key: {"sha256": P.sha256_file(path), "rows": counts[key.split("/")[1].split(".")[0]], "private": False}
             for key, (path, _) in P.others_files().items() if path.exists()}
    manifest = {
        "_comment": "Frozen \"others\" held-out set (ADR 0021): real messages by other people, scored with "
                    "`evalrun ... --others`. `pairs validate` and CI fail if a listed file changes. "
                    "Do not edit by hand.",
        "version": args.version, "frozen_on": date.today().isoformat(),
        "reason": "first import of the others set", "previous_version": None, "unchecked_rows": 0, "files": files,
    }
    P.OTHERS_MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"froze {args.version} (data/pairs/others/manifest.json)")
    return 0


def cmd_split_prefixes(args: argparse.Namespace) -> int:
    """Write Arabic prefixes apart from Latin words (`الvideo` -> `ال video`, SPELLING.md 4) in every training file,
    public and private, and with --others in the others held-out set (which then needs `pairs freeze --others`).
    testset-v1.0 is never touched. Accepted variants are rewritten the same way. Prints counts only."""
    files = [path for path in P.pair_files() if P.expected_split(path)[0] == "train"]
    files += P.pair_files(others=True) if args.others else []
    changed_rows = 0
    for path in files:
        lines, changed = [], 0
        for _, row, err in P.read_jsonl(path):
            if row is None:
                raise SystemExit(f"{path.name}: {err}")
            fixed = P.split_glued_prefixes(row["arabic"])
            accepted = {P.split_glued_prefixes(k): [P.split_glued_prefixes(v) for v in vs]
                        for k, vs in row["accepted"].items()}
            if fixed != row["arabic"] or accepted != row["accepted"]:
                changed += 1
                row = {**row, "arabic": fixed, "accepted": accepted}
            lines.append(json.dumps(row, ensure_ascii=False))
        if changed and not args.dry_run:
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        where = "others/" if P.OTHERS_DIR in path.parents else "private/" if P.is_private(path) else ""
        print(f"{where}{path.name}: {changed} rows {'would change' if args.dry_run else 'changed'}")
        changed_rows += changed
    print(f"total: {changed_rows} rows")
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


def cmd_freeze(args: argparse.Namespace) -> int:
    """Record the SHA-256 of the public and private test/dev files in data/pairs/manifest.json.

    After the freeze, `pairs validate` (and CI) fail if a frozen file changes; new hand-written rows go to training.
    Private files are recorded by hash and row count only. Refuses while held-out rows are unchecked (ADR 0011),
    unless --allow-unchecked is given (recorded in the manifest). `--others`: the others held-out set and its own
    manifest (data/pairs/others/manifest.json, ADR 0021) instead.
    """
    manifest_path = P.OTHERS_MANIFEST_PATH if args.others else P.MANIFEST_PATH
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else None
    if previous and not args.reason:
        print(f"Already frozen as {previous['version']}: a new freeze needs --version and --reason.")
        return 1
    if previous and args.version == previous["version"]:
        print(f"{args.version} is the current version: choose a new one (e.g. testset-v1.1).")
        return 1
    rows_now = ([row for path in P.pair_files(others=True) for _, row, err in P.read_jsonl(path) if not err]
                if args.others else all_rows())
    held_out = [r for r in rows_now if r.get("split") in ("test", "dev")]
    unchecked = sum(not r.get("checked_by") for r in held_out)
    if unchecked and not args.allow_unchecked:
        print(f"{unchecked} test/dev rows are not checked yet (checked_by is empty). Run `pairs check` first, "
              "or freeze anyway with --allow-unchecked (recorded in the manifest).")
        return 1
    files = {}
    for key, (path, private) in (P.others_files() if args.others else P.held_out_files()).items():
        if path.exists():
            rows = sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
            files[key] = {"sha256": P.sha256_file(path), "rows": rows, "private": private}
    manifest = {
        "_comment": "Frozen held-out data (roadmap P2 step 4). `pairs validate` and CI fail if a listed file changes. "
                    "Private files: hash and row count only, checked where they exist. Do not edit by hand: use "
                    "`pairs freeze --version ... --reason ...` with the testset-change label (docs/DATA.md).",
        "version": args.version, "frozen_on": date.today().isoformat(),
        "reason": args.reason or "first freeze, before any fine-tuning (P4)",
        "previous_version": previous["version"] if previous else None,
        "unchecked_rows": unchecked, "files": files,
    }
    if args.others:
        manifest["_comment"] = ("Frozen \"others\" held-out set (ADR 0021): real messages by other people, scored with "
                                "`evalrun ... --others`. `pairs validate` and CI fail if a listed file changes. "
                                "Re-freeze with `pairs freeze --others --version ... --reason ...`.")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    total = sum(f["rows"] for f in files.values())
    print(f"froze {args.version}: {total} held-out rows in {len(files)} files "
          f"({sum(f['rows'] for f in files.values() if f['private'])} private, hashes only); "
          f"{unchecked} unchecked. Commit data/pairs/{'others/' if args.others else ''}manifest.json in a PR with the "
          "testset-change label, then tag "
          f"the merge commit: git tag {args.version} && git push origin {args.version}")
    return 0


def publish_review_path() -> Path:
    """Ids already declined by `pairs publish`; in data/private, so never committed."""
    return P.PRIVATE_DIR.parent / "publish_review.json"


def publish_sheet_path() -> Path:
    """The spreadsheet for choosing rows to publish; in data/private, so never committed."""
    return P.PRIVATE_DIR.parent / "publish_review.xlsx"


YES = {"y", "yes", "x", "1", "true", "✓", "✔"}
NO = {"n", "no", "0", "false"}


def _declined() -> set[str]:
    review = publish_review_path()
    return set(json.loads(review.read_text(encoding="utf-8"))["declined"]) if review.exists() else set()


def _save_declined(declined: set[str]) -> None:
    publish_review_path().write_text(json.dumps({"declined": sorted(declined)}, indent=1) + "\n", encoding="utf-8")


def _private_held_out() -> list[dict]:
    if not P.PRIVATE_DIR.exists():
        return []
    return [row for split in ("test", "dev") for _, row, err in P.read_jsonl(path_for(split, private=True)) if not err]


def _publish_row(row: dict) -> None:
    """Move one private held-out row to the public file of its split, with the chat label replaced."""
    private_path = path_for(row["split"], private=True)
    rewrite(private_path, [r for _, r, err in P.read_jsonl(private_path) if not err and r["id"] != row["id"]])
    append(path_for(row["split"]), row | {"source": PUBLISHED_SOURCE})


def _publish_summary(published: Counter) -> None:
    from arabizi_eval import parity

    if published:
        parity.write()  # public dev rows are part of the Swift parity fixture
    public = Counter(r["split"] for r in all_rows(include_private=False) if r.get("split") in ("test", "dev"))
    print(f"published {sum(published.values())} rows ({published['test']} test, {published['dev']} dev); public "
          f"held-out now {public['test']} test + {public['dev']} dev. Commit data/pairs/test.jsonl, dev.jsonl and "
          "the parity fixture in a PR; freeze only after `pairs check` has covered every row.")


def _write_publish_sheet(rows: list[dict]) -> Path:
    import openpyxl
    from openpyxl.styles import Alignment, Font

    book = openpyxl.Workbook()
    sheet = book.active
    sheet.title = "publish"
    sheet.append(["arabizi", "arabic", "publish", "split", "id"])  # the choice sits right after the Arabic
    for row in rows:
        sheet.append([row["arabizi"], row["arabic"], "", row["split"], row["id"]])
    for cell in sheet[1]:
        cell.font = Font(bold=True)
    for cell in sheet["B"][1:]:
        cell.alignment = Alignment(horizontal="right", readingOrder=2)  # right to left
    for column, width in zip("ABCDE", (60, 60, 9, 6, 10), strict=True):
        sheet.column_dimensions[column].width = width
    sheet.freeze_panes = "A2"
    path = publish_sheet_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    book.save(path)
    return path


def _apply_publish_sheet(path: Path) -> int:
    """Publish the rows marked y in the sheet, remember the rows marked n, leave the blank ones for later."""
    by_id = {row["id"]: row for row in _private_held_out()}
    declined = _declined()
    published, changed, gone = Counter(), [], 0
    for line in read_sheet(path):
        row = by_id.get(str(line.get("id") or "").strip())
        answer = str(line.get("publish") or "").strip().lower()
        if row is None:
            gone += answer in YES  # already published, or not a private held-out id
            continue
        if answer in YES:
            if (str(line.get("arabizi") or ""), str(line.get("arabic") or "")) != (row["arabizi"], row["arabic"]):
                changed.append(row["id"])  # the sheet is for choosing, not editing: edits go through `pairs check`
                continue
            _publish_row(row)
            published[row["split"]] += 1
        elif answer in NO:
            declined.add(row["id"])
    _save_declined(declined)
    if changed:
        print(f"Not published, the text was changed in the sheet: {', '.join(changed)}. Fix spelling with "
              "`pairs check`, then mark them again.")
    if gone:
        print(f"{gone} rows marked y were already public or unknown; skipped.")
    _publish_summary(published)
    return 1 if changed else 0


def cmd_publish(args: argparse.Namespace) -> int:
    """Move private test/dev rows that Moustafa chooses into the public files, before the freeze (ADR 0014).

    Two ways to choose: one row at a time in the terminal, or (better for Arabic, which many terminals cannot lay
    out) `--sheet` writes data/private/publish_review.xlsx to mark with y/n in Numbers or Excel and `--apply` reads
    it back. A published row keeps its id, split, text, date and check; its source becomes PUBLISHED_SOURCE, so the
    private chat label is never published. Declined rows are remembered in data/private/publish_review.json.
    """
    if P.MANIFEST_PATH.exists():
        print("The test set is frozen: publishing rows would change it. Publish before `pairs freeze`, or plan a new "
              "freeze version with a reason (docs/DATA.md).")
        return 1
    if args.apply:
        return _apply_publish_sheet(Path(args.apply))
    declined = _declined()
    candidates = [row for row in _private_held_out() if row["id"] not in declined]
    random.Random(args.seed).shuffle(candidates)  # test and dev mixed, so the published share stays near 70/30
    if not candidates:
        print("No private test/dev rows left to review.")
        return 0
    if args.sheet:
        path = _write_publish_sheet(candidates)
        print(f"wrote {path.relative_to(P.ROOT) if path.is_relative_to(P.ROOT) else path} ({len(candidates)} rows; "
              "never committed). Open it in Numbers or Excel (not Google Sheets: it holds private text), type y in "
              "the publish column for each row with nothing personal (no names, places, other people or private "
              "details), n to keep it private, or leave it blank to decide later. Export it as .xlsx into "
              "data/private, not iCloud Drive (Numbers: File > Export To > Excel, then choose this folder; close the "
              "Numbers copy "
              "without saving it to iCloud, which would upload private text), then run:\n"
              f"  uv run --project eval pairs publish --apply {path}")
        return 0
    print(f"{len(candidates)} private test/dev rows to review. Publish a row only if it holds nothing personal: no "
          "names, places, other people, plans or details you would not post publicly.\n"
          "y = publish, Enter or n = keep private, q = stop (choices so far are saved)")
    published = Counter()
    for row in candidates:
        if args.target and sum(published.values()) >= args.target:
            break
        print(f"\n[{row['split']}] {row['arabizi']}\n       {row['arabic']}")
        answer = ask("  publish? [y/N/q] ").lower()
        if answer == "q":
            break
        if answer != "y":
            declined.add(row["id"])
            _save_declined(declined)
            continue
        _publish_row(row)
        published[row["split"]] += 1
    print()
    _publish_summary(published)
    return 0


def _duplicate_of(row: dict, rows: list[dict]) -> str | None:
    keys = P._dedupe_keys(row)
    for other in rows:
        if keys & P._dedupe_keys(other):
            return other["id"]
    return None


BIDI_MARKS = re.compile("[\u200e\u200f\u202a-\u202e\u2066-\u2069]")  # spreadsheets may add these around Arabic


def check_sheet_path() -> Path:
    """The spreadsheet for the self-check; in data/private (it can hold private rows), so never committed."""
    return P.PRIVATE_DIR.parent / "check_review.xlsx"


def format_accepted(accepted: dict[str, list[str]]) -> str:
    """{'هلق': ['هلأ']} -> 'هلق=هلأ', the form parse_accepted reads back."""
    return "; ".join(f"{primary}={'|'.join(variants)}" for primary, variants in accepted.items())


def _sheet_text(value: object) -> str:
    return BIDI_MARKS.sub("", str(value if value is not None else "")).strip()


def _write_check_sheet(rows: list[dict]) -> Path:
    import openpyxl
    from openpyxl.styles import Alignment, Font

    book = openpyxl.Workbook()
    sheet = book.active
    sheet.title = "check"
    # ok sits right after the Arabic, where the eye ends up (a first-column ok was missed: y went into accepted).
    sheet.append(["arabizi", "arabic", "ok", "accepted", "split", "id"])
    for row in rows:
        sheet.append([row["arabizi"], row["arabic"], "", format_accepted(row["accepted"]), row["split"], row["id"]])
    for cell in sheet[1]:
        cell.font = Font(bold=True)
    for column in ("B", "D"):
        for cell in sheet[column][1:]:
            cell.alignment = Alignment(horizontal="right", readingOrder=2)  # right to left
    for column, width in zip("ABCDEF", (60, 60, 8, 30, 6, 10), strict=True):
        sheet.column_dimensions[column].width = width
    sheet.freeze_panes = "A2"
    path = check_sheet_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    book.save(path)
    return path


def _check_candidates(cutoff: date, include_train: bool) -> list[dict]:
    """Unchecked rows old enough to check: test and dev, plus hand-written training rows if asked (never variants)."""
    out = []
    for path in P.pair_files():
        lines = P.read_jsonl(path)
        if any(err for _, _, err in lines):
            print(f"Skipping {path.name}: it has broken lines. Run `pairs validate` and fix them first.")
            continue
        for _, row, _ in lines:
            if row.get("checked_by") or date.fromisoformat(row["date"]) >= cutoff:
                continue
            if row["split"] in ("test", "dev") or (include_train and row["method"] in ("hand", "ai_checked")):
                out.append(row)
    return out


def _apply_check_sheet(sheet_path: Path, cutoff: date) -> int:
    """Mark the rows with ok = y as checked, taking the Arabic and accepted variants as fixed in the sheet."""
    marks, keep_accepted = {}, set()
    for line in read_sheet(sheet_path):
        row_id = _sheet_text(line.get("id"))
        ok, accepted = _sheet_text(line.get("ok")).lower(), _sheet_text(line.get("accepted"))
        if not ok and accepted.lower() in YES:
            # A check mark typed one column off (accepted instead of ok). "y" can never be a variant, so it is
            # read as ok and the row keeps the accepted variants it had.
            ok = "y"
            keep_accepted.add(row_id)
        if ok in YES:
            marks[row_id] = line
    if keep_accepted:
        print(f"{len(keep_accepted)} row(s) had the y in the accepted column; taken as ok.")
    checked, refused = 0, []
    for path in P.pair_files():
        lines = P.read_jsonl(path)
        if any(err for _, _, err in lines):
            print(f"Skipping {path.name}: it has broken lines. Run `pairs validate` and fix them first.")
            continue
        rows = [row for _, row, _ in lines]
        changed = False
        for row in rows:
            line = marks.pop(row["id"], None)
            if line is None or row.get("checked_by"):
                continue
            if date.fromisoformat(row["date"]) >= cutoff:
                refused.append(f"{row['id']}: written less than {(date.today() - cutoff).days} day(s) ago")
                continue
            if _sheet_text(line.get("arabizi")) != row["arabizi"].strip():
                refused.append(f"{row['id']}: the Arabizi was changed (the self-check only fixes the Arabic)")
                continue
            original = dict(row)
            row["arabic"] = _sheet_text(line.get("arabic")) or row["arabic"]
            try:
                if row["id"] not in keep_accepted:
                    row["accepted"] = parse_accepted(_sheet_text(line.get("accepted")))
            except ValueError as exc:
                refused.append(f"{row['id']}: {exc}")
                row.clear()
                row.update(original)
                continue
            errors = P.row_errors(row)
            if errors:
                refused.append(f"{row['id']}: " + "; ".join(errors))
                row.clear()
                row.update(original)
                continue
            row["checked_by"] = CHECKER
            changed = True
            checked += 1
        if changed:
            rewrite(path, rows)
    for row_id in marks:
        refused.append(f"{row_id}: no unchecked row with this id")
    for message in refused:
        print(f"  not checked: {message}")
    rest = f", {len(refused)} not (fix them in the sheet and apply again)" if refused else ""
    print(f"{checked} row(s) checked{rest}.")
    return 1 if refused else 0


def cmd_check(args: argparse.Namespace) -> int:
    """Delayed self-check (ADR 0011) of unchecked rows.

    Rows only carry a date, so "at least N days" means written before the date N days ago: with --days 1, a row
    from yesterday waits until tomorrow, which guarantees >= 24 hours whatever time it was written.
    `--sheet` writes data/private/check_review.xlsx to check in Numbers or Excel, which lay out Arabic correctly
    (many terminals do not); `--apply` reads it back.
    """
    cutoff = date.today() - timedelta(days=args.days)
    if args.apply:
        return _apply_check_sheet(Path(args.apply), cutoff)
    if args.sheet:
        rows = _check_candidates(cutoff, args.train)
        if not rows:
            print(f"No unchecked rows written before {cutoff}.")
            return 0
        path = _write_check_sheet(rows)
        print(f"wrote {path.relative_to(P.ROOT) if path.is_relative_to(P.ROOT) else path}: {len(rows)} unchecked rows "
              f"written before {cutoff} (never committed). Re-read docs/SPELLING.md, then open it in Numbers or Excel "
              "(not Google Sheets: it can hold private text). For each row: fix the arabic (and accepted, as "
              "primary=variant; ...) if needed, then type y in ok. Leave ok blank to check it later. Do not change "
              "the arabizi. Export as .xlsx into data/private, not iCloud Drive (Numbers: File > Export To > Excel, "
              "then choose this folder in the save dialog; close the Numbers copy without saving it to iCloud), then "
              f"run:\n  uv run --project eval pairs check --apply {path}")
        return 0
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
    if P.MANIFEST_PATH.exists():
        frozen = json.loads(P.MANIFEST_PATH.read_text(encoding="utf-8"))
        print(f"Test set frozen: {frozen['version']} ({frozen['frozen_on']}); new hand-written rows go to training")
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
    real = sub.add_parser("import-real", help="import real messages by other people: training rows and the "
                                              "frozen 'others' held-out set (ADR 0021)")
    real.add_argument("--train", required=True, help=".xlsx/.jsonl with arabizi and arabic columns")
    real.add_argument("--held-out", required=True, help=".xlsx/.jsonl for the others dev/test set")
    real.add_argument("--dev", type=int, default=200, help="held-out rows that go to dev (the rest: test)")
    real.add_argument("--writer", default="friends-and-family")
    real.add_argument("--source", default="friends-and-family (ADR 0021)")
    real.add_argument("--checked-by", default="moustafa")
    real.add_argument("--version", default="others-v1.0")
    real.add_argument("--seed", type=int, default=2026)
    real.add_argument("--dry-run", action="store_true")
    split = sub.add_parser("split-prefixes", help="write Arabic prefixes apart from Latin words (SPELLING.md 4)")
    split.add_argument("--others", action="store_true", help="also the others held-out set (re-freeze afterwards)")
    split.add_argument("--dry-run", action="store_true")
    sub.add_parser("lexicon", help="rebuild the B0 word dictionary from the public train split")
    exp = sub.add_parser("export-train", help="training files for Kaggle fine-tuning (P4)")
    exp.add_argument("--ai-variants", type=int, default=1, help="spelling variants kept per AI-drafted row")
    exp.add_argument("--val-share", type=float, default=0.05, help="share of sentence groups for validation loss")
    exp.add_argument("--seed", type=int, default=2026)
    exp.add_argument("--public-only", action="store_true", help="leave out the private rows")
    check = sub.add_parser("check", help="delayed self-check")
    check.add_argument("--days", type=int, default=1,
                       help="only rows written before the date this many days ago (default 1: >= 24 h)")
    check.add_argument("--sheet", action="store_true", help="write a spreadsheet to check in, instead of the terminal")
    check.add_argument("--apply", metavar="FILE", help="mark the rows with ok = y in that spreadsheet as checked")
    check.add_argument("--train", action="store_true",
                       help="with --sheet: include hand-written training rows too (never generated variants)")
    sub.add_parser("stats", help="counts and progress")
    pub = sub.add_parser("publish", help="choose private chat test/dev rows to make public (before the freeze)")
    pub.add_argument("--target", type=int, help="stop after publishing this many rows")
    pub.add_argument("--sheet", action="store_true", help="write a spreadsheet to choose in, instead of the terminal")
    pub.add_argument("--apply", metavar="FILE", help="publish the rows marked y in that spreadsheet")
    pub.add_argument("--seed", type=int, default=2026, help="order in which rows are shown")
    freeze = sub.add_parser("freeze", help="freeze the test and dev sets (roadmap P2 step 4)")
    freeze.add_argument("--version", default="testset-v1.0")
    freeze.add_argument("--reason", help="required when re-freezing: why the held-out data changed")
    freeze.add_argument("--allow-unchecked", action="store_true", help="freeze although some rows are unchecked")
    freeze.add_argument("--others", action="store_true", help="the others held-out set (ADR 0021) and its manifest")
    sub.add_parser("validate", help="run all checks")
    args = parser.parse_args(argv)
    commands = {"add": cmd_add, "import": cmd_import, "import-batch": cmd_import_batch,
                "import-chats": cmd_import_chats, "import-real": cmd_import_real, "split-prefixes": cmd_split_prefixes,
                "variants": cmd_variants,
                "lexicon": cmd_lexicon,
                "check": cmd_check, "stats": cmd_stats, "freeze": cmd_freeze, "publish": cmd_publish,
                "export-train": cmd_export_train, "validate": cmd_validate}
    return commands[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
