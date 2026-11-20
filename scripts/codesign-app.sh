#!/bin/sh
# Sign AppleSign.app inside-out: the applesign helper first (node needs JIT
# under the hardened runtime), then the app bundle.
#
#   scripts/codesign-app.sh path/to/AppleSign.app ["Developer ID Application: ..." | -]
set -e
APP=$1
ID=${2:--}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OPTS="--force --options runtime"
[ "$ID" = - ] || OPTS="$OPTS --timestamp"
[ -n "$KEYCHAIN" ] && OPTS="$OPTS --keychain $KEYCHAIN"

codesign $OPTS --entitlements "$ROOT/Config/applesign-helper.entitlements" \
  --sign "$ID" "$APP/Contents/Helpers/applesign"
codesign $OPTS --entitlements "$ROOT/Config/AppleSign.entitlements" --sign "$ID" "$APP"
codesign --verify --strict --deep --verbose=1 "$APP"
