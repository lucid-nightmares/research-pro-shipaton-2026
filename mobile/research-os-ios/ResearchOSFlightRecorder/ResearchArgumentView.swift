import SwiftUI
import UniformTypeIdentifiers

struct ResearchArgumentView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var capturing = false
    @State private var claiming = false
    @State private var error: String?
    @State private var archiveURL: URL?
    @State private var briefURL: URL?
    @State private var previewFile: ResearchPreviewFile?
    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            if project.classification == .syntheticDemo {
                                Label("Synthetic sample", systemImage: "doc.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text(project.scope.question).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            Text(nextAction(project)).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                        if let reason = workspace.mutationAccessReason(projectID: projectID) {
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let failure = workspace.mutationCapacityFailure {
                        Section("Change not saved") { Text(failure).foregroundStyle(AppTheme.coral) }
                    }
                    Section("Evidence") {
                        ForEach(project.argument?.sources ?? []) { source in
                            NavigationLink {
                                ArgumentSourceDetail(workspace: workspace, projectID: projectID, sourceID: source.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(source.title, systemImage: source.included ? "doc.text" : "doc.badge.ellipsis")
                                        .font(.headline)
                                    Text(source.excerpt).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    Text(source.included ? "Snapshot v\(source.version) · \(source.locator)" : "Excluded by a recorded decision")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }
                        }
                        Button("Capture evidence", systemImage: "plus") { capturing = true }
                            .disabled(!workspace.canMutateProject(id: projectID)).accessibilityIdentifier("capture-evidence")
                    }
                    Section("Argument") {
                        if (project.argument?.claims ?? []).isEmpty {
                            Text("State a conclusion, then link the exact evidence it depends on.").foregroundStyle(.secondary)
                        }
                        ForEach(project.argument?.claims ?? []) { claim in
                            NavigationLink {
                                ArgumentClaimDetail(workspace: workspace, projectID: projectID, claimID: claim.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    if claim.effectiveDisposition != .active {
                                        Label(claim.effectiveDisposition == .withdrawn ? "Withdrawn claim" : "Contested claim",
                                              systemImage: "exclamationmark.triangle")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    }
                                    Text(claim.text).font(.headline)
                                    let count = project.argument?.findings.filter { $0.claimID == claim.id }.count ?? 0
                                    Label(count == 0 ? "Review the evidence and prepare a defense" : "\(count) checks to review",
                                          systemImage: count == 0 ? "text.bubble" : "exclamationmark.bubble")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                        }
                        Button("Add a claim", systemImage: "text.badge.plus") { claiming = true }
                            .disabled(!workspace.canMutateProject(id: projectID)).accessibilityIdentifier("add-claim")
                    }
                    Section("Research Defense Pack") {
                        let reviewItems = project.argument?.exportReviewItems ?? [ArgumentExportReviewItem(
                            id: "no-argument", claimID: nil, message: "No argument or claims have been recorded for this brief.")]
                        Text(reviewItems.isEmpty ? "No structural review items detected. Human review of scientific meaning is still required." : "\(reviewItems.count) items to review before sharing. The brief includes every item; export remains available.")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("export-review-summary")
                        ForEach(Array(reviewItems.prefix(4))) { item in
                            Text(item.message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if reviewItems.count > 4 {
                            Text("\(reviewItems.count - 4) more in the exported brief.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Prepare brief & archive", systemImage: "shippingbox") {
                            perform {
                                archiveURL = try workspace.exportProjectFile(id: projectID)
                                briefURL = try workspace.exportResearchBriefFile(id: projectID)
                            }
                        }.accessibilityIdentifier("prepare-pack")
                        if let briefURL {
                            Button("Open readable brief") { previewFile = .init(url: briefURL) }
                            ShareLink("Share readable brief", item: briefURL)
                        }
                        if let archiveURL {
                            Button("Open reimportable archive") { previewFile = .init(url: archiveURL) }
                            ShareLink("Share reimportable archive", item: archiveURL)
                        }
                        NavigationLink("Manuscript styles") { PublicationWorkflowView(workspace: workspace, projectID: projectID) }.accessibilityIdentifier("publication-workflow")
                        Text("Includes your sources, argument, decisions, and defense history. Local integrity checks verify bytes and lineage; they do not validate scientific conclusions.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Deeper research tools") {
                        NavigationLink { ProjectWorkbenchView(workspace: workspace, projectID: projectID) } label: { Label("Scope, protocol & full workspace", systemImage: "square.grid.2x2") }
                        NavigationLink { ArgumentHistoryView(workspace: workspace, projectID: projectID) } label: { Label("Flight Recorder", systemImage: "clock.arrow.circlepath") }
                    }
                }.listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("Project unavailable", systemImage: "folder.badge.questionmark", description: Text("Return to the library to inspect its recovery state."))
            }
        }
        .navigationTitle(project?.title ?? "Project").navigationBarTitleDisplayMode(.inline).researchKeyboard()
        .sheet(item: $previewFile) { file in ResearchFilePreview(url: file.url) }
        .sheet(isPresented: $capturing) { ArgumentCaptureSheet(workspace: workspace, projectID: projectID) }
        .sheet(isPresented: $claiming) { ArgumentClaimSheet(workspace: workspace, projectID: projectID) }
        .alert("Action needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: project?.updatedAt) { _, _ in archiveURL = nil; briefURL = nil }
        .onAppear { workspace.selectedProjectID = projectID }
    }
    private func nextAction(_ project: ResearchProject) -> String {
        if project.argument?.sources.isEmpty ?? true { return "Next, capture an excerpt from a source you can inspect." }
        if project.argument?.claims.isEmpty ?? true { return "You have evidence. State what it supports, with its limitations." }
        return "Review your claims. Preview how a source change affects your argument, then prepare your defense."
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}

private struct ArgumentCaptureSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var origin = ""
    @State private var excerpt = ""
    @State private var locator = ""
    @State private var population = ""
    @State private var design: ArgumentStudyDesign = .unknown
    @State private var importing = false
    @State private var busy = false
    @State private var document: ArgumentDocumentSnapshot?
    @State private var selectedPage = 1
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Import text or PDF", systemImage: "doc.badge.plus") { importing = true }.disabled(busy).accessibilityIdentifier("import-source-file")
                    Text("Local files only. Text extraction preserves page markers; scanned pages need a checked transcription.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView("Reading local file…") }
                }
                if let document {
                    Section("Inspect extracted text") {
                        Picker("Source page", selection: $selectedPage) {
                            ForEach(1...document.pages.count, id: \.self) { page in Text("Page \(page)").tag(page) }
                        }.accessibilityIdentifier("source-page")
                        DisclosureGroup("Read selected page") {
                            Text(document.pages[selectedPage - 1]).font(.body).textSelection(.enabled)
                                .accessibilityIdentifier("extracted-page-text")
                        }
                        Button("Use selected page as excerpt") { excerpt = document.pages[selectedPage - 1] }
                        Text("Select or paste a quotation from this page. Matching normalizes whitespace only; it does not establish support for a claim.").font(.footnote).foregroundStyle(.secondary)
                        Label(document.contains(quote: excerpt, page: selectedPage) ? "Quote found on selected page" : "Quote does not match selected page",
                              systemImage: document.contains(quote: excerpt, page: selectedPage) ? "text.quote" : "exclamationmark.triangle")
                            .accessibilityIdentifier("quote-locator-result")
                        Text("Original SHA-256: \(document.originalSHA256)").font(.caption).textSelection(.enabled)
                    }
                }
                Section("Source snapshot") {
                    TextField("Source title", text: $title).accessibilityIdentifier("source-title")
                    TextField("Origin or citation", text: $origin).accessibilityIdentifier("source-origin")
                    if document == nil {
                        TextField("Page, section, or locator", text: $locator).accessibilityIdentifier("source-locator")
                    } else { Text(exactLocator).font(.footnote) }
                    TextField("Exact excerpt", text: $excerpt, axis: .vertical).lineLimit(5...14).accessibilityIdentifier("source-excerpt")
                }
                Section("What does this evidence describe?") {
                    TextField("Population / sample (optional)", text: $population).accessibilityIdentifier("source-population")
                    Picker("Study design", selection: $design) {
                        Text("Unknown / not established").tag(ArgumentStudyDesign.unknown)
                        Text("Observational").tag(ArgumentStudyDesign.observational)
                        Text("Experimental").tag(ArgumentStudyDesign.experimental)
                    }
                    Text("These are your descriptions of the source. The app cannot infer scientific validity from a label.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(AppTheme.coral) } }
            }
            .navigationTitle("Capture evidence").navigationBarTitleDisplayMode(.inline).researchKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { do { try ResearchFormDraftStore.clear(projectID: projectID, form: "capture"); dismiss() } catch { self.error = error.localizedDescription } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try workspace.addArgumentSource(projectID: projectID, title: title, origin: origin,
                                                               excerpt: excerpt, locator: exactLocator, population: population, design: design,
                                                               document: document, selectedPage: document == nil ? nil : selectedPage)
                            try ResearchFormDraftStore.clear(projectID: projectID, form: "capture")
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || (document != nil && !(document?.contains(quote: excerpt, page: selectedPage) ?? false)))
                    .accessibilityIdentifier("save-source")
                }
            }
            .interactiveDismissDisabled(!title.isEmpty || !excerpt.isEmpty)
            .onAppear {
                let draft = ResearchFormDraftStore.load(projectID: projectID, form: "capture")
                error = draft["_recovery_notice"]
                title = draft["title"] ?? ""; origin = draft["origin"] ?? ""; excerpt = draft["excerpt"] ?? ""
                locator = draft["locator"] ?? ""; population = draft["population"] ?? ""
                design = ArgumentStudyDesign(rawValue: draft["design"] ?? "") ?? .unknown
                if let saved = draft["document"], let data = saved.data(using: .utf8) {
                    document = try? JSONDecoder().decode(ArgumentDocumentSnapshot.self, from: data)
                }
                selectedPage = min(max(Int(draft["selectedPage"] ?? "1") ?? 1, 1), document?.pages.count ?? 1)
            }
            .onChange(of: [title, origin, excerpt, locator, population, design.rawValue, String(selectedPage), document?.originalSHA256 ?? ""]) { _, _ in
                do {
                    var fields = ["title": title, "origin": origin, "excerpt": excerpt, "locator": locator, "population": population, "design": design.rawValue, "selectedPage": String(selectedPage)]
                    if let document { fields["document"] = String(data: try JSONEncoder().encode(document), encoding: .utf8) }
                    try ResearchFormDraftStore.save(projectID: projectID, form: "capture", fields: fields)
                }
                catch { self.error = "Draft could not be saved: " + error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]) { result in
                switch result {
                case .failure(let error): self.error = error.localizedDescription
                case .success(let url):
                    busy = true
                    Task {
                        do {
                            let imported = try await Task.detached(priority: .userInitiated) { try ResearchContentImport.read(url) }.value
                            title = imported.title; origin = imported.origin; document = imported.document; selectedPage = 1
                            excerpt = ""; locator = imported.locator
                        } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
            }
        }
    }
    private var exactLocator: String {
        guard let document else { return locator }
        return "\(document.isPDF ? "PDF page" : "Text section") \(selectedPage) · exact quote (whitespace normalized)"
    }
}

private struct ArgumentClaimSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var limitation = ""
    @State private var selected: Set<UUID> = []
    @State private var relationship: ArgumentRelationship = .support
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("What are you claiming?") {
                    TextField("Claim wording", text: $text, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("claim-text")
                    TextField("Strongest limitation", text: $limitation, axis: .vertical).lineLimit(2...5)
                }
                Section("Evidence relationship") {
                    Picker("Relationship", selection: $relationship) {
                        Text("Supports").tag(ArgumentRelationship.support)
                        Text("Contradicts").tag(ArgumentRelationship.contradiction)
                        Text("Limits").tag(ArgumentRelationship.limitation)
                        Text("Missing support").tag(ArgumentRelationship.missing)
                    }
                    ForEach(workspace.project(id: projectID)?.argument?.sources ?? []) { source in
                        Toggle(source.title, isOn: Binding(get: { selected.contains(source.id) }, set: { if $0 { selected.insert(source.id) } else { selected.remove(source.id) } }))
                    }
                    Text("Select the source snapshots this claim depends on. Missing support remains an open question, not a finding of falsity.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(AppTheme.coral) }
            }
            .navigationTitle("Add a claim").navigationBarTitleDisplayMode(.inline).researchKeyboard()
            .interactiveDismissDisabled(!text.isEmpty || !limitation.isEmpty)
            .onAppear {
                let draft = ResearchFormDraftStore.load(projectID: projectID, form: "claim")
                error = draft["_recovery_notice"]
                text = draft["text"] ?? ""; limitation = draft["limitation"] ?? ""
                relationship = ArgumentRelationship(rawValue: draft["relationship"] ?? "") ?? .support
                selected = Set((draft["selected"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            }
            .onChange(of: [text, limitation, relationship.rawValue, selected.map(\.uuidString).sorted().joined(separator: ",")]) { _, _ in
                do { try ResearchFormDraftStore.save(projectID: projectID, form: "claim", fields: ["text": text, "limitation": limitation, "relationship": relationship.rawValue, "selected": selected.map(\.uuidString).sorted().joined(separator: ",")]) }
                catch { self.error = "Draft could not be saved: " + error.localizedDescription }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { do { try ResearchFormDraftStore.clear(projectID: projectID, form: "claim"); dismiss() } catch { self.error = error.localizedDescription } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try workspace.addArgumentClaim(projectID: projectID, text: text, sourceIDs: Array(selected).sorted { $0.uuidString < $1.uuidString }, relationship: relationship, limitation: limitation)
                            try ResearchFormDraftStore.clear(projectID: projectID, form: "claim")
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("save-claim")
                }
            }
        }
    }
}

private struct ArgumentSourceDetail: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let sourceID: UUID
    @State private var preview: ArgumentImpactPreview?
    @State private var reason = ""
    @State private var error: String?
    @State private var confirming = false
    @State private var revising = false
    private var source: ArgumentSource? { workspace.project(id: projectID)?.argument?.sources.first { $0.id == sourceID } }
    var body: some View {
        List {
            if let source {
                Section("Source snapshot v\(source.version)") {
                    Text(source.title).font(.headline)
                    LabeledContent("Origin", value: source.origin)
                    LabeledContent("Locator", value: source.locator)
                    LabeledContent("Population", value: source.population.isEmpty ? "Not established" : source.population)
                    Text(source.excerpt).textSelection(.enabled)
                    if let document = source.document, let page = source.selectedPage {
                        Label("Exact quote retained from page \(page)", systemImage: "text.quote")
                        Text("Original SHA-256: \(document.originalSHA256)").font(.caption).textSelection(.enabled)
                        DisclosureGroup("Reopen retained extracted text") {
                            Text(document.pages[page - 1]).textSelection(.enabled)
                        }
                        Text("Retained extracted text is available offline. The digest identifies imported bytes; neither matching text nor a digest validates the claim.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Revise source snapshot") { revising = true }
                        .disabled(!workspace.canMutateProject(id: projectID))
                }
                Section("What depends on this source?") {
                    Text("Preview an exclusion to see which claims and defense sessions need another look. Preview changes nothing.").foregroundStyle(.secondary)
                    Button("Preview exclusion", systemImage: "eye") {
                        do { preview = try workspace.previewEvidenceExclusion(projectID: projectID, sourceID: sourceID) }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("preview-exclusion")
                    if let preview {
                        Text("Preview only").font(.headline)
                        Text("\(preview.affectedClaimIDs.count) affected claims · \(preview.unaffectedClaimIDs.count) unchanged claims · \(preview.staleDefenseSessionIDs.count) affected defense sessions")
                        ForEach(workspace.project(id: projectID)?.argument?.claims.filter { preview.affectedClaimIDs.contains($0.id) } ?? []) { claim in
                            Label(claim.text, systemImage: "arrow.triangle.branch")
                        }
                        Text("Affected arguments require review before you describe their defense as current. You can always export the record, including its limitations.").font(.footnote).foregroundStyle(.secondary)
                        Button("Close preview") { self.preview = nil }
                    }
                }
                Section("Record a research decision") {
                    TextField("Why include or exclude this source?", text: $reason, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("source-decision-reason")
                    Button(source.included ? "Exclude source…" : "Include source again…") { confirming = true }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspace.canMutateProject(id: projectID))
                    Text("The snapshot and its history remain in your project.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(AppTheme.coral) }
        }
        .navigationTitle("Evidence").navigationBarTitleDisplayMode(.inline).researchKeyboard()
        .sheet(isPresented: $revising) { ArgumentSourceRevisionSheet(workspace: workspace, projectID: projectID, sourceID: sourceID) }
        .alert("Record this evidence change?", isPresented: $confirming) {
            Button("Confirm evidence change") {
                guard let source else { return }
                do {
                    try workspace.setArgumentSourceIncluded(projectID: projectID, sourceID: sourceID, included: !source.included, reason: reason)
                    reason = ""; preview = nil
                } catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This creates a new version and marks dependent defense sessions stale. The original remains in the local history.") }
    }
}

private struct ArgumentClaimDetail: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController
    let projectID: UUID
    let claimID: UUID
    @State private var repairing = false
    @State private var checkingSubscription = false
    @State private var premiumActionTask: Task<Void, Never>?
    @State private var editingRelationships = false
    @State private var openedDefenseSessionID: UUID?
    @State private var plus = false
    @State private var error: String?
    private var project: ResearchProject? { workspace.project(id: projectID) }
    private var claim: ArgumentClaim? { project?.argument?.claims.first { $0.id == claimID } }
    var body: some View {
        List {
            if let claim {
                Section("Claim v\(claim.version)") {
                    Text(claim.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                    if claim.effectiveDisposition != .active { Text("Status: " + claim.effectiveDisposition.rawValue).font(.subheadline) }
                    Text(claim.limitation.isEmpty ? "No limitation recorded yet." : claim.limitation).foregroundStyle(.secondary)
                }
                Section("Review") {
                    let findings = project?.argument?.findings.filter { $0.claimID == claimID } ?? []
                    if findings.isEmpty {
                        Text("No rule findings. Read the linked sources and use your judgment; a clean check is not a truth certificate.").foregroundStyle(.secondary)
                    }
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 8) {
                            if !finding.phrase.isEmpty { Text("“\(finding.phrase)”").font(.headline) }
                            Text(finding.explanation)
                            DisclosureGroup("Rule and source basis") {
                                Text("Deterministic check: \(finding.ruleID) · claim v\(finding.claimVersion)").font(.caption).textSelection(.enabled)
                                Text(finding.nextStep).font(.caption)
                                ForEach(project?.argument?.sources.filter { finding.evidenceIDs.contains($0.id) } ?? []) { source in
                                    Text("\(source.title) · v\(source.version) · \(source.locator)").font(.caption.weight(.semibold))
                                    Text(source.excerpt).font(.caption).textSelection(.enabled)
                                }
                            }
                        }.padding(.vertical, 7)
                    }
                    Button("Repair wording", systemImage: "pencil.line") { repairing = true }
                        .disabled(!workspace.canMutateProject(id: projectID)).accessibilityIdentifier("repair-wording")
                }
                Section("Linked evidence") {
                    Button("Edit evidence, limitations & status") { editingRelationships = true }
                        .disabled(!workspace.canMutateProject(id: projectID))
                    ForEach(project?.argument?.sources.filter { source in claim.links.contains { $0.sourceID == source.id } } ?? []) { source in
                        NavigationLink(source.title) { ArgumentSourceDetail(workspace: workspace, projectID: projectID, sourceID: source.id) }
                    }
                }
                Section("Defense Lab") {
                    Text("Answer in your own words. Link evidence and name a limitation. Coverage checks show what you filled in, not whether your reasoning is true.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Start standard defense", systemImage: "text.bubble") { startDefense(advanced: false) }
                        .disabled(!workspace.canMutateProject(id: projectID)).accessibilityIdentifier("start-standard-defense")
                    Button(checkingSubscription ? "Checking Plus…" : "Start advanced defense", systemImage: "text.bubble.fill") {
                        guard !checkingSubscription else { return }
                        checkingSubscription = true
                        premiumActionTask = Task {
                            defer { checkingSubscription = false }
                            let access = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
                            guard !Task.isCancelled else { return }
                            if access.grantsPlusAccess { startDefense(advanced: true) } else { plus = true }
                        }
                    }.disabled(checkingSubscription || !workspace.canMutateProject(id: projectID))
                    Text("Plus adds source-by-source challenges, alternative explanations, change-of-mind questions, and new sessions while retaining your history.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(project?.argument?.defenseSessions.filter { $0.claimID == claimID } ?? []) { session in
                        NavigationLink {
                            ArgumentDefenseView(workspace: workspace, projectID: projectID, sessionID: session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.advanced ? "Advanced defense" : "Standard defense").font(.headline)
                                Text(session.isStale ? "Evidence or wording changed · review needed" : "Open your answers")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(AppTheme.coral) }
        }
        .navigationTitle("Review & defend").navigationBarTitleDisplayMode(.inline).researchKeyboard()
        .onDisappear { premiumActionTask?.cancel() }
        .navigationDestination(item: $openedDefenseSessionID) { sessionID in
            ArgumentDefenseView(workspace: workspace, projectID: projectID, sessionID: sessionID)
        }
        .sheet(isPresented: $editingRelationships) { ArgumentRelationshipsSheet(workspace: workspace, projectID: projectID, claimID: claimID) }
        .sheet(isPresented: $repairing) { ArgumentRepairSheet(workspace: workspace, projectID: projectID, claimID: claimID) }
        .sheet(isPresented: $plus) { NavigationStack { SubscriptionView() } }
    }
    private func startDefense(advanced: Bool) {
        do { openedDefenseSessionID = try workspace.startArgumentDefense(projectID: projectID, claimID: claimID, advanced: advanced) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ArgumentRepairSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let claimID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var after = ""
    @State private var reason = ""
    @State private var proposal: ArgumentRepairProposal?
    @State private var error: String?
    private var claim: ArgumentClaim? { workspace.project(id: projectID)?.argument?.claims.first { $0.id == claimID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Before") { Text(claim?.text ?? "Claim unavailable").textSelection(.enabled) }
                Section("Your repair") {
                    Text("Narrow the population, reduce certainty, remove unsupported causality, or state a limitation. Keep the meaning grounded in your source.").font(.footnote).foregroundStyle(.secondary)
                    TextField("Revised wording", text: $after, axis: .vertical).lineLimit(3...9).accessibilityIdentifier("repair-after")
                    TextField("Reason and source basis", text: $reason, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("repair-reason")
                }
                if let proposal {
                    Section("Review before accepting") {
                        Text("Before: \(proposal.before)").foregroundStyle(.secondary)
                        Text("After: \(proposal.after)").font(.headline)
                        Text(proposal.reason)
                        Button("Accept repair") {
                            do { try workspace.acceptArgumentRepair(projectID: projectID, proposal: proposal); try ResearchFormDraftStore.clear(projectID: projectID, form: "repair-" + claimID.uuidString); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("accept-repair")
                        Text("Your explicit decision is recorded with the original, source versions, and a local event digest.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Preview repair") {
                        do { proposal = try workspace.proposeArgumentRepair(projectID: projectID, claimID: claimID, after: after, reason: reason) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Text(error).foregroundStyle(AppTheme.coral) }
            }
            .navigationTitle("Human-controlled repair").navigationBarTitleDisplayMode(.inline).researchKeyboard()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { do { try ResearchFormDraftStore.clear(projectID: projectID, form: "repair-" + claimID.uuidString); dismiss() } catch { self.error = error.localizedDescription } } } }
            .interactiveDismissDisabled(!reason.isEmpty)
            .onAppear {
                let draft = ResearchFormDraftStore.load(projectID: projectID, form: "repair-" + claimID.uuidString)
                error = draft["_recovery_notice"]
                after = draft["after"] ?? claim?.text ?? ""; reason = draft["reason"] ?? ""
            }
            .onChange(of: [after, reason]) { _, _ in
                do { try ResearchFormDraftStore.save(projectID: projectID, form: "repair-" + claimID.uuidString, fields: ["after": after, "reason": reason]) }
                catch { self.error = "Draft could not be saved: " + error.localizedDescription }
            }
            .onChange(of: after) { _, _ in proposal = nil }
            .onChange(of: reason) { _, _ in proposal = nil }
        }
    }
}

private struct ArgumentDefenseView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let sessionID: UUID
    @State private var answers: [String: String] = [:]
    @State private var citations: Set<UUID> = []
    @State private var limitation = ""
    @State private var error: String?
    @State private var saved = false
    private var eligibleSources: [ArgumentSource] {
        guard let session, let argument = workspace.project(id: projectID)?.argument,
              let claim = argument.claims.first(where: { $0.id == session.claimID }) else { return [] }
        return argument.sources.filter { source in (source.included && claim.links.contains { $0.sourceID == source.id }) || session.citedSourceIDs.contains(source.id) }
    }
    private var session: ArgumentDefenseSession? { workspace.project(id: projectID)?.argument?.defenseSessions.first { $0.id == sessionID } }
    var body: some View {
        Form {
            if let session {
                if session.isStale {
                    Section { Text("This session refers to older evidence or wording. Your exact answers are preserved; start a new session to reassess the current argument.").foregroundStyle(.secondary) }
                }
                ForEach(session.questions, id: \.id) { question in
                    Section(question.prompt) {
                        TextField("Your response", text: Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0; saved = false }), axis: .vertical)
                            .lineLimit(3...10).accessibilityIdentifier("defense-answer-\(question.id)")
                    }
                }
                Section("Cite the evidence you used") {
                    ForEach(eligibleSources) { source in
                        Toggle(source.title, isOn: Binding(get: { citations.contains(source.id) }, set: { if $0 { citations.insert(source.id) } else { citations.remove(source.id) }; saved = false }))
                    }
                    TextField("A limitation you acknowledge", text: $limitation, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("defense-limitation")
                        .onChange(of: limitation) { _, _ in saved = false }
                }
                Section("Coverage") {
                    Text("\(session.questions.filter { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) of \(session.questions.count) responses · \(citations.count) source references")
                    Text("A person must judge whether the answers actually support the argument.").font(.footnote).foregroundStyle(.secondary)
                    Button(saved ? "Answers saved" : "Save exact answers") {
                        do {
                            try workspace.saveArgumentDefense(projectID: projectID, sessionID: sessionID, answers: answers, citedSourceIDs: Array(citations).sorted { $0.uuidString < $1.uuidString }, limitation: limitation)
                            saved = true
                            try ResearchFormDraftStore.clear(projectID: projectID, form: "defense-" + sessionID.uuidString)
                        } catch { self.error = error.localizedDescription }
                    }.disabled(saved || session.isStale || !workspace.canMutateProject(id: projectID)).accessibilityIdentifier("save-defense")
                }
            }
            if let error { Text(error).foregroundStyle(AppTheme.coral) }
        }
        .navigationTitle(session?.advanced == true ? "Advanced Defense" : "Defense Lab").navigationBarTitleDisplayMode(.inline).researchKeyboard()
        .onAppear {
            if let session {
                let fields = ResearchFormDraftStore.load(projectID: projectID, form: "defense-" + sessionID.uuidString)
                error = fields["_recovery_notice"]
                let draft = ResearchDefenseDraft(session: session, fields: fields)
                answers = draft.answers; citations = draft.citations; limitation = draft.limitation
            }
        }
        .onChange(of: answers) { _, _ in saveDraft() }
        .onChange(of: citations) { _, _ in saveDraft() }
        .onChange(of: limitation) { _, _ in saveDraft() }
    }
    private func saveDraft() {
        guard session?.isStale == false else { return }
        let draft = ResearchDefenseDraft(answers: answers, citations: citations, limitation: limitation)
        do { try ResearchFormDraftStore.save(projectID: projectID, form: "defense-" + sessionID.uuidString, fields: draft.fields) }
        catch { self.error = "Draft could not be saved: " + error.localizedDescription }
    }

}

private struct ArgumentHistoryView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var events: [ResearchEventEnvelope] = []
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("Local history records what this installation saved. Hashes do not prove when research happened or prevent replacement of an entire history.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(Array(events.enumerated()), id: \.offset) { item in
                DisclosureGroup("Event \(item.offset + 1)") {
                    Text(String(describing: item.element)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            if let error { Text(error).foregroundStyle(AppTheme.coral) }
        }.navigationTitle("Flight Recorder")
        .task { do { events = try workspace.eventHistory(projectID: projectID) } catch { self.error = error.localizedDescription } }
    }
}

private struct ArgumentSourceRevisionSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let sourceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var excerpt = ""
    @State private var reason = ""
    @State private var error: String?
    @State private var expectedVersion: Int?
    private var source: ArgumentSource? { workspace.project(id: projectID)?.argument?.sources.first { $0.id == sourceID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Revise the snapshot") {
                    Text("The previous version remains in Flight Recorder. Dependent defenses will need review.").font(.footnote).foregroundStyle(.secondary)
                    if source?.document != nil {
                        Text("If edited wording no longer matches the imported page, this becomes an author-edited snapshot. Its prior import and locator remain in history.").font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("Revised exact excerpt", text: $excerpt, axis: .vertical).lineLimit(6...18)
                    TextField("Why did the source change?", text: $reason, axis: .vertical).lineLimit(2...5)
                }
                if let error { Text(error).foregroundStyle(AppTheme.coral) }
            }
            .navigationTitle("Revise source").navigationBarTitleDisplayMode(.inline).researchKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record revision") {
                        do { try workspace.reviseArgumentSource(projectID: projectID, sourceID: sourceID, excerpt: excerpt, reason: reason, expectedVersion: expectedVersion); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(excerpt == source?.excerpt || excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { excerpt = source?.excerpt ?? ""; expectedVersion = source?.version }
            .interactiveDismissDisabled(!reason.isEmpty)
        }
    }
}

private struct ArgumentRelationshipsSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let claimID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var relationships: [UUID: ArgumentRelationship] = [:]
    @State private var selected: Set<UUID> = []
    @State private var limitation = ""
    @State private var disposition: ArgumentClaimDisposition = .active
    @State private var reason = ""
    @State private var error: String?
    @State private var expectedVersion: Int?
    private var claim: ArgumentClaim? { workspace.project(id: projectID)?.argument?.claims.first { $0.id == claimID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Evidence relationships") {
                    ForEach(workspace.project(id: projectID)?.argument?.sources ?? []) { source in
                        Toggle(source.title, isOn: Binding(get: { selected.contains(source.id) }, set: { if $0 { selected.insert(source.id) } else { selected.remove(source.id) } }))
                        if selected.contains(source.id) {
                            Picker("Relationship to \(source.title)", selection: Binding(get: { relationships[source.id] ?? .support }, set: { relationships[source.id] = $0 })) {
                                Text("Supports").tag(ArgumentRelationship.support)
                                Text("Contradicts").tag(ArgumentRelationship.contradiction)
                                Text("Limits").tag(ArgumentRelationship.limitation)
                                Text("Missing support").tag(ArgumentRelationship.missing)
                            }
                        }
                    }
                }
                Section("Limit and decide") {
                    TextField("Limitation", text: $limitation, axis: .vertical).lineLimit(2...6)
                    Picker("Claim status", selection: $disposition) {
                        Text("Active").tag(ArgumentClaimDisposition.active)
                        Text("Contested").tag(ArgumentClaimDisposition.contested)
                        Text("Withdrawn").tag(ArgumentClaimDisposition.withdrawn)
                    }
                    TextField("Reason for this decision", text: $reason, axis: .vertical).lineLimit(2...6)
                    Text("Recording this change preserves the previous version and marks this claim’s defense sessions stale.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(AppTheme.coral) }
            }
            .navigationTitle("Evidence & limitations").navigationBarTitleDisplayMode(.inline).researchKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record decision") {
                        do {
                            let links = selected.sorted { $0.uuidString < $1.uuidString }.map { ArgumentEvidenceLink(sourceID: $0, relationship: relationships[$0] ?? .support) }
                            try workspace.reviseArgumentClaim(projectID: projectID, claimID: claimID, links: links, limitation: limitation, disposition: disposition, reason: reason, expectedVersion: expectedVersion)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(!reason.isEmpty)
            .onAppear {
                if let claim {
                    expectedVersion = claim.version
                    selected = Set(claim.links.map(\.sourceID)); relationships = Dictionary(uniqueKeysWithValues: claim.links.map { ($0.sourceID, $0.relationship) })
                    limitation = claim.limitation; disposition = claim.effectiveDisposition
                }
            }
        }
    }
}
