#!/bin/sh
# Preparation only. Never presses Purchase, modifies provider accounts, or creates proof.
set -eu
native_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:---check}
case "$mode" in --check|--launch) ;; *) echo 'Usage: verify-revenuecat-demo.sh [--check|--launch]' >&2; exit 2 ;; esac
/usr/bin/python3 - "$native_root/Config/LocalSecrets.xcconfig" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file():
    print('BLOCKED: Config/LocalSecrets.xcconfig is absent. Account holder must supply the public Test Store SDK key; do not supply a private API key.')
    sys.exit(3)
settings = {}
for line in p.read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('//'):
        name, value = line.split('=', 1)
        settings[name.strip()] = value.split('//')[0].strip()
key = settings.get('RC_PUBLIC_SDK_KEY', '')
if not re.fullmatch(r'test_[A-Za-z0-9_]{15,}', key) or any(x in key.lower() for x in ('replace', 'placeholder', 'example', 'dummy', 'fake', 'your_', 'changeme', 'abcdefghijklmnopqrstuvwxyz')):
    print('BLOCKED: Configure a genuine Test Store public SDK key. Key syntax alone is not provider proof.')
    sys.exit(3)
print('CONFIGURATION_ONLY: Test Store key syntax found. Provider project, offering, paywall, purchase, restore and premium unlock are NOT VERIFIED by this script.')
PY
if [ "$mode" = --launch ]; then
  : "${SIMULATOR_ID:?Set SIMULATOR_ID to the selected booted iPhone simulator UUID.}"
  derived="$native_root/build/ShipatonDemo"
  xcodebuild -quiet -project "$native_root/ResearchOSFlightRecorder.xcodeproj" \
    -scheme ResearchPro-Shipaton-Demo -configuration Debug-TestStore \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO build
  app="$derived/Build/Products/Debug-TestStore-iphonesimulator/ResearchOSFlightRecorder.app"
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
  xcrun simctl install "$SIMULATOR_ID" "$app"
  xcrun simctl launch "$SIMULATOR_ID" "$bundle_id"
fi
cat <<'TEXT'
Manual verification remains required:
1. Create a free project, record evidence, repair a claim, complete a standard defense.
2. Open Plus. Record environment, fetched CustomerInfo timestamp, actual default offering and localized terms. Verify Close and Restore are visible.
3. Only after explicit authorization, a human initiates a Test Store purchase.
4. Confirm CustomerInfo reports research_pro_plus from Test Store; start an advanced defense and save responses to evidence-specific questions.
5. Relaunch, refresh, restore and inspect saved responses. Observe an expiration or revocation through the provider; new premium work locks, saved work still reads/exports.
6. Record redacted dashboard and app observations with source revision, SDK version, time and device. Never mark this script as purchase proof.
TEXT
