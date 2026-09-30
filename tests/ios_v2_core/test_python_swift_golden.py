from __future__ import annotations

from hashlib import sha256
import json
import math
from pathlib import Path

import pytest

from challa.os2.contracts import canonical_json, digest_json


ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "mobile" / "research-os-ios"
FIXTURE = IOS / "Fixtures" / "python-swift-event-v1.json"
CORE = IOS / "ResearchOSFlightRecorder" / "Core"


def fixture() -> dict[str, object]:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def test_golden_fixture_is_derived_from_live_python_canonical_contract() -> None:
    value = fixture()
    assert value["fixture_schema"] == "research-os.python-swift-golden.v1"
    assert value["python_contract"] == "challa.os2.contracts.canonical_json/digest_json"
    assert digest_json(value["payload"]) == value["payload_digest"]
    assert digest_json(
        {
            "previous_chain_digest": value["previous_chain_digest"],
            "event": value["event_material"],
        }
    ) == value["chain_digest"]
    assert value["envelope"]["chain_digest"] == value["chain_digest"]  # type: ignore[index]
    assert digest_json(value["archive"]) == value["archive_digest"]


def test_fixture_uses_compact_sorted_utf8_without_ascii_rewriting() -> None:
    value = fixture()
    encoded = canonical_json(value["payload"]).encode("utf-8")
    assert b" " in encoded  # spaces inside scientific prose remain data
    assert b'": "' not in encoded  # no formatting whitespace between fields
    assert sha256(encoded).hexdigest() == value["payload_digest"]


def test_python_canonical_contract_rejects_nonfinite_numbers_like_swift() -> None:
    for value in (math.nan, math.inf, -math.inf):
        with pytest.raises(ValueError):
            canonical_json({"value": value})


def test_swift_core_freezes_python_field_names_and_chain_material() -> None:
    contracts = (CORE / "ResearchOSContracts.swift").read_text(encoding="utf-8")
    store = (CORE / "ResearchEventStore.swift").read_text(encoding="utf-8")
    canonical = (CORE / "CanonicalJSON.swift").read_text(encoding="utf-8")
    for field in (
        "event_id",
        "project_id",
        "branch_id",
        "sequence",
        "schema_id",
        "schema_version",
        "actor_ref",
        "authority_ref",
        "object_refs",
        "prior_project_digest",
        "payload_digest",
        "result_project_digest",
        "chain_digest",
    ):
        assert f'"{field}"' in contracts
    assert '"previous_chain_digest"' in store
    assert '"event"' in store
    assert "keys.sorted()" in canonical
    assert 'joined(separator: ",")' in canonical


def test_core_preserves_private_proposal_only_and_human_authority_boundaries() -> None:
    source = "\n".join(path.read_text(encoding="utf-8") for path in sorted(CORE.glob("*.swift")))
    assert "proposalOnly = true" in source
    assert 'actorRef.hasPrefix("human:")' in source
    assert "SYNTHETIC_DEMO_ONLY" in source
    assert "URLSession" not in source
    assert "RevenueCat" not in source
    assert "StoreKit" not in source


def test_lane_does_not_modify_commercial_contracts() -> None:
    for path in CORE.glob("*.swift"):
        lowered = path.name.lower()
        assert "subscription" not in lowered
        assert "purchase" not in lowered
        assert "revenue" not in lowered
