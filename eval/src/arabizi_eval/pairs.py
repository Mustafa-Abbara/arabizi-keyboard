"""Load and validate Arabizi pairs (data/pairs/*.jsonl). Format: docs/DATA.md; spelling: docs/SPELLING.md."""

from __future__ import annotations

import hashlib
import json
import os
import re
from collections import Counter
from dataclasses import dataclass, field
from functools import cache
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(os.environ.get("ARABIZI_ROOT", Path(__file__).resolve().parents[3]))
PAIRS_DIR = ROOT / "data" / "pairs"
# Private pairs (Moustafa's own chat messages, ADR 0014): same file names and rules, never committed (.gitignore).
PRIVATE_DIR = ROOT / "data" / "private" / "pairs"
SCHEMA_PATH = ROOT / "data" / "schema" / "pair.schema.json"
MANIFEST_PATH = PAIRS_DIR / "manifest.json"  # written when the test set is frozen (P2 step 4)
# The "others" held-out set (ADR 0021): real messages written by other people, scored separately from testset-v1.0.
# Its own folder, so training, variants and the main splits never read it; frozen with its own manifest.
OTHERS_DIR = PAIRS_DIR / "others"
OTHERS_MANIFEST_PATH = OTHERS_DIR / "manifest.json"

ID_PREFIX = {"hand": "hw", "rule_variant": "rv", "public": "pb", "ai_checked": "ai"}

DIACRITICS = re.compile("[ً-ْٰ]")
TATWEEL = "ـ"
ARABIC_INDIC_DIGITS = re.compile("[٠-٩۰-۹]")
ARABIC_LETTER = re.compile("[ء-ي]")
# A standalone number: not glued to letters or digits. "2pm", "100$", "$5", "10:30" count; "3am", "la2", "7elo" do not
# ("3am" is the word عم, so "am" is deliberately not a number suffix).
NUMBER = re.compile(r"(?<![A-Za-z0-9])[$€£]?\d+(?:[.,:]\d+)*(?:[$€£%]|k|K|pm|PM)?(?![A-Za-z0-9])")
UNTOUCHED = re.compile(r"https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.]+|[@#]\w+")
TRAILING_PUNCTUATION = "?,;!.:)\"'"  # typed after a link, not part of it; SPELLING.md 7 may convert it
# Arabic letters glued to a Latin word (`الvideo`): SPELLING.md 4 writes the Arabic prefix apart (`ال video`).
GLUED_PREFIX = re.compile("([ء-ي]+)(?=[A-Za-z])")


def split_glued_prefixes(text: str) -> str:
    """`الvideo عالfacebook` -> `ال video عال facebook` (SPELLING.md 4; ADR 0024). Links and mentions are kept."""
    kept = UNTOUCHED.findall(text)
    parts = UNTOUCHED.split(text)
    out = [GLUED_PREFIX.sub(r"\1 ", part) for part in parts]
    return "".join(p + (kept[i] if i < len(kept) else "") for i, p in enumerate(out))


@dataclass
class Problem:
    where: str  # "file:line id"
    message: str


@dataclass
class Report:
    rows: list[dict] = field(default_factory=list)
    errors: list[Problem] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


@cache
def validator() -> Draft202012Validator:
    return Draft202012Validator(json.loads(SCHEMA_PATH.read_text(encoding="utf-8")))


def normalize_arabic(text: str, lenient: bool = False) -> str:
    """Strict: drop diacritics and tatweel, collapse spaces. Lenient also merges alif forms, final ى/ي and ة/ه."""
    text = DIACRITICS.sub("", text).replace(TATWEEL, "")
    if lenient:
        text = re.sub("[أإآ]", "ا", text)
        text = re.sub(r"ى\b", "ي", text)
        text = re.sub(r"ة\b", "ه", text)
    return " ".join(text.split())


def normalize_arabizi(text: str) -> str:
    """For duplicate detection: lowercase, punctuation removed, spaces collapsed."""
    return " ".join(re.sub(r"[^\w\s$€£%@#:/.]", " ", text.lower()).split())


def expected_split(path: Path) -> tuple[str, str | None]:
    """test.jsonl -> (test, None); dev.jsonl -> (dev, None); train-<method>.jsonl -> (train, method)."""
    stem = path.stem
    if stem in ("test", "dev"):
        return stem, None
    if stem.startswith("train-") and stem[len("train-"):] in ID_PREFIX:
        return "train", stem[len("train-"):]
    raise ValueError(f"unexpected pair file name {path.name}: use test.jsonl, dev.jsonl or train-<method>.jsonl")


def pair_files(pairs_dir: Path | None = None, include_private: bool = True, others: bool = False) -> list[Path]:
    """Pair files in `pairs_dir`, or the public folder plus (if present and wanted) the private one.
    `others=True`: the "others" held-out set instead (ADR 0021)."""
    if pairs_dir is not None:
        return sorted(pairs_dir.glob("*.jsonl"))
    if others:
        return sorted(OTHERS_DIR.glob("*.jsonl"))
    folders = [PAIRS_DIR] + ([PRIVATE_DIR] if include_private and PRIVATE_DIR.exists() else [])
    return [path for folder in folders for path in sorted(folder.glob("*.jsonl"))]


def is_private(path: Path) -> bool:
    return PRIVATE_DIR in path.parents


def read_jsonl(path: Path) -> list[tuple[int, dict | None, str | None]]:
    """(line number, row or None, error or None) for each non-empty line. Rows are always JSON objects."""
    out = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            out.append((n, None, f"invalid JSON: {exc}"))
            continue
        out.append((n, row, None) if isinstance(row, dict) else (n, None, "line is not a JSON object"))
    return out


def row_errors(row: dict, split: str | None = None, method: str | None = None) -> list[str]:
    """Problems in one row that do not need the other rows."""
    errors = [f"schema: {e.message}" for e in validator().iter_errors(row)]
    if errors:
        return errors
    if split and row["split"] != split:
        errors.append(f"split is {row['split']!r} but the file holds {split!r} rows")
    if method and row["method"] != method:
        errors.append(f"method is {row['method']!r} but the file holds {method!r} rows")
    if row["split"] in ("test", "dev") and row["method"] != "hand":
        errors.append("test and dev rows must be hand-written (method 'hand')")
    if not row["id"].startswith(ID_PREFIX[row["method"]] + "-"):
        errors.append(f"id must start with {ID_PREFIX[row['method']]}- for method {row['method']}")
    if row["method"] == "ai_checked" and not row["checked_by"]:
        errors.append("ai_checked rows must be checked (checked_by is empty)")
    if row["method"] == "rule_variant" and "parent" not in row:
        errors.append("rule_variant rows need a parent id")

    arabic, arabizi = row["arabic"], row["arabizi"]
    if DIACRITICS.search(arabic) or TATWEEL in arabic:
        errors.append("arabic has diacritics or tatweel (SPELLING.md 2.3)")
    if ARABIC_INDIC_DIGITS.search(arabic):
        errors.append("arabic has Arabic-Indic digits; keep Western digits (SPELLING.md 6)")
    if not ARABIC_LETTER.search(arabic):
        errors.append("arabic has no Arabic letters")
    if ARABIC_LETTER.search(arabizi):
        errors.append("arabizi has Arabic letters")
    missing = Counter(NUMBER.findall(arabizi)) - Counter(NUMBER.findall(arabic))
    if missing:
        errors.append(f"numbers not kept as typed (SPELLING.md 6): {sorted(missing)}")
    for token in UNTOUCHED.findall(arabizi):
        token = token.rstrip(TRAILING_PUNCTUATION)
        if token not in arabic:
            errors.append(f"link, email, mention or hashtag changed: {token!r}")
    for primary, variants in row["accepted"].items():
        if primary not in arabic:
            errors.append(f"accepted key {primary!r} is not in the arabic text")
        if primary in variants:
            errors.append(f"accepted variants for {primary!r} repeat the primary spelling")
    return errors


def row_warnings(row: dict) -> list[str]:
    """Likely slips that are allowed (shown by the CLI, not failed by tests)."""
    warnings = []
    # Numbers ("89,500") and links keep their punctuation as typed (SPELLING.md 6), so ignore them here.
    def outside_numbers_and_links(text: str) -> str:
        return NUMBER.sub(" ", UNTOUCHED.sub(" ", text))

    arabizi, arabic_text = outside_numbers_and_links(row["arabizi"]), outside_numbers_and_links(row["arabic"])
    if GLUED_PREFIX.search(UNTOUCHED.sub(" ", row["arabic"])):
        warnings.append("an Arabic prefix is glued to a Latin word; write it apart (SPELLING.md 4)")
    for latin, arabic in (("?", "؟"), (",", "،"), (";", "؛")):
        if latin in arabizi and arabic not in arabic_text and latin in arabic_text:
            warnings.append(f"{latin!r} usually becomes {arabic!r} (SPELLING.md 7)")
    return warnings


FROZEN_NAMES = ("test.jsonl", "dev.jsonl")  # the held-out files the freeze protects (roadmap P2 step 4)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def held_out_files() -> dict[str, tuple[Path, bool]]:
    """Manifest key -> (path, private) for the public and private test/dev files."""
    files = {f"public/{name}": (PAIRS_DIR / name, False) for name in FROZEN_NAMES}
    files.update({f"private/{name}": (PRIVATE_DIR / name, True) for name in FROZEN_NAMES})
    return files


def others_files() -> dict[str, tuple[Path, bool]]:
    """Manifest key -> (path, private) for the "others" held-out set (ADR 0021)."""
    return {f"others/{name}": (OTHERS_DIR / name, False) for name in FROZEN_NAMES}


def freeze_problems(manifest_path: Path | None = None, others: bool = False) -> list[Problem]:
    """Frozen held-out files that changed or disappeared. Private files are only checked where they exist."""
    path = manifest_path or (OTHERS_MANIFEST_PATH if others else MANIFEST_PATH)
    if not path.exists():
        return []
    manifest = json.loads(path.read_text(encoding="utf-8"))
    files = others_files() if others else held_out_files()
    problems = []
    for key, entry in manifest["files"].items():
        file, private = files[key]
        if not file.exists():
            if not private:
                problems.append(Problem(key, f"frozen in {manifest['version']} but missing"))
            continue
        if sha256_file(file) != entry["sha256"]:
            problems.append(Problem(key, f"changed after the freeze ({manifest['version']}): a deliberate change "
                                         "needs `pairs freeze --version ... --reason ...` and the testset-change "
                                         "label on the PR (docs/DATA.md)"))
    return problems


def validate(pairs_dir: Path | None = None) -> Report:
    """Validate every pair file, then check ids, duplicates and test/dev leakage across files."""
    report = Report()
    located: list[tuple[str, dict]] = []
    files = pair_files(pairs_dir) + (pair_files(others=True) if pairs_dir is None else [])
    for path in files:
        try:
            split, method = expected_split(path)
        except ValueError as exc:
            report.errors.append(Problem(path.name, str(exc)))
            continue
        for n, row, line_error in read_jsonl(path):
            folder = "private/" if is_private(path) else "others/" if OTHERS_DIR in path.parents else ""
            where = f"{folder}{path.name}:{n}"
            if line_error:
                report.errors.append(Problem(where, line_error))
                continue
            where += f" {row.get('id', '?')}"
            report.errors += [Problem(where, e) for e in row_errors(row, split, method)]
            report.rows.append(row)
            located.append((where, row))

    seen_ids: dict[str, str] = {}
    held_out: dict[str, str] = {}  # normalized text of test/dev rows -> where
    for where, row in located:
        if row.get("id") in seen_ids:
            report.errors.append(Problem(where, f"duplicate id (first at {seen_ids[row['id']]})"))
        seen_ids.setdefault(row.get("id"), where)
        if row.get("split") in ("test", "dev"):
            for key in _dedupe_keys(row):
                if key in held_out:
                    report.errors.append(Problem(where, f"duplicate of held-out row {held_out[key]}"))
                held_out.setdefault(key, where)

    splits = {row["id"]: row["split"] for _, row in located if "id" in row and "split" in row}
    for where, row in located:
        if row.get("split") == "train":
            for key in _dedupe_keys(row):
                if key in held_out:
                    report.errors.append(Problem(where, f"train row leaks held-out row {held_out[key]}"))
        parent = row.get("parent")
        if parent and splits.get(parent) != "train":
            report.errors.append(Problem(where, f"parent {parent} is missing or not a train row"))
    if pairs_dir is None:
        report.errors += freeze_problems() + freeze_problems(others=True)
    return report


def _dedupe_keys(row: dict) -> set[str]:
    keys = set()
    if isinstance(row.get("arabic"), str):
        keys.add("ar:" + normalize_arabic(row["arabic"], lenient=True))
    if isinstance(row.get("arabizi"), str):
        keys.add("az:" + normalize_arabizi(row["arabizi"]))
    return keys
