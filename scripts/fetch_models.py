#!/usr/bin/env python3
"""Download the pinned model files in config/models.json into models/ and check their SHA-256 (docs/MODELS.md).

  python3 scripts/fetch_models.py --list                    # what would be fetched, no network
  python3 scripts/fetch_models.py                           # all models that need no licence acceptance
  python3 scripts/fetch_models.py --accept-licence gemma --accept-licence llama   # also Gemma and Llama
  python3 scripts/fetch_models.py --only qwen2.5-0.5b       # one model
  python3 scripts/fetch_models.py --shipped --accept-licence llama   # Harfi's own model (config/engine.json)

Files are pinned to a repository revision, downloaded to a .part file, checked, then renamed. A file that is
already present with the right hash is skipped. Standard library only; models/ is never committed.

--shipped: the model Harfi ships (the one config/engine.json selects), from its own GitHub release (model-<version>),
in parts of 100 MiB, as the installers get it: each part is checked against the release's list, the parts are
joined and the whole file is checked against config/models.json. Parts already complete are kept, so a dropped
connection resumes.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "models.json"
ENGINE = ROOT / "config" / "engine.json"
RELEASES = "https://github.com/Mustafa-Abbara/arabizi-keyboard/releases/download"
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
        if "repo" not in entry:  # fine-tuned (P4): from the Kaggle run's output, not Hugging Face
            skipped.append(f"{entry['id']}: fine-tuned; the shipped one comes with --shipped, the others from "
                           "their training run's output (docs/TRAINING.md)")
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


def shipped_entry(entries: list[dict] | None = None) -> dict:
    """The model config/engine.json selects."""
    chosen = json.loads(ENGINE.read_text(encoding="utf-8"))["model"]
    return next(e for e in (entries or load_manifest()) if e["id"] == chosen)


def release_asset(entry: dict) -> tuple[str, str]:
    """(release folder URL, asset name) of a shipped model, named as the installers name it (scripts/build_ime.sh)."""
    version = entry["id"].rsplit("-", 1)[-1]  # arabizi-llama3.2-1b-v5 -> v5
    return f"{RELEASES}/model-{version}", f"Llama-3.2-1B-Harfi-{version}-{entry['quant']}.gguf"


def _windows_curl() -> Path | None:
    curl = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "curl.exe"
    return curl if sys.platform == "win32" and curl.exists() else None


def _get_with_windows(url: str, part: Path, label: str) -> None:
    """Download with Windows' own curl.exe, which checks the certificate the way Windows does. Python checks it
    against the certificates already on the computer and cannot fetch a missing intermediate; some of GitHub's
    servers send a chain that needs one (found by the drill, 22 Nov 2026: "unable to get issuer certificate",
    now and then). Resumes like _get; the certificate is still checked."""
    print(f"  {label}: Python could not check the server's certificate; using Windows' curl.exe")
    done = subprocess.run([str(_windows_curl()), "-sS", "-L", "--fail", "-C", "-", "--retry", "3",
                           "-o", str(part), url], check=False)
    if done.returncode != 0:
        raise OSError(f"curl.exe exit code {done.returncode}")


def _get(url: str, part: Path, label: str) -> None:
    """Download `url` into `part`, resuming from its current size (HTTP Range)."""
    have = part.stat().st_size if part.exists() else 0
    request = urllib.request.Request(url, headers={"Range": f"bytes={have}-"} if have else {})
    try:
        response = urllib.request.urlopen(request, timeout=60)
    except urllib.error.HTTPError as exc:
        if exc.code == 416:  # the part is already complete
            return
        raise
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, ssl.SSLCertVerificationError) and _windows_curl():
            _get_with_windows(url, part, label)
            return
        raise
    with response:
        if have and response.status != 206:  # the server ignored the range: start over
            have = 0
        with part.open("ab" if have else "wb") as out:
            done = have
            while block := response.read(CHUNK):
                out.write(block)
                done += len(block)
                print(f"\r  {label}: {done / 1e6:,.0f} MB", end="", flush=True)
    print()


def fetch_shipped(entry: dict, models_dir: Path = MODELS_DIR, attempts: int = 6, wait: float = 10.0) -> str:
    """The shipped model from its release: each part checked, then joined and the whole checked."""
    target = models_dir / entry["file"]
    if target.exists() and sha256_of(target) == entry["sha256"]:
        return "already present"
    folder, asset = release_asset(entry)
    version = entry["id"].rsplit("-", 1)[-1]
    parts_dir = models_dir / f"parts-{version}"
    parts_dir.mkdir(parents=True, exist_ok=True)
    listing = parts_dir / f"{asset}.parts.sha256"
    if not listing.exists():
        _get(f"{folder}/{asset}.parts.sha256", listing, "the parts list")
    parts = []
    for line in listing.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        expected, name = fields[0], fields[1].lstrip("*")
        part = parts_dir / name
        for attempt in range(1, attempts + 1):
            if part.exists() and sha256_of(part) == expected:
                break
            try:
                _get(f"{folder}/{name}", part, name)
            except (OSError, http.client.HTTPException) as exc:  # network drops: keep the partial part, resume
                pause = wait * attempt
                print(f"\n  {name}: attempt {attempt} interrupted ({exc}); resuming in {pause:.0f} s")
                time.sleep(pause)
                continue
            if sha256_of(part) != expected:
                print(f"  {name}: damaged; downloading it again")
                part.unlink()
        else:
            if not (part.exists() and sha256_of(part) == expected):
                raise FetchError(f"{name}: could not get a verified copy in {attempts} attempts; the parts "
                                 "already downloaded are kept, so running the same command again resumes")
        parts.append(part)
    joined = target.with_suffix(target.suffix + ".part")
    with joined.open("wb") as out:
        for part in parts:
            with part.open("rb") as f:
                while block := f.read(CHUNK):
                    out.write(block)
    if joined.stat().st_size != entry["size"] or sha256_of(joined) != entry["sha256"]:
        joined.unlink()
        raise FetchError(f"{entry['id']}: the joined file does not match config/models.json; run the script again")
    joined.rename(target)
    for leftover in parts_dir.iterdir():
        leftover.unlink()
    parts_dir.rmdir()
    return f"downloaded from model-{version} and verified"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="show the plan and exit (no network)")
    parser.add_argument("--only", action="append", default=[], help="model id; repeat for several")
    parser.add_argument("--accept-licence", action="append", default=[], choices=["gemma", "llama"],
                        help="confirm you accept that model family's licence (see docs/MODELS.md)")
    parser.add_argument("--shipped", action="store_true",
                        help="Harfi's own model (config/engine.json), from its GitHub release, instead")
    args = parser.parse_args(argv)

    if args.shipped:
        entry = shipped_entry()
        folder, asset = release_asset(entry)
        print(f"{entry['id']}: {entry['size'] / 1e9:.2f} GB from {folder}/{asset}.part* ({entry['licence']})")
        needs = entry.get("licence_acceptance")
        if needs and needs not in args.accept_licence:
            print(f"  needs --accept-licence {needs}")
            return 1
        if args.list:
            return 0
        try:
            print(f"{entry['id']}: {fetch_shipped(entry)}")
        except FetchError as exc:
            print(f"FAILED {exc}")
            return 1
        return 0

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
