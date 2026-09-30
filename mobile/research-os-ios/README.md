# Research Pro native client

Open `ResearchOSFlightRecorder.xcodeproj` on macOS with Xcode 26 or later. Choose **ResearchPro-Shipaton-Demo**, select an installed simulator and Run. The current source was verified with Xcode 27.0 / iOS 27 simulator. The app targets iOS 17 and later.

The free workflow requires no login, purchase, RevenueCat key or generative-model endpoint. The pinned RevenueCat/RevenueCatUI 5.84.0 dependency requires initial SwiftPM resolution or an existing cache. The internal target and bundle identifier retain the ResearchOSFlightRecorder name for data continuity.

From the repository root, follow README.md for native and Python test commands. `scripts/verify-on-mac.sh` remains a native-suite helper; `IOS_TEST_DESTINATION` selects a simulator. `scripts/validate-revenuecat-key.sh` and `scripts/validate-revenuecat-release-evidence.py` are build guards, not proof of a transaction. `scripts/test-revenuecat-release-guards.py` tests those guards.

`Config/LocalSecrets.xcconfig.example` contains placeholders only. Optional Test Store configuration belongs in ignored `Config/LocalSecrets.xcconfig`. The demo scheme uses Debug-TestStore without a local StoreKit fixture. Other schemes preserve the separate local StoreKit and Apple-sandbox development lanes. Never ship a Test Store key as production configuration.

All 52 application-directory files remain byte-identical to candidate 53e32f408d16c5cc6afa4d0230af76fd927853c9. Public release documentation supersedes historical integration instructions inside retained source comments/documents. Read the root SOURCE_PROVENANCE.md and VERIFICATION.md for what was retained, excluded and tested.
