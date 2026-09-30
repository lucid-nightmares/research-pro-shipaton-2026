# Research Pro

Research Pro is a native iOS prototype for tracing a claim to a source passage, reviewing an overclaim, explicitly accepting a revision and preparing an explanation you can defend.

Import a selectable-text PDF, locate a quotation on its page, connect it to a claim, and record why the wording should change. Defense Lab retains answers, cited sources and limitations. The project also holds scope/protocol notes and an independently authored manuscript, with PLOS ONE, ICLR 2027 and Generic research formatting previews.

[Watch the 116.5-second demo](https://www.youtube.com/watch?v=15AjcoeJCBI) · [Shipaton project](https://devpost.com/software/research-pro-pma2gz)

## Run

On macOS with Xcode 26 or later, open `mobile/research-os-ios/ResearchOSFlightRecorder.xcodeproj`. Select **ResearchPro-Shipaton-Demo**, choose an installed iPhone simulator and Run. The latest verification used Xcode 27.0 and iOS 27. The deployment target supports iOS 17 and later.

The free workflow needs no paid Apple account, login, RevenueCat key or generative-model service. Xcode needs internet access or a populated SwiftPM cache to resolve the pinned RevenueCat 5.84.0 dependency. Start with **Create project** for local content or **Try a sample** for explicitly synthetic data. Use a separate simulator for experimentation rather than erasing an existing installation.

Research content is stored locally. Import/export and optional subscription operations are explicit actions. The archive retains extracted PDF pages and the original file fingerprint, not the original PDF bytes. Local hashes establish byte relationships, not scientific truth.

## Verify

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-test.txt
.venv/bin/python -m pytest -q tests/ios_v2_core tests/reverie
python3 mobile/research-os-ios/scripts/test-revenuecat-release-guards.py
```

For native tests, choose an installed simulator UUID and run:

```sh
xcodebuild -project mobile/research-os-ios/ResearchOSFlightRecorder.xcodeproj \
  -scheme ResearchOSFlightRecorder -configuration Debug-TestStore \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -only-testing:ResearchOSFlightRecorderTests \
  CODE_SIGNING_ALLOWED=NO RC_PUBLIC_SDK_KEY= test
```

See [verification](VERIFICATION.md) for the exact tested source, configurations and limits, and [source provenance](SOURCE_PROVENANCE.md) for the public payload's relationship to the original candidate.

## Optional subscriptions

RevenueCat Test Store is a separate development lane. To use your own Test Store project, copy `Config/LocalSecrets.xcconfig.example` to the ignored `Config/LocalSecrets.xcconfig` inside the native directory and supply your own Test Store public SDK key. Keep configuration, provider receipts and configured binaries out of source control. The demo uses actual provider results; it does not simulate an entitlement override. Test Store transactions are not Apple production purchases. Apple distribution has separate signing, legal and provider-evidence requirements.

## Current limits

The three publication profiles are partial previews; custom style import is unavailable. The brief omits Primary outcome and Change policy despite persisting both. Legacy Claims & evidence is not fully synchronized with the newer argument workflow. A nonfatal frame-dimension warning remains. The current demonstration is scripted simulator QA, not physical-device or human-study validation.

## Contributions and license

This project builds on Research OS/Challa, Research Flight Recorder/Reverie and Mobile V2. Pranav Reddy Challa contributed native handoffs, UI/publication direction and export/wording work; Aditya Chandran Arvind coordinated product direction, Mac integration, verification and evidence/media preparation. OpenAI Codex, including verified `gpt-6-astra` sessions, assisted engineering, tests, review, documentation and media. Earlier contributors' exact model use is not fully confirmed.

See [LICENSE](LICENSE), [public release licensing](PUBLIC_RELEASE_LICENSING.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Preserve the separate citation-engine, citation-style/locale, RevenueCat and published-article notices. The Kross et al. (2013) test material retains its author/source and Creative Commons Attribution credit; deliberately false claims in tests are QA inputs.
