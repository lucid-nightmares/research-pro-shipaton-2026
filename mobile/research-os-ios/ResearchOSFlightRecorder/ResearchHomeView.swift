import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController
    @EnvironmentObject private var model: AppModel
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var plus = false
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var archived = false
    @State private var searchText = ""
    @State private var checkingSubscription = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Research you can defend.")
                            .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Collect the evidence. Refine your argument. Explain what would change your mind.")
                            .font(.body).foregroundStyle(.secondary)
                        Button("Create project", systemImage: "plus") {
                            guard !checkingSubscription else { return }
                            let count = workspace.activeProjects.filter { $0.classification == .userCreated }.count
                            if count == 0 { creating = true }
                            else {
                                checkingSubscription = true
                                Task {
                                    let access = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace)
                                    checkingSubscription = false
                                    if CommercialCapabilityPolicy.decision(for: .createAdditionalActiveProject,
                                        subscriptionState: access,
                                        activeUserProjectCount: workspace.activeProjects.filter { $0.classification == .userCreated }.count).allowsUse {
                                        creating = true
                                    } else { plus = true }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(checkingSubscription)
                        .accessibilityIdentifier("create-project")
                        Button("Try a sample", systemImage: "doc.text.magnifyingglass") {
                            perform {
                                let id = try workspace.createArgumentSample()
                                workspace.selectedProjectID = id
                                path.append(id)
                            }
                        }.controlSize(.large).accessibilityIdentifier("try-sample")
                        Text("Start locally. No account needed.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if let failure = workspace.mutationCapacityFailure {
                    Section("Change not saved") { Text(failure).foregroundStyle(AppTheme.coral) }
                }
                if let failure = workspace.persistenceFailure {
                    Section("History needs attention") {
                        Text(failure).foregroundStyle(AppTheme.coral)
                        NavigationLink("Inspect recovery options") { WorkspaceLibraryView(workspace: workspace) }
                    }
                }
                Section(archived ? "Archived projects" : "Your projects") {
                    let projects = ResearchProjectList.filtered(archived ? workspace.archivedProjects : workspace.activeProjects, query: searchText)
                    if projects.isEmpty {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            Text(archived ? "No archived projects." : "Your question is the starting point. Create a project or explore the sample above.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(projects) { project in
                        NavigationLink(value: project.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(project.title).font(.headline)
                                Text(project.scope.question).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                if project.classification == .syntheticDemo {
                                    Text("Synthetic sample").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(nextAction(project)).font(.caption.weight(.medium))
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("project-\(project.id)")
                    }
                    Toggle("Show archived projects", isOn: $archived)
                }
                Section("Research OS") {
                    NavigationLink { WorkspaceLibraryView(workspace: workspace) } label: { Label("Full workspace & protocols", systemImage: "square.grid.2x2") }
                    NavigationLink { ResearchInboxView(workspace: workspace) } label: { Label("Research Inbox", systemImage: "tray") }
                    NavigationLink { LegacyReviewTabs() } label: { Label("Flight Recorder & previous reviews", systemImage: "clock.arrow.circlepath") }
                    if model.localReview != nil {
                        NavigationLink("Previous single review") { LocalReviewView() }
                    }
                    Button("Import research archive", systemImage: "square.and.arrow.down") { importing = true }
                        .disabled(busy)
                }
                Section {
                    Text("Research stays on this device. Optional subscription services contact RevenueCat and the store; source text and defense answers are not sent to them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Project or research question")
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Research Pro Plus", systemImage: "rectangle.stack.badge.plus") { plus = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ResearchArgumentView(workspace: workspace, projectID: id)
            }
            .sheet(isPresented: $creating) {
                NewResearchProjectView(workspace: workspace) { id in path.append(id) }
            }
            .sheet(isPresented: $plus) { NavigationStack { SubscriptionView() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .failure(let failure): error = failure.localizedDescription
                case .success(let url):
                    busy = true
                    Task {
                        do {
                            let data = try await Task.detached(priority: .userInitiated) {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                guard url.isFileURL,
                                      (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= ResearchArgumentLimits.maximumArchiveBytes else {
                                    throw ResearchContentImportError.tooLarge
                                }
                                let bytes = try Data(contentsOf: url)
                                guard bytes.count <= ResearchArgumentLimits.maximumArchiveBytes else { throw ResearchContentImportError.tooLarge }
                                return bytes
                            }.value
                            let id = try workspace.importArchiveData(data)
                            path.append(id)
                        } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
            }
            .overlay { if busy { ProgressView("Checking archive…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)) } }
            .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func nextAction(_ project: ResearchProject) -> String {
        guard let argument = project.argument, !argument.sources.isEmpty else { return "Next: capture evidence" }
        if argument.claims.isEmpty { return "Next: state a claim" }
        if !argument.findings.isEmpty { return "\(argument.findings.count) checks need your attention" }
        return "Resume your research"
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

private struct NewResearchProjectView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    @EnvironmentObject private var subscriptions: SubscriptionController
    @Environment(\.dismiss) private var dismiss
    @SceneStorage("research-pro.create.title") private var title = ""
    @SceneStorage("research-pro.create.question") private var question = ""
    @State private var error: String?
    @State private var checkingSubscription = false
    @State private var creationTask: Task<Void, Never>?
    let created: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Begin with a question") {
                    TextField("Project title", text: $title).accessibilityIdentifier("project-title")
                    TextField("Research question", text: $question, axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("research-question")
                }
                Section { Text("Add evidence and claims at your own pace. Scope, protocol, and reproducibility tools remain available in the full workspace.").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(AppTheme.coral) }
            }
            .navigationTitle("Create project").researchKeyboard()
            .onDisappear { creationTask?.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creationTask?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard !checkingSubscription else { return }
                        checkingSubscription = true
                        creationTask = Task {
                            defer { checkingSubscription = false }
                            let count = workspace.activeProjects.filter { $0.classification == .userCreated }.count
                            let access: SubscriptionAccessState
                            if count > 0 { access = await CommercialActionGate.refreshAccess(using: subscriptions, workspace: workspace) }
                            else { access = subscriptions.state }
                            guard !Task.isCancelled else { return }
                            if let id = workspace.createProject(title: title, question: question, subscriptionState: access) {
                                title = ""; question = ""; dismiss(); created(id)
                            } else { error = workspace.persistenceFailure ?? "The free plan includes one active project. Archive one in the full workspace, or explore Plus." }
                        }
                    }
                    .disabled(checkingSubscription || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || question.count > 1000)
                    .accessibilityIdentifier("confirm-create-project")
                }
            }
        }
    }
}
