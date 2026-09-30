import Foundation

struct PurchaseConfiguration: Equatable {
    enum StoreMode: String {
        case testStore = "test-store"
        case appleSandbox = "apple-sandbox"
        case appStore = "app-store"
    }

    enum ValidationError: LocalizedError, Equatable {
        case missingKey
        case unknownStoreMode
        case testKeyRequired
        case appleKeyRequired
        case testKeyInRelease
        case customerCenterNotReviewed

        var errorDescription: String? {
            switch self {
            case .missingKey: "This build has no RevenueCat public SDK key."
            case .unknownStoreMode: "This build has an unknown purchase environment."
            case .testKeyRequired: "The Test Store build requires a Test Store public SDK key."
            case .appleKeyRequired: "The Apple store build requires an Apple public SDK key."
            case .testKeyInRelease: "A Test Store key cannot be used in a release build."
            case .customerCenterNotReviewed: "Customer Center must be configured and reviewed before release."
            }
        }
    }

    let publicSDKKey: String
    let storeMode: StoreMode
    let isReleaseBuild: Bool
    let customerCenterReviewed: Bool

    static func load(from bundle: Bundle = .main) throws -> PurchaseConfiguration {
        let key = (bundle.object(forInfoDictionaryKey: "RC_PUBLIC_SDK_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawMode = (bundle.object(forInfoDictionaryKey: "RC_STORE_MODE") as? String) ?? ""
        let release = (bundle.object(forInfoDictionaryKey: "RC_RELEASE_BUILD") as? String) == "YES"
        let customerCenterReviewed = (bundle.object(forInfoDictionaryKey: "RC_CUSTOMER_CENTER_REVIEWED") as? String) == "YES"
        guard let storeMode = StoreMode(rawValue: rawMode) else {
            throw ValidationError.unknownStoreMode
        }
        let configuration = PurchaseConfiguration(
            publicSDKKey: key,
            storeMode: storeMode,
            isReleaseBuild: release,
            customerCenterReviewed: customerCenterReviewed
        )
        try configuration.validate()
        return configuration
    }

    func validate() throws {
        guard !publicSDKKey.isEmpty else { throw ValidationError.missingKey }
        let normalized = publicSDKKey.lowercased()
        let placeholderFragments = ["replace", "placeholder", "changeme", "your_", "example", "dummy", "fake", "abcdefghijklmnopqrstuvwxyz"]
        guard publicSDKKey.count >= 20,
              !placeholderFragments.contains(where: normalized.contains) else {
            throw ValidationError.missingKey
        }
        guard publicSDKKey.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else {
            throw ValidationError.missingKey
        }
        // This validates syntax and environment only. Provider readiness requires
        // a fetched offering and real CustomerInfo; a plausible key proves neither.
        let isTestKey = publicSDKKey.hasPrefix("test_")
        let isAppleKey = publicSDKKey.hasPrefix("appl_")

        if isReleaseBuild && isTestKey {
            throw ValidationError.testKeyInRelease
        }
        switch storeMode {
        case .testStore:
            guard isTestKey else { throw ValidationError.testKeyRequired }
        case .appleSandbox, .appStore:
            guard isAppleKey else { throw ValidationError.appleKeyRequired }
        }
        if isReleaseBuild && storeMode != .appStore {
            throw ValidationError.appleKeyRequired
        }
        if isReleaseBuild && !customerCenterReviewed {
            throw ValidationError.customerCenterNotReviewed
        }
    }
}
