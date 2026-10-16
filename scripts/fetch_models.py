#!/usr/bin/env python3
"""Download the pinned model files in config/models.json into models/ and check their SHA-256 (docs/MODELS.md).

  python3 scripts/fetch_models.py --list                    # what would be fetched, no network
  python3 scripts/fetch_models.py                           # all models that need no licence acceptance
  python3 scripts/fetch_models.py --accept-licence gemma --accept-licence llama   # also Gemma and Llama
  python3 scripts/fetch_models.py --only qwen2.5-0.5b       # one model

Files are pinned to a repository revision, downloaded to a .part file, checked, then renamed. A file that is
already present with the right hash is skipped. Standard library only; models/ is never committed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "models.json"
MODELS_DIR = ROOT / "models"
CHUNK = 1 << 20


def load_manifest(path: Path = MANIFEST) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["models"]


def url_for(entry: dict) -> str:
    return f"https://huggingface.co/{entry['repo']}/resolve/{entry['revision']}/{entry['file']}"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while block := f.read(CHUNK):
            digest.update(block)
    return digest.hexdigest()


def plan(entries: list[dict], only: list[str], accepted: set[str]) -> tuple[list[dict], list[str]]:
    """(entries to fetch, reasons for skipping others)."""
    unknown = set(only) - {e["id"] for e in entries}
    if unknown:
        raise SystemExit(f"unknown model id(s): {', '.join(sorted(unknown))}")
    chosen, skipped = [], []
    for entry in entries:
        if only and entry["id"] not in only:
            continue
        if "repo" not in entry:  # fine-tuned (P4): from the private Kaggle output, not Hugging Face
            skipped.append(f"{entry['id']}: fine-tuned, copy it from the Kaggle output (docs/TRAINING.md)")
            continue
        needs = entry.get("licence_acceptance")
        if needs and needs not in accepted:
            skipped.append(f"{entry['id']}: needs --accept-licence {needs} ({entry['licence']})")
            continue
        chosen.append(entry)
    return chosen, skipped


class FetchError(RuntimeError):
    pass


def _download(entry: dict, part: Path) -> None:
    """Download into `part`, resuming from its current size (HTTP Range) if it already has bytes."""
    have = part.stat().st_size if part.exists() else 0
    request = urllib.request.Request(url_for(entry), headers={"Range": f"bytes={have}-"} if have else {})
    with urllib.request.urlopen(request, timeout=60) as response:
        if have and response.status != 206:  # server ignored the range: start over
            have = 0
        with part.open("ab" if have else "wb") as out:
            done = have
            while block := response.read(CHUNK):
                out.write(block)
                done += len(block)
                print(f"\r  {entry['id']}: {done / 1e6:,.0f} / {entry['size'] / 1e6:,.0f} MB", end="", flush=True)
    print()


def fetch(entry: dict, models_dir: Path = MODELS_DIR, attempts: int = 3) -> str:
    target = models_dir / entry["file"]
    if target.exists() and sha256_of(target) == entry["sha256"]:
        return "already present"
    models_dir.mkdir(parents=True, exist_ok=True)
    part = target.with_suffix(target.suffix + ".part")
    for attempt in range(1, attempts + 1):
        try:
            _download(entry, part)
        except OSError as exc:  # network errors: keep the partial file and resume
            print(f"\n  {entry['id']}: attempt {attempt} interrupted ({exc}); resuming")
            continue
        size = part.stat().st_size
        if size < entry["size"]:
            print(f"  {entry['id']}: attempt {attempt} stopped early ({size:,} of {entry['size']:,} bytes); resuming")
            continue
        actual = sha256_of(part)
        if size == entry["size"] and actual == entry["sha256"]:
            part.rename(target)
            return "downloaded and verified" + ("" if attempt == 1 else f" (attempt {attempt})")
        print(f"  {entry['id']}: attempt {attempt}: {size:,} bytes, SHA-256 {actual[:16]}… does not match; "
              "starting over")
        part.unlink()
    raise FetchError(f"{entry['id']}: could not get a verified copy in {attempts} attempts")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="show the plan and exit (no network)")
    parser.add_argument("--only", action="append", default=[], help="model id; repeat for several")
    parser.add_argument("--accept-licence", action="append", default=[], choices=["gemma", "llama"],
                        help="confirm you accept that model family's licence (see docs/MODELS.md)")
    args = parser.parse_args(argv)

    chosen, skipped = plan(load_manifest(), args.only, set(args.accept_licence))
    total = sum(e["size"] for e in chosen)
    print(f"{len(chosen)} model file(s), {total / 1e9:.2f} GB, into {MODELS_DIR.relative_to(ROOT)}/")
    for entry in chosen:
        print(f"  {entry['id']:13} {entry['size'] / 1e9:5.2f} GB  {entry['repo']}  ({entry['licence']})")
    for reason in skipped:
        print(f"  skipped {reason}")
    if args.list:
        return 0
    failed = []
    for entry in chosen:
        try:
            print(f"{entry['id']}: {fetch(entry)}")
        except FetchError as exc:
            print(f"FAILED {exc}")
            failed.append(entry["id"])
    if failed:
        print(f"{len(failed)} file(s) not verified: {', '.join(failed)}. Run the script again to retry.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
