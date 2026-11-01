#!/bin/bash
# Installs (or updates) Harfi for this macOS user from a GitHub release: no admin password, no developer tools.
#
#   curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash
#
# Options: --version 0.1.0 (default: the latest release), --from DIR (a local release folder, as made by
# scripts/package_release.sh), --uninstall (remove the app and the downloaded model; your corrections stay
# until you delete them in Harfi's window).
set -euo pipefail
REPO="Mustafa-Abbara/arabizi-keyboard"
VERSION="latest"
FROM=""
DEST="$HOME/Library/Input Methods"
APP="$DEST/ArabiziIME.app"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --from) FROM="$(cd "$2" && pwd)"; shift 2 ;;
    --uninstall)
      pkill -x ArabiziIME 2>/dev/null || true
      rm -rf "$APP" "$HOME/Library/Caches/Harfi"
      echo "Harfi removed. If it still shows in Input Sources, remove it there (−) or log out and back in."
      exit 0 ;;
    *) echo "Unknown option $1"; exit 2 ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ "$VERSION" = "latest" ]; then BASE="https://github.com/$REPO/releases/latest/download"
else BASE="https://github.com/$REPO/releases/download/v$VERSION"; fi

fetch() {  # name -> $WORK/name, from the local folder or the release
  if [ -n "$FROM" ]; then cp "$FROM/$1" "$WORK/$1"; return; fi
  curl -L --fail --retry 5 --retry-delay 3 --progress-bar -o "$WORK/$1" "$BASE/$1"
}

echo "Getting Harfi..."
fetch SHA256SUMS
ZIP="$(grep -oE 'Harfi-[0-9][0-9.]*\.zip' "$WORK/SHA256SUMS" | head -1)"
[ -n "$ZIP" ] || { echo "No Harfi app in this release."; exit 1; }
fetch "$ZIP"
(cd "$WORK" && grep " $ZIP\$" SHA256SUMS | shasum -a 256 -c --status) || { echo "The download is damaged. Try again."; exit 1; }

pkill -x ArabiziIME 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$APP"
ditto -x -k "$WORK/$ZIP" "$DEST"
echo "App installed in $DEST."
if [ -n "$FROM" ] && [ -d "$FROM/model" ]; then export HARFI_MODEL_FROM="$FROM/model"; fi  # package_release.sh
"$APP/Contents/Resources/harfi-setup.sh" "$APP"
cat <<'EOF'

Almost there: turn Harfi on once.
  System Settings → Keyboard → Input Sources → Edit… → + → Arabic → Harfi → Add
Then switch to it with Ctrl+Space (or the input menu in the menu bar) and type: kifak?
If Harfi is not in the list, log out and back in once.
EOF
