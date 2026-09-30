import XCTest
import RevenueCat
@testable import ResearchOSFlightRecorder

final class SubscriptionContractTests: XCTestCase {
    func testRevenueCatContractIsExact() {
        XCTAssertEqual(RevenueCatContract.entitlementIdentifier, "research_pro_plus")
        XCTAssertEqual(RevenueCatContract.offeringIdentifier, "default")
        XCTAssertEqual(RevenueCatContract.monthlyProductIdentifier, "research_pro_plus_monthly")
        XCTAssertEqual(RevenueCatContract.annualProductIdentifier, "research_pro_plus_yearly")
        XCTAssertEqual(RevenueCatContract.monthlyPackageIdentifier, "$rc_monthly")
        XCTAssertEqual(RevenueCatContract.annualPackageIdentifier, "$rc_annual")
        XCTAssertEqual(RevenueCatContract.annualIntroductoryPeriod, "P7D")
    }

    func testOnlyVerifiedActiveCustomerInfoGrantsOrdinaryPlusAccess() {
        let active = SubscriptionEntitlementSnapshot(
            isActive: true,
            hasBillingIssue: false,
            expirationDate: nil,
            verification: .verified
        )
        XCTAssertTrue(SubscriptionStateResolver.resolve(active).grantsPlusAccess)
        XCTAssertFalse(SubscriptionStateResolver.resolve(nil).grantsPlusAccess)
    }

    func testBillingRetryKeepsTemporaryAccessForGracefulRecovery() {
        let retry = SubscriptionEntitlementSnapshot(
            isActive: true,
            hasBillingIssue: true,
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
            verification: .verifiedOnDevice
        )
        XCTAssertEqual(
            SubscriptionStateResolver.resolve(
                retry,
                evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            .billingRetry(expirationDate: retry.expirationDate)
        )
        XCTAssertTrue(SubscriptionStateResolver.resolve(
            retry,
            evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ).grantsPlusAccess)
    }

    func testSignatureFailureAndPendingVerificationFailClosed() {
        for verification in [
            SubscriptionEntitlementSnapshot.Verification.failed,
            .notRequested
        ] {
            let snapshot = SubscriptionEntitlementSnapshot(
                isActive: true,
                hasBillingIssue: false,
                expirationDate: nil,
                verification: verification
            )
            XCTAssertFalse(SubscriptionStateResolver.resolve(snapshot).grantsPlusAccess)
        }
    }

    func testSDKInactiveEntitlementDoesNotGrantAccess() {
        let expired = SubscriptionEntitlementSnapshot(
            isActive: false,
            hasBillingIssue: false,
            expirationDate: Date(timeIntervalSince1970: 100),
            verification: .verified
        )
        XCTAssertEqual(
            SubscriptionStateResolver.resolve(
                expired,
                evaluatedAt: Date(timeIntervalSince1970: 101)
            ),
            .free
        )
    }

    func testPurchaseConfigurationSeparatesTestAndReleaseKeys() throws {
        XCTAssertNoThrow(try PurchaseConfiguration(
            publicSDKKey: "test_contractFixtureForValidationOnly91",
            storeMode: .testStore,
            isReleaseBuild: false,
            customerCenterReviewed: false
        ).validate())
        XCTAssertNoThrow(try PurchaseConfiguration(
            publicSDKKey: "appl_contractFixtureForValidationOnly91",
            storeMode: .appStore,
            isReleaseBuild: true,
            customerCenterReviewed: true
        ).validate())
        XCTAssertThrowsError(try PurchaseConfiguration(
            publicSDKKey: "test_contractFixtureForValidationOnly91",
            storeMode: .appStore,
            isReleaseBuild: true,
            customerCenterReviewed: true
        ).validate())
        XCTAssertThrowsError(try PurchaseConfiguration(
            publicSDKKey: "appl_contractFixtureForValidationOnly91",
            storeMode: .appStore,
            isReleaseBuild: true,
            customerCenterReviewed: false
        ).validate())
        XCTAssertThrowsError(try PurchaseConfiguration(
            publicSDKKey: "appl_REPLACE_WITH_REAL_KEY",
            storeMode: .appStore,
            isReleaseBuild: true,
            customerCenterReviewed: true
        ).validate())
    }

    func testCommercialPolicyGatesCapacityAndRetainsActivatedWork() {
        XCTAssertEqual(
            CommercialCapabilityPolicy.decision(
                for: .createAdditionalActiveProject,
                subscriptionState: .free,
                activeUserProjectCount: 0
            ),
            .freeFloor
        )
        XCTAssertEqual(
            CommercialCapabilityPolicy.decision(
                for: .createAdditionalActiveProject,
                subscriptionState: .free,
                activeUserProjectCount: 1
            ),
            .requiresPlus
        )

        XCTAssertEqual(
            CommercialCapabilityPolicy.decision(
                for: .standardDefense,
                subscriptionState: .free,
                activeUserProjectCount: 1
            ),
            .freeFloor
        )

        var project = ResearchProject.blank(title: "Bounded work", question: "What changed?")
        XCTAssertEqual(
            CommercialCapabilityPolicy.decision(
                for: .advancedWorkspace,
                subscriptionState: .free,
                activeUserProjectCount: 1,
                project: project
            ),
            .requiresPlus
        )
        project.plusWorkspaceActivatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            CommercialCapabilityPolicy.decision(
                for: .advancedWorkspace,
                subscriptionState: .free,
                activeUserProjectCount: 1,
                project: project
            ),
            .retainedAfterDowngrade
        )
        XCTAssertFalse(
            CommercialCapabilityPolicy.decision(
                for: .advancedWorkspace,
                subscriptionState: .free,
                activeUserProjectCount: 1,
                project: project
            ).allowsMutation
        )
    }

    func testSDKActivityPreservesReportedGraceRatherThanRecomputingExpiration() {
        let grace = SubscriptionEntitlementSnapshot(isActive: true, hasBillingIssue: true,
            expirationDate: Date(timeIntervalSince1970: 100), verification: .verified)
        XCTAssertTrue(SubscriptionStateResolver.resolve(grace,
            evaluatedAt: Date(timeIntervalSince1970: 101)).grantsPlusAccess)
    }

    func testUnverifiedTestStoreIsExplicitlyTestOnlyAndFailureAlwaysDenies() {
        var test = SubscriptionEntitlementSnapshot(isActive: true, hasBillingIssue: false,
            expirationDate: nil, verification: .notRequested, isTestStore: true, isSandbox: true)
        XCTAssertEqual(SubscriptionStateResolver.resolve(test, storeMode: .testStore), .testStoreActive(expirationDate: nil))
        XCTAssertFalse(SubscriptionStateResolver.resolve(test, storeMode: .appStore).grantsPlusAccess)
        XCTAssertFalse(SubscriptionStateResolver.resolve(test, storeMode: .appleSandbox).grantsPlusAccess)
        test = SubscriptionEntitlementSnapshot(isActive: true, hasBillingIssue: false,
            expirationDate: nil, verification: .failed, isTestStore: true, isSandbox: true)
        XCTAssertEqual(SubscriptionStateResolver.resolve(test, storeMode: .testStore), .verificationFailed)
    }

    func testAppleSandboxDoesNotBecomeProductionOrTestStoreAccess() {
        let sandbox = SubscriptionEntitlementSnapshot(isActive: true, hasBillingIssue: false,
            expirationDate: nil, verification: .verified, isSandbox: true)
        XCTAssertTrue(SubscriptionStateResolver.resolve(sandbox, storeMode: .appleSandbox).grantsPlusAccess)
        XCTAssertFalse(SubscriptionStateResolver.resolve(sandbox, storeMode: .appStore).grantsPlusAccess)
        XCTAssertFalse(SubscriptionStateResolver.resolve(sandbox, storeMode: .testStore).grantsPlusAccess)
        let production = SubscriptionEntitlementSnapshot(isActive: true, hasBillingIssue: false,
            expirationDate: nil, verification: .verified, isSandbox: false)
        XCTAssertFalse(SubscriptionStateResolver.resolve(production, storeMode: .appleSandbox).grantsPlusAccess)
    }

    func testOutOfOrderCallbacksCannotUndoRefundOrVerificationFailure() {
        for denied in [SubscriptionAccessState.free, .verificationFailed] {
            var order = SubscriptionUpdateOrder()
            XCTAssertTrue(order.accept(.plusActive(expirationDate: nil), requestedAt: Date(timeIntervalSince1970: 1)))
            XCTAssertTrue(order.accept(denied, requestedAt: Date(timeIntervalSince1970: 3)))
            XCTAssertFalse(order.accept(.plusActive(expirationDate: nil), requestedAt: Date(timeIntervalSince1970: 2)))
            XCTAssertFalse(order.accept(.plusActive(expirationDate: nil), requestedAt: Date(timeIntervalSince1970: 3)))
            XCTAssertEqual(order.state, denied)
            XCTAssertTrue(order.accept(.plusActive(expirationDate: nil), requestedAt: Date(timeIntervalSince1970: 4)))
        }
    }

    func testDuplicateCallbacksAreIdempotentAndEqualDateDenialWins() {
        var order = SubscriptionUpdateOrder()
        let date = Date(timeIntervalSince1970: 10)
        XCTAssertTrue(order.accept(.plusActive(expirationDate: nil), requestedAt: date))
        XCTAssertTrue(order.accept(.plusActive(expirationDate: nil), requestedAt: date))
        XCTAssertEqual(order.state, .plusActive(expirationDate: nil))
        XCTAssertTrue(order.accept(.free, requestedAt: date))
        XCTAssertFalse(order.accept(.plusActive(expirationDate: nil), requestedAt: date))
        XCTAssertEqual(order.state, .free)
    }

    func testStandardAndLegacyPackageContractsBothWork() throws {
        for legacy in [false, true] {
            XCTAssertNoThrow(try SubscriptionOfferingContract.validate([
                .init(identifier: legacy ? "monthly" : "$rc_monthly",
                      productIdentifier: "research_pro_plus_monthly", kind: legacy ? .custom : .monthly, period: "P1M"),
                .init(identifier: legacy ? "annual" : "$rc_annual",
                      productIdentifier: "research_pro_plus_yearly", kind: legacy ? .custom : .annual, period: "P1Y")
            ]))
        }
    }

    func testMismatchedProductPeriodAndExtraPackagesAreDiagnosable() {
        let monthly = SubscriptionPackageDescriptor(identifier: "$rc_monthly",
            productIdentifier: "research_pro_plus_monthly", kind: .monthly, period: "P1M")
        let annual = SubscriptionPackageDescriptor(identifier: "$rc_annual",
            productIdentifier: "research_pro_plus_yearly", kind: .annual, period: "P1Y")
        for invalid in [
            [], [monthly], [monthly, annual, annual],
            [monthly, .init(identifier: "$rc_annual", productIdentifier: "wrong", kind: .annual, period: "P1Y")],
            [monthly, .init(identifier: "$rc_annual", productIdentifier: "research_pro_plus_yearly", kind: .annual, period: "P1M")],
            [monthly, .init(identifier: "unreviewed", productIdentifier: "research_pro_plus_yearly", kind: .custom, period: "P1Y")]
        ] as [[SubscriptionPackageDescriptor]] {
            XCTAssertThrowsError(try SubscriptionOfferingContract.validate(invalid)) { error in
                XCTAssertEqual(error as? OfferingContractError, .invalidPackages)
            }
        }
    }

    func testAdvancedDefenseNeedsActualEntitlementAndHasNoSampleBypass() {
        let project = ResearchProject.blank(title: "Synthetic", question: "Does the policy bypass?")
        for state in [SubscriptionAccessState.free, .notConfigured, .verificationFailed, .unavailable] {
            XCTAssertEqual(CommercialCapabilityPolicy.decision(for: .advancedDefense,
                subscriptionState: state, activeUserProjectCount: 0, project: project), .requiresPlus)
        }
        XCTAssertEqual(CommercialCapabilityPolicy.decision(for: .advancedDefense,
            subscriptionState: .testStoreActive(expirationDate: nil), activeUserProjectCount: 0,
            project: project), .activePlus)
    }

    func testDummyAndUnexpandedKeysAreRejectedWithoutProviderClaims() {
        for key in ["appl_abcdefghijklmnopqrstuvwxyz1234", "appl_dummyCredentialDoNotUse1234", "$(RC_PUBLIC_SDK_KEY)"] {
            XCTAssertThrowsError(try PurchaseConfiguration(publicSDKKey: key, storeMode: .appStore,
                isReleaseBuild: true, customerCenterReviewed: true).validate())
        }
    }


    @MainActor
    func testActivatedSyntheticWorkspaceRetainsReadAccessAfterExpiry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [.syntheticStarter], storageDirectory: directory)
        let id = try XCTUnwrap(workspace.projects.first?.id)
        XCTAssertFalse(workspace.activateAdvancedWorkspace(projectID: id, subscriptionState: .free))
        workspace.updateSubscriptionAccess(.plusActive(expirationDate: nil))
        XCTAssertTrue(workspace.activateAdvancedWorkspace(projectID: id, subscriptionState: .plusActive(expirationDate: nil)))
        workspace.updateSubscriptionAccess(.free)
        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let decision = CommercialCapabilityPolicy.decision(for: .advancedWorkspace, subscriptionState: .free,
            activeUserProjectCount: 0, project: restarted.project(id: id))
        XCTAssertEqual(decision, .retainedAfterDowngrade)
        XCTAssertTrue(decision.allowsUse)
        XCTAssertFalse(decision.allowsMutation)
    }

    @MainActor
    func testPremiumActionRefreshesAndAppliesExpiredAuthorityBeforeCommand() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let project = try XCTUnwrap(workspace.createProject(title: "Fixture", question: "Boundary?", subscriptionState: .free))
        let claim = try workspace.addArgumentClaim(projectID: project, text: "A bounded claim", sourceIDs: [])
        workspace.updateSubscriptionAccess(.plusActive(expirationDate: nil))
        // Application-only fixture: not a RevenueCat receipt or purchase.
        let provider = FixtureSubscriptionRefresh(initial: .plusActive(expirationDate: nil), next: .free)
        let current = await CommercialActionGate.refreshAccess(using: provider, workspace: workspace)
        XCTAssertEqual(provider.forcedRequests, [true])
        XCTAssertEqual(current, .free)
        XCTAssertThrowsError(try workspace.startArgumentDefense(projectID: project, claimID: claim, advanced: true)) {
            XCTAssertEqual($0 as? ResearchArgumentError, .premiumRequired)
        }
        XCTAssertNoThrow(try workspace.startArgumentDefense(projectID: project, claimID: claim))
    }

    @MainActor
    func testPremiumActionAppliesRefreshedAuthorityWithoutWaitingForUIObservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let project = try XCTUnwrap(workspace.createProject(title: "Fixture", question: "Boundary?", subscriptionState: .free))
        let claim = try workspace.addArgumentClaim(projectID: project, text: "A bounded claim", sourceIDs: [])
        let provider = FixtureSubscriptionRefresh(initial: .free, next: .testStoreActive(expirationDate: nil))
        let current = await CommercialActionGate.refreshAccess(using: provider, workspace: workspace)
        XCTAssertTrue(current.grantsPlusAccess)
        let session = try workspace.startArgumentDefense(projectID: project, claimID: claim, advanced: true)
        XCTAssertEqual(workspace.project(id: project)?.argument?.defenseSessions.first(where: { $0.id == session })?.advanced, true)
    }

    @MainActor
    func testPurchaseCompletionAppliesOnlyProviderResultOnce() async {
        let operation = SubscriptionPurchaseOperation<Int>()
        var applied: [Int] = []
        // Application-only fixture payload, never a provider purchase or receipt.
        let result = await operation.run(purchase: { (customerInfo: 7, userCancelled: false) },
                                         apply: { applied.append($0) })
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(applied, [7])
        XCTAssertFalse(operation.isRunning)
    }

    @MainActor
    func testBothProviderCancellationFormsPreserveExistingAuthority() async {
        let operation = SubscriptionPurchaseOperation<Int>()
        var applied: [Int] = []
        let tuple = await operation.run(purchase: { (customerInfo: 7, userCancelled: true) },
                                        apply: { applied.append($0) })
        XCTAssertEqual(tuple, .cancelled)
        let thrown = await operation.run(purchase: {
            throw NSError(domain: ErrorCode.errorDomain, code: ErrorCode.purchaseCancelledError.rawValue)
        }, apply: { applied.append($0) })
        XCTAssertEqual(thrown, .cancelled)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertFalse(operation.isRunning)
    }

    @MainActor
    func testPendingAndFailedPurchasesNeverApplyAuthorityAndAllowRetry() async {
        let operation = SubscriptionPurchaseOperation<Int>()
        var applied: [Int] = []
        let pending = await operation.run(purchase: {
            throw NSError(domain: ErrorCode.errorDomain, code: ErrorCode.paymentPendingError.rawValue)
        }, apply: { applied.append($0) })
        XCTAssertEqual(pending, .pending)
        let failure = await operation.run(purchase: {
            throw NSError(domain: "fixture.transport", code: 42)
        }, apply: { applied.append($0) })
        XCTAssertEqual(failure, .failed(code: 42))
        // A same-number unrelated error must not masquerade as user cancellation.
        let unrelated = await operation.run(purchase: {
            throw NSError(domain: "fixture.transport", code: ErrorCode.purchaseCancelledError.rawValue)
        }, apply: { applied.append($0) })
        XCTAssertEqual(unrelated, .failed(code: ErrorCode.purchaseCancelledError.rawValue))
        XCTAssertTrue(applied.isEmpty)
        let retry = await operation.run(purchase: { (customerInfo: 8, userCancelled: false) },
                                       apply: { applied.append($0) })
        XCTAssertEqual(retry, .completed)
        XCTAssertEqual(applied, [8])
    }

    @MainActor
    func testDuplicatePurchaseDoesNotCallProviderWhileFirstIsPending() async {
        let operation = SubscriptionPurchaseOperation<Int>()
        var continuation: CheckedContinuation<Void, Never>?
        var applied: [Int] = []
        var providerCalls = 0
        let first = Task {
            await operation.run(purchase: {
                providerCalls += 1
                await withCheckedContinuation { continuation = $0 }
                return (customerInfo: 9, userCancelled: false)
            }, apply: { applied.append($0) })
        }
        while !operation.isRunning { await Task.yield() }
        let duplicate = await operation.run(purchase: {
            providerCalls += 1
            return (customerInfo: 10, userCancelled: false)
        }, apply: { applied.append($0) })
        XCTAssertEqual(duplicate, .alreadyInProgress)
        XCTAssertEqual(providerCalls, 1)
        continuation?.resume()
        let result = await first.value
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(applied, [9])
        XCTAssertFalse(operation.isRunning)
    }

    func testDisplayedQuoteRejectsChangedPriceCurrencyProductAndPeriod() {
        let quote = SubscriptionPurchaseQuote(packageIdentifier: "$rc_monthly", productIdentifier: "research_pro_plus_monthly",
            price: Decimal(5), currencyCode: "USD", period: "1:2")
        XCTAssertEqual(quote, SubscriptionPurchaseQuote(packageIdentifier: "$rc_monthly", productIdentifier: "research_pro_plus_monthly",
            price: Decimal(5), currencyCode: "USD", period: "1:2"))
        let changes: [SubscriptionPurchaseQuote] = [
            .init(packageIdentifier: "$rc_monthly", productIdentifier: "research_pro_plus_monthly", price: Decimal(6), currencyCode: "USD", period: "1:2"),
            .init(packageIdentifier: "$rc_monthly", productIdentifier: "research_pro_plus_monthly", price: Decimal(5), currencyCode: "CAD", period: "1:2"),
            .init(packageIdentifier: "$rc_monthly", productIdentifier: "other", price: Decimal(5), currencyCode: "USD", period: "1:2"),
            .init(packageIdentifier: "$rc_monthly", productIdentifier: "research_pro_plus_monthly", price: Decimal(5), currencyCode: "USD", period: "1:3")
        ]
        for changed in changes { XCTAssertNotEqual(quote, changed) }
    }

    func testLegalLinksRequireExplicitReviewAndRealHTTPSLocations() {
        // These addresses are test fixtures, never configured or opened by the app.
        let terms = "https://policy.fixture.invalid/terms"
        let privacy = "https://policy.fixture.invalid/privacy"
        XCTAssertNil(SubscriptionLegalLinks.reviewed(terms: terms, privacy: privacy, approved: false))
        XCTAssertNotNil(SubscriptionLegalLinks.reviewed(terms: terms, privacy: privacy, approved: true))
        for invalid in ["", "http://policy.fixture.invalid/terms", "https://example.com/terms",
                        "https://localhost/terms", "https://name:password" + "@" + "policy.fixture.invalid/terms", "$(RC_TERMS_URL)"] {
            XCTAssertNil(SubscriptionLegalLinks.reviewed(terms: invalid, privacy: privacy, approved: true))
        }
    }

    func testProductionPurchaseStaysDisabledUntilLegalMetadataIsReviewed() {
        XCTAssertTrue(SubscriptionPurchaseAvailability.allowsPurchase(storeMode: .testStore, legalLinksReviewed: false))
        XCTAssertTrue(SubscriptionPurchaseAvailability.allowsPurchase(storeMode: .appleSandbox, legalLinksReviewed: false))
        XCTAssertFalse(SubscriptionPurchaseAvailability.allowsPurchase(storeMode: .appStore, legalLinksReviewed: false))
        XCTAssertTrue(SubscriptionPurchaseAvailability.allowsPurchase(storeMode: .appStore, legalLinksReviewed: true))
        XCTAssertFalse(SubscriptionPurchaseAvailability.allowsPurchase(storeMode: nil, legalLinksReviewed: true))
    }

}


@MainActor
private final class FixtureSubscriptionRefresh: SubscriptionStatusRefreshing {
    private(set) var state: SubscriptionAccessState
    private let next: SubscriptionAccessState
    private(set) var forcedRequests: [Bool] = []
    init(initial: SubscriptionAccessState, next: SubscriptionAccessState) {
        state = initial
        self.next = next
    }
    func refresh(forceNetwork: Bool) async {
        forcedRequests.append(forceNetwork)
        await Task.yield()
        state = next
    }
}
