#!/usr/bin/env bash
# Build build/ArabiziIME.app from the Swift packages (ADR 0013), with the sandboxed engine service inside it at
# Contents/XPCServices/ArabiziEngineXPC.xpc (ADR 0020). Ad-hoc signed: no Developer ID (A5).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Apps/ArabiziIME"
XPC_PKG="$ROOT/Apps/ArabiziEngineXPC"
APP="$ROOT/build/ArabiziIME.app"
XPC="$APP/Contents/XPCServices/ArabiziEngineXPC.xpc"

swift build -c release --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/ArabiziIME"
swift build -c release --package-path "$XPC_PKG"
XPC_BIN_DIR="$(swift build -c release --package-path "$XPC_PKG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ArabiziIME"
cp "$(dirname "$BIN")/arabizi-engine-check" "$APP/Contents/MacOS/"  # diagnostic: status, network probe, one sentence
cp "$PKG/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
swift "$PKG/Tools/make_icon.swift" "$APP/Contents/Resources/MenuIcon.tiff"
# The keyboard's own rule converter (used when the engine service cannot answer) and the engine settings.
cp "$ROOT/data/rules/arabizi_to_arabic.json" "$ROOT/data/rules/arabizi_lexicon.json" "$ROOT/data/rules/spelling_options.json" \
   "$ROOT/data/rules/english_stopwords.json" "$APP/Contents/Resources/"
cp "$ROOT/config/engine.json" "$ROOT/config/models.json" "$APP/Contents/Resources/"

# The engine service: its executable, llama.framework, and everything it reads (the sandbox lets it read only its
# own bundle): settings, rule files and the configured model file if it is in models/ (never committed).
mkdir -p "$XPC/Contents/MacOS" "$XPC/Contents/Resources" "$XPC/Contents/Frameworks"
cp "$XPC_BIN_DIR/ArabiziEngineXPC" "$XPC/Contents/MacOS/ArabiziEngineXPC"
cp "$XPC_PKG/Resources/Info.plist" "$XPC/Contents/Info.plist"
plutil -lint -s "$XPC/Contents/Info.plist"
cp -R "$XPC_BIN_DIR/llama.framework" "$XPC/Contents/Frameworks/"
cp "$ROOT/data/rules/arabizi_to_arabic.json" "$ROOT/data/rules/arabizi_lexicon.json" "$ROOT/data/rules/english_stopwords.json" \
   "$XPC/Contents/Resources/"
cp "$ROOT/config/engine.json" "$ROOT/config/models.json" "$XPC/Contents/Resources/"
MODEL_FILE="$(python3 - "$ROOT/config" <<'EOF'
import json, sys
engine = json.load(open(f"{sys.argv[1]}/engine.json"))
models = {m["id"]: m for m in json.load(open(f"{sys.argv[1]}/models.json"))["models"]}
model = engine.get("model")
print(models[model]["file"] if model and engine["features"]["use_model"] else "")
EOF
)"
if [ -n "$MODEL_FILE" ] && [ -f "$ROOT/models/$MODEL_FILE" ]; then
  cp -c "$ROOT/models/$MODEL_FILE" "$XPC/Contents/Resources/" 2>/dev/null || cp "$ROOT/models/$MODEL_FILE" "$XPC/Contents/Resources/"
  echo "Engine model: $MODEL_FILE"
elif [ -n "$MODEL_FILE" ]; then
  echo "Engine model $MODEL_FILE not in models/: the engine will use the rules (docs/MODELS.md)"
fi

# Sign from the inside out: the framework, the service with its sandbox entitlements (no network), then the app.
codesign --force --sign - "$XPC/Contents/Frameworks/llama.framework"
codesign --force --sign - --entitlements "$XPC_PKG/Resources/ArabiziEngineXPC.entitlements" "$XPC"
codesign --force --sign - "$APP"
echo "Built $APP"
