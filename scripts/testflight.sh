#!/bin/zsh
# Archive the iOS app (or, with --mac, the Mac app) and upload it to TestFlight.
#
# Needs, in the environment or in scripts/release.local.env (not in git):
#   APPLE_TEAM_ID     your Apple developer team
#   ASC_KEY_ID        App Store Connect API key id
#   ASC_ISSUER_ID     App Store Connect issuer id
#   ASC_KEY_PATH      path to AuthKey_<id>.p8   (default: ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
# Optional: BUILD_NUMBER (default: minutes since 2026-01-01, so every upload is higher than the last).
#           KARTEI_SIGNING=local builds without the App Group (the widget then shows no data); use it until
#           group.pro.geist.bergmoench.beta is registered for both bundle ids in the developer portal.
#
# usage: scripts/testflight.sh [--mac] [--no-upload]
# The Mac build is sandboxed (Entitlements/Kartei-macOS-team.entitlements) and always signed with the team.
set -euo pipefail
ROOT="${0:A:h:h}"
[[ -f "$ROOT/scripts/release.local.env" ]] && source "$ROOT/scripts/release.local.env"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}" "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
PLATFORM=iOS; UPLOAD=1
for arg in "$@"; do case "$arg" in --mac) PLATFORM=macOS;; --no-upload) UPLOAD=0;; *) echo "unknown option $arg"; exit 1;; esac; done
# The Rust core is built for Apple Silicon only (core/ffi/build.sh), so the Mac app is too.
EXTRA=()
if [[ $PLATFORM == macOS ]]; then KARTEI_SIGNING=team; EXTRA=(ARCHS=arm64 ONLY_ACTIVE_ARCH=NO); fi
BUILD_NUMBER="${BUILD_NUMBER:-$(( ($(date +%s) - 1767225600) / 60 ))}"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

[[ -d "$ROOT/core/build/KarteiCore.xcframework" ]] || { echo "run core/ffi/build.sh first"; exit 1; }
ls "$ROOT"/apps/apple/Kartei/Resources/course-*.apkg >/dev/null 2>&1 || { echo "course decks missing: content/courses/{sync_decks,build_decks.py,install_decks}.sh"; exit 1; }

cd "$ROOT/apps/apple"
xcodegen generate --quiet
OUT="$ROOT/apps/apple/build-release${PLATFORM:#iOS}"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project Kartei.xcodeproj -scheme Kartei -configuration Release \
  -destination "generic/platform=$PLATFORM" -archivePath "$OUT/Bergmoench.xcarchive" \
  KARTEI_SIGNING="${KARTEI_SIGNING:-team}" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="Apple Development" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${EXTRA[@]}" "${AUTH[@]}" archive | tail -3
[[ -d "$OUT/Bergmoench.xcarchive" ]] || { echo "archive failed"; exit 1; }
cp ExportOptions.plist "$OUT/ExportOptions.plist"
(( UPLOAD )) && /usr/libexec/PlistBuddy -c "Set :destination upload" "$OUT/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Add :teamID string $APPLE_TEAM_ID" "$OUT/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$OUT/Bergmoench.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}" | tail -5
echo "$PLATFORM build $BUILD_NUMBER done ($( (( UPLOAD )) && echo uploaded || echo "not uploaded, see $OUT/export"))"
