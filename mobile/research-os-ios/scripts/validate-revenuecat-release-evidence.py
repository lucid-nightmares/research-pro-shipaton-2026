#!/usr/bin/env python3
"""Validate an account-holder-reviewed release receipt. Never calls a provider.

This is a completeness/integrity gate, not receipt signature verification or
proof that the described human observations occurred. Do not fabricate a receipt.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys


def validate(path):
    receipt_path = Path(path).resolve(strict=True)
    receipt = json.loads(receipt_path.read_text())
    required = {
        "schema_version": 1,
        "status": "VERIFIED",
        "environment": "apple-sandbox",
        "customer_info_verification": "verified",
        "premium_workflow": "advanced-defense",
        "premium_unlock_observed": True,
        "relaunch_observed": True,
        "restore_observed": True,
        "customer_center_reviewed": True,
        "account_holder_reviewed": True,
    }
    for name, value in required.items():
        if receipt.get(name) != value:
            raise ValueError("Missing or unreviewed receipt field: " + name)
    if not isinstance(receipt.get("revenuecat_project_id"), str) or not receipt["revenuecat_project_id"].strip():
        raise ValueError("RevenueCat project ID is absent")
    observed = datetime.datetime.fromisoformat(receipt["observed_at"].replace("Z", "+00:00"))
    if observed.tzinfo is None or observed > datetime.datetime.now(datetime.timezone.utc):
        raise ValueError("Observed date must include timezone and cannot be in the future")
    actual = hashlib.sha256(os.environ.get("RC_PUBLIC_SDK_KEY", "").encode()).hexdigest()
    if receipt.get("production_public_key_sha256") != actual:
        raise ValueError("Evidence belongs to a different production public SDK key")
    evidence = receipt.get("evidence", [])
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("No redacted provider evidence artifacts supplied")
    for item in evidence:
        candidate = (receipt_path.parent / item["path"]).resolve(strict=True)
        candidate.relative_to(receipt_path.parent)
        if not candidate.is_file() or candidate.stat().st_size == 0:
            raise ValueError("Evidence artifact is missing or empty")
        if hashlib.sha256(candidate.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Evidence artifact hash mismatch")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Supply the reviewed release evidence JSON path")
        validate(sys.argv[1])
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("BLOCKED: " + str(error), file=sys.stderr)
        sys.exit(1)
    print("Receipt completeness checked. Provider behavior remains the account holder's recorded observation.")
