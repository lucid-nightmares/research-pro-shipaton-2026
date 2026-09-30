import Foundation
import RevenueCat

@MainActor
final class SubscriptionController: NSObject, ObservableObject, SubscriptionStatusRefreshing {
    @Published private(set) var state: SubscriptionAccessState = .notConfigured
    /// SDK initialized, not a claim that the dashboard or purchasing works.
    @Published private(set) var isConfigured = false
    @Published private(set) var offering: Offering?
    @Published private(set) var offeringContractReviewed = false
    @Published private(set) var customerCenterReviewed = false
    @Published private(set) var isWorking = false
    @Published private(set) var environmentLabel = "Purchases disabled"
    @Published private(set) var lastCustomerInfoDate: Date?
    @Published private(set) var verificationLabel = "No CustomerInfo received"
    @Published private(set) var storeMode: PurchaseConfiguration.StoreMode?
    @Published private(set) var legalLinks: SubscriptionLegalLinks?
    @Published var message: String?

    private var configuration: PurchaseConfiguration?
    private var updateOrder = SubscriptionUpdateOrder()
    private var acceptedRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskForcesNetwork = false
    private var restoreTask: Task<Void, Never>?
    private var purchaseTask: Task<Bool, Never>?
    private let purchaseOperation = SubscriptionPurchaseOperation<CustomerInfo>()

    var canStartPurchase: Bool {
        isConfigured && offeringContractReviewed &&
        SubscriptionPurchaseAvailability.allowsPurchase(storeMode: storeMode, legalLinksReviewed: legalLinks != nil)
    }

    override init() {
        super.init()
        configureIfPossible()
    }

    func configureIfPossible() {
        guard !isConfigured else { return }
        do {
            let configuration = try PurchaseConfiguration.load()
            self.configuration = configuration
            storeMode = configuration.storeMode
            legalLinks = SubscriptionLegalLinks.load()
            customerCenterReviewed = configuration.customerCenterReviewed
            switch configuration.storeMode {
            case .testStore: environmentLabel = "RevenueCat Test Store • no real charge"
            case .appleSandbox: environmentLabel = "Apple sandbox • no real charge"
            case .appStore: environmentLabel = "Apple App Store"
            }
            // Debug logs may include transaction/customer identifiers. Use the
            // content-free diagnostics below for recording; opt in locally only.
            Purchases.logLevel = .warn
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: configuration.publicSDKKey)
                    .with(entitlementVerificationMode: .informational)
                    .with(automaticDeviceIdentifierCollectionEnabled: false)
                    .build()
            )
            Purchases.shared.delegate = self
            isConfigured = true
            state = .loading
            Task { await refresh() }
        } catch {
            isConfigured = false
            state = .notConfigured
            message = error.localizedDescription
        }
    }

    /// Coalesce overlapping scene, view and button refreshes. Restore waits for
    /// refresh and vice versa, so an older error cannot reset a newer operation.
    func refresh(forceNetwork: Bool = false) async {
        guard isConfigured else { return }
        if let purchaseTask {
            _ = await purchaseTask.value
            if !forceNetwork { return }
        }
        if let restoreTask {
            await restoreTask.value
            if !forceNetwork { return }
        }
        if let refreshTask {
            let existingForcesNetwork = refreshTaskForcesNetwork
            await refreshTask.value
            if forceNetwork && !existingForcesNetwork {
                // The owner clears the finished task before its value returns.
                await refresh(forceNetwork: true)
            }
            return
        }
        refreshTaskForcesNetwork = forceNetwork
        let task = Task {
            await performRefresh(forceNetwork: forceNetwork)
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh(forceNetwork: Bool) async {
        isWorking = true
        defer { isWorking = false }
        let revisionAtStart = acceptedRevision
        var customerInfoLoaded = false
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: forceNetwork ? .fetchCurrent : .cachedOrFetched)
            receive(info)
            customerInfoLoaded = true
            // A cache created before signature verification was enabled can have
            // notRequested. Fetch a current response, without deleting saved work.
            if state == .verificationPending && !forceNetwork {
                receive(try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
            }
            message = nil
        } catch {
            // Rehydrate the SDK's own disk cache (which applies its grace rules),
            // including on offline relaunch. Do not invent an in-memory paid lease.
            if let cached = try? await Purchases.shared.customerInfo(fetchPolicy: .fromCacheOnly) {
                receive(cached)
                customerInfoLoaded = true
            }
            if acceptedRevision == revisionAtStart && !customerInfoLoaded { state = .unavailable }
            message = "The current provider record could not be fetched. Any retained access uses RevenueCat's cached CustomerInfo. Saved research remains readable and exportable."
        }
        // Offering failures must not revoke a valid existing entitlement.
        do { try await refreshOffering() }
        catch {
            offering = nil
            offeringContractReviewed = false
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard isConfigured, purchaseTask == nil else { return }
        if let restoreTask { await restoreTask.value; return }
        if let refreshTask { await refreshTask.value }
        // A purchase may have started while awaiting the refresh.
        guard purchaseTask == nil else { return }
        // A second restore may have started while awaiting the refresh.
        if let restoreTask { await restoreTask.value; return }
        let task = Task { await performRestore() }
        restoreTask = task
        await task.value
        restoreTask = nil
    }

    private func performRestore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            receive(try await Purchases.shared.restorePurchases())
            message = state.grantsPlusAccess
                ? "Restore completed. RevenueCat reports active Plus access in this environment."
                : "Restore completed without verified active Plus access. Saved research remains readable and exportable."
        } catch {
            message = "Restore did not complete. No research data was changed. Try again when connected."
        }
    }

    /// Resolve the quoted plan against the currently validated Offering. Never
    /// silently charge a refreshed price different from the one on screen.
    func purchase(package quotedPackage: Package) async -> Bool {
        guard purchaseTask == nil, refreshTask == nil, restoreTask == nil,
              !isWorking, canStartPurchase,
              let package = offering?.availablePackages.first(where: { $0.identifier == quotedPackage.identifier }) else {
            return false
        }
        guard SubscriptionPurchaseQuote(package: package) == SubscriptionPurchaseQuote(package: quotedPackage) else {
            message = "The available plans changed. Close and reopen plans to review the current price before continuing."
            return false
        }
        let task = Task {
            isWorking = true
            defer { isWorking = false; purchaseTask = nil }
            let outcome = await purchaseOperation.run(purchase: {
                let result = try await Purchases.shared.purchase(package: package)
                return (customerInfo: result.customerInfo, userCancelled: result.userCancelled)
            }, apply: { receive($0) })
            switch outcome {
            case .completed:
                message = state.grantsPlusAccess
                    ? "RevenueCat reports active Plus access. Your advanced research tools are ready."
                    : "The provider completed the purchase, but active Plus access has not been confirmed. Refresh or restore; your research is unaffected."
                return state.grantsPlusAccess
            case .cancelled:
                purchaseCancelled()
            case .pending:
                message = "Payment is pending. Plus unlocks only when RevenueCat reports an active entitlement."
            case .failed(let code):
                message = "Purchase did not complete (provider error \(code)). Your research is unchanged."
            case .alreadyInProgress:
                break
            }
            return false
        }
        purchaseTask = task
        return await task.value
    }

    /// Only SDK-produced CustomerInfo enters this path; purchase-button state,
    /// callback arrival and local project markers never grant Plus by themselves.
    func receive(_ customerInfo: CustomerInfo) {
        guard let configuration else { return }
        let entitlement = customerInfo.entitlements[RevenueCatContract.entitlementIdentifier]
        let verification: SubscriptionEntitlementSnapshot.Verification
        switch customerInfo.entitlements.verification {
        case .verified: verification = .verified
        case .verifiedOnDevice: verification = .verifiedOnDevice
        case .notRequested: verification = .notRequested
        case .failed: verification = .failed
        @unknown default: verification = .failed
        }
        let snapshot = entitlement.map {
            SubscriptionEntitlementSnapshot(
                isActive: $0.isActive,
                hasBillingIssue: $0.billingIssueDetectedAt != nil,
                expirationDate: $0.expirationDate,
                verification: verification,
                isTestStore: $0.store == .testStore,
                isSandbox: $0.isSandbox
            )
        }
        let candidate = verification == .failed
            ? SubscriptionAccessState.verificationFailed
            : SubscriptionStateResolver.resolve(snapshot, storeMode: configuration.storeMode)
        guard updateOrder.accept(candidate, requestedAt: customerInfo.requestDate) else { return }
        state = candidate
        lastCustomerInfoDate = customerInfo.requestDate
        verificationLabel = String(describing: verification)
        acceptedRevision += 1
    }

    func purchaseCancelled() {
        message = "Purchase cancelled. Existing access and research are unchanged."
    }

    func purchaseFailed(_ error: NSError) {
        if error.code == ErrorCode.paymentPendingError.rawValue {
            message = "Payment is pending. Plus unlocks only when RevenueCat reports an active entitlement."
        } else {
            message = "Purchase did not complete (provider error \(error.code)). Existing research is unchanged."
        }
    }

    private func refreshOffering() async throws {
        let offerings = try await Purchases.shared.offerings()
        guard let candidate = offerings.offering(identifier: RevenueCatContract.offeringIdentifier) else {
            throw OfferingContractError.missingOffering
        }
        let descriptors = candidate.availablePackages.map { package in
            let kind: SubscriptionPackageDescriptor.Kind
            switch package.packageType {
            case .monthly: kind = .monthly
            case .annual: kind = .annual
            case .custom: kind = .custom
            default: kind = .other
            }
            let period = package.storeProduct.subscriptionPeriod.map { period in
                let suffix: String
                switch period.unit {
                case .day: suffix = "D"
                case .week: suffix = "W"
                case .month: suffix = "M"
                case .year: suffix = "Y"
                @unknown default: suffix = "?"
                }
                return "P\(period.value)\(suffix)"
            }
            return SubscriptionPackageDescriptor(identifier: package.identifier,
                productIdentifier: package.storeProduct.productIdentifier, kind: kind, period: period)
        }
        try SubscriptionOfferingContract.validate(descriptors)
        offering = candidate
        offeringContractReviewed = true
    }
}

extension SubscriptionController: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in self?.receive(customerInfo) }
    }
}

/// Executes one provider purchase at a time. Only a successful, non-cancelled
/// response reaches the CustomerInfo application callback. Tests use a generic
/// fixture payload here; the running controller always uses SDK CustomerInfo.
@MainActor
final class SubscriptionPurchaseOperation<Info> {
    enum Outcome: Equatable {
        case completed, cancelled, pending, alreadyInProgress
        case failed(code: Int)
    }
    private(set) var isRunning = false

    func run(
        purchase: () async throws -> (customerInfo: Info, userCancelled: Bool),
        apply: (Info) -> Void
    ) async -> Outcome {
        guard !isRunning else { return .alreadyInProgress }
        isRunning = true
        defer { isRunning = false }
        do {
            let result = try await purchase()
            guard !result.userCancelled else { return .cancelled }
            apply(result.customerInfo)
            return .completed
        } catch {
            let error = error as NSError
            guard error.domain == ErrorCode.errorDomain else { return .failed(code: error.code) }
            switch error.code {
            case ErrorCode.purchaseCancelledError.rawValue: return .cancelled
            case ErrorCode.paymentPendingError.rawValue: return .pending
            default: return .failed(code: error.code)
            }
        }
    }
}

private extension SubscriptionPurchaseQuote {
    init(package: Package) {
        self.init(packageIdentifier: package.identifier,
                  productIdentifier: package.storeProduct.productIdentifier,
                  price: package.storeProduct.price,
                  currencyCode: package.storeProduct.currencyCode,
                  period: package.storeProduct.subscriptionPeriod.map { "\($0.value):\($0.unit.rawValue)" })
    }
}
