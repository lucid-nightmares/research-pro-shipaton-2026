import CryptoKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var record: FlightRecord?
    @Published private(set) var receipt: RepairReceipt?
    @Published private(set) var localReview: LocalClaimReview?
    @Published var selectedEventIndex = 0
    @Published var selectedChoice: RepairChoice = .recommended
    @Published var errorMessage: String?
    @Published var localReviewErrorMessage: String?

    private let fileManager: FileManager
    private let bundle: Bundle
    private let receiptDirectory: URL?

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        receiptDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.receiptDirectory = receiptDirectory
    }

    func load() {
        guard record == nil, errorMessage == nil else { return }
        // V1 stored its single local review separately from the bundled
        // walkthrough. Load it independently so a missing demo can never hide
        // a person's existing local work during the V2 transition.
        do {
            localReview = try loadLocalReview()
        } catch {
            localReviewErrorMessage = "A previous local review could not be opened safely. \(error.localizedDescription)"
        }
        do {
            guard let url = bundle.url(forResource: "DemoRecord", withExtension: "json") else {
                throw AppModelError.missingDemoRecord
            }
            let data = try Data(contentsOf: url)
            let decoded = try Self.decoder.decode(FlightRecord.self, from: data)
            try Self.validate(decoded)
            record = decoded
            receipt = try loadReceipt()
        } catch {
            let walkthroughError = "The verified example could not be opened. \(error.localizedDescription)"
            errorMessage = walkthroughError
        }
    }

    func selectEvent(_ index: Int) {
        guard let record else { return }
        selectedEventIndex = min(max(index, 0), max(record.journey.count - 1, 0))
    }

    @discardableResult
    func recordDecision() throws -> RepairReceipt {
        guard let record else { throw AppModelError.missingDemoRecord }
        if let receipt { return receipt }

        let after = selectedChoice == .recommended
            ? record.repair.recommended
            : record.repair.alternative
        let recordedAt = Self.currentTimestamp()
        let digestMaterial = [
            record.project.id,
            record.repair.id,
            selectedChoice.rawValue,
            record.repair.before,
            after,
            Self.iso8601.string(from: recordedAt)
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(digestMaterial.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let created = RepairReceipt(
            schemaVersion: "research-os.ios.repair-receipt.v1",
            receiptID: "IOS-\(UUID().uuidString.uppercased())",
            projectID: record.project.id,
            repairID: record.repair.id,
            choice: selectedChoice,
            before: record.repair.before,
            after: after,
            authority: "Explicit local device-owner confirmation",
            recordedAt: recordedAt,
            contentDigest: digest
        )
        let url = try receiptURL(createDirectory: true)
        let data = try Self.encoder.encode(created)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        receipt = created
        return created
    }

    func resetLocalDecision() throws {
        let url = try receiptURL(createDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        receipt = nil
        selectedChoice = .recommended
    }

    @discardableResult
    func saveLocalReview(
        question: String,
        evidenceSummary: String,
        claimNeedingReview: String,
        boundedWording: String,
        limitation: String
    ) throws -> LocalClaimReview {
        let fields = [question, evidenceSummary, claimNeedingReview, boundedWording, limitation]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.allSatisfy({ !$0.isEmpty && $0.count <= 2_000 }) else {
            throw AppModelError.invalidLocalReview
        }
        let existing = localReview
        let changed = existing.map {
            [$0.question, $0.evidenceSummary, $0.claimNeedingReview, $0.boundedWording, $0.limitation] != fields
        } ?? true
        let review = LocalClaimReview(
            id: existing?.id ?? UUID(),
            createdAt: existing?.createdAt ?? Self.currentTimestamp(),
            question: fields[0],
            evidenceSummary: fields[1],
            claimNeedingReview: fields[2],
            boundedWording: fields[3],
            limitation: fields[4],
            confirmedAt: changed ? nil : existing?.confirmedAt,
            receiptDigest: changed ? nil : existing?.receiptDigest
        )
        try persistLocalReview(review)
        localReview = review
        return review
    }

    @discardableResult
    func confirmLocalReview() throws -> LocalClaimReview {
        guard var review = localReview else { throw AppModelError.invalidLocalReview }
        if review.receiptDigest != nil { return review }
        let confirmedAt = Self.currentTimestamp()
        let material = [
            review.id.uuidString,
            review.question,
            review.evidenceSummary,
            review.claimNeedingReview,
            review.boundedWording,
            review.limitation,
            Self.iso8601.string(from: confirmedAt)
        ].joined(separator: "\n")
        review.confirmedAt = confirmedAt
        review.receiptDigest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        try persistLocalReview(review)
        localReview = review
        return review
    }

    func deleteLocalReview() throws {
        let url = try localReviewURL(createDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let exportURL = localReviewExportURL()
        if fileManager.fileExists(atPath: exportURL.path) {
            try fileManager.removeItem(at: exportURL)
        }
        localReview = nil
    }

    func localReviewManifestFile() throws -> URL {
        guard let localReview else { throw AppModelError.invalidLocalReview }
        let manifest = LocalReviewManifest(
            schemaVersion: "research-os.ios.local-review-manifest.v1",
            classification: "LOCAL_USER_CREATED_REVIEW",
            review: localReview,
            verificationBoundary: localReview.receiptDigest == nil
                ? "Draft only. The bounded wording has not been confirmed."
                : "Local human confirmation and manifest integrity only. The app did not independently verify the evidence or scientific conclusion."
        )
        let url = localReviewExportURL()
        try Self.encoder.encode(manifest).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func manifest() throws -> ReviewManifest {
        guard let record else { throw AppModelError.missingDemoRecord }
        return ReviewManifest(
            schemaVersion: "research-os.ios.review-manifest.v1",
            classification: record.classification,
            projectID: record.project.id,
            question: record.project.question,
            activeClaim: receipt?.after ?? record.driftAlarm.unsupportedClaim,
            evidenceSummary: record.capsule.evidenceSummary,
            limitations: record.capsule.limitations,
            repairReceipt: receipt,
            verificationBoundary: receipt == nil
                ? "Preview only. No local repair receipt has been recorded."
                : "Local receipt and manifest integrity only. No scientific rerun, publication, or external validation occurred."
        )
    }

    func manifestFile() throws -> URL {
        let data = try Self.encoder.encode(manifest())
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("Research-OS-Review-Manifest.json", isDirectory: false)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func validate(_ record: FlightRecord) throws {
        guard record.classification == "SYNTHETIC_DEMO_ONLY" else {
            throw AppModelError.unsupportedClassification
        }
        let summary = record.dataset.summary
        let quietTotal = record.dataset.rows.reduce(0) { $0 + $1.quietCorrect }
        let musicTotal = record.dataset.rows.reduce(0) { $0 + $1.musicCorrect }
        guard record.dataset.rows.count == summary.studentCount,
              quietTotal == summary.quietCorrectTotal,
              musicTotal == summary.musicCorrectTotal,
              !record.journey.isEmpty,
              record.journey.filter(\.resultFirstKnown).count == 1 else {
            throw AppModelError.invalidDemoRecord
        }
    }

    private func loadReceipt() throws -> RepairReceipt? {
        let url = try receiptURL(createDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let value = try Self.decoder.decode(RepairReceipt.self, from: Data(contentsOf: url))
        guard let record else { throw AppModelError.invalidReceipt }
        try Self.validateRepairReceipt(value, record: record)
        return value
    }

    private func loadLocalReview() throws -> LocalClaimReview? {
        let url = try localReviewURL(createDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let value = try Self.decoder.decode(LocalClaimReview.self, from: Data(contentsOf: url))
        try Self.validateLocalReview(value)
        return value
    }

    private func persistLocalReview(_ review: LocalClaimReview) throws {
        let url = try localReviewURL(createDirectory: true)
        try Self.encoder.encode(review).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func receiptURL(createDirectory: Bool) throws -> URL {
        let directory: URL
        if let receiptDirectory {
            directory = receiptDirectory
        } else {
            directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: createDirectory
            ).appendingPathComponent("ResearchOSFlightRecorder", isDirectory: true)
        }
        if createDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("repair-receipt.json", isDirectory: false)
    }

    private func localReviewURL(createDirectory: Bool) throws -> URL {
        let receipt = try receiptURL(createDirectory: createDirectory)
        return receipt.deletingLastPathComponent().appendingPathComponent("local-review.json", isDirectory: false)
    }

    private func localReviewExportURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("Research-OS-Local-Claim-Review.json", isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let iso8601 = ISO8601DateFormatter()

    /// Persisted ISO-8601 dates are second-precision. Normalize at creation so
    /// the in-memory receipt is byte-for-byte equivalent to a decoded receipt.
    private static func currentTimestamp() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    private static func validateLocalReview(_ review: LocalClaimReview) throws {
        let fields = [
            review.question,
            review.evidenceSummary,
            review.claimNeedingReview,
            review.boundedWording,
            review.limitation
        ]
        guard fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 2_000 }),
              (review.confirmedAt == nil) == (review.receiptDigest == nil) else {
            throw AppModelError.invalidLocalReview
        }
        guard let confirmedAt = review.confirmedAt, let receiptDigest = review.receiptDigest else { return }
        let material = [
            review.id.uuidString,
            review.question,
            review.evidenceSummary,
            review.claimNeedingReview,
            review.boundedWording,
            review.limitation,
            iso8601.string(from: confirmedAt)
        ].joined(separator: "\n")
        let expected = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard receiptDigest == expected else { throw AppModelError.invalidReceipt }
    }

    private static func validateRepairReceipt(_ receipt: RepairReceipt, record: FlightRecord) throws {
        let expectedAfter = receipt.choice == .recommended
            ? record.repair.recommended
            : record.repair.alternative
        let material = [
            record.project.id,
            record.repair.id,
            receipt.choice.rawValue,
            record.repair.before,
            expectedAfter,
            iso8601.string(from: receipt.recordedAt)
        ].joined(separator: "\n")
        let expectedDigest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard receipt.schemaVersion == "research-os.ios.repair-receipt.v1",
              receipt.projectID == record.project.id,
              receipt.repairID == record.repair.id,
              receipt.before == record.repair.before,
              receipt.after == expectedAfter,
              receipt.contentDigest == expectedDigest else {
            throw AppModelError.invalidReceipt
        }
    }
}

enum AppModelError: LocalizedError {
    case missingDemoRecord
    case unsupportedClassification
    case invalidDemoRecord
    case invalidLocalReview
    case invalidReceipt

    var errorDescription: String? {
        switch self {
        case .missingDemoRecord: "The bundled example is missing."
        case .unsupportedClassification: "Only a supported Research OS record can be opened in this build."
        case .invalidDemoRecord: "The bundled example did not pass its integrity checks."
        case .invalidLocalReview: "Complete every field using 2,000 characters or fewer."
        case .invalidReceipt: "The stored local receipt did not pass its integrity check."
        }
    }
}
