#!/usr/bin/env bash
# Builds a Harfi release into dist/, uploading nothing:
#   Harfi-<version>.zip   the app without the model (installers add it, scripts/harfi-setup.sh)
#   SHA256SUMS            its checksum, read by scripts/install_harfi.sh
#   harfi.rb              the Homebrew cask for that zip (packaging/homebrew/harfi.rb.in)
#   model/                the model under its published name with the Llama 3.2 licence, when models/ has it:
#                         uploaded separately, once, to the model-<version> release (docs/INSTALL.md)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Apps/ArabiziIME/Resources/Info.plist")"
APP="$ROOT/build/ArabiziIME.app"
ZIP="Harfi-$VERSION.zip"

HARFI_NO_MODEL=1 "$ROOT/scripts/build_ime.sh"
rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/$ZIP"
(cd "$DIST" && shasum -a 256 "$ZIP" > SHA256SUMS)
SHA="$(cut -d' ' -f1 "$DIST/SHA256SUMS")"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" "$ROOT/packaging/homebrew/harfi.rb.in" > "$DIST/harfi.rb"

# shellcheck source=/dev/null
. "$APP/Contents/Resources/model-download.txt"
if [ -f "$ROOT/models/$MODEL_FILE" ]; then
  mkdir -p "$DIST/model"
  cp -c "$ROOT/models/$MODEL_FILE" "$DIST/model/$MODEL_ASSET" 2>/dev/null || cp "$ROOT/models/$MODEL_FILE" "$DIST/model/$MODEL_ASSET"
  cp "$ROOT/NOTICE" "$DIST/model/"
  curl -fsSL -o "$DIST/model/LLAMA_3.2_LICENSE.txt" \
    https://raw.githubusercontent.com/meta-llama/llama-models/main/models/llama3_2/LICENSE \
    || echo "Could not fetch the Llama 3.2 licence: add LLAMA_3.2_LICENSE.txt to dist/model before uploading"
  echo "Model for the model release: dist/model/$MODEL_ASSET"
fi
echo "Release $VERSION in $DIST: $ZIP ($SHA)"
