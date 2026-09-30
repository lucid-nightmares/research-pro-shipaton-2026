import StoreKit
import StoreKitTest
import XCTest
@testable import ResearchOSFlightRecorder

@available(iOS 15.0, *)
final class StoreKitContractTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()
        session = try SKTestSession(configurationFileNamed: "ResearchOSSubscriptions")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        // StoreKit Test can take a moment to publish a newly activated local
        // catalog to StoreKit 2, especially on a freshly booted simulator.
        let identifiers = [
            RevenueCatContract.monthlyProductIdentifier,
            RevenueCatContract.annualProductIdentifier,
        ]
        for attempt in 0..<20 {
            if try await !Product.products(for: identifiers).isEmpty { break }
            if attempt < 19 { try await Task.sleep(nanoseconds: 250_000_000) }
        }
    }

    func testLocalCatalogContainsExactMonthlyAndAnnualProducts() async throws {
        let expected = Set([
            RevenueCatContract.monthlyProductIdentifier,
            RevenueCatContract.annualProductIdentifier,
        ])
        let products = try await Product.products(for: Array(expected))
        XCTAssertEqual(Set(products.map(\.id)), expected)
        XCTAssertEqual(products.first(where: { $0.id == RevenueCatContract.monthlyProductIdentifier })?.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(products.first(where: { $0.id == RevenueCatContract.annualProductIdentifier })?.subscription?.subscriptionPeriod.unit, .year)
    }

    func testAnnualFixtureCarriesSevenDayIntroOffer() async throws {
        let products = try await Product.products(for: [RevenueCatContract.annualProductIdentifier])
        let annual = try XCTUnwrap(products.first)
        let offer = try XCTUnwrap(annual.subscription?.introductoryOffer)
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.period.value, 7)
        XCTAssertEqual(offer.period.unit, .day)
    }
}
