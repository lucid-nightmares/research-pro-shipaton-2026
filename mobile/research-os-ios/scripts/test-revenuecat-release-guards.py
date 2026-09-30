#!/usr/bin/env python3
"""Local configuration tests. These fixtures are NOT RevenueCat/provider proof."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('validate-revenuecat-key.sh')
FIXTURE_KEY = 'appl_contractFixtureForValidationOnly91'


class ReleaseGuardTests(unittest.TestCase):
    def run_guard(self, **overrides):
        env = dict(os.environ, CONFIGURATION='Release', RC_STORE_MODE='app-store',
                   RC_RELEASE_BUILD='YES', RC_PUBLIC_SDK_KEY=FIXTURE_KEY,
                   RC_CUSTOMER_CENTER_REVIEWED='YES', RC_RELEASE_EVIDENCE_FILE='')
        env.update(overrides)
        return subprocess.run(['sh', str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_free_debug_build_needs_no_credentials(self):
        self.assertEqual(self.run_guard(CONFIGURATION='Debug-TestStore', RC_RELEASE_BUILD='NO', RC_PUBLIC_SDK_KEY='').returncode, 0)

    def test_test_store_never_ships(self):
        self.assertNotEqual(self.run_guard(RC_PUBLIC_SDK_KEY='test_contractFixtureForValidationOnly91').returncode, 0)

    def test_plausible_key_is_not_integration_proof(self):
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('RC_RELEASE_EVIDENCE_FILE is missing', result.stderr)
        self.assertNotIn(FIXTURE_KEY, result.stderr)

    def test_release_variants_are_guarded(self):
        self.assertNotEqual(self.run_guard(CONFIGURATION='Release-AppStore', RC_RELEASE_BUILD='NO').returncode, 0)

    def test_unreviewed_customer_center_blocks(self):
        self.assertNotEqual(self.run_guard(RC_CUSTOMER_CENTER_REVIEWED='NO').returncode, 0)

    def test_receipt_bytes_and_key_binding(self):
        # A mechanical validation fixture, never copied to the release package.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'fixture.txt'
            artifact.write_text('UNIT TEST FIXTURE: NOT A PROVIDER RECEIPT')
            receipt = dict(schema_version=1, status='VERIFIED', environment='apple-sandbox',
                customer_info_verification='verified', premium_workflow='advanced-defense',
                premium_unlock_observed=True, relaunch_observed=True, restore_observed=True,
                customer_center_reviewed=True, account_holder_reviewed=True,
                revenuecat_project_id='UNIT_TEST_ONLY', observed_at='2026-01-01T00:00:00Z',
                production_public_key_sha256=hashlib.sha256(FIXTURE_KEY.encode()).hexdigest(),
                evidence=[dict(path=artifact.name, sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())])
            path = root / 'receipt.json'
            path.write_text(json.dumps(receipt))
            self.assertEqual(self.run_guard(RC_RELEASE_EVIDENCE_FILE=str(path)).returncode, 0)
            artifact.write_text('tampered')
            self.assertNotEqual(self.run_guard(RC_RELEASE_EVIDENCE_FILE=str(path)).returncode, 0)
            receipt['production_public_key_sha256'] = '0' * 64
            path.write_text(json.dumps(receipt))
            self.assertNotEqual(self.run_guard(RC_RELEASE_EVIDENCE_FILE=str(path)).returncode, 0)


if __name__ == '__main__':
    unittest.main()
