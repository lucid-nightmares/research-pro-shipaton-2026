import Foundation
import PDFKit
import CryptoKit

/// A durable extraction snapshot, not publisher authentication or scientific validation.
struct ArgumentDocumentSnapshot: Codable, Equatable, Sendable {
    let filename: String
    let originalSHA256: String
    let pages: [String]
    let isPDF: Bool
    let extractionVersion: Int

    func validate() throws {
        guard filename.count <= 250, !filename.isEmpty, pages.count > 0, pages.count <= 200,
              pages.reduce(0, { $0 + $1.count }) <= ResearchContentImport.maximumCharacters,
              originalSHA256.count == 64, originalSHA256.allSatisfy({ $0.isHexDigit }),
              extractionVersion == 1 else {
            throw ResearchArgumentError.invalid("The imported document snapshot is invalid or exceeds its supported size.")
        }
    }
    func contains(quote: String, page: Int) -> Bool {
        guard page >= 1, page <= pages.count else { return false }
        let needle = Self.normalized(quote)
        return !needle.isEmpty && Self.normalized(pages[page - 1]).contains(needle)
    }
    // Normalize whitespace only; spelling, numbers, case and punctuation stay exact.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

struct ImportedResearchContent: Sendable {
    let title: String
    let origin: String
    let excerpt: String
    let locator: String
    let document: ArgumentDocumentSnapshot
}

enum ResearchContentImportError: LocalizedError {
    case unsupported, tooLarge, unreadable, scanned, tooManyPages
    var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a UTF-8 text, Markdown, or PDF file. You can also paste an excerpt."
        case .tooLarge: "This file exceeds the local import limit (10 MB or 100,000 characters). Import a smaller excerpt."
        case .unreadable: "This file could not be read. Encrypted or damaged PDFs need a readable text copy."
        case .scanned: "No selectable text was found. OCR is not available here; paste a checked transcription and keep its page locator."
        case .tooManyPages: "This PDF has more than 200 pages. Choose a smaller section before importing."
        }
    }
}

/// Reads local documents only. Imported words are evidence data, never commands.
/// The caller runs parsing off the main actor and confirms the saved excerpt.
enum ResearchContentImport {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumCharacters = 100_000

    static func read(_ url: URL) throws -> ImportedResearchContent {
        guard url.isFileURL else { throw ResearchContentImportError.unsupported }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ResearchContentImportError.unsupported }
        guard let size = values.fileSize, size <= maximumBytes else { throw ResearchContentImportError.tooLarge }
        let suffix = url.pathExtension.lowercased()
        guard ["txt", "md", "text", "pdf"].contains(suffix) else { throw ResearchContentImportError.unsupported }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else { throw ResearchContentImportError.tooLarge }
        let text: String
        let locator: String
        let extractedPages: [String]
        if suffix == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw ResearchContentImportError.unreadable }
            guard pdf.pageCount <= 200 else { throw ResearchContentImportError.tooManyPages }
            var pages: [String] = [], rawPages: [String] = [], length = 0
            for page in 0..<pdf.pageCount {
                let value = pdf.page(at: page)?.string ?? ""
                rawPages.append(value)
                length += value.count
                guard length <= maximumCharacters else { throw ResearchContentImportError.tooLarge }
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pages.append("[Page \(page + 1)]\n\(value)")
                }
            }
            guard !pages.isEmpty else { throw ResearchContentImportError.scanned }
            text = pages.joined(separator: "\n\n")
            extractedPages = rawPages
            locator = "PDF pages 1–\(pdf.pageCount); page markers retained"
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw ResearchContentImportError.unreadable }
            text = decoded
            extractedPages = [decoded]
            locator = "Local text snapshot"
        }
        guard text.count <= maximumCharacters else { throw ResearchContentImportError.tooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchContentImportError.unreadable }
        return ImportedResearchContent(title: url.deletingPathExtension().lastPathComponent,
                                       origin: url.lastPathComponent, excerpt: text, locator: locator,
                                       document: ArgumentDocumentSnapshot(filename: url.lastPathComponent,
                                          originalSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                          pages: extractedPages, isPDF: suffix == "pdf", extractionVersion: 1))
    }
}

/// Partial forms are protected local data, scoped to their project and purged
/// with it. Explicit Cancel discards the form; interruption preserves it.
@MainActor enum ResearchFormDraftStore {
    private static var blockedPaths: Set<String> = []
    static func load(projectID: UUID, form: String) -> [String: String] {
        do {
            let url = try location(projectID: projectID, form: form)
            guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 500_000 else { throw ResearchContentImportError.tooLarge }
                let bytes = try Data(contentsOf: url)
                return try JSONDecoder().decode([String: String].self, from: bytes)
            } catch {
                // Keep the unreadable bytes. Never turn a corrupt draft into a
                // healthy empty draft and silently overwrite the only copy.
                let backup = url.appendingPathExtension("recovery-" + UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: url, to: backup)
                    return ["_recovery_notice": "A damaged partial draft was preserved in this project's recovery files. The committed project is unchanged. You can enter a new draft."]
                } catch {
                    blockedPaths.insert(url.path)
                    return ["_recovery_notice": "The partial draft could not be read or preserved safely. Draft writing is blocked; your committed project remains available."]
                }
            }
        } catch { return ["_recovery_notice": "Local draft storage could not be opened: " + error.localizedDescription] }
    }
    static func save(projectID: UUID, form: String, fields: [String: String]) throws {
        let url = try location(projectID: projectID, form: form)
        guard !blockedPaths.contains(url.path) else { throw ResearchContentImportError.unreadable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        let bytes = try JSONEncoder().encode(fields)
        guard bytes.count <= 500_000 else { throw ResearchContentImportError.tooLarge }
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
    }
    static func clear(projectID: UUID, form: String) throws {
        let url = try location(projectID: projectID, form: form)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private static func location(projectID: UUID, form: String) throws -> URL {
        try ResearchWorkspaceStore.defaultStorageDirectory().appendingPathComponent("FormDrafts", isDirectory: true)
            .appendingPathComponent(projectID.uuidString.lowercased(), isDirectory: true).appendingPathComponent(form + ".json")
    }
}

/// Partial Defense Lab work includes source selections, not only typed prose.
/// Absence of the citations field means a legacy draft; an empty field means
/// the researcher explicitly deselected every citation.
struct ResearchDefenseDraft: Equatable {
    var answers: [String: String]
    var citations: Set<UUID>
    var limitation: String

    init(answers: [String: String], citations: Set<UUID>, limitation: String) {
        self.answers = answers
        self.citations = citations
        self.limitation = limitation
    }

    init(session: ArgumentDefenseSession, fields: [String: String]) {
        answers = session.answers
        for question in session.questions {
            if let value = fields[question.id] { answers[question.id] = value }
        }
        limitation = fields["_limitation"] ?? session.limitation
        if let raw = fields["_citations"] {
            citations = Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        } else {
            citations = Set(session.citedSourceIDs)
        }
    }

    var fields: [String: String] {
        var result = answers
        result["_limitation"] = limitation
        result["_citations"] = citations.map(\.uuidString).sorted().joined(separator: ",")
        return result
    }
}
