import XCTest
import PDFKit
import UIKit
import CoreText
@testable import ResearchOSFlightRecorder

@MainActor final class PublicationEngineTests: XCTestCase {
    private var plos: PublicationProfile { PublicationProfile.registry.first { $0.id == "plos-one-research" }! }
    private var iclr: PublicationProfile { PublicationProfile.registry.first { $0.id == "iclr-2027-initial" }! }
    private func fixture() -> PublicationManuscript {
        var m = PublicationManuscript(id: UUID(uuidString: "1E000000-0000-0000-0000-000000000001")!, title: "Frozen control: α = 0.05")
        m.shortTitle = "Frozen control"
        m.abstract = "A frozen engineering fixture. Results remain provisional, with 42 observations and no human validation."
        m.authors = [.init(id: "a1", name: "Private Author Name", affiliationIDs: ["af1", "af2"])]
        m.affiliations = [.init(id: "af1", label: "First institute"), .init(id: "af2", label: "Second institute")]
        m.references = [.init(id: "refA", title: "Control result", authors: ["Jane Doe"], year: 2024), .init(id: "refB", title: "Second result", authors: ["Sam Lee"], year: 2025)]
        m.sections = [.init(id: "sec1", role: .introduction, heading: "Introduction", blocks: [
            .init(id: "p1", text: "Independent oracle: 42 observations; β = −1.25; café; 日本語.", citationIDs: ["refB"], evidenceLinks: [.init(sourceID: "study-source", sourceVersion: "version-1", evidenceID: "ev1", locator: "Page 2, paragraph 3", url: "https://example.org/study")]),
            .init(id: "eq1", kind: .equation, text: "E = mc²; \\alpha + \\beta = 42", citationIDs: ["refA"]),
            .init(id: "p2", text: "Repeated reference without altered content.", citationIDs: ["refB"], crossReferenceIDs: ["eq1"])
        ])]
        m.appendices = [.init(id: "app1", role: .appendix, heading: "Frozen appendix", blocks: [.init(id: "ap1", text: "APPENDIX-END-92817")])]
        return m
    }
    func testCSLHasIndependentNumericCitationOracle() throws {
        let result = try PublicationRenderer.render(fixture(), profile: plos)
        XCTAssertTrue(result.html.contains("[1]")); XCTAssertTrue(result.html.contains("[2]"))
        XCTAssertTrue(result.html.contains("1.  Sam Lee. Second result. 2025."))
        XCTAssertTrue(result.html.contains("2.  Jane Doe. Control result. 2024."))
        XCTAssertTrue(result.html.contains("href=\"#ref-refB\""))
        XCTAssertEqual(result.receipt.assetSHA256.count, 3)
    }
    func testSwitchABAPreservesCanonicalAndEntireNormalizedPDF() throws {
        let manuscript = fixture(), before = try manuscript.canonicalData()
        let a1 = try PublicationRenderer.render(manuscript, profile: plos)
        let b = try PublicationRenderer.render(manuscript, profile: iclr)
        let a2 = try PublicationRenderer.render(manuscript, profile: plos)
        XCTAssertEqual(a1.canonical, before); XCTAssertEqual(b.canonical, before); XCTAssertEqual(a2.canonical, before)
        XCTAssertEqual(a1.html, a2.html)
        XCTAssertEqual(try PublicationRenderer.normalizedPDF(a1.pdf), try PublicationRenderer.normalizedPDF(a2.pdf))
        XCTAssertEqual(a1.receipt.normalizedPDFSHA256, a2.receipt.normalizedPDFSHA256)
        XCTAssertNotEqual(a1.html, b.html)
        let decoded = try JSONDecoder().decode(PublicationManuscript.self, from: a2.canonical)
        XCTAssertEqual(decoded.sections[0].blocks[1].text, "E = mc²; \\alpha + \\beta = 42")
        XCTAssertEqual(decoded.sections[0].blocks[0].evidenceLinks[0].sourceVersion, "version-1")
        XCTAssertEqual(decoded.sections[0].blocks[2].citationIDs, ["refB"])
    }
    func testAnonymousViewPreservesCanonicalAuthors() throws {
        let m = fixture(), result = try PublicationRenderer.render(m, profile: iclr)
        XCTAssertFalse(result.html.contains("Private Author Name"))
        XCTAssertTrue(String(decoding: result.canonical, as: UTF8.self).contains("Private Author Name"))
        XCTAssertTrue(result.preflight.unresolved.contains { $0.id.hasPrefix("anonymity:") })
    }
    func testLimitsReportExactOverage() throws {
        var m = fixture(); m.title = String(repeating: "é", count: 257); m.abstract = Array(repeating: "token", count: 307).joined(separator: " ")
        let report = try PublicationEngine.preflight(m, profile: plos)
        let title = try XCTUnwrap(report.checks.first { $0.id == "limits:title" })
        let abstract = try XCTUnwrap(report.checks.first { $0.id == "limits:abstract" })
        XCTAssertEqual(title.handling, .lockedSubstantiveEdit); XCTAssertTrue(title.currentValue.contains("overage 7"))
        XCTAssertEqual(abstract.handling, .lockedSubstantiveEdit); XCTAssertTrue(abstract.currentValue.contains("overage 7"))
        XCTAssertEqual(m.title?.count, 257); XCTAssertEqual(PublicationEngine.words(m.abstract!), 307)
    }
    func testMissingFieldsStayExplicit() throws {
        var m = PublicationManuscript(); m.unknownFields = ["funding"]
        let report = try PublicationEngine.preflight(m, profile: plos)
        XCTAssertTrue(report.checks.contains { $0.location == "title" && $0.outcome == .fail })
        XCTAssertTrue(report.checks.contains { $0.location == "funding" && $0.outcome == .unknown })
        XCTAssertTrue(report.previewAllowed); XCTAssertFalse(report.unresolved.isEmpty)
        let output = try PublicationRenderer.render(m, profile: plos)
        XCTAssertTrue(output.html.contains("[Missing title]")); XCTAssertNil(m.title)
        XCTAssertFalse(output.html.contains("The authors declare no competing interests"))
    }
    func testBothVenueProfilesRemainPartialPreviews() throws {
        for profile in [plos, iclr] {
            let report = try PublicationEngine.preflight(fixture(), profile: profile)
            XCTAssertTrue(report.checks.contains { $0.id == "submission-format:outputs" && $0.outcome == .fail })
            XCTAssertTrue(report.summary.contains("preview only"))
            XCTAssertTrue(profile.rules.allSatisfy { !$0.sourceURL.isEmpty && !$0.failureBehavior.isEmpty && !$0.tests.isEmpty })
        }
    }
    func testProfileTamperingAndUnknownVersionRejected() throws {
        let encoder = JSONEncoder(), data = try encoder.encode(plos)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = "2099-unknown"
        let changed = try JSONDecoder().decode(PublicationProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try PublicationEngine.preflight(fixture(), profile: changed))
        json["version"] = plos.version; json["fontPoints"] = -100
        let malformed = try JSONDecoder().decode(PublicationProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try malformed.validate())
        var m = fixture(); m.schemaVersion = 99; XCTAssertThrowsError(try m.validate())
    }
    func testUnknownCitationFails() throws {
        var m = fixture(); m.sections[0].blocks[0].citationIDs = ["unknown"]
        XCTAssertThrowsError(try PublicationRenderer.render(m, profile: plos))
    }
    func testUnsafeIDAndDuplicateIDsFailWithoutInjection() throws {
        var m = fixture(); m.references[0].id = "\"><script>alert(1)</script>"
        XCTAssertThrowsError(try m.validate())
        m = fixture(); m.sections[0].blocks[0].id = m.references[0].id
        XCTAssertThrowsError(try m.validate())
    }
    func testUntrustedContentIsEscapedWithoutExecution() throws {
        var m = fixture(); let attack = "<script>fetch('https://invalid.test')</script> & <img src=file:///private>"
        m.sections[0].blocks[0].text = attack
        m.references[0].url = "javascript:alert('x')"
        let result = try PublicationRenderer.render(m, profile: plos)
        XCTAssertTrue(result.html.contains("&lt;script&gt;fetch")); XCTAssertFalse(result.html.contains("<script>"))
        XCTAssertFalse(result.html.contains("href=\"javascript:")); XCTAssertFalse(result.html.contains("src=\"file:"))
        XCTAssertTrue(result.html.contains("default-src 'none'"))
        XCTAssertEqual(try JSONDecoder().decode(PublicationManuscript.self, from: result.canonical).sections[0].blocks[0].text, attack)
    }
    func testMissingImageBlockedRatherThanSubstituted() throws {
        var m = fixture(); m.sections[0].blocks.append(.init(id: "fig1", kind: .figure, text: "Image evidence", figure: .init(mediaType: "image/png", data: nil, sha256: nil, altText: nil)))
        let report = try PublicationEngine.preflight(m, profile: plos)
        XCTAssertFalse(report.previewAllowed)
        XCTAssertTrue(report.checks.contains { $0.location == "fig1.caption" && $0.outcome == .fail })
        XCTAssertThrowsError(try PublicationRenderer.render(m, profile: plos))
    }
    func testCorruptImageAndHashMismatchFail() throws {
        var m = fixture(); let data = Data("not PNG".utf8)
        m.sections[0].blocks.append(.init(id: "fig1", kind: .figure, text: "", caption: "Caption", figure: .init(mediaType: "image/png", data: data, sha256: PublicationHash.sha256(data), altText: "Description")))
        XCTAssertThrowsError(try PublicationRenderer.render(m, profile: plos))
        m.sections[0].blocks[m.sections[0].blocks.count-1].figure?.sha256 = "wrong"
        XCTAssertThrowsError(try m.validate())
    }
    func testTablesAndFiguresRetained() throws {
        var m = fixture()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { ctx in UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
        m.sections[0].blocks.append(.init(id: "tab1", kind: .table, text: "Table note", caption: "Observed counts", table: .init(columns: ["Group", "Count"], rows: [["A", "42"], ["B", "−3.14"]])))
        m.sections[0].blocks.append(.init(id: "fig1", kind: .figure, text: "Figure note", caption: "An explicitly synthetic blue square", figure: .init(mediaType: "image/png", data: image, sha256: PublicationHash.sha256(image), altText: "Synthetic blue square")))
        let result = try PublicationRenderer.render(m, profile: plos)
        XCTAssertTrue(result.html.contains("<td>−3.14</td>")); XCTAssertTrue(result.html.contains(image.base64EncodedString()))
        let pdf = try XCTUnwrap(PDFDocument(data: result.pdf)); XCTAssertTrue(pdf.string?.contains("Count: −3.14") == true)
        XCTAssertEqual(try JSONDecoder().decode(PublicationManuscript.self, from: result.canonical).allBlocks.first(where: { $0.id == "fig1" })?.figure?.data, image)
    }
    func testLargeTableAndPaginationPreserveLastCell() throws {
        var m = fixture(); m.sections[0].blocks.append(.init(id: "tab1", kind: .table, text: "", caption: "Long table", table: .init(columns: ["Key", "Value"], rows: (0..<180).map { ["row-\($0)", $0 == 179 ? "LAST-CELL-58421" : "data"] })))
        let result = try PublicationRenderer.render(m, profile: plos), pdf = try XCTUnwrap(PDFDocument(data: result.pdf))
        XCTAssertGreaterThan(pdf.pageCount, 3); XCTAssertTrue(pdf.string?.contains("LAST-CELL-58421") == true)
        m.sections[0].blocks[m.sections[0].blocks.count-1].table?.rows.append(["wrong-width"])
        XCTAssertThrowsError(try m.validate())
    }
    func testPDFPaginationPreservesTail() throws {
        var m = fixture(); m.sections[0].blocks[0].text = Array(repeating: "Original values 42 and 0.05 remain unchanged.", count: 180).joined(separator: "\n") + "\nLAST-PARAGRAPH-92561"
        let result = try PublicationRenderer.render(m, profile: plos), pdf = try XCTUnwrap(PDFDocument(data: result.pdf))
        XCTAssertGreaterThan(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("LAST-PARAGRAPH-92561") == true)
        XCTAssertTrue(pdf.string?.contains("APPENDIX-END-92817") == true)
    }
    func testPaginatedPDFNeverMirrorsTextAfterFooterDrawing() throws {
        var m = fixture()
        m.sections[0].blocks[0].text = Array(repeating: "Upright glyph controls: ABC abc 123; original scientific values remain unchanged.", count: 80).joined(separator: "\n")
        let rendered = try PublicationRenderer.render(m, profile: plos)
        let provider = try XCTUnwrap(CGDataProvider(data: rendered.pdf as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(document.numberOfPages, 2)
        for number in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: number))
            let probe = PublicationPDFOrientationProbe()
            let table = try XCTUnwrap(CGPDFOperatorTableCreate())
            CGPDFOperatorTableSetCallback(table, "q") { _, context in
                let p = Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue()
                p.graphicsStack.append(p.graphicsDeterminant)
            }
            CGPDFOperatorTableSetCallback(table, "Q") { _, context in
                let p = Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue()
                p.graphicsDeterminant = p.graphicsStack.popLast() ?? 1
            }
            CGPDFOperatorTableSetCallback(table, "cm") { scanner, context in
                let p = Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue()
                p.graphicsDeterminant *= PublicationPDFOrientationProbe.popDeterminant(scanner)
            }
            CGPDFOperatorTableSetCallback(table, "Tm") { scanner, context in
                let p = Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue()
                p.textDeterminant = PublicationPDFOrientationProbe.popDeterminant(scanner)
            }
            CGPDFOperatorTableSetCallback(table, "BT") { _, context in
                Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue().textDeterminant = 1
            }
            for operation in ["Tj", "TJ", "'", "\""] {
                CGPDFOperatorTableSetCallback(table, operation) { _, context in
                    let p = Unmanaged<PublicationPDFOrientationProbe>.fromOpaque(context!).takeUnretainedValue()
                    p.textShows += 1
                    if p.graphicsDeterminant * p.textDeterminant <= 0 { p.mirroredTextShows += 1 }
                }
            }
            let stream = try XCTUnwrap(CGPDFContentStreamCreateWithPage(page))
            let scanner = try XCTUnwrap(CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(probe).toOpaque()))
            XCTAssertTrue(CGPDFScannerScan(scanner))
            XCTAssertGreaterThan(probe.textShows, 0)
            XCTAssertEqual(probe.mirroredTextShows, 0, "PDF page \(number) contains mirrored glyph transformations, even if extraction preserves its text.")
        }
    }
    func testUnicodeFontAndActualTextProbeExports() throws {
        // Investigation fixture deliberately distinguishes visually similar 日
        // U+65E5 and ⽇ U+2F47. No compatibility normalization is permitted.
        let expected = "Exact Unicode: 日本語 | ⽇本語 | café | β = −1.25 | E = mc²; \\alpha + \\beta = 42"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchOSUnicodeProbe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var observations: [[String: Any]] = []
        for name in ["TimesNewRomanPSMT", "PingFangSC-Regular", "HiraginoSans-W3", "HiraginoMinchoProN-W3", "STSongti-SC-Regular", "AppleSDGothicNeo-Regular"] {
            guard let font = UIFont(name: name, size: 14) else {
                observations.append(["requestedFont": name, "available": false]); continue
            }
            for tagged in [false, true] {
                let filename = name + (tagged ? "-actual-text" : "-untagged") + ".pdf"
                let attributed = NSAttributedString(string: expected, attributes: [.font: font])
                let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                    context.beginPage(); let cg = context.cgContext
                    cg.textMatrix = .identity; cg.translateBy(x: 0, y: 792); cg.scaleBy(x: 1, y: -1)
                    if tagged { CGPDFContextBeginTag(cg, .span, [CGPDFTagProperty.actualText.rawValue as String: expected] as CFDictionary) }
                    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed), CFRange(location: 0, length: attributed.length), CGPath(rect: CGRect(x: 72, y: 72, width: 468, height: 648), transform: nil), nil)
                    CTFrameDraw(frame, cg)
                    if tagged { CGPDFContextEndTag(cg) }
                }
                try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                let text = try XCTUnwrap(PDFDocument(data: data)?.string)
                observations.append(["requestedFont": name, "resolvedFont": font.fontName, "available": true, "taggedActualText": tagged, "filename": filename, "nativePDFKitText": text, "nativePDFKitExactContains": text.contains(expected)])
            }
        }
        try Data(expected.utf8).write(to: directory.appendingPathComponent("expected-unicode.txt"))
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("observations.json"))
        print("RESEARCH_OS_UNICODE_PROBE_DIRECTORY=" + directory.path)
        XCTAssertFalse(observations.isEmpty)
    }
    func testTransactionalWriteKeepsOldExportsAndFailedWriteHasNoPartialResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try PublicationRenderer.render(fixture(), profile: plos), destination = root.appendingPathComponent("export")
        let files = try result.write(to: destination); XCTAssertEqual(files.count, 5)
        let original = try Data(contentsOf: destination.appendingPathComponent("canonical-manuscript.json"))
        XCTAssertThrowsError(try result.write(to: destination))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("canonical-manuscript.json")), original)
        let blocking = root.appendingPathComponent("file-not-directory"); try Data("blocking".utf8).write(to: blocking)
        XCTAssertThrowsError(try result.write(to: blocking.appendingPathComponent("cannot-write")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["export", "file-not-directory"])
    }
    func testIncompleteBibliographyReportsMissingFields() throws {
        var m = fixture(); m.references[0].title = nil; m.references[0].year = nil
        let report = try PublicationEngine.preflight(m, profile: plos)
        XCTAssertTrue(report.checks.contains { $0.location == "refA" && $0.currentValue.contains("title, year") && $0.outcome == .fail })
        XCTAssertNil(m.references[0].year)
    }
    func testNormalizationChangesOnlyDeclaredPDFMetadata() throws {
        let pdf = "%PDF-1.3\n1 0 obj\n<< /Length 70 >>\nstream\n/CreationDate (SCIENTIFIC-DATA) /ID [<ABCD><1234>]\nendstream\nendobj\n2 0 obj\n<< /CreationDate (D:20260924123456Z) /Title (Scientific title) >>\nendobj\ntrailer\n<< /Root 3 0 R /Info 2 0 R /ID [<ABCDEF><123456>] >>\nstartxref\n0\n%%EOF"
        let normalized = String(decoding: try PublicationRenderer.normalizedPDF(Data(pdf.utf8)), as: UTF8.self)
        XCTAssertTrue(normalized.contains("/CreationDate (SCIENTIFIC-DATA) /ID [<ABCD><1234>]"))
        XCTAssertTrue(normalized.contains("/CreationDate (00000000000000000)"))
        XCTAssertTrue(normalized.contains("/ID [<000000><000000>]"))
        XCTAssertTrue(normalized.contains("/Title (Scientific title)"))
        XCTAssertEqual(normalized.utf8.count, pdf.utf8.count)
    }
    func testDeclaredCombinedResultsAndDiscussionIsAllowed() throws {
        var m = fixture()
        m.sections.append(.init(id: "combined", role: .resultsAndDiscussion, heading: "Results and discussion", blocks: [.init(id: "combined-p", text: "Author supplied combined content.")]))
        let report = try PublicationEngine.preflight(m, profile: plos)
        XCTAssertTrue(report.checks.contains { $0.id == "sections:results" && $0.outcome == .pass })
        XCTAssertTrue(report.checks.contains { $0.id == "sections:discussion" && $0.outcome == .pass })
        XCTAssertEqual(m.sections.last?.heading, "Results and discussion")
    }
    func testProfileSpecificManualRequirementsAreExplicit() throws {
        let m = fixture(), plosReport = try PublicationEngine.preflight(m, profile: plos), iclrReport = try PublicationEngine.preflight(m, profile: iclr)
        for report in [plosReport, iclrReport] {
            let check = try XCTUnwrap(report.checks.first { $0.location == "reference-name-structure" })
            XCTAssertEqual(check.handling, .needsAuthorInput); XCTAssertEqual(check.outcome, .unknown)
            XCTAssertTrue(check.currentValue.contains("literal strings"))
        }
        XCTAssertTrue(plosReport.checks.contains { $0.location == "abstract-no-citations" && $0.outcome == .unknown })
        XCTAssertTrue(iclrReport.checks.contains { $0.location == "abstract-single-paragraph" && $0.outcome == .unknown })
        XCTAssertEqual(m.abstract, fixture().abstract)
    }
    func testNativeExportEvidenceABARetainsRichFrozenFixture() throws {
        var m = fixture()
        m.title = "Synthetic formatter preservation fixture: α = 0.05"
        m.abstract = "This is an explicitly synthetic software test fixture. Numbers, table and graphic test content preservation; they are not study results or human validation."
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 150)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 150))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 20, y: 85, width: 40, height: 35)); context.fill(CGRect(x: 85, y: 55, width: 40, height: 65)); context.fill(CGRect(x: 150, y: 25, width: 40, height: 95))
            ("SYNTHETIC TEST GRAPHIC" as NSString).draw(at: CGPoint(x: 18, y: 130), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
        }
        m.sections[0].blocks += [
            .init(id: "table-evidence", kind: .table, text: "Every cell is a synthetic preservation control.", caption: "Synthetic numeric and Unicode controls", table: .init(columns: ["Control", "Value", "Note"], rows: [["A", "42", "café"], ["B", "−3.14", "日本語"], ["C", "0.05", "LAST-CELL-58421"]])),
            .init(id: "figure-evidence", kind: .figure, text: "This generated graphic is not research evidence.", caption: "Synthetic blue bars used only to inspect figure preservation", figure: .init(mediaType: "image/png", data: image, sha256: PublicationHash.sha256(image), altText: "Three synthetic blue bars increasing in height; no empirical interpretation."))
        ]
        let canonical = try m.canonicalData(), a = try PublicationRenderer.render(m, profile: plos), b = try PublicationRenderer.render(m, profile: iclr), a2 = try PublicationRenderer.render(m, profile: plos)
        XCTAssertEqual(a.canonical, canonical); XCTAssertEqual(b.canonical, canonical); XCTAssertEqual(a2.canonical, canonical)
        XCTAssertEqual(a.html, a2.html)
        XCTAssertEqual(try PublicationRenderer.normalizedPDF(a.pdf), try PublicationRenderer.normalizedPDF(a2.pdf))
        XCTAssertEqual(a.receipt.normalizedPDFSHA256, a2.receipt.normalizedPDFSHA256)
        for result in [a, b, a2] {
            let decoded = try JSONDecoder().decode(PublicationManuscript.self, from: result.canonical)
            XCTAssertEqual(decoded.allBlocks.first { $0.id == "figure-evidence" }?.figure?.data, image)
            XCTAssertEqual(decoded.allBlocks.first { $0.id == "table-evidence" }?.table?.rows.last, ["C", "0.05", "LAST-CELL-58421"])
            XCTAssertTrue(PDFDocument(data: result.pdf)?.string?.contains("LAST-CELL-58421") == true)
            XCTAssertTrue(PDFDocument(data: result.pdf)?.string?.contains("APPENDIX-END-92817") == true)
        }
        // Deliberately retained for the root integrator to copy, open and inspect.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchOSPublicationEvidence-" + UUID().uuidString, isDirectory: true)
        _ = try a.write(to: directory.appendingPathComponent("A-PLOS"))
        _ = try b.write(to: directory.appendingPathComponent("B-ICLR"))
        _ = try a2.write(to: directory.appendingPathComponent("A2-PLOS"))
        let report: [String: Any] = ["classification": "SYNTHETIC_FORMATTER_TEST_FIXTURE", "canonicalSHA256": PublicationHash.sha256(canonical), "ABACanonicalBytesEqual": a.canonical == b.canonical && a.canonical == a2.canonical, "ABAHTMLBytesEqual": a.html == a2.html, "ABANormalizedFullPDFBytesEqual": try PublicationRenderer.normalizedPDF(a.pdf) == PublicationRenderer.normalizedPDF(a2.pdf), "rawPDFSHA256A": a.receipt.pdfSHA256, "rawPDFSHA256A2": a2.receipt.pdfSHA256, "os": a.receipt.operatingSystem, "font": a.receipt.resolvedFontName, "humanTesting": "NOT_PERFORMED", "physicalDevice": "NOT_ESTABLISHED_BY_THIS_TEST", "publicationReadiness": "PARTIAL_PREVIEW_ONLY"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("evidence-manifest.json"), options: .atomic)
        print("RESEARCH_OS_PUBLICATION_EVIDENCE_DIRECTORY=" + directory.path)
    }
}

/// Independent PDF operator inspection: compare the handedness of effective
/// text transforms instead of accepting an extracted-string snapshot as proof
/// of readable pages. The renderer's CoreText calls are not reused here.
private final class PublicationPDFOrientationProbe {
    var graphicsDeterminant: CGFloat = 1
    var textDeterminant: CGFloat = 1
    var graphicsStack: [CGFloat] = []
    var textShows = 0
    var mirroredTextShows = 0
    static func popDeterminant(_ scanner: CGPDFScannerRef) -> CGFloat {
        var values = [CGPDFReal](repeating: 0, count: 6)
        for index in values.indices {
            guard CGPDFScannerPopNumber(scanner, &values[index]) else { return 0 }
        }
        // PDF operands are popped f,e,d,c,b,a; translation does not alter handedness.
        return CGFloat(values[5] * values[2] - values[4] * values[3])
    }
}
