import Foundation
import UIKit
import CoreText
import PDFKit
import JavaScriptCore
import ImageIO

struct PublicationExportReceipt: Codable, Equatable {
    let manuscriptID: UUID
    let manuscriptRevision: Int
    let manuscriptSHA256: String
    let profile: PublicationProfile
    let rendererVersion: String
    let operatingSystem: String
    let resolvedFontName: String
    let assetSHA256: [String: String]
    let htmlSHA256: String
    let pdfSHA256: String
    let normalizedPDFSHA256: String
    let normalizedPDFTextSHA256: String
    let normalization: String
    let transformations: [String]
    let unresolvedChecks: [PublicationCheck]
    let authorDecisions: [String: String]
    let boundary: String
}

struct PublicationRenderResult {
    let html: String
    let pdf: Data
    let canonical: Data
    let receipt: PublicationExportReceipt
    let preflight: PublicationPreflight

    /// Build a complete sibling staging directory, then atomically rename it. No existing
    /// export is overwritten, and partial files never appear as a completed export.
    func write(to directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard directory.isFileURL, !fm.fileExists(atPath: directory.path) else {
            throw PublicationError.invalid("Choose a new local export directory; existing exports are immutable.")
        }
        let parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".publication-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let files: [(String, Data)] = [
            ("manuscript.html", Data(html.utf8)), ("manuscript.pdf", pdf),
            ("canonical-manuscript.json", canonical), ("export-receipt.json", try encoder.encode(receipt)),
            ("preflight.json", try encoder.encode(preflight))
        ]
        for (name, data) in files { try data.write(to: staging.appendingPathComponent(name), options: .atomic) }
        try fm.moveItem(at: staging, to: directory)
        return files.map { directory.appendingPathComponent($0.0) }
    }
}

enum PublicationRenderer {
    static let version = "native-coretext-csl-1.0.2"
    static let boundary = "PUBLICATION PREVIEW — unresolved checks are disclosed. Formatting does not verify science, eligibility, acceptance, or complete publisher compliance. Canonical JSON and receipts remain private and may identify authors."
    static let attribution = "(c) Frank Bennett · citeproc-js implements the Citation Style Language · https://citationstyles.org/ · citeproc-js 2.4.63 (CPAL/AGPL). CSL styles and en-US locale: Citation Style Language project and the named contributors retained in bundled files (CC BY-SA 3.0). Full notices and processor source are bundled in PublicationAssets."

    /// Preserve every PDF byte except values of the declared volatile metadata keys.
    /// Replacements have identical lengths, preserving object offsets and the xref table.
    /// Compressed text, image streams, fonts, geometry, and all other metadata are untouched.
    static func normalizedPDF(_ data: Data) throws -> Data {
        var bytes = [UInt8](data)
        let latin = String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        guard latin.utf16.count == bytes.count else { throw PublicationError.invalid("Cannot normalize PDF without preserving its bytes.") }
        let whole = NSRange(location: 0, length: latin.utf16.count)
        // Only this renderer's final classic trailer and its referenced Info object may
        // contain normalizable metadata. Similar strings inside manuscript/image streams
        // are meaningful bytes and must remain untouched.
        guard let trailer = try NSRegularExpression(pattern: #"(?s)trailer\s*<<(.*?)>>\s*startxref"#).matches(in: latin, range: whole).last else { return data }
        func replaceValues(_ pattern: String, in range: NSRange) throws {
            for match in try NSRegularExpression(pattern: pattern).matches(in: latin, range: range) {
                for group in 1..<match.numberOfRanges {
                    let range = match.range(at: group)
                    if range.location != NSNotFound { for index in range.location..<(range.location + range.length) { bytes[index] = 48 } }
                }
            }
        }
        try replaceValues(#"/ID\s*\[\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\]"#, in: trailer.range(at: 1))
        if let info = try NSRegularExpression(pattern: #"/Info\s+(\d+)\s+(\d+)\s+R"#).firstMatch(in: latin, range: trailer.range(at: 1)) {
            let ns = latin as NSString, object = ns.substring(with: info.range(at: 1)), generation = ns.substring(with: info.range(at: 2))
            let pattern = "(?ms)^" + object + " " + generation + #" obj\s*<<(.*?)>>\s*endobj"#
            if let dictionary = try NSRegularExpression(pattern: pattern).matches(in: latin, range: NSRange(location: 0, length: trailer.range.location)).last {
                try replaceValues(#"/(?:CreationDate|ModDate)\s*\(([^)]*)\)"#, in: dictionary.range(at: 1))
            }
        }
        return Data(bytes)
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    private static func resource(_ name: String) throws -> Data {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "PublicationAssets")
                ?? bundle.url(forResource: name, withExtension: nil) else {
            throw PublicationError.invalid("Required offline publication asset is missing: \(name). No remote fallback is used.")
        }
        return try Data(contentsOf: url)
    }

    private struct Citations { let clusters: [String]; let bibliography: [(String, String)]; let hashes: [String: String] }
    /// JavaScriptCore provides no browser, fetch, XHR, file, shell, model, or native bridge.
    /// Untrusted manuscript values are passed as objects, never concatenated into code.
    private static func citations(_ manuscript: PublicationManuscript, profile: PublicationProfile) throws -> Citations {
        let names = ["citeproc-2.4.63.js", "locales-en-US.xml", profile.citationAsset]
        var assets: [String: String] = [:], hashes: [String: String] = [:]
        for name in names {
            let data = try resource(name)
            guard let text = String(data: data, encoding: .utf8) else { throw PublicationError.invalid("Invalid UTF-8 in bundled citation asset \(name).") }
            assets[name] = text; hashes[name] = PublicationHash.sha256(data)
        }
        let manifest = try JSONSerialization.jsonObject(with: resource("ASSET-MANIFEST.json")) as? [String: Any]
        guard let expected = manifest?["assets"] as? [String: String], hashes.allSatisfy({ expected[$0.key] == $0.value }) else {
            throw PublicationError.invalid("Offline citation asset integrity check failed.")
        }
        guard let context = JSContext() else { throw PublicationError.invalid("The offline citation processor could not start.") }
        var failure: String?
        context.exceptionHandler = { _, error in failure = error?.toString() ?? "JavaScript citation error" }
        context.evaluateScript("var module = {exports:{}}; var console = {log:function(){},warn:function(){},error:function(){}};")
        context.evaluateScript(assets["citeproc-2.4.63.js"]!)
        if let failure { throw PublicationError.invalid("Citation processor failed: \(failure)") }
        let items: [[String: Any]] = manuscript.references.map { ref in
            var item: [String: Any] = ["id": ref.id, "type": ref.type]
            if let value = ref.title { item["title"] = value }
            if !ref.authors.isEmpty { item["author"] = ref.authors.map { ["literal": $0] } }
            if let year = ref.year { item["issued"] = ["date-parts": [[year]]] }
            for (key, value) in [("container-title", ref.containerTitle), ("volume", ref.volume), ("issue", ref.issue), ("page", ref.pages), ("DOI", ref.doi), ("URL", ref.url)] { if let value { item[key] = value } }
            return item
        }
        let clusters = manuscript.allBlocks.filter { !$0.citationIDs.isEmpty }.map(\.citationIDs)
        context.setObject(items, forKeyedSubscript: "publicationItems" as NSString)
        context.setObject(clusters, forKeyedSubscript: "publicationClusters" as NSString)
        context.setObject(assets[profile.citationAsset]!, forKeyedSubscript: "publicationStyle" as NSString)
        context.setObject(assets["locales-en-US.xml"]!, forKeyedSubscript: "publicationLocale" as NSString)
        let script = #"""
        (function () {
          var items = Object.create(null), order = [], seen = Object.create(null);
          publicationItems.forEach(function(item) { items[item.id] = item; });
          publicationClusters.forEach(function(ids) { ids.forEach(function(id) { if (!seen[id]) { order.push(id); seen[id] = true; } }); });
          publicationItems.forEach(function(item) { if (!seen[item.id]) { order.push(item.id); seen[item.id] = true; } });
          var engine = new CSL.Engine({retrieveLocale:function(){return publicationLocale;}, retrieveItem:function(id){return items[id];}}, publicationStyle, 'en-US', true);
          engine.setOutputFormat('text'); engine.updateItems(order);
          var rendered = [];
          publicationClusters.forEach(function(ids,index) {
            var result = engine.appendCitationCluster({citationID:'c'+index,citationItems:ids.map(function(id){return {id:id};}),properties:{noteIndex:0}});
            result.forEach(function(update){rendered[update[0]]=update[1];});
          });
          var bib = engine.makeBibliography(), bibliography = [];
          if (bib) bib[1].forEach(function(text,index){bibliography.push([bib[0].entry_ids[index][0],text]);});
          return JSON.stringify({clusters:rendered,bibliography:bibliography,networkUnavailable:typeof fetch==='undefined'&&typeof XMLHttpRequest==='undefined'&&typeof require==='undefined'});
        }())
        """#
        guard let output = context.evaluateScript(script)?.toString(), failure == nil,
              let data = output.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rendered = object["clusters"] as? [String], let bibliography = object["bibliography"] as? [[String]],
              object["networkUnavailable"] as? Bool == true, rendered.count == clusters.count,
              bibliography.allSatisfy({ $0.count == 2 }) else {
            throw PublicationError.invalid("Offline CSL citation rendering failed: \(failure ?? "invalid processor result"). Nothing was exported.")
        }
        return .init(clusters: rendered, bibliography: bibliography.map { ($0[0], $0[1].trimmingCharacters(in: .newlines)) }, hashes: hashes)
    }

    static func render(_ manuscript: PublicationManuscript, profile: PublicationProfile) throws -> PublicationRenderResult {
        let preflight = try PublicationEngine.preflight(manuscript, profile: profile)
        guard preflight.previewAllowed else { throw PublicationError.invalid("Export blocked: " + preflight.checks.filter(\.blocksExport).map(\.requiredAction).joined(separator: " ")) }
        let canonical = try manuscript.canonicalData(), csl = try citations(manuscript, profile: profile)
        let content = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = profile.lineHeight; paragraph.maximumLineHeight = profile.lineHeight; paragraph.paragraphSpacing = profile.fontPoints * 0.5
        let font = UIFont(name: "TimesNewRomanPSMT", size: profile.fontPoints) ?? UIFont.systemFont(ofSize: profile.fontPoints)
        func append(_ text: String, bold: Bool = false) {
            let face = bold ? (UIFont(name: "TimesNewRomanPS-BoldMT", size: profile.fontPoints) ?? UIFont.boldSystemFont(ofSize: profile.fontPoints)) : font
            content.append(NSAttributedString(string: text + "\n", attributes: [.font: face, .paragraphStyle: paragraph, .foregroundColor: UIColor.black]))
        }
        var html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\"><title>Publication preview</title><style>body{font-family:Georgia,serif;max-width:50rem;margin:3rem auto;padding:1rem;line-height:1.6;overflow-wrap:anywhere}p,pre,figcaption,td,th{white-space:pre-wrap}pre{font-family:Georgia,serif}table{border-collapse:collapse;width:100%;table-layout:fixed}th,td{border:1px solid #777;padding:.4rem;vertical-align:top}img{max-width:100%;height:auto}.notice{border:1px solid #777;padding:1rem}a{color:#174d82} @media print{body{margin:0}thead{display:table-header-group}tr{break-inside:avoid}}</style></head><body>"
        html += "<aside class=\"notice\"><strong>" + escape(boundary) + "</strong><p>" + escape(profile.label + " · " + profile.version + " · " + preflight.summary) + "</p><p>" + escape(profile.coverageNotes) + "</p></aside>"
        append("PUBLICATION PREVIEW", bold: true); append(profile.label + " · " + profile.version); append(boundary); append(profile.coverageNotes)
        let title = manuscript.title ?? "[Missing title]"
        html += "<h1>" + escape(title) + "</h1>"; append(title, bold: true)
        if profile.anonymized { html += "<p>Anonymous author view</p>"; append("Anonymous author view") }
        else {
            for author in manuscript.authors { let text = author.name + (author.affiliationIDs.isEmpty ? "" : " [" + author.affiliationIDs.joined(separator: ", ") + "]"); html += "<p>" + escape(text) + "</p>"; append(text) }
            for affiliation in manuscript.affiliations { let text = affiliation.id + ": " + affiliation.label; html += "<p>" + escape(text) + "</p>"; append(text) }
        }
        if let short = manuscript.shortTitle { html += "<p>Short title: " + escape(short) + "</p>"; append("Short title: " + short) }
        html += "<h2>Abstract</h2><p>" + escape(manuscript.abstract ?? "[Missing abstract]") + "</p>"
        append("Abstract", bold: true); append(manuscript.abstract ?? "[Missing abstract]")
        var numbers: [String: String] = [:], counts: [PublicationBlockKind: Int] = [:]
        for block in manuscript.allBlocks where block.kind != .paragraph { counts[block.kind, default: 0] += 1; numbers[block.id] = block.kind.rawValue.capitalized + " " + String(counts[block.kind]!) }
        var clusterIndex = 0, images: [(UIImage, String)] = []
        for (sectionIndex, section) in (manuscript.sections + manuscript.appendices).enumerated() {
            let heading = String(sectionIndex + 1) + ". " + section.heading
            html += "<section id=\"" + section.id + "\"><h2>" + escape(heading) + "</h2>"; append(heading, bold: true)
            for block in section.blocks {
                var citation = ""
                if !block.citationIDs.isEmpty { citation = csl.clusters[clusterIndex]; clusterIndex += 1 }
                html += "<div id=\"" + block.id + "\">"
                let numbered = numbers[block.id] ?? ""
                if block.kind == .table, let table = block.table {
                    let caption = numbered + ": " + (block.caption ?? "[Missing caption]")
                    html += "<table><caption>" + escape(caption) + "</caption><thead><tr>" + table.columns.map { "<th>" + escape($0) + "</th>" }.joined() + "</tr></thead><tbody>"
                    append(caption, bold: true)
                    for (rowIndex, row) in table.rows.enumerated() {
                        html += "<tr>" + row.map { "<td>" + escape($0) + "</td>" }.joined() + "</tr>"
                        append("Row \(rowIndex + 1): " + zip(table.columns, row).map { $0 + ": " + $1 }.joined(separator: " | "))
                    }
                    if table.rows.isEmpty { append("Columns: " + table.columns.joined(separator: " | ")) }
                    html += "</tbody></table>"
                }
                if block.kind == .figure, let figure = block.figure, let data = figure.data {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetType(source) as String? == (figure.mediaType == "image/png" ? "public.png" : "public.jpeg"),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 8000, height <= 8000, width * height <= 16_000_000,
                          let image = UIImage(data: data) else { throw PublicationError.invalid("Figure \(block.id) is corrupt or exceeds the 16-million-pixel image bound.") }
                    let caption = numbered + ": " + (block.caption ?? "[Missing caption]")
                    html += "<figure><img alt=\"" + escape(figure.altText ?? "[Missing alternative text]") + "\" src=\"data:" + figure.mediaType + ";base64," + data.base64EncodedString() + "\"><figcaption>" + escape(caption) + "</figcaption></figure>"
                    append(caption + " [Actual image reproduced after manuscript text.]"); images.append((image, caption))
                    if let alt = figure.altText { append("Alternative text: " + alt) }
                }
                if block.kind == .equation { html += "<p>" + escape(numbered) + "</p><pre>" + escape(block.text) + "</pre>"; append(numbered, bold: true); append(block.text) }
                else { html += "<p>" + escape(block.text) + "</p>"; append(block.text) }
                if block.kind != .figure && block.kind != .table, let caption = block.caption { html += "<p>" + escape(caption) + "</p>"; append(caption) }
                if !citation.isEmpty { html += "<p>" + escape(citation) + " <small>" + block.citationIDs.map { "<a href=\"#ref-" + $0 + "\">" + escape($0) + "</a>" }.joined(separator: " · ") + "</small></p>"; append(citation + " [Stable references: " + block.citationIDs.joined(separator: ", ") + "]") }
                if !block.crossReferenceIDs.isEmpty {
                    let labels = block.crossReferenceIDs.map { numbers[$0] ?? $0 }
                    html += "<p>Cross-references: " + zip(block.crossReferenceIDs, labels).map { "<a href=\"#" + $0 + "\">" + escape($1) + "</a>" }.joined(separator: "; ") + "</p>"; append("Cross-references: " + labels.joined(separator: "; "))
                }
                for link in block.evidenceLinks {
                    let text = "Evidence: source " + link.sourceID + " · version " + link.sourceVersion + " · evidence " + (link.evidenceID ?? "[missing ID]") + " · locator " + (link.locator ?? "[missing locator]") + (link.url.map { " · " + $0 } ?? "")
                    html += "<p>" + escape(text) + "</p>"; append(text)
                }
                html += "</div>"
            }
            html += "</section>"
        }
        for key in manuscript.declarations.keys.sorted() { let text = manuscript.declarations[key]!; html += "<h2>" + escape(key) + "</h2><p>" + escape(text) + "</p>"; append(key, bold: true); append(text) }
        html += "<h2>References</h2>"; append("References", bold: true)
        for (id, text) in csl.bibliography { html += "<p id=\"ref-" + id + "\">" + escape(text) + "</p>"; append(text) }
        html += "<aside class=\"notice\"><h2>Unresolved checks</h2>"; append("Unresolved checks", bold: true)
        for check in preflight.unresolved { let text = "\(check.handling.rawValue) / \(check.outcome.rawValue) · \(check.location): \(check.currentValue). \(check.requiredAction)"; html += "<p>" + escape(text) + "</p>"; append(text) }
        html += "<p>" + escape(attribution) + " <a href=\"https://citationstyles.org/\">Citation Style Language project</a></p></aside></body></html>"; append(attribution)
        let pdf = try paginatedPDF(content, images: images, profile: profile)
        guard let document = PDFDocument(data: pdf), let pdfText = document.string, document.pageCount > 0 else { throw PublicationError.invalid("Generated PDF could not be reopened for inspection.") }
        let receipt = PublicationExportReceipt(manuscriptID: manuscript.id, manuscriptRevision: manuscript.revision, manuscriptSHA256: PublicationHash.sha256(canonical), profile: profile, rendererVersion: version, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, resolvedFontName: font.fontName, assetSHA256: csl.hashes, htmlSHA256: PublicationHash.sha256(Data(html.utf8)), pdfSHA256: PublicationHash.sha256(pdf), normalizedPDFSHA256: PublicationHash.sha256(try normalizedPDF(pdf)), normalizedPDFTextSHA256: PublicationHash.sha256(Data(pdfText.utf8)), normalization: "Full PDF bytes are hashed after replacing only CreationDate/ModDate parenthesized values and trailer ID hexadecimal values with equal-length zero bytes. All streams, fonts, geometry and images remain untouched. Raw PDF hash is also retained. The separate PDFKit text hash is a preservation check, not a layout-equivalence oracle. HTML and canonical JSON contain no volatile values. Determinism is scoped to the recorded native renderer and OS/font environment.", transformations: ["CSL citation/reference presentation; en-US locale pinned", "Exact flowing page text retained in PDF ActualText tags; readers ignoring tags may expose Quartz compatibility glyph mappings. HTML/canonical preserve exact Unicode independently.", "Author-supplied section order retained; section/figure/table/equation numbering added", "Native CoreText pagination; table cells rendered as labeled rows without truncation", "Figures reproduced after all text in native PDF; HTML figures remain in place", "Equations preserved as literal author notation without TeX interpretation", profile.anonymized ? "Author/affiliation metadata hidden in view only; private canonical archive retains identities" : "Author metadata retained"], unresolvedChecks: preflight.unresolved, authorDecisions: manuscript.authorDecisions, boundary: boundary)
        guard try manuscript.canonicalData() == canonical else { throw PublicationError.invalid("Canonical preservation check failed.") }
        return .init(html: html, pdf: pdf, canonical: canonical, receipt: receipt, preflight: preflight)
    }

    private static func paginatedPDF(_ text: NSAttributedString, images: [(UIImage, String)], profile: PublicationProfile) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin = profile.marginPoints
        let body = CGRect(x: margin, y: 64, width: 612 - margin * 2, height: 664)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: version, kCGPDFContextTitle as String: "Publication preview", kCGPDFContextAuthor as String: ""]
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        var failure: String?, lineNumber = 1, page = 0
        let data = UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            var position = 0
            while position < text.length {
                if page >= 400 { failure = "PDF exceeds 400-page resource bound; no partial export was returned."; break }
                context.beginPage(); page += 1
                let cg = context.cgContext
                // UIKit footer drawing leaves a flipped text matrix. The text
                // matrix is not restored by saveGState/restoreGState; reset it
                // at every CoreText page boundary, not just on the first page.
                cg.textMatrix = .identity
                cg.saveGState(); cg.translateBy(x: 0, y: bounds.height); cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: body.minX, y: bounds.height-body.maxY, width: body.width, height: body.height), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0), path, nil)
                let range = CTFrameGetVisibleStringRange(frame)
                if range.length == 0 { failure = "Native pagination made no progress; no content was truncated."; cg.restoreGState(); break }
                // Quartz can map a shared CJK glyph to a compatibility code point
                // in ToUnicode. ActualText retains the exact original code points
                // in standard PDF semantics; readers ignoring tags may still expose
                // the glyph-map approximation. Never normalize scientific content.
                let exactPageText = text.attributedSubstring(from: NSRange(location: range.location, length: range.length)).string
                CGPDFContextBeginTag(cg, .span, [CGPDFTagProperty.actualText.rawValue as String: exactPageText] as CFDictionary)
                CTFrameDraw(frame, cg)
                CGPDFContextEndTag(cg)
                if profile.id == "plos-one-research" {
                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    var origins = [CGPoint](repeating: .zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                    for origin in origins {
                        let label = NSAttributedString(string: String(lineNumber), attributes: [.font: UIFont.systemFont(ofSize: 7), .foregroundColor: UIColor.gray])
                        cg.textMatrix = .identity
                        cg.textPosition = CGPoint(x: body.minX-27, y: bounds.height-body.maxY+origin.y)
                        CTLineDraw(CTLineCreateWithAttributedString(label), cg); lineNumber += 1
                    }
                }
                cg.restoreGState()
                ("Preview · page \(page)" as NSString).draw(at: CGPoint(x: margin, y: 756), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
                position += range.length
            }
            if failure == nil {
                for (image, caption) in images {
                    context.beginPage(); page += 1
                    let available = CGRect(x: margin, y: 85, width: body.width, height: 570)
                    let scale = min(available.width/image.size.width, available.height/image.size.height)
                    let size = CGSize(width: image.size.width*scale, height: image.size.height*scale)
                    image.draw(in: CGRect(x: available.midX-size.width/2, y: available.midY-size.height/2, width: size.width, height: size.height))
                    // Full caption already appears in flowing body text; this page repeats a label only.
                    ((caption.components(separatedBy: ":").first ?? "Figure") + " reproduction; full caption is retained in manuscript text." as NSString).draw(in: CGRect(x: margin, y: 680, width: body.width, height: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
                    ("Preview · page \(page)" as NSString).draw(at: CGPoint(x: margin, y: 756), withAttributes: [.font: UIFont.systemFont(ofSize: 9)])
                    _ = caption
                }
            }
        }
        if let failure { throw PublicationError.invalid(failure) }
        return data
    }
}
