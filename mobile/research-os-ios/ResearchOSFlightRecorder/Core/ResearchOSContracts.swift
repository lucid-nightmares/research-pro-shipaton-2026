import Foundation

enum ResearchOSSchema {
    static let namespace = "com.challa.research-os.mobile"
    static let event = "com.challa.research-os.event"
    static let object = "com.challa.research-os.object"
    static let archive = "com.challa.research-os.mobile.event-archive"
    static let replay = "com.challa.research-os.mobile.replay"
    static let store = "com.challa.research-os.mobile.event-store"
    static let projectDeletionReceipt = "com.challa.research-os.mobile.project-deletion-receipt"
    static let currentVersion = 1
    static let zeroDigest = String(repeating: "0", count: 64)
}

struct ResearchObjectRef: Codable, Equatable, Hashable, Comparable, Sendable {
    let projectID: String
    let objectType: String
    let logicalID: String
    let version: Int

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case objectType = "object_type"
        case logicalID = "logical_id"
        case version
    }

    init(projectID: String, objectType: String, logicalID: String, version: Int) throws {
        try ResearchOSValidation.requireID(projectID, field: "project_id")
        try ResearchOSValidation.requireID(objectType, field: "object_type")
        try ResearchOSValidation.requireID(logicalID, field: "logical_id")
        guard version > 0 else { throw ResearchOSCoreError.invalidContract("object version must be positive") }
        self.projectID = projectID
        self.objectType = objectType
        self.logicalID = logicalID
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            projectID: container.decode(String.self, forKey: .projectID),
            objectType: container.decode(String.self, forKey: .objectType),
            logicalID: container.decode(String.self, forKey: .logicalID),
            version: container.decode(Int.self, forKey: .version)
        )
    }

    var key: String { "\(projectID)/\(objectType)/\(logicalID)@\(version)" }

    func validate() throws {
        try ResearchOSValidation.requireID(projectID, field: "project_id")
        try ResearchOSValidation.requireID(objectType, field: "object_type")
        try ResearchOSValidation.requireID(logicalID, field: "logical_id")
        guard version > 0 else { throw ResearchOSCoreError.invalidContract("object version must be positive") }
    }

    static func < (lhs: ResearchObjectRef, rhs: ResearchObjectRef) -> Bool { lhs.key < rhs.key }
}

enum ResearchObjectKind: String, Codable, CaseIterable, Sendable {
    case project
    case question
    case protocolObject = "protocol"
    case evidence
    case claim
    case repairProposal = "repair_proposal"
    case repairReceipt = "repair_receipt"
    case verificationReceipt = "verification_receipt"
}

enum ResearchClassification: String, Codable, Sendable {
    case privateResearch = "PRIVATE_RESEARCH"
    case syntheticDemoOnly = "SYNTHETIC_DEMO_ONLY"
    case localUserCreated = "LOCAL_USER_CREATED_REVIEW"
}

enum ResearchWorkflowStage: String, Codable, Sendable {
    case review = "REVIEW"
    case repair = "REPAIR"
    case verify = "VERIFY"
}

/// A versioned, branch-addressed Research OS object. Content remains typed JSON,
/// while identity, lifecycle, classification, and authority boundaries are frozen.
struct VersionedResearchObject: Codable, Equatable, Sendable {
    let schemaID: String
    let schemaVersion: Int
    let ref: ResearchObjectRef
    let branchID: String
    let kind: ResearchObjectKind
    let stage: ResearchWorkflowStage
    let classification: ResearchClassification
    let content: CanonicalJSONValue

    enum CodingKeys: String, CodingKey {
        case schemaID = "schema_id"
        case schemaVersion = "schema_version"
        case ref
        case branchID = "branch_id"
        case kind, stage, classification, content
    }

    init(
        ref: ResearchObjectRef,
        branchID: String,
        kind: ResearchObjectKind,
        stage: ResearchWorkflowStage,
        classification: ResearchClassification,
        content: CanonicalJSONValue
    ) throws {
        try ResearchOSValidation.requireID(branchID, field: "branch_id")
        guard case .object = content else {
            throw ResearchOSCoreError.invalidContract("research object content must be a JSON object")
        }
        schemaID = ResearchOSSchema.object
        schemaVersion = ResearchOSSchema.currentVersion
        self.ref = ref
        self.branchID = branchID
        self.kind = kind
        self.stage = stage
        self.classification = classification
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .schemaID) == ResearchOSSchema.object,
              try container.decode(Int.self, forKey: .schemaVersion) == ResearchOSSchema.currentVersion else {
            throw ResearchOSCoreError.unsupportedSchema
        }
        try self.init(
            ref: container.decode(ResearchObjectRef.self, forKey: .ref),
            branchID: container.decode(String.self, forKey: .branchID),
            kind: container.decode(ResearchObjectKind.self, forKey: .kind),
            stage: container.decode(ResearchWorkflowStage.self, forKey: .stage),
            classification: container.decode(ResearchClassification.self, forKey: .classification),
            content: container.decode(CanonicalJSONValue.self, forKey: .content)
        )
    }
}

/// AI output cannot directly authorize a mutation. It can only be persisted as
/// a proposal that a named human may accept or reject in a later event.
struct ResearchAIProposal: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let proposalID: String
    let projectID: String
    let branchID: String
    let proposedObject: VersionedResearchObject
    let rationale: String
    let proposalOnly: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case proposalID = "proposal_id"
        case projectID = "project_id"
        case branchID = "branch_id"
        case proposedObject = "proposed_object"
        case rationale
        case proposalOnly = "proposal_only"
    }

    init(
        proposalID: String,
        projectID: String,
        branchID: String,
        proposedObject: VersionedResearchObject,
        rationale: String
    ) throws {
        try ResearchOSValidation.requireID(proposalID, field: "proposal_id")
        try ResearchOSValidation.requireID(projectID, field: "project_id")
        try ResearchOSValidation.requireID(branchID, field: "branch_id")
        guard proposedObject.ref.projectID == projectID, proposedObject.branchID == branchID else {
            throw ResearchOSCoreError.crossProject
        }
        guard !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchOSCoreError.invalidContract("AI proposal rationale is required")
        }
        schemaVersion = ResearchOSSchema.currentVersion
        self.proposalID = proposalID
        self.projectID = projectID
        self.branchID = branchID
        self.proposedObject = proposedObject
        self.rationale = rationale
        proposalOnly = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == ResearchOSSchema.currentVersion,
              try container.decode(Bool.self, forKey: .proposalOnly) else {
            throw ResearchOSCoreError.proposalOnlyRequired
        }
        try self.init(
            proposalID: container.decode(String.self, forKey: .proposalID),
            projectID: container.decode(String.self, forKey: .projectID),
            branchID: container.decode(String.self, forKey: .branchID),
            proposedObject: container.decode(VersionedResearchObject.self, forKey: .proposedObject),
            rationale: container.decode(String.self, forKey: .rationale)
        )
    }
}

struct HumanAuthorityDecision: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Sendable { case accepted, rejected }

    let actorRef: String
    let authorityRef: String
    let proposalID: String
    let decision: Decision
    let decidedAt: String

    enum CodingKeys: String, CodingKey {
        case actorRef = "actor_ref"
        case authorityRef = "authority_ref"
        case proposalID = "proposal_id"
        case decision
        case decidedAt = "decided_at"
    }

    init(actorRef: String, authorityRef: String, proposalID: String, decision: Decision, decidedAt: String) throws {
        guard actorRef.hasPrefix("human:") else { throw ResearchOSCoreError.humanAuthorityRequired }
        try ResearchOSValidation.requireID(actorRef, field: "actor_ref")
        try ResearchOSValidation.requireID(authorityRef, field: "authority_ref")
        try ResearchOSValidation.requireID(proposalID, field: "proposal_id")
        try ResearchOSValidation.requireTimestamp(decidedAt, field: "decided_at")
        self.actorRef = actorRef
        self.authorityRef = authorityRef
        self.proposalID = proposalID
        self.decision = decision
        self.decidedAt = decidedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            actorRef: container.decode(String.self, forKey: .actorRef),
            authorityRef: container.decode(String.self, forKey: .authorityRef),
            proposalID: container.decode(String.self, forKey: .proposalID),
            decision: container.decode(Decision.self, forKey: .decision),
            decidedAt: container.decode(String.self, forKey: .decidedAt)
        )
    }
}

enum ResearchMutationOperation: String, Codable, Sendable { case put, delete }

struct ResearchMutation: Codable, Equatable, Sendable {
    let ref: ResearchObjectRef
    let operation: ResearchMutationOperation
    let value: CanonicalJSONValue
    let dependsOn: [ResearchObjectRef]

    enum CodingKeys: String, CodingKey {
        case ref, operation, value
        case dependsOn = "depends_on"
    }

    init(
        ref: ResearchObjectRef,
        operation: ResearchMutationOperation,
        value: CanonicalJSONValue = .object([:]),
        dependsOn: [ResearchObjectRef] = []
    ) throws {
        if operation == .delete, value != .object([:]) {
            throw ResearchOSCoreError.invalidContract("delete mutations cannot carry a value")
        }
        if dependsOn.contains(ref) {
            throw ResearchOSCoreError.invalidContract("an object cannot depend on itself")
        }
        guard dependsOn.allSatisfy({ $0.projectID == ref.projectID }) else {
            throw ResearchOSCoreError.crossProject
        }
        self.ref = ref
        self.operation = operation
        self.value = value
        self.dependsOn = Array(Set(dependsOn)).sorted()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ref: container.decode(ResearchObjectRef.self, forKey: .ref),
            operation: container.decode(ResearchMutationOperation.self, forKey: .operation),
            value: container.decode(CanonicalJSONValue.self, forKey: .value),
            dependsOn: container.decode([ResearchObjectRef].self, forKey: .dependsOn)
        )
    }
}

struct ResearchEventDraft: Equatable, Sendable {
    let eventID: String
    let projectID: String
    let branchID: String
    let kind: String
    let schemaID: String
    let schemaVersion: Int
    let actorRef: String
    let authorityRef: String
    let origin: String
    let causeRefs: [String]
    let objectRefs: [ResearchObjectRef]
    let idempotencyKey: String
    let occurredAt: String
    let parentEventIDs: [String]
    let priorProjectDigest: String
    let resultProjectDigest: String
    let payload: CanonicalJSONValue

    init(
        eventID: String,
        projectID: String,
        branchID: String,
        kind: String,
        actorRef: String,
        authorityRef: String,
        origin: String,
        idempotencyKey: String,
        occurredAt: String,
        priorProjectDigest: String,
        resultProjectDigest: String,
        payload: CanonicalJSONValue,
        causeRefs: [String] = [],
        objectRefs: [ResearchObjectRef] = [],
        parentEventIDs: [String] = [],
        schemaID: String = ResearchOSSchema.event,
        schemaVersion: Int = ResearchOSSchema.currentVersion
    ) throws {
        for (field, value) in [
            ("event_id", eventID), ("project_id", projectID), ("branch_id", branchID),
            ("kind", kind), ("schema_id", schemaID), ("actor_ref", actorRef),
            ("authority_ref", authorityRef), ("origin", origin), ("idempotency_key", idempotencyKey)
        ] { try ResearchOSValidation.requireID(value, field: field) }
        try ResearchOSValidation.requireTimestamp(occurredAt, field: "occurred_at")
        try ResearchOSValidation.requireSHA256(priorProjectDigest, field: "prior_project_digest")
        try ResearchOSValidation.requireSHA256(resultProjectDigest, field: "result_project_digest")
        guard schemaVersion == ResearchOSSchema.currentVersion else { throw ResearchOSCoreError.unsupportedSchema }
        guard case .object = payload else { throw ResearchOSCoreError.invalidContract("event payload must be an object") }
        guard objectRefs.allSatisfy({ $0.projectID == projectID }) else { throw ResearchOSCoreError.crossProject }
        for value in causeRefs { try ResearchOSValidation.requireID(value, field: "cause_ref") }
        for value in parentEventIDs { try ResearchOSValidation.requireID(value, field: "parent_event_id") }
        guard Set(parentEventIDs).count == parentEventIDs.count, !parentEventIDs.contains(eventID) else {
            throw ResearchOSCoreError.invalidContract("event parents must be unique and cannot include the event")
        }
        if ResearchOSValidation.requiresHumanAuthority(kind: kind) {
            guard actorRef.hasPrefix("human:") else { throw ResearchOSCoreError.humanAuthorityRequired }
        }
        try ResearchOSValidation.validateAIEvent(
            actorRef: actorRef,
            origin: origin,
            kind: kind,
            payload: payload,
            objectRefs: objectRefs
        )
        self.eventID = eventID
        self.projectID = projectID
        self.branchID = branchID
        self.kind = kind
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
        self.actorRef = actorRef
        self.authorityRef = authorityRef
        self.origin = origin
        self.causeRefs = Array(Set(causeRefs)).sorted()
        self.objectRefs = Array(Set(objectRefs)).sorted()
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.parentEventIDs = Array(Set(parentEventIDs)).sorted()
        self.priorProjectDigest = priorProjectDigest
        self.resultProjectDigest = resultProjectDigest
        self.payload = payload
    }
}

struct ResearchEventEnvelope: Codable, Equatable, Identifiable, Sendable {
    let eventID: String
    let projectID: String
    let branchID: String
    let sequence: Int
    let kind: String
    let schemaID: String
    let schemaVersion: Int
    let actorRef: String
    let authorityRef: String
    let origin: String
    let causeRefs: [String]
    let objectRefs: [ResearchObjectRef]
    let idempotencyKey: String
    let occurredAt: String
    let parentEventIDs: [String]
    let priorProjectDigest: String
    let payloadDigest: String
    let resultProjectDigest: String
    let chainDigest: String
    let payload: CanonicalJSONValue

    var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case projectID = "project_id"
        case branchID = "branch_id"
        case sequence, kind
        case schemaID = "schema_id"
        case schemaVersion = "schema_version"
        case actorRef = "actor_ref"
        case authorityRef = "authority_ref"
        case origin
        case causeRefs = "cause_refs"
        case objectRefs = "object_refs"
        case idempotencyKey = "idempotency_key"
        case occurredAt = "occurred_at"
        case parentEventIDs = "parent_event_ids"
        case priorProjectDigest = "prior_project_digest"
        case payloadDigest = "payload_digest"
        case resultProjectDigest = "result_project_digest"
        case chainDigest = "chain_digest"
        case payload
    }

    func materialValue() -> CanonicalJSONValue {
        .object([
            "event_id": .string(eventID),
            "project_id": .string(projectID),
            "branch_id": .string(branchID),
            "sequence": .integer(Int64(sequence)),
            "kind": .string(kind),
            "schema_id": .string(schemaID),
            "schema_version": .integer(Int64(schemaVersion)),
            "actor_ref": .string(actorRef),
            "authority_ref": .string(authorityRef),
            "origin": .string(origin),
            "cause_refs": .array(causeRefs.map(CanonicalJSONValue.string)),
            "object_refs": .array(objectRefs.map { ref in
                .object([
                    "project_id": .string(ref.projectID),
                    "object_type": .string(ref.objectType),
                    "logical_id": .string(ref.logicalID),
                    "version": .integer(Int64(ref.version))
                ])
            }),
            "idempotency_key": .string(idempotencyKey),
            "occurred_at": .string(occurredAt),
            "parent_event_ids": .array(parentEventIDs.map(CanonicalJSONValue.string)),
            "prior_project_digest": .string(priorProjectDigest),
            "payload_digest": .string(payloadDigest),
            "result_project_digest": .string(resultProjectDigest),
            "payload": payload
        ])
    }

    func validate(previousChainDigest: String) throws {
        guard sequence > 0, schemaVersion == ResearchOSSchema.currentVersion else {
            throw ResearchOSCoreError.unsupportedSchema
        }
        for (field, value) in [
            ("event_id", eventID), ("project_id", projectID), ("branch_id", branchID),
            ("kind", kind), ("schema_id", schemaID), ("actor_ref", actorRef),
            ("authority_ref", authorityRef), ("origin", origin), ("idempotency_key", idempotencyKey)
        ] { try ResearchOSValidation.requireID(value, field: field) }
        try ResearchOSValidation.requireTimestamp(occurredAt, field: "occurred_at")
        for (field, digest) in [
            ("previous_chain_digest", previousChainDigest),
            ("prior_project_digest", priorProjectDigest),
            ("payload_digest", payloadDigest),
            ("result_project_digest", resultProjectDigest),
            ("chain_digest", chainDigest)
        ] { try ResearchOSValidation.requireSHA256(digest, field: field) }
        guard case .object = payload else { throw ResearchOSCoreError.corrupt("event payload is not an object") }
        for ref in objectRefs {
            try ref.validate()
            guard ref.projectID == projectID else { throw ResearchOSCoreError.crossProject }
        }
        for value in causeRefs { try ResearchOSValidation.requireID(value, field: "cause_ref") }
        for value in parentEventIDs { try ResearchOSValidation.requireID(value, field: "parent_event_id") }
        guard Set(parentEventIDs).count == parentEventIDs.count, !parentEventIDs.contains(eventID) else {
            throw ResearchOSCoreError.corrupt("event parent inventory is invalid")
        }
        if ResearchOSValidation.requiresHumanAuthority(kind: kind) {
            guard actorRef.hasPrefix("human:") else { throw ResearchOSCoreError.humanAuthorityRequired }
        }
        try ResearchOSValidation.validateAIEvent(
            actorRef: actorRef,
            origin: origin,
            kind: kind,
            payload: payload,
            objectRefs: objectRefs
        )
        if let mutationsValue = payload["mutations"] {
            let mutations = try JSONDecoder().decode(
                [ResearchMutation].self,
                from: CanonicalJSON.encode(mutationsValue)
            )
            let mutationRefs = mutations.map(\.ref)
            guard Set(mutationRefs).count == mutationRefs.count,
                  mutationRefs.sorted() == objectRefs else {
                throw ResearchOSCoreError.corrupt("mutation inventory does not match object_refs")
            }
        }
        let expectedPayload = try CanonicalJSON.digest(payload)
        guard payloadDigest == expectedPayload else { throw ResearchOSCoreError.corrupt("payload digest mismatch") }
        let expectedChain = try CanonicalJSON.digest(.object([
            "previous_chain_digest": .string(previousChainDigest),
            "event": materialValue()
        ]))
        guard chainDigest == expectedChain else { throw ResearchOSCoreError.corrupt("event chain mismatch") }
    }
}

struct ResearchReplayFrame: Codable, Equatable, Sendable {
    let ordinal: Int
    let event: ResearchEventEnvelope
    let priorFrameDigest: String
    let frameDigest: String

    enum CodingKeys: String, CodingKey {
        case ordinal, event
        case priorFrameDigest = "prior_frame_digest"
        case frameDigest = "frame_digest"
    }
}

struct ResearchReplay: Codable, Equatable, Sendable {
    let schemaID: String
    let schemaVersion: Int
    let projectID: String
    let branchID: String
    let throughSequence: Int
    let frames: [ResearchReplayFrame]
    let replayDigest: String

    enum CodingKeys: String, CodingKey {
        case schemaID = "schema_id"
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case branchID = "branch_id"
        case throughSequence = "through_sequence"
        case frames
        case replayDigest = "replay_digest"
    }
}

struct ResearchEventArchive: Codable, Equatable, Sendable {
    let schemaID: String
    let schemaVersion: Int
    let projectID: String
    let exportedHeadDigest: String
    let events: [ResearchEventEnvelope]

    enum CodingKeys: String, CodingKey {
        case schemaID = "schema_id"
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case exportedHeadDigest = "exported_head_digest"
        case events
    }
}

enum ResearchOSValidation {
    private static let idPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

    static func requireID(_ value: String, field: String) throws {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard idPattern.firstMatch(in: value, range: range)?.range == range else {
            throw ResearchOSCoreError.invalidContract("\(field) must be a stable 1-128 character identifier")
        }
    }

    static func requireSHA256(_ value: String, field: String) throws {
        let allowed = Set("0123456789abcdef")
        guard value.utf8.count == 64, value.allSatisfy(allowed.contains) else {
            throw ResearchOSCoreError.invalidContract("\(field) must be a lowercase SHA-256 digest")
        }
    }

    static func requireTimestamp(_ value: String, field: String) throws {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard withFraction.date(from: value) != nil || plain.date(from: value) != nil else {
            throw ResearchOSCoreError.invalidContract("\(field) must be a timezone-aware ISO-8601 timestamp")
        }
    }

    static func requiresHumanAuthority(kind: String) -> Bool {
        if kind.hasSuffix(".verified") || kind.hasSuffix(".repaired") { return true }
        let decision = kind.hasSuffix(".applied")
            || kind.hasSuffix(".accepted")
            || kind.hasSuffix(".rejected")
            || kind.hasSuffix(".confirmed")
        return decision && (kind.hasPrefix("repair.") || kind.hasPrefix("verification."))
    }

    static func validateAIEvent(
        actorRef: String,
        origin: String,
        kind: String,
        payload: CanonicalJSONValue,
        objectRefs: [ResearchObjectRef]
    ) throws {
        let actor = actorRef.lowercased()
        let source = origin.lowercased()
        let isAI = ["ai:", "model:", "agent:"].contains(where: actor.hasPrefix)
            || ["ai", "model", "agent", "remote-ai"].contains(where: {
                source == $0 || source.hasPrefix("\($0):") || source.hasPrefix("\($0)-")
            })
        guard isAI else { return }
        let authoritativeTokens = [
            ".accepted", ".applied", ".confirmed", ".published", ".repaired", ".verified"
        ]
        let forbiddenKinds: Set<String> = [
            "authority.granted",
            "entitlement.changed",
            "evidence.created",
            "evidence.verified",
            "proof_finding.cleared",
            "protocol.frozen",
        ]
        let allowedObjectTypes: Set<String> = ["proposal", "ai_proposal", "ai_contribution"]
        guard payload["proposal_only"] == .bool(true),
              !forbiddenKinds.contains(kind.lowercased()),
              !authoritativeTokens.contains(where: kind.lowercased().hasSuffix),
              objectRefs.allSatisfy({ allowedObjectTypes.contains($0.objectType.lowercased()) }) else {
            throw ResearchOSCoreError.proposalOnlyRequired
        }
    }
}

enum ResearchOSCoreError: LocalizedError, Equatable {
    case invalidContract(String)
    case archiveCapacityExceeded(projectID: String)
    case unsupportedSchema
    case crossProject
    case humanAuthorityRequired
    case proposalOnlyRequired
    case duplicateIdentity
    case staleHead
    case corrupt(String)
    case recoveryRequiresHuman

    var errorDescription: String? {
        switch self {
        case let .invalidContract(message): message
        case .archiveCapacityExceeded: "This change would exceed the portable archive limit. Export your existing history and use a smaller excerpt or a new project. No committed research was changed."
        case .unsupportedSchema: "This Research OS schema version is not supported."
        case .crossProject: "A private object cannot cross a project boundary."
        case .humanAuthorityRequired: "A named human actor must authorize repair or verification."
        case .proposalOnlyRequired: "AI-originated content must remain proposal-only."
        case .duplicateIdentity: "The event identity or idempotency key already has different content."
        case .staleHead: "The append-only journal advanced after this proposal was created."
        case let .corrupt(message): "The event journal is corrupt: \(message)."
        case .recoveryRequiresHuman: "Recovery requires an explicit human authority reference."
        }
    }
}
