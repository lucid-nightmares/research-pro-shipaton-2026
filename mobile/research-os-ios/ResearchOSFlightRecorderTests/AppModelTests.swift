import XCTest
@testable import ResearchOSFlightRecorder

final class AppModelTests: XCTestCase {
    @MainActor
    func testBundledExampleIsSyntheticAndInternallyConsistent() throws {
        let record = try loadRecord()
        XCTAssertEqual(record.classification, "SYNTHETIC_DEMO_ONLY")
        XCTAssertEqual(record.dataset.rows.count, 12)
        XCTAssertEqual(record.dataset.rows.reduce(0) { $0 + $1.quietCorrect }, 78)
        XCTAssertEqual(record.dataset.rows.reduce(0) { $0 + $1.musicCorrect }, 83)
        XCTAssertEqual(record.journey.filter(\.resultFirstKnown).count, 1)
        XCTAssertNoThrow(try AppModel.validate(record))
    }

    func testClaimRepairNeverRetainsCausalOrPopulationOverclaim() throws {
        let record = try loadRecord()
        XCTAssertTrue(record.repair.before.contains("improves"))
        XCTAssertTrue(record.repair.before.contains("all students"))
        XCTAssertFalse(record.repair.recommended.lowercased().contains("all students"))
        XCTAssertFalse(record.repair.alternative.lowercased().contains("all students"))
        XCTAssertTrue(record.repair.recommended.contains("synthetic class sample"))
    }

    func testAllFourProtocolDriftLabelsRemainNamedInProductEvidence() throws {
        let supported = Set([
            "PRE_RESULT_PLANNED_CHANGE",
            "POST_RESULT_DISCLOSED_CHANGE",
            "POST_RESULT_UNEXPLAINED_CHANGE",
            "INSUFFICIENT_TIMELINE_EVIDENCE"
        ])
        XCTAssertTrue(supported.contains(try loadRecord().driftAlarm.classification))
    }

    @MainActor
    func testLocalDecisionIsDurableAndIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(bundle: .main, receiptDirectory: directory)
        model.load()
        XCTAssertNil(model.errorMessage)
        let first = try model.recordDecision()
        let second = try model.recordDecision()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.after, model.record?.repair.recommended)
        XCTAssertEqual(first.contentDigest.count, 64)

        let reopened = AppModel(bundle: .main, receiptDirectory: directory)
        reopened.load()
        XCTAssertEqual(reopened.receipt, first)

        try reopened.resetLocalDecision()
        XCTAssertNil(reopened.receipt)
    }

    @MainActor
    func testManifestStatesTheVerificationBoundary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(bundle: .main, receiptDirectory: directory)
        model.load()
        XCTAssertTrue(try model.manifest().verificationBoundary.contains("Preview only"))
        _ = try model.recordDecision()
        let manifest = try model.manifest()
        XCTAssertNotNil(manifest.repairReceipt)
        XCTAssertTrue(manifest.verificationBoundary.contains("No scientific rerun"))
    }

    @MainActor
    func testUserCreatedReviewPersistsConfirmsAndDeletesLocally() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(bundle: .main, receiptDirectory: directory)
        model.load()
        let draft = try model.saveLocalReview(
            question: "What changed?",
            evidenceSummary: "Three bounded observations.",
            claimNeedingReview: "The intervention always works.",
            boundedWording: "The three observations were higher after the intervention.",
            limitation: "No causal or population conclusion."
        )
        XCTAssertNil(draft.receiptDigest)
        let confirmed = try model.confirmLocalReview()
        XCTAssertEqual(confirmed.receiptDigest?.count, 64)

        let reopened = AppModel(bundle: .main, receiptDirectory: directory)
        reopened.load()
        XCTAssertEqual(reopened.localReview, confirmed)
        let export = try reopened.localReviewManifestFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))

        try reopened.deleteLocalReview()
        XCTAssertNil(reopened.localReview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
    }

    @MainActor
    func testTamperedPreviousReviewIsRejectedWithoutBlockingWalkthrough() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(bundle: .main, receiptDirectory: directory)
        model.load()
        _ = try model.saveLocalReview(
            question: "What changed?",
            evidenceSummary: "Three bounded observations.",
            claimNeedingReview: "The intervention always works.",
            boundedWording: "The three observations were higher after the intervention.",
            limitation: "No causal or population conclusion."
        )
        _ = try model.confirmLocalReview()
        let url = directory.appendingPathComponent("local-review.json")
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        document["receipt_digest"] = String(repeating: "0", count: 64)
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: url)

        let reopened = AppModel(bundle: .main, receiptDirectory: directory)
        reopened.load()
        XCTAssertNil(reopened.localReview)
        XCTAssertNotNil(reopened.localReviewErrorMessage)
        XCTAssertNotNil(reopened.record)
    }

    private func loadRecord() throws -> FlightRecord {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "DemoRecord", withExtension: "json"))
        return try JSONDecoder().decode(FlightRecord.self, from: Data(contentsOf: url))
    }
}
