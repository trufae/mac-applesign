#!/bin/sh
# Build the node-applesign single executable (SEA) for darwin-arm64 and
# drop it at vendor/applesign, where the Xcode build phase picks it up.
#
#   scripts/build-applesign.sh [path/to/node-applesign]
#
# SEA needs an official (static) node >= 25.5. When the node in PATH is a
# shared build (Homebrew) the official darwin-arm64 tarball is fetched.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(cd "${1:-$ROOT/../node-applesign}" && pwd)
OUT=$ROOT/vendor/applesign
NODE_MAJOR=${NODE_MAJOR:-26}

usable_node() {
  command -v node >/dev/null || return 1
  [ "$(node -p 'process.arch')" = arm64 ] || return 1
  node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>25||(a==25&&b>=5)?0:1)' || return 1
  ! otool -L "$(command -v node)" | grep -q libnode
}

if ! usable_node; then
  CACHE=$ROOT/.cache
  V=$(curl -fsSL https://nodejs.org/dist/index.json |
    python3 -c "import json,sys;print(next(x['version'] for x in json.load(sys.stdin) if x['version'].startswith('v$NODE_MAJOR.')))")
  DIR=$CACHE/node-$V-darwin-arm64
  if [ ! -x "$DIR/bin/node" ]; then
    echo "[*] Fetching official node $V"
    mkdir -p "$CACHE"
    curl -fsSL "https://nodejs.org/dist/$V/node-$V-darwin-arm64.tar.xz" | tar -xJ -C "$CACHE"
  fi
  PATH=$DIR/bin:$PATH
  export PATH
fi
echo "[*] Using node $(node --version) at $(command -v node)"

cd "$SRC"
[ -d node_modules ] || npm ci
npm run dist
BIN=$(ls -t applesign-*-darwin-arm64 | head -n 1)
mkdir -p "$(dirname "$OUT")"
cp -f "$BIN" "$OUT"
"$OUT" --version
echo "[+] $OUT"
