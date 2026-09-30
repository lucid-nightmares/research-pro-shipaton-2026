import Foundation

/// Versioned local research content. Rules inspect explicit wording and documented
/// relationships; they do not determine scientific truth or send text to a model.
enum ResearchArgumentLimits {
    static let maximumArchiveBytes = 20_000_000
}

enum ArgumentStudyDesign: String, Codable, CaseIterable {
    case unknown, observational, experimental
}
enum ArgumentRelationship: String, Codable, CaseIterable {
    case support, contradiction, limitation, missing
}
struct ArgumentSource: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var version: Int = 1
    var title: String
    var origin: String
    var excerpt: String
    var locator: String
    var population: String
    var design: ArgumentStudyDesign
    var included: Bool = true
    var document: ArgumentDocumentSnapshot? = nil
    var selectedPage: Int? = nil
}
struct ArgumentEvidenceLink: Codable, Equatable {
    var sourceID: UUID
    var relationship: ArgumentRelationship
}
enum ArgumentClaimDisposition: String, Codable, CaseIterable {
    case active, contested, withdrawn
}
struct ArgumentClaim: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var version: Int = 1
    var text: String
    var limitation: String
    var links: [ArgumentEvidenceLink]
    var disposition: ArgumentClaimDisposition? = nil
    var effectiveDisposition: ArgumentClaimDisposition { disposition ?? .active }
}
struct ArgumentFinding: Equatable, Identifiable {
    let id: String
    let claimID: UUID
    let phrase: String
    let explanation: String
    let ruleID: String
    let evidenceIDs: [UUID]
    let claimVersion: Int
    let evidenceVersions: [String: Int]
    var nextStep: String { "Inspect the quoted source, then narrow the claim, document a limitation, or attach stronger evidence." }
}
struct ArgumentExportReviewItem: Equatable, Identifiable {
    let id: String
    let claimID: UUID?
    let message: String
}
struct ArgumentRepairProposal: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let claimID: UUID
    let before: String
    let after: String
    let reason: String
    let baseDigest: String
}
struct ArgumentRepairDecision: Codable, Equatable, Identifiable {
    let id: UUID
    let proposal: ArgumentRepairProposal
    let actor: String
    let acceptedAt: String
}
struct ArgumentDefenseQuestion: Codable, Equatable, Identifiable {
    let id: String
    let prompt: String
}
struct ArgumentDefenseSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let claimID: UUID
    let advanced: Bool
    let basisDigest: String
    let questions: [ArgumentDefenseQuestion]
    var answers: [String: String] = [:]
    var citedSourceIDs: [UUID] = []
    var limitation: String = ""
    var isStale: Bool = false
    var answeredAt: String? = nil
    var completedChecks: Int {
        (questions.allSatisfy { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? 1 : 0)
        + (citedSourceIDs.isEmpty ? 0 : 1)
        + (limitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
    var coverageSummary: String { coverageDescription }
    var coverageDescription: String { "\(completedChecks)/3 explicit coverage checks: answers, linked source, limitation. Human review is still required." }
}
struct ArgumentImpactPreview: Equatable {
    let sourceID: UUID
    let affectedClaimIDs: [UUID]
    let unaffectedClaimIDs: [UUID]
    let staleDefenseSessionIDs: [UUID]
    var explanation: String { "Preview only. \(affectedClaimIDs.count) dependent claim(s) need review; \(unaffectedClaimIDs.count) unrelated claim(s) remain unchanged. Export stays available." }
}
struct ArgumentCommand: Codable, Equatable {
    var id: UUID = UUID()
    let action: Action
    enum Action: Codable, Equatable {
        case sourceAdded(ArgumentSource)
        case sourceRevised(source: ArgumentSource, baseDigest: String, reason: String)
        case claimAdded(ArgumentClaim)
        case claimRevised(claim: ArgumentClaim, baseDigest: String, reason: String)
        case repairAccepted(proposal: ArgumentRepairProposal, at: String)
        case defenseStarted(ArgumentDefenseSession)
        case defenseAnswered(sessionID: UUID, answers: [String: String], sourceIDs: [UUID], limitation: String, at: String)
    }
}
enum ResearchArgumentError: LocalizedError, Equatable {
    case invalid(String), stale, premiumRequired, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .stale: "The claim or its source changed. Review the current version and create a fresh proposal."
        case .premiumRequired: "Starting advanced Defense Lab requires a current Research Pro Plus entitlement. Existing work remains readable and exportable."
        case .unavailable: "This project is unavailable for editing. Its retained work remains readable and exportable."
        }
    }
}
struct ResearchArgument: Codable, Equatable {
    var schemaVersion: Int = 1
    var sources: [ArgumentSource] = []
    var claims: [ArgumentClaim] = []
    var repairs: [ArgumentRepairDecision] = []
    var defenseSessions: [ArgumentDefenseSession] = []
    var appliedOperationIDs: [UUID] = []
    var lastCommand: ArgumentCommand? = nil
    static let ruleVersion = "research-pro-structural-rules/2"

    /// Derived at read time from recorded relationships and versions. A clear
    /// structural review is not a verdict about a paper or scientific claim.
    var exportReviewItems: [ArgumentExportReviewItem] {
        if claims.isEmpty {
            return [ArgumentExportReviewItem(id: "no-claims", claimID: nil,
                message: "No claims have been recorded for this brief.")]
        }
        var items: [ArgumentExportReviewItem] = []
        let structuralFindings = findings
        for claim in claims {
            let prefix = "Claim \(claim.id.uuidString.prefix(8))"
            if claim.effectiveDisposition == .withdrawn {
                items.append(ArgumentExportReviewItem(id: "\(claim.id)-withdrawn", claimID: claim.id,
                    message: "\(prefix) is withdrawn and must not be presented as a current conclusion."))
                continue
            }
            if claim.effectiveDisposition == .contested {
                items.append(ArgumentExportReviewItem(id: "\(claim.id)-contested", claimID: claim.id,
                    message: "\(prefix) is contested; explain the disagreement before presenting it as a conclusion."))
            }
            let linked = sources.filter { source in claim.links.contains { $0.sourceID == source.id } }
            let included = linked.filter { $0.included }
            if !linked.isEmpty && included.count != linked.count {
                items.append(ArgumentExportReviewItem(id: "\(claim.id)-excluded-source", claimID: claim.id,
                    message: "\(prefix) links to an excluded source; inspect whether its evidence relationship still belongs in the brief."))
            }
            for source in included {
                if source.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    source.locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(ArgumentExportReviewItem(id: "\(claim.id)-source-\(source.id)-trace", claimID: claim.id,
                        message: "\(prefix): source \(source.id) needs an origin and exact locator so another person can inspect the passage."))
                }
                if source.document == nil {
                    items.append(ArgumentExportReviewItem(id: "\(claim.id)-source-\(source.id)-unbound", claimID: claim.id,
                        message: "\(prefix): source \(source.id) has a manual locator that is not bound to an imported file. Confirm the original passage and exact location before sharing."))
                }
            }
            for finding in structuralFindings where finding.claimID == claim.id {
                items.append(ArgumentExportReviewItem(id: finding.id, claimID: claim.id,
                    message: "\(prefix): \(finding.explanation)"))
            }
            let sessions = defenseSessions.filter { $0.claimID == claim.id }
            if sessions.isEmpty {
                items.append(ArgumentExportReviewItem(id: "\(claim.id)-no-defense", claimID: claim.id,
                    message: "\(prefix) has no recorded defense of its evidence, alternatives, and limits."))
            } else if let latest = sessions.last, latest.isStale || latest.completedChecks < 3 {
                items.append(ArgumentExportReviewItem(id: "\(claim.id)-defense-review", claimID: claim.id,
                    message: "\(prefix)'s latest defense is \(latest.isStale ? "stale after a source or claim change" : "incomplete"); review it against the current evidence."))
            }
        }
        return items
    }

    func basisDigest(claimID: UUID) throws -> String {
        guard let claim = claims.first(where: { $0.id == claimID }) else { throw ResearchArgumentError.invalid("Select an existing claim.") }
        let linked = sources.filter { source in claim.links.contains { $0.sourceID == source.id } }
        return try CanonicalJSON.digest(.object([
            "claim": try CanonicalJSON.value(from: claim),
            "sources": .array(try linked.map { try CanonicalJSON.value(from: $0) })
        ]))
    }
    func proposal(claimID: UUID, after: String, reason: String) throws -> ArgumentRepairProposal {
        guard let claim = claims.first(where: { $0.id == claimID }) else { throw ResearchArgumentError.invalid("Select an existing claim.") }
        try Self.requireText(after, limit: 10_000, name: "Revised claim")
        try Self.requireText(reason, limit: 4_000, name: "Repair reason")
        guard after != claim.text else { throw ResearchArgumentError.invalid("Write a revised claim before accepting a repair.") }
        return ArgumentRepairProposal(claimID: claimID, before: claim.text, after: after, reason: reason, baseDigest: try basisDigest(claimID: claimID))
    }
    func impact(sourceID: UUID) throws -> ArgumentImpactPreview {
        guard sources.contains(where: { $0.id == sourceID }) else { throw ResearchArgumentError.invalid("Select an existing source.") }
        let affected = claims.filter { $0.links.contains { $0.sourceID == sourceID } }.map(\.id)
        return ArgumentImpactPreview(sourceID: sourceID, affectedClaimIDs: affected,
            unaffectedClaimIDs: claims.filter { !affected.contains($0.id) }.map(\.id),
            staleDefenseSessionIDs: defenseSessions.filter { affected.contains($0.claimID) }.map(\.id))
    }
    func defense(claimID: UUID, advanced: Bool) throws -> ArgumentDefenseSession {
        guard let claim = claims.first(where: { $0.id == claimID }) else { throw ResearchArgumentError.invalid("Select an existing claim.") }
        let linked = sources.filter { source in source.included && claim.links.contains { $0.sourceID == source.id } }
        let titles = linked.map(\.title).joined(separator: ", ")
        var questions = [
            ArgumentDefenseQuestion(id: "basis", prompt: "Which exact passage in \(titles.isEmpty ? "your sources" : titles) supports ‘\(claim.text)’?"),
            ArgumentDefenseQuestion(id: "change", prompt: "What observation would change this conclusion?"),
            ArgumentDefenseQuestion(id: "limit", prompt: "What is the strongest limitation or alternative explanation?")
        ]
        if advanced {
            questions += linked.map { ArgumentDefenseQuestion(id: "source-\($0.id.uuidString)", prompt: "If ‘\($0.title)’ stopped supporting this claim, what would remain? Cite another source or acknowledge the gap.") }
            questions += [
                ArgumentDefenseQuestion(id: "contradiction", prompt: "Compare the strongest supporting passage with contradictory or missing evidence. What remains unresolved?"),
                ArgumentDefenseQuestion(id: "alternative", prompt: "Give a competing explanation and a feasible observation that would distinguish it from your claim."),
                ArgumentDefenseQuestion(id: "scope", prompt: "Specify the population, timeframe and outcome to which you would limit this conclusion.")
            ]
        }
        return ArgumentDefenseSession(claimID: claimID, advanced: advanced, basisDigest: try basisDigest(claimID: claimID), questions: questions)
    }
    func applying(_ command: ArgumentCommand) throws -> ResearchArgument {
        guard schemaVersion == 1 else { throw ResearchArgumentError.invalid("Unsupported research argument schema.") }
        if appliedOperationIDs.contains(command.id) { return self }
        guard appliedOperationIDs.count < 10_000 else { throw ResearchArgumentError.invalid("This project reached the bounded operation limit. Export your research before continuing.") }
        var result = self
        switch command.action {
        case .sourceAdded(let source):
            try Self.validate(source)
            guard source.version == 1, !sources.contains(where: { $0.id == source.id }), sources.count < 100 else { throw ResearchArgumentError.invalid("Duplicate source or the 100-source project limit was reached.") }
            result.sources.append(source)
        case .sourceRevised(let source, let digest, let reason):
            try Self.validate(source)
            try Self.requireText(reason, limit: 4_000, name: "Source change reason")
            guard let index = sources.firstIndex(where: { $0.id == source.id }),
                  try CanonicalJSON.digest(sources[index]) == digest,
                  source.version == sources[index].version + 1 else { throw ResearchArgumentError.stale }
            result.sources[index] = source
            let affected = try impact(sourceID: source.id).affectedClaimIDs
            for index in result.defenseSessions.indices where affected.contains(result.defenseSessions[index].claimID) { result.defenseSessions[index].isStale = true }
        case .claimAdded(let claim):
            try Self.requireText(claim.text, limit: 10_000, name: "Claim")
            guard claim.limitation.count <= 4_000, claim.version == 1, claims.count < 100,
                  !claims.contains(where: { $0.id == claim.id }), Set(claim.links.map(\.sourceID)).count == claim.links.count,
                  claim.links.allSatisfy({ link in sources.contains { $0.id == link.sourceID } }) else { throw ResearchArgumentError.invalid("Claim links must address existing sources without duplicates; at most 100 claims are allowed.") }
            result.claims.append(claim)
        case .claimRevised(let claim, let digest, let reason):
            try Self.requireText(reason, limit: 4_000, name: "Claim decision reason")
            guard let index = claims.firstIndex(where: { $0.id == claim.id }),
                  try basisDigest(claimID: claim.id) == digest,
                  claim.version == claims[index].version + 1, claim.text == claims[index].text else { throw ResearchArgumentError.stale }
            guard claim.limitation.count <= 4_000, Set(claim.links.map(\.sourceID)).count == claim.links.count,
                  claim.links.allSatisfy({ link in sources.contains { $0.id == link.sourceID } }) else { throw ResearchArgumentError.invalid("Link existing sources once each and keep the limitation within 4,000 characters.") }
            result.claims[index] = claim
            for index in result.defenseSessions.indices where result.defenseSessions[index].claimID == claim.id { result.defenseSessions[index].isStale = true }
        case .repairAccepted(let proposal, let at):
            if repairs.contains(where: { $0.id == proposal.id }) { return self }
            guard let index = claims.firstIndex(where: { $0.id == proposal.claimID }),
                  claims[index].text == proposal.before,
                  try basisDigest(claimID: proposal.claimID) == proposal.baseDigest else { throw ResearchArgumentError.stale }
            try Self.requireText(proposal.after, limit: 10_000, name: "Revised claim")
            try Self.requireText(proposal.reason, limit: 4_000, name: "Repair reason")
            guard proposal.before != proposal.after else { throw ResearchArgumentError.invalid("The repair must change the claim.") }
            try ResearchOSValidation.requireTimestamp(at, field: "repair.accepted_at")
            result.claims[index].text = proposal.after
            result.claims[index].version += 1
            result.repairs.append(ArgumentRepairDecision(id: proposal.id, proposal: proposal, actor: "human:local", acceptedAt: at))
            for index in result.defenseSessions.indices where result.defenseSessions[index].claimID == proposal.claimID { result.defenseSessions[index].isStale = true }
        case .defenseStarted(let session):
            let expected = try defense(claimID: session.claimID, advanced: session.advanced)
            guard session.questions == expected.questions, session.basisDigest == expected.basisDigest,
                  session.answers.isEmpty, session.citedSourceIDs.isEmpty, session.limitation.isEmpty,
                  !session.isStale, session.answeredAt == nil, defenseSessions.count < 100,
                  !defenseSessions.contains(where: { $0.id == session.id }) else { throw ResearchArgumentError.invalid("Defense session must start from the current claim and evidence.") }
            result.defenseSessions.append(session)
        case .defenseAnswered(let id, let answers, let sourceIDs, let limitation, let at):
            guard let index = defenseSessions.firstIndex(where: { $0.id == id }) else { throw ResearchArgumentError.invalid("Select an existing defense session.") }
            let session = defenseSessions[index]
            if session.answeredAt != nil && session.answers == answers && session.citedSourceIDs == sourceIDs && session.limitation == limitation { return self }
            guard !session.isStale, try basisDigest(claimID: session.claimID) == session.basisDigest else { throw ResearchArgumentError.stale }
            let allowed = Set(session.questions.map(\.id))
            guard answers.keys.allSatisfy({ allowed.contains($0) }), answers.values.allSatisfy({ $0.count <= 10_000 }), limitation.count <= 4_000,
                  Set(sourceIDs).count == sourceIDs.count,
                  sourceIDs.allSatisfy({ id in sources.contains { $0.id == id && $0.included } && claims.first(where: { $0.id == session.claimID })!.links.contains { $0.sourceID == id } }) else { throw ResearchArgumentError.invalid("Use bounded answers and cite sources linked to this claim.") }
            try ResearchOSValidation.requireTimestamp(at, field: "defense.answered_at")
            result.defenseSessions[index].answers = answers
            result.defenseSessions[index].citedSourceIDs = sourceIDs
            result.defenseSessions[index].limitation = limitation
            result.defenseSessions[index].answeredAt = at
        }
        result.appliedOperationIDs.append(command.id)
        result.lastCommand = command
        return result
    }
    var findings: [ArgumentFinding] {
        claims.filter { $0.effectiveDisposition != .withdrawn }.flatMap { claim -> [ArgumentFinding] in
            let relevant = sources.filter { source in source.included && claim.links.contains { $0.sourceID == source.id } }
            let support = relevant.filter { source in claim.links.contains { $0.sourceID == source.id && $0.relationship == .support } }
            func finding(_ rule: String, _ phrase: String, _ explanation: String) -> ArgumentFinding {
                ArgumentFinding(id: "\(claim.id)-v\(claim.version)-\(rule)", claimID: claim.id, phrase: phrase, explanation: explanation,
                    ruleID: "\(Self.ruleVersion):\(rule)", evidenceIDs: relevant.map(\.id), claimVersion: claim.version,
                    evidenceVersions: Dictionary(uniqueKeysWithValues: relevant.map { ($0.id.uuidString, $0.version) }))
            }
            var result: [ArgumentFinding] = []
            if support.isEmpty { result.append(finding("missing-support", claim.text, "No included source is explicitly linked as support. This is a documentation gap, not proof the claim is false.")) }
            if let phrase = Self.positivePhrase(in: claim.text, pattern: "\\b(all students|everyone|every person|all people|always|never)\\b"), support.contains(where: { !$0.population.isEmpty }) {
                result.append(finding("scope-review", phrase, "This universal wording may exceed the documented population: \(support.map(\.population).filter { !$0.isEmpty }.joined(separator: "; ")). Check the scope with a human reviewer."))
            }
            if let phrase = Self.positivePhrase(in: claim.text, pattern: "\\b(causes?|caused|leads? to|improves?|improved|prevents?|proves?|established causality)\\b"), support.contains(where: { $0.design == .observational }) {
                result.append(finding("causal-review", phrase, "A linked source is described as observational. This wording may imply causality the documented design does not establish."))
            }
            if let phrase = Self.positivePhrase(in: claim.text, pattern: "\\b(definitely|definitively|certainly|guarantees?|proves?|undeniably)\\b") {
                result.append(finding("certainty-review", phrase, "This phrase asserts strong certainty. Inspect the quoted evidence and qualify it if that certainty is unsupported; this rule does not assess scientific truth."))
            }
            if claim.links.contains(where: { $0.relationship == .contradiction && relevant.map(\.id).contains($0.sourceID) }) {
                result.append(finding("contradiction-review", claim.text, "A source is explicitly linked as contradictory. Explain the disagreement or revise the conclusion."))
            }
            return result
        }
    }
    private static func positivePhrase(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let prefix = ns.substring(to: match.range.location).lowercased().components(separatedBy: CharacterSet(charactersIn: ".!?;\n")).last ?? ""
            // Abstain on negated/quoted/uncertain formulations rather than asserting a verdict.
            let suppressed = prefix.range(of: "\\b(not|no|cannot|can't|doesn't|didn't|whether|may|might|could|unlikely|without)\\b", options: .regularExpression) != nil
            if !suppressed { return ns.substring(with: match.range) }
        }
        return nil
    }
    private static func validate(_ source: ArgumentSource) throws {
        try requireText(source.title, limit: 200, name: "Source title")
        try requireText(source.excerpt, limit: 100_000, name: "Exact excerpt")
        guard source.origin.count <= 2_000, source.locator.count <= 1_000, source.population.count <= 2_000, source.version > 0 else { throw ResearchArgumentError.invalid("Source metadata exceeds its supported size.") }
        if let document = source.document {
            try document.validate()
            guard let page = source.selectedPage, document.contains(quote: source.excerpt, page: page),
                  source.locator == "\(document.isPDF ? "PDF page" : "Text section") \(page) · exact quote (whitespace normalized)" else {
                throw ResearchArgumentError.invalid("The quote does not match its selected page. Select an exact passage and locator from the imported document.")
            }
        } else if source.selectedPage != nil {
            throw ResearchArgumentError.invalid("A selected page needs its retained document snapshot.")
        }
    }
    private static func requireText(_ text: String, limit: Int, name: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= limit else { throw ResearchArgumentError.invalid("\(name) must contain 1–\(limit) characters.") }
    }
}
