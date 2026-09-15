#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
DISTRIBUTION=false
if [[ "${1:-}" == --distribution ]]; then
  DISTRIBUTION=true
elif [[ $# -gt 0 ]]; then
  echo 'Usage: scripts/build.sh [--distribution]' >&2
  exit 1
fi
SIGNING_IDENTITY="${PROMPT_PALETTE_SIGNING_IDENTITY:-}"
IDENTITY_FILE=scripts/signing-identity.local
if $DISTRIBUTION; then
  SIGNING_IDENTITY="${PROMPT_PALETTE_DISTRIBUTION_IDENTITY:-}"
  IDENTITY_FILE=scripts/distribution-identity.local
fi
if [[ -z "$SIGNING_IDENTITY" && -f "$IDENTITY_FILE" ]]; then
  SIGNING_IDENTITY="$(< "$IDENTITY_FILE")"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Configure a signing identity in $IDENTITY_FILE or the appropriate environment variable." >&2
  echo 'For a local-only development build, set PROMPT_PALETTE_SIGNING_IDENTITY=-.' >&2
  exit 1
fi
BUILD_ARGS=(-c release)
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --options runtime)
if $DISTRIBUTION; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
  SIGN_ARGS+=(--timestamp)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
APP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' Resources/Info.plist)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)
APP="$PWD/dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PromptPalette" "$APP/Contents/MacOS/PromptPalette"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
fi
codesign "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
if $DISTRIBUTION; then
  codesign --display --verbose=4 "$APP" 2>&1 | /usr/bin/grep '^Authority=Developer ID Application:' > /dev/null
  lipo "$APP/Contents/MacOS/PromptPalette" -verify_arch arm64 x86_64
fi
echo "Built: $APP"
