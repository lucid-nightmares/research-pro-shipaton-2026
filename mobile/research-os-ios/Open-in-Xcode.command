#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Install Xcode 26 or later from the Mac App Store, open it once, then run this file again." >&2
  printf "Press Return to close. "
  read -r _
  exit 2
fi

open "$ROOT/ResearchOSFlightRecorder.xcodeproj"
echo "Opened ResearchOSFlightRecorder.xcodeproj. In Xcode, choose your signing team before a device/archive build."
