from __future__ import annotations

from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
IOS = REPO / "mobile" / "research-os-ios"
APP = IOS / "ResearchOSFlightRecorder"
TESTS = IOS / "ResearchOSFlightRecorderTests"


def source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def function_body(swift: str, start: str, end: str) -> str:
    return swift.split(start, 1)[1].split(end, 1)[0]


def test_workspace_authority_is_a_protected_application_support_event_store() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    event_store = source(APP / "Core" / "ResearchEventStore.swift")
    assert "let store = try ResearchEventStore(" in workspace
    assert "rootDirectory: directory" in workspace
    assert ".applicationSupportDirectory" in workspace
    assert 'appendingPathComponent("ResearchWorkspace"' in workspace
    assert 'appendingPathComponent("EventStore"' in workspace
    assert "FileProtectionType.complete" in event_store
    assert ".completeFileProtection" in event_store
    assert "UserDefaults" not in workspace


def test_workspace_commands_are_typed_digest_bound_human_events() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    for event_kind in (
        'projectCreated = "project.created"',
        'projectSnapshotSaved = "project.snapshot_saved"',
        'projectDeleted = "project.deleted"',
        'repairConfirmed = "repair.confirmed"',
        'proofGateConfirmed = "verification.confirmed"',
        'protocolFrozen = "protocol.frozen"',
        'advancedWorkspaceActivated = "workspace.plus_activated"',
    ):
        assert event_kind in workspace
    for authority_field in (
        'actorRef: "human:local"',
        'authorityRef: "role:owner"',
        "priorProjectDigest:",
        "resultProjectDigest:",
        "expectedChainDigest:",
        "ResearchWorkspaceEventPayload",
        "ResearchMutation",
    ):
        assert authority_field in workspace


def test_free_text_edits_are_bounded_but_semantic_decisions_append_immediately() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    application = source(APP / "ResearchOSFlightRecorderApp.swift")
    update = function_body(
        workspace,
        "func updateProject(id: UUID",
        "func addInboxItem(",
    )
    assert "scheduleDraftPersistence(for: id)" in update
    assert "appendTransition(" not in update
    assert "Task.sleep(nanoseconds: delay)" in workspace
    assert "flushPendingChanges()" in workspace
    assert "scenePhase" in application
    assert "workspace.flushPendingChanges()" in application
    assert "kind: .repairConfirmed" in workspace
    assert "kind: .proofGateConfirmed" in workspace
    assert "humanDecision:" in workspace


def test_downgrade_enforces_one_deterministic_free_edit_slot_in_the_store() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    application = source(APP / "ResearchOSFlightRecorderApp.swift")
    library = source(APP / "WorkspaceLibraryView.swift")
    update = function_body(workspace, "func updateProject(id: UUID", "func addInboxItem(")
    commit = function_body(workspace, "private func commitProjectCommand(", "private func scheduleDraftPersistence")
    flush = function_body(workspace, "private func flushPendingProject", "private func appendTransition")
    assert "func updateSubscriptionAccess(_ state: SubscriptionAccessState)" in workspace
    assert "private var freeEditableUserProjectID" in workspace
    assert "$0.createdAt < $1.createdAt" in workspace
    assert "authorizeMutation(projectID: id)" in update
    assert "authorizeMutation(projectID: id)" in commit
    assert "guard canMutateProject(id: id)" in flush
    assert "restorePersistedProjection(id: id)" in flush
    assert "workspace.updateSubscriptionAccess(subscriptions.state)" in application
    assert "onChange(of: subscriptions.state)" in application
    assert "mutationAccessReason(projectID: projectID)" in library
    archive = function_body(workspace, "func archiveProject(id: UUID)", "func restoreProject(")
    assert "capabilityPolicyApproved: true" in archive


def test_delete_is_an_atomic_privacy_purge_and_export_is_the_canonical_event_archive() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    event_store = source(APP / "Core" / "ResearchEventStore.swift")
    library = source(APP / "WorkspaceLibraryView.swift")
    workflows = source(APP / "ResearchWorkflowViews.swift")
    root_view = source(APP / "RootView.swift")
    delete = function_body(workspace, "func deleteProject(id: UUID)", "func updateProject(id: UUID")
    assert "purgeManagedExports(projectID: id)" in delete
    assert "eventStore.purgeProject(" in delete
    assert delete.index("purgeManagedExports(projectID: id)") < delete.index("eventStore.purgeProject(")
    assert delete.index("eventStore.purgeProject(") < delete.index("projects.removeAll")
    assert "ResearchProjectDeletionReceipt" in event_store
    assert "purgeNoncanonicalArtifacts()" in event_store
    assert "purgeLegacyMigrationArtifacts()" in event_store
    assert "fileManager.removeItem(at: quarantineDirectory)" in event_store
    assert "atomicJournalWriter(rewritten, journalURL)" in event_store
    assert "all.filter { $0.projectID != projectID }" in event_store
    assert "rewritten.range(of: Data(projectID.utf8))" not in event_store
    assert "prior OS backups" in event_store
    assert "physical flash remnants may persist" in event_store
    assert "eventStore.exportArchive" in workspace
    assert "JSONEncoder().encode(project)" not in workspace
    assert "-event-archive.json" in workspace
    assert 'appendingPathComponent("ManagedExports"' in workspace
    assert "FileManager.default.temporaryDirectory" not in workspace
    assert '.onAppear { prepareExport() }' not in library
    assert '.onAppear { prepareExport() }' not in workflows
    assert '.task { prepareExport() }' not in root_view
    assert 'Button("Prepare event archive"' in library
    assert 'Button("Prepare event archive"' in workflows
    assert 'Button("Prepare verified project record"' in root_view
    assert "Copies you already shared are outside this app's control" in library


def test_projection_validates_transition_digests_and_fails_closed() -> None:
    workspace = source(APP / "ResearchWorkspace.swift")
    contracts = source(APP / "Core" / "ResearchOSContracts.swift")
    assert "materializeProjection(from:" in workspace
    assert "validateTransition(command:" in workspace
    for command in (
        ".projectRenamed:",
        ".projectArchived:",
        ".repairConfirmed:",
        ".proofGateConfirmed:",
        ".advancedWorkspaceActivated:",
    ):
        assert command in workspace
    assert "event.priorProjectDigest == expectedPrior" in workspace
    assert "event.resultProjectDigest == expectedResult" in workspace
    assert "mutation.ref.version == event.sequence" in workspace
    assert "init(from decoder: Decoder) throws" in contracts
    assert "delete mutations cannot carry a value" in contracts
    assert "mutation inventory does not match object_refs" in contracts
    assert "dateEncodingStrategy = .custom" in workspace
    assert "dateDecodingStrategy = .custom" in workspace
    assert "timestampDate(value)" in workspace
    assert "enterFailClosed(error)" in workspace
    fail_closed = function_body(workspace, "private func enterFailClosed", "private static func projectID")
    assert "canRecoverCorruptTail" in workspace
    assert "persistenceFailure" in fail_closed
    assert "eventStore = nil" not in fail_closed
    assert "persistedProjects.removeAll()" in fail_closed
    assert "projects = []" in fail_closed


def test_first_launch_creation_orders_journal_before_manifest() -> None:
    event_store = source(APP / "Core" / "ResearchEventStore.swift")
    prepare = function_body(event_store, "private func prepareStore()", "private func writeCurrentManifest()")
    assert prepare.index("createFile(atPath: journalURL.path") < prepare.index("writeCurrentManifest()")


def test_xctest_covers_restart_append_only_time_travel_export_and_corruption() -> None:
    tests = source(TESTS / "CoreParityTests.swift")
    for test_name in (
        "testWorkspaceProjectionSurvivesRestartAndBatchesDraftKeystrokes",
        "testRepairDecisionAppendsHumanReceiptWithoutRewritingHistory",
        "testWorkspaceTimeTravelAndArchiveAreDeterministic",
        "testProjectPurgeSurvivesRestartRemovesRawContentAndPreservesOtherProject",
        "testFailedAtomicProjectPurgeLeavesOriginalJournalIntact",
        "testWorkspacePurgeWriterFailureKeepsJournalAndProjectsAfterManagedExportCleanup",
        "testDowngradeAndRestartPreserveAuthorizedDraftsAndBlockNewWrites",
        "testWorkspaceCorruptionFailsClosedWithoutImplicitRecovery",
    ):
        assert f"func {test_name}" in tests
    assert "complete.starts(with: prefix)" in tests
    assert "XCTAssertEqual(firstArchive, secondArchive)" in tests
    assert "throughSequence: 1" in tests
    assert "PURGE_ME_SECRET_ALPHA" in tests
    assert 'path.contains("ManagedExports")' in tests
    assert "storedBytes(in: directory)" in tests
    assert 'appendingPathComponent("Recovery"' in tests
    assert 'appendingPathComponent("events-v0.migrated.json")' in tests
    assert "atomicJournalWriter:" in tests
    assert "XCTAssertNotNil(restarted.persistenceFailure)" in tests
