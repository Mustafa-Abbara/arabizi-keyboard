#!/usr/bin/env bash
# Publishes the engine's model to its own GitHub release (model-<version>) in parts of 100 MiB, with the Llama 3.2
# licence and NOTICE. A dropped connection repeats one part only, and running it again uploads just the parts
# GitHub does not have yet. Needs `gh` signed in, and the model in models/ (scripts/fetch_models.py).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="Mustafa-Abbara/arabizi-keyboard"
APP="$ROOT/build/ArabiziIME.app"
[ -f "$APP/Contents/Resources/model-download.txt" ] || HARFI_NO_MODEL=1 "$ROOT/scripts/build_ime.sh"
# shellcheck source=/dev/null
. "$APP/Contents/Resources/model-download.txt"
TAG="model-${MODEL_URL#*/download/model-}"
TAG="${TAG%%/*}"
SRC="$ROOT/models/$MODEL_FILE"
[ -f "$SRC" ] || { echo "No $SRC: fetch the model first (docs/MODELS.md)"; exit 1; }
[ "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" = "$MODEL_SHA256" ] || { echo "$SRC does not match config/models.json"; exit 1; }

PARTS="$ROOT/build/model-parts"  # not dist/: scripts/package_release.sh empties that
mkdir -p "$PARTS"
if [ ! -f "$PARTS/$MODEL_ASSET.part01" ]; then
  split -b 100m -a 2 -d "$SRC" "$PARTS/$MODEL_ASSET.part"  # .part00, .part01, ... renamed to start at 01
  for f in $(ls -r "$PARTS/$MODEL_ASSET".part[0-9][0-9]); do
    n=$((10#${f##*.part} + 1))
    mv "$f" "$PARTS/$MODEL_ASSET.part$(printf %02d "$n")"
  done
fi
cp "$ROOT/NOTICE" "$PARTS/"
[ -f "$PARTS/LLAMA_3.2_LICENSE.txt" ] || curl -fsSL -o "$PARTS/LLAMA_3.2_LICENSE.txt" \
  https://raw.githubusercontent.com/meta-llama/llama-models/main/models/llama3_2/LICENSE
(cd "$PARTS" && shasum -a 256 "$MODEL_ASSET".part* > "$MODEL_ASSET.parts.sha256")

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$REPO" --title "Harfi model ${TAG#model-}" --latest=false --notes \
"The conversion model Harfi downloads when it is installed: a fine-tune of Llama 3.2 1B Instruct (Q4_K_M, $MODEL_SIZE bytes, SHA-256 \`$MODEL_SHA256\`), in parts of 100 MiB that the installer joins and checks.

Built with Llama. Llama 3.2 is licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved. See LLAMA_3.2_LICENSE.txt and NOTICE."
fi

uploaded() {  # name and size of each asset already on GitHub
  gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[] | "\(.name) \(.size)"'
}
for file in "$PARTS"/*; do
  name="$(basename "$file")" size="$(stat -f %z "$file")"
  if uploaded | grep -qx "$name $size"; then echo "already there: $name"; continue; fi
  for attempt in $(seq 1 50); do
    echo "uploading $name (try $attempt)"
    gh release upload "$TAG" "$file" --repo "$REPO" --clobber && break
    [ "$attempt" = 50 ] && { echo "Upload keeps failing; run this script again later to continue."; exit 1; }
    sleep 10
  done
done
echo "Model release $TAG complete."
