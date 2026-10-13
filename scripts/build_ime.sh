#!/usr/bin/env bash
# Build build/ArabiziIME.app from the Swift package (ADR 0013). Ad-hoc signed: no Developer ID (A5).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Apps/ArabiziIME"
APP="$ROOT/build/ArabiziIME.app"

swift build -c release --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/ArabiziIME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ArabiziIME"
cp "$PKG/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
swift "$PKG/Tools/make_icon.swift" "$APP/Contents/Resources/MenuIcon.tiff"
codesign --force --sign - "$APP"
echo "Built $APP"
