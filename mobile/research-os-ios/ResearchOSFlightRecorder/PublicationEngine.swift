import Foundation
import ImageIO

enum PublicationHandling: String, Codable { case auto = "AUTO", needsAuthorInput = "NEEDS_AUTHOR_INPUT", lockedSubstantiveEdit = "LOCKED_SUBSTANTIVE_EDIT" }
enum PublicationOutcome: String, Codable { case pass = "PASS", fail = "FAIL", unknown = "UNKNOWN" }
enum PublicationImplementation: String, Codable { case implemented, partial, unsupported, manual }
struct PublicationRule: Codable, Equatable, Identifiable {
    let id: String
    let requirement: String
    let sourceURL: String
    let implementation: PublicationImplementation
    let failureBehavior: String
    let tests: [String]
}
struct PublicationProfile: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let venue: String
    let articleType: String
    let version: String
    let manuscriptSchema: Int
    let instructionURL: String
    let checkedUTC: String
    let instructionSHA256: String?
    let coverageNotes: String
    let outputs: [String]
    let renderer: String
    let citationAsset: String
    let citationAssetVersion: String
    let anonymized: Bool
    let fontPoints: Double
    let lineHeight: Double
    let marginPoints: Double
    let titleLimit: Int?
    let abstractLimit: Int?
    let requiredSections: [PublicationSectionRole]
    let requiredDeclarations: [String]
    let rules: [PublicationRule]

    static let registry: [PublicationProfile] = {
        let plos = "https://journals.plos.org/plosone/s/submission-guidelines"
        let iclr = "https://iclr.cc/Conferences/2027/AuthorGuidelines"
        let local = "research-os:generic-profile-v1"
        func rules(_ url: String, venue: Bool) -> [PublicationRule] {
            [
                .init(id: "metadata", requirement: "Title, authors, affiliations and abstract supplied by the author", sourceURL: url, implementation: .implemented, failureBehavior: "Preview only; no invented metadata", tests: ["testMissingFieldsStayExplicit"]),
                .init(id: "limits", requirement: "Count title characters and abstract words without rewriting", sourceURL: url, implementation: .implemented, failureBehavior: "LOCKED_SUBSTANTIVE_EDIT with exact overage", tests: ["testLimitsReportExactOverage"]),
                .init(id: "sections", requirement: "Required semantic sections supplied and mapped by author", sourceURL: url, implementation: .partial, failureBehavior: "Preview only; no automatic substantive relabeling", tests: ["testMissingFieldsStayExplicit"]),
                .init(id: "citations", requirement: "Stable citations and references rendered by pinned CSL processor", sourceURL: "https://github.com/citation-style-language/styles", implementation: .partial, failureBehavior: "Unknown reference fails; incomplete metadata requires author", tests: ["testCSLHasIndependentNumericCitationOracle", "testUnknownCitationFails"]),
                .init(id: "abstract-structure", requirement: "Venue-specific abstract structure and citation restrictions require author review", sourceURL: url, implementation: .manual, failureBehavior: "Unknown; raw abstract text is not silently parsed or relabeled", tests: ["testProfileSpecificManualRequirementsAreExplicit"]),
                .init(id: "layout", requirement: "Native pagination, typography, numbering and readable tables/figures", sourceURL: url, implementation: .partial, failureBehavior: "Preview only; table rows linearized, images reproduced after text", tests: ["testPDFPaginationPreservesTail", "testTablesAndFiguresRetained"]),
                .init(id: "declarations", requirement: "Required author declarations supplied without invention", sourceURL: url, implementation: .implemented, failureBehavior: "Preview only when declarations missing", tests: ["testMissingFieldsStayExplicit"]),
                .init(id: "anonymity", requirement: "Author metadata omitted only from anonymous presentation; prose/assets require review", sourceURL: url, implementation: .partial, failureBehavior: "Author review of self-identifying text/attachments", tests: ["testAnonymousViewPreservesCanonicalAuthors"]),
                .init(id: "instructions", requirement: "Author confirms current official venue instructions and all nonautomated requirements", sourceURL: url, implementation: .manual, failureBehavior: "Unknown; instructions snapshot is dated", tests: ["testProfileTamperingAndUnknownVersionRejected"]),
                .init(id: "submission-format", requirement: venue ? "Venue-required submission files and exact template layout" : "Generic PDF and HTML; no venue certification", sourceURL: url, implementation: venue ? .unsupported : .implemented, failureBehavior: venue ? "Clearly noncompliant preview only; DOCX/RTF/official LaTeX not implemented" : "Generic output only", tests: ["testBothVenueProfilesRemainPartialPreviews"])
            ]
        }
        return [
            .init(id: "plos-one-research", label: "PLOS ONE · Research Article", venue: "PLOS ONE", articleType: "Research Article · submission preview", version: "2026-09-24.1", manuscriptSchema: 1, instructionURL: plos, checkedUTC: "2026-09-24", instructionSHA256: "ae37f676926e6143a7c48bb0b61e7f8c94c4630c4511d6d64f799fe369e6dd28", coverageNotes: "Partial preview. Native PDF/HTML are not the DOC/DOCX/RTF submission route; LaTeX source is not generated. Continuous line/page numbers and double spacing are preview aids. Caption placement, title page and full publisher requirements need review. Reference authors are literal strings; family/given-name and initials formatting is unsupported. Confirm the abstract contains no citations.", outputs: ["PDF preview", "HTML preview", "canonical JSON", "receipt JSON"], renderer: PublicationRenderer.version, citationAsset: "plos.csl", citationAssetVersion: "pinned ASSET-MANIFEST.json", anonymized: false, fontPoints: 12, lineHeight: 24, marginPoints: 72, titleLimit: 250, abstractLimit: 300, requiredSections: [.introduction, .methods, .results, .discussion], requiredDeclarations: ["funding", "competing-interests", "data-availability"], rules: rules(plos, venue: true)),
            .init(id: "iclr-2027-initial", label: "ICLR 2027 · Initial submission", venue: "ICLR 2027", articleType: "Initial submission · anonymous preview", version: "2026-09-24.1", manuscriptSchema: 1, instructionURL: iclr, checkedUTC: "2026-09-24", instructionSHA256: "7cd9c7cf7daf268483205732bebd9ffbc4156ec7b9014b32204b5fd104c55df2", coverageNotes: "Partial preview. Official ICLR LaTeX template/natbib output is not implemented. APA CSL is an explicitly approximate author-date preview, not the required ICLR bibliography. Nine-main-page limit cannot be certified from this native preview. Reference authors are literal strings, so surname author-year presentation is not established. Author must review prose/assets for anonymity, confirm a one-paragraph abstract and supply AI-use statement. Template redistribution license unresolved; no ICLR template bundled.", outputs: ["PDF preview", "HTML preview", "canonical JSON", "receipt JSON"], renderer: PublicationRenderer.version, citationAsset: "apa.csl", citationAssetVersion: "pinned ASSET-MANIFEST.json", anonymized: true, fontPoints: 10, lineHeight: 11, marginPoints: 72, titleLimit: nil, abstractLimit: nil, requiredSections: [], requiredDeclarations: ["ai-use"], rules: rules(iclr, venue: true)),
            .init(id: "generic-research", label: "Generic research · No venue claim", venue: "Generic", articleType: "Research manuscript", version: "1.0.0", manuscriptSchema: 1, instructionURL: local, checkedUTC: "2026-09-24", instructionSHA256: nil, coverageNotes: "Readable local PDF/HTML with APA CSL. No publisher compliance claim. Reference names remain literal author-entered strings. Equations retain literal notation; native table rows are linearized for reliable pagination and figures follow manuscript text.", outputs: ["PDF", "HTML", "canonical JSON", "receipt JSON"], renderer: PublicationRenderer.version, citationAsset: "apa.csl", citationAssetVersion: "pinned ASSET-MANIFEST.json", anonymized: false, fontPoints: 12, lineHeight: 18, marginPoints: 54, titleLimit: nil, abstractLimit: nil, requiredSections: [], requiredDeclarations: [], rules: rules(local, venue: false))
        ]
    }()
    func validate() throws {
        guard let current = Self.registry.first(where: { $0.id == id }), current == self, manuscriptSchema == 1 else {
            throw PublicationError.invalid("Unknown, modified, or unsupported profile/version. The canonical manuscript remains unchanged.")
        }
    }
}
struct PublicationCheck: Codable, Equatable, Identifiable {
    var id: String
    var handling: PublicationHandling
    var outcome: PublicationOutcome
    var location: String
    var currentValue: String
    var requiredAction: String
    var sourceURL: String
    var blocksExport: Bool
}
struct PublicationPreflight: Codable, Equatable {
    var profileID: String
    var profileVersion: String
    var checks: [PublicationCheck]
    var previewAllowed: Bool { !checks.contains(where: \.blocksExport) }
    var unresolved: [PublicationCheck] { checks.filter { $0.outcome != .pass } }
    var summary: String { unresolved.isEmpty ? "Supported automated checks passed; no scientific validity or acceptance claim." : "\(unresolved.count) unresolved checks · clearly labeled preview only" }
}
enum PublicationEngine {
    static func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
    static func preflight(_ manuscript: PublicationManuscript, profile: PublicationProfile) throws -> PublicationPreflight {
        try manuscript.validate(); try profile.validate()
        var checks: [PublicationCheck] = []
        func add(_ rule: String, _ handling: PublicationHandling, _ outcome: PublicationOutcome, _ location: String, _ value: String, _ action: String, blocked: Bool = false) {
            checks.append(.init(id: rule + ":" + location, handling: handling, outcome: outcome, location: location, currentValue: value, requiredAction: action, sourceURL: profile.rules.first(where: { $0.id == rule })?.sourceURL ?? profile.instructionURL, blocksExport: blocked))
        }
        for (field, value) in [("title", manuscript.title), ("abstract", manuscript.abstract)] {
            let supplied = value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            add("metadata", supplied ? .auto : .needsAuthorInput, supplied ? .pass : .fail, field, supplied ? "Supplied" : "Missing", supplied ? "None" : "Enter the author's \(field); nothing will be invented.")
        }
        for (field, valid) in [("authors", !manuscript.authors.isEmpty && manuscript.authors.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), ("affiliations", !manuscript.affiliations.isEmpty && manuscript.authors.allSatisfy { !$0.affiliationIDs.isEmpty })] {
            add("metadata", valid ? .auto : .needsAuthorInput, valid ? .pass : .fail, field, valid ? "Supplied" : "Missing or incomplete", valid ? "None" : "Supply and link \(field).")
        }
        for field in manuscript.unknownFields { add("metadata", .needsAuthorInput, .unknown, field, "Explicitly unknown", "Resolve this field or retain its unknown status.") }
        if let limit = profile.titleLimit { let n = manuscript.title?.count ?? 0; add("limits", n > limit ? .lockedSubstantiveEdit : .auto, n > limit ? .fail : .pass, "title", "\(n) Unicode grapheme clusters; limit \(limit); overage \(max(0, n-limit))", n > limit ? "Author must shorten the title; renderer never edits it." : "None") }
        if profile.id == "plos-one-research", let title = manuscript.shortTitle {
            add("limits", title.count > 100 ? .lockedSubstantiveEdit : .auto, title.count > 100 ? .fail : .pass, "shortTitle", "\(title.count) characters; limit 100; overage \(max(0,title.count-100))", title.count > 100 ? "Author must shorten the short title." : "None")
        } else if profile.id == "plos-one-research" { add("metadata", .needsAuthorInput, .fail, "shortTitle", "Missing", "Supply a short title of at most 100 characters.") }
        if let limit = profile.abstractLimit { let n = words(manuscript.abstract ?? ""); add("limits", n > limit ? .lockedSubstantiveEdit : .auto, n > limit ? .fail : .pass, "abstract", "\(n) whitespace-separated tokens; limit \(limit); overage \(max(0,n-limit))", n > limit ? "Author must shorten the abstract; text remains unchanged." : "None. Publisher counting convention needs final review.") }
        if profile.id == "plos-one-research" {
            add("abstract-structure", .needsAuthorInput, .unknown, "abstract-no-citations", "Abstract is raw author-entered text; absence of citations is not established", "Confirm the PLOS abstract contains no citations. The renderer does not infer or remove references from prose.")
        } else if profile.id == "iclr-2027-initial" {
            let breaks = (manuscript.abstract ?? "").filter { $0 == "\n" }.count
            add("abstract-structure", .needsAuthorInput, .unknown, "abstract-single-paragraph", "Raw abstract has \(breaks) line breaks; line wrapping versus paragraph boundaries is author intent", "Confirm the ICLR abstract is one paragraph in the official template. The renderer does not merge or rewrite abstract text.")
        }
        if !manuscript.references.isEmpty {
            add("citations", .needsAuthorInput, .unknown, "reference-name-structure", "Reference author names are passed to CSL as literal strings; family/given names are not inferred", "Review venue-required author-name presentation. PLOS family-name/initial formatting and ICLR surname author-year presentation are not established by literal-name previews; supply structured name metadata in a future supported profile or complete the required publisher source workflow.")
        }
        for role in profile.requiredSections {
            let found = manuscript.sections.contains { section in
                !section.blocks.isEmpty && (section.role == role || (profile.id == "plos-one-research" && section.role == .resultsAndDiscussion && (role == .results || role == .discussion)))
            }
            add("sections", found ? .auto : .needsAuthorInput, found ? .pass : .fail, role.rawValue, found ? "Author-mapped section present (a declared combined Results and Discussion section is allowed)" : "Required semantic content not mapped", found ? "None" : "Supply or explicitly map a section, including a combined Results and Discussion section when appropriate; arbitrary prose is never relabeled.")
        }
        for key in profile.requiredDeclarations { let supplied = manuscript.declarations[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false; add("declarations", supplied ? .auto : .needsAuthorInput, supplied ? .pass : .fail, key, supplied ? "Author supplied" : "Missing", supplied ? "Author remains responsible for its accuracy." : "Enter the actual \(key) declaration. No default declaration is invented.") }
        for ref in manuscript.references {
            let missing = [("title", ref.title?.isEmpty != false), ("authors", ref.authors.isEmpty), ("year", ref.year == nil)].filter(\.1).map(\.0)
            add("citations", missing.isEmpty ? .auto : .needsAuthorInput, missing.isEmpty ? .pass : .fail, ref.id, missing.isEmpty ? "Required basic metadata supplied" : "Missing: " + missing.joined(separator: ", "), missing.isEmpty ? "Check bibliographic accuracy against the source." : "Supply missing metadata; any locale missing-date marker is a placeholder, not an invented date.")
        }
        for block in manuscript.allBlocks {
            if block.kind == .figure {
                let present = block.figure?.data != nil
                add("layout", present ? .auto : .needsAuthorInput, present ? .pass : .fail, block.id, present ? "Embedded asset present" : "Missing image asset", present ? "Inspect image, caption and anonymity; PDF reproduces figures after text." : "Supply the image. Export is blocked instead of substituting an image.", blocked: !present)
                if let data = block.figure?.data {
                    let source = CGImageSourceCreateWithData(data as CFData, nil)
                    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
                    let actualType = source.flatMap { CGImageSourceGetType($0) as String? }
                    let expectedType = block.figure?.mediaType == "image/png" ? "public.png" : "public.jpeg"
                    let valid = actualType == expectedType && width > 0 && height > 0 && width <= 8000 && height <= 8000 && width * height <= 16_000_000
                    add("layout", valid ? .auto : .needsAuthorInput, valid ? .pass : .fail, block.id + ".pixels", valid ? "\(width) × \(height) decoded image header" : "Invalid image or image exceeds 16-million-pixel bound", valid ? "Inspect the actual image in the rendered preview." : "Supply a decodable bounded PNG/JPEG; no image substitution is performed.", blocked: !valid)
                }
                if block.figure?.altText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { add("layout", .needsAuthorInput, .fail, block.id + ".altText", "Missing alternative text", "Supply an accessible description; the renderer does not invent image meaning.") }
            }
            if (block.kind == .figure || block.kind == .table) && block.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { add("layout", .needsAuthorInput, .fail, block.id + ".caption", "Missing caption", "Supply the author's caption; preview retains an explicit missing-caption marker.") }
            if block.kind == .table {
                add("layout", .needsAuthorInput, block.table == nil ? .fail : .unknown, block.id, block.table == nil ? "Missing table" : "\(block.table!.rows.count) rows retained; PDF renders labeled rows", "Inspect row/column presentation; exact venue table layout is unsupported.", blocked: block.table == nil)
            }
            if block.kind == .equation { add("layout", .needsAuthorInput, .unknown, block.id, "Literal equation retained", "Inspect glyphs and notation. TeX is preserved literally; no TeX typesetter is bundled.") }
        }
        add("layout", .auto, .pass, "native-pagination", "Native CoreText pagination; \(profile.fontPoints) point base font; \(profile.lineHeight) point line height", "Inspect actual page breaks, glyphs and final page. No text is truncated.")
        let authoredText = [manuscript.title ?? "", manuscript.abstract ?? ""] + manuscript.allBlocks.map(\.text) + manuscript.allBlocks.compactMap(\.caption) + manuscript.allBlocks.flatMap { ($0.table?.columns ?? []) + ($0.table?.rows.flatMap { $0 } ?? []) }
        if authoredText.contains(where: { $0.unicodeScalars.contains { $0.value > 127 } }) {
            add("layout", .needsAuthorInput, .unknown, "pdf-unicode-reader", "Exact Unicode is retained in PDF ActualText tags, HTML and canonical JSON; Quartz glyph maps can use compatibility code points", "Check copying scientific text in the intended PDF reader. Readers that ignore ActualText may expose a different code point for a visually identical glyph; use the exact HTML/canonical source when that reader cannot preserve it. No compatibility normalization is applied to manuscript content.")
        }
        if profile.anonymized { add("anonymity", .needsAuthorInput, .unknown, "manuscript-and-assets", "Author metadata hidden only in rendered view; original retained in canonical archive", "Review self-identifying prose, citations, figures, declarations and supplementary material. Canonical JSON and receipt are private and include identity.") }
        add("instructions", .needsAuthorInput, .unknown, "profile", "Official source snapshot checked \(profile.checkedUTC)", "Review current instructions and nonautomated requirements. A dated profile does not establish current full compliance.")
        add("submission-format", profile.id == "generic-research" ? .auto : .needsAuthorInput, profile.id == "generic-research" ? .pass : .fail, "outputs", profile.outputs.joined(separator: ", "), profile.coverageNotes)
        return .init(profileID: profile.id, profileVersion: profile.version, checks: checks)
    }
}
