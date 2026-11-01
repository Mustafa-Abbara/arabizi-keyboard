#!/bin/bash
# Finishes installing Harfi for this macOS user (run by scripts/install_harfi.sh and by the Homebrew cask; it
# ships inside the app as Contents/Resources/harfi-setup.sh). No admin password and no developer tools needed.
#
# 1. Downloads the model named in Contents/Resources/model-download.txt into ~/Library/Caches/Harfi, resuming a
#    dropped download, and checks its SHA-256.
# 2. Puts it inside the engine service: the sandboxed service may read only its own bundle (ADR 0020).
# 3. Signs the app again on this Mac (ad hoc, as built) so macOS accepts the bundle with the model in it.
# 4. Registers the app with macOS.
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

if [ -f "$MODEL" ] && [ "$(checksum "$MODEL")" = "$MODEL_SHA256" ]; then
  echo "Model already downloaded."
elif [ -n "${HARFI_MODEL_FROM:-}" ]; then
  cp -c "$HARFI_MODEL_FROM/$MODEL_ASSET" "$MODEL" 2>/dev/null || cp "$HARFI_MODEL_FROM/$MODEL_ASSET" "$MODEL"
elif [ "$(curl -sIL -o /dev/null -w '%{http_code}' "$MODEL_URL.part01")" = "404" ]; then
  # The release has no model yet: Harfi works on the rules alone until it is added.
  echo "The model is not published yet, so Harfi uses its rules for now (less accurate)."
  echo "When it is, run: \"$APP/Contents/Resources/harfi-setup.sh\""
  MODEL=""
else
  echo "Downloading the model ($((MODEL_SIZE / 1000000)) MB in $MODEL_PARTS parts)."
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
fi
if [ -n "$MODEL" ] && [ "$(checksum "$MODEL")" != "$MODEL_SHA256" ]; then
  rm -f "$MODEL" "$CACHE/$MODEL_ASSET".part[0-9]*
  echo "The model download is damaged (checksum differs). Run the installer again to download it again."
  exit 1
fi

pkill -x ArabiziIME 2>/dev/null || true
pkill -x ArabiziEngineXPC 2>/dev/null || true
if [ -n "$MODEL" ]; then
  rm -f "$XPC/Contents/Resources/"*.gguf
  cp -c "$MODEL" "$XPC/Contents/Resources/$MODEL_FILE" 2>/dev/null || cp "$MODEL" "$XPC/Contents/Resources/$MODEL_FILE"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
# Inside out, as scripts/build_ime.sh does; the service keeps its sandbox entitlements (no network).
codesign --force --sign - --preserve-metadata=entitlements "$XPC"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/harfi-register" "$APP"
