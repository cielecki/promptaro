#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${PROMPT_PALETTE_NOTARY_PROFILE:?Set this to your existing notarytool Keychain profile.}"
./scripts/build.sh --distribution
APP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' Resources/Info.plist)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP="$PWD/dist/$APP_NAME.app"
SUBMISSION="$PWD/dist/notarization.zip"
ARCHIVE="$PWD/dist/${APP_NAME// /-}-$VERSION-macOS.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROMPT_PALETTE_NOTARY_PROFILE" --wait --timeout 15m
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
(cd dist && shasum -a 256 "${ARCHIVE:t}" > "${ARCHIVE:t}.sha256")
echo "Release archive: $ARCHIVE"
