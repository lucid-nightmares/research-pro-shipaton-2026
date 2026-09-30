#!/bin/sh
set -eu
configuration="${CONFIGURATION:-}"
store_mode="${RC_STORE_MODE:-}"
public_key="${RC_PUBLIC_SDK_KEY:-}"
customer_center_reviewed="${RC_CUSTOMER_CENTER_REVIEWED:-NO}"
fail() { echo "error: RevenueCat release configuration is invalid: $1" >&2; exit 1; }

# Free development runs deliberately require no key. Syntax is never provider proof.
release_guard=NO
case "$configuration" in Release*) release_guard=YES ;; esac
[ "${RC_RELEASE_BUILD:-NO}" != YES ] || release_guard=YES
if [ "$release_guard" = YES ]; then
  [ "$store_mode" = app-store ] || fail "Release must use RC_STORE_MODE=app-store."
  [ -n "$public_key" ] || fail "RC_PUBLIC_SDK_KEY is missing. Inject a public Apple SDK key in ignored local configuration."
  [ "${#public_key}" -ge 20 ] || fail "RC_PUBLIC_SDK_KEY is too short."
  normalized_key=$(printf '%s' "$public_key" | tr '[:upper:]' '[:lower:]')
  case "$normalized_key" in
    *replace*|*placeholder*|*changeme*|*your_*|*example*|*dummy*|*fake*|*abcdefghijklmnopqrstuvwxyz*) fail "The public SDK key is a known placeholder." ;;
  esac
  case "$public_key" in *[!A-Za-z0-9_]*) fail "The public SDK key contains invalid characters." ;; esac
  case "$public_key" in
    test_*) fail "A Test Store key cannot enter a production build." ;;
    appl_*) ;;
    *) fail "Release requires an Apple public SDK key." ;;
  esac
  [ "$customer_center_reviewed" = YES ] || fail "Customer Center has not been reviewed."
  [ -n "${RC_RELEASE_EVIDENCE_FILE:-}" ] || fail "RC_RELEASE_EVIDENCE_FILE is missing. A plausible key is not completed provider integration."
  script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  /usr/bin/python3 "$script_root/validate-revenuecat-release-evidence.py" "$RC_RELEASE_EVIDENCE_FILE" || fail "Provider evidence receipt is incomplete or mismatched."
fi
