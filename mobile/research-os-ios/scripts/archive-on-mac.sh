#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROJECT="$ROOT/ResearchOSFlightRecorder.xcodeproj"
SCHEME="ResearchOSFlightRecorder"
ARCHIVE="$ROOT/build/ResearchOSFlightRecorder.xcarchive"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer Team ID.}"
: "${PRODUCT_BUNDLE_IDENTIFIER:?Set PRODUCT_BUNDLE_IDENTIFIER to the registered explicit App ID.}"

case "$PRODUCT_BUNDLE_IDENTIFIER" in
  org.researchos.flightrecorder|*YOUR*|*yourorganization*|*example*)
    echo "Replace the placeholder bundle identifier before archiving." >&2
    exit 2
    ;;
esac

"$ROOT/scripts/verify-on-mac.sh"

rm -rf "$ARCHIVE"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -disableAutomaticPackageResolution \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$PRODUCT_BUNDLE_IDENTIFIER" \
  -allowProvisioningUpdates \
  archive

echo "PASS: signed archive created at $ARCHIVE"
echo "Open Xcode Organizer to validate and upload. This script does not submit the app."
