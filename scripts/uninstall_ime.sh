#!/usr/bin/env bash
# Remove the input method for the current macOS user.
set -euo pipefail
pkill -x ArabiziIME 2>/dev/null || true
rm -rf "$HOME/Library/Input Methods/ArabiziIME.app"
echo "Removed. If it still shows in Input Sources, remove it there (−) or log out and back in."
