import Foundation
import CryptoKit

enum PublicationError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Scientific content is independent of profiles. A nil scalar explicitly means missing;
/// unknownFields distinguishes fields whose values the author explicitly does not know.
/// Revisions are committed by the workspace journal, never by style conversion.
struct PublicationManuscript: Codable, Equatable, Identifiable {
    var schemaVersion = 1
    var id: UUID
    var revision: Int
    var title: String?
    var shortTitle: String? = nil
    var abstract: String? = nil
    var authors: [PublicationAuthor] = []
    var affiliations: [PublicationAffiliation] = []
    var sections: [PublicationSection] = []
    var references: [PublicationReference] = []
    var appendices: [PublicationSection] = []
    var declarations: [String: String] = [:]
    var unknownFields: [String] = []
    var authorDecisions: [String: String] = [:]

    init(id: UUID = UUID(), revision: Int = 1, title: String? = nil) {
        self.id = id; self.revision = revision; self.title = title
    }

    var allBlocks: [PublicationBlock] { (sections + appendices).flatMap(\.blocks) }
    func canonicalData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    func contentHash() throws -> String { PublicationHash.sha256(try canonicalData()) }

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw PublicationError.invalid(message) }
        }
        try require(schemaVersion == 1, "Unsupported manuscript schema version \(schemaVersion). Original content is retained.")
        try require(revision > 0, "Manuscript revision must be positive.")
        try require((try canonicalData()).count <= 12_000_000, "Manuscript exceeds the 12 MB native export bound; content was not truncated.")
        try require(sections.count + appendices.count <= 100 && allBlocks.count <= 2000, "Manuscript exceeds 100 sections or 2,000 blocks; content was not truncated.")
        try require(references.count <= 500 && authors.count <= 100 && affiliations.count <= 100, "Manuscript metadata exceeds the supported resource bounds.")
        let ids = authors.map(\.id) + affiliations.map(\.id) + (sections + appendices).map(\.id) + allBlocks.map(\.id) + references.map(\.id)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        try require(ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 100 && $0.unicodeScalars.allSatisfy(allowed.contains) }, "Stable IDs must contain only ASCII letters, digits, hyphen, or underscore (100 bytes maximum).")
        try require(Set(ids).count == ids.count, "Stable manuscript IDs must be globally unique.")
        let affs = Set(affiliations.map(\.id)), targets = Set(allBlocks.map(\.id)), refs = Set(references.map(\.id))
        try require(authors.allSatisfy { Set($0.affiliationIDs).isSubset(of: affs) }, "An author references an unknown affiliation.")
        var assetBytes = 0
        for block in allBlocks {
            try require(Set(block.citationIDs).isSubset(of: refs), "Block \(block.id) cites an unknown reference; no reference will be invented.")
            try require(Set(block.crossReferenceIDs).isSubset(of: targets), "Block \(block.id) points to an unknown cross-reference.")
            try require(block.text.utf8.count <= 200_000, "Block \(block.id) exceeds 200 KB; content was not truncated.")
            try require(block.kind == .figure || block.figure == nil, "Figure data must belong to a figure block.")
            try require(block.kind == .table || block.table == nil, "Table data must belong to a table block.")
            if let table = block.table {
                try require(!table.columns.isEmpty && table.columns.count <= 30 && table.rows.count <= 1000, "Table \(block.id) requires 1–30 columns and at most 1,000 rows.")
                try require(table.rows.allSatisfy { $0.count == table.columns.count }, "Table \(block.id) has inconsistent row widths; no cells were dropped.")
            }
            if let figure = block.figure, let data = figure.data {
                try require(["image/png", "image/jpeg"].contains(figure.mediaType), "Only embedded PNG/JPEG figures are supported; SVG, paths, and remote images are not executed or fetched.")
                try require(data.count <= 3_000_000, "Figure \(block.id) exceeds the 3 MB asset bound.")
                try require(figure.sha256 == PublicationHash.sha256(data), "Figure \(block.id) content does not match its recorded SHA-256.")
                assetBytes += data.count
            }
            for link in block.evidenceLinks {
                try require(!link.sourceID.isEmpty && !link.sourceVersion.isEmpty, "Evidence links need a stable source ID and source version.")
            }
        }
        try require(assetBytes <= 8_000_000, "Embedded assets exceed 8 MB; content was not truncated.")
    }
}

struct PublicationAuthor: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var affiliationIDs: [String] = []
}
struct PublicationAffiliation: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var label: String
}
enum PublicationSectionRole: String, Codable, CaseIterable {
    case introduction, methods, results, discussion, resultsAndDiscussion, conclusions, acknowledgments, other, appendix
}
struct PublicationSection: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var role: PublicationSectionRole = .other
    var heading: String
    var blocks: [PublicationBlock]
}
enum PublicationBlockKind: String, Codable, CaseIterable { case paragraph, equation, figure, table }
struct PublicationBlock: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var kind: PublicationBlockKind = .paragraph
    var text: String
    var citationIDs: [String] = []
    var crossReferenceIDs: [String] = []
    var evidenceLinks: [PublicationEvidenceLink] = []
    var caption: String? = nil
    var table: PublicationTable? = nil
    var figure: PublicationFigure? = nil
}
struct PublicationTable: Codable, Equatable {
    var columns: [String]
    var rows: [[String]]
}
struct PublicationFigure: Codable, Equatable {
    var mediaType: String
    var data: Data?
    var sha256: String?
    var altText: String?
}
struct PublicationEvidenceLink: Codable, Equatable {
    var sourceID: String
    var sourceVersion: String
    var evidenceID: String?
    var locator: String?
    var url: String?
}
struct PublicationReference: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String?
    var authors: [String] = []
    var year: Int? = nil
    var containerTitle: String? = nil
    var volume: String? = nil
    var issue: String? = nil
    var pages: String? = nil
    var doi: String? = nil
    var url: String? = nil
    var type = "article-journal"
}
enum PublicationHash {
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
