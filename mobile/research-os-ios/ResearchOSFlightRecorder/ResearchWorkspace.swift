import Combine
import Foundation

enum WorkspaceClassification: String, Codable, CaseIterable {
    case syntheticDemo = "SYNTHETIC_DEMO_ONLY"
    case userCreated = "LOCAL_USER_CREATED_PROJECT"

    var label: String {
        switch self {
        case .syntheticDemo: "Invented example"
        case .userCreated: "Your local project"
        }
    }

    var boundary: String {
        switch self {
        case .syntheticDemo:
            "This project is an invented product example, not research evidence."
        case .userCreated:
            "Research OS organizes your entries but does not independently verify them."
        }
    }
}

enum ResearchProjectStatus: String, Codable {
    case active
    case archived
}

enum InboxReviewState: String, Codable, CaseIterable {
    case unreviewed
    case reviewed
    case excluded

    var label: String { rawValue.capitalized }
}

enum EvidenceSupport: String, Codable, CaseIterable {
    case supports
    case mixed
    case contradicts
    case unlinked

    var label: String {
        switch self {
        case .supports: "Supports"
        case .mixed: "Mixed"
        case .contradicts: "Contradicts"
        case .unlinked: "Not linked"
        }
    }
}

enum ReproducibilityState: String, Codable, CaseIterable {
    case open
    case ready
    case notApplicable

    var label: String {
        switch self {
        case .open: "Open"
        case .ready: "Ready for review"
        case .notApplicable: "Not applicable"
        }
    }
}

struct ResearchScope: Codable, Equatable {
    var question: String
    var population: String
    var variables: String
    var exclusions: String
}

struct ResearchProtocol: Codable, Equatable {
    var method: String
    var primaryOutcome: String
    var changePolicy: String
    var frozenByHuman: Bool
}

struct ResearchInboxItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var source: String
    var note: String
    var addedAt: Date
    var reviewState: InboxReviewState
    var classification: WorkspaceClassification
}

struct ClaimEvidenceLink: Codable, Equatable, Identifiable {
    var id: UUID
    var claim: String
    var evidencePointer: String
    var support: EvidenceSupport
    var limitation: String
    var humanReviewed: Bool
}

struct ExplicitRepairDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var before: String
    var after: String
    var reason: String
    var confirmedAt: Date?
}

struct DefensePrompt: Codable, Equatable, Identifiable {
    var id: UUID
    var objection: String
    var response: String
    var evidencePointer: String
}

struct ReproducibilityCheck: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var detail: String
    var state: ReproducibilityState
}

struct ResearchFileNode: Codable, Equatable, Identifiable {
    var id: UUID
    var path: String
    var purpose: String
    var status: String
}

struct ResearchProject: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var classification: WorkspaceClassification
    var status: ResearchProjectStatus
    var createdAt: Date
    var updatedAt: Date
    var scope: ResearchScope
    var protocolRecord: ResearchProtocol
    var inbox: [ResearchInboxItem]
    var claims: [ClaimEvidenceLink]
    var repairs: [ExplicitRepairDraft]
    var defense: [DefensePrompt]
    var reproducibility: [ReproducibilityCheck]
    var fileSystem: [ResearchFileNode]
    var proofGateConfirmedAt: Date?
    var plusWorkspaceActivatedAt: Date?
    // Optional for byte-compatible replay of all pre-Shipaton project snapshots.
    var argument: ResearchArgument? = nil
    // Nil stays absent from legacy snapshots; formatting never mutates this value.
    var publication: PublicationManuscript? = nil

    var proofGateReadiness: ProofGateReadiness {
        let checks = [
            !scope.question.trimmed.isEmpty,
            !scope.population.trimmed.isEmpty,
            !scope.variables.trimmed.isEmpty,
            !scope.exclusions.trimmed.isEmpty,
            protocolRecord.frozenByHuman,
            !claims.isEmpty && claims.allSatisfy {
                !$0.evidencePointer.trimmed.isEmpty && !$0.limitation.trimmed.isEmpty && $0.humanReviewed
            }
        ]
        let complete = checks.filter { $0 }.count
        return ProofGateReadiness(completedChecks: complete, totalChecks: checks.count)
    }
}

struct ProofGateReadiness: Equatable {
    let completedChecks: Int
    let totalChecks: Int

    var isReadyForHumanDecision: Bool { completedChecks == totalChecks }
}

enum ResearchWorkspaceEventKind: String, Codable, CaseIterable, Hashable {
    case argumentChanged = "argument.changed"
    case publicationSaved = "publication.saved"
    case projectCreated = "project.created"
    case projectSnapshotSaved = "project.snapshot_saved"
    case projectRenamed = "project.renamed"
    case projectArchived = "project.archived"
    case projectRestored = "project.restored"
    case projectDeleted = "project.deleted"
    case inboxItemAdded = "inbox.item_added"
    case inboxItemReviewed = "inbox.item_reviewed"
    case claimAdded = "claim.added"
    case repairProposed = "repair.proposed"
    case repairConfirmed = "repair.confirmed"
    case proofGateConfirmed = "verification.confirmed"
    case protocolFrozen = "protocol.frozen"
    case protocolAmendmentStarted = "protocol.amendment_started"
    case advancedWorkspaceActivated = "workspace.plus_activated"

    var workflowStage: ResearchWorkflowStage {
        switch self {
        case .repairProposed, .repairConfirmed:
            .repair
        case .proofGateConfirmed:
            .verify
        default:
            .review
        }
    }
}

struct ResearchWorkspaceHumanDecision: Codable, Equatable {
    let targetID: String
    let decision: String
    let decidedAt: String

    enum CodingKeys: String, CodingKey {
        case targetID = "target_id"
        case decision
        case decidedAt = "decided_at"
    }
}

/// The typed payload persisted inside every workspace event. The full project
/// value is a projection input, never a second source of truth.
struct ResearchWorkspaceEventPayload: Codable, Equatable {
    static let schemaID = "com.challa.research-os.mobile.workspace-command"

    let workspaceSchemaID: String
    let workspaceSchemaVersion: Int
    let command: ResearchWorkspaceEventKind
    let classification: WorkspaceClassification
    let workflowStage: ResearchWorkflowStage
    let mutations: [ResearchMutation]
    let humanDecision: ResearchWorkspaceHumanDecision?
    let tombstone: Bool

    enum CodingKeys: String, CodingKey {
        case workspaceSchemaID = "workspace_schema_id"
        case workspaceSchemaVersion = "workspace_schema_version"
        case command, classification
        case workflowStage = "workflow_stage"
        case mutations
        case humanDecision = "human_decision"
        case tombstone
    }

    init(
        command: ResearchWorkspaceEventKind,
        classification: WorkspaceClassification,
        mutations: [ResearchMutation],
        humanDecision: ResearchWorkspaceHumanDecision?,
        tombstone: Bool
    ) {
        workspaceSchemaID = Self.schemaID
        workspaceSchemaVersion = ResearchOSSchema.currentVersion
        self.command = command
        self.classification = classification
        workflowStage = command.workflowStage
        self.mutations = mutations
        self.humanDecision = humanDecision
        self.tombstone = tombstone
    }
}

@MainActor
final class ResearchWorkspaceStore: ObservableObject {
    @Published private(set) var projects: [ResearchProject]
    @Published var selectedProjectID: UUID?
    @Published private(set) var persistenceFailure: String?
    @Published private(set) var lastDeletionReceipt: ResearchProjectDeletionReceipt?
    @Published private(set) var deletionFailure: String?
    @Published private(set) var mutationAccessFailure: String?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var mutationCapacityFailure: String? = nil

    private(set) var storageDirectoryURL: URL?
    private var exportRootDirectoryURL: URL?
    private var eventStore: ResearchEventStore?
    private var persistedProjects: [UUID: ResearchProject] = [:]
    private var scheduledDraftWrites: [UUID: Task<Void, Never>] = [:]
    private let fileManager: FileManager
    private let clock: () -> Date
    private let makeUUID: () -> UUID
    private let draftPersistenceDelayNanoseconds: UInt64
    private let maximumArgumentArchiveBytes: Int
    private var subscriptionAccessState: SubscriptionAccessState = .free

    /// A new workspace is seeded only when its protected journal is empty. On
    /// restart, the journal is always authoritative and the supplied seeds are
    /// ignored. Injection points keep XCTest deterministic without changing the
    /// commercial-facing initializer or command APIs.
    init(
        projects seedProjects: [ResearchProject] = [.syntheticStarter],
        storageDirectory: URL? = nil,
        fileManager: FileManager = .default,
        clock: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        draftPersistenceDelayNanoseconds: UInt64 = 700_000_000,
        maximumArgumentArchiveBytes: Int = ResearchArgumentLimits.maximumArchiveBytes,
        atomicAppendWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        },
        atomicJournalWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    ) {
        projects = []
        selectedProjectID = nil
        persistenceFailure = nil
        lastDeletionReceipt = nil
        deletionFailure = nil
        mutationAccessFailure = nil
        recoveryMessage = nil
        storageDirectoryURL = nil
        exportRootDirectoryURL = nil
        eventStore = nil
        self.fileManager = fileManager
        // Canonical event dates have millisecond precision. Keep live state at
        // that same precision so export/reimport never changes a saved value.
        self.clock = {
            let value = clock()
            return Self.timestampDate(Self.timestamp(value)) ?? value
        }
        self.makeUUID = makeUUID
        self.draftPersistenceDelayNanoseconds = draftPersistenceDelayNanoseconds
        self.maximumArgumentArchiveBytes = min(maximumArgumentArchiveBytes, ResearchArgumentLimits.maximumArchiveBytes)

        do {
            let directory: URL
            if let storageDirectory {
                directory = storageDirectory
            } else {
                directory = try Self.defaultStorageDirectory(fileManager: fileManager)
            }
            storageDirectoryURL = directory
            exportRootDirectoryURL = directory.appendingPathComponent("ManagedExports", isDirectory: true)
            let store = try ResearchEventStore(
                rootDirectory: directory,
                fileManager: fileManager,
                atomicAppendWriter: atomicAppendWriter,
                atomicJournalWriter: atomicJournalWriter
            )
            eventStore = store
            if try store.isPristine() {
                for seed in seedProjects {
                    try appendTransition(
                        kind: .projectCreated,
                        from: nil,
                        to: seed,
                        occurredAt: seed.createdAt
                    )
                }
            }
            try reloadProjection()
        } catch {
            enterFailClosed(error)
        }
    }

    static func defaultStorageDirectory(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appComponent = Bundle.main.bundleIdentifier ?? "com.challa.research-os-flight-recorder"
#if DEBUG
        // UI tests get a fresh, bounded namespace. No real workspace is erased,
        // no arbitrary path is accepted, and no entitlement is overridden.
        if let raw = ProcessInfo.processInfo.environment["RESEARCH_PRO_UI_TEST_SESSION"], let session = UUID(uuidString: raw) {
            return applicationSupport.appendingPathComponent(appComponent, isDirectory: true)
                .appendingPathComponent("UITestWorkspaces", isDirectory: true)
                .appendingPathComponent(session.uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent("EventStore", isDirectory: true)
        }
#endif
        return applicationSupport
            .appendingPathComponent(appComponent, isDirectory: true)
            .appendingPathComponent("ResearchWorkspace", isDirectory: true)
            .appendingPathComponent("EventStore", isDirectory: true)
    }

    var activeProjects: [ResearchProject] {
        projects.filter { $0.status == .active }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var archivedProjects: [ResearchProject] {
        projects.filter { $0.status == .archived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var canRecoverCorruptTail: Bool {
        persistenceFailure != nil && eventStore?.audit().valid == false
    }

    @discardableResult
    func recoverCorruptTail() -> ResearchRecoveryReceipt? {
        guard canRecoverCorruptTail, let eventStore else { return nil }
        do {
            let receipt = try eventStore.recover(
                actorRef: "human:local",
                recoveredAt: Self.timestamp(clock())
            )
            guard let receipt else { return nil }
            try reloadProjection()
            persistenceFailure = nil
            recoveryMessage = "Recovered \(receipt.validEventCount) verified events and quarantined \(receipt.removedByteCount) corrupt bytes."
            return receipt
        } catch {
            persistenceFailure = "Local research history remains locked because recovery could not be verified. \(error.localizedDescription)"
            return nil
        }
    }

    /// Subscription authority is runtime state, never inferred from retained
    /// project data. Until the verified controller supplies Plus, the store
    /// fails closed to the deterministic one-project free editing floor.
    func updateSubscriptionAccess(_ state: SubscriptionAccessState) {
        // These edits were accepted while the previous entitlement authorized
        // them. Persist them before restricting future writes; downgrade must
        // never erase the last debounced keystrokes in a retained project.
        if subscriptionAccessState != state {
            do { try flushPendingChanges() }
            catch { /* flushPendingChanges records a visible persistence failure. */ }
        }
        subscriptionAccessState = state
        mutationAccessFailure = nil
    }

    func canMutateProject(id: UUID) -> Bool {
        guard eventStore != nil, persistenceFailure == nil,
              let project = project(id: id) else { return false }
        if project.classification == .syntheticDemo { return true }
        if subscriptionAccessState.grantsPlusAccess { return true }
        guard project.status == .active else { return false }
        return freeEditableUserProjectID == id
    }

    func mutationAccessReason(projectID: UUID) -> String? {
        guard !canMutateProject(id: projectID) else { return nil }
        guard let project = project(id: projectID) else {
            return "This project cannot be changed because its verified local history is unavailable."
        }
        if project.status == .archived {
            return "This archived project is read-only. Restore it within the available active-project capacity before editing."
        }
        let editableTitle = freeEditableUserProjectID.flatMap { self.project(id: $0)?.title }
        if let editableTitle {
            return "The free editing slot belongs to \(editableTitle). This retained project stays readable, exportable, and deletable until Plus access is verified."
        }
        return "This retained project stays readable, exportable, and deletable, but cannot be changed until Plus access is verified."
    }

    var inbox: [ResearchInboxItem] {
        projects
            .flatMap(\.inbox)
            .sorted { $0.addedAt > $1.addedAt }
    }

    func project(id: UUID) -> ResearchProject? {
        projects.first { $0.id == id }
    }

    @discardableResult
    func createProject(
        title: String,
        question: String,
        subscriptionState: SubscriptionAccessState = .free
    ) -> UUID? {
        let cleanTitle = title.trimmed
        let cleanQuestion = question.trimmed
        guard !cleanTitle.isEmpty, !cleanQuestion.isEmpty else { return nil }
        let activeUserProjectCount = activeProjects.filter { $0.classification == .userCreated }.count
        guard CommercialCapabilityPolicy.decision(
            for: .createAdditionalActiveProject,
            subscriptionState: subscriptionState,
            activeUserProjectCount: activeUserProjectCount
        ).allowsUse else { return nil }

        guard eventStore != nil, persistenceFailure == nil else { return nil }
        let now = clock()
        let project = ResearchProject.blank(
            title: cleanTitle,
            question: cleanQuestion,
            id: makeUUID(),
            now: now,
            makeUUID: makeUUID
        )
        do {
            try appendTransition(kind: .projectCreated, from: nil, to: project, occurredAt: now)
            projects.append(project)
            selectedProjectID = project.id
            return project.id
        } catch {
            enterFailClosed(error)
            return nil
        }
    }

    func activateAdvancedWorkspace(projectID: UUID, subscriptionState: SubscriptionAccessState) -> Bool {
        guard let project = project(id: projectID) else { return false }
        let decision = CommercialCapabilityPolicy.decision(
            for: .advancedWorkspace,
            subscriptionState: subscriptionState,
            activeUserProjectCount: activeProjects.filter { $0.classification == .userCreated }.count,
            project: project
        )
        guard decision.allowsUse else { return false }
        if decision == .activePlus {
            do {
                guard try commitProjectCommand(
                    id: projectID,
                    kind: .advancedWorkspaceActivated,
                    capabilityPolicyApproved: true,
                    change: { project, now in
                    project.plusWorkspaceActivatedAt = project.plusWorkspaceActivatedAt ?? now
                }) else { return false }
            } catch {
                enterFailClosed(error)
                return false
            }
        }
        return true
    }

    func renameProject(id: UUID, to title: String) {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { return }
        do {
            _ = try commitProjectCommand(id: id, kind: .projectRenamed) { project, _ in
                project.title = String(cleanTitle.prefix(120))
            }
        } catch { enterFailClosed(error) }
    }

    func archiveProject(id: UUID) {
        do {
            _ = try commitProjectCommand(
                id: id,
                kind: .projectArchived,
                capabilityPolicyApproved: true
            ) { project, _ in
                    project.status = .archived
                    project.proofGateConfirmedAt = nil
                }
        } catch { enterFailClosed(error) }
        if selectedProjectID == id { selectedProjectID = activeProjects.first?.id }
    }

    @discardableResult
    func restoreProject(
        id: UUID,
        subscriptionState: SubscriptionAccessState = .free
    ) -> Bool {
        guard let project = project(id: id) else { return false }
        if project.status == .active { return true }
        if project.classification == .userCreated {
            let decision = CommercialCapabilityPolicy.decision(
                for: .createAdditionalActiveProject,
                subscriptionState: subscriptionState,
                activeUserProjectCount: activeProjects.filter { $0.classification == .userCreated }.count
            )
            guard decision.allowsUse else { return false }
        }
        do {
            guard try commitProjectCommand(
                id: id,
                kind: .projectRestored,
                capabilityPolicyApproved: true,
                change: { project, _ in
                project.status = .active
            }) else { return false }
            selectedProjectID = id
            return true
        } catch {
            enterFailClosed(error)
            return false
        }
    }

    @discardableResult
    func deleteProject(id: UUID) -> ResearchProjectDeletionReceipt? {
        do {
            try flushPendingProject(id)
            guard let project = persistedProjects[id] else { return nil }
            let now = max(clock(), project.updatedAt)
            guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
            try purgeManagedExports(projectID: id)
            let receipt = try eventStore.purgeProject(
                projectID: Self.projectID(project.id),
                actorRef: "human:local",
                authorityRef: "role:owner",
                deletedAt: Self.timestamp(now)
            )
            persistedProjects.removeValue(forKey: id)
            projects.removeAll { $0.id == id }
            if selectedProjectID == id { selectedProjectID = activeProjects.first?.id }
            lastDeletionReceipt = receipt
            deletionFailure = nil
            return receipt
        } catch {
            if eventStore?.audit().valid == true {
                deletionFailure = "Project purge did not complete. The live project and event journal were kept. \(error.localizedDescription)"
            } else {
                enterFailClosed(error)
            }
            return nil
        }
    }

    /// Text editors bind to this bounded draft projection. Repeated keystrokes
    /// replace one scheduled snapshot; semantic buttons use immediate commands.
    func updateProject(id: UUID, _ change: (inout ResearchProject) -> Void) {
        guard authorizeMutation(projectID: id),
              let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let before = projects[index]
        var updated = before
        change(&updated)
        // Canonical argument changes require a typed, version-checked human command.
        guard updated.argument == before.argument, updated.publication == before.publication else {
            mutationAccessFailure = "Use the evidence, repair, defense or manuscript Save actions to change canonical records."
            return
        }
        guard updated != before else { return }
        updated.updatedAt = max(clock(), before.updatedAt)
        if !updated.proofGateReadiness.isReadyForHumanDecision { updated.proofGateConfirmedAt = nil }
        projects[index] = updated
        scheduleDraftPersistence(for: id)
    }

    func addInboxItem(
        projectID: UUID,
        title: String,
        source: String,
        note: String,
        classification: WorkspaceClassification = .userCreated
    ) {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty,
              project(id: projectID)?.classification == classification else { return }
        let now = max(clock(), project(id: projectID)?.updatedAt ?? .distantPast)
        let item = ResearchInboxItem(
            id: makeUUID(),
            title: String(cleanTitle.prefix(160)),
            source: String(source.trimmed.prefix(240)),
            note: String(note.trimmed.prefix(4_000)),
            addedAt: now,
            reviewState: .unreviewed,
            classification: classification
        )
        do {
            _ = try commitProjectCommand(id: projectID, kind: .inboxItemAdded) { project, _ in
                project.inbox.append(item)
            }
        } catch { enterFailClosed(error) }
    }

    func updateInboxItem(projectID: UUID, itemID: UUID, state: InboxReviewState) {
        do {
            _ = try commitProjectCommand(id: projectID, kind: .inboxItemReviewed) { project, _ in
                guard let index = project.inbox.firstIndex(where: { $0.id == itemID }) else { return }
                project.inbox[index].reviewState = state
            }
        } catch { enterFailClosed(error) }
    }

    func addClaim(projectID: UUID, claim: String, evidence: String, limitation: String) {
        let cleanClaim = claim.trimmed
        guard !cleanClaim.isEmpty else { return }
        let link = ClaimEvidenceLink(
                id: makeUUID(),
                claim: cleanClaim,
                evidencePointer: evidence.trimmed,
                support: evidence.trimmed.isEmpty ? .unlinked : .mixed,
                limitation: limitation.trimmed,
                humanReviewed: false
            )
        do {
            _ = try commitProjectCommand(id: projectID, kind: .claimAdded) { project, _ in
                project.claims.append(link)
            }
        } catch { enterFailClosed(error) }
    }

    func addRepair(projectID: UUID, before: String, after: String, reason: String) {
        guard !before.trimmed.isEmpty, !after.trimmed.isEmpty else { return }
        let repair = ExplicitRepairDraft(
                id: makeUUID(),
                before: before.trimmed,
                after: after.trimmed,
                reason: reason.trimmed,
                confirmedAt: nil
            )
        do {
            _ = try commitProjectCommand(id: projectID, kind: .repairProposed) { project, _ in
                project.repairs.append(repair)
            }
        } catch { enterFailClosed(error) }
    }

    func confirmRepair(projectID: UUID, repairID: UUID) {
        let targetID = "repair-\(repairID.uuidString.lowercased())"
        do {
            _ = try commitProjectCommand(
                id: projectID,
                kind: .repairConfirmed,
                decision: { now in
                    ResearchWorkspaceHumanDecision(
                        targetID: targetID,
                        decision: "confirmed",
                        decidedAt: Self.timestamp(now)
                    )
                },
                causeRefs: [targetID]
            ) { project, now in
                guard let index = project.repairs.firstIndex(where: { $0.id == repairID }) else { return }
                project.repairs[index].confirmedAt = project.repairs[index].confirmedAt ?? now
            }
        } catch { enterFailClosed(error) }
    }

    func recordProofGateDecision(projectID: UUID) {
        do {
            try flushPendingProject(projectID)
            guard project(id: projectID)?.proofGateReadiness.isReadyForHumanDecision == true else { return }
            _ = try commitProjectCommand(
                id: projectID,
                kind: .proofGateConfirmed,
                decision: { now in
                    ResearchWorkspaceHumanDecision(
                        targetID: "proof-gate",
                        decision: "confirmed",
                        decidedAt: Self.timestamp(now)
                    )
                },
                causeRefs: ["proof-gate"]
            ) { project, now in
                project.proofGateConfirmedAt = project.proofGateConfirmedAt ?? now
            }
        } catch { enterFailClosed(error) }
    }

    func setProtocolFrozen(projectID: UUID, isFrozen: Bool) {
        let kind: ResearchWorkspaceEventKind = isFrozen ? .protocolFrozen : .protocolAmendmentStarted
        do {
            _ = try commitProjectCommand(
                id: projectID,
                kind: kind,
                decision: { now in
                    ResearchWorkspaceHumanDecision(
                        targetID: "protocol",
                        decision: isFrozen ? "frozen" : "amendment_started",
                        decidedAt: Self.timestamp(now)
                    )
                },
                causeRefs: ["protocol"]
            ) { project, _ in
                project.protocolRecord.frozenByHuman = isFrozen
            }
        } catch { enterFailClosed(error) }
    }

    // MARK: Research Pro argument commands
    func savePublication(projectID: UUID, manuscript: PublicationManuscript, expectedRevision: Int?) throws {
        guard authorizeMutation(projectID: projectID) else { throw ResearchArgumentError.unavailable }
        try flushPendingProject(projectID)
        guard let project = project(id: projectID) else { throw ResearchWorkspaceError.projectNotFound }
        guard project.publication?.revision == expectedRevision else { throw ResearchArgumentError.stale }
        if let prior = project.publication {
            guard prior.id == manuscript.id else { throw PublicationError.invalid("A saved manuscript's identity cannot be replaced.") }
            if prior == manuscript { return }
        }
        var next = manuscript
        next.revision = (project.publication?.revision ?? 0) + 1
        try next.validate()
        guard try commitProjectCommand(id: projectID, kind: .publicationSaved, decision: { now in
            ResearchWorkspaceHumanDecision(targetID: "publication-\(next.id.uuidString.lowercased())", decision: "saved", decidedAt: Self.timestamp(now))
        }, change: { project, _ in project.publication = next }) else { throw ResearchArgumentError.unavailable }
    }

    @discardableResult
    func addArgumentSource(projectID: UUID, title: String, origin: String, excerpt: String,
                           locator: String = "", population: String = "", design: ArgumentStudyDesign = .unknown,
                           document: ArgumentDocumentSnapshot? = nil, selectedPage: Int? = nil) throws -> UUID {
        let source = ArgumentSource(title: title, origin: origin, excerpt: excerpt, locator: locator, population: population, design: design,
                                    document: document, selectedPage: selectedPage)
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .sourceAdded(source)))
        return source.id
    }
    @discardableResult
    func addArgumentClaim(projectID: UUID, text: String, sourceIDs: [UUID],
                          relationship: ArgumentRelationship = .support, limitation: String = "") throws -> UUID {
        let claim = ArgumentClaim(text: text, limitation: limitation, links: sourceIDs.map { ArgumentEvidenceLink(sourceID: $0, relationship: relationship) })
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .claimAdded(claim)))
        return claim.id
    }
    func reviseArgumentClaim(projectID: UUID, claimID: UUID, links: [ArgumentEvidenceLink], limitation: String,
                             disposition: ArgumentClaimDisposition = .active, reason: String, expectedVersion: Int? = nil) throws {
        guard let argument = project(id: projectID)?.argument, let prior = argument.claims.first(where: { $0.id == claimID }) else { throw ResearchArgumentError.unavailable }
        if let expectedVersion, prior.version != expectedVersion { throw ResearchArgumentError.stale }
        if prior.links == links && prior.limitation == limitation && prior.effectiveDisposition == disposition { return }
        var revised = prior
        revised.links = links
        revised.limitation = limitation
        revised.disposition = disposition
        revised.version += 1
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .claimRevised(claim: revised, baseDigest: try argument.basisDigest(claimID: claimID), reason: reason)))
    }
    func proposeArgumentRepair(projectID: UUID, claimID: UUID, after: String, reason: String) throws -> ArgumentRepairProposal {
        guard let argument = project(id: projectID)?.argument else { throw ResearchArgumentError.unavailable }
        return try argument.proposal(claimID: claimID, after: after, reason: reason)
    }
    func acceptArgumentRepair(projectID: UUID, proposal: ArgumentRepairProposal) throws {
        let command = ArgumentCommand(id: proposal.id, action: .repairAccepted(proposal: proposal, at: Self.timestamp(clock())))
        try applyArgumentCommand(projectID: projectID, command: command)
    }
    func previewEvidenceExclusion(projectID: UUID, sourceID: UUID) throws -> ArgumentImpactPreview {
        guard let argument = project(id: projectID)?.argument else { throw ResearchArgumentError.unavailable }
        return try argument.impact(sourceID: sourceID)
    }
    func setArgumentSourceIncluded(projectID: UUID, sourceID: UUID, included: Bool, reason: String) throws {
        guard let source = project(id: projectID)?.argument?.sources.first(where: { $0.id == sourceID }) else { throw ResearchArgumentError.unavailable }
        if source.included == included { return }
        var revised = source
        revised.included = included
        revised.version += 1
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .sourceRevised(source: revised, baseDigest: try CanonicalJSON.digest(source), reason: reason)))
    }
    func reviseArgumentSource(projectID: UUID, sourceID: UUID, excerpt: String, reason: String, expectedVersion: Int? = nil) throws {
        guard let source = project(id: projectID)?.argument?.sources.first(where: { $0.id == sourceID }) else { throw ResearchArgumentError.unavailable }
        if let expectedVersion, source.version != expectedVersion { throw ResearchArgumentError.stale }
        if source.excerpt == excerpt { return }
        var revised = source
        revised.excerpt = excerpt
        if let document = source.document, let page = source.selectedPage,
           !document.contains(quote: excerpt, page: page) {
            // A manual revision must not inherit an exact-import claim it no
            // longer satisfies. Prior document bytes/text remain in the journal.
            revised.document = nil
            revised.selectedPage = nil
            revised.locator = "Author-edited snapshot; prior import retained in history"
        }
        revised.version += 1
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .sourceRevised(source: revised, baseDigest: try CanonicalJSON.digest(source), reason: reason)))
    }
    @discardableResult
    func startArgumentDefense(projectID: UUID, claimID: UUID, advanced: Bool = false) throws -> UUID {
        guard let argument = project(id: projectID)?.argument else { throw ResearchArgumentError.unavailable }
        if advanced && !subscriptionAccessState.grantsPlusAccess { throw ResearchArgumentError.premiumRequired }
        if !advanced, let existing = argument.defenseSessions.last(where: { $0.claimID == claimID && !$0.advanced && !$0.isStale }) { return existing.id }
        let session = try argument.defense(claimID: claimID, advanced: advanced)
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .defenseStarted(session)))
        return session.id
    }
    func saveArgumentDefense(projectID: UUID, sessionID: UUID, answers: [String: String], citedSourceIDs: [UUID], limitation: String) throws {
        try applyArgumentCommand(projectID: projectID, command: ArgumentCommand(action: .defenseAnswered(sessionID: sessionID, answers: answers, sourceIDs: citedSourceIDs, limitation: limitation, at: Self.timestamp(clock()))))
    }
    private func applyArgumentCommand(projectID: UUID, command: ArgumentCommand) throws {
        guard authorizeMutation(projectID: projectID) else { throw ResearchArgumentError.unavailable }
        try flushPendingProject(projectID)
        guard let project = project(id: projectID) else { throw ResearchArgumentError.unavailable }
        let previous = project.argument ?? ResearchArgument()
        let next = try previous.applying(command)
        guard next != previous else { return }
        guard try commitProjectCommand(id: projectID, kind: .argumentChanged, decision: { now in
            ResearchWorkspaceHumanDecision(targetID: "argument-\(command.id.uuidString.lowercased())", decision: "accepted", decidedAt: Self.timestamp(now))
        }, change: { project, _ in project.argument = next }) else { throw ResearchArgumentError.unavailable }
    }
    @discardableResult
    func createArgumentSample() throws -> UUID {
        if let existing = projects.first(where: { $0.classification == .syntheticDemo && $0.argument != nil }) {
            selectedProjectID = existing.id
            return existing.id
        }
        guard eventStore != nil, persistenceFailure == nil else { throw ResearchArgumentError.unavailable }
        let now = clock()
        var project = ResearchProject.blank(title: "Music and recall — synthetic sample", question: "How did recall differ in this invented classroom sample?", id: makeUUID(), now: now, makeUUID: makeUUID)
        project.classification = .syntheticDemo
        try appendTransition(kind: .projectCreated, from: nil, to: project, occurredAt: now)
        projects.append(project)
        selectedProjectID = project.id
        let quiet = [6, 7, 5, 8, 7, 6, 5, 8, 6, 7, 7, 6]
        let music = [7, 7, 6, 8, 7, 7, 6, 8, 6, 7, 8, 6]
        let total = quiet.count * 10
        let q = quiet.reduce(0, +), m = music.reduce(0, +)
        let delta = Double(m - q) / Double(total) * 100
        let rows = quiet.indices.map { "\($0 + 1),\(quiet[$0]),\(music[$0])" }.joined(separator: "\n")
        let excerpt = "SYNTHETIC: twelve invented paired rows; each score is out of ten. Nonrandom condition order.\nstudent,quiet,music\n\(rows)\nComputed totals: quiet \(q)/\(total), music \(m)/\(total). Descriptive difference: \(String(format: "%.2f", delta)) percentage points. No causal or population inference."
        let sourceID = try addArgumentSource(projectID: project.id, title: "Invented observation table", origin: "Bundled synthetic teaching example", excerpt: excerpt, locator: "All 12 CSV rows", population: "12 invented students in one classroom", design: .observational)
        _ = try addArgumentClaim(projectID: project.id, text: "Instrumental music improves recall for all students.", sourceIDs: [sourceID], limitation: "Invented class sample; nonrandom condition order.")
        let contextID = try addArgumentSource(projectID: project.id, title: "Invented room note", origin: "Bundled synthetic teaching example", excerpt: "The same classroom was used for both invented conditions.", locator: "Room note", population: "This invented classroom", design: .unknown)
        _ = try addArgumentClaim(projectID: project.id, text: "Both conditions used the same classroom in this invented example.", sourceIDs: [contextID], limitation: "Room identity alone does not control order or measurement effects.")
        return project.id
    }
    @discardableResult
    func importArchiveData(_ data: Data) throws -> UUID {
        guard data.count <= ResearchArgumentLimits.maximumArchiveBytes else { throw ResearchArgumentError.invalid("Research archives must be 20 MB or smaller.") }
        guard let eventStore, persistenceFailure == nil else { throw ResearchWorkspaceError.persistenceUnavailable }
        let archive = try JSONDecoder().decode(ResearchEventArchive.self, from: data)
        guard archive.events.count <= 10_000, let identity = UUID(uuidString: archive.projectID) else { throw ResearchArgumentError.invalid("Unsupported archive identity or event count.") }
        // Validate typed authority and all projections before any persistent write.
        let imported = try Self.materializeProjection(from: archive.events)
        guard imported.count == 1, imported[0].id == identity else { throw ResearchArgumentError.invalid("An archive must contain one complete project.") }
        _ = try eventStore.validateArchive(data, expectedProjectID: archive.projectID)
        // Reloading the journal must never replace unsaved drafts in this or
        // another project. Persist authorized drafts before the atomic import.
        try flushPendingChanges()
        _ = try eventStore.importArchive(data, expectedProjectID: archive.projectID)
        try reloadProjection()
        selectedProjectID = identity
        return identity
    }
    func exportResearchBriefFile(id: UUID) throws -> URL {
        try flushPendingProject(id)
        guard let project = project(id: id), let exportRootDirectoryURL else { throw ResearchWorkspaceError.projectNotFound }
        let directory = exportRootDirectoryURL.appendingPathComponent(Self.projectID(id), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Blank-line-delimited indented code blocks render imported text
        // literally, including Markdown headings, links, and raw HTML.
        func literal(_ value: String) -> [String] {
            let lines = value.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            return [""] + lines.map { "    \($0)" } + [""]
        }
        var lines = ["# Research defense brief", "", "Project title:"] + literal(project.title)
        lines += ["", "Classification: \(project.classification.label)", "", "## Research question"] + literal(project.scope.question)
        lines += ["", "## Scope and protocol", "Population:"] + literal(project.scope.population)
        lines += ["Variables:"] + literal(project.scope.variables)
        lines += ["Exclusions:"] + literal(project.scope.exclusions)
        lines += ["Method:"] + literal(project.protocolRecord.method)
        lines += ["Frozen by human: \(project.protocolRecord.frozenByHuman)"]
        let reviewItems = project.argument?.exportReviewItems ?? [ArgumentExportReviewItem(
            id: "no-argument", claimID: nil, message: "No argument or claims have been recorded for this brief.")]
        lines += ["", "## Review before sharing",
                  "This is a structural traceability check, not a scientific verdict. Human review is required even if no items are listed.",
                  "Review items: \(reviewItems.count)"]
        if reviewItems.isEmpty { lines.append("No structural review items detected.") }
        for item in reviewItems { lines += ["Review item:"] + literal(item.message) }
        lines += ["", "## Claims"]
        if let argument = project.argument {
            for claim in argument.claims {
                lines += ["", "### \(claim.effectiveDisposition.rawValue.uppercased()) claim \(claim.id) · version \(claim.version)"]
                lines += literal(claim.text)
                lines += ["Disposition: \(claim.effectiveDisposition.rawValue)", "Limitation:"] + literal(claim.limitation)
                for link in claim.links { lines += ["- \(link.relationship.rawValue): source \(link.sourceID)"] }
            }
            lines += ["", "## Sources and exact local snapshots"]
            for source in argument.sources {
                lines += ["", "### Source \(source.id) · version \(source.version)", "Title:"] + literal(source.title)
                lines += ["Origin:"] + literal(source.origin)
                lines += ["Locator:"] + literal(source.locator)
                lines += ["Population:"] + literal(source.population)
                lines += ["Design: \(source.design.rawValue)", "Included: \(source.included)", "", "Exact excerpt:"] + literal(source.excerpt)
                if let document = source.document {
                    lines += ["Original file SHA-256: \(document.originalSHA256)", "Extraction: local PDFKit/text v\(document.extractionVersion); whitespace-normalized quote match only. Full extracted pages retained in companion archive."]
                }
            }
            lines += ["", "## Human repair decisions"]
            for repair in argument.repairs {
                lines += ["", "Before:"] + literal(repair.proposal.before)
                lines += ["After:"] + literal(repair.proposal.after)
                lines += ["Reason:"] + literal(repair.proposal.reason)
                lines += ["Actor:"] + literal(repair.actor)
                lines += ["Accepted at: \(repair.acceptedAt)", "Basis digest: \(repair.proposal.baseDigest)"]
            }
            lines += ["", "## Defense Lab"]
            for session in argument.defenseSessions {
                lines += ["", "### \(session.advanced ? "Advanced" : "Standard") session \(session.id)", "Claim: \(session.claimID)", "Stale: \(session.isStale)", "Coverage:"] + literal(session.coverageDescription)
                for question in session.questions {
                    lines += ["", "Question:"] + literal(question.prompt)
                    lines += ["Answer:"] + literal(session.answers[question.id] ?? "Unanswered")
                }
                lines += ["Cited sources: \(session.citedSourceIDs.map(\.uuidString).joined(separator: ", "))", "Acknowledged limitation:"] + literal(session.limitation)
            }
        }
        lines += ["", "## Provenance and limits", "AI contribution: none in the deterministic argument and defense workflow; any optional legacy AI output remains a proposal.", "The companion event archive preserves versions, decisions, and event digests. Local hashes check bytes and lineage, not scientific truth, peer review, or independently witnessed timing."]
        for event in try eventHistory(projectID: id) { lines += ["- \(event.sequence): \(event.kind) · \(event.occurredAt) · \(event.chainDigest)"] }
        let url = directory.appendingPathComponent("Research-Defense-Brief.md")
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func exportPublicationFiles(id: UUID, profile: PublicationProfile) throws -> (files: [URL], preflight: PublicationPreflight) {
        try flushPendingProject(id)
        guard let manuscript = project(id: id)?.publication, let root = exportRootDirectoryURL else {
            throw PublicationError.invalid("Save a manuscript before exporting.")
        }
        let result = try PublicationRenderer.render(manuscript, profile: profile)
        let directory = root.appendingPathComponent(Self.projectID(id), isDirectory: true)
            .appendingPathComponent("Publication", isDirectory: true)
            .appendingPathComponent("r\(manuscript.revision)-\(profile.id)-\(UUID().uuidString)", isDirectory: true)
        return (try result.write(to: directory), result.preflight)
    }

    func exportProjectFile(id: UUID) throws -> URL {
        let data = try exportArchiveData(id: id)
        guard let project = project(id: id) else { throw ResearchWorkspaceError.projectNotFound }
        let safeTitle = project.title
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard let exportRootDirectoryURL else { throw ResearchWorkspaceError.persistenceUnavailable }
        let projectDirectory = exportRootDirectoryURL
            .appendingPathComponent(Self.projectID(id), isDirectory: true)
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try Self.applyCompleteProtection(to: exportRootDirectoryURL, fileManager: fileManager)
        try Self.applyCompleteProtection(to: projectDirectory, fileManager: fileManager)
        let url = projectDirectory
            .appendingPathComponent("\(safeTitle.isEmpty ? "Research-Project" : safeTitle)-event-archive.json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func exportArchiveData(id: UUID) throws -> Data {
        do {
            try flushPendingProject(id)
            guard persistedProjects[id] != nil else { throw ResearchWorkspaceError.projectNotFound }
            guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
            return try eventStore.exportArchive(projectID: Self.projectID(id))
        } catch {
            if !(error is ResearchWorkspaceError) { enterFailClosed(error) }
            throw error
        }
    }

    /// Synchronous save boundary used by export, lifecycle commands, and tests.
    func flushPendingChanges() throws {
        do {
            for id in scheduledDraftWrites.keys.sorted(by: {
                $0.uuidString.lowercased() < $1.uuidString.lowercased()
            }) {
                try flushPendingProject(id)
            }
        } catch {
            enterFailClosed(error)
            throw error
        }
    }

    func eventHistory(projectID: UUID) throws -> [ResearchEventEnvelope] {
        guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
        return try eventStore.events(projectID: Self.projectID(projectID))
    }

    func project(id: UUID, throughSequence: Int) throws -> ResearchProject? {
        guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
        let events = try eventStore.events(
            projectID: Self.projectID(id),
            branchID: "main",
            throughSequence: throughSequence
        )
        return try Self.materializeProjection(from: events).first(where: { $0.id == id })
    }

    private func commitProjectCommand(
        id: UUID,
        kind: ResearchWorkspaceEventKind,
        decision: ((Date) -> ResearchWorkspaceHumanDecision)? = nil,
        causeRefs: [String] = [],
        capabilityPolicyApproved: Bool = false,
        change: (inout ResearchProject, Date) -> Void
    ) throws -> Bool {
        guard capabilityPolicyApproved || authorizeMutation(projectID: id) else { return false }
        try flushPendingProject(id)
        guard let index = projects.firstIndex(where: { $0.id == id }),
              let persisted = persistedProjects[id] else { return false }
        let now = max(clock(), persisted.updatedAt)
        var updated = projects[index]
        change(&updated, now)
        guard updated != projects[index] else { return true }
        updated.updatedAt = now
        if !updated.proofGateReadiness.isReadyForHumanDecision { updated.proofGateConfirmedAt = nil }
        try appendTransition(
            kind: kind,
            from: persisted,
            to: updated,
            occurredAt: now,
            humanDecision: decision?(now),
            causeRefs: causeRefs
        )
        projects[index] = updated
        return true
    }

    private func scheduleDraftPersistence(for id: UUID) {
        scheduledDraftWrites[id]?.cancel()
        let delay = draftPersistenceDelayNanoseconds
        scheduledDraftWrites[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return }
            guard let self else { return }
            self.scheduledDraftWrites[id] = nil
            do { try self.flushPendingProject(id) }
            catch { self.enterFailClosed(error) }
        }
    }

    private func flushPendingProject(_ id: UUID) throws {
        scheduledDraftWrites[id]?.cancel()
        scheduledDraftWrites[id] = nil
        guard let current = projects.first(where: { $0.id == id }),
              let persisted = persistedProjects[id], current != persisted else { return }
        guard canMutateProject(id: id) else {
            restorePersistedProjection(id: id)
            return
        }
        try appendTransition(
            kind: .projectSnapshotSaved,
            from: persisted,
            to: current,
            occurredAt: current.updatedAt
        )
    }

    private func appendTransition(
        kind: ResearchWorkspaceEventKind,
        from previous: ResearchProject?,
        to next: ResearchProject?,
        occurredAt: Date,
        humanDecision: ResearchWorkspaceHumanDecision? = nil,
        causeRefs: [String] = []
    ) throws {
        guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
        guard let identity = next?.id ?? previous?.id else {
            throw ResearchWorkspaceError.invalidProjection("A workspace event is missing its project identity.")
        }
        let projectID = Self.projectID(identity)
        let existing = try eventStore.events(projectID: projectID)
        let nextSequence = (existing.last?.sequence ?? 0) + 1
        let ref = try ResearchObjectRef(
            projectID: projectID,
            objectType: "project",
            logicalID: projectID,
            version: nextSequence
        )
        let mutation: ResearchMutation
        if let next {
            mutation = try ResearchMutation(
                ref: ref,
                operation: .put,
                value: try Self.projectValue(next)
            )
        } else {
            mutation = try ResearchMutation(ref: ref, operation: .delete)
        }
        let classification = next?.classification ?? previous?.classification
        guard let classification else {
            throw ResearchWorkspaceError.invalidProjection("A workspace event is missing its classification.")
        }
        let payload = ResearchWorkspaceEventPayload(
            command: kind,
            classification: classification,
            mutations: [mutation],
            humanDecision: humanDecision,
            tombstone: next == nil
        )
        try Self.validateTransition(command: kind, previous: previous, next: next, payload: payload)
        let commandID = makeUUID().uuidString.lowercased()
        let draft = try ResearchEventDraft(
            eventID: "event-\(commandID)",
            projectID: projectID,
            branchID: "main",
            kind: kind.rawValue,
            actorRef: "human:local",
            authorityRef: "role:owner",
            origin: "ios:local",
            idempotencyKey: "command-\(commandID)",
            occurredAt: Self.timestamp(occurredAt),
            priorProjectDigest: try previous.map { try Self.projectDigest($0) } ?? ResearchOSSchema.zeroDigest,
            resultProjectDigest: try next.map { try Self.projectDigest($0) } ?? ResearchOSSchema.zeroDigest,
            payload: try CanonicalJSON.value(from: payload),
            causeRefs: causeRefs,
            objectRefs: [ref],
            parentEventIDs: existing.last.map { [$0.eventID] } ?? []
        )
        do {
            _ = try eventStore.append(
                draft,
                expectedChainDigest: existing.last?.chainDigest ?? ResearchOSSchema.zeroDigest,
                // Every event carries a full snapshot, including embedded manuscript assets.
                // Guard all append kinds so every committed archive remains reimportable.
                maximumProjectArchiveBytes: maximumArgumentArchiveBytes
            )
            mutationCapacityFailure = nil
        } catch ResearchOSCoreError.archiveCapacityExceeded(let projectID) {
            if let id = UUID(uuidString: projectID) { restorePersistedProjection(id: id) }
            let failure = ResearchOSCoreError.archiveCapacityExceeded(projectID: projectID)
            mutationCapacityFailure = failure.localizedDescription
            throw failure
        }
        if let next { persistedProjects[identity] = next }
        else { persistedProjects.removeValue(forKey: identity) }
    }

    private func reloadProjection() throws {
        guard let eventStore else { throw ResearchWorkspaceError.persistenceUnavailable }
        let loaded = try Self.materializeProjection(from: eventStore.allEvents())
        projects = loaded
        persistedProjects = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        if let selectedProjectID, loaded.contains(where: { $0.id == selectedProjectID }) { return }
        selectedProjectID = loaded.first(where: { $0.status == .active })?.id
    }

    private var freeEditableUserProjectID: UUID? {
        projects
            .filter { $0.classification == .userCreated && $0.status == .active }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return Self.projectID($0.id) < Self.projectID($1.id)
            }
            .first?.id
    }

    private func authorizeMutation(projectID: UUID) -> Bool {
        guard canMutateProject(id: projectID) else {
            mutationAccessFailure = mutationAccessReason(projectID: projectID)
            return false
        }
        mutationAccessFailure = nil
        return true
    }

    private func restorePersistedProjection(id: UUID) {
        guard let persisted = persistedProjects[id],
              let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index] = persisted
    }

    private func purgeManagedExports(projectID: UUID) throws {
        guard let exportRootDirectoryURL else { throw ResearchWorkspaceError.persistenceUnavailable }
        let root = exportRootDirectoryURL.standardizedFileURL
        let projectDirectory = root
            .appendingPathComponent(Self.projectID(projectID), isDirectory: true)
            .standardizedFileURL
        guard projectDirectory.deletingLastPathComponent() == root else {
            throw ResearchWorkspaceError.invalidProjection("The managed export path escaped its protected root.")
        }
        if fileManager.fileExists(atPath: projectDirectory.path) {
            try fileManager.removeItem(at: projectDirectory)
        }
        guard !fileManager.fileExists(atPath: projectDirectory.path) else {
            throw ResearchWorkspaceError.exportPurgeFailed
        }
        // Partial forms are private project data too; purge only this project's
        // exact app-managed directory before removing its canonical journal.
        if let storageDirectoryURL {
            let draftsRoot = storageDirectoryURL.appendingPathComponent("FormDrafts", isDirectory: true).standardizedFileURL
            let drafts = draftsRoot.appendingPathComponent(Self.projectID(projectID), isDirectory: true).standardizedFileURL
            guard drafts.deletingLastPathComponent() == draftsRoot else { throw ResearchWorkspaceError.exportPurgeFailed }
            if fileManager.fileExists(atPath: drafts.path) { try fileManager.removeItem(at: drafts) }
            guard !fileManager.fileExists(atPath: drafts.path) else { throw ResearchWorkspaceError.exportPurgeFailed }
        }
    }

    private static func materializeProjection(from events: [ResearchEventEnvelope]) throws -> [ResearchProject] {
        var states: [UUID: ResearchProject] = [:]
        var creationOrder: [UUID] = []
        var seenIdentities: Set<UUID> = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = timestampDate(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a UTC ISO-8601 workspace timestamp."
                )
            }
            return date
        }

        for event in events {
            guard event.branchID == "main", let identity = UUID(uuidString: event.projectID) else {
                throw ResearchWorkspaceError.invalidProjection("Workspace events must address a UUID project on the main branch.")
            }
            let payload = try decoder.decode(
                ResearchWorkspaceEventPayload.self,
                from: CanonicalJSON.encode(event.payload)
            )
            guard payload.workspaceSchemaID == ResearchWorkspaceEventPayload.schemaID,
                  payload.workspaceSchemaVersion == ResearchOSSchema.currentVersion,
                  payload.command.rawValue == event.kind,
                  payload.workflowStage == payload.command.workflowStage,
                  payload.mutations.count == 1,
                  event.actorRef.hasPrefix("human:") else {
                throw ResearchWorkspaceError.invalidProjection("Workspace event metadata is inconsistent.")
            }

            let previous = states[identity]
            let expectedPrior = try previous.map { try Self.projectDigest($0) } ?? ResearchOSSchema.zeroDigest
            guard event.priorProjectDigest == expectedPrior else {
                throw ResearchWorkspaceError.invalidProjection("Workspace transition prior digest does not match its projection.")
            }

            let mutation = payload.mutations[0]
            guard mutation.ref.projectID == event.projectID,
                  mutation.ref.objectType == "project",
                  mutation.ref.logicalID == event.projectID,
                  mutation.ref.version == event.sequence,
                  event.objectRefs == [mutation.ref] else {
                throw ResearchWorkspaceError.invalidProjection("Workspace mutation identity or version is inconsistent.")
            }

            let next: ResearchProject?
            switch mutation.operation {
            case .put:
                guard !payload.tombstone else {
                    throw ResearchWorkspaceError.invalidProjection("A project value cannot also be a tombstone.")
                }
                let decoded = try decoder.decode(ResearchProject.self, from: CanonicalJSON.encode(mutation.value))
                guard decoded.id == identity, decoded.classification == payload.classification else {
                    throw ResearchWorkspaceError.invalidProjection("The projected project does not match its event identity.")
                }
                if payload.command == .projectCreated {
                    guard previous == nil, seenIdentities.insert(identity).inserted else {
                        throw ResearchWorkspaceError.invalidProjection("A project identity cannot be created twice.")
                    }
                    creationOrder.append(identity)
                } else if previous == nil {
                    throw ResearchWorkspaceError.invalidProjection("A project update is missing its creation event.")
                }
                next = decoded
                states[identity] = decoded
            case .delete:
                guard payload.tombstone, payload.command == .projectDeleted, previous != nil else {
                    throw ResearchWorkspaceError.invalidProjection("A project tombstone is not valid at this position.")
                }
                next = nil
                states.removeValue(forKey: identity)
            }

            try validateTransition(command: payload.command, previous: previous, next: next, payload: payload)
            let expectedResult = try next.map { try Self.projectDigest($0) } ?? ResearchOSSchema.zeroDigest
            guard event.resultProjectDigest == expectedResult else {
                throw ResearchWorkspaceError.invalidProjection("Workspace transition result digest does not match its projection.")
            }
            let requiresDecision = payload.command == .repairConfirmed || payload.command == .proofGateConfirmed
            guard !requiresDecision || payload.humanDecision != nil else {
                throw ResearchWorkspaceError.invalidProjection("A human repair or proof decision is missing its decision receipt.")
            }
        }
        return creationOrder.compactMap { states[$0] }
    }

    private static func validateTransition(
        command: ResearchWorkspaceEventKind,
        previous: ResearchProject?,
        next: ResearchProject?,
        payload: ResearchWorkspaceEventPayload
    ) throws {
        let decisionCommands: Set<ResearchWorkspaceEventKind> = [
            .repairConfirmed, .proofGateConfirmed, .protocolFrozen, .protocolAmendmentStarted, .argumentChanged, .publicationSaved,
        ]
        guard decisionCommands.contains(command) == (payload.humanDecision != nil) else {
            throw ResearchWorkspaceError.invalidProjection("The command's human-decision receipt is inconsistent.")
        }
        if let decision = payload.humanDecision {
            try ResearchOSValidation.requireID(decision.targetID, field: "decision.target_id")
            try ResearchOSValidation.requireTimestamp(decision.decidedAt, field: "decision.decided_at")
        }

        switch command {
        case .publicationSaved:
            guard let previous, let next, let manuscript = next.publication,
                  manuscript.revision == (previous.publication?.revision ?? 0) + 1,
                  previous.publication == nil || previous.publication?.id == manuscript.id,
                  payload.humanDecision?.targetID == "publication-\(manuscript.id.uuidString.lowercased())",
                  payload.humanDecision?.decision == "saved",
                  payload.humanDecision?.decidedAt == timestamp(next.updatedAt) else { try invalidCommand(.publicationSaved) }
            try manuscript.validate()
            var expected = previous
            expected.publication = manuscript
            expected.updatedAt = next.updatedAt
            if !expected.proofGateReadiness.isReadyForHumanDecision { expected.proofGateConfirmedAt = nil }
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(.publicationSaved) }
        case .argumentChanged:
            guard let previous, let next, let argument = next.argument, let command = argument.lastCommand,
                  payload.humanDecision?.targetID == "argument-\(command.id.uuidString.lowercased())",
                  payload.humanDecision?.decision == "accepted",
                  payload.humanDecision?.decidedAt == timestamp(next.updatedAt) else { try invalidCommand(.argumentChanged) }
            var expected = previous
            expected.argument = try (previous.argument ?? ResearchArgument()).applying(command)
            expected.updatedAt = next.updatedAt
            if !expected.proofGateReadiness.isReadyForHumanDecision { expected.proofGateConfirmedAt = nil }
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(.argumentChanged) }
        case .projectCreated:
            guard previous == nil, let next,
                  next.status == .active,
                  next.createdAt == next.updatedAt,
                  next.proofGateConfirmedAt == nil,
                  next.plusWorkspaceActivatedAt == nil,
                  next.argument == nil,
                  next.publication == nil,
                  next.repairs.allSatisfy({ $0.confirmedAt == nil }) else { try invalidCommand(command) }
        case .projectDeleted:
            guard previous != nil, next == nil, payload.tombstone else { try invalidCommand(command) }
        case .projectSnapshotSaved:
            guard let previous, let next,
                  next.updatedAt >= previous.updatedAt,
                  next.id == previous.id,
                  next.title == previous.title,
                  next.classification == previous.classification,
                  next.status == previous.status,
                  next.createdAt == previous.createdAt,
                  next.argument == previous.argument,
                  next.publication == previous.publication,
                  next.plusWorkspaceActivatedAt == previous.plusWorkspaceActivatedAt,
                  next.protocolRecord.frozenByHuman == previous.protocolRecord.frozenByHuman,
                  next.inbox.map(\.id) == previous.inbox.map(\.id),
                  next.claims.map(\.id) == previous.claims.map(\.id),
                  next.repairs.map(\.id) == previous.repairs.map(\.id),
                  next.repairs.map(\.confirmedAt) == previous.repairs.map(\.confirmedAt),
                  next.defense.map(\.id) == previous.defense.map(\.id),
                  next.reproducibility.map(\.id) == previous.reproducibility.map(\.id),
                  next.fileSystem.map(\.id) == previous.fileSystem.map(\.id),
                  next.proofGateConfirmedAt == previous.proofGateConfirmedAt
                    || (previous.proofGateConfirmedAt != nil && next.proofGateConfirmedAt == nil) else {
                try invalidCommand(command)
            }
        case .projectRenamed:
            guard let previous, let next else { try invalidCommand(command) }
            var expected = previous
            expected.title = next.title
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .projectArchived:
            guard let previous, let next else { try invalidCommand(command) }
            var expected = previous
            expected.status = .archived
            expected.proofGateConfirmedAt = nil
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .projectRestored:
            guard let previous, let next else { try invalidCommand(command) }
            var expected = previous
            expected.status = .active
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .inboxItemAdded:
            guard let previous, let next,
                  next.inbox.count == previous.inbox.count + 1,
                  Array(next.inbox.dropLast()) == previous.inbox,
                  next.inbox.last?.classification == next.classification,
                  !previous.inbox.map(\.id).contains(next.inbox.last!.id) else { try invalidCommand(command) }
            var expected = previous
            expected.inbox = next.inbox
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .inboxItemReviewed:
            guard let previous, let next,
                  next.inbox.map(\.id) == previous.inbox.map(\.id) else { try invalidCommand(command) }
            var expected = previous
            var changed = 0
            for index in expected.inbox.indices {
                if expected.inbox[index].reviewState != next.inbox[index].reviewState { changed += 1 }
                expected.inbox[index].reviewState = next.inbox[index].reviewState
            }
            expected.updatedAt = next.updatedAt
            guard changed == 1, next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .claimAdded:
            guard let previous, let next,
                  next.claims.count == previous.claims.count + 1,
                  Array(next.claims.dropLast()) == previous.claims,
                  !previous.claims.map(\.id).contains(next.claims.last!.id) else { try invalidCommand(command) }
            var expected = previous
            expected.claims = next.claims
            expected.updatedAt = next.updatedAt
            if !expected.proofGateReadiness.isReadyForHumanDecision { expected.proofGateConfirmedAt = nil }
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .repairProposed:
            guard let previous, let next,
                  next.repairs.count == previous.repairs.count + 1,
                  Array(next.repairs.dropLast()) == previous.repairs,
                  next.repairs.last?.confirmedAt == nil,
                  !previous.repairs.map(\.id).contains(next.repairs.last!.id) else { try invalidCommand(command) }
            var expected = previous
            expected.repairs = next.repairs
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .repairConfirmed:
            guard let previous, let next,
                  next.repairs.map(\.id) == previous.repairs.map(\.id) else { try invalidCommand(command) }
            var expected = previous
            var confirmedID: UUID?
            for index in expected.repairs.indices where expected.repairs[index].confirmedAt != next.repairs[index].confirmedAt {
                guard expected.repairs[index].confirmedAt == nil, next.repairs[index].confirmedAt != nil,
                      confirmedID == nil else { try invalidCommand(command) }
                confirmedID = expected.repairs[index].id
                expected.repairs[index].confirmedAt = next.repairs[index].confirmedAt
            }
            expected.updatedAt = next.updatedAt
            guard let confirmedID,
                  payload.humanDecision?.targetID == "repair-\(confirmedID.uuidString.lowercased())",
                  payload.humanDecision?.decision == "confirmed",
                  payload.humanDecision?.decidedAt == timestamp(next.updatedAt),
                  next.updatedAt >= previous.updatedAt,
                  expected == next else { try invalidCommand(command) }
        case .proofGateConfirmed:
            guard let previous, let next,
                  previous.proofGateReadiness.isReadyForHumanDecision,
                  previous.proofGateConfirmedAt == nil,
                  next.proofGateConfirmedAt != nil,
                  payload.humanDecision?.targetID == "proof-gate",
                  payload.humanDecision?.decision == "confirmed",
                  payload.humanDecision?.decidedAt == timestamp(next.updatedAt) else { try invalidCommand(command) }
            var expected = previous
            expected.proofGateConfirmedAt = next.proofGateConfirmedAt
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .protocolFrozen, .protocolAmendmentStarted:
            guard let previous, let next,
                  payload.humanDecision?.targetID == "protocol" else { try invalidCommand(command) }
            let isFrozen = command == .protocolFrozen
            guard payload.humanDecision?.decision == (isFrozen ? "frozen" : "amendment_started") else {
                try invalidCommand(command)
            }
            guard payload.humanDecision?.decidedAt == timestamp(next.updatedAt) else { try invalidCommand(command) }
            var expected = previous
            expected.protocolRecord.frozenByHuman = isFrozen
            expected.updatedAt = next.updatedAt
            if !expected.proofGateReadiness.isReadyForHumanDecision { expected.proofGateConfirmedAt = nil }
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        case .advancedWorkspaceActivated:
            guard let previous, let next,
                  previous.plusWorkspaceActivatedAt == nil,
                  next.plusWorkspaceActivatedAt != nil else { try invalidCommand(command) }
            var expected = previous
            expected.plusWorkspaceActivatedAt = next.plusWorkspaceActivatedAt
            expected.updatedAt = next.updatedAt
            guard next.updatedAt >= previous.updatedAt, expected == next else { try invalidCommand(command) }
        }
    }

    private static func invalidCommand(_ command: ResearchWorkspaceEventKind) throws -> Never {
        throw ResearchWorkspaceError.invalidProjection("The \(command.rawValue) event changed fields outside its typed command boundary.")
    }

    private static func projectValue(_ project: ResearchProject) throws -> CanonicalJSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.decodeValue(encoder.encode(project))
    }

    private static func projectDigest(_ project: ResearchProject) throws -> String {
        try CanonicalJSON.digest(projectValue(project))
    }

    private func enterFailClosed(_ error: Error) {
        // A rejected capacity-bound append did not write or corrupt the journal.
        // appendTransition already restored only that project's unsaved projection.
        if case ResearchOSCoreError.archiveCapacityExceeded = error { return }
        for task in scheduledDraftWrites.values { task.cancel() }
        scheduledDraftWrites.removeAll()
        persistedProjects.removeAll()
        projects = []
        selectedProjectID = nil
        lastDeletionReceipt = nil
        deletionFailure = nil
        mutationAccessFailure = nil
        recoveryMessage = nil
        persistenceFailure = "Local research history is locked because it could not be verified. \(error.localizedDescription)"
    }

    private static func projectID(_ id: UUID) -> String { id.uuidString.lowercased() }

    private static func applyCompleteProtection(to url: URL, fileManager: FileManager) throws {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
#endif
    }

    nonisolated private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    nonisolated private static func timestampDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? plain.date(from: value)
    }
}

enum ResearchWorkspaceError: LocalizedError, Equatable {
    case projectNotFound
    case persistenceUnavailable
    case exportPurgeFailed
    case invalidProjection(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            "The selected research project is no longer available."
        case .persistenceUnavailable:
            "The protected local event journal is unavailable."
        case .exportPurgeFailed:
            "A managed project export could not be removed."
        case let .invalidProjection(message):
            "The protected local event journal cannot be projected safely: \(message)"
        }
    }
}

extension ResearchProject {
    static func blank(title: String, question: String) -> ResearchProject {
        blank(title: title, question: question, id: UUID(), now: Date(), makeUUID: UUID.init)
    }

    static func blank(
        title: String,
        question: String,
        id: UUID,
        now: Date,
        makeUUID: () -> UUID
    ) -> ResearchProject {
        return ResearchProject(
            id: id,
            title: title,
            classification: .userCreated,
            status: .active,
            createdAt: now,
            updatedAt: now,
            scope: ResearchScope(question: question, population: "", variables: "", exclusions: ""),
            protocolRecord: ResearchProtocol(method: "", primaryOutcome: "", changePolicy: "", frozenByHuman: false),
            inbox: [],
            claims: [],
            repairs: [],
            defense: [
                DefensePrompt(id: makeUUID(), objection: "What would change your conclusion?", response: "", evidencePointer: ""),
                DefensePrompt(id: makeUUID(), objection: "Where could selection or measurement bias enter?", response: "", evidencePointer: "")
            ],
            reproducibility: ResearchProject.makeDefaultReproducibility(makeUUID: makeUUID),
            fileSystem: ResearchProject.makeDefaultFileSystem(makeUUID: makeUUID),
            proofGateConfirmedAt: nil,
            plusWorkspaceActivatedAt: nil
        )
    }

    static let syntheticStarter: ResearchProject = {
        var project = ResearchProject.blank(
            title: "Music and recall — invented walkthrough",
            question: "In this invented class sample, how did recall differ between quiet and instrumental conditions?"
        )
        project.classification = .syntheticDemo
        project.scope.population = "Twelve invented students in one synthetic classroom record"
        project.scope.variables = "Condition order and correct answers out of ten"
        project.scope.exclusions = "No causal, population-wide, or real-student inference"
        project.protocolRecord = ResearchProtocol(
            method: "Within-sample descriptive comparison across two conditions",
            primaryOutcome: "Correct-answer percentage by condition",
            changePolicy: "Disclose timing and rationale for every change; post-result changes never become preregistered.",
            frozenByHuman: true
        )
        project.inbox = [
            ResearchInboxItem(
                id: UUID(),
                title: "Synthetic observation table",
                source: "Bundled invented example",
                note: "Twelve fictional rows; no real person or experiment.",
                addedAt: Date(),
                reviewState: .reviewed,
                classification: .syntheticDemo
            )
        ]
        project.claims = [
            ClaimEvidenceLink(
                id: UUID(),
                claim: "Instrumental-condition accuracy was 4.2 percentage points higher in this synthetic sample.",
                evidencePointer: "Synthetic observation summary: 83/120 versus 78/120",
                support: .supports,
                limitation: "Descriptive difference only; no causal or population conclusion.",
                humanReviewed: true
            )
        ]
        project.repairs = [
            ExplicitRepairDraft(
                id: UUID(),
                before: "Instrumental music improves memory for all students.",
                after: "Accuracy was 4.2 points higher in the instrumental condition in this synthetic class sample.",
                reason: "Removes unsupported causality and population scope.",
                confirmedAt: nil
            )
        ]
        return project
    }()

    private static func makeDefaultReproducibility(makeUUID: () -> UUID) -> [ReproducibilityCheck] { [
        ReproducibilityCheck(id: makeUUID(), title: "Inputs identified", detail: "List every source, file, and inclusion boundary.", state: .open),
        ReproducibilityCheck(id: makeUUID(), title: "Method executable", detail: "Document steps, versions, parameters, and seeds where applicable.", state: .open),
        ReproducibilityCheck(id: makeUUID(), title: "Outputs mapped", detail: "Connect each reported output to its generating step.", state: .open),
        ReproducibilityCheck(id: makeUUID(), title: "Independent rerun", detail: "Record only a rerun actually performed by another environment or person.", state: .open)
    ] }

    private static func makeDefaultFileSystem(makeUUID: () -> UUID) -> [ResearchFileNode] { [
        ResearchFileNode(id: makeUUID(), path: "00-scope/", purpose: "Question, population, variables, exclusions", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "01-protocol/", purpose: "Frozen method and disclosed amendments", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "02-inputs/", purpose: "Source inventory and integrity notes", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "03-analysis/", purpose: "Executable methods and environment", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "04-claims/", purpose: "Claim-to-evidence map and limitations", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "05-defense/", purpose: "Objections, responses, unresolved risks", status: "Derived at display time"),
        ResearchFileNode(id: makeUUID(), path: "06-release/", purpose: "Human-approved export; never silent publication", status: "Derived at display time")
    ] }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
