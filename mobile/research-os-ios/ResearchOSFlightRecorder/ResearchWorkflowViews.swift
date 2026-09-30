import SwiftUI

struct ScopeProtocolView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID

    @State private var showingFreeze = false
    @State private var showingAmendment = false

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        Form {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                }
                Section("Research scope") {
                    workflowEditor(
                        "Question",
                        prompt: "What exactly are you trying to learn?",
                        text: projectBinding(\.scope.question, fallback: project.scope.question)
                    )
                    workflowEditor(
                        "Population or material",
                        prompt: "Who or what could the record describe?",
                        text: projectBinding(\.scope.population, fallback: project.scope.population)
                    )
                    workflowEditor(
                        "Variables and measures",
                        prompt: "Name the inputs, outcomes, units, and timing.",
                        text: projectBinding(\.scope.variables, fallback: project.scope.variables)
                    )
                    workflowEditor(
                        "Exclusions and non-claims",
                        prompt: "What is explicitly outside the project?",
                        text: projectBinding(\.scope.exclusions, fallback: project.scope.exclusions)
                    )
                }
                .disabled(project.protocolRecord.frozenByHuman)

                Section("Protocol") {
                    workflowEditor(
                        "Method",
                        prompt: "Describe steps, comparisons, controls, and stopping rules.",
                        text: projectBinding(\.protocolRecord.method, fallback: project.protocolRecord.method)
                    )
                    workflowEditor(
                        "Primary outcome",
                        prompt: "Which outcome is primary, and how is it computed?",
                        text: projectBinding(\.protocolRecord.primaryOutcome, fallback: project.protocolRecord.primaryOutcome)
                    )
                    workflowEditor(
                        "Change policy",
                        prompt: "How will pre-result and post-result changes be labeled?",
                        text: projectBinding(\.protocolRecord.changePolicy, fallback: project.protocolRecord.changePolicy)
                    )
                }
                .disabled(project.protocolRecord.frozenByHuman)

                Section("Human protocol decision") {
                    if project.protocolRecord.frozenByHuman {
                        Label("Marked frozen by you", systemImage: "lock.fill")
                            .foregroundStyle(AppTheme.moss)
                        Text("A freeze records your boundary. It is not preregistration, ethics approval, or external review.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Start a disclosed amendment", systemImage: "pencil.and.outline") {
                            showingAmendment = true
                        }
                    } else {
                        Label("Editable draft", systemImage: "pencil")
                            .foregroundStyle(AppTheme.gold)
                        Button("Mark protocol frozen", systemImage: "lock") { showingFreeze = true }
                            .disabled(!canFreeze(project))
                        Text("Complete the question, population, method, primary outcome, and change policy first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Scope & protocol")
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Mark this protocol frozen?", isPresented: $showingFreeze, titleVisibility: .visible) {
            Button("Record my freeze decision") {
                workspace.setProtocolFrozen(projectID: projectID, isFrozen: true)
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("You remain the authority. Research OS records the state but does not preregister or approve the protocol.")
        }
        .confirmationDialog("Start a disclosed amendment?", isPresented: $showingAmendment, titleVisibility: .visible) {
            Button("Unlock as amendment") {
                workspace.setProtocolFrozen(projectID: projectID, isFrozen: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Proof Gate will reopen. Describe the change and its timing in the protocol before freezing again.")
        }
    }

    private func canFreeze(_ project: ResearchProject) -> Bool {
        [
            project.scope.question,
            project.scope.population,
            project.protocolRecord.method,
            project.protocolRecord.primaryOutcome,
            project.protocolRecord.changePolicy
        ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func projectBinding<Value>(_ path: WritableKeyPath<ResearchProject, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { workspace.project(id: projectID)?[keyPath: path] ?? fallback },
            set: { value in workspace.updateProject(id: projectID) { $0[keyPath: path] = value } }
        )
    }
}

struct ClaimsEvidenceView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var showingAdd = false

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        List {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                    Text("A link means a person connected the claim and evidence. It does not mean the source is true, sufficient, or independently reproduced.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if project.claims.isEmpty {
                    ContentUnavailableView(
                        "No claims linked",
                        systemImage: "link.badge.plus",
                        description: Text("Add one claim, its exact evidence pointer, and the limitation that must travel with it.")
                    )
                } else {
                    ForEach(project.claims) { link in
                        Section {
                            ClaimEvidenceCard(
                                link: link,
                                support: claimBinding(link.id, \.support, fallback: link.support),
                                reviewed: claimBinding(link.id, \.humanReviewed, fallback: link.humanReviewed)
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Claims & evidence")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add claim", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddClaimSheet(workspace: workspace, projectID: projectID)
        }
    }

    private func claimBinding<Value>(
        _ claimID: UUID,
        _ path: WritableKeyPath<ClaimEvidenceLink, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                workspace.project(id: projectID)?.claims.first(where: { $0.id == claimID })?[keyPath: path] ?? fallback
            },
            set: { value in
                workspace.updateProject(id: projectID) { project in
                    guard let index = project.claims.firstIndex(where: { $0.id == claimID }) else { return }
                    project.claims[index][keyPath: path] = value
                }
            }
        )
    }
}

private struct ClaimEvidenceCard: View {
    let link: ClaimEvidenceLink
    @Binding var support: EvidenceSupport
    @Binding var reviewed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(link.claim).font(.headline).textSelection(.enabled)
            LabeledContent("Evidence pointer", value: link.evidencePointer.isEmpty ? "Missing" : link.evidencePointer)
            LabeledContent("Limitation", value: link.limitation.isEmpty ? "Missing" : link.limitation)
            Picker("Support state", selection: $support) {
                ForEach(EvidenceSupport.allCases, id: \.self) { state in Text(state.label).tag(state) }
            }
            Toggle("I reviewed this exact link", isOn: $reviewed)
            if reviewed {
                Text("Human-reviewed link — not independently validated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.moss)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct AddClaimSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var claim = ""
    @State private var evidence = ""
    @State private var limitation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Claim") {
                    TextField("Exact claim wording", text: $claim, axis: .vertical).lineLimit(3...8)
                }
                Section("Proof link") {
                    TextField("Exact source, row, figure, output, or file pointer", text: $evidence, axis: .vertical)
                    TextField("Limitation that must travel", text: $limitation, axis: .vertical)
                }
                Section {
                    Text("The link begins unreviewed and uses a conservative support state. You must review it explicitly in the project.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add claim link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        workspace.addClaim(projectID: projectID, claim: claim, evidence: evidence, limitation: limitation)
                        dismiss()
                    }
                    .disabled(claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ProofGateView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var showingDecision = false

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        ScrollView {
            if let project {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ProjectClassificationBanner(project: project)
                    SectionCard(title: "Structural readiness", systemImage: "checklist") {
                        gateCheck(
                            "Question, population, variables, and exclusions are explicit",
                            ready: [
                                project.scope.question,
                                project.scope.population,
                                project.scope.variables,
                                project.scope.exclusions,
                            ].allSatisfy { !$0.trimmedForWorkflow.isEmpty }
                        )
                        gateCheck("Protocol freeze recorded by a person", ready: project.protocolRecord.frozenByHuman)
                        gateCheck("Every claim points to evidence", ready: !project.claims.isEmpty && project.claims.allSatisfy { !$0.evidencePointer.trimmedForWorkflow.isEmpty })
                        gateCheck("Every claim carries a limitation and human review", ready: !project.claims.isEmpty && project.claims.allSatisfy { !$0.limitation.trimmedForWorkflow.isEmpty && $0.humanReviewed })
                    }
                    SectionCard(title: "Decision boundary", systemImage: "hand.raised") {
                        if let date = project.proofGateConfirmedAt {
                            StatusPill(text: "Human readiness decision recorded", color: AppTheme.moss)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text("This means the local structure was ready for your next review. It does not mean the evidence is true, the analysis was rerun, or an external reviewer approved it.")
                                .foregroundStyle(.secondary)
                        } else {
                            StatusPill(
                                text: project.proofGateReadiness.isReadyForHumanDecision ? "Ready for your decision" : "Open work remains",
                                color: project.proofGateReadiness.isReadyForHumanDecision ? AppTheme.gold : AppTheme.coral
                            )
                            Button("Record my readiness decision", systemImage: "checkmark.shield") {
                                showingDecision = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!project.proofGateReadiness.isReadyForHumanDecision)
                        }
                    }
                    SectionCard(title: "What this gate never does", systemImage: "nosign") {
                        Label("Does not certify scientific validity", systemImage: "xmark.circle")
                        Label("Does not run or reproduce an analysis", systemImage: "xmark.circle")
                        Label("Does not publish, submit, or share", systemImage: "xmark.circle")
                        Label("Does not replace ethics, safety, or expert review", systemImage: "xmark.circle")
                    }
                }
                .padding()
                .frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Proof Gate")
        .confirmationDialog("Record readiness for the next review?", isPresented: $showingDecision, titleVisibility: .visible) {
            Button("Record my decision") { workspace.recordProofGateDecision(projectID: projectID) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This records your local decision only. It does not claim independent validation.")
        }
    }

    @ViewBuilder
    private func gateCheck(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(ready ? AppTheme.moss : .secondary)
            .accessibilityLabel("\(title). \(ready ? "Ready" : "Not ready").")
    }
}

struct ExplicitRepairsView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var showingAdd = false
    @State private var pendingConfirmation: ExplicitRepairDraft?

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        List {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                    Text("Repairs are additive: the original remains visible, the replacement is explicit, and only a person can confirm the change.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(project.repairs) { repair in
                    Section(repair.confirmedAt == nil ? "Draft repair" : "Human-confirmed repair") {
                        LabeledContent("Before", value: repair.before)
                        LabeledContent("After", value: repair.after)
                        LabeledContent("Reason", value: repair.reason.isEmpty ? "No reason entered" : repair.reason)
                        if let date = repair.confirmedAt {
                            Label("Confirmed locally \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(AppTheme.moss)
                        } else {
                            Button("Review and confirm", systemImage: "person.crop.circle.badge.checkmark") {
                                pendingConfirmation = repair
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Explicit repairs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add repair", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddRepairSheet(workspace: workspace, projectID: projectID)
        }
        .confirmationDialog(
            "Confirm this wording repair?",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm this repair") {
                if let repair = pendingConfirmation {
                    workspace.confirmRepair(projectID: projectID, repairID: repair.id)
                }
                pendingConfirmation = nil
            }
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
        } message: {
            Text("The original remains visible. Confirmation records your choice; it does not validate the evidence.")
        }
    }
}

private struct AddRepairSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var before = ""
    @State private var after = ""
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Original wording") { TextField("Before", text: $before, axis: .vertical).lineLimit(3...8) }
                Section("Proposed repair") { TextField("After", text: $after, axis: .vertical).lineLimit(3...8) }
                Section("Why it is narrower or clearer") { TextField("Reason", text: $reason, axis: .vertical).lineLimit(2...6) }
                Section { Text("Saving creates a draft. Confirmation is a separate human action.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Draft repair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save draft") {
                        workspace.addRepair(projectID: projectID, before: before, after: after, reason: reason)
                        dismiss()
                    }
                    .disabled(before.trimmedForWorkflow.isEmpty || after.trimmedForWorkflow.isEmpty)
                }
            }
        }
    }
}

struct DefenseView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        Form {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                    Text("Defense is a stress-test worksheet. Draft responses are not endorsements, peer review, or proof.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(project.defense.enumerated()), id: \.element.id) { index, prompt in
                    Section(prompt.objection) {
                        workflowEditor(
                            "Response",
                            prompt: "State the strongest bounded response, or leave unresolved.",
                            text: defenseBinding(index, \.response, fallback: prompt.response)
                        )
                        workflowEditor(
                            "Evidence pointer",
                            prompt: "Point to the exact source or output; do not summarize vaguely.",
                            text: defenseBinding(index, \.evidencePointer, fallback: prompt.evidencePointer)
                        )
                        Label(
                            prompt.response.trimmedForWorkflow.isEmpty ? "Unresolved" : "Draft response — human review needed",
                            systemImage: prompt.response.trimmedForWorkflow.isEmpty ? "questionmark.circle" : "person.crop.circle.badge.clock"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(prompt.response.trimmedForWorkflow.isEmpty ? AppTheme.coral : AppTheme.gold)
                    }
                }
            }
        }
        .navigationTitle("Defense")
        .scrollDismissesKeyboard(.interactively)
    }

    private func defenseBinding<Value>(
        _ index: Int,
        _ path: WritableKeyPath<DefensePrompt, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let defense = workspace.project(id: projectID)?.defense, defense.indices.contains(index) else { return fallback }
                return defense[index][keyPath: path]
            },
            set: { value in
                workspace.updateProject(id: projectID) { project in
                    guard project.defense.indices.contains(index) else { return }
                    project.defense[index][keyPath: path] = value
                }
            }
        )
    }
}

struct ReproducibilityView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    let allowsEditing: Bool

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        List {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                    Text("A ready checklist means documentation is prepared for review. Only record an independent rerun if one actually happened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(project.reproducibility.enumerated()), id: \.element.id) { index, item in
                    Section(item.title) {
                        Text(item.detail).foregroundStyle(.secondary)
                        Picker("State", selection: reproducibilityBinding(index, fallback: item.state)) {
                            ForEach(ReproducibilityState.allCases, id: \.self) { state in
                                Text(state.label).tag(state)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!allowsEditing)
                        if item.title == "Independent rerun", item.state == .ready {
                            Label("Confirm this only from a real rerun record", systemImage: "exclamationmark.triangle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.coral)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reproducibility")
    }

    private func reproducibilityBinding(_ index: Int, fallback: ReproducibilityState) -> Binding<ReproducibilityState> {
        Binding(
            get: {
                guard let items = workspace.project(id: projectID)?.reproducibility, items.indices.contains(index) else { return fallback }
                return items[index].state
            },
            set: { value in
                workspace.updateProject(id: projectID) { project in
                    guard project.reproducibility.indices.contains(index) else { return }
                    project.reproducibility[index].state = value
                }
            }
        )
    }
}

struct ResearchFSView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @State private var exportURL: URL?
    @State private var localError: String?

    private var project: ResearchProject? { workspace.project(id: projectID) }

    var body: some View {
        List {
            if let project {
                Section {
                    ProjectClassificationBanner(project: project)
                    Text("ResearchFS derives a human-readable completeness map from the current verified project projection. Ready describes local organization, not scientific validity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Project tree") {
                    ForEach(project.fileSystem) { node in
                        let status = derivedResearchFSStatus(node: node, project: project)
                        DisclosureGroup {
                            Text(node.purpose).foregroundStyle(.secondary)
                        } label: {
                            HStack {
                                Label(node.path, systemImage: "folder")
                                Spacer()
                                Text(status)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(status == "Locked" ? AppTheme.coral : .secondary)
                            }
                        }
                    }
                }
                Section("User-controlled export") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share event archive", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Prepare event archive", systemImage: "doc.badge.gearshape") { prepareExport() }
                    }
                    Text("Preparing an archive does not share it. The system share sheet opens only when you choose Share.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let localError { Text(localError).font(.footnote).foregroundStyle(AppTheme.coral) }
                }
            }
        }
        .navigationTitle("ResearchFS")
    }

    private func prepareExport() {
        do {
            exportURL = try workspace.exportProjectFile(id: projectID)
            localError = nil
        } catch {
            exportURL = nil
            localError = error.localizedDescription
        }
    }

    private func derivedResearchFSStatus(node: ResearchFileNode, project: ResearchProject) -> String {
        switch node.path {
        case "00-scope/":
            return [project.scope.question, project.scope.population, project.scope.variables, project.scope.exclusions]
                .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? "Ready" : "Draft"
        case "01-protocol/":
            return project.protocolRecord.frozenByHuman &&
                [project.protocolRecord.method, project.protocolRecord.primaryOutcome, project.protocolRecord.changePolicy]
                    .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? "Ready" : "Draft"
        case "02-inputs/":
            return !project.inbox.isEmpty && project.inbox.allSatisfy { $0.reviewState != .unreviewed }
                ? "Ready" : "Open"
        case "03-analysis/":
            return project.reproducibility.contains {
                $0.title == "Method executable" && $0.state == .ready
            } ? "Ready" : "Open"
        case "04-claims/":
            return !project.claims.isEmpty && project.claims.allSatisfy {
                $0.humanReviewed && !$0.evidencePointer.isEmpty && !$0.limitation.isEmpty
            } ? "Ready" : "Open"
        case "05-defense/":
            return !project.defense.isEmpty && project.defense.allSatisfy {
                !$0.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.evidencePointer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ? "Ready" : "Open"
        case "06-release/":
            return project.proofGateConfirmedAt == nil ? "Locked" : "Human-approved"
        default:
            return "Unknown"
        }
    }
}

@ViewBuilder
private func workflowEditor(_ title: String, prompt: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.subheadline.weight(.semibold))
        TextEditor(text: text)
            .frame(minHeight: 86)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(title)
            .accessibilityHint(prompt)
    }
}

private extension String {
    var trimmedForWorkflow: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
