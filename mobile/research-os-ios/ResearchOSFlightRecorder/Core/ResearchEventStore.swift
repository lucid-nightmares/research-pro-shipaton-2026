import Foundation

struct ResearchStoreAudit: Equatable, Sendable {
    let valid: Bool
    let checkedEvents: Int
    let projectHeads: [String: String]
    let failure: String?
}

struct ResearchRecoveryReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let actorRef: String
    let recoveredAt: String
    let validEventCount: Int
    let removedByteCount: Int
    let corruptTailDigest: String
    let quarantineFilename: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case actorRef = "actor_ref"
        case recoveredAt = "recovered_at"
        case validEventCount = "valid_event_count"
        case removedByteCount = "removed_byte_count"
        case corruptTailDigest = "corrupt_tail_digest"
        case quarantineFilename = "quarantine_filename"
    }
}

/// Non-content proof of an explicit privacy purge. The receipt deliberately
/// omits titles, questions, objects, payloads, and event identifiers.
struct ResearchProjectDeletionReceipt: Codable, Equatable, Sendable {
    let schemaID: String
    let schemaVersion: Int
    let projectID: String
    let actorRef: String
    let authorityRef: String
    let deletedAt: String
    let removedEventCount: Int
    let removedHeadDigest: String
    let removedProjectDigest: String
    let journalDigestBefore: String
    let journalDigestAfter: String
    let storageCaveat: String

    enum CodingKeys: String, CodingKey {
        case schemaID = "schema_id"
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case actorRef = "actor_ref"
        case authorityRef = "authority_ref"
        case deletedAt = "deleted_at"
        case removedEventCount = "removed_event_count"
        case removedHeadDigest = "removed_head_digest"
        case removedProjectDigest = "removed_project_digest"
        case journalDigestBefore = "journal_digest_before"
        case journalDigestAfter = "journal_digest_after"
        case storageCaveat = "storage_caveat"
    }
}

struct ResearchProjectState: Equatable, Sendable {
    let projectID: String
    let branchID: String
    let atSequence: Int
    let objects: [String: CanonicalJSONValue]
    let sourceEventIDs: [String]
}

/// A local-only append journal with deterministic import, export, replay, and
/// explicit recovery. It performs no network calls and stores no credentials.
final class ResearchEventStore: @unchecked Sendable {
    private struct StoreManifest: Codable, Equatable {
        let schemaID: String
        let storeSchemaVersion: Int
        let eventSchemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schemaID = "schema_id"
            case storeSchemaVersion = "store_schema_version"
            case eventSchemaVersion = "event_schema_version"
        }
    }

    private struct ScanResult {
        let events: [ResearchEventEnvelope]
        let validPrefix: Data
        let corruptTail: Data
        let failure: String?
    }

    private let rootDirectory: URL
    private let manifestURL: URL
    private let journalURL: URL
    private let legacyV0URL: URL
    private let migratedLegacyV0URL: URL
    private let activityMarkerURL: URL
    private let quarantineDirectory: URL
    private let fileManager: FileManager
    private let atomicJournalWriter: (Data, URL) throws -> Void
    private let atomicAppendWriter: (Data, URL) throws -> Void
    private let lock = NSLock()
    // Cache only against the digest of bytes reread from disk. A changed file,
    // including external corruption or replacement, never inherits trust.
    private var verifiedJournalDigest: String?
    private var verifiedJournalData: Data?
    private var verifiedJournalEvents: [ResearchEventEnvelope] = []
    private var mutationCache: [String: [ResearchMutation]] = [:]
    private var encodedEventCache: [String: Data] = [:]

    init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        atomicAppendWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        },
        atomicJournalWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    ) throws {
        self.rootDirectory = rootDirectory
        manifestURL = rootDirectory.appendingPathComponent("store-manifest.json")
        journalURL = rootDirectory.appendingPathComponent("events-v1.jsonl")
        legacyV0URL = rootDirectory.appendingPathComponent("events-v0.json")
        migratedLegacyV0URL = rootDirectory.appendingPathComponent("events-v0.migrated.json")
        activityMarkerURL = rootDirectory.appendingPathComponent("activity-v1.marker")
        quarantineDirectory = rootDirectory.appendingPathComponent("Recovery", isDirectory: true)
        self.fileManager = fileManager
        self.atomicJournalWriter = atomicJournalWriter
        self.atomicAppendWriter = atomicAppendWriter
        try prepareStore()
    }

    var eventJournalURL: URL { journalURL }

    func audit() -> ResearchStoreAudit {
        lock.withLock {
            do {
                let events = try loadStrict()
                var heads: [String: String] = [:]
                for event in events { heads[event.projectID] = event.chainDigest }
                return ResearchStoreAudit(valid: true, checkedEvents: events.count, projectHeads: heads, failure: nil)
            } catch {
                let scan = scanJournal()
                var heads: [String: String] = [:]
                for event in scan.events { heads[event.projectID] = event.chainDigest }
                return ResearchStoreAudit(
                    valid: false,
                    checkedEvents: scan.events.count,
                    projectHeads: heads,
                    failure: error.localizedDescription
                )
            }
        }
    }

    func allEvents() throws -> [ResearchEventEnvelope] {
        try lock.withLock { try loadStrict() }
    }

    /// True only before the first successful append/import/migration. A durable
    /// activity marker prevents a fully purged store from being mistaken for a
    /// first launch and silently reseeded.
    func isPristine() throws -> Bool {
        try lock.withLock {
            try loadStrict().isEmpty && !fileManager.fileExists(atPath: activityMarkerURL.path)
        }
    }

    func events(
        projectID: String,
        branchID: String? = nil,
        throughSequence: Int? = nil
    ) throws -> [ResearchEventEnvelope] {
        try ResearchOSValidation.requireID(projectID, field: "project_id")
        if let branchID { try ResearchOSValidation.requireID(branchID, field: "branch_id") }
        if let throughSequence, throughSequence < 0 {
            throw ResearchOSCoreError.invalidContract("time-travel sequence cannot be negative")
        }
        return try lock.withLock {
            try loadStrict().filter { event in
                event.projectID == projectID
                    && (branchID == nil || event.branchID == branchID)
                    && (throughSequence == nil || event.sequence <= throughSequence!)
            }
        }
    }

    func headDigest(projectID: String) throws -> String {
        try events(projectID: projectID).last?.chainDigest ?? ResearchOSSchema.zeroDigest
    }

    @discardableResult
    func append(_ draft: ResearchEventDraft, expectedChainDigest: String? = nil, maximumProjectArchiveBytes: Int? = nil) throws -> ResearchEventEnvelope {
        try lock.withLock {
            let existingEvents = try loadStrict()
            let projectEvents = existingEvents.filter { $0.projectID == draft.projectID }
            let priorChain = projectEvents.last?.chainDigest ?? ResearchOSSchema.zeroDigest
            if existingEvents.contains(where: {
                $0.projectID != draft.projectID && $0.eventID == draft.eventID
            }) {
                throw ResearchOSCoreError.duplicateIdentity
            }
            if let prior = projectEvents.first(where: {
                $0.idempotencyKey == draft.idempotencyKey || $0.eventID == draft.eventID
            }) {
                if matches(prior, draft: draft) { return prior }
                throw ResearchOSCoreError.duplicateIdentity
            }
            if let expectedChainDigest {
                try ResearchOSValidation.requireSHA256(expectedChainDigest, field: "expected_chain_digest")
                guard expectedChainDigest == priorChain else { throw ResearchOSCoreError.staleHead }
            }
            let sequence = (projectEvents.last?.sequence ?? 0) + 1
            let payloadDigest = try CanonicalJSON.digest(draft.payload)
            let provisional = ResearchEventEnvelope(
                eventID: draft.eventID,
                projectID: draft.projectID,
                branchID: draft.branchID,
                sequence: sequence,
                kind: draft.kind,
                schemaID: draft.schemaID,
                schemaVersion: draft.schemaVersion,
                actorRef: draft.actorRef,
                authorityRef: draft.authorityRef,
                origin: draft.origin,
                causeRefs: draft.causeRefs,
                objectRefs: draft.objectRefs,
                idempotencyKey: draft.idempotencyKey,
                occurredAt: draft.occurredAt,
                parentEventIDs: draft.parentEventIDs,
                priorProjectDigest: draft.priorProjectDigest,
                payloadDigest: payloadDigest,
                resultProjectDigest: draft.resultProjectDigest,
                chainDigest: ResearchOSSchema.zeroDigest,
                payload: draft.payload
            )
            let chainDigest = try CanonicalJSON.digest(.object([
                "previous_chain_digest": .string(priorChain),
                "event": provisional.materialValue()
            ]))
            let event = ResearchEventEnvelope(
                eventID: provisional.eventID,
                projectID: provisional.projectID,
                branchID: provisional.branchID,
                sequence: provisional.sequence,
                kind: provisional.kind,
                schemaID: provisional.schemaID,
                schemaVersion: provisional.schemaVersion,
                actorRef: provisional.actorRef,
                authorityRef: provisional.authorityRef,
                origin: provisional.origin,
                causeRefs: provisional.causeRefs,
                objectRefs: provisional.objectRefs,
                idempotencyKey: provisional.idempotencyKey,
                occurredAt: provisional.occurredAt,
                parentEventIDs: provisional.parentEventIDs,
                priorProjectDigest: provisional.priorProjectDigest,
                payloadDigest: provisional.payloadDigest,
                resultProjectDigest: provisional.resultProjectDigest,
                chainDigest: chainDigest,
                payload: provisional.payload
            )
            // Existing history has just passed loadStrict (or its exact-byte
            // cache). Validate only the new event against that verified history.
            try event.validate(previousChainDigest: priorChain)
            try validateMutationVersions(event, priorEvents: projectEvents)
            try validateBranchTopology(projectEvents + [event])
            if let maximumProjectArchiveBytes {
                let candidate = ResearchEventArchive(
                    schemaID: ResearchOSSchema.archive,
                    schemaVersion: ResearchOSSchema.currentVersion,
                    projectID: draft.projectID,
                    exportedHeadDigest: event.chainDigest,
                    events: projectEvents + [event]
                )
                guard try encodeArchive(candidate).count <= maximumProjectArchiveBytes else {
                    throw ResearchOSCoreError.archiveCapacityExceeded(projectID: draft.projectID)
                }
            }
            var replacement = try verifiedJournalData ?? encodeJournal(existingEvents)
            if !replacement.isEmpty && replacement.last != 0x0A { replacement.append(0x0A) }
            replacement.append(try encodedEvent(event))
            replacement.append(0x0A)
            try recordActivity()
            do { try atomicAppendWriter(replacement, journalURL) }
            catch { guard (try? Data(contentsOf: journalURL)) == replacement else { throw error } }
            guard try Data(contentsOf: journalURL) == replacement else { throw ResearchOSCoreError.corrupt("atomic append did not persist the expected bytes") }
            rememberVerifiedJournal(replacement, events: existingEvents + [event])
            return event
        }
    }

    /// Returns ancestry plus branch-local events, bounded at an exact project sequence.
    func branchHistory(
        projectID: String,
        branchID: String,
        throughSequence: Int? = nil
    ) throws -> [ResearchEventEnvelope] {
        let events = try allEvents().filter {
            $0.projectID == projectID && (throughSequence == nil || $0.sequence <= throughSequence!)
        }
        return try resolveBranchHistory(events: events, branchID: branchID, visiting: [])
    }

    func replay(projectID: String, branchID: String, throughSequence: Int? = nil) throws -> ResearchReplay {
        let history = try branchHistory(projectID: projectID, branchID: branchID, throughSequence: throughSequence)
        var prior = ResearchOSSchema.zeroDigest
        var frames: [ResearchReplayFrame] = []
        for (index, event) in history.enumerated() {
            let ordinal = index + 1
            let material: CanonicalJSONValue = .object([
                "ordinal": .integer(Int64(ordinal)),
                "event": try CanonicalJSON.value(from: event),
                "prior_frame_digest": .string(prior)
            ])
            let digest = try CanonicalJSON.digest(material)
            frames.append(ResearchReplayFrame(
                ordinal: ordinal,
                event: event,
                priorFrameDigest: prior,
                frameDigest: digest
            ))
            prior = digest
        }
        let limit = throughSequence ?? history.last?.sequence ?? 0
        let material: CanonicalJSONValue = .object([
            "schema_id": .string(ResearchOSSchema.replay),
            "schema_version": .integer(Int64(ResearchOSSchema.currentVersion)),
            "project_id": .string(projectID),
            "branch_id": .string(branchID),
            "through_sequence": .integer(Int64(limit)),
            "frames": .array(try frames.map { try CanonicalJSON.value(from: $0) })
        ])
        return ResearchReplay(
            schemaID: ResearchOSSchema.replay,
            schemaVersion: ResearchOSSchema.currentVersion,
            projectID: projectID,
            branchID: branchID,
            throughSequence: limit,
            frames: frames,
            replayDigest: try CanonicalJSON.digest(material)
        )
    }

    func projectState(projectID: String, branchID: String, throughSequence: Int? = nil) throws -> ResearchProjectState {
        let history = try branchHistory(projectID: projectID, branchID: branchID, throughSequence: throughSequence)
        var objects: [String: CanonicalJSONValue] = [:]
        for event in history {
            guard let mutationsValue = event.payload["mutations"] else { continue }
            let data = try CanonicalJSON.encode(mutationsValue)
            let mutations = try JSONDecoder().decode([ResearchMutation].self, from: data)
            for mutation in mutations {
                guard mutation.ref.projectID == projectID else { throw ResearchOSCoreError.crossProject }
                let logicalKey = "\(mutation.ref.objectType)/\(mutation.ref.logicalID)"
                switch mutation.operation {
                case .put: objects[logicalKey] = mutation.value
                case .delete: objects.removeValue(forKey: logicalKey)
                }
            }
        }
        return ResearchProjectState(
            projectID: projectID,
            branchID: branchID,
            atSequence: history.last?.sequence ?? 0,
            objects: objects,
            sourceEventIDs: history.map(\.eventID)
        )
    }

    func exportArchive(projectID: String) throws -> Data {
        let selected = try events(projectID: projectID)
        let archive = ResearchEventArchive(
            schemaID: ResearchOSSchema.archive,
            schemaVersion: ResearchOSSchema.currentVersion,
            projectID: projectID,
            exportedHeadDigest: selected.last?.chainDigest ?? ResearchOSSchema.zeroDigest,
            events: selected
        )
        return try lock.withLock { try encodeArchive(archive) }
    }

    /// Deliberate privacy exception to append-only history. All records for one
    /// project are removed in one atomic replacement; no removed bytes are
    /// copied to Recovery. The caller must remove its live projection only after
    /// this method returns successfully.
    func purgeProject(
        projectID: String,
        actorRef: String,
        authorityRef: String,
        deletedAt: String
    ) throws -> ResearchProjectDeletionReceipt {
        try ResearchOSValidation.requireID(projectID, field: "project_id")
        guard actorRef.hasPrefix("human:") else { throw ResearchOSCoreError.humanAuthorityRequired }
        try ResearchOSValidation.requireID(actorRef, field: "actor_ref")
        try ResearchOSValidation.requireID(authorityRef, field: "authority_ref")
        try ResearchOSValidation.requireTimestamp(deletedAt, field: "deleted_at")

        return try lock.withLock {
            let all = try loadStrict()
            let removed = all.filter { $0.projectID == projectID }
            guard let removedHead = removed.last else {
                throw ResearchOSCoreError.invalidContract("the project has no event history to purge")
            }
            let retained = all.filter { $0.projectID != projectID }
            try verifyAllChains(retained)
            let original = try Data(contentsOf: journalURL)
            let rewritten = try encodeJournal(retained)
            guard retained.allSatisfy({ $0.projectID != projectID }) else {
                throw ResearchOSCoreError.crossProject
            }
            let receipt = ResearchProjectDeletionReceipt(
                schemaID: ResearchOSSchema.projectDeletionReceipt,
                schemaVersion: ResearchOSSchema.currentVersion,
                projectID: projectID,
                actorRef: actorRef,
                authorityRef: authorityRef,
                deletedAt: deletedAt,
                removedEventCount: removed.count,
                removedHeadDigest: removedHead.chainDigest,
                removedProjectDigest: removedHead.resultProjectDigest,
                journalDigestBefore: CanonicalJSON.sha256(original),
                journalDigestAfter: CanonicalJSON.sha256(rewritten),
                storageCaveat: "Logical purge removes live app-managed journal and recovery bytes; shared copies, prior OS backups, and physical flash remnants may persist."
            )
            // Recovery tails are not safely project-partitioned. A human privacy
            // purge therefore discards all app-managed recovery quarantine and
            // obsolete migration sources before the canonical rewrite. If this
            // cleanup fails, the live journal is not touched.
            try purgeNoncanonicalArtifacts()
            try recordActivity()
            do {
                try atomicJournalWriter(rewritten, journalURL)
            } catch {
                // A replace can reach durable storage before a late sync error.
                // Count that narrow state as committed only when the observed
                // bytes exactly equal the prevalidated replacement.
                guard (try? Data(contentsOf: journalURL)) == rewritten else { throw error }
            }
            let verified = try loadStrict()
            guard verified == retained else {
                throw ResearchOSCoreError.corrupt("atomic project purge did not produce the expected journal")
            }
            return receipt
        }
    }

    /// Deterministic and fail-closed: import never renames a private project and
    /// accepts only an empty target or an exact idempotent archive replay.
    func validateArchive(_ data: Data, expectedProjectID: String) throws -> ResearchEventArchive {
        return try lock.withLock {
        let archive = try JSONDecoder().decode(ResearchEventArchive.self, from: data)
        guard archive.schemaID == ResearchOSSchema.archive,
              archive.schemaVersion == ResearchOSSchema.currentVersion else {
            throw ResearchOSCoreError.unsupportedSchema
        }
        guard archive.projectID == expectedProjectID,
              archive.events.allSatisfy({ $0.projectID == expectedProjectID }) else {
            throw ResearchOSCoreError.crossProject
        }
        try verifyProjectChain(archive.events)
        guard archive.exportedHeadDigest == (archive.events.last?.chainDigest ?? ResearchOSSchema.zeroDigest) else {
            throw ResearchOSCoreError.corrupt("archive head digest mismatch")
        }
        return archive
        }
    }

    func importArchive(_ data: Data, expectedProjectID: String) throws -> Int {
        let archive = try validateArchive(data, expectedProjectID: expectedProjectID)
        return try lock.withLock {
            let allExisting = try loadStrict()
            let existingProject = allExisting.filter { $0.projectID == expectedProjectID }
            if !existingProject.isEmpty {
                guard existingProject == archive.events else { throw ResearchOSCoreError.duplicateIdentity }
                return 0
            }
            let existingEventIDs = Set(allExisting.map(\.eventID))
            guard archive.events.allSatisfy({ !existingEventIDs.contains($0.eventID) }) else {
                throw ResearchOSCoreError.duplicateIdentity
            }
            try verifyAllChains(allExisting + archive.events)
            let replacement = try encodeJournal(allExisting + archive.events)
            try recordActivity()
            do { try atomicAppendWriter(replacement, journalURL) }
            catch { guard (try? Data(contentsOf: journalURL)) == replacement else { throw error } }
            guard try Data(contentsOf: journalURL) == replacement else { throw ResearchOSCoreError.corrupt("atomic import did not persist the expected bytes") }
            rememberVerifiedJournal(replacement, events: allExisting + archive.events)
            return archive.events.count
        }
    }

    /// Truncates only from the first invalid record onward, preserves removed
    /// bytes in Recovery, and requires a named human authority.
    func recover(actorRef: String, recoveredAt: String) throws -> ResearchRecoveryReceipt? {
        guard actorRef.hasPrefix("human:") else { throw ResearchOSCoreError.recoveryRequiresHuman }
        try ResearchOSValidation.requireID(actorRef, field: "actor_ref")
        try ResearchOSValidation.requireTimestamp(recoveredAt, field: "recovered_at")
        return try lock.withLock {
            let scan = scanJournal()
            guard !scan.corruptTail.isEmpty else { return nil }
            try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
            let digest = CanonicalJSON.sha256(scan.corruptTail)
            let filename = "corrupt-tail-\(digest.prefix(16)).bin"
            let quarantineURL = quarantineDirectory.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: quarantineURL.path) {
                try scan.corruptTail.write(to: quarantineURL, options: [.atomic, .completeFileProtection])
            }
            try scan.validPrefix.write(to: journalURL, options: [.atomic, .completeFileProtection])
            let receipt = ResearchRecoveryReceipt(
                schemaVersion: ResearchOSSchema.currentVersion,
                actorRef: actorRef,
                recoveredAt: recoveredAt,
                validEventCount: scan.events.count,
                removedByteCount: scan.corruptTail.count,
                corruptTailDigest: digest,
                quarantineFilename: filename
            )
            let receiptURL = quarantineDirectory
                .appendingPathComponent("recovery-receipt-\(digest.prefix(16)).json")
            try CanonicalJSON.encode(receipt).write(
                to: receiptURL,
                options: [.atomic, .completeFileProtection]
            )
            return receipt
        }
    }

    private func prepareStore() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try applyCompleteProtection(to: rootDirectory)
        let hadManifest = fileManager.fileExists(atPath: manifestURL.path)
        let hadLegacy = fileManager.fileExists(atPath: legacyV0URL.path)
        if hadManifest {
            let manifest = try JSONDecoder().decode(StoreManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.schemaID == ResearchOSSchema.store,
                  manifest.storeSchemaVersion == ResearchOSSchema.currentVersion,
                  manifest.eventSchemaVersion == ResearchOSSchema.currentVersion else {
                throw ResearchOSCoreError.unsupportedSchema
            }
        } else if hadLegacy {
            try migrateLegacyV0()
        } else {
            if !fileManager.fileExists(atPath: journalURL.path) {
                guard fileManager.createFile(atPath: journalURL.path, contents: Data()) else {
                    throw ResearchOSCoreError.corrupt("event journal could not be created")
                }
                try applyCompleteProtection(to: journalURL)
            }
            try writeCurrentManifest()
        }
        try applyCompleteProtection(to: manifestURL)
        if !fileManager.fileExists(atPath: journalURL.path) {
            guard !hadManifest, !hadLegacy else {
                throw ResearchOSCoreError.corrupt("the manifest exists but the event journal is missing")
            }
            guard fileManager.createFile(atPath: journalURL.path, contents: Data()) else {
                throw ResearchOSCoreError.corrupt("event journal could not be created")
            }
        }
        try applyCompleteProtection(to: journalURL)
        // Keep a store handle available when an otherwise-recognized journal
        // ends in a corrupt suffix. Reads still fail closed through loadStrict(),
        // while the workspace can offer its explicit human recovery action.
        guard scanJournal().failure == nil else { return }
        _ = try loadStrict()
        // A verified v1 journal is the sole canonical migration result. Remove
        // plaintext v0 sources, including copies left by pre-release builds.
        try purgeLegacyMigrationArtifacts()
    }

    private func writeCurrentManifest() throws {
        let manifest = StoreManifest(
            schemaID: ResearchOSSchema.store,
            storeSchemaVersion: ResearchOSSchema.currentVersion,
            eventSchemaVersion: ResearchOSSchema.currentVersion
        )
        try CanonicalJSON.encode(manifest).write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    private func applyCompleteProtection(to url: URL) throws {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
#endif
    }

    private func recordActivity() throws {
        guard !fileManager.fileExists(atPath: activityMarkerURL.path) else { return }
        try Data("research-os-event-activity-v1\n".utf8).write(
            to: activityMarkerURL,
            options: [.atomic, .completeFileProtection]
        )
        try applyCompleteProtection(to: activityMarkerURL)
    }

    private func migrateLegacyV0() throws {
        let legacyData = try Data(contentsOf: legacyV0URL)
        let events = try JSONDecoder().decode([ResearchEventEnvelope].self, from: legacyData)
        try verifyAllChains(events)
        var journal = Data()
        for event in events {
            journal.append(try CanonicalJSON.encode(event))
            journal.append(0x0A)
        }
        try journal.write(to: journalURL, options: [.atomic, .completeFileProtection])
        try writeCurrentManifest()
        try recordActivity()
    }

    private func purgeNoncanonicalArtifacts() throws {
        if fileManager.fileExists(atPath: quarantineDirectory.path) {
            try fileManager.removeItem(at: quarantineDirectory)
        }
        try purgeLegacyMigrationArtifacts()
        guard !fileManager.fileExists(atPath: quarantineDirectory.path) else {
            throw ResearchOSCoreError.corrupt("recovery quarantine could not be removed before project purge")
        }
    }

    private func purgeLegacyMigrationArtifacts() throws {
        for url in [legacyV0URL, migratedLegacyV0URL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard !fileManager.fileExists(atPath: legacyV0URL.path),
              !fileManager.fileExists(atPath: migratedLegacyV0URL.path) else {
            throw ResearchOSCoreError.corrupt("legacy migration bytes could not be removed")
        }
    }

    private func rememberVerifiedJournal(_ data: Data, events: [ResearchEventEnvelope]) {
        verifiedJournalDigest = CanonicalJSON.sha256(data)
        verifiedJournalData = data
        verifiedJournalEvents = events
    }

    private func loadStrict() throws -> [ResearchEventEnvelope] {
        let data = try Data(contentsOf: journalURL)
        let digest = CanonicalJSON.sha256(data)
        if verifiedJournalDigest == digest { return verifiedJournalEvents }
        verifiedJournalDigest = nil
        verifiedJournalData = nil
        verifiedJournalEvents = []
        mutationCache.removeAll()
        encodedEventCache.removeAll()
        let scan = scanJournal(data: data)
        if let failure = scan.failure { throw ResearchOSCoreError.corrupt(failure) }
        try verifyAllChains(scan.events)
        rememberVerifiedJournal(data, events: scan.events)
        return scan.events
    }

    private func scanJournal(data suppliedData: Data? = nil) -> ScanResult {
        let data: Data
        do { data = try suppliedData ?? Data(contentsOf: journalURL) }
        catch { return ScanResult(events: [], validPrefix: Data(), corruptTail: Data(), failure: error.localizedDescription) }
        if data.isEmpty { return ScanResult(events: [], validPrefix: Data(), corruptTail: Data(), failure: nil) }

        var events: [ResearchEventEnvelope] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let newline = bytes[offset...].firstIndex(of: 0x0A) ?? bytes.count
            let end = newline
            let next = newline < bytes.count ? newline + 1 : newline
            if end == offset {
                offset = next
                continue
            }
            let line = Data(bytes[offset..<end])
            do {
                let event = try JSONDecoder().decode(ResearchEventEnvelope.self, from: line)
                guard try encodedEvent(event) == line else {
                    throw ResearchOSCoreError.corrupt("non-canonical event bytes")
                }
                let projectEvents = events.filter { $0.projectID == event.projectID }
                let expectedSequence = (projectEvents.last?.sequence ?? 0) + 1
                guard event.sequence == expectedSequence else {
                    throw ResearchOSCoreError.corrupt("project sequence is missing or reordered")
                }
                let prior = projectEvents.last?.chainDigest ?? ResearchOSSchema.zeroDigest
                try event.validate(previousChainDigest: prior)
                try validateMutationVersions(event, priorEvents: projectEvents)
                guard !projectEvents.contains(where: {
                    $0.eventID == event.eventID || $0.idempotencyKey == event.idempotencyKey
                }) else { throw ResearchOSCoreError.duplicateIdentity }
                events.append(event)
                offset = next
            } catch {
                return ScanResult(
                    events: events,
                    validPrefix: Data(bytes[0..<offset]),
                    corruptTail: Data(bytes[offset..<bytes.count]),
                    failure: error.localizedDescription
                )
            }
        }
        return ScanResult(events: events, validPrefix: data, corruptTail: Data(), failure: nil)
    }

    private func verifyAllChains(_ events: [ResearchEventEnvelope]) throws {
        guard Set(events.map(\.eventID)).count == events.count else {
            throw ResearchOSCoreError.duplicateIdentity
        }
        for projectID in Set(events.map(\.projectID)) {
            try verifyProjectChain(events.filter { $0.projectID == projectID })
        }
    }

    private func encodedEvent(_ event: ResearchEventEnvelope) throws -> Data {
        if let encoded = encodedEventCache[event.chainDigest] { return encoded }
        let data = try CanonicalJSON.encode(event)
        encodedEventCache[event.chainDigest] = data
        return data
    }

    private func encodeJournal(_ events: [ResearchEventEnvelope]) throws -> Data {
        try events.reduce(into: Data()) { output, event in
            output.append(try encodedEvent(event))
            output.append(0x0A)
        }
    }

    /// The metadata and each envelope use the canonical encoder. Reusing those
    /// already-canonical envelope bytes avoids re-encoding every old snapshot.
    /// Key order exactly matches CanonicalJSON.encode(ResearchEventArchive).
    private func encodeArchive(_ archive: ResearchEventArchive) throws -> Data {
        var data = Data("{\"events\":[".utf8)
        for (index, event) in archive.events.enumerated() {
            if index > 0 { data.append(0x2C) }
            data.append(try encodedEvent(event))
        }
        data.append(contentsOf: "],".utf8)
        let metadata = try CanonicalJSON.encode(.object([
            "exported_head_digest": .string(archive.exportedHeadDigest),
            "project_id": .string(archive.projectID),
            "schema_id": .string(archive.schemaID),
            "schema_version": .integer(Int64(archive.schemaVersion))
        ]))
        data.append(metadata.dropFirst())
        return data
    }

    private func matches(_ event: ResearchEventEnvelope, draft: ResearchEventDraft) -> Bool {
        event.eventID == draft.eventID
            && event.projectID == draft.projectID
            && event.branchID == draft.branchID
            && event.kind == draft.kind
            && event.schemaID == draft.schemaID
            && event.schemaVersion == draft.schemaVersion
            && event.actorRef == draft.actorRef
            && event.authorityRef == draft.authorityRef
            && event.origin == draft.origin
            && event.causeRefs == draft.causeRefs
            && event.objectRefs == draft.objectRefs
            && event.idempotencyKey == draft.idempotencyKey
            && event.occurredAt == draft.occurredAt
            && event.parentEventIDs == draft.parentEventIDs
            && event.priorProjectDigest == draft.priorProjectDigest
            && event.resultProjectDigest == draft.resultProjectDigest
            && event.payload == draft.payload
    }

    private func verifyProjectChain(_ events: [ResearchEventEnvelope]) throws {
        var prior = ResearchOSSchema.zeroDigest
        var identities: Set<String> = []
        var idempotencyKeys: Set<String> = []
        for (index, event) in events.enumerated() {
            guard event.sequence == index + 1 else {
                throw ResearchOSCoreError.corrupt("project sequence is missing or reordered")
            }
            guard identities.insert(event.eventID).inserted,
                  idempotencyKeys.insert(event.idempotencyKey).inserted else {
                throw ResearchOSCoreError.duplicateIdentity
            }
            try event.validate(previousChainDigest: prior)
            try validateMutationVersions(event, priorEvents: Array(events.prefix(index)))
            prior = event.chainDigest
        }
        try validateBranchTopology(events)
    }

    private func validateBranchTopology(_ events: [ResearchEventEnvelope]) throws {
        let branches = Set(events.map(\.branchID)).subtracting(["main"])
        for branchID in branches {
            let local = events.filter { $0.branchID == branchID }.sorted { $0.sequence < $1.sequence }
            let forks = local.filter { $0.kind == "branch.created" }
            guard let fork = local.first, fork.kind == "branch.created", forks.count == 1,
                  let sourceBranch = fork.payload["source_branch"]?.stringValue,
                  let sourceSequence64 = fork.payload["source_sequence"]?.integerValue,
                  sourceBranch != branchID,
                  sourceSequence64 > 0,
                  sourceSequence64 < Int64(fork.sequence),
                  sourceSequence64 <= Int64(Int.max) else {
                throw ResearchOSCoreError.corrupt("branch fork metadata is invalid or not unique")
            }
            let sourceSequence = Int(sourceSequence64)
            guard events.contains(where: {
                $0.branchID == sourceBranch && $0.sequence == sourceSequence
            }) else {
                throw ResearchOSCoreError.corrupt("branch source does not exist at the declared fork sequence")
            }
            _ = try resolveBranchHistory(events: events, branchID: branchID, visiting: [])
        }
    }

    private func validateMutationVersions(
        _ event: ResearchEventEnvelope,
        priorEvents: [ResearchEventEnvelope]
    ) throws {
        let visiblePriorEvents: [ResearchEventEnvelope]
        if event.branchID == "main" {
            visiblePriorEvents = priorEvents.filter { $0.branchID == "main" }
        } else if event.kind == "branch.created" {
            visiblePriorEvents = []
        } else {
            visiblePriorEvents = try resolveBranchHistory(
                events: priorEvents,
                branchID: event.branchID,
                visiting: []
            )
        }
        var latestVersion: [String: Int] = [:]
        var activeRefByLogicalKey: [String: ResearchObjectRef] = [:]
        for priorEvent in visiblePriorEvents {
            for mutation in try decodedMutations(priorEvent) {
                let key = "\(mutation.ref.objectType)/\(mutation.ref.logicalID)"
                latestVersion[key] = max(latestVersion[key] ?? 0, mutation.ref.version)
                switch mutation.operation {
                case .put: activeRefByLogicalKey[key] = mutation.ref
                case .delete: activeRefByLogicalKey.removeValue(forKey: key)
                }
            }
        }
        let mutations = try decodedMutations(event)
        var currentLogicalKeys: Set<String> = []
        for mutation in mutations {
            let key = "\(mutation.ref.objectType)/\(mutation.ref.logicalID)"
            guard currentLogicalKeys.insert(key).inserted,
                  mutation.ref.version == (latestVersion[key] ?? 0) + 1 else {
                throw ResearchOSCoreError.corrupt("object versions must advance by exactly one")
            }
            let activeRefs = Set(activeRefByLogicalKey.values)
            guard mutation.dependsOn.allSatisfy(activeRefs.contains) else {
                throw ResearchOSCoreError.corrupt("a mutation dependency is not active before this mutation")
            }
            switch mutation.operation {
            case .put:
                activeRefByLogicalKey[key] = mutation.ref
            case .delete:
                guard activeRefByLogicalKey.removeValue(forKey: key) != nil else {
                    throw ResearchOSCoreError.corrupt("a delete mutation requires an active object")
                }
            }
            latestVersion[key] = mutation.ref.version
        }
    }

    private func decodedMutations(_ event: ResearchEventEnvelope) throws -> [ResearchMutation] {
        if let cached = mutationCache[event.chainDigest] { return cached }
        guard let value = event.payload["mutations"] else { return [] }
        let mutations = try JSONDecoder().decode([ResearchMutation].self, from: CanonicalJSON.encode(value))
        mutationCache[event.chainDigest] = mutations
        return mutations
    }

    private func resolveBranchHistory(
        events: [ResearchEventEnvelope],
        branchID: String,
        visiting: Set<String>
    ) throws -> [ResearchEventEnvelope] {
        guard !visiting.contains(branchID) else { throw ResearchOSCoreError.corrupt("branch ancestry cycle") }
        let local = events.filter { $0.branchID == branchID }.sorted { $0.sequence < $1.sequence }
        if branchID == "main" { return local }
        guard let fork = local.first, fork.kind == "branch.created",
              local.filter({ $0.kind == "branch.created" }).count == 1,
              let sourceBranch = fork.payload["source_branch"]?.stringValue,
              let sourceSequence64 = fork.payload["source_sequence"]?.integerValue,
              sourceBranch != branchID,
              sourceSequence64 > 0,
              sourceSequence64 < Int64(fork.sequence),
              sourceSequence64 <= Int64(Int.max),
              events.contains(where: {
                  $0.branchID == sourceBranch && $0.sequence == Int(sourceSequence64)
              }) else {
            throw ResearchOSCoreError.corrupt("branch is missing a deterministic fork event")
        }
        let sourceSequence = Int(sourceSequence64)
        let bounded = events.filter { $0.sequence <= sourceSequence }
        let ancestry = try resolveBranchHistory(
            events: bounded,
            branchID: sourceBranch,
            visiting: visiting.union([branchID])
        )
        return ancestry + local
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
