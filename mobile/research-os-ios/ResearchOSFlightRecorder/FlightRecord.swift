import Foundation

struct FlightRecord: Codable, Equatable {
    let schemaVersion: String
    let classification: String
    let project: Project
    let dataset: Dataset
    let journey: [JourneyEvent]
    let driftAlarm: DriftAlarm
    let phraseFindings: [PhraseFinding]
    let repair: Repair
    let capsule: Capsule
    let aiChecks: [AICheck]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case classification
        case project
        case dataset
        case journey
        case driftAlarm = "drift_alarm"
        case phraseFindings = "phrase_findings"
        case repair
        case capsule
        case aiChecks = "ai_checks"
    }
}

struct Project: Codable, Equatable {
    let id: String
    let title: String
    let question: String
    let notice: String
}

struct Dataset: Codable, Equatable {
    let rows: [ObservationRow]
    let summary: DatasetSummary
}

struct ObservationRow: Codable, Equatable, Identifiable {
    let id: String
    let order: String
    let quietCorrect: Int
    let musicCorrect: Int

    enum CodingKeys: String, CodingKey {
        case id
        case order
        case quietCorrect = "quiet_correct"
        case musicCorrect = "music_correct"
    }
}

struct DatasetSummary: Codable, Equatable {
    let studentCount: Int
    let itemsPerCondition: Int
    let quietCorrectTotal: Int
    let musicCorrectTotal: Int
    let quietAccuracyPercent: Double
    let musicAccuracyPercent: Double
    let differencePercentagePoints: Double
    let inferenceNotice: String

    enum CodingKeys: String, CodingKey {
        case studentCount = "student_count"
        case itemsPerCondition = "items_per_condition"
        case quietCorrectTotal = "quiet_correct_total"
        case musicCorrectTotal = "music_correct_total"
        case quietAccuracyPercent = "quiet_accuracy_percent"
        case musicAccuracyPercent = "music_accuracy_percent"
        case differencePercentagePoints = "difference_percentage_points"
        case inferenceNotice = "inference_notice"
    }
}

struct JourneyEvent: Codable, Equatable, Identifiable {
    let id: String
    let time: String
    let title: String
    let summary: String
    let detail: String
    let actor: String
    let kind: String
    let resultFirstKnown: Bool

    enum CodingKeys: String, CodingKey {
        case id, time, title, summary, detail, actor, kind
        case resultFirstKnown = "result_first_known"
    }
}

struct DriftAlarm: Codable, Equatable {
    let severity: String
    let status: String
    let unsupportedClaim: String
    let supportedClaim: String
    let plainReason: String
    let classification: String

    enum CodingKeys: String, CodingKey {
        case severity, status, classification
        case unsupportedClaim = "unsupported_claim"
        case supportedClaim = "supported_claim"
        case plainReason = "plain_reason"
    }
}

struct PhraseFinding: Codable, Equatable, Identifiable {
    let id: String
    let phrase: String
    let status: String
    let note: String
}

struct Repair: Codable, Equatable {
    let id: String
    let before: String
    let recommended: String
    let alternative: String
    let reason: String
}

struct Capsule: Codable, Equatable {
    let id: String
    let title: String
    let evidenceSummary: String
    let limitations: [String]
    let contents: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, limitations, contents
        case evidenceSummary = "evidence_summary"
    }
}

struct AICheck: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let proposal: String
    let whyReview: String

    enum CodingKeys: String, CodingKey {
        case id, title, proposal
        case whyReview = "why_review"
    }
}

enum RepairChoice: String, Codable, CaseIterable, Identifiable {
    case recommended
    case alternative

    var id: String { rawValue }
    var label: String {
        switch self {
        case .recommended: "Use the narrower description"
        case .alternative: "Turn it into a future question"
        }
    }
}

struct RepairReceipt: Codable, Equatable {
    let schemaVersion: String
    let receiptID: String
    let projectID: String
    let repairID: String
    let choice: RepairChoice
    let before: String
    let after: String
    let authority: String
    let recordedAt: Date
    let contentDigest: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case receiptID = "receipt_id"
        case projectID = "project_id"
        case repairID = "repair_id"
        case choice, before, after, authority
        case recordedAt = "recorded_at"
        case contentDigest = "content_digest"
    }
}

struct ReviewManifest: Codable, Equatable {
    let schemaVersion: String
    let classification: String
    let projectID: String
    let question: String
    let activeClaim: String
    let evidenceSummary: String
    let limitations: [String]
    let repairReceipt: RepairReceipt?
    let verificationBoundary: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case classification
        case projectID = "project_id"
        case question
        case activeClaim = "active_claim"
        case evidenceSummary = "evidence_summary"
        case limitations
        case repairReceipt = "repair_receipt"
        case verificationBoundary = "verification_boundary"
    }
}

struct LocalClaimReview: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    var question: String
    var evidenceSummary: String
    var claimNeedingReview: String
    var boundedWording: String
    var limitation: String
    var confirmedAt: Date?
    var receiptDigest: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case question
        case evidenceSummary = "evidence_summary"
        case claimNeedingReview = "claim_needing_review"
        case boundedWording = "bounded_wording"
        case limitation
        case confirmedAt = "confirmed_at"
        case receiptDigest = "receipt_digest"
    }
}

struct LocalReviewManifest: Codable, Equatable {
    let schemaVersion: String
    let classification: String
    let review: LocalClaimReview
    let verificationBoundary: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case classification
        case review
        case verificationBoundary = "verification_boundary"
    }
}
