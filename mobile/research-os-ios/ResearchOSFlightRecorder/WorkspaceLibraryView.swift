import SwiftUI

struct WorkspaceLibraryView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController

    @State private var showingArchived = false
    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var showingUpgrade = false
    @State private var showingRecoveryConfirmation = false
    @State private var checkingCreateAccess = false
    @State private var createAccessTask: Task<Void, Never>?

    private var visibleProjects: [ResearchProject] {
        let projects = showingArchived ? workspace.archivedProjects : workspace.activeProjects
        return ResearchProjectList.filtered(projects, query: searchText)
    }

    private var createDecision: CommercialCapabilityDecision {
        CommercialCapabilityPolicy.decision(
            for: .createAdditionalActiveProject,
            subscriptionState: subscriptions.state,
            activeUserProjectCount: workspace.activeProjects.filter { $0.classification == .userCreated }.count
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $workspace.selectedProjectID) {
                Section {
                    Picker("Project state", selection: $showingArchived) {
                        Text("Active").tag(false)
                        Text("Archived").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Switches between active and archived research projects.")
                }

                Section(showingArchived ? "Archived projects" : "Active projects") {
                    if let persistenceFailure = workspace.persistenceFailure {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(persistenceFailure, systemImage: "exclamationmark.shield.fill")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.coral)
                                .accessibilityLabel("Local history locked: \(persistenceFailure)")
                            if workspace.canRecoverCorruptTail {
                                Button("Recover verified history", systemImage: "cross.case") {
                                    showingRecoveryConfirmation = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    if let failure = workspace.mutationCapacityFailure {
                        Label(failure, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(AppTheme.coral)
                    }
                    if let recoveryMessage = workspace.recoveryMessage {
                        Label(recoveryMessage, systemImage: "checkmark.shield")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.moss)
                    }
                    if let deletionFailure = workspace.deletionFailure {
                        Label(deletionFailure, systemImage: "trash.slash.fill")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.coral)
                            .accessibilityLabel("Project purge failed: \(deletionFailure)")
                    }
                    if visibleProjects.isEmpty {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ContentUnavailableView(
                                showingArchived ? "No archived projects" : "No active projects",
                                systemImage: showingArchived ? "archivebox" : "folder.badge.plus",
                                description: Text(showingArchived
                                                  ? "Projects you archive will appear here."
                                                  : "Create a project to scope a question and organize its proof trail.")
                            )
                        }
                    } else {
                        ForEach(visibleProjects) { project in
                            NavigationLink(value: project.id) {
                                ProjectLibraryRow(project: project)
                            }
                            .accessibilityAddTraits(workspace.selectedProjectID == project.id ? .isSelected : [])
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Project or research question")
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New project", systemImage: "plus") {
                        guard !checkingCreateAccess else { return }
                        if workspace.activeProjects.filter({ $0.classification == .userCreated }).isEmpty {
                            showingCreate = true
                        } else {
                            checkingCreateAccess = true
                            createAccessTask = Task {
                                defer { checkingCreateAccess = false; createAccessTask = nil }
                                _ = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
                                guard !Task.isCancelled else { return }
                                if createDecision.allowsUse { showingCreate = true }
                                else { showingUpgrade = true }
                            }
                        }
                    }
                    .disabled(workspace.persistenceFailure != nil || checkingCreateAccess)
                }
            }
        } detail: {
            NavigationStack {
                if let id = workspace.selectedProjectID, workspace.project(id: id) != nil {
                    ProjectWorkbenchView(workspace: workspace, projectID: id)
                } else {
                    ContentUnavailableView(
                        "Choose a project",
                        systemImage: "folder",
                        description: Text("Open an active or archived project from the library.")
                    )
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateProjectSheet(workspace: workspace)
        }
        .sheet(isPresented: $showingUpgrade) {
            NavigationStack { SubscriptionView() }
        }
        .confirmationDialog(
            "Recover the verified part of local history?",
            isPresented: $showingRecoveryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Recover and quarantine corrupt tail") {
                _ = workspace.recoverCorruptTail()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Research OS will keep every verified event, move the unreadable tail into protected Recovery storage, and record a local human recovery receipt. Nothing is silently repaired.")
        }
        .onDisappear { createAccessTask?.cancel() }
    }
}

private struct ProjectLibraryRow: View {
    let project: ResearchProject

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(project.scope.question)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(project.classification.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text("Proof gate \(project.proofGateReadiness.completedChecks) of \(project.proofGateReadiness.totalChecks)")
                Spacer()
                Text(project.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title). \(project.scope.question). \(project.classification.label). Proof gate \(project.proofGateReadiness.completedChecks) of \(project.proofGateReadiness.totalChecks).")
    }
}

private struct CreateProjectSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptions: SubscriptionController

    @State private var title = ""
    @State private var question = ""
    @State private var creationMessage: String?
    @State private var creating = false
    @State private var creationTask: Task<Void, Never>?

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= 120 && question.count <= 1_000
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("New projects are labeled as your local work. The app never presents your entries as independently verified.", systemImage: "person.crop.circle")
                        .font(.subheadline)
                }
                Section("Project") {
                    TextField("Project title", text: $title, axis: .vertical)
                    TextField("Research question", text: $question, axis: .vertical)
                        .lineLimit(3...7)
                }
                Section("Start small") {
                    Text("You can create the project with only a title and question. Population, variables, protocol, evidence links, and proof checks stay visible as open work instead of being invented for you.")
                        .foregroundStyle(.secondary)
                }
                if let creationMessage {
                    Section { Text(creationMessage).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(creating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard !creating else { return }
                        if workspace.activeProjects.filter({ $0.classification == .userCreated }).isEmpty {
                            create(using: subscriptions.state)
                        } else {
                            creating = true
                            creationTask = Task {
                                defer { creating = false; creationTask = nil }
                                let current = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
                                guard !Task.isCancelled else { return }
                                create(using: current)
                            }
                        }
                    }
                    .disabled(!canCreate || creating)
                }
            }
            .interactiveDismissDisabled(creating)
        }
        .onDisappear { creationTask?.cancel() }
    }

    private func create(using state: SubscriptionAccessState) {
        if workspace.createProject(title: title, question: question, subscriptionState: state) != nil {
            dismiss()
        } else {
            creationMessage = workspace.persistenceFailure ?? "Your free project is preserved. Research Pro Plus is required to add another active project."
        }
    }
}

struct ProjectWorkbenchView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController
    let projectID: UUID

    @State private var showingRename = false
    @State private var showingArchive = false
    @State private var showingDelete = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var restoring = false
    @State private var restoreTask: Task<Void, Never>?
    @State private var showingUpgrade = false

    private var project: ResearchProject? { workspace.project(id: projectID) }

    private var advancedDecision: CommercialCapabilityDecision {
        CommercialCapabilityPolicy.decision(
            for: .advancedWorkspace,
            subscriptionState: subscriptions.state,
            activeUserProjectCount: workspace.activeProjects.filter { $0.classification == .userCreated }.count,
            project: project
        )
    }

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ProjectClassificationBanner(project: project)

                        if let reason = workspace.mutationAccessReason(projectID: projectID) {
                            Label(reason, systemImage: "lock.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 4))
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(project.title)
                                .font(.title2.weight(.semibold))
                            Text(project.scope.question.isEmpty ? "Question not scoped yet" : project.scope.question)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        ProofGateSummaryCard(project: project)

                        // Ordered rows preserve all seven destinations and their access checks.
                        VStack(spacing: 0) {
                            WorkbenchLink(
                                title: "Scope & protocol",
                                detail: project.protocolRecord.frozenByHuman ? "Protocol marked frozen by you" : "Define the decision boundary",
                                systemImage: "scope",
                                readOnlyReason: workspace.mutationAccessReason(projectID: projectID)
                            ) {
                                ScopeProtocolView(workspace: workspace, projectID: projectID)
                            }
                            WorkbenchLink(
                                title: "Claims & evidence",
                                detail: "\(project.claims.count) claim-to-evidence link\(project.claims.count == 1 ? "" : "s")",
                                systemImage: "link",
                                readOnlyReason: workspace.mutationAccessReason(projectID: projectID)
                            ) {
                                ClaimsEvidenceView(workspace: workspace, projectID: projectID)
                            }
                            WorkbenchLink(
                                title: "Proof Gate",
                                detail: project.proofGateConfirmedAt == nil ? "Human decision not recorded" : "Human decision recorded",
                                systemImage: "checkmark.shield",
                                readOnlyReason: workspace.mutationAccessReason(projectID: projectID)
                            ) {
                                ProofGateView(workspace: workspace, projectID: projectID)
                            }
                            WorkbenchLink(
                                title: "Explicit repairs",
                                detail: "Original wording stays visible",
                                systemImage: "wrench.and.screwdriver",
                                readOnlyReason: workspace.mutationAccessReason(projectID: projectID)
                            ) {
                                ExplicitRepairsView(workspace: workspace, projectID: projectID)
                            }
                            WorkbenchLink(
                                title: "Defense",
                                detail: "Objections, responses, unresolved risks",
                                systemImage: "shield.lefthalf.filled",
                                readOnlyReason: workspace.mutationAccessReason(projectID: projectID)
                            ) { DefenseView(workspace: workspace, projectID: projectID) }
                            advancedLink(
                                title: "Reproducibility",
                                detail: "A checklist, never a certification",
                                systemImage: "arrow.triangle.2.circlepath"
                            ) { allowsEditing in
                                ReproducibilityView(
                                    workspace: workspace,
                                    projectID: projectID,
                                    allowsEditing: allowsEditing
                                )
                            }
                            advancedLink(
                                title: "ResearchFS",
                                detail: "See what exists and what is still missing",
                                systemImage: "folder.badge.gearshape"
                            ) { _ in ResearchFSView(workspace: workspace, projectID: projectID) }
                        }

                        if let exportError {
                            Text(exportError)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.coral)
                                .accessibilityLabel("Export error: \(exportError)")
                        }
                    }
                    .padding()
                    .frame(maxWidth: 1_000)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemBackground))
                .navigationTitle("Project")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Share event archive", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button("Prepare event archive", systemImage: "doc.badge.gearshape") {
                                prepareExport()
                            }
                        }
                        Menu("Project actions", systemImage: "ellipsis.circle") {
                            Button("Rename", systemImage: "pencil") { showingRename = true }
                                .disabled(!workspace.canMutateProject(id: projectID))
                            if project.status == .active {
                                Button("Archive", systemImage: "archivebox") { showingArchive = true }
                            } else {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    guard !restoring else { return }
                                    if project.classification == .syntheticDemo || workspace.activeProjects.filter({ $0.classification == .userCreated }).isEmpty {
                                        _ = workspace.restoreProject(id: projectID, subscriptionState: subscriptions.state)
                                    } else {
                                        restoring = true
                                        restoreTask = Task {
                                            defer { restoring = false; restoreTask = nil }
                                            let current = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
                                            guard !Task.isCancelled else { return }
                                            if CommercialCapabilityPolicy.decision(
                                                for: .createAdditionalActiveProject,
                                                subscriptionState: current,
                                                activeUserProjectCount: workspace.activeProjects.filter { $0.classification == .userCreated }.count
                                            ).allowsUse {
                                                _ = workspace.restoreProject(id: projectID, subscriptionState: current)
                                            } else { showingUpgrade = true }
                                        }
                                    }
                                }
                                .disabled(restoring)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true }
                        }
                    }
                }
                .sheet(isPresented: $showingRename) {
                    RenameProjectSheet(workspace: workspace, project: project)
                }
                .sheet(isPresented: $showingUpgrade) {
                    NavigationStack { SubscriptionView() }
                }
                .confirmationDialog("Archive this project?", isPresented: $showingArchive, titleVisibility: .visible) {
                    Button("Archive project") { workspace.archiveProject(id: projectID) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The project remains available under Archived projects. This does not publish or delete anything.")
                }
                .confirmationDialog("Delete this local project?", isPresented: $showingDelete, titleVisibility: .visible) {
                    Button("Purge project from this app", role: .destructive) { workspace.deleteProject(id: projectID) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the project's managed exports first, then atomically purges its event history from the live app journal. Export first if you need a copy. Copies you already shared are outside this app's control, and prior OS backups or physical flash remnants may still retain older bytes.")
                }
            } else {
                ContentUnavailableView("Project unavailable", systemImage: "folder.badge.questionmark")
            }
        }
        .onDisappear { restoreTask?.cancel() }
    }

    private func prepareExport() {
        do {
            exportURL = try workspace.exportProjectFile(id: projectID)
            exportError = nil
        } catch {
            exportURL = nil
            exportError = error.localizedDescription
        }
    }

    private func advancedLink<Destination: View>(
        title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder destination: @escaping (Bool) -> Destination
    ) -> some View {
        NavigationLink {
            AdvancedWorkspaceEntryView(workspace: workspace, projectID: projectID, destination: destination)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(title).font(.headline).foregroundStyle(.primary)
                        if !advancedDecision.allowsUse {
                            Text("Plus").font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: advancedDecision.allowsUse ? "chevron.right" : "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title). Existing content remains readable after a downgrade.")
    }
}


/// Saved advanced work is immediately readable. New activation and editing
/// become available only after a current provider refresh completes.
private struct AdvancedWorkspaceEntryView<Destination: View>: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController
    let projectID: UUID
    let destination: (Bool) -> Destination
    @State private var checkedAccess = false
    @State private var activationFailure: String?

    private var retained: Bool { workspace.project(id: projectID)?.plusWorkspaceActivatedAt != nil }
    private var decision: CommercialCapabilityDecision {
        CommercialCapabilityPolicy.decision(for: .advancedWorkspace, subscriptionState: subscriptions.state,
            activeUserProjectCount: workspace.activeProjects.filter { $0.classification == .userCreated }.count,
            project: workspace.project(id: projectID))
    }
    var body: some View {
        Group {
            if retained {
                destination(checkedAccess && decision.allowsMutation)
                    .safeAreaInset(edge: .top) {
                        if !checkedAccess || !decision.allowsMutation {
                            Label("Existing work remains readable and exportable. Editing requires current Plus access.", systemImage: "lock.open.display")
                                .font(.footnote).foregroundStyle(.secondary).padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemBackground))
                        }
                    }
            } else if let activationFailure {
                ContentUnavailableView("Workspace needs attention", systemImage: "exclamationmark.triangle", description: Text(activationFailure))
            } else if checkedAccess {
                SubscriptionView()
            } else {
                ProgressView("Checking current access…")
            }
        }
        .task {
            guard !checkedAccess else { return }
            let current = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
            guard !Task.isCancelled else { return }
            if current.grantsPlusAccess && !retained {
                if !workspace.activateAdvancedWorkspace(projectID: projectID, subscriptionState: current) {
                    activationFailure = workspace.persistenceFailure ?? "The workspace could not be activated. Your research was kept."
                }
            }
            checkedAccess = true
        }
    }
}

private struct RenameProjectSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let project: ResearchProject
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(workspace: ResearchWorkspaceStore, project: ResearchProject) {
        self.workspace = workspace
        self.project = project
        _title = State(initialValue: project.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project title", text: $title, axis: .vertical)
                Text("Renaming changes the library label only. It does not rewrite claims, evidence, exports, or authorship.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Rename project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspace.renameProject(id: project.id, to: title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120)
                }
            }
        }
    }
}

struct ProjectClassificationBanner: View {
    let project: ResearchProject

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.classification.label).font(.subheadline.bold())
                Text(project.classification.boundary).font(.footnote)
            }
        } icon: {
            Image(systemName: project.classification == .syntheticDemo ? "theatermasks" : "person.crop.circle")
        }
        .foregroundStyle(AppTheme.ink)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

private struct ProofGateSummaryCard: View {
    let project: ResearchProject

    var body: some View {
        SectionCard(title: "Proof Gate", systemImage: "checkmark.shield") {
            ProgressView(
                value: Double(project.proofGateReadiness.completedChecks),
                total: Double(project.proofGateReadiness.totalChecks)
            )
            .tint(project.proofGateReadiness.isReadyForHumanDecision ? AppTheme.moss : AppTheme.gold)
            Text("\(project.proofGateReadiness.completedChecks) of \(project.proofGateReadiness.totalChecks) structural checks are ready.")
                .font(.subheadline.bold())
            Text(project.proofGateConfirmedAt == nil
                 ? "No human proof decision has been recorded."
                 : "A human recorded readiness for the next review; this is not external validation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkbenchLink<Destination: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let readOnlyReason: String?
    let destination: Destination

    init(
        title: String,
        detail: String,
        systemImage: String,
        readOnlyReason: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.readOnlyReason = readOnlyReason
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            if let readOnlyReason {
                destination
                    .disabled(true)
                    .safeAreaInset(edge: .top) {
                        Label(readOnlyReason, systemImage: "lock.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                    }
            } else {
                destination
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title).")
    }
}

/// Local library presentation. A stable tie-break avoids row movement for equal update times.
enum ResearchProjectList {
    static func filtered(_ projects: [ResearchProject], query: String) -> [ResearchProject] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return projects.filter { project in
            query.isEmpty || project.title.localizedStandardContains(query)
                || project.scope.question.localizedStandardContains(query)
        }.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }
}
