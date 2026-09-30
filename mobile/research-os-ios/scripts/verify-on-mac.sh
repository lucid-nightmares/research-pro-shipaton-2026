#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROJECT="$ROOT/ResearchOSFlightRecorder.xcodeproj"
SCHEME="ResearchOSFlightRecorder"
DERIVED="$ROOT/build/DerivedData"
RESOLVED="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode command-line tools are required." >&2
  exit 2
fi

XCODE_VERSION=$(xcodebuild -version | sed -n '1p')
xcode_major=$(printf '%s\n' "$XCODE_VERSION" | sed -n 's/^Xcode \([0-9][0-9]*\).*/\1/p')
case "$xcode_major" in
  ''|*[!0-9]*)
    echo "Could not determine the Xcode major version. Found: $XCODE_VERSION" >&2
    exit 2
    ;;
esac
if [ "$xcode_major" -lt 26 ]; then
  echo "Xcode 26 or later is required. Found: $XCODE_VERSION" >&2
  exit 2
fi

if [ ! -f "$RESOLVED" ]; then
  echo "The reviewed Swift package lockfile is missing: $RESOLVED" >&2
  exit 2
fi

RESOLVED_BEFORE=$(shasum -a 256 "$RESOLVED" | awk '{print $1}')
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"
RESOLVED_AFTER=$(shasum -a 256 "$RESOLVED" | awk '{print $1}')
if [ "$RESOLVED_BEFORE" != "$RESOLVED_AFTER" ]; then
  echo "Xcode rewrote Package.resolved. Review the dependency change before building." >&2
  exit 2
fi

if [ -n "${IOS_TEST_DESTINATION:-}" ]; then
  DESTINATION="$IOS_TEST_DESTINATION"
else
  DESTINATION_ID=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations \
    | sed -n '/platform:iOS Simulator/ { /id:dvtdevice-/d; s/.*id:\([^,}]*\).*/\1/p; }' \
    | sed -n '1p' \
    | xargs)
  if [ -z "$DESTINATION_ID" ]; then
    echo "Install at least one iOS Simulator runtime in Xcode, or set IOS_TEST_DESTINATION." >&2
    exit 2
  fi
  DESTINATION="platform=iOS Simulator,id=$DESTINATION_ID"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  clean test

echo "PASS: SwiftUI app compiled and unit tests passed in the iPhone simulator."
