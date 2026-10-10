"""Check that this machine has the tools the project needs.

Usage:  python scripts/doctor.py
Exit code 0 if every tool required on this OS is present, 1 otherwise.
Works on macOS and Windows; macOS-only tools are skipped on other systems.
"""
from __future__ import annotations

import platform
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 12)

# (command, version args, needed on: "all" | "macos", why)
TOOLS = [
    ("git", ["--version"], "all", "version control"),
    ("gh", ["--version"], "all", "GitHub CLI: issues, PRs, bootstrap script"),
    ("uv", ["--version"], "all", "Python env manager for eval/ (S4+)"),
    ("pre-commit", ["--version"], "all", "local secret/large-file guards"),
    ("docker", ["--version"], "all", "local Jaeger/Langfuse stack (S9)"),
    ("swift", ["--version"], "macos", "Swift toolchain"),
    ("xcodebuild", ["-version"], "macos", "Xcode builds (IME, XPC)"),
    ("swiftlint", ["version"], "macos", "Swift lint (CI gate)"),
    ("swiftformat", ["--version"], "macos", "Swift formatting"),
    ("cmake", ["--version"], "macos", "building KenLM / llama.cpp tools"),
]


def first_line(cmd: list[str]) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"error: {exc}"
    text = (out.stdout or out.stderr).strip()
    return text.splitlines()[0] if text else "(no output)"


def main() -> int:
    is_macos = platform.system() == "Darwin"
    print(f"OS: {platform.system()} {platform.release()} ({platform.machine()})\n")

    missing: list[str] = []
    py_ok = sys.version_info >= MIN_PYTHON
    print(f"{'OK' if py_ok else 'MISSING':8} python      {platform.python_version()} (need >= {'.'.join(map(str, MIN_PYTHON))})")
    if not py_ok:
        missing.append("python")

    for name, args, needed_on, why in TOOLS:
        if needed_on == "macos" and not is_macos:
            print(f"{'SKIP':8} {name:11} macOS only: {why}")
            continue
        path = shutil.which(name)
        if path is None:
            print(f"{'MISSING':8} {name:11} {why}")
            missing.append(name)
        else:
            print(f"{'OK':8} {name:11} {first_line([path, *args])}")

    print()
    if missing:
        print("Missing: " + ", ".join(missing) + ". See docs/process/S0_SETUP.md for install commands.")
        return 1
    print("All required tools found. Remaining S0 check: `docker run hello-world` must succeed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
