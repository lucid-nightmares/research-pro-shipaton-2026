import XCTest
@testable import ResearchOSFlightRecorder

final class CoreParityTests: XCTestCase {
    func testPythonGoldenPayloadEventChainAndArchiveParity() throws {
        let raw = try Data(contentsOf: fixtureURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: raw) as? [String: Any]
        )
        let payload = try CanonicalJSONValue(jsonObject: try XCTUnwrap(root["payload"]))
        XCTAssertEqual(
            try CanonicalJSON.digest(payload),
            root["payload_digest"] as? String
        )

        let material = try CanonicalJSONValue(jsonObject: try XCTUnwrap(root["event_material"]))
        let chainMaterial: CanonicalJSONValue = .object([
            "previous_chain_digest": .string(try XCTUnwrap(root["previous_chain_digest"] as? String)),
            "event": material
        ])
        XCTAssertEqual(
            try CanonicalJSON.digest(chainMaterial),
            root["chain_digest"] as? String
        )

        let envelopeData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(root["envelope"]))
        let envelope = try JSONDecoder().decode(ResearchEventEnvelope.self, from: envelopeData)
        try envelope.validate(previousChainDigest: ResearchOSSchema.zeroDigest)

        let archive = try CanonicalJSONValue(jsonObject: try XCTUnwrap(root["archive"]))
        XCTAssertEqual(
            try CanonicalJSON.digest(archive),
            root["archive_digest"] as? String
        )
    }

    func testAppendIsDurableIdempotentAndDetectsStaleHead() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ResearchEventStore(rootDirectory: directory)
        let draft = try makeDraft(eventID: "event-1", key: "key-1", result: "1")
        let first = try store.append(draft, expectedChainDigest: ResearchOSSchema.zeroDigest)
        // A true retry returns the original receipt even if its remembered head is stale.
        XCTAssertEqual(
            try store.append(draft, expectedChainDigest: ResearchOSSchema.zeroDigest),
            first
        )
        XCTAssertEqual(try ResearchEventStore(rootDirectory: directory).allEvents(), [first])
        XCTAssertThrowsError(
            try store.append(
                makeDraft(eventID: "event-2", key: "key-2", result: "2", objectVersion: 2),
                expectedChainDigest: ResearchOSSchema.zeroDigest
            )
        ) { XCTAssertEqual($0 as? ResearchOSCoreError, .staleHead) }
    }

    func testMutationVersionsDependenciesDeletesAndEventIDsFailClosed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ResearchEventStore(rootDirectory: directory)
        let first = try store.append(makeDraft(eventID: "event-1", key: "key-1", result: "1"))

        func draft(eventID: String, key: String, mutations: [ResearchMutation]) throws -> ResearchEventDraft {
            try ResearchEventDraft(
                eventID: eventID,
                projectID: "project-1",
                branchID: "main",
                kind: "claim.reviewed",
                actorRef: "human:local",
                authorityRef: "role:owner",
                origin: "local",
                idempotencyKey: key,
                occurredAt: "2026-08-18T12:01:00Z",
                priorProjectDigest: first.resultProjectDigest,
                resultProjectDigest: String(repeating: "2", count: 64),
                payload: .object([
                    "classification": .string("SYNTHETIC_DEMO_ONLY"),
                    "mutations": .array(try mutations.map { try CanonicalJSON.value(from: $0) }),
                    "workflow_stage": .string("REVIEW")
                ]),
                objectRefs: mutations.map(\.ref),
                parentEventIDs: [first.eventID]
            )
        }

        let skippedRef = try ResearchObjectRef(
            projectID: "project-1", objectType: "claim", logicalID: "claim-1", version: 3
        )
        XCTAssertThrowsError(try store.append(draft(
            eventID: "event-skipped", key: "key-skipped",
            mutations: [try ResearchMutation(ref: skippedRef, operation: .put, value: .object([:]))]
        )))

        let absentRef = try ResearchObjectRef(
            projectID: "project-1", objectType: "claim", logicalID: "missing", version: 1
        )
        XCTAssertThrowsError(try store.append(draft(
            eventID: "event-delete-absent", key: "key-delete-absent",
            mutations: [try ResearchMutation(ref: absentRef, operation: .delete)]
        )))

        let sourceRef = try ResearchObjectRef(
            projectID: "project-1", objectType: "evidence", logicalID: "new-source", version: 1
        )
        let dependentRef = try ResearchObjectRef(
            projectID: "project-1", objectType: "claim", logicalID: "new-claim", version: 1
        )
        XCTAssertThrowsError(try store.append(draft(
            eventID: "event-forward-dependency", key: "key-forward-dependency",
            mutations: [
                try ResearchMutation(
                    ref: dependentRef,
                    operation: .put,
                    value: .object([:]),
                    dependsOn: [sourceRef]
                ),
                try ResearchMutation(ref: sourceRef, operation: .put, value: .object([:])),
            ]
        )))

        XCTAssertThrowsError(try store.append(makeDraft(
            eventID: "event-1", key: "key-project-2", result: "2", projectID: "project-2"
        ))) { XCTAssertEqual($0 as? ResearchOSCoreError, .duplicateIdentity) }
    }

    func testBranchReplayAndTimeTravelProduceDeterministicState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ResearchEventStore(rootDirectory: directory)
        let base = try store.append(makeDraft(eventID: "event-base", key: "base", result: "1"))
        let forkPayload: CanonicalJSONValue = .object([
            "source_branch": .string("main"),
            "source_sequence": .integer(1)
        ])
        _ = try store.append(ResearchEventDraft(
            eventID: "event-fork",
            projectID: "project-1",
            branchID: "alternative",
            kind: "branch.created",
            actorRef: "human:local",
            authorityRef: "role:owner",
            origin: "local",
            idempotencyKey: "fork",
            occurredAt: "2026-08-18T12:01:00Z",
            priorProjectDigest: String(repeating: "1", count: 64),
            resultProjectDigest: String(repeating: "1", count: 64),
            payload: forkPayload,
            parentEventIDs: [base.eventID]
        ))
        _ = try store.append(makeDraft(
            eventID: "event-alt",
            key: "alt",
            result: "3",
            branchID: "alternative",
            claimText: "Alternative bounded claim",
            objectVersion: 2
        ))

        let atFork = try store.projectState(projectID: "project-1", branchID: "alternative", throughSequence: 2)
        let latest = try store.projectState(projectID: "project-1", branchID: "alternative")
        XCTAssertEqual(atFork.objects["claim/claim-1"]?["text"]?.stringValue, "Initial bounded claim")
        XCTAssertEqual(latest.objects["claim/claim-1"]?["text"]?.stringValue, "Alternative bounded claim")
        let firstReplay = try store.replay(projectID: "project-1", branchID: "alternative")
        let secondReplay = try store.replay(projectID: "project-1", branchID: "alternative")
        XCTAssertEqual(firstReplay, secondReplay)
        XCTAssertEqual(firstReplay.frames.map(\.event.eventID), ["event-base", "event-fork", "event-alt"])
    }

    func testBranchForkRequiresOneExistingHistoricalSource() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ResearchEventStore(rootDirectory: directory)
        let base = try store.append(makeDraft(eventID: "event-base", key: "base", result: "1"))

        func fork(_ eventID: String, sourceSequence: Int) throws -> ResearchEventDraft {
            try ResearchEventDraft(
                eventID: eventID,
                projectID: "project-1",
                branchID: "alternative",
                kind: "branch.created",
                actorRef: "human:local",
                authorityRef: "role:owner",
                origin: "local",
                idempotencyKey: "key-\(eventID)",
                occurredAt: "2026-08-18T12:01:00Z",
                priorProjectDigest: String(repeating: "1", count: 64),
                resultProjectDigest: String(repeating: "1", count: 64),
                payload: .object([
                    "source_branch": .string("main"),
                    "source_sequence": .integer(Int64(sourceSequence))
                ]),
                parentEventIDs: [base.eventID]
            )
        }

        XCTAssertThrowsError(try store.append(fork("event-bad-fork", sourceSequence: 99)))
        _ = try store.append(fork("event-good-fork", sourceSequence: 1))
        XCTAssertThrowsError(try store.append(fork("event-second-fork", sourceSequence: 1)))
        XCTAssertEqual(try store.branchHistory(projectID: "project-1", branchID: "alternative").map(\.eventID), [
            "event-base", "event-good-fork"
        ])
    }

    func testExportImportRoundTripIsByteDeterministicAndProjectBounded() throws {
        let sourceDirectory = temporaryDirectory()
        let targetDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        let source = try ResearchEventStore(rootDirectory: sourceDirectory)
        _ = try source.append(makeDraft(eventID: "event-1", key: "key-1", result: "1"))
        let archive = try source.exportArchive(projectID: "project-1")
        let target = try ResearchEventStore(rootDirectory: targetDirectory)
        XCTAssertEqual(try target.importArchive(archive, expectedProjectID: "project-1"), 1)
        XCTAssertEqual(try target.importArchive(archive, expectedProjectID: "project-1"), 0)
        XCTAssertEqual(try target.exportArchive(projectID: "project-1"), archive)
        XCTAssertThrowsError(try target.importArchive(archive, expectedProjectID: "project-2")) {
            XCTAssertEqual($0 as? ResearchOSCoreError, .crossProject)
        }
    }

    func testImportRejectsCrossProjectEventIDCollisionBeforeWriting() throws {
        let targetDirectory = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: targetDirectory)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let target = try ResearchEventStore(rootDirectory: targetDirectory)
        _ = try target.append(makeDraft(
            eventID: "event-collision", key: "target-key", result: "1", projectID: "project-a"
        ))
        let originalJournal = try Data(contentsOf: target.eventJournalURL)

        let source = try ResearchEventStore(rootDirectory: sourceDirectory)
        _ = try source.append(makeDraft(
            eventID: "event-collision", key: "source-key", result: "2", projectID: "project-b"
        ))
        let archive = try source.exportArchive(projectID: "project-b")
        XCTAssertThrowsError(try target.importArchive(archive, expectedProjectID: "project-b")) {
            XCTAssertEqual($0 as? ResearchOSCoreError, .duplicateIdentity)
        }
        XCTAssertEqual(try Data(contentsOf: target.eventJournalURL), originalJournal)
        XCTAssertTrue(try ResearchEventStore(rootDirectory: targetDirectory).audit().valid)
    }

    func testCorruptTailFailsClosedThenExplicitHumanRecoveryQuarantinesBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ResearchEventStore(rootDirectory: directory)
        _ = try store.append(makeDraft(eventID: "event-1", key: "key-1", result: "1"))
        let handle = try FileHandle(forWritingTo: store.eventJournalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{truncated".utf8))
        try handle.close()
        XCTAssertFalse(store.audit().valid)
        XCTAssertThrowsError(
            try store.recover(actorRef: "ai:model", recoveredAt: "2026-08-18T13:00:00Z")
        ) { XCTAssertEqual($0 as? ResearchOSCoreError, .recoveryRequiresHuman) }
        let receipt = try XCTUnwrap(store.recover(
            actorRef: "human:local",
            recoveredAt: "2026-08-18T13:00:00Z"
        ))
        XCTAssertEqual(receipt.validEventCount, 1)
        XCTAssertGreaterThan(receipt.removedByteCount, 0)
        XCTAssertTrue(store.audit().valid)
    }

    func testLegacyArrayMigrationRemovesPlaintextSourceAndFutureManifestFailsClosed() throws {
        let sourceDirectory = temporaryDirectory()
        let legacyDirectory = temporaryDirectory()
        let futureDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: legacyDirectory)
            try? FileManager.default.removeItem(at: futureDirectory)
        }
        let source = try ResearchEventStore(rootDirectory: sourceDirectory)
        let event = try source.append(makeDraft(eventID: "event-1", key: "key-1", result: "1"))
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode([event]).write(
            to: legacyDirectory.appendingPathComponent("events-v0.json"),
            options: .atomic
        )
        let migrated = try ResearchEventStore(rootDirectory: legacyDirectory)
        XCTAssertEqual(try migrated.allEvents(), [event])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: legacyDirectory.appendingPathComponent("events-v0.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: legacyDirectory.appendingPathComponent("events-v0.migrated.json").path
        ))

        try FileManager.default.createDirectory(at: futureDirectory, withIntermediateDirectories: true)
        let futureManifest = Data(
            "{\"event_schema_version\":1,\"schema_id\":\"com.challa.research-os.mobile.event-store\",\"store_schema_version\":2}".utf8
        )
        try futureManifest.write(to: futureDirectory.appendingPathComponent("store-manifest.json"))
        XCTAssertThrowsError(try ResearchEventStore(rootDirectory: futureDirectory)) {
            XCTAssertEqual($0 as? ResearchOSCoreError, .unsupportedSchema)
        }
    }

    func testAIIsProposalOnlyAndRepairVerifyKeepHumanAuthority() throws {
        XCTAssertThrowsError(try ResearchEventDraft(
            eventID: "event-ai",
            projectID: "project-1",
            branchID: "main",
            kind: "claim.proposed",
            actorRef: "agent:model",
            authorityRef: "role:owner",
            origin: "ai:local-model",
            idempotencyKey: "ai-1",
            occurredAt: "2026-08-18T12:00:00Z",
            priorProjectDigest: ResearchOSSchema.zeroDigest,
            resultProjectDigest: String(repeating: "1", count: 64),
            payload: .object(["proposal_only": .bool(false)])
        )) { XCTAssertEqual($0 as? ResearchOSCoreError, .proposalOnlyRequired) }

        for forbiddenKind in ["protocol.frozen", "authority.granted"] {
            XCTAssertThrowsError(try ResearchEventDraft(
                eventID: "event-ai-\(forbiddenKind.replacingOccurrences(of: ".", with: "-"))",
                projectID: "project-1",
                branchID: "main",
                kind: forbiddenKind,
                actorRef: "model:gpt",
                authorityRef: "role:owner",
                origin: "model",
                idempotencyKey: "ai-\(forbiddenKind.replacingOccurrences(of: ".", with: "-"))",
                occurredAt: "2026-08-18T12:00:00Z",
                priorProjectDigest: ResearchOSSchema.zeroDigest,
                resultProjectDigest: String(repeating: "1", count: 64),
                payload: .object(["proposal_only": .bool(true)])
            )) { XCTAssertEqual($0 as? ResearchOSCoreError, .proposalOnlyRequired) }
        }

        XCTAssertThrowsError(try ResearchEventDraft(
            eventID: "event-repair",
            projectID: "project-1",
            branchID: "main",
            kind: "repair.applied",
            actorRef: "agent:model",
            authorityRef: "role:owner",
            origin: "local",
            idempotencyKey: "repair-1",
            occurredAt: "2026-08-18T12:00:00Z",
            priorProjectDigest: ResearchOSSchema.zeroDigest,
            resultProjectDigest: String(repeating: "1", count: 64),
            payload: .object([:])
        )) { XCTAssertEqual($0 as? ResearchOSCoreError, .humanAuthorityRequired) }

        for (actor, origin) in [("model:gpt", "local"), ("human:local", "remote-ai:model")] {
            XCTAssertThrowsError(try ResearchEventDraft(
                eventID: "event-model-\(actor.replacingOccurrences(of: ":", with: "-"))",
                projectID: "project-1",
                branchID: "main",
                kind: "claim.proposed",
                actorRef: actor,
                authorityRef: "role:owner",
                origin: origin,
                idempotencyKey: "model-\(origin.replacingOccurrences(of: ":", with: "-"))",
                occurredAt: "2026-08-18T12:00:00Z",
                priorProjectDigest: ResearchOSSchema.zeroDigest,
                resultProjectDigest: String(repeating: "1", count: 64),
                payload: .object([:])
            )) { XCTAssertEqual($0 as? ResearchOSCoreError, .proposalOnlyRequired) }
        }

        let claimRef = try ResearchObjectRef(
            projectID: "project-1", objectType: "claim", logicalID: "claim-ai", version: 1
        )
        let claimMutation = try ResearchMutation(
            ref: claimRef,
            operation: .put,
            value: .object(["text": .string("AI must not write this claim")])
        )
        XCTAssertThrowsError(try ResearchEventDraft(
            eventID: "event-ai-claim",
            projectID: "project-1",
            branchID: "main",
            kind: "claim.proposed",
            actorRef: "model:gpt",
            authorityRef: "role:owner",
            origin: "model",
            idempotencyKey: "ai-claim",
            occurredAt: "2026-08-18T12:00:00Z",
            priorProjectDigest: ResearchOSSchema.zeroDigest,
            resultProjectDigest: String(repeating: "1", count: 64),
            payload: .object([
                "proposal_only": .bool(true),
                "mutations": .array([try CanonicalJSON.value(from: claimMutation)])
            ]),
            objectRefs: [claimRef]
        )) { XCTAssertEqual($0 as? ResearchOSCoreError, .proposalOnlyRequired) }
    }

    func testTypedContractsRevalidateInvariantsDuringDecode() throws {
        let hostileObject = Data("""
        {"branch_id":"main","classification":"PRIVATE_RESEARCH","content":{},"kind":"claim","ref":{"logical_id":"claim-1","object_type":"claim","project_id":"project-1","version":1},"schema_id":"hostile.object","schema_version":1,"stage":"REVIEW"}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(VersionedResearchObject.self, from: hostileObject))

        let validObject = try VersionedResearchObject(
            ref: ResearchObjectRef(projectID: "project-1", objectType: "claim", logicalID: "claim-1", version: 1),
            branchID: "main",
            kind: .claim,
            stage: .review,
            classification: .privateResearch,
            content: .object(["text": .string("bounded")])
        )
        var proposal = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(try ResearchAIProposal(
                proposalID: "proposal-1",
                projectID: "project-1",
                branchID: "main",
                proposedObject: validObject,
                rationale: "Narrow the population."
            ))) as? [String: Any]
        )
        proposal["proposal_only"] = false
        XCTAssertThrowsError(try JSONDecoder().decode(
            ResearchAIProposal.self,
            from: JSONSerialization.data(withJSONObject: proposal, options: [.sortedKeys])
        ))

        let hostileDecision = Data("""
        {"actor_ref":"ai:model","authority_ref":"role:owner","proposal_id":"proposal-1","decision":"accepted","decided_at":"2026-08-18T12:00:00Z"}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HumanAuthorityDecision.self, from: hostileDecision)) {
            XCTAssertEqual($0 as? ResearchOSCoreError, .humanAuthorityRequired)
        }
    }

    @MainActor
    func testWorkspaceProjectionSurvivesRestartAndBatchesDraftKeystrokes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ResearchWorkspaceStore(
            projects: [],
            storageDirectory: directory,
            clock: { instant },
            draftPersistenceDelayNanoseconds: 60_000_000_000
        )
        let projectID = try XCTUnwrap(first.createProject(
            title: "Durable workspace",
            question: "What survives a restart?"
        ))
        XCTAssertNil(first.persistenceFailure)
        XCTAssertEqual(try first.eventHistory(projectID: projectID).count, 1)

        first.updateProject(id: projectID) { $0.scope.population = "First edit" }
        first.updateProject(id: projectID) { $0.scope.population = "Final bounded edit" }
        XCTAssertEqual(try first.eventHistory(projectID: projectID).count, 1)
        try first.flushPendingChanges()
        XCTAssertEqual(try first.eventHistory(projectID: projectID).count, 2)

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(restarted.persistenceFailure)
        XCTAssertEqual(restarted.project(id: projectID)?.scope.population, "Final bounded edit")
        XCTAssertEqual(try restarted.eventHistory(projectID: projectID).map(\.kind), [
            ResearchWorkspaceEventKind.projectCreated.rawValue,
            ResearchWorkspaceEventKind.projectSnapshotSaved.rawValue,
        ])
    }

    @MainActor
    func testRepairDecisionAppendsHumanReceiptWithoutRewritingHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let projectID = try XCTUnwrap(workspace.createProject(
            title: "Append-only decisions",
            question: "Can a decision preserve its prior records?"
        ))
        workspace.addRepair(
            projectID: projectID,
            before: "Unbounded claim",
            after: "Bounded claim",
            reason: "Match the evidence"
        )
        let repairID = try XCTUnwrap(workspace.project(id: projectID)?.repairs.first?.id)
        let journalURL = directory.appendingPathComponent("events-v1.jsonl")
        let prefix = try Data(contentsOf: journalURL)

        workspace.confirmRepair(projectID: projectID, repairID: repairID)

        let complete = try Data(contentsOf: journalURL)
        XCTAssertTrue(complete.starts(with: prefix))
        XCTAssertGreaterThan(complete.count, prefix.count)
        let decisionEvent = try XCTUnwrap(workspace.eventHistory(projectID: projectID).last)
        XCTAssertEqual(decisionEvent.kind, ResearchWorkspaceEventKind.repairConfirmed.rawValue)
        XCTAssertEqual(decisionEvent.actorRef, "human:local")
        XCTAssertEqual(decisionEvent.authorityRef, "role:owner")
        let payload = try JSONDecoder().decode(
            ResearchWorkspaceEventPayload.self,
            from: CanonicalJSON.encode(decisionEvent.payload)
        )
        XCTAssertEqual(payload.humanDecision?.decision, "confirmed")
        XCTAssertNotNil(workspace.project(id: projectID)?.repairs.first?.confirmedAt)
    }

    @MainActor
    func testWorkspaceTimeTravelAndArchiveAreDeterministic() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let projectID = try XCTUnwrap(workspace.createProject(
            title: "Original title",
            question: "What did the project say then?"
        ))
        workspace.renameProject(id: projectID, to: "Revised title")

        XCTAssertEqual(try workspace.project(id: projectID, throughSequence: 1)?.title, "Original title")
        XCTAssertEqual(try workspace.project(id: projectID, throughSequence: 2)?.title, "Revised title")
        let firstArchive = try workspace.exportArchiveData(id: projectID)
        let secondArchive = try workspace.exportArchiveData(id: projectID)
        XCTAssertEqual(firstArchive, secondArchive)
        let archive = try JSONDecoder().decode(ResearchEventArchive.self, from: firstArchive)
        XCTAssertEqual(archive.events, try workspace.eventHistory(projectID: projectID))
        XCTAssertEqual(archive.exportedHeadDigest, archive.events.last?.chainDigest)

    }

    @MainActor
    func testProjectPurgeSurvivesRestartRemovesRawContentAndPreservesOtherProject() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let removedID = try XCTUnwrap(first.createProject(
            title: "PURGE_ME_SECRET_ALPHA",
            question: "PURGE_ME_SECRET_QUESTION",
            subscriptionState: .plusActive(expirationDate: nil)
        ))
        let retainedID = try XCTUnwrap(first.createProject(
            title: "Retained project",
            question: "Should this remain intact?",
            subscriptionState: .plusActive(expirationDate: nil)
        ))

        let recoveryStore = try ResearchEventStore(rootDirectory: directory)
        let quarantinedEvent = try XCTUnwrap(recoveryStore.events(
            projectID: removedID.uuidString.lowercased()
        ).last)
        let recoveryHandle = try FileHandle(forWritingTo: recoveryStore.eventJournalURL)
        try recoveryHandle.seekToEnd()
        try recoveryHandle.write(contentsOf: Data("{invalid-recovery-tail\n".utf8))
        try recoveryHandle.write(contentsOf: CanonicalJSON.encode(quarantinedEvent))
        try recoveryHandle.write(contentsOf: Data([0x0A]))
        try recoveryHandle.close()
        XCTAssertNotNil(try recoveryStore.recover(
            actorRef: "human:local",
            recoveredAt: "2026-08-18T14:00:00Z"
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Recovery", isDirectory: true).path
        ))

        let beforeDelete = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNotNil(beforeDelete.project(id: removedID))
        let retainedEvents = try beforeDelete.eventHistory(projectID: retainedID)
        let removedExportURL = try beforeDelete.exportProjectFile(id: removedID)
        let retainedExportURL = try beforeDelete.exportProjectFile(id: retainedID)
        XCTAssertTrue(removedExportURL.path.contains("ManagedExports"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedExportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedExportURL.path))
        let legacyBytes = try JSONEncoder().encode(try beforeDelete.eventHistory(projectID: removedID))
        try legacyBytes.write(to: directory.appendingPathComponent("events-v0.json"), options: .atomic)
        try legacyBytes.write(to: directory.appendingPathComponent("events-v0.migrated.json"), options: .atomic)
        let receipt = try XCTUnwrap(beforeDelete.deleteProject(id: removedID))
        XCTAssertEqual(receipt.schemaID, ResearchOSSchema.projectDeletionReceipt)
        XCTAssertEqual(receipt.projectID, removedID.uuidString.lowercased())
        XCTAssertGreaterThan(receipt.removedEventCount, 0)
        XCTAssertEqual(receipt.actorRef, "human:local")
        XCTAssertTrue(receipt.storageCaveat.contains("OS backups"))
        XCTAssertNil(beforeDelete.project(id: removedID))
        XCTAssertEqual(try beforeDelete.eventHistory(projectID: removedID), [])
        XCTAssertEqual(try beforeDelete.eventHistory(projectID: retainedID), retainedEvents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedExportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedExportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Recovery", isDirectory: true).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("events-v0.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("events-v0.migrated.json").path
        ))

        let rawJournal = try String(
            contentsOf: directory.appendingPathComponent("events-v1.jsonl"),
            encoding: .utf8
        )
        XCTAssertFalse(rawJournal.contains(removedID.uuidString.lowercased()))
        XCTAssertFalse(rawJournal.contains(removedID.uuidString.uppercased()))
        XCTAssertFalse(rawJournal.contains("PURGE_ME_SECRET_ALPHA"))
        XCTAssertFalse(rawJournal.contains("PURGE_ME_SECRET_QUESTION"))
        XCTAssertTrue(rawJournal.contains(retainedID.uuidString.lowercased()))
        XCTAssertTrue(rawJournal.contains("Retained project"))

        let rawStoredFiles = String(decoding: try storedBytes(in: directory), as: UTF8.self)
        XCTAssertFalse(rawStoredFiles.contains(removedID.uuidString.lowercased()))
        XCTAssertFalse(rawStoredFiles.contains(removedID.uuidString.uppercased()))
        XCTAssertFalse(rawStoredFiles.contains("PURGE_ME_SECRET_ALPHA"))
        XCTAssertFalse(rawStoredFiles.contains("PURGE_ME_SECRET_QUESTION"))
        XCTAssertTrue(rawStoredFiles.contains(retainedID.uuidString.lowercased()))
        XCTAssertTrue(rawStoredFiles.contains("Retained project"))

        let afterDelete = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(afterDelete.persistenceFailure)
        XCTAssertNil(afterDelete.project(id: removedID))
        XCTAssertEqual(afterDelete.project(id: retainedID)?.title, "Retained project")
    }

    func testFailedAtomicProjectPurgeLeavesOriginalJournalIntact() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = try ResearchEventStore(rootDirectory: directory)
        _ = try originalStore.append(makeDraft(
            eventID: "event-project-1",
            key: "key-project-1",
            result: "1",
            projectID: "project-1"
        ))
        _ = try originalStore.append(makeDraft(
            eventID: "event-project-2",
            key: "key-project-2",
            result: "2",
            projectID: "project-2"
        ))
        let journalURL = directory.appendingPathComponent("events-v1.jsonl")
        let originalBytes = try Data(contentsOf: journalURL)
        let originalEvents = try originalStore.allEvents()
        let failingStore = try ResearchEventStore(
            rootDirectory: directory,
            atomicJournalWriter: { _, _ in
                throw NSError(domain: "ResearchEventStoreTests", code: 73)
            }
        )

        XCTAssertThrowsError(try failingStore.purgeProject(
            projectID: "project-1",
            actorRef: "human:local",
            authorityRef: "role:owner",
            deletedAt: "2026-08-18T14:00:00Z"
        ))
        XCTAssertEqual(try Data(contentsOf: journalURL), originalBytes)
        XCTAssertEqual(try failingStore.allEvents(), originalEvents)
    }

    func testLateWriterErrorAfterExactReplacementCountsAsCommittedPurge() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = try ResearchEventStore(rootDirectory: directory)
        _ = try originalStore.append(makeDraft(
            eventID: "event-project-1", key: "key-project-1", result: "1", projectID: "project-1"
        ))
        _ = try originalStore.append(makeDraft(
            eventID: "event-project-2", key: "key-project-2", result: "2", projectID: "project-2"
        ))
        let lateErrorStore = try ResearchEventStore(
            rootDirectory: directory,
            atomicJournalWriter: { data, url in
                try data.write(to: url, options: .atomic)
                throw NSError(domain: "ResearchEventStoreTests", code: 75)
            }
        )
        let receipt = try lateErrorStore.purgeProject(
            projectID: "project-1",
            actorRef: "human:local",
            authorityRef: "role:owner",
            deletedAt: "2026-08-18T14:00:00Z"
        )
        XCTAssertEqual(receipt.removedEventCount, 1)
        XCTAssertTrue(try lateErrorStore.events(projectID: "project-1").isEmpty)
        XCTAssertEqual(try lateErrorStore.events(projectID: "project-2").count, 1)
        XCTAssertTrue(try ResearchEventStore(rootDirectory: directory).audit().valid)
    }

    @MainActor
    func testBackwardDeviceClockNeverCreatesAnUnreplayableWorkspaceTransition() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var current = Date(timeIntervalSince1970: 1_800_000_100)
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory, clock: { current })
        let projectID = try XCTUnwrap(workspace.createProject(title: "Clock-safe", question: "Can time regress?"))
        let originalTime = try XCTUnwrap(workspace.project(id: projectID)?.updatedAt)
        current = originalTime.addingTimeInterval(-3_600)
        workspace.renameProject(id: projectID, to: "Still replayable")
        XCTAssertEqual(workspace.project(id: projectID)?.updatedAt, originalTime)

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(restarted.persistenceFailure)
        XCTAssertEqual(restarted.project(id: projectID)?.title, "Still replayable")
        XCTAssertEqual(restarted.project(id: projectID)?.updatedAt, originalTime)
    }

    @MainActor
    func testWorkspacePurgeWriterFailureKeepsJournalAndProjectsAfterManagedExportCleanup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(
            projects: [],
            storageDirectory: directory,
            atomicJournalWriter: { _, _ in
                throw NSError(domain: "ResearchWorkspaceStoreTests", code: 74)
            }
        )
        let removedID = try XCTUnwrap(workspace.createProject(
            title: "FAILED_PURGE_SECRET",
            question: "Must the canonical bytes survive a failed rewrite?",
            subscriptionState: .plusActive(expirationDate: nil)
        ))
        let retainedID = try XCTUnwrap(workspace.createProject(
            title: "Failure isolation control",
            question: "Does the other project remain?",
            subscriptionState: .plusActive(expirationDate: nil)
        ))
        let removedExportURL = try workspace.exportProjectFile(id: removedID)
        let retainedExportURL = try workspace.exportProjectFile(id: retainedID)
        let recoveryDirectory = directory.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let recoveryArtifact = recoveryDirectory.appendingPathComponent("corrupt-tail-test.bin")
        try Data("\(removedID.uuidString.lowercased()) FAILED_PURGE_SECRET".utf8).write(
            to: recoveryArtifact,
            options: .atomic
        )
        let legacyArtifact = directory.appendingPathComponent("events-v0.migrated.json")
        try Data("\(removedID.uuidString.lowercased()) FAILED_PURGE_SECRET".utf8).write(
            to: legacyArtifact,
            options: .atomic
        )
        let journalURL = directory.appendingPathComponent("events-v1.jsonl")
        let originalJournal = try Data(contentsOf: journalURL)

        XCTAssertNil(workspace.deleteProject(id: removedID))
        XCTAssertNotNil(workspace.deletionFailure)
        XCTAssertEqual(try Data(contentsOf: journalURL), originalJournal)
        XCTAssertNotNil(workspace.project(id: removedID))
        XCTAssertNotNil(workspace.project(id: retainedID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedExportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedExportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyArtifact.path))

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(restarted.persistenceFailure)
        XCTAssertEqual(restarted.project(id: removedID)?.title, "FAILED_PURGE_SECRET")
        XCTAssertEqual(restarted.project(id: retainedID)?.title, "Failure isolation control")
    }

    @MainActor
    func testDowngradeAndRestartPreserveAuthorizedDraftsAndBlockNewWrites() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(
            projects: [],
            storageDirectory: directory,
            draftPersistenceDelayNanoseconds: 60_000_000_000
        )
        let firstID = try XCTUnwrap(workspace.createProject(
            title: "First Plus project",
            question: "Which project owns the free edit slot?",
            subscriptionState: .plusActive(expirationDate: nil)
        ))
        let secondID = try XCTUnwrap(workspace.createProject(
            title: "Second Plus project",
            question: "Does downgrade retain this without granting writes?",
            subscriptionState: .plusActive(expirationDate: nil)
        ))
        workspace.updateSubscriptionAccess(.plusActive(expirationDate: nil))
        XCTAssertTrue(workspace.canMutateProject(id: firstID))
        XCTAssertTrue(workspace.canMutateProject(id: secondID))
        workspace.updateProject(id: firstID) { $0.scope.population = "Pending first edit" }
        workspace.updateProject(id: secondID) { $0.scope.population = "Pending second edit" }

        workspace.updateSubscriptionAccess(.free)
        let editableIDs = [firstID, secondID].filter { workspace.canMutateProject(id: $0) }
        XCTAssertEqual(editableIDs.count, 1)
        let editableID = try XCTUnwrap(editableIDs.first)
        let retainedReadOnlyID = editableID == firstID ? secondID : firstID
        XCTAssertNotNil(workspace.mutationAccessReason(projectID: retainedReadOnlyID))
        let retainedTitle = try XCTUnwrap(workspace.project(id: retainedReadOnlyID)?.title)
        workspace.updateProject(id: retainedReadOnlyID) { $0.scope.population = "BLOCKED_AFTER_DOWNGRADE" }
        workspace.renameProject(id: retainedReadOnlyID, to: "BLOCKED_RENAME")
        XCTAssertNotNil(workspace.mutationAccessFailure)
        try workspace.flushPendingChanges()

        XCTAssertEqual(workspace.project(id: editableID)?.scope.population,
                       editableID == firstID ? "Pending first edit" : "Pending second edit")
        XCTAssertEqual(workspace.project(id: retainedReadOnlyID)?.scope.population,
                       retainedReadOnlyID == firstID ? "Pending first edit" : "Pending second edit")
        XCTAssertEqual(workspace.project(id: retainedReadOnlyID)?.title, retainedTitle)
        XCTAssertFalse(try workspace.exportArchiveData(id: retainedReadOnlyID).isEmpty)

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertEqual([firstID, secondID].filter { restarted.canMutateProject(id: $0) }, [editableID])
        XCTAssertEqual(restarted.project(id: retainedReadOnlyID)?.scope.population,
                       retainedReadOnlyID == firstID ? "Pending first edit" : "Pending second edit")
        XCTAssertEqual(restarted.project(id: retainedReadOnlyID)?.title, retainedTitle)
        restarted.archiveProject(id: retainedReadOnlyID)
        XCTAssertEqual(restarted.project(id: retainedReadOnlyID)?.status, .archived)
        XCTAssertFalse(restarted.canMutateProject(id: retainedReadOnlyID))
        XCTAssertNotNil(restarted.deleteProject(id: retainedReadOnlyID))

        let afterDelete = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(afterDelete.project(id: retainedReadOnlyID))
        XCTAssertNotNil(afterDelete.project(id: editableID))
    }

    func testDecodedMutationReappliesDeleteAndProjectBoundaryValidation() throws {
        let invalidDelete = Data("""
        {
          "depends_on": [],
          "operation": "delete",
          "ref": {"logical_id":"claim-1","object_type":"claim","project_id":"project-1","version":1},
          "value": {"secret":"must not ride a delete"}
        }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ResearchMutation.self, from: invalidDelete))

        let crossProjectDependency = Data("""
        {
          "depends_on": [{"logical_id":"evidence-1","object_type":"evidence","project_id":"project-2","version":1}],
          "operation": "put",
          "ref": {"logical_id":"claim-1","object_type":"claim","project_id":"project-1","version":1},
          "value": {"text":"bounded"}
        }
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ResearchMutation.self, from: crossProjectDependency)) {
            XCTAssertEqual($0 as? ResearchOSCoreError, .crossProject)
        }
    }

    @MainActor
    func testForgedTypedRenameCannotChangeArchiveStatus() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        let projectID = try XCTUnwrap(workspace.createProject(
            title: "Typed transition",
            question: "Can rename smuggle another mutation?"
        ))
        let previous = try XCTUnwrap(workspace.project(id: projectID))
        var forged = previous
        forged.title = "Apparently renamed"
        forged.status = .archived
        forged.updatedAt = previous.updatedAt.addingTimeInterval(1)

        let eventStore = try ResearchEventStore(rootDirectory: directory)
        let head = try XCTUnwrap(eventStore.events(projectID: projectID.uuidString.lowercased()).last)
        let ref = try ResearchObjectRef(
            projectID: projectID.uuidString.lowercased(),
            objectType: "project",
            logicalID: projectID.uuidString.lowercased(),
            version: 2
        )
        let mutation = try ResearchMutation(
            ref: ref,
            operation: .put,
            value: try workspaceProjectValue(forged)
        )
        let payload = ResearchWorkspaceEventPayload(
            command: .projectRenamed,
            classification: forged.classification,
            mutations: [mutation],
            humanDecision: nil,
            tombstone: false
        )
        _ = try eventStore.append(
            ResearchEventDraft(
                eventID: "event-forged-rename",
                projectID: projectID.uuidString.lowercased(),
                branchID: "main",
                kind: ResearchWorkspaceEventKind.projectRenamed.rawValue,
                actorRef: "human:local",
                authorityRef: "role:owner",
                origin: "ios:local",
                idempotencyKey: "command-forged-rename",
                occurredAt: "2026-08-18T15:00:00Z",
                priorProjectDigest: try workspaceProjectDigest(previous),
                resultProjectDigest: try workspaceProjectDigest(forged),
                payload: try CanonicalJSON.value(from: payload),
                objectRefs: [ref],
                parentEventIDs: [head.eventID]
            ),
            expectedChainDigest: head.chainDigest
        )

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertTrue(restarted.projects.isEmpty)
        XCTAssertNotNil(restarted.persistenceFailure)
    }

    @MainActor
    func testWorkspaceCorruptionFailsClosedWithoutImplicitRecovery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        _ = try XCTUnwrap(first.createProject(
            title: "Corruption probe",
            question: "Will invalid history be rejected?"
        ))
        let journalURL = directory.appendingPathComponent("events-v1.jsonl")
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{truncated".utf8))
        try handle.close()
        let corruptBytes = try Data(contentsOf: journalURL)

        let restarted = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertTrue(restarted.projects.isEmpty)
        XCTAssertNotNil(restarted.persistenceFailure)
        XCTAssertNil(restarted.createProject(title: "Must not write", question: "Is the store locked?"))
        XCTAssertEqual(try Data(contentsOf: journalURL), corruptBytes)
        XCTAssertTrue(restarted.canRecoverCorruptTail)
        let receipt = try XCTUnwrap(restarted.recoverCorruptTail())
        XCTAssertEqual(receipt.validEventCount, 1)
        XCTAssertGreaterThan(receipt.removedByteCount, 0)
        XCTAssertNil(restarted.persistenceFailure)
        XCTAssertEqual(restarted.projects.count, 1)

        let afterRecovery = ResearchWorkspaceStore(projects: [], storageDirectory: directory)
        XCTAssertNil(afterRecovery.persistenceFailure)
        XCTAssertEqual(afterRecovery.projects.count, 1)
    }

    private var fixtureURL: URL {
        get throws {
            try XCTUnwrap(
                Bundle(for: Self.self).url(
                    forResource: "python-swift-event-v1",
                    withExtension: "json"
                )
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("research-os-core-\(UUID().uuidString)", isDirectory: true)
    }

    private func workspaceProjectValue(_ project: ResearchProject) throws -> CanonicalJSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.decodeValue(encoder.encode(project))
    }

    private func workspaceProjectDigest(_ project: ResearchProject) throws -> String {
        try CanonicalJSON.digest(workspaceProjectValue(project))
    }

    private func storedBytes(in directory: URL) throws -> Data {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        )
        var result = Data()
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: Set(keys)).isRegularFile == true {
                result.append(try Data(contentsOf: url))
                result.append(0)
            }
        }
        return result
    }

    private func makeDraft(
        eventID: String,
        key: String,
        result: Character,
        branchID: String = "main",
        claimText: String = "Initial bounded claim",
        projectID: String = "project-1",
        objectVersion: Int = 1
    ) throws -> ResearchEventDraft {
        let ref = try ResearchObjectRef(
            projectID: projectID,
            objectType: "claim",
            logicalID: "claim-1",
            version: objectVersion
        )
        let mutation = try ResearchMutation(
            ref: ref,
            operation: .put,
            value: .object(["text": .string(claimText)])
        )
        return try ResearchEventDraft(
            eventID: eventID,
            projectID: projectID,
            branchID: branchID,
            kind: "claim.reviewed",
            actorRef: "human:local",
            authorityRef: "role:owner",
            origin: "local",
            idempotencyKey: key,
            occurredAt: "2026-08-18T12:00:00Z",
            priorProjectDigest: ResearchOSSchema.zeroDigest,
            resultProjectDigest: String(repeating: String(result), count: 64),
            payload: .object([
                "classification": .string("SYNTHETIC_DEMO_ONLY"),
                "mutations": .array([try CanonicalJSON.value(from: mutation)]),
                "workflow_stage": .string("REVIEW")
            ]),
            objectRefs: [ref]
        )
    }
}
