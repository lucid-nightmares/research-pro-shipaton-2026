import Foundation

enum RevenueCatContract {
    static let entitlementIdentifier = "research_pro_plus"
    static let offeringIdentifier = "default"
    static let monthlyProductIdentifier = "research_pro_plus_monthly"
    static let annualProductIdentifier = "research_pro_plus_yearly"
    // RevenueCat's standard package identifiers. Legacy custom names remain supported.
    static let monthlyPackageIdentifier = "$rc_monthly"
    static let annualPackageIdentifier = "$rc_annual"
    static let annualIntroductoryPeriod = "P7D"
}

enum SubscriptionAccessState: Equatable {
    case notConfigured, loading, free
    case plusActive(expirationDate: Date?)
    case billingRetry(expirationDate: Date?)
    case testStoreActive(expirationDate: Date?)
    case offlineVerified(expirationDate: Date)
    case verificationPending, verificationFailed, unavailable

    var grantsPlusAccess: Bool {
        switch self {
        case .plusActive, .billingRetry, .testStoreActive, .offlineVerified: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .notConfigured: "Plus is not configured"
        case .loading: "Checking subscription"
        case .free: "Free"
        case .plusActive: "Research Pro Plus"
        case .billingRetry: "Research Pro Plus — billing issue"
        case .testStoreActive: "Research Pro Plus — Test Store"
        case .offlineVerified: "Research Pro Plus — offline"
        case .verificationPending: "Subscription verification pending"
        case .verificationFailed: "Subscription could not be verified"
        case .unavailable: "Subscription status unavailable"
        }
    }

    var detail: String {
        switch self {
        case .notConfigured:
            "Purchases are disabled in this build. Your first active project, evidence, review, repair, defense, and export remain available."
        case .loading:
            "RevenueCat is refreshing CustomerInfo."
        case .free:
            "Core evidence, review, repair, defense, and portable export remain available without a subscription."
        case .plusActive:
            "RevenueCat CustomerInfo reports an active, verified Plus entitlement."
        case .billingRetry:
            "RevenueCat still reports active access during a billing issue. Review your subscription to avoid interruption."
        case .testStoreActive:
            "An active RevenueCat Test Store entitlement unlocks Plus in this test build. This is not an Apple purchase or a production trial."
        case .offlineVerified:
            "Access is based on RevenueCat's cached CustomerInfo, including its offline grace rules. Refresh when a connection returns."
        case .verificationPending:
            "CustomerInfo has not been signature-verified for this Apple environment. Refresh status to fetch a current record. Plus stays locked."
        case .verificationFailed:
            "CustomerInfo signature verification failed. Plus stays locked; your saved research remains accessible."
        case .unavailable:
            "CustomerInfo could not be loaded. Your saved research remains readable and exportable."
        }
    }
}

struct SubscriptionEntitlementSnapshot: Equatable {
    enum Verification: Equatable { case verified, verifiedOnDevice, notRequested, failed }
    let isActive: Bool
    let hasBillingIssue: Bool
    let expirationDate: Date?
    let verification: Verification
    var isTestStore = false
    var isSandbox = false
}

enum SubscriptionStateResolver {
    static func resolve(
        _ snapshot: SubscriptionEntitlementSnapshot?,
        evaluatedAt: Date = Date(),
        storeMode: PurchaseConfiguration.StoreMode = .appStore
    ) -> SubscriptionAccessState {
        guard let snapshot else { return .free }
        guard snapshot.verification != .failed else { return .verificationFailed }
        // A Test Store grant must never leak into an Apple environment. App Store
        // builds must not accept a sandbox entitlement merely because isActive is true.
        guard snapshot.isTestStore == (storeMode == .testStore),
              storeMode != .appStore || !snapshot.isSandbox,
              storeMode != .appleSandbox || snapshot.isSandbox else { return .free }
        if snapshot.verification == .notRequested && snapshot.isActive && storeMode != .testStore {
            return .verificationPending
        }
        // CustomerInfo is authority for activity, including cancellation, billing
        // grace, and SDK cache grace. Do not recompute activity from expiration alone.
        guard snapshot.isActive else { return .free }
        if storeMode == .testStore { return .testStoreActive(expirationDate: snapshot.expirationDate) }
        if snapshot.hasBillingIssue { return .billingRetry(expirationDate: snapshot.expirationDate) }
        return .plusActive(expirationDate: snapshot.expirationDate)
    }
}

/// Server request dates order delegate, purchase, restore and refresh callbacks.
/// For equal timestamps, a denial wins over an older grant; repeated callbacks
/// cannot resurrect access. No paid flag or CustomerInfo is persisted by the app.
struct SubscriptionUpdateOrder {
    private(set) var requestDate: Date?
    private(set) var state: SubscriptionAccessState?

    mutating func accept(_ candidate: SubscriptionAccessState, requestedAt date: Date) -> Bool {
        if let requestDate {
            if date < requestDate { return false }
            if date == requestDate, state?.grantsPlusAccess == false, candidate.grantsPlusAccess { return false }
        }
        requestDate = date
        state = candidate
        return true
    }
}

struct SubscriptionPackageDescriptor: Equatable {
    enum Kind: Equatable { case monthly, annual, custom, other }
    let identifier: String
    let productIdentifier: String
    let kind: Kind
    /// Normalized ISO period from provider metadata, not display copy.
    let period: String?
}

enum OfferingContractError: LocalizedError, Equatable {
    case missingOffering
    case invalidPackages
    var errorDescription: String? {
        switch self {
        case .missingOffering: "RevenueCat has no default offering in this environment. Attach the Test Store or Apple products to default."
        case .invalidPackages: "The default offering must contain exactly one monthly and one annual plan with the reviewed product IDs and periods. Use RevenueCat Monthly/Annual package types, or legacy custom monthly/annual packages."
        }
    }
}

enum SubscriptionOfferingContract {
    static func validate(_ packages: [SubscriptionPackageDescriptor]) throws {
        // Do not pass unreviewed extra products through a remotely rendered paywall.
        guard packages.count == 2 else { throw OfferingContractError.invalidPackages }
        let monthly = packages.filter {
            ($0.kind == .monthly || ($0.kind == .custom && $0.identifier == "monthly")) &&
            $0.productIdentifier == RevenueCatContract.monthlyProductIdentifier && $0.period == "P1M"
        }
        let annual = packages.filter {
            ($0.kind == .annual || ($0.kind == .custom && $0.identifier == "annual")) &&
            $0.productIdentifier == RevenueCatContract.annualProductIdentifier && $0.period == "P1Y"
        }
        guard monthly.count == 1, annual.count == 1 else { throw OfferingContractError.invalidPackages }
    }
}

struct SubscriptionLegalLinks: Equatable {
    let terms: URL
    let privacy: URL

    static func reviewed(terms: String, privacy: String, approved: Bool) -> SubscriptionLegalLinks? {
        guard approved else { return nil }
        func approvedURL(_ value: String) -> URL? {
            guard let url = URL(string: value), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil,
                  !["localhost", "example.com", "example.org"].contains(host.lowercased()),
                  !value.lowercased().contains("replace_") else { return nil }
            return url
        }
        guard let termsURL = approvedURL(terms), let privacyURL = approvedURL(privacy) else { return nil }
        return SubscriptionLegalLinks(terms: termsURL, privacy: privacyURL)
    }

    static func load(from bundle: Bundle = .main) -> SubscriptionLegalLinks? {
        reviewed(terms: bundle.object(forInfoDictionaryKey: "RC_TERMS_URL") as? String ?? "",
                 privacy: bundle.object(forInfoDictionaryKey: "RC_PRIVACY_URL") as? String ?? "",
                 approved: (bundle.object(forInfoDictionaryKey: "RC_LEGAL_LINKS_REVIEWED") as? String) == "YES")
    }
}

enum SubscriptionPurchaseAvailability {
    static func allowsPurchase(storeMode: PurchaseConfiguration.StoreMode?, legalLinksReviewed: Bool) -> Bool {
        switch storeMode {
        case .testStore, .appleSandbox: true
        case .appStore: legalLinksReviewed
        case nil: false
        }
    }
}

/// A displayed quote must still match the validated provider plan at purchase.
struct SubscriptionPurchaseQuote: Equatable {
    let packageIdentifier: String
    let productIdentifier: String
    let price: Decimal
    let currencyCode: String?
    let period: String?
}
