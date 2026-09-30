import SwiftUI
import UniformTypeIdentifiers

struct ResearchInboxView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore

    @State private var targetProjectID: UUID?
    @State private var reviewFilter: InboxReviewState?
    @State private var showingManualAdd = false
    @State private var showingFileImporter = false
    @State private var importError: String?

    private var items: [(project: ResearchProject, item: ResearchInboxItem)] {
        workspace.projects
            .flatMap { project in project.inbox.map { (project: project, item: $0) } }
            .filter { reviewFilter == nil || $0.item.reviewState == reviewFilter }
            .sorted { $0.item.addedAt > $1.item.addedAt }
    }

    var body: some View {
        List {
            Section {
                Label("Capture first; decide later. Inbox items never become evidence, claims, or citations without an explicit human review.", systemImage: "tray.and.arrow.down")
                    .font(.subheadline)
                Picker("Target project", selection: $targetProjectID) {
                    Text("Choose a project").tag(UUID?.none)
                    ForEach(workspace.activeProjects) { project in
                        Text(project.title).tag(UUID?.some(project.id))
                    }
                }
                Picker("Review state", selection: $reviewFilter) {
                    Text("All").tag(InboxReviewState?.none)
                    ForEach(InboxReviewState.allCases, id: \.self) { state in
                        Text(state.label).tag(InboxReviewState?.some(state))
                    }
                }
            }

            Section("Captured items") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Inbox is clear",
                        systemImage: "tray",
                        description: Text("Add a note or bring in a file when there is something to review.")
                    )
                } else {
                    ForEach(items, id: \.item.id) { pair in
                        InboxItemRow(
                            project: pair.project,
                            item: pair.item,
                            onStateChange: { state in
                                workspace.updateInboxItem(projectID: pair.project.id, itemID: pair.item.id, state: state)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Research Inbox")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import file", systemImage: "doc.badge.plus") {
                    showingFileImporter = true
                }
                .disabled(targetProjectID == nil)
                Button("Add note", systemImage: "square.and.pencil") {
                    showingManualAdd = true
                }
                .disabled(targetProjectID == nil)
            }
        }
        .onAppear {
            if targetProjectID == nil { targetProjectID = workspace.selectedProjectID ?? workspace.activeProjects.first?.id }
        }
        .sheet(isPresented: $showingManualAdd) {
            if let targetProjectID {
                AddInboxNoteSheet(workspace: workspace, projectID: targetProjectID)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText, .json, .commaSeparatedText, .pdf],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .alert("Could not add file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "Unknown import error")
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let projectID = targetProjectID else { return }
            let url = try result.get().first
            guard let url else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let size = values.fileSize ?? 0
            let type = values.contentType?.localizedDescription ?? "document"
            var note = "Imported from Files as \(type). The source file itself is not uploaded by Research OS."
            if size <= 256_000,
               values.contentType?.conforms(to: .text) == true,
               let text = try? String(contentsOf: url, encoding: .utf8),
               !text.isEmpty {
                note += "\n\nLocal preview:\n\(String(text.prefix(4_000)))"
            } else if size > 256_000 {
                note += " Preview omitted because the file is larger than 256 KB."
            } else {
                note += " Content preview is unavailable for this file type; review the source in Files."
            }
            workspace.addInboxItem(
                projectID: projectID,
                title: url.lastPathComponent,
                source: "Files · \(type)",
                note: note
            )
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct InboxItemRow: View {
    let project: ResearchProject
    let item: ResearchInboxItem
    let onStateChange: (InboxReviewState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline)
                    Text(project.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu(item.reviewState.label) {
                    ForEach(InboxReviewState.allCases, id: \.self) { state in
                        Button(state.label) { onStateChange(state) }
                    }
                }
                .font(.caption.weight(.semibold))
                .accessibilityLabel("Review state: \(item.reviewState.label)")
            }
            Label(item.classification.label, systemImage: item.classification == .syntheticDemo ? "theatermasks" : "person.crop.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !item.source.isEmpty {
                LabeledContent("Source", value: item.source)
                    .font(.subheadline)
            }
            DisclosureGroup("Review note") {
                Text(item.note.isEmpty ? "No note entered." : item.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            Text(item.addedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct AddInboxNoteSheet: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var source = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    TextField("Item title", text: $title, axis: .vertical)
                    TextField("Where it came from", text: $source, axis: .vertical)
                    TextField("What needs review", text: $note, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    Text("This creates an unreviewed inbox item. It is not automatically a citation, evidence link, or claim.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add inbox note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        workspace.addInboxItem(projectID: projectID, title: title, source: source, note: note)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
