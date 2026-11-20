#!/bin/sh
# Xcode build phase: copy the applesign SEA binary into Contents/Helpers.
# Looks at $APPLESIGN_BIN, then vendor/applesign (scripts/build-applesign.sh).
SRC=${APPLESIGN_BIN:-$SRCROOT/vendor/applesign}
DST=$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/applesign
if [ ! -x "$SRC" ]; then
  echo "warning: applesign binary not found at $SRC, run scripts/build-applesign.sh"
  exit 0
fi
mkdir -p "$(dirname "$DST")"
ditto "$SRC" "$DST"
if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
  # node needs JIT, so the hardened runtime requires these entitlements
  codesign --force --options runtime --timestamp=none \
    --entitlements "$SRCROOT/Config/applesign-helper.entitlements" \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DST"
fi
