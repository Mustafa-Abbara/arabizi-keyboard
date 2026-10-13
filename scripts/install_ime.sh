#!/usr/bin/env bash
# Install the input method for the current macOS user. Test on a second user account first (docs/SETUP_IME.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Input Methods"

"$ROOT/scripts/build_ime.sh"
pkill -x ArabiziIME 2>/dev/null || true   # the running copy is replaced; macOS restarts it on next use
mkdir -p "$DEST"
rm -rf "$DEST/ArabiziIME.app"
cp -R "$ROOT/build/ArabiziIME.app" "$DEST/"
swift "$ROOT/Apps/ArabiziIME/Tools/register.swift" "$DEST/ArabiziIME.app"
echo
echo "Next: System Settings → Keyboard → Input Sources → Edit… → + → Arabic → \"Arabizi Keyboard\"."
echo "First install: if it is not listed, log out and back in once."
