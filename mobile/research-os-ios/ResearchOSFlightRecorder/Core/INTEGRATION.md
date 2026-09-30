# Research OS Mobile V2 portable core

This lane ports the bounded, deterministic parts of the Python OS2 contract. It
does not claim to replace the Python kernel, independently verify scientific
evidence, run autonomous repairs, publish data, or authorize purchases.

## Contract boundary

- `CanonicalJSON.swift` implements compact, sorted, UTF-8 canonical JSON and
  SHA-256. The golden fixture covers the Python-safe intersection: objects,
  arrays, strings, booleans, nulls, and signed 64-bit integers. Scientific
  decimals that require a fixed lexical representation should remain strings.
- `ResearchOSContracts.swift` freezes versioned object references, typed
  research objects, Review → Repair → Verify stages, event envelopes, AI
  proposals, human decisions, replay frames, and archives.
- `ResearchEventStore.swift` is a local file journal. It supplies project-wide
  monotonic sequences and digest chains, branch ancestry, sequence-addressed
  time travel, deterministic replay/state projection, exact import/export,
  schema-manifest migration, corruption detection, quarantine, and explicit
  human-authorized recovery.
- AI-origin events must say `proposal_only: true`. Repair and verification
  events require an actor reference beginning with `human:`. Imports may not
  rename or combine private projects.

## Integration hooks

The shared Xcode project is intentionally not edited by this lane. Add these
three production files to the `ResearchOSFlightRecorder` target:

1. `Core/CanonicalJSON.swift`
2. `Core/ResearchOSContracts.swift`
3. `Core/ResearchEventStore.swift`

Add `ResearchOSFlightRecorderTests/CoreParityTests.swift` to the test target and
make `Fixtures/python-swift-event-v1.json` available at its repository-relative
path (or copy it into the test bundle and adjust `fixtureURL`).

An application composition root should create one `ResearchEventStore` under a
protected Application Support directory, then translate existing V1 local
review and repair confirmations into event drafts. Do not write the user’s
working draft until a human action occurs. AI output should be stored as a
`ResearchAIProposal`; acceptance or rejection is a separate human event.

## Recovery and migration

Fresh stores write `store-manifest.json` plus `events-v1.jsonl`. A pre-manifest
`events-v0.json` array is validated and converted deterministically. The
plaintext legacy source and any migration copy are removed after the protected
v1 journal is verified; unknown future manifests fail closed.

The store never silently repairs corruption. `audit()` reports the first bad
record. `recover(actorRef:recoveredAt:)` requires explicit `human:` authority,
quarantines every removed byte under `Recovery/`, and truncates only from the
first invalid record onward.

## Verification limits

The Swift sources and golden fixture can be syntax/contract checked on Windows,
but executable Swift/XCTest verification requires macOS with Xcode. The fixture
hashes are recomputed by `tests/ios_v2_core/test_python_swift_golden.py` against
the live Python `challa.os2.contracts` implementation. Passing parity tests does
not prove App Store readiness, evidence validity, cloud synchronization, or
publication authority.
