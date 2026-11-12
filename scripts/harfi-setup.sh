#!/bin/bash
# Finishes installing Harfi for this macOS user (run by scripts/install_harfi.sh; it ships inside the app as
# Contents/Resources/harfi-setup.sh, so it can be run again to add or repair the model). No admin password and no developer tools needed.
#
# 1. Signs the app on this Mac (ad hoc, as built), registers it with macOS and turns it on, so Harfi converts on its
#    rules straight away.
# 2. Downloads the model named in Contents/Resources/model-download.txt into ~/Library/Caches/Harfi, resuming a
#    dropped download, and checks its SHA-256. The settings window shows how far it has got.
# 3. Puts it inside the engine service (the sandboxed service may read only its own bundle, ADR 0020), signs the app
#    again so macOS accepts the bundle with the model in it, and restarts the keyboard, which then uses the model.
# A model already downloaded (or HARFI_MODEL_FROM) goes in at step 1.
#
# Without a published model (an HTTP 404), it installs on the rules alone and says how to add the model later.
#
# Usage: harfi-setup.sh [path/to/ArabiziIME.app]   (default: ~/Library/Input Methods/ArabiziIME.app)
#        HARFI_MODEL_FROM=/folder harfi-setup.sh     take the model from a local folder instead of downloading it
set -euo pipefail
APP="${1:-$HOME/Library/Input Methods/ArabiziIME.app}"
XPC="$APP/Contents/XPCServices/ArabiziEngineXPC.xpc"
INFO="$APP/Contents/Resources/model-download.txt"
[ -d "$XPC" ] && [ -f "$INFO" ] || { echo "Harfi is not installed at $APP"; exit 1; }
# shellcheck source=/dev/null
. "$INFO"  # MODEL_FILE, MODEL_ASSET, MODEL_SHA256, MODEL_SIZE, MODEL_URL

CACHE="$HOME/Library/Caches/Harfi"
MODEL="$CACHE/$MODEL_ASSET"
mkdir -p "$CACHE"

checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Puts the model (when given) inside the engine service, signs the app and registers it. The keyboard and the service
# are stopped first; macOS starts them again on the next key.
install_app() {
  pkill -x ArabiziIME 2>/dev/null || true
  pkill -x ArabiziEngineXPC 2>/dev/null || true
  if [ -n "${1:-}" ]; then
    rm -f "$XPC/Contents/Resources/"*.gguf
    cp -c "$1" "$XPC/Contents/Resources/$MODEL_FILE" 2>/dev/null || cp "$1" "$XPC/Contents/Resources/$MODEL_FILE"
  fi
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
  # Inside out, as scripts/build_ime.sh does; the service keeps its sandbox entitlements (no network).
  codesign --force --sign - --preserve-metadata=entitlements "$XPC"
  codesign --force --sign - "$APP"
  "$APP/Contents/MacOS/harfi-register" "$APP"
}

if [ -f "$MODEL" ] && [ "$(checksum "$MODEL")" = "$MODEL_SHA256" ]; then
  echo "Model already downloaded."
  install_app "$MODEL"
  exit 0
elif [ -n "${HARFI_MODEL_FROM:-}" ]; then
  cp -c "$HARFI_MODEL_FROM/$MODEL_ASSET" "$MODEL" 2>/dev/null || cp "$HARFI_MODEL_FROM/$MODEL_ASSET" "$MODEL"
  [ "$(checksum "$MODEL")" = "$MODEL_SHA256" ] || { rm -f "$MODEL"; echo "The model in $HARFI_MODEL_FROM does not match its SHA-256."; exit 1; }
  install_app "$MODEL"
  exit 0
fi

# No model yet: Harfi goes on now and works on its rules while the model downloads.
install_app
if [ "$(curl -sIL -o /dev/null -w '%{http_code}' "$MODEL_URL.part01")" = "404" ]; then
  echo "The model is not published yet, so Harfi uses its rules for now (less accurate)."
  echo "When it is, run: \"$APP/Contents/Resources/harfi-setup.sh\""
  exit 0
fi
echo
echo "You can type with Harfi now: it uses its rules (less accurate) until the model arrives."
echo "Downloading the model ($((MODEL_SIZE / 1000000)) MB in $MODEL_PARTS parts). Keep this window open."
echo "If the connection drops, it carries on where it stopped, even if you run the installer again later."
: > "$MODEL.part"
for n in $(seq -f "%02g" 1 "$MODEL_PARTS"); do
  piece="$CACHE/$MODEL_ASSET.part$n"
  expected=$(( MODEL_SIZE - (10#$n - 1) * 104857600 ))
  [ "$expected" -gt 104857600 ] && expected=104857600
  if [ -f "$piece" ] && [ "$(stat -f %z "$piece")" -eq "$expected" ]; then continue; fi  # done in an earlier run
  echo "Part $n of $MODEL_PARTS"
  # A silent connection counts as dropped after 30 s below 5 KB/s; each new try resumes the partial part.
  for attempt in $(seq 1 50); do
    curl -L --fail -C - --speed-limit 5000 --speed-time 30 --progress-bar -o "$piece" "$MODEL_URL.part$n" && break
    [ "$attempt" = 50 ] && { echo "The download keeps failing. Run the installer again later: it resumes."; exit 1; }
    echo "Connection dropped (try $attempt), resuming in 3 s..."
    sleep 3
  done
done
for n in $(seq -f "%02g" 1 "$MODEL_PARTS"); do cat "$CACHE/$MODEL_ASSET.part$n" >> "$MODEL.part"; done
mv "$MODEL.part" "$MODEL"
rm -f "$CACHE/$MODEL_ASSET".part[0-9]*
if [ "$(checksum "$MODEL")" != "$MODEL_SHA256" ]; then
  rm -f "$MODEL"
  echo "The model download is damaged (checksum differs). Run the installer again to download it again."
  exit 1
fi
echo "Model downloaded. Harfi restarts to use it: if you were typing, press a key again."
install_app "$MODEL" > /dev/null 2>&1
