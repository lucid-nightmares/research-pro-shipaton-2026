import SwiftUI

enum AppTab: Hashable {
    case review
    case repair
    case verify
    case workspace
}

struct LegacyReviewTabs: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workspace: ResearchWorkspaceStore
    @State private var selectedTab: AppTab = .review
    @State private var showingAbout = false
    @State private var showingInbox = false
    @State private var showingPlus = false
    @State private var showingPreviousReview = false

    private var selectedUserProject: ResearchProject? {
        guard let id = workspace.selectedProjectID,
              let project = workspace.project(id: id),
              project.classification == .userCreated else { return nil }
        return project
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                if let project = selectedUserProject {
                    WorkspaceProjectReviewView(workspace: workspace, project: project) { selectedTab = .repair }
                        .navigationTitle("Review")
                        .toolbar { aboutButton }
                } else if let record = model.record {
                    ReviewView(record: record) { selectedTab = .repair }
                        .navigationTitle("Flight Recorder")
                        .toolbar { aboutButton }
                } else {
                    unavailableExample
                        .navigationTitle("Flight Recorder")
                        .toolbar { aboutButton }
                }
            }
            .tabItem { Label("Review", systemImage: "doc.text.magnifyingglass") }
            .tag(AppTab.review)

            NavigationStack {
                if let project = selectedUserProject {
                    WorkspaceProjectRepairView(workspace: workspace, project: project) {
                        selectedTab = .verify
                    }
                    .navigationTitle("Repair")
                    .toolbar { aboutButton }
                } else if let record = model.record {
                    RepairView(record: record) { selectedTab = .verify }
                        .navigationTitle("Repair")
                        .toolbar { aboutButton }
                } else {
                    unavailableExample
                        .navigationTitle("Repair")
                        .toolbar { aboutButton }
                }
            }
            .tabItem { Label("Repair", systemImage: "checkmark.seal") }
            .tag(AppTab.repair)

            NavigationStack {
                if let project = selectedUserProject {
                    WorkspaceProjectVerifyView(workspace: workspace, project: project)
                        .navigationTitle("Verify")
                        .toolbar { aboutButton }
                } else if let record = model.record {
                    VerifyView(record: record)
                        .navigationTitle("Verify")
                        .toolbar { aboutButton }
                } else {
                    unavailableExample
                        .navigationTitle("Verify")
                        .toolbar { aboutButton }
                }
            }
            .tabItem { Label("Verify", systemImage: "checkmark.shield") }
            .tag(AppTab.verify)

            WorkspaceLibraryView(workspace: workspace)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Workspace actions", systemImage: "ellipsis.circle") {
                            Button("Research Inbox", systemImage: "tray") { showingInbox = true }
                            if model.localReview != nil {
                                Button("Previous single review", systemImage: "clock.arrow.circlepath") {
                                    showingPreviousReview = true
                                }
                            }
                            Button("Research OS Plus", systemImage: "rectangle.stack.badge.plus") { showingPlus = true }
                            Button("About", systemImage: "info.circle") { showingAbout = true }
                        }
                    }
                }
                .tabItem { Label("Workspace", systemImage: "folder") }
                .tag(AppTab.workspace)
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .sheet(isPresented: $showingInbox) {
            NavigationStack { ResearchInboxView(workspace: workspace) }
        }
        .sheet(isPresented: $showingPlus) {
            NavigationStack { SubscriptionView() }
        }
        .sheet(isPresented: $showingPreviousReview) {
            NavigationStack {
                LocalReviewView()
                    .navigationTitle("Previous single review")
            }
        }
        .alert(
            "Previous review unavailable",
            isPresented: Binding(
                get: { model.localReviewErrorMessage != nil },
                set: { if !$0 { model.localReviewErrorMessage = nil } }
            )
        ) {
            Button("OK") { model.localReviewErrorMessage = nil }
        } message: {
            Text(model.localReviewErrorMessage ?? "The previous review could not be verified.")
        }
    }

    @ViewBuilder
    private var unavailableExample: some View {
        if let message = model.errorMessage {
            ContentUnavailableView(
                "Walkthrough unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("\(message) Your local workspace remains available in the Workspace tab.")
            )
        } else {
            ProgressView("Opening the invented walkthrough…")
        }
    }

    @ToolbarContentBuilder
    private var aboutButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("About", systemImage: "info.circle") { showingAbout = true }
        }
    }
}

private struct WorkspaceProjectReviewView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let project: ResearchProject
    let continueToRepair: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ProjectClassificationBanner(project: project)
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.title).font(.title2.weight(.semibold))
                    Text(project.scope.question).font(.title3).foregroundStyle(.secondary)
                }
                SectionCard(title: "Claim review", systemImage: "doc.text.magnifyingglass") {
                    if project.claims.isEmpty {
                        Text("No claim has been linked to evidence yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(project.claims) { link in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(link.claim).font(.headline).textSelection(.enabled)
                                LabeledContent("Evidence", value: link.evidencePointer.isEmpty ? "Missing" : link.evidencePointer)
                                LabeledContent("Limitation", value: link.limitation.isEmpty ? "Missing" : link.limitation)
                                StatusPill(
                                    text: link.humanReviewed ? "Human-reviewed link" : "Human review required",
                                    color: link.humanReviewed ? AppTheme.moss : AppTheme.gold
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Button("Repair this project", systemImage: "arrow.right") { continueToRepair() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!workspace.canMutateProject(id: project.id))
                if let reason = workspace.mutationAccessReason(projectID: project.id) {
                    Label(reason, systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }
}

private struct WorkspaceProjectRepairView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let project: ResearchProject
    let continueToVerify: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let reason = workspace.mutationAccessReason(projectID: project.id) {
                ContentUnavailableView(
                    "Read-only project",
                    systemImage: "lock",
                    description: Text(reason)
                )
            } else {
                ExplicitRepairsView(workspace: workspace, projectID: project.id)
            }
            Button("Continue to Verify", systemImage: "arrow.right") { continueToVerify() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
        }
        .background(Color(.systemBackground))
    }
}

private struct WorkspaceProjectVerifyView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let project: ResearchProject
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ProjectClassificationBanner(project: project)
                SectionCard(title: "Proof Gate", systemImage: "checkmark.shield") {
                    ProgressView(
                        value: Double(project.proofGateReadiness.completedChecks),
                        total: Double(project.proofGateReadiness.totalChecks)
                    )
                    Text("\(project.proofGateReadiness.completedChecks) of \(project.proofGateReadiness.totalChecks) structural checks are ready.")
                    Text(project.proofGateConfirmedAt == nil
                         ? "No human readiness decision is recorded."
                         : "A local human readiness decision is recorded; this is not scientific validation.")
                        .foregroundStyle(.secondary)
                }
                SectionCard(title: "Portable record", systemImage: "shippingbox") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export verified project record", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else if let exportError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(exportError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(AppTheme.coral)
                            Button("Try preparing again", systemImage: "arrow.clockwise") {
                                prepareExport()
                            }
                        }
                    } else {
                        Button("Prepare verified project record", systemImage: "doc.badge.gearshape") {
                            prepareExport()
                        }
                    }
                    Text("Preparing creates a protected, app-managed copy. It is not shared until you choose Export.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Integrity verifies the local event record and exact bytes. It does not rerun an analysis or validate a scientific conclusion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private func prepareExport() {
        do {
            exportURL = try workspace.exportProjectFile(id: project.id)
            exportError = nil
        } catch {
            exportURL = nil
            exportError = error.localizedDescription
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Research Pro · Flight Recorder")
                            .font(.title2.bold())
                    Text("A native research workspace for reviewing how claims change, recording bounded wording, and exporting evidence-aware manifests.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("Privacy") {
                    Label("No account", systemImage: "person.crop.circle.badge.xmark")
                    Label("No advertising or cross-app tracking", systemImage: "chart.bar.xaxis")
                    Label("Research content stays local", systemImage: "externaldrive.badge.checkmark")
                    Label("Network use is limited to optional purchases", systemImage: "network")
                    Label("Local app data is protected by iOS", systemImage: "lock.shield")
                }
                Section("Evidence boundary") {
                    Text("The bundled classroom example is invented. It does not represent real students or scientific evidence. Local integrity checks do not equal scientific reproduction, publication, or independent validation.")
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
