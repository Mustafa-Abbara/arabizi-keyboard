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
cp "$(dirname "$BIN")/harfi-register" "$APP/Contents/MacOS/"  # registers the installed app with macOS
cp "$PKG/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
swift "$PKG/Tools/make_icon.swift" "$APP/Contents/Resources/MenuIcon.tiff"
# The keyboard's own rule converter (used when the engine service cannot answer) and the engine settings.
cp "$ROOT/data/rules/arabizi_to_arabic.json" "$ROOT/data/rules/arabizi_lexicon.json" "$ROOT/data/rules/spelling_options.json" \
   "$ROOT/data/rules/english_stopwords.json" "$APP/Contents/Resources/"
cp "$ROOT/config/engine.json" "$ROOT/config/models.json" "$APP/Contents/Resources/"
# Installing on another Mac (scripts/install_harfi.sh): the setup script, where the model is
# published, and the model's licence notice. The model is published under a name that starts with "Llama", as the
# Llama 3.2 licence asks, in a release of its own (model-<version>), so every app version finds it.
cp "$ROOT/scripts/harfi-setup.sh" "$ROOT/NOTICE" "$APP/Contents/Resources/"
cp -R "$PKG/Resources/Fonts" "$APP/Contents/Resources/"  # Noto Naskh Arabic for the Arabic Harfi shows (SIL OFL 1.1)
python3 - "$ROOT/config" > "$APP/Contents/Resources/model-download.txt" <<'EOF'
import json, sys
engine = json.load(open(f"{sys.argv[1]}/engine.json"))
model = {m["id"]: m for m in json.load(open(f"{sys.argv[1]}/models.json"))["models"]}[engine["model"]]
version = model["id"].rsplit("-", 1)[-1]  # arabizi-llama3.2-1b-v3 -> v3
asset = f"Llama-3.2-1B-Harfi-{version}-{model['quant']}.gguf"
print(f'MODEL_FILE="{model["file"]}"')
print(f'MODEL_ASSET="{asset}"')
print(f'MODEL_SHA256="{model["sha256"]}"')
print(f'MODEL_SIZE="{model["size"]}"')
part = 100 * 1024 * 1024  # published in parts of 100 MiB: an interrupted upload or download repeats one part only
print(f'MODEL_PARTS="{-(-model["size"] // part)}"')
print(f'MODEL_URL="https://github.com/Mustafa-Abbara/arabizi-keyboard/releases/download/model-{version}/{asset}"')
EOF

# The engine service: its executable, llama.framework, and everything it reads (the sandbox lets it read only its
# own bundle): settings, rule files and the configured model file if it is in models/ (never committed).
mkdir -p "$XPC/Contents/MacOS" "$XPC/Contents/Resources" "$XPC/Contents/Frameworks"
cp "$XPC_BIN_DIR/ArabiziEngineXPC" "$XPC/Contents/MacOS/ArabiziEngineXPC"
cp "$XPC_PKG/Resources/Info.plist" "$XPC/Contents/Info.plist"
plutil -lint -s "$XPC/Contents/Info.plist"
cp -R "$XPC_BIN_DIR/llama.framework" "$XPC/Contents/Frameworks/"
cp "$ROOT/data/rules/arabizi_to_arabic.json" "$ROOT/data/rules/arabizi_lexicon.json" "$ROOT/data/rules/english_stopwords.json" \
   "$ROOT/data/rules/chat_abbreviations.json" "$XPC/Contents/Resources/"
cp "$ROOT/config/engine.json" "$ROOT/config/models.json" "$XPC/Contents/Resources/"
MODEL_FILE="$(python3 - "$ROOT/config" <<'EOF'
import json, sys
engine = json.load(open(f"{sys.argv[1]}/engine.json"))
models = {m["id"]: m for m in json.load(open(f"{sys.argv[1]}/models.json"))["models"]}
model = engine.get("model")
print(models[model]["file"] if model and engine["features"]["use_model"] else "")
EOF
)"
# HARFI_NO_MODEL=1 (release builds): no model in the app; the installer adds it (scripts/install_harfi.sh).
if [ -n "${HARFI_NO_MODEL:-}" ]; then
  echo "Engine model left out (HARFI_NO_MODEL): the installer adds $MODEL_FILE"
elif [ -n "$MODEL_FILE" ] && [ -f "$ROOT/models/$MODEL_FILE" ]; then
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
