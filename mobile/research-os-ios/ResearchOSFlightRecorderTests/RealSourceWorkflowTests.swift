import XCTest
import PDFKit
import CryptoKit
import UIKit
@testable import ResearchOSFlightRecorder

/// Real published input; injected claims and provisional AI annotations are QA fixtures.
/// Native service execution is not a picker interaction, human pilot, or scientific validation.
@MainActor
final class RealSourceWorkflowTests: XCTestCase {
    private let originalDigest = "7ba9667c23217f8f2571181b40884ce2e3d6342613425b6232ad56ebbcfeea8d"
    private let citation = "Kross et al. (2013), PLOS ONE 8(8):e69841. doi:10.1371/journal.pone.0069841. CC Attribution."

    private struct Freeze: Decodable {
        let files: [File]
        struct File: Decodable { let path: String; let sha256: String }
    }
    private struct FrozenSet: Decodable {
        let split: String
        let source: Source
        let records: [Record]
        struct Source: Decodable { let id: String; let version: String }
        struct Record: Decodable {
            let id: String; let kind: String; let claim: String
            let source_id: String; let source_version: String
            let locator: Locator; let expected_structural: Expected
            let provisional_semantic_expectation: String
            struct Locator: Decodable { let page: Int?; let quote: String }
            struct Expected: Decodable { let source_exists: Bool; let version_current: Bool; let locator: String }
        }
    }
    private func resource(_ name: String) throws -> URL {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        let url = root.appendingPathComponent("Fixtures/RealSource/" + name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing bundled frozen fixture: \(name)")
        return url
    }
    private func temporaryDirectory(_ label: String, preserve: Bool = false) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RealSource-\(label)-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if !preserve { addTeardownBlock { try? FileManager.default.removeItem(at: url) } }
        return url
    }
    private func workspace() throws -> ResearchWorkspaceStore {
        ResearchWorkspaceStore(projects: [], storageDirectory: try temporaryDirectory("workspace"))
    }
    private func writeJSON(_ value: [String: Any], name: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
        print("RESEARCH_OS_REAL_SOURCE_EVIDENCE=\(url.path)")
        return url
    }
    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func addSource(_ store: ResearchWorkspaceStore, project: UUID, imported: ImportedResearchContent,
                           quote: String, page: Int) throws -> UUID {
        try store.addArgumentSource(projectID: project, title: "Facebook use and well-being (Kross et al., 2013)",
            origin: citation, excerpt: quote, locator: "PDF page \(page) · exact quote (whitespace normalized)",
            population: "82 people recruited around Ann Arbor; sampled young adults", design: .observational,
            document: imported.document, selectedPage: page)
    }

    func testUntrustedExtremePageBoundsCannotOverflow() throws {
        let imported = try ResearchContentImport.read(resource("kross2013.pdf"))
        for page in [Int.min, -1, 0, 7, Int.max] {
            XCTAssertFalse(imported.document.contains(quote: "Eighty-two people", page: page))
        }
    }

    func testNativePDFKitRunsAllFrozenLocatorCasesAndRecordsHeuristicMisses() throws {
        let imported = try ResearchContentImport.read(resource("kross2013.pdf"))
        XCTAssertEqual(imported.document.originalSHA256, originalDigest)
        XCTAssertEqual(imported.document.pages.count, 6)
        XCTAssertTrue(imported.document.isPDF)
        try imported.document.validate()
        let freeze = try JSONDecoder().decode(Freeze.self, from: Data(contentsOf: resource("FREEZE.json")))
        let out = try temporaryDirectory("frozen-evaluation", preserve: true)
        var records: [[String: Any]] = []
        var semanticMisses: [String] = [], semanticFalseAlarms: [String] = [], evaluatedIDs: [String] = []
        for name in ["development.json", "evaluation.json"] {
            let data = try Data(contentsOf: resource(name))
            XCTAssertEqual(digest(data), try XCTUnwrap(freeze.files.first { $0.path == "fixtures/" + name }).sha256, "Frozen fixture bytes changed")
            let set = try JSONDecoder().decode(FrozenSet.self, from: data)
            for row in set.records {
                let store = try workspace()
                let project = try XCTUnwrap(store.createProject(title: "Frozen \(row.id)", question: "Where is the exact evidence?"))
                let sourceExists = row.source_id == set.source.id
                XCTAssertEqual(sourceExists, row.expected_structural.source_exists, row.id)
                XCTAssertEqual(row.source_version == set.source.version, row.expected_structural.version_current, row.id)
                let page = row.locator.page
                let actualLocator: String
                if !sourceExists { actualLocator = "SOURCE_MISSING" }
                else if page == nil { actualLocator = "MISSING_PAGE" }
                else if !(1...imported.document.pages.count).contains(page!) { actualLocator = "PAGE_OUT_OF_RANGE" }
                else if row.locator.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { actualLocator = "EMPTY_QUOTE" }
                else { actualLocator = imported.document.contains(quote: row.locator.quote, page: page!) ? "EXACT_QUOTE_AT_PAGE" : "QUOTE_NOT_AT_PAGE" }
                XCTAssertEqual(actualLocator, row.expected_structural.locator, row.id)
                let before = try store.exportArchiveData(id: project)
                var serviceAccepted = false, serviceError = "", versionInvalidation = "NOT_APPLICABLE"
                if !sourceExists {
                    XCTAssertThrowsError(try store.addArgumentClaim(projectID: project, text: row.claim, sourceIDs: [UUID()]))
                    XCTAssertEqual(try store.exportArchiveData(id: project), before, row.id)
                    serviceError = "Unknown source link rejected without journal mutation"
                } else {
                    do {
                        let source = try store.addArgumentSource(projectID: project, title: "Frozen \(row.id)", origin: citation,
                            excerpt: row.locator.quote, locator: "PDF page \(page ?? 0) · exact quote (whitespace normalized)",
                            population: "82 sampled people", design: .observational, document: imported.document, selectedPage: page)
                        serviceAccepted = true
                        if row.source_version != set.source.version {
                            let claim = try store.addArgumentClaim(projectID: project, text: row.claim, sourceIDs: [source])
                            let pending = try store.proposeArgumentRepair(projectID: project, claimID: claim,
                                after: "The source describes 82 recruited people.", reason: "Injected version precondition test.")
                            let defense = try store.startArgumentDefense(projectID: project, claimID: claim)
                            try store.reviseArgumentSource(projectID: project, sourceID: source,
                                excerpt: row.locator.quote + "\nLOCAL QA VERSION CHANGE - not a publisher correction.", reason: "Injected source revision fixture.")
                            XCTAssertThrowsError(try store.acceptArgumentRepair(projectID: project, proposal: pending))
                            XCTAssertEqual(store.project(id: project)?.argument?.defenseSessions.first(where: { $0.id == defense })?.isStale, true)
                            versionInvalidation = "STALE_REPAIR_REJECTED_AND_DEFENSE_MARKED_STALE"
                        }
                    } catch { serviceError = error.localizedDescription }
                    XCTAssertEqual(serviceAccepted, row.expected_structural.locator == "EXACT_QUOTE_AT_PAGE", row.id + ": " + serviceError)
                    if serviceAccepted { XCTAssertTrue(serviceError.isEmpty, row.id + ": " + serviceError) }
                    else { XCTAssertEqual(try store.exportArchiveData(id: project), before, row.id) }
                }
                // Run the product wording rules independently of locator gate acceptance.
                // These rules never become the semantic gold labels or decide scientific truth.
                let sourceID = UUID(), claimID = UUID()
                var argument = ResearchArgument()
                argument.sources = [ArgumentSource(id: sourceID, title: "Kross et al.", origin: citation,
                    excerpt: row.locator.quote.isEmpty ? "Incomplete injected evidence" : row.locator.quote,
                    locator: "Fixture semantic assessment only", population: "82 sampled people", design: .observational)]
                argument.claims = [ArgumentClaim(id: claimID, text: row.claim, limitation: "AI-drafted QA annotation; human review pending.",
                    links: sourceExists ? [ArgumentEvidenceLink(sourceID: sourceID, relationship: .support)] : [])]
                let rules = argument.findings.map(\.ruleID).sorted()
                let semanticRules = rules.filter { $0.contains("causal-review") || $0.contains("scope-review") || $0.contains("certainty-review") }
                let expected = row.provisional_semantic_expectation
                var comparison = "NOT_SCORED_ANNOTATION_UNRESOLVED"
                if expected == "SUPPORTED_BY_CITED_TEXT" {
                    evaluatedIDs.append(row.id)
                    comparison = semanticRules.isEmpty ? "NO_WORDING_FALSE_ALARM" : "WORDING_FALSE_ALARM"
                    if !semanticRules.isEmpty { semanticFalseAlarms.append(row.id) }
                } else if expected.hasPrefix("UNSUPPORTED_") {
                    evaluatedIDs.append(row.id)
                    let relevant = expected.contains("CAUSAL") ? semanticRules.contains { $0.contains("causal-review") || $0.contains("certainty-review") } : semanticRules.contains { $0.contains("scope-review") }
                    comparison = relevant ? "WORDING_REVIEW_TRIGGERED" : "WORDING_RULE_MISS"
                    if !relevant { semanticMisses.append(row.id) }
                }
                records.append(["id": row.id, "split": set.split, "kind": row.kind,
                    "fixture_file_sha256": digest(data), "expected_locator": row.expected_structural.locator,
                    "actual_native_locator": actualLocator, "locator_pass": actualLocator == row.expected_structural.locator,
                    "native_source_service_accepted": serviceAccepted, "native_service_error": serviceError,
                    "expected_version_current": row.expected_structural.version_current, "version_invalidation_observed": versionInvalidation,
                    "provisional_semantic_expectation": expected, "actual_wording_rule_ids": rules,
                    "provisional_comparison": comparison, "annotation_status": "AI_DRAFTED_PROVISIONAL_NOT_HUMAN_VALIDATED"])
            }
        }
        XCTAssertEqual(records.count, 14)
        _ = try writeJSON(["schema_version": 1, "scope": "Native PDFKit extraction, source validation and bounded wording rules; no picker or human participant.",
            "pdf_sha256": originalDigest, "rule_version": ResearchArgument.ruleVersion,
            "records": records, "semantics_evaluated_ids": evaluatedIDs, "wording_rule_misses": semanticMisses,
            "wording_false_alarms": semanticFalseAlarms, "exclusions": ["AUTHOR_REVIEW_REQUIRED annotations are not semantically scored"],
            "human_pilot": "HUMAN_PILOT_PENDING", "publication_readiness": "NOT_ASSESSED"], name: "frozen-native-outcomes.json", directory: out)
    }

    func testRealSourceRepairDefenseRevisionRelaunchExportAndReimportPreserveLineage() throws {
        let imported = try ResearchContentImport.read(resource("kross2013.pdf"))
        let store = try workspace()
        let project = try XCTUnwrap(store.createProject(title: "Facebook use - real source QA", question: "Does this observational study establish causality?"))
        let quote = "experiments\nthat manipulate Facebook use in daily life are needed to\ncorroborate these findings and establish definitive causal relations."
        let source = try addSource(store, project: project, imported: imported, quote: quote, page: 5)
        let unrelatedSource = try addSource(store, project: project, imported: imported, quote: "Three participants did not complete the study.", page: 2)
        let originalClaim = "This observational study proves that Facebook causes worse well-being."
        let claim = try store.addArgumentClaim(projectID: project, text: originalClaim, sourceIDs: [source])
        let unrelated = try store.addArgumentClaim(projectID: project, text: "Three participants did not finish the study.", sourceIDs: [unrelatedSource])
        let beforeProposal = try store.exportArchiveData(id: project)
        let proposal = try store.proposeArgumentRepair(projectID: project, claimID: claim,
            after: "The study reports associations over time; experiments are needed to establish definitive causal relations.",
            reason: "Scripted QA acceptance: retain observational scope and the authors' causal limitation.")
        XCTAssertEqual(try store.exportArchiveData(id: project), beforeProposal, "Preview must not commit a repair.")
        try store.acceptArgumentRepair(projectID: project, proposal: proposal)
        let dependentDefense = try store.startArgumentDefense(projectID: project, claimID: claim)
        let otherDefense = try store.startArgumentDefense(projectID: project, claimID: unrelated)
        let answers = ["basis": "Page 5 explicitly asks for experiments. " + citation,
                       "change": "A credible randomized manipulation would alter the causal assessment.",
                       "limit": "This study's observational associations do not establish definitive causality."]
        try store.saveArgumentDefense(projectID: project, sessionID: dependentDefense, answers: answers,
                                      citedSourceIDs: [source], limitation: "Sampled young adults; observational design.")
        let preRevision = try store.exportArchiveData(id: project)
        let preRevisionHistory = try store.eventHistory(projectID: project)
        // Recover the original source by its identity before mutation, then prove
        // this exact event prefix survives the later revision and reimport.
        // A digest substring alone could come from the unrelated second source.
        let priorRecovery = try workspace()
        XCTAssertEqual(try priorRecovery.importArchiveData(preRevision), project)
        XCTAssertEqual(priorRecovery.project(id: project)?.argument?.sources.first(where: { $0.id == source })?.document, imported.document)
        let preview = try store.previewEvidenceExclusion(projectID: project, sourceID: source)
        XCTAssertEqual(preview.affectedClaimIDs, [claim]); XCTAssertEqual(preview.unaffectedClaimIDs, [unrelated])
        XCTAssertEqual(try store.exportArchiveData(id: project), preRevision)
        let oldBasis = try XCTUnwrap(store.project(id: project)?.argument).basisDigest(claimID: claim)
        try store.reviseArgumentSource(projectID: project, sourceID: source,
            excerpt: quote + "\nLOCAL QA NOTE: re-review this imported passage. Not a publisher correction.",
            reason: "Injected local source-version change for dependency verification.", expectedVersion: 1)
        let changed = try XCTUnwrap(store.project(id: project)?.argument)
        XCTAssertNotEqual(try changed.basisDigest(claimID: claim), oldBasis)
        XCTAssertEqual(changed.defenseSessions.first(where: { $0.id == dependentDefense })?.isStale, true)
        XCTAssertEqual(changed.defenseSessions.first(where: { $0.id == otherDefense })?.isStale, false)
        XCTAssertEqual(changed.claims.first(where: { $0.id == unrelated })?.version, 1)
        let revisedSource = try XCTUnwrap(changed.sources.first { $0.id == source })
        XCTAssertEqual(revisedSource.version, 2); XCTAssertNil(revisedSource.document); XCTAssertNil(revisedSource.selectedPage)
        XCTAssertEqual(revisedSource.locator, "Author-edited snapshot; prior import retained in history")
        XCTAssertEqual(changed.repairs.first?.proposal.before, originalClaim)
        XCTAssertEqual(changed.sources.first(where: { $0.id == unrelatedSource })?.document, imported.document)
        let reopened = ResearchWorkspaceStore(projects: [], storageDirectory: try XCTUnwrap(store.storageDirectoryURL))
        XCTAssertNil(reopened.persistenceFailure)
        XCTAssertEqual(reopened.project(id: project), store.project(id: project))
        let archive = try reopened.exportArchiveData(id: project)
        XCTAssertEqual(archive, try reopened.exportArchiveData(id: project))
        let archiveText = String(decoding: archive, as: UTF8.self)
        XCTAssertTrue(archiveText.contains(originalDigest)); XCTAssertTrue(archiveText.contains(originalClaim))
        let target = try workspace()
        XCTAssertEqual(try target.importArchiveData(archive), project)
        XCTAssertEqual(target.project(id: project), reopened.project(id: project))
        let recoveredHistory = try target.eventHistory(projectID: project)
        XCTAssertEqual(recoveredHistory, try reopened.eventHistory(projectID: project))
        XCTAssertGreaterThan(recoveredHistory.count, preRevisionHistory.count)
        XCTAssertEqual(Array(recoveredHistory.prefix(preRevisionHistory.count)), preRevisionHistory, "Exact pre-revision journal, including this source document, must survive unchanged.")
        XCTAssertEqual(try target.exportArchiveData(id: project), archive)
        let briefURL = try target.exportResearchBriefFile(id: project)
        let brief = try String(contentsOf: briefURL, encoding: .utf8)
        XCTAssertTrue(brief.contains(originalClaim)); XCTAssertTrue(brief.contains(proposal.after))
        XCTAssertTrue(brief.contains(originalDigest)); XCTAssertTrue(brief.contains("Stale: true"))
        XCTAssertTrue(brief.contains("Sampled young adults; observational design."))
        let output = try temporaryDirectory("journey-evidence", preserve: true)
        let archiveURL = output.appendingPathComponent("real-source-event-archive.json")
        let finalBriefURL = output.appendingPathComponent("real-source-brief.md")
        try archive.write(to: archiveURL, options: .atomic)
        try Data(contentsOf: briefURL).write(to: finalBriefURL, options: .atomic)
        try preRevision.write(to: output.appendingPathComponent("before-source-revision-event-archive.json"), options: .atomic)
        _ = try writeJSON(["scope": "Scripted native service journey; actual picker/share UI and human approval not exercised by this test.",
            "pdf_sha256": originalDigest, "archive_sha256": digest(archive), "brief_sha256": digest(Data(brief.utf8)),
            "project_id": project.uuidString, "event_count": try target.eventHistory(projectID: project).count,
            "source_revision": 2, "reimport_preserved_journal": true, "relaunch_preserved_project": true,
            "dependent_defense_stale": true, "unrelated_defense_stale": false,
            "accepted_repair_original_retained": true, "durable_document_snapshot_retained_in_journal": true,
            "archive_path": archiveURL.path, "brief_path": finalBriefURL.path,
            "human_pilot": "HUMAN_PILOT_PENDING"], name: "journey-receipt.json", directory: output)
        print("RESEARCH_OS_REAL_SOURCE_EVIDENCE_DIRECTORY=\(output.path)")
    }

    func testUnicodeWhitespacePreservesCharactersAndRejectsChangedNumbersCaseAndPunctuation() throws {
        let text = "Provisional synthetic Unicode parser control only.\nβ = −0.124; café; 東京; Δ = 2.\nSecond\tline\u{00a0}continues."
        let directory = try temporaryDirectory("unicode")
        let file = directory.appendingPathComponent("unicode.md")
        try Data(text.utf8).write(to: file)
        let imported = try ResearchContentImport.read(file)
        XCTAssertEqual(imported.excerpt, text)
        XCTAssertTrue(imported.document.contains(quote: "Second line continues.", page: 1))
        XCTAssertTrue(imported.document.contains(quote: "β = −0.124; café; 東京; Δ = 2.", page: 1))
        XCTAssertFalse(imported.document.contains(quote: "β = −0.125;", page: 1))
        XCTAssertFalse(imported.document.contains(quote: "Café", page: 1))
        XCTAssertFalse(imported.document.contains(quote: "Δ = 2!", page: 1))
        XCTAssertFalse(imported.document.contains(quote: "   ", page: 1))
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(imported.document.contains(quote: "東京", page: 1), "Snapshot must retain local text after picker URL is unavailable.")
    }

    func testEncryptedPDFAndBytePageBoundsFailVisiblyWithoutPartialProjectMutation() throws {
        let directory = try temporaryDirectory("failure-inputs")
        let original = try XCTUnwrap(PDFDocument(url: resource("kross2013.pdf")))
        let encryptionOptions: [PDFDocumentWriteOption: Any] = [.userPasswordOption: "fixture-user", .ownerPasswordOption: "fixture-owner"]
        let encrypted = try XCTUnwrap(original.dataRepresentation(options: encryptionOptions))
        let encryptedURL = directory.appendingPathComponent("encrypted.pdf")
        try encrypted.write(to: encryptedURL)
        XCTAssertEqual(PDFDocument(url: encryptedURL)?.isLocked, true, "Fixture must actually be encrypted.")
        let overByteURL = directory.appendingPathComponent("over-byte-limit.txt")
        try Data(repeating: 65, count: ResearchContentImport.maximumBytes + 1).write(to: overByteURL)
        let manyPages = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            for _ in 0..<201 { context.beginPage() }
        }
        let manyPagesURL = directory.appendingPathComponent("over-page-limit.pdf")
        try manyPages.write(to: manyPagesURL)
        let store = try workspace()
        let project = try XCTUnwrap(store.createProject(title: "Failure recovery", question: "Does failed intake preserve work?"))
        let before = try store.exportArchiveData(id: project)
        for (url, expected) in [(encryptedURL, "read"), (overByteURL, "limit"), (manyPagesURL, "200 pages")] {
            XCTAssertThrowsError(try ResearchContentImport.read(url)) { error in
                XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains(expected), error.localizedDescription)
            }
            XCTAssertEqual(try store.exportArchiveData(id: project), before)
        }
        // Recovery uses the real PDF after the rejected inputs.
        let recovered = try ResearchContentImport.read(resource("kross2013.pdf"))
        _ = try addSource(store, project: project, imported: recovered, quote: "Eighty-two people", page: 1)
        XCTAssertEqual(store.project(id: project)?.argument?.sources.count, 1)
        XCTAssertNil(store.persistenceFailure)
    }
}
