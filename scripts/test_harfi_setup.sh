#!/usr/bin/env bash
# Tests scripts/harfi-setup.sh against a local web server (docs/FAILURE_MATRIX.md): a model not published yet
# (HTTP 404), a download in parts, a part resumed after a dropped connection, and a damaged download. Uses a tiny
# fake app bundle and a throwaway home folder; like a real install it restarts a running Harfi. macOS only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/www"

# A web server that honours byte ranges, as GitHub's does (curl -C - resumes with them).
cat > "$WORK/server.py" <<'EOF'
import http.server, os, re, sys
class Ranged(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
    def send_head(self):
        path = self.translate_path(self.path)
        match = re.match(r"bytes=(\d+)-", self.headers.get("Range", ""))
        if not os.path.isfile(path) or not match:
            return super().send_head()
        size, start = os.path.getsize(path), int(match.group(1))
        if start >= size:
            self.send_error(416)
            return None
        handle = open(path, "rb")
        handle.seek(start)
        self.send_response(206)
        self.send_header("Content-Range", f"bytes {start}-{size - 1}/{size}")
        self.send_header("Content-Length", str(size - start))
        self.end_headers()
        return handle
os.chdir(sys.argv[1])
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), Ranged).serve_forever()
EOF
PORT=$((20000 + RANDOM % 20000))
python3 "$WORK/server.py" "$WORK/www" "$PORT" &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

MODEL="$WORK/model.bin"
head -c 3000 /dev/urandom > "$MODEL"
SHA="$(shasum -a 256 "$MODEL" | cut -d' ' -f1)"

write_plist() {  # path, executable name
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>$2</string>
<key>CFBundleIdentifier</key><string>test.harfi.$2</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
EOF
}

make_app() {  # a minimal app with an engine service, signable ad hoc, with a stand-in register tool
  local app="$WORK/Harfi.app"
  rm -rf "$app"
  local xpc="$app/Contents/XPCServices/ArabiziEngineXPC.xpc"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$xpc/Contents/MacOS" "$xpc/Contents/Resources"
  cp /usr/bin/true "$app/Contents/MacOS/Harfi"
  cp /usr/bin/true "$xpc/Contents/MacOS/ArabiziEngineXPC"
  cp /usr/bin/true "$app/Contents/MacOS/harfi-register"  # signed code, as the real tool is: registers nothing
  write_plist "$app/Contents/Info.plist" Harfi
  write_plist "$xpc/Contents/Info.plist" ArabiziEngineXPC
  cat > "$app/Contents/Resources/model-download.txt" <<EOF
MODEL_FILE="model.gguf"
MODEL_ASSET="Test-model.gguf"
MODEL_SHA256="$SHA"
MODEL_SIZE="3000"
MODEL_PARTS="1"
MODEL_URL="http://127.0.0.1:$PORT/Test-model.gguf"
EOF
  echo "$app"
}

pass=0
check() {  # name, condition result
  if [ "$2" = 0 ]; then echo "ok    $1"; pass=$((pass + 1)); else echo "FAIL  $1"; exit 1; fi
}

# 1. The model is not published yet: install on the rules alone, no model, success.
APP="$(make_app)"
out="$(bash "$ROOT/scripts/harfi-setup.sh" "$APP" 2>&1)"
grep -q "not published yet" <<<"$out" && [ ! -e "$APP/Contents/XPCServices/ArabiziEngineXPC.xpc/Contents/Resources/model.gguf" ]
check "a model not published yet installs on the rules" $?

# 2. A part resumed after a dropped connection: 1,000 bytes already in the cache, the rest downloaded.
cp "$MODEL" "$WORK/www/Test-model.gguf.part01"
mkdir -p "$HOME/Library/Caches/Harfi"
head -c 1000 "$MODEL" > "$HOME/Library/Caches/Harfi/Test-model.gguf.part01"
APP="$(make_app)"
bash "$ROOT/scripts/harfi-setup.sh" "$APP" > /dev/null 2>&1
cmp -s "$MODEL" "$APP/Contents/XPCServices/ArabiziEngineXPC.xpc/Contents/Resources/model.gguf"
check "a part resumed after a dropped connection gives the right model" $?
codesign --verify "$APP/Contents/XPCServices/ArabiziEngineXPC.xpc" 2>/dev/null
check "the engine service is signed again with the model inside" $?

# 3. Already downloaded: nothing is fetched again.
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""
APP="$(make_app)"
out="$(bash "$ROOT/scripts/harfi-setup.sh" "$APP" 2>&1)"
grep -q "already downloaded" <<<"$out"
check "a model already in the cache is not downloaded again" $?

# 4. A damaged download: the checksum differs, the cache is emptied and the script fails.
python3 "$WORK/server.py" "$WORK/www" "$PORT" &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
rm -f "$HOME/Library/Caches/Harfi/"*
head -c 3000 /dev/urandom > "$WORK/www/Test-model.gguf.part01"
APP="$(make_app)"
set +e
out="$(bash "$ROOT/scripts/harfi-setup.sh" "$APP" 2>&1)"; status=$?
set -e
[ "$status" -ne 0 ] && grep -q "damaged" <<<"$out" && [ -z "$(ls "$HOME/Library/Caches/Harfi")" ]
check "a damaged download is refused and removed" $?

echo "$pass checks passed"
