import XCTest
import CryptoKit
@testable import ResearchOSFlightRecorder

@MainActor
final class ResearchArgumentTests: XCTestCase {
    private func makeStore() -> ResearchWorkspaceStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchArgumentTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return ResearchWorkspaceStore(projects: [], storageDirectory: url)
    }
    private func seed(_ store: ResearchWorkspaceStore) throws -> (UUID, UUID, UUID) {
        let project = try XCTUnwrap(store.createProject(title: "My study", question: "What changed in this class?"))
        let source = try store.addArgumentSource(projectID: project, title: "Class notes", origin: "local notes", excerpt: "Twelve students were observed; scores were higher with music. Order was not randomized.", locator: "page 1", population: "12 students in one class", design: .observational)
        let claim = try store.addArgumentClaim(projectID: project, text: "Music improves recall for all students.", sourceIDs: [source])
        return (project, source, claim)
    }
    func testFreshProjectRepairRelaunchDefenseAndDeterministicExportReimport() throws {
        let store = makeStore()
        XCTAssertTrue(store.projects.isEmpty)
        let (project, source, claim) = try seed(store)
        XCTAssertEqual(store.project(id: project)?.argument?.findings.count, 2)
        let proposal = try store.proposeArgumentRepair(projectID: project, claimID: claim, after: "Recall was higher with music in this observed class sample.", reason: "Limit scope and remove unsupported causality.")
        try store.acceptArgumentRepair(projectID: project, proposal: proposal)
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertNil(reopened.persistenceFailure)
        XCTAssertEqual(reopened.project(id: project)?.argument?.claims.first?.version, 2)
        XCTAssertTrue(try XCTUnwrap(reopened.project(id: project)?.argument?.findings).isEmpty)
        let session = try reopened.startArgumentDefense(projectID: project, claimID: claim)
        try reopened.saveArgumentDefense(projectID: project, sessionID: session, answers: ["basis":"The passage describes this class.", "change":"A controlled follow-up with no difference.", "limit":"Nonrandom order may explain the difference."], citedSourceIDs: [source], limitation: "One observational class.")
        let archive = try reopened.exportArchiveData(id: project)
        XCTAssertEqual(archive, try reopened.exportArchiveData(id: project))
        let imported = makeStore()
        XCTAssertEqual(try imported.importArchiveData(archive), project)
        XCTAssertEqual(imported.project(id: project), reopened.project(id: project))
        XCTAssertEqual(try imported.exportArchiveData(id: project), archive)
        let brief = try String(contentsOf: imported.exportResearchBriefFile(id: project), encoding: .utf8)
        XCTAssertTrue(brief.contains("Nonrandom order may explain the difference."))
        XCTAssertTrue(brief.contains(proposal.before))
        XCTAssertTrue(brief.contains(proposal.after))
    }
    func testImpactPreviewDoesNotMutateAndCommitOnlyStalesDependentDefense() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let otherSource = try store.addArgumentSource(projectID: project, title: "Other", origin: "local", excerpt: "A separate observed outcome.")
        let otherClaim = try store.addArgumentClaim(projectID: project, text: "A separate observed outcome.", sourceIDs: [otherSource])
        let dependent = try store.startArgumentDefense(projectID: project, claimID: claim)
        let unrelated = try store.startArgumentDefense(projectID: project, claimID: otherClaim)
        let before = try store.exportArchiveData(id: project)
        let preview = try store.previewEvidenceExclusion(projectID: project, sourceID: source)
        XCTAssertEqual(preview.affectedClaimIDs, [claim])
        XCTAssertEqual(preview.unaffectedClaimIDs, [otherClaim])
        XCTAssertEqual(try store.exportArchiveData(id: project), before)
        try store.setArgumentSourceIncluded(projectID: project, sourceID: source, included: false, reason: "Exclude pending origin review.")
        let argument = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertEqual(argument.sources.first?.version, 2)
        XCTAssertEqual(argument.defenseSessions.first(where: { $0.id == dependent })?.isStale, true)
        XCTAssertEqual(argument.defenseSessions.first(where: { $0.id == unrelated })?.isStale, false)
        XCTAssertEqual(argument.claims.first(where: { $0.id == otherClaim })?.version, 1)
        XCTAssertTrue(argument.findings.contains { $0.ruleID.contains("missing-support") && $0.claimID == claim })
    }
    func testSourceRevisionRejectsStaleProposalAndPreservesExactPriorExcerptInHistory() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let proposal = try store.proposeArgumentRepair(projectID: project, claimID: claim, after: "The observed class had higher scores.", reason: "Narrow scope.")
        try store.reviseArgumentSource(projectID: project, sourceID: source, excerpt: "Revised: measurement error discovered.", reason: "Author correction.")
        let before = try store.exportArchiveData(id: project)
        XCTAssertThrowsError(try store.acceptArgumentRepair(projectID: project, proposal: proposal))
        XCTAssertEqual(before, try store.exportArchiveData(id: project))
        XCTAssertTrue(String(decoding: before, as: UTF8.self).contains("Order was not randomized."))
    }
    func testRepeatedRepairDoesNotDuplicateCommit() throws {
        let store = makeStore()
        let (project, _, claim) = try seed(store)
        let proposal = try store.proposeArgumentRepair(projectID: project, claimID: claim, after: "Scores differed in this class.", reason: "Limit claim.")
        try store.acceptArgumentRepair(projectID: project, proposal: proposal)
        let count = try store.eventHistory(projectID: project).count
        try store.acceptArgumentRepair(projectID: project, proposal: proposal)
        XCTAssertEqual(try store.eventHistory(projectID: project).count, count)
        XCTAssertEqual(store.project(id: project)?.argument?.repairs.count, 1)
    }
    func testRulesAbstainOnNegationAndBoundedClaims() throws {
        let store = makeStore()
        let (project, source, _) = try seed(store)
        let bounded = try store.addArgumentClaim(projectID: project, text: "Scores were higher in this observed class sample.", sourceIDs: [source])
        let negative = try store.addArgumentClaim(projectID: project, text: "This does not prove that music improves recall for all students.", sourceIDs: [source])
        let uncertain = try store.addArgumentClaim(projectID: project, text: "Whether music improves recall for all students remains unclear.", sourceIDs: [source])
        let argument = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertFalse(argument.findings.contains { [bounded, negative, uncertain].contains($0.claimID) })
    }
    func testMissingEvidenceIsDocumentationGapAndContradictionIsExplicit() throws {
        let store = makeStore()
        let (project, source, _) = try seed(store)
        let missing = try store.addArgumentClaim(projectID: project, text: "Some effect is possible.", sourceIDs: [])
        let contradiction = try store.addArgumentClaim(projectID: project, text: "Scores were lower.", sourceIDs: [source], relationship: .contradiction)
        let findings = try XCTUnwrap(store.project(id: project)?.argument?.findings)
        XCTAssertTrue(findings.contains { $0.claimID == missing && $0.explanation.contains("not proof") })
        XCTAssertTrue(findings.contains { $0.claimID == contradiction && $0.ruleID.contains("contradiction-review") })
    }
    func testFrozenEvaluationWordingMissAndControlClaimsOnTheirOwnQuotes() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Frozen wording regression", question: "What does the observational source support?"))
        let source = try store.addArgumentSource(projectID: project, title: "Kross 2013 source fixture",
            origin: "Kross et al. (2013), DOI 10.1371/journal.pone.0069841",
            excerpt: "experiments that manipulate Facebook use in daily life are needed to corroborate these findings and establish definitive causal relations.",
            locator: "PDF page 5", population: "82 sampled people", design: .observational)
        let missed = try store.addArgumentClaim(projectID: project,
            text: "A randomized experiment in this paper definitively established causality.", sourceIDs: [source])
        let controlSource1 = try store.addArgumentSource(projectID: project, title: "Kross EVAL-01 page 2 quote",
            origin: "Kross et al. (2013), DOI 10.1371/journal.pone.0069841",
            excerpt: "Participants were text-messaged 5 times per day between 10am and midnight over 14-days.",
            locator: "PDF page 2", design: .observational)
        let controlSource2 = try store.addArgumentSource(projectID: project, title: "Kross EVAL-03 page 2 quote",
            origin: "Kross et al. (2013), DOI 10.1371/journal.pone.0069841",
            excerpt: "Three participants did not complete the study.", locator: "PDF page 2", design: .observational)
        let control1 = try store.addArgumentClaim(projectID: project,
            text: "Participants received five text messages daily for 14 days.", sourceIDs: [controlSource1])
        let control2 = try store.addArgumentClaim(projectID: project,
            text: "Three participants did not finish the study.", sourceIDs: [controlSource2])
        let caution = try store.addArgumentClaim(projectID: project,
            text: "Experiments are needed to establish causality.", sourceIDs: [source])
        let findings = try XCTUnwrap(store.project(id: project)?.argument?.findings)
        XCTAssertEqual(ResearchArgument.ruleVersion, "research-pro-structural-rules/2")
        XCTAssertTrue(findings.contains { $0.claimID == missed && $0.ruleID.contains("certainty-review") })
        XCTAssertTrue(findings.contains { $0.claimID == missed && $0.ruleID.contains("causal-review") })
        XCTAssertFalse(findings.contains { $0.claimID == control1 || $0.claimID == control2 || $0.claimID == caution })
    }
    func testExportReviewKeepsExcludedSourceStaleDefenseAndAmbiguousPDFUnresolved() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let before = try store.exportArchiveData(id: project)
        let initial = try XCTUnwrap(store.project(id: project)?.argument?.exportReviewItems)
        XCTAssertTrue(initial.contains { $0.message.contains("no recorded defense") })
        XCTAssertTrue(initial.contains { $0.message.contains("observational") })
        XCTAssertEqual(before, try store.exportArchiveData(id: project))
        let session = try store.startArgumentDefense(projectID: project, claimID: claim)
        try store.saveArgumentDefense(projectID: project, sessionID: session,
            answers: ["basis":"One class passage.", "change":"A controlled replication.", "limit":"Nonrandom order."],
            citedSourceIDs: [source], limitation: "One observed class.")
        try store.reviseArgumentSource(projectID: project, sourceID: source,
            excerpt: "Twelve students were observed; a corrected note reports higher scores with music. Order was not randomized.",
            reason: "Correct the source snapshot before export.")
        XCTAssertTrue(try XCTUnwrap(store.project(id: project)?.argument?.exportReviewItems)
            .contains { $0.message.contains("stale after a source or claim change") })
        try store.setArgumentSourceIncluded(projectID: project, sourceID: source, included: false, reason: "Source withdrawn.")
        let items = try XCTUnwrap(store.project(id: project)?.argument?.exportReviewItems)
        XCTAssertTrue(items.contains { $0.message.contains("excluded source") })
        XCTAssertTrue(items.contains { $0.message.contains("stale") })
        XCTAssertTrue(items.contains { $0.message.contains("No included source") })
        let brief = try String(contentsOf: store.exportResearchBriefFile(id: project), encoding: .utf8)
        XCTAssertTrue(brief.contains("## Review before sharing"))
        XCTAssertTrue(brief.contains("excluded source"))

        let manual = try store.addArgumentSource(projectID: project, title: "Unbound PDF note",
            origin: "study.pdf", excerpt: "A manually pasted passage.", locator: "PDF pages 1–6; page markers retained")
        _ = try store.addArgumentClaim(projectID: project, text: "A manually pasted passage.", sourceIDs: [manual])
        XCTAssertTrue(try XCTUnwrap(store.project(id: project)?.argument?.exportReviewItems)
            .contains { $0.message.contains("manual locator that is not bound") })
        let untraceable = try store.addArgumentSource(projectID: project, title: "Untraceable note",
            origin: "", excerpt: "A second manually pasted passage.", locator: "")
        _ = try store.addArgumentClaim(projectID: project, text: "A second manually pasted passage.", sourceIDs: [untraceable])
        XCTAssertTrue(try XCTUnwrap(store.project(id: project)?.argument?.exportReviewItems)
            .contains { $0.message.contains("needs an origin and exact locator") })
    }
    func testExportQuotesUntrustedMarkdownFieldsAndLabelsWithdrawnClaims() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Study\n## False verdict\n<h1>False HTML heading</h1>", question: "What is known?"))
        let source = try store.addArgumentSource(projectID: project, title: "Paper\n## False source verdict",
            origin: "DOI\n## False origin", excerpt: "Observed result.\n# False validation\n<script>alert(1)</script>\n[false link](javascript:alert(1))\nMore source text.",
            locator: "page 1\n## False locator")
        let claim = try store.addArgumentClaim(projectID: project,
            text: "Observed result.\n## False conclusion", sourceIDs: [source])
        try store.reviseArgumentClaim(projectID: project, claimID: claim, links: [], limitation: "Withdrawn pending source check.",
            disposition: .withdrawn, reason: "Do not treat this as a conclusion.")
        let brief = try String(contentsOf: store.exportResearchBriefFile(id: project), encoding: .utf8)
        for heading in ["## False verdict", "## False source verdict", "## False origin", "# False validation", "## False locator", "## False conclusion"] {
            XCTAssertTrue(brief.contains("\n    \(heading)\n"))
            XCTAssertFalse(brief.contains("\n\(heading)\n"))
        }
        for markup in ["<h1>False HTML heading</h1>", "<script>alert(1)</script>", "[false link](javascript:alert(1))"] {
            XCTAssertTrue(brief.contains("\n    \(markup)\n"))
            XCTAssertFalse(brief.contains("\n\(markup)\n"))
        }
        XCTAssertTrue(brief.contains("### WITHDRAWN claim"))
        XCTAssertTrue(brief.contains("must not be presented as a current conclusion"))
    }
    func testEmptyProjectBriefStatesMissingClaimsBeforeSharing() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Empty", question: "What is known?"))
        let brief = try String(contentsOf: store.exportResearchBriefFile(id: project), encoding: .utf8)
        XCTAssertTrue(brief.contains("## Review before sharing"))
        XCTAssertTrue(brief.contains("No argument or claims have been recorded"))
        _ = try store.addArgumentSource(projectID: project, title: "Source without a claim", origin: "local note", excerpt: "An observation.")
        let sourceOnlyBrief = try String(contentsOf: store.exportResearchBriefFile(id: project), encoding: .utf8)
        XCTAssertTrue(sourceOnlyBrief.contains("No claims have been recorded for this brief"))
    }
    func testGeneralProjectEditorCannotRewriteArgumentAuthority() throws {
        let store = makeStore()
        let (project, _, _) = try seed(store)
        let before = try store.exportArchiveData(id: project)
        store.updateProject(id: project) { $0.argument?.claims[0].text = "Forged conclusion" }
        try store.flushPendingChanges()
        XCTAssertEqual(before, try store.exportArchiveData(id: project))
        XCTAssertNotNil(store.mutationAccessFailure)
    }
    func testPremiumDefenseIsSubstantivelyRicherAndExportSurvivesExpiry() throws {
        let store = makeStore()
        let (project, _, claim) = try seed(store)
        let standard = try store.startArgumentDefense(projectID: project, claimID: claim)
        XCTAssertThrowsError(try store.startArgumentDefense(projectID: project, claimID: claim, advanced: true))
        store.updateSubscriptionAccess(.plusActive(expirationDate: nil)) // Labeled application-state fixture, not provider evidence.
        let advanced = try store.startArgumentDefense(projectID: project, claimID: claim, advanced: true)
        let sessions = try XCTUnwrap(store.project(id: project)?.argument?.defenseSessions)
        XCTAssertGreaterThan(try XCTUnwrap(sessions.first { $0.id == advanced }).questions.count, try XCTUnwrap(sessions.first { $0.id == standard }).questions.count)
        store.updateSubscriptionAccess(.free)
        XCTAssertThrowsError(try store.startArgumentDefense(projectID: project, claimID: claim, advanced: true))
        XCTAssertFalse(try store.exportArchiveData(id: project).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.exportResearchBriefFile(id: project).path))
        XCTAssertEqual(store.project(id: project)?.argument?.defenseSessions.count, 2)
    }
    func testStaleDefenseCannotBeSavedAndQuestionsPrecedeAssistance() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let session = try store.startArgumentDefense(projectID: project, claimID: claim)
        XCTAssertEqual(store.project(id: project)?.argument?.defenseSessions.first?.answers, [:])
        try store.setArgumentSourceIncluded(projectID: project, sourceID: source, included: false, reason: "Review required.")
        XCTAssertThrowsError(try store.saveArgumentDefense(projectID: project, sessionID: session, answers: ["basis":"Answer"], citedSourceIDs: [], limitation: "Limited"))
    }
    func testTamperedArchiveRejectedWithoutPartialImport() throws {
        let store = makeStore()
        let (project, _, _) = try seed(store)
        let data = try store.exportArchiveData(id: project)
        let tampered = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "My study", with: "Forged study").utf8)
        let imported = makeStore()
        XCTAssertThrowsError(try imported.importArchiveData(tampered))
        XCTAssertTrue(imported.projects.isEmpty)
        XCTAssertNil(imported.persistenceFailure)
    }
    func testOldProjectMigrationRetainsCanonicalArchiveBytes() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Old project", question: "Old question"))
        XCTAssertNil(store.project(id: project)?.argument)
        let archive = try store.exportArchiveData(id: project)
        XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("\"argument\""))
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertEqual(try reopened.exportArchiveData(id: project), archive)
        _ = try reopened.addArgumentSource(projectID: project, title: "New source", origin: "local", excerpt: "New evidence")
        XCTAssertNotNil(reopened.project(id: project)?.argument)
        XCTAssertEqual(reopened.project(id: project)?.title, "Old project")
    }
    func testSyntheticSampleUsesRealRulesAndNoPremiumBypass() throws {
        let store = makeStore()
        let project = try store.createArgumentSample()
        let argument = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertEqual(argument.sources.count, 2)
        XCTAssertTrue(argument.sources[0].excerpt.contains("quiet 78/120, music 83/120"))
        XCTAssertTrue(argument.sources[0].excerpt.contains("4.17 percentage points"))
        XCTAssertEqual(argument.findings.count, 2)
        XCTAssertThrowsError(try store.startArgumentDefense(projectID: project, claimID: argument.claims[0].id, advanced: true))
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertEqual(reopened.project(id: project)?.argument, argument)
    }
    func testRepeatedDefenseSaveIsIdempotent() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let session = try store.startArgumentDefense(projectID: project, claimID: claim)
        try store.saveArgumentDefense(projectID: project, sessionID: session, answers: ["basis":"Exact answer"], citedSourceIDs: [source], limitation: "One class")
        let before = try store.exportArchiveData(id: project)
        try store.saveArgumentDefense(projectID: project, sessionID: session, answers: ["basis":"Exact answer"], citedSourceIDs: [source], limitation: "One class")
        XCTAssertEqual(try store.exportArchiveData(id: project), before)
    }
    func testHashCorrectCreationCannotInjectArgumentAuthority() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Clean", question: "Question"))
        let original = try XCTUnwrap(store.eventHistory(projectID: project).first)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: CanonicalJSON.encode(original.payload)) as? [String: Any])
        var mutations = try XCTUnwrap(payload["mutations"] as? [[String: Any]])
        var value = try XCTUnwrap(mutations[0]["value"] as? [String: Any])
        var injected = ResearchArgument()
        injected.schemaVersion = 999
        value["argument"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(injected))
        mutations[0]["value"] = value
        payload["mutations"] = mutations
        let draft = try ResearchEventDraft(eventID: original.eventID, projectID: original.projectID, branchID: "main", kind: original.kind, actorRef: "human:local", authorityRef: "role:owner", origin: "ios:local", idempotencyKey: original.idempotencyKey, occurredAt: original.occurredAt, priorProjectDigest: ResearchOSSchema.zeroDigest, resultProjectDigest: CanonicalJSON.digest(CanonicalJSONValue(jsonObject: value)), payload: CanonicalJSONValue(jsonObject: payload), objectRefs: original.objectRefs)
        let attackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchArgumentAttack-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: attackDirectory) }
        let attackStore = try ResearchEventStore(rootDirectory: attackDirectory)
        _ = try attackStore.append(draft)
        XCTAssertTrue(attackStore.audit().valid) // Hash-correct does not mean authorized.
        let target = makeStore()
        XCTAssertThrowsError(try target.importArchiveData(attackStore.exportArchive(projectID: original.projectID)))
        XCTAssertTrue(target.projects.isEmpty)
        XCTAssertNil(target.persistenceFailure)
    }
    func testInterruptedAtomicImportPreservesExistingJournal() throws {
        let source = makeStore()
        let (project, _, _) = try seed(source)
        let archive = try source.exportArchiveData(id: project)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchArgumentAtomic-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let target = try ResearchEventStore(rootDirectory: directory, atomicAppendWriter: { _, _ in throw NSError(domain: "SimulatedInterruptedWrite", code: 1) })
        let before = try Data(contentsOf: target.eventJournalURL)
        XCTAssertThrowsError(try target.importArchive(archive, expectedProjectID: project.uuidString.lowercased()))
        XCTAssertEqual(try Data(contentsOf: target.eventJournalURL), before)
        XCTAssertTrue(target.audit().valid)
        XCTAssertTrue(try target.allEvents().isEmpty)
    }
    func testDeletionPurgesOnlyThisProjectsPrivateFormDrafts() throws {
        let store = makeStore()
        let (project, _, _) = try seed(store)
        let root = try XCTUnwrap(store.storageDirectoryURL).appendingPathComponent("FormDrafts", isDirectory: true)
        let removed = root.appendingPathComponent(project.uuidString.lowercased(), isDirectory: true)
        let retained = root.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        for directory in [removed, retained] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("Private draft".utf8).write(to: directory.appendingPathComponent("source.json"), options: .atomic)
        }
        XCTAssertNotNil(store.deleteProject(id: project))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
    }
    func testExplicitLinkLimitationContestAndWithdrawalPreserveHistory() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let session = try store.startArgumentDefense(projectID: project, claimID: claim)
        let proposal = try store.proposeArgumentRepair(projectID: project, claimID: claim, after: "Scores differed in this class.", reason: "Narrow scope")
        try store.reviseArgumentClaim(projectID: project, claimID: claim, links: [ArgumentEvidenceLink(sourceID: source, relationship: .contradiction)], limitation: "The source contradicts my inference.", disposition: .contested, reason: "Reconsider after rereading the source.")
        let contested = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertEqual(contested.claims.first?.version, 2)
        XCTAssertEqual(contested.claims.first?.effectiveDisposition, .contested)
        XCTAssertTrue(contested.findings.contains { $0.ruleID.contains("contradiction-review") })
        XCTAssertEqual(contested.defenseSessions.first(where: { $0.id == session })?.isStale, true)
        XCTAssertThrowsError(try store.acceptArgumentRepair(projectID: project, proposal: proposal))
        try store.reviseArgumentClaim(projectID: project, claimID: claim, links: [], limitation: "Not enough support", disposition: .withdrawn, reason: "Withdraw this conclusion pending stronger evidence.")
        let withdrawn = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertTrue(withdrawn.findings.isEmpty)
        XCTAssertEqual(withdrawn.claims.count, 1)
        XCTAssertEqual(withdrawn.claims.first?.text, "Music improves recall for all students.")
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertEqual(reopened.project(id: project)?.argument, withdrawn)
        XCTAssertTrue(String(decoding: try reopened.exportArchiveData(id: project), as: UTF8.self).contains("Reconsider after rereading the source."))
    }
    func testStaleSourceAndClaimEditorsCannotOverwriteNewerWork() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        try store.reviseArgumentSource(projectID: project, sourceID: source, excerpt: "New correction", reason: "Version update", expectedVersion: 1)
        XCTAssertThrowsError(try store.reviseArgumentSource(projectID: project, sourceID: source, excerpt: "Stale editor", reason: "Outdated", expectedVersion: 1))
        try store.reviseArgumentClaim(projectID: project, claimID: claim, links: [], limitation: "Current limitation", reason: "New review", expectedVersion: 1)
        XCTAssertThrowsError(try store.reviseArgumentClaim(projectID: project, claimID: claim, links: [], limitation: "Stale limitation", reason: "Outdated", expectedVersion: 1))
        XCTAssertEqual(store.project(id: project)?.argument?.sources.first?.excerpt, "New correction")
        XCTAssertEqual(store.project(id: project)?.argument?.claims.first?.limitation, "Current limitation")
    }
    func testMeasuredMultiSourceRuleAndExportLatency() throws {
        for count in [10, 50] {
            let store = makeStore()
            let project = try XCTUnwrap(store.createProject(title: "Measured \(count) sources", question: "What does this bounded source collection support?"))
            var sourceIDs: [UUID] = []
            for index in 0..<count {
                sourceIDs.append(try store.addArgumentSource(projectID: project, title: "Observed source \(index)", origin: "Authored performance fixture", excerpt: "Observed scores differed in class \(index). Order was not randomized; measurement and selection limitations remain.", locator: "paragraph 1", population: "Class \(index)", design: .observational))
            }
            _ = try store.addArgumentClaim(projectID: project, text: "Music improves recall for all students.", sourceIDs: sourceIDs)
            let argument = try XCTUnwrap(store.project(id: project)?.argument)
            let ruleStart = Date()
            var observed = 0
            for _ in 0..<100 { observed += argument.findings.count }
            let ruleMS = Date().timeIntervalSince(ruleStart) * 1000 / 100
            XCTAssertEqual(observed, 200)
            let exportStart = Date()
            let archive = try store.exportArchiveData(id: project)
            let exportMS = Date().timeIntervalSince(exportStart) * 1000
            XCTAssertFalse(archive.isEmpty)
            print("RESEARCH_PRO_BENCHMARK source_count=\(count) rule_mean_ms=\(ruleMS) export_ms=\(exportMS) archive_bytes=\(archive.count) environment=\(ProcessInfo.processInfo.operatingSystemVersionString) authored_fixture=true")
        }
    }
    func testImportPreservesPendingLocalProjectDraftsAndRejectsOlderSnapshot() throws {
        let local = makeStore()
        let localID = try XCTUnwrap(local.createProject(title: "Local", question: "Question"))
        let older = try local.exportArchiveData(id: localID)
        local.updateProject(id: localID) { $0.scope.population = "Pending local population" }
        XCTAssertThrowsError(try local.importArchiveData(older))
        XCTAssertEqual(local.project(id: localID)?.scope.population, "Pending local population")
        let other = makeStore()
        let otherID = try XCTUnwrap(other.createProject(title: "Imported", question: "Other question"))
        local.updateProject(id: localID) { $0.scope.exclusions = "Preserve this unflushed edit" }
        _ = try local.importArchiveData(other.exportArchiveData(id: otherID))
        XCTAssertEqual(local.project(id: localID)?.scope.exclusions, "Preserve this unflushed edit")
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(local.storageDirectoryURL))
        XCTAssertEqual(reopened.project(id: localID)?.scope.population, "Pending local population")
        XCTAssertEqual(reopened.project(id: localID)?.scope.exclusions, "Preserve this unflushed edit")
        XCTAssertNotNil(reopened.project(id: otherID))
    }
    func testStandardDefenseCanBeRenewedFreeAfterEvidenceChanges() throws {
        let store = makeStore()
        let (project, source, claim) = try seed(store)
        let original = try store.startArgumentDefense(projectID: project, claimID: claim)
        try store.saveArgumentDefense(projectID: project, sessionID: original, answers: ["basis":"Original answer"], citedSourceIDs: [source], limitation: "Original limitation")
        try store.reviseArgumentSource(projectID: project, sourceID: source, excerpt: "Corrected observation", reason: "Source revision")
        let renewed = try store.startArgumentDefense(projectID: project, claimID: claim)
        XCTAssertNotEqual(original, renewed)
        let sessions = try XCTUnwrap(store.project(id: project)?.argument?.defenseSessions)
        XCTAssertEqual(sessions.first?.answers["basis"], "Original answer")
        XCTAssertEqual(sessions.first?.isStale, true)
        XCTAssertEqual(sessions.last?.isStale, false)
        XCTAssertFalse(sessions.last?.advanced ?? true)
    }
    func testArgumentArchiveBudgetRejectsBeforeMutationAndKeepsExportReimportable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchArchiveBudget-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // Same production archive bound with a smaller injected budget, so this
        // regression exercises boundary failure without a 20 MB fixture.
        let budget = 30_000
        let store = ResearchWorkspaceStore(projects: [], storageDirectory: directory, maximumArgumentArchiveBytes: budget)
        let project = try XCTUnwrap(store.createProject(title: "Portable budget", question: "Can every accepted argument change be exported and reimported?"))
        var rejected = false
        for index in 0..<30 {
            let before = try store.exportArchiveData(id: project)
            let sourceCount = store.project(id: project)?.argument?.sources.count ?? 0
            do {
                _ = try store.addArgumentSource(projectID: project, title: "Source \(index)", origin: "Bounded test", excerpt: String(repeating: "a", count: 1_000))
                XCTAssertLessThanOrEqual(try store.exportArchiveData(id: project).count, budget)
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("portable archive limit"))
                XCTAssertEqual(try store.exportArchiveData(id: project), before)
                XCTAssertEqual(store.project(id: project)?.argument?.sources.count ?? 0, sourceCount)
                XCTAssertNil(store.persistenceFailure)
                rejected = true
                break
            }
        }
        XCTAssertTrue(rejected)
        let archive = try store.exportArchiveData(id: project)
        let imported = makeStore()
        _ = try imported.importArchiveData(archive)
        XCTAssertEqual(try imported.exportArchiveData(id: project), archive)
        store.updateSubscriptionAccess(.free)
        XCTAssertFalse(try store.exportArchiveData(id: project).isEmpty)
    }
    func testVerifiedJournalCacheRejectsSameSizeExternalCorruptionAndArchiveRemainsCanonical() throws {
        let workspace = makeStore()
        let (project, _, _) = try seed(workspace)
        let core = try ResearchEventStore(rootDirectory: XCTUnwrap(workspace.storageDirectoryURL))
        let verified = try core.allEvents()
        let archive = try core.exportArchive(projectID: project.uuidString.lowercased())
        let decoded = try JSONDecoder().decode(ResearchEventArchive.self, from: archive)
        XCTAssertEqual(archive, try CanonicalJSON.encode(decoded))
        let original = try Data(contentsOf: core.eventJournalURL)
        let changed = Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "Class notes", with: "False notes").utf8)
        XCTAssertEqual(changed.count, original.count)
        XCTAssertNotEqual(changed, original)
        try changed.write(to: core.eventJournalURL, options: .atomic)
        XCTAssertFalse(core.audit().valid)
        XCTAssertThrowsError(try core.allEvents())
        XCTAssertThrowsError(try core.exportArchive(projectID: project.uuidString.lowercased()))
        try original.write(to: core.eventJournalURL, options: .atomic)
        XCTAssertEqual(try core.allEvents(), verified)
        XCTAssertEqual(try core.exportArchive(projectID: project.uuidString.lowercased()), archive)
    }
    func testOversizedSourcesFailBeforePersistence() throws {
        let store = makeStore()
        let project = try XCTUnwrap(store.createProject(title: "Bounds", question: "Question"))
        let before = try store.exportArchiveData(id: project)
        XCTAssertThrowsError(try store.addArgumentSource(projectID: project, title: "Large", origin: "local", excerpt: String(repeating: "x", count: 100_001)))
        XCTAssertEqual(try store.exportArchiveData(id: project), before)
    }

    // Draft insertion: inside ResearchArgumentTests, reusing its existing makeStore().
    // Add `import CryptoKit` at file scope. No app-source change is required.
    func testLegacyC070ArchiveRoundTripsWithoutRewritingHistory() throws {
        let resources = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        let fixture = resources.appendingPathComponent("Fixtures/LegacyC070/research-archive.json")
        let original = try Data(contentsOf: fixture)
        XCTAssertEqual(original.count, 231_101)
        XCTAssertEqual(SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
                       "f8c4da7c5f31b399ded1789b86b6556a681000adbaad3c675c8c131816ef4e28")
        let store = makeStore()
        let projectID = try store.importArchiveData(original)
        XCTAssertEqual(projectID.uuidString.lowercased(), "02b8d520-8262-4084-a58b-19b1adfb5b32")
        let project = try XCTUnwrap(store.project(id: projectID))
        XCTAssertEqual(project.title, "Kross 2013 source review")
        let argument = try XCTUnwrap(project.argument)
        let claim = try XCTUnwrap(argument.claims.first)
        XCTAssertEqual(claim.id.uuidString, "1C85BB2F-5846-49E5-BCB5-CCB9F044B5AA")
        XCTAssertEqual(claim.version, 2)
        XCTAssertEqual(claim.text, "The study recruited 82 people.")
        let source = try XCTUnwrap(argument.sources.first)
        XCTAssertEqual(source.id.uuidString, "80D4D4B1-1C32-4334-9817-4834A5559309")
        XCTAssertEqual(source.version, 1)
        XCTAssertEqual(source.excerpt, "Eighty-two people")
        XCTAssertEqual(source.selectedPage, 1)
        XCTAssertEqual(source.locator, "PDF page 1 · exact quote (whitespace normalized)")
        XCTAssertEqual(source.document?.originalSHA256,
                       "7ba9667c23217f8f2571181b40884ce2e3d6342613425b6232ad56ebbcfeea8d")
        let history = try store.eventHistory(projectID: projectID)
        XCTAssertEqual(history.count, 6)
        XCTAssertEqual(history.last?.chainDigest, "9bbbd002c1b851e98ceb27f1b89a0ff4d7a99a6c0228a8c090c907204900965b")
        XCTAssertEqual(try store.exportArchiveData(id: projectID), original)

        // Reading the new rule/preflight version and exporting a new brief must
        // not migrate the old archive, mutate saved answers, or append events.
        XCTAssertEqual(ResearchArgument.ruleVersion, "research-pro-structural-rules/2")
        _ = argument.exportReviewItems
        let brief = try String(contentsOf: store.exportResearchBriefFile(id: projectID), encoding: .utf8)
        XCTAssertTrue(brief.contains("## Review before sharing"))
        XCTAssertTrue(brief.contains("Eighty-two people"))
        XCTAssertTrue(brief.contains("7ba9667c23217f8f2571181b40884ce2e3d6342613425b6232ad56ebbcfeea8d"))
        XCTAssertEqual(store.project(id: projectID), project)
        XCTAssertEqual(try store.eventHistory(projectID: projectID), history)
        XCTAssertEqual(try store.exportArchiveData(id: projectID), original)
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertNil(reopened.persistenceFailure)
        XCTAssertEqual(try reopened.exportArchiveData(id: projectID), original)
        let reimported = makeStore()
        XCTAssertEqual(try reimported.importArchiveData(reopened.exportArchiveData(id: projectID)), projectID)
        XCTAssertEqual(try reimported.exportArchiveData(id: projectID), original)
    }

    func testNativeAdversarialBriefPreservesFieldsAndLeavesParserEvidence() throws {
        let store = makeStore()
        // Synthetic adversarial text, not research evidence. Each exported
        // free-text field gets a distinct sentinel, mixed markup and Unicode.
        let fields: [String: String] = [
            "project-title": "TITLE_SENTINEL\n## False title\n<h1>Injected title</h1>",
            "question": "QUESTION_SENTINEL\r\n# False question\r[question](javascript:alert(1))",
            "scope-population": "SCOPE_POPULATION_SENTINEL\n</code></pre><script>bad()</script>\nα = −0.124",
            "scope-variables": "VARIABLES_SENTINEL\n```html\n<img src=x onerror=bad()>\n```",
            "scope-exclusions": "EXCLUSIONS_SENTINEL\n---\n[hidden]: https://example.org/hidden\n[hidden]",
            "method": "METHOD_SENTINEL\n<table><tr><td>bad</td></tr></table>\n日本語 ⽇本語 café E = mc²",
            "source-title": "SOURCE_TITLE_SENTINEL\n## False source\n<strong>Fake verdict</strong>",
            "source-origin": "SOURCE_ORIGIN_SENTINEL\n<https://example.org/origin>\n[origin](file:///private/test)",
            "source-locator": "LOCATOR_SENTINEL\n# False locator\n![fake](https://example.org/image.png)",
            "source-population": "SOURCE_POPULATION_SENTINEL\n<h2>False population</h2>\n[population](https://example.org)",
            "source-excerpt": "EXCERPT_SENTINEL\n\n    # Leading spaces\n\n</code></pre><script>evil()</script>\n\tTAB\nα = −0.124; café; 日本語; ⽇本語; E = mc²\nTail",
            "repair-before": "BEFORE_SENTINEL All students had this observed difference.\n## False prior conclusion",
            "repair-after": "AFTER_SENTINEL All students had an observed difference in the record.\n## False current conclusion\n[claim](javascript:bad())",
            "repair-reason": "REASON_SENTINEL\n</pre><script>bad()</script>\n# False repair",
            "claim-limitation": "CLAIM_LIMIT_SENTINEL\n## False limitation\n<iframe src=https://example.org></iframe>",
            "withdrawn-claim": "WITHDRAWN_SENTINEL\n# False withdrawn conclusion\n[withdrawn](https://example.org)",
            "withdrawn-limitation": "WITHDRAWN_LIMIT_SENTINEL\n> False blockquote\n<span>not HTML</span>",
            "answer-basis": "BASIS_SENTINEL\n# False defense\n<script>bad()</script>",
            "answer-change": "CHANGE_SENTINEL\n![remote](https://example.org/change.png)\n- Fake list",
            "answer-limit": "LIMIT_SENTINEL\n```\n<a href=javascript:bad()>false</a>\n```",
            "defense-limitation": "DEFENSE_LIMIT_SENTINEL\r\n## False limitation\r日本語 ⽇本語"
        ]
        func field(_ key: String) throws -> String { try XCTUnwrap(fields[key]) }
        let projectID = try XCTUnwrap(store.createProject(title: field("project-title"), question: field("question")))
        store.updateProject(id: projectID) { project in
            project.scope.population = fields["scope-population"]!
            project.scope.variables = fields["scope-variables"]!
            project.scope.exclusions = fields["scope-exclusions"]!
            project.protocolRecord.method = fields["method"]!
        }
        try store.flushPendingChanges()
        let sourceID = try store.addArgumentSource(projectID: projectID, title: field("source-title"),
            origin: field("source-origin"), excerpt: field("source-excerpt"), locator: field("source-locator"),
            population: field("source-population"), design: .observational)
        let claimID = try store.addArgumentClaim(projectID: projectID, text: field("repair-before"), sourceIDs: [sourceID])
        let proposal = try store.proposeArgumentRepair(projectID: projectID, claimID: claimID,
            after: field("repair-after"), reason: field("repair-reason"))
        try store.acceptArgumentRepair(projectID: projectID, proposal: proposal)
        try store.reviseArgumentClaim(projectID: projectID, claimID: claimID,
            links: [ArgumentEvidenceLink(sourceID: sourceID, relationship: .support)], limitation: field("claim-limitation"),
            disposition: .contested, reason: "Synthetic QA disposition; no human validation.")
        let sessionID = try store.startArgumentDefense(projectID: projectID, claimID: claimID)
        try store.saveArgumentDefense(projectID: projectID, sessionID: sessionID,
            answers: ["basis": field("answer-basis"), "change": field("answer-change"), "limit": field("answer-limit")],
            citedSourceIDs: [sourceID], limitation: field("defense-limitation"))
        let withdrawnID = try store.addArgumentClaim(projectID: projectID, text: field("withdrawn-claim"), sourceIDs: [sourceID])
        try store.reviseArgumentClaim(projectID: projectID, claimID: withdrawnID, links: [],
            limitation: field("withdrawn-limitation"), disposition: .withdrawn, reason: "Synthetic QA withdrawal.")

        let originalProject = try XCTUnwrap(store.project(id: projectID))
        let archive = try store.exportArchiveData(id: projectID)
        let briefURL = try store.exportResearchBriefFile(id: projectID)
        let briefData = try Data(contentsOf: briefURL)
        let brief = try XCTUnwrap(String(data: briefData, encoding: .utf8))
        XCTAssertTrue(brief.contains("### CONTESTED claim \(claimID) · version 3"))
        XCTAssertTrue(brief.contains("### WITHDRAWN claim \(withdrawnID) · version 2"))
        XCTAssertEqual(try store.exportArchiveData(id: projectID), archive)
        let reimported = makeStore()
        XCTAssertEqual(try reimported.importArchiveData(archive), projectID)
        XCTAssertEqual(reimported.project(id: projectID), originalProject)
        let reimportedArchive = try reimported.exportArchiveData(id: projectID)
        let reimportedBrief = try Data(contentsOf: reimported.exportResearchBriefFile(id: projectID))
        XCTAssertEqual(reimportedArchive, archive)
        XCTAssertEqual(reimportedBrief, briefData)

        // Retained outside makeStore() cleanup. The independent Markdown parser
        // consumes these ACTUAL native outputs, never a reimplemented formatter.
        let evidence = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearchOSExportReviewEvidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try briefData.write(to: evidence.appendingPathComponent("native-adversarial-brief.md"), options: .atomic)
        try archive.write(to: evidence.appendingPathComponent("native-adversarial-archive.json"), options: .atomic)
        var expected = fields
        let argument = try XCTUnwrap(originalProject.argument)
        for (index, item) in argument.exportReviewItems.enumerated() { expected["review-item-\(index)"] = item.message }
        for question in try XCTUnwrap(argument.defenseSessions.first).questions {
            expected["question-\(question.id)"] = question.prompt
        }
        expected["repair-actor"] = try XCTUnwrap(argument.repairs.first).actor
        try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys, .prettyPrinted])
            .write(to: evidence.appendingPathComponent("expected-literal-values.json"), options: .atomic)
        let receipt: [String: Any] = [
            "evidenceKind": "actual native XCTest output from synthetic adversarial inputs",
            "ruleVersion": ResearchArgument.ruleVersion,
            "briefSHA256": SHA256.hash(data: briefData).map { String(format: "%02x", $0) }.joined(),
            "archiveSHA256": SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined(),
            "expectedLiteralFieldCount": expected.count,
            "archiveReimportByteIdentical": reimportedArchive == archive,
            "briefReimportByteIdentical": reimportedBrief == briefData,
            "humanValidation": false,
            "parserExecution": "pending external parser against this actual native brief"
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
            .write(to: evidence.appendingPathComponent("native-export-receipt.json"), options: .atomic)
        print("RESEARCH_OS_EXPORT_REVIEW_EVIDENCE_DIRECTORY=\(evidence.path)")
    }

    func testExportReviewRetainsContestedIncompleteAndAllSixItems() throws {
        let store = makeStore()
        let projectID = try XCTUnwrap(store.createProject(title: "Six-item preflight QA", question: "What remains to review?"))
        let sourceID = try store.addArgumentSource(projectID: projectID, title: "Unbound note", origin: "",
            excerpt: "The recorded values differed.", locator: "")
        let contestedID = try store.addArgumentClaim(projectID: projectID, text: "The recorded values differed.", sourceIDs: [sourceID])
        try store.reviseArgumentClaim(projectID: projectID, claimID: contestedID,
            links: [ArgumentEvidenceLink(sourceID: sourceID, relationship: .support)], limitation: "Source trace not complete.",
            disposition: .contested, reason: "Record unresolved interpretation.")
        let sessionID = try store.startArgumentDefense(projectID: projectID, claimID: contestedID)
        try store.saveArgumentDefense(projectID: projectID, sessionID: sessionID,
            answers: ["basis": "Only this answer has been recorded."], citedSourceIDs: [sourceID], limitation: "")
        let missingID = try store.addArgumentClaim(projectID: projectID, text: "A separate outcome was recorded.", sourceIDs: [])
        let before = try store.exportArchiveData(id: projectID)
        let argument = try XCTUnwrap(store.project(id: projectID)?.argument)
        let session = try XCTUnwrap(argument.defenseSessions.first)
        XCTAssertFalse(session.isStale)
        XCTAssertEqual(session.completedChecks, 1)
        let items = argument.exportReviewItems
        let expectedIDs: Set<String> = [
            "\(contestedID)-contested", "\(contestedID)-source-\(sourceID)-trace",
            "\(contestedID)-source-\(sourceID)-unbound", "\(contestedID)-defense-review",
            "\(missingID)-v1-missing-support", "\(missingID)-no-defense"
        ]
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(Set(items.map(\.id)), expectedIDs)
        let defenseReview = try XCTUnwrap(items.first { $0.id == "\(contestedID)-defense-review" })
        XCTAssertTrue(defenseReview.message.contains("incomplete"))
        XCTAssertFalse(defenseReview.message.contains("stale"))
        let brief = try String(contentsOf: store.exportResearchBriefFile(id: projectID), encoding: .utf8)
        let reviewSection = try XCTUnwrap(brief.components(separatedBy: "## Review before sharing").last?
            .components(separatedBy: "## Claims").first)
        XCTAssertTrue(reviewSection.contains("Review items: 6"))
        XCTAssertEqual(reviewSection.components(separatedBy: "\nReview item:\n").count - 1, 6)
        for item in items { XCTAssertTrue(reviewSection.contains(item.message), item.id) }
        XCTAssertEqual(try store.exportArchiveData(id: projectID), before)
    }
}
