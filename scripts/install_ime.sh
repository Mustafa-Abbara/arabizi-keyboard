#!/usr/bin/env bash
# Install the input method for the current macOS user. Test on a second user account first (docs/SETUP_IME.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Input Methods"

"$ROOT/scripts/build_ime.sh"
pkill -x ArabiziIME 2>/dev/null || true   # the running copy is replaced; macOS restarts it on next use
pkill -x ArabiziEngineXPC 2>/dev/null || true   # and its engine service
mkdir -p "$DEST"
rm -rf "$DEST/ArabiziIME.app"
# APFS clone: the app holds the 0.8 GB model, so a plain copy would be slow and double the disk use.
cp -Rc "$ROOT/build/ArabiziIME.app" "$DEST/" 2>/dev/null || cp -R "$ROOT/build/ArabiziIME.app" "$DEST/"
swift "$ROOT/Apps/ArabiziIME/Tools/register.swift" "$DEST/ArabiziIME.app"
