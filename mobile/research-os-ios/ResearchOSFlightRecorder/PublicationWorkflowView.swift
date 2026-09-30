import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ResearchPreviewFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
struct ResearchFilePreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var document: PDFDocument?
    @State private var chunks: [String] = []
    @State private var index = 0
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    ResearchPDFPreview(document: document)
                        .accessibilityIdentifier("native-document-preview")
                        .accessibilityLabel("PDF preview, \(document.pageCount) pages")
                } else if !chunks.isEmpty {
                    VStack(spacing: 0) {
                        if chunks.count > 1 {
                            HStack {
                                Button("Previous text page") { index -= 1 }.disabled(index == 0)
                                Spacer()
                                Text("Text page \(index + 1) of \(chunks.count)").font(.caption)
                                Spacer()
                                Button("Next text page") { index += 1 }.disabled(index + 1 == chunks.count)
                            }.padding()
                            Text("The complete file is preserved. This viewer divides long text into pages for reading.").font(.caption).padding(.horizontal)
                        }
                        ResearchPlainTextPreview(text: chunks[index])
                            .accessibilityIdentifier("native-text-preview")
                    }
                } else if let failure {
                    ContentUnavailableView("Preview unavailable", systemImage: "doc.questionmark", description: Text(failure))
                } else { ProgressView("Opening local export…") }
            }
            .navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: url) {
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 20_000_000 else {
                    throw PublicationError.invalid("The local viewer is limited to 20 MB. The full exported file is still available through Share.")
                }
                if url.pathExtension.lowercased() == "pdf" {
                    guard let loaded = PDFDocument(url: url), loaded.pageCount > 0 else { throw PublicationError.invalid("The PDF could not be opened.") }
                    document = loaded
                } else {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    var position = text.startIndex, result: [String] = []
                    while position < text.endIndex {
                        let end = text.index(position, offsetBy: 32_000, limitedBy: text.endIndex) ?? text.endIndex
                        result.append(String(text[position..<end])); position = end
                    }
                    chunks = result.isEmpty ? ["(Empty file)"] : result
                }
            } catch { failure = error.localizedDescription }
        }
    }
}
private struct ResearchPDFPreview: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.document = document; view.autoScales = true
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
private struct ResearchPlainTextPreview: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isSelectable = true
        view.font = UIFont.preferredFont(forTextStyle: .body); view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.text = text; view.accessibilityIdentifier = "native-text-preview"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text; view.setContentOffset(.zero, animated: false) }
    }
}

/// Author editing is explicit. Profiles always render the committed canonical
/// manuscript, never the previous export or an inferred paper from a defense.
struct PublicationWorkflowView: View {
    @ObservedObject var workspace: ResearchWorkspaceStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PublicationManuscript()
    @State private var loadedDraft: PublicationManuscript?
    @State private var confirmingDeparture = false
    @State private var expectedRevision: Int?
    @State private var profileID = "plos-one-research"
    @State private var preflight: PublicationPreflight?
    @State private var error: String?
    @State private var loaded = false
    @State private var previewFile: ResearchPreviewFile?
    @State private var exportFiles: [URL] = []
    private var project: ResearchProject? { workspace.project(id: projectID) }
    private var profile: PublicationProfile { PublicationProfile.registry.first { $0.id == profileID }! }
    private var dirty: Bool { draft != project?.publication }
    private var editable: Bool { workspace.canMutateProject(id: projectID) }

    var body: some View {
        List {
            Section("Manuscript") {
                Text("Write or enter your manuscript here. A defense worksheet is not converted into a finished paper. Missing fields remain missing.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("\(dirty ? "Unsaved edits" : "Saved") · revision \(project?.publication?.revision ?? 0)")
                    .accessibilityIdentifier("publication-save-state")
                NavigationLink("Edit content & metadata") {
                    PublicationEditorView(manuscript: $draft, sources: project?.argument?.sources ?? [])
                }.accessibilityIdentifier("edit-publication")
                Button("Save manuscript") { save() }.disabled(!editable || !dirty)
                    .accessibilityIdentifier("save-publication")
                Button("Discard unsaved edits", role: .destructive) { load() }.disabled(!dirty)
                if let reason = workspace.mutationAccessReason(projectID: projectID) { Text(reason).font(.footnote) }
            }
            Section("Publication style") {
                Picker("Venue / article type", selection: $profileID) {
                    ForEach(PublicationProfile.registry) { item in Text(item.label).tag(item.id) }
                }.accessibilityIdentifier("publication-profile")
                Text("Profile \(profile.version)").font(.caption)
                Text(profile.coverageNotes).font(.footnote).foregroundStyle(.secondary)
                Button("Check supported rules") { check() }.accessibilityIdentifier("publication-preflight")
            }
            Section("Preview & export") {
                Text(dirty ? "Save or discard edits before exporting. Style changes never save or rewrite content." : "Exports include the exact committed revision, profile, content/output hashes and unresolved checks.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Render saved manuscript") { render() }.disabled(dirty || project?.publication == nil)
                    .accessibilityIdentifier("render-publication")
                ForEach(exportFiles, id: \.path) { url in
                    Button("Open \(url.lastPathComponent)") { previewFile = .init(url: url) }
                    ShareLink("Share \(url.lastPathComponent)", item: url)
                }
            }
            if let preflight {
                Section("Preflight") {
                    Text(preflight.summary).font(.headline).accessibilityIdentifier("publication-preflight-summary")
                    ForEach(preflight.checks) { check in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(check.outcome.rawValue) · \(check.handling.rawValue)").font(.caption.bold())
                            Text(check.location).font(.headline)
                            Text(check.currentValue)
                            Text(check.requiredAction).font(.footnote).foregroundStyle(.secondary)
                            if let url = URL(string: check.sourceURL), url.scheme == "https",
                               PublicationProfile.registry.flatMap(\.rules).contains(where: { $0.sourceURL == check.sourceURL }) {
                                Link("Rule source instruction", destination: url)
                                    .accessibilityIdentifier("publication-rule-source-\(check.id)")
                            } else { Text(check.sourceURL).font(.caption).textSelection(.enabled) }
                            Text(check.blocksExport ? "Export blocked" : "Preview allowed with unresolved checks disclosed").font(.caption)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
            Section("Citation software & attribution") {
                Text(PublicationRenderer.attribution).font(.footnote).foregroundStyle(.secondary)
                Link("Citation Style Language", destination: URL(string: "https://citationstyles.org/")!)
                    .accessibilityIdentifier("publication-citation-attribution")
            }
            if let error { Section("Needs attention") { Text(error).foregroundStyle(AppTheme.coral) } }
        }
        .navigationTitle("Manuscript styles").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    if dirty && draft != loadedDraft { confirmingDeparture = true }
                    else { dismiss() }
                }.accessibilityIdentifier("publication-back")
            }
        }
        .confirmationDialog("Keep your manuscript edits?", isPresented: $confirmingDeparture, titleVisibility: .visible) {
            Button("Save and leave") { if save() { dismiss() } }.disabled(!editable)
            Button("Discard edits and leave", role: .destructive) { load(); dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("These edits are not saved. Your previously saved revision stays intact until you choose Save.")
        }
        .onAppear { if !loaded { load(); loaded = true } }
        .onChange(of: profileID) { _, _ in preflight = nil; exportFiles = []; check() }
        .onChange(of: draft) { _, _ in preflight = nil; exportFiles = [] }
        .sheet(item: $previewFile) { file in ResearchFilePreview(url: file.url) }
    }
    private func load() {
        draft = project?.publication ?? PublicationManuscript(title: project?.title)
        expectedRevision = project?.publication?.revision
        loadedDraft = draft
        preflight = nil; exportFiles = []; error = nil
    }
    @discardableResult
    private func save() -> Bool {
        do {
            try workspace.savePublication(projectID: projectID, manuscript: draft, expectedRevision: expectedRevision)
            load()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func check() {
        do { preflight = try PublicationEngine.preflight(draft, profile: profile); error = nil }
        catch { preflight = nil; self.error = error.localizedDescription }
    }
    private func render() {
        do {
            guard let manuscript = project?.publication, manuscript == draft else { throw PublicationError.invalid("Save the current manuscript before exporting.") }
            let result = try workspace.exportPublicationFiles(id: projectID, profile: profile)
            exportFiles = result.files
            preflight = result.preflight
            if let pdf = exportFiles.first(where: { $0.pathExtension == "pdf" }) { previewFile = .init(url: pdf) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
}
private struct PublicationEditorView: View {
    @Binding var manuscript: PublicationManuscript
    let sources: [ArgumentSource]
    var body: some View {
        Form {
            Section("Title & abstract") {
                TextField("Title", text: optionalText($manuscript.title), axis: .vertical).accessibilityIdentifier("manuscript-title")
                TextField("Short title", text: optionalText($manuscript.shortTitle))
                TextField("Abstract", text: optionalText($manuscript.abstract), axis: .vertical).lineLimit(4...14).accessibilityIdentifier("manuscript-abstract")
                Text("Blank means missing. Nothing is filled or shortened automatically.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Authors & affiliations") {
                ForEach($manuscript.affiliations) { $affiliation in
                    TextField("Affiliation", text: $affiliation.label)
                    Button("Remove affiliation", role: .destructive) { let id = affiliation.id; manuscript.affiliations.removeAll { $0.id == id } }
                        .disabled(manuscript.authors.contains { $0.affiliationIDs.contains(affiliation.id) })
                        .accessibilityIdentifier("remove-affiliation-\(affiliation.id)")
                    if manuscript.authors.contains(where: { $0.affiliationIDs.contains(affiliation.id) }) {
                        Text("Unlink this affiliation from its authors before removing it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Add affiliation") { manuscript.affiliations.append(.init(label: "")) }
                ForEach($manuscript.authors) { $author in
                    NavigationLink(author.name.isEmpty ? "New author" : author.name) {
                        Form {
                            TextField("Author name", text: $author.name)
                            ForEach(manuscript.affiliations) { affiliation in
                                Toggle(affiliation.label.isEmpty ? "Unnamed affiliation" : affiliation.label,
                                       isOn: membership(affiliation.id, in: $author.affiliationIDs))
                            }
                            Text("Author data remains in the private canonical archive when anonymous presentation is selected.").font(.footnote)
                        }.navigationTitle("Author").researchKeyboard()
                    }
                    Button("Remove author from draft", role: .destructive) { let id = author.id; manuscript.authors.removeAll { $0.id == id } }
                        .accessibilityIdentifier("remove-author-\(author.id)")
                }
                Button("Add author") { manuscript.authors.append(.init(name: "")) }
            }
            Section("Sections") {
                ForEach($manuscript.sections) { $section in
                    NavigationLink(section.heading.isEmpty ? "Untitled section" : section.heading) {
                        PublicationSectionEditor(section: $section, references: manuscript.references, sources: sources,
                            targets: manuscript.allBlocks.map { ($0.id, $0.kind.rawValue) },
                            canRemoveBlock: { id in !manuscript.allBlocks.contains { $0.id != id && $0.crossReferenceIDs.contains(id) } })
                    }
                }
                ForEach(manuscript.sections) { section in
                    Button("Remove section: \(section.heading.isEmpty ? "Untitled section" : section.heading)", role: .destructive) {
                        manuscript.sections.removeAll { $0.id == section.id }
                    }.disabled(!canRemoveSection(section))
                        .accessibilityIdentifier("remove-section-\(section.id)")
                    if !canRemoveSection(section) { Text("Remove incoming cross references before removing this section.").font(.caption) }
                }
                Button("Add section") { manuscript.sections.append(.init(heading: "", blocks: [])) }.accessibilityIdentifier("add-manuscript-section")
            }
            Section("References") {
                ForEach($manuscript.references) { $reference in
                    NavigationLink(reference.title ?? "Untitled reference") { PublicationReferenceEditor(reference: $reference) }
                    Button("Remove reference from draft", role: .destructive) { let id = reference.id; manuscript.references.removeAll { $0.id == id } }
                        .disabled(manuscript.allBlocks.contains { $0.citationIDs.contains(reference.id) })
                        .accessibilityIdentifier("remove-reference-\(reference.id)")
                    if manuscript.allBlocks.contains(where: { $0.citationIDs.contains(reference.id) }) {
                        Text("Unlink this reference from its citing blocks before removing it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Add reference") { manuscript.references.append(.init()) }
            }
            Section("Appendices") {
                ForEach($manuscript.appendices) { $section in
                    NavigationLink(section.heading.isEmpty ? "Untitled appendix" : section.heading) {
                        PublicationSectionEditor(section: $section, references: manuscript.references, sources: sources,
                            targets: manuscript.allBlocks.map { ($0.id, $0.kind.rawValue) },
                            canRemoveBlock: { id in !manuscript.allBlocks.contains { $0.id != id && $0.crossReferenceIDs.contains(id) } })
                    }
                }
                ForEach(manuscript.appendices) { section in
                    Button("Remove appendix: \(section.heading.isEmpty ? "Untitled appendix" : section.heading)", role: .destructive) {
                        manuscript.appendices.removeAll { $0.id == section.id }
                    }.disabled(!canRemoveSection(section))
                        .accessibilityIdentifier("remove-appendix-\(section.id)")
                    if !canRemoveSection(section) { Text("Remove incoming cross references before removing this appendix.").font(.caption) }
                }
                Button("Add appendix") { manuscript.appendices.append(.init(role: .appendix, heading: "", blocks: [])) }
            }
            Section("Author declarations") {
                ForEach(["funding", "competing-interests", "data-availability", "ai-use"], id: \.self) { field in
                    TextField(field, text: Binding(get: { manuscript.declarations[field] ?? "" }, set: { manuscript.declarations[field] = $0 }), axis: .vertical)
                }
                Text("Enter truthful declarations. Empty declarations are flagged; the app never invents 'none'.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Text("Removals change this draft only. Save records a new revision; previous saved revisions remain in history.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Edit manuscript").navigationBarTitleDisplayMode(.inline).researchKeyboard()
    }
    private func canRemoveSection(_ section: PublicationSection) -> Bool {
        let removed = Set(section.blocks.map(\.id))
        return !manuscript.allBlocks.contains { !removed.contains($0.id) && !removed.isDisjoint(with: $0.crossReferenceIDs) }
    }
}
private func membership(_ id: String, in values: Binding<[String]>) -> Binding<Bool> {
    Binding(get: { values.wrappedValue.contains(id) }, set: { enabled in
        values.wrappedValue.removeAll { $0 == id }; if enabled { values.wrappedValue.append(id) }
    })
}
private struct PublicationSectionEditor: View {
    @Binding var section: PublicationSection
    let references: [PublicationReference]
    let sources: [ArgumentSource]
    let targets: [(String, String)]
    let canRemoveBlock: (String) -> Bool
    var body: some View {
        Form {
            TextField("Section heading", text: $section.heading).accessibilityIdentifier("manuscript-section-heading")
            Picker("Semantic role", selection: $section.role) { ForEach(PublicationSectionRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            ForEach($section.blocks) { $block in
                NavigationLink("\(block.kind.rawValue.capitalized): \(block.text.prefix(60))") {
                    PublicationBlockEditor(block: $block, references: references, sources: sources, targets: targets)
                }
                Button("Remove \(block.kind.rawValue) from draft", role: .destructive) { let id = block.id; section.blocks.removeAll { $0.id == id } }
                    .disabled(!canRemoveBlock(block.id))
                    .accessibilityIdentifier("remove-block-\(block.id)")
                if !canRemoveBlock(block.id) { Text("Remove incoming cross references before removing this block.").font(.caption) }
            }
            ForEach(PublicationBlockKind.allCases, id: \.self) { kind in
                Button("Add \(kind.rawValue)") {
                    var block = PublicationBlock(kind: kind, text: "")
                    if kind == .table { block.table = .init(columns: [""], rows: []) }
                    if kind == .figure { block.figure = .init(mediaType: "image/png", data: nil, sha256: nil, altText: nil) }
                    section.blocks.append(block)
                }
            }
        }.navigationTitle("Section").researchKeyboard()
    }
}
private struct PublicationBlockEditor: View {
    @Binding var block: PublicationBlock
    let references: [PublicationReference]
    let sources: [ArgumentSource]
    let targets: [(String, String)]
    @State private var importing = false
    @State private var error: String?
    var body: some View {
        Form {
            Section(block.kind.rawValue.capitalized) {
                TextField(block.kind == .equation ? "Literal equation / notation" : "Exact content", text: $block.text, axis: .vertical)
                    .lineLimit(5...20).accessibilityIdentifier("manuscript-block-text")
                if block.kind == .equation { Text("Literal notation is preserved. Inspect math glyphs; this is not a TeX typesetter.").font(.footnote) }
                if block.kind == .figure || block.kind == .table {
                    TextField("Caption", text: optionalText($block.caption), axis: .vertical)
                }
                if block.kind == .figure {
                    Button("Import PNG or JPEG figure") { importing = true }
                    Text(block.figure?.data == nil ? "Image missing; export blocked" : "Embedded image stored with checksum")
                    TextField("Alternative text", text: Binding(get: { block.figure?.altText ?? "" }, set: { block.figure?.altText = $0 }))
                }
            }
            if block.kind == .table {
                PublicationTableEditor(table: Binding(get: { block.table ?? .init(columns: [""], rows: []) }, set: { block.table = $0 }))
            }
            Section("Citations") {
                ForEach(references) { reference in Toggle(reference.title ?? "Untitled reference", isOn: membership(reference.id, in: $block.citationIDs)) }
                if references.isEmpty { Text("Add references in manuscript metadata, then link them here.") }
            }
            Section("Cross references") {
                ForEach(targets.filter { $0.0 != block.id }, id: \.0) { target in
                    Toggle("\(target.1) · \(target.0.prefix(8))", isOn: membership(target.0, in: $block.crossReferenceIDs))
                }
            }
            Section("Source / evidence links") {
                ForEach(sources) { source in
                    let recorded = block.evidenceLinks.first { UUID(uuidString: $0.sourceID) == source.id }
                    Toggle(source.title, isOn: Binding(get: { block.evidenceLinks.contains { UUID(uuidString: $0.sourceID) == source.id } }, set: { enabled in
                        block.evidenceLinks.removeAll { UUID(uuidString: $0.sourceID) == source.id }
                        if enabled { linkCurrentVersion(of: source) }
                    })).accessibilityIdentifier("publication-source-\(source.id)")
                    if let recorded {
                        Text("Linked version \(recorded.sourceVersion) · current version \(source.version)")
                            .font(.footnote).accessibilityIdentifier("publication-source-version-\(source.id)")
                        if recorded.sourceVersion != String(source.version) {
                            Label("The source changed. This manuscript still cites the recorded version.", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(AppTheme.gold)
                            Button("Relink to current version \(source.version)") { linkCurrentVersion(of: source) }
                                .accessibilityIdentifier("publication-refresh-source-\(source.id)")
                            Text("Relinking updates this draft's version and locator. Save records your decision; prior manuscript revisions remain available.").font(.caption)
                        }
                    } else { Text("Current version \(source.version) · not linked").font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach(block.evidenceLinks.filter { link in !sources.contains { UUID(uuidString: link.sourceID) == $0.id } }, id: \.sourceID) { link in
                    Text("Unavailable source \(link.sourceID) · recorded version \(link.sourceVersion)").font(.footnote)
                    Button("Remove unavailable source link", role: .destructive) { block.evidenceLinks.removeAll { $0.sourceID == link.sourceID } }
                        .accessibilityIdentifier("publication-remove-source-\(link.sourceID)")
                }
                Text("Links retain the selected source version. They do not validate scientific support.").font(.footnote)
            }
            if let error { Text(error).foregroundStyle(AppTheme.coral) }
        }.navigationTitle("Content block").researchKeyboard()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
            do {
                let url = try result.get(), accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 3_000_000 else { throw PublicationError.invalid("Figures must be at most 3 MB.") }
                let data = try Data(contentsOf: url)
                block.figure = .init(mediaType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg", data: data, sha256: PublicationHash.sha256(data), altText: block.figure?.altText)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func linkCurrentVersion(of source: ArgumentSource) {
        block.evidenceLinks.removeAll { UUID(uuidString: $0.sourceID) == source.id }
        block.evidenceLinks.append(.init(sourceID: source.id.uuidString, sourceVersion: String(source.version), evidenceID: nil, locator: source.locator, url: nil))
    }
}
private struct PublicationReferenceEditor: View {
    @Binding var reference: PublicationReference
    var body: some View {
        Form {
            TextField("Reference title", text: optionalText($reference.title))
            TextField("Authors, one full name per line", text: Binding(get: { reference.authors.joined(separator: "\n") }, set: { reference.authors = $0.isEmpty ? [] : $0.components(separatedBy: "\n") }), axis: .vertical)
            TextField("Year", text: Binding(get: { reference.year.map(String.init) ?? "" }, set: { reference.year = Int($0) })).keyboardType(.numberPad)
            TextField("Journal / container", text: optionalText($reference.containerTitle))
            TextField("Volume", text: optionalText($reference.volume))
            TextField("Issue", text: optionalText($reference.issue))
            TextField("Pages / article number", text: optionalText($reference.pages))
            TextField("DOI", text: optionalText($reference.doi))
            TextField("URL", text: optionalText($reference.url)).textInputAutocapitalization(.never)
            Text("Stable reference: \(reference.id)").font(.caption).textSelection(.enabled)
        }.navigationTitle("Reference").researchKeyboard()
    }
}

private struct PublicationTableEditor: View {
    @Binding var table: PublicationTable

    var body: some View {
        Section("Table columns") {
            ForEach(Array(table.columns.indices), id: \.self) { column in
                TextField("Column \(column + 1) label", text: columnBinding(column))
                    .accessibilityIdentifier("publication-table-column-\(column)")
                Button("Remove column \(column + 1) and its cells", role: .destructive) {
                    guard table.columns.indices.contains(column), table.columns.count > 1 else { return }
                    table.columns.remove(at: column)
                    for row in table.rows.indices where table.rows[row].indices.contains(column) {
                        table.rows[row].remove(at: column)
                    }
                }.disabled(table.columns.count <= 1)
                    .accessibilityIdentifier("publication-table-remove-column-\(column)")
            }
            Button("Add column") {
                guard table.columns.count < 30 else { return }
                table.columns.append("")
                for row in table.rows.indices { table.rows[row].append("") }
            }.disabled(table.columns.count >= 30)
                .accessibilityIdentifier("publication-table-add-column")
        }
        Section("Table rows") {
            ForEach(Array(table.rows.indices), id: \.self) { row in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Row \(row + 1)").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(Array(table.columns.indices), id: \.self) { column in
                        TextField(cellLabel(row: row, column: column), text: cellBinding(row: row, column: column), axis: .vertical)
                            .accessibilityLabel(cellLabel(row: row, column: column))
                            .accessibilityIdentifier("publication-table-cell-\(row)-\(column)")
                    }
                    Button("Remove row \(row + 1)", role: .destructive) {
                        guard table.rows.indices.contains(row) else { return }
                        table.rows.remove(at: row)
                    }.accessibilityIdentifier("publication-table-remove-row-\(row)")
                }
            }
            Button("Add row") {
                guard table.rows.count < 1000 else { return }
                table.rows.append(Array(repeating: "", count: table.columns.count))
            }.disabled(table.rows.count >= 1000)
                .accessibilityIdentifier("publication-table-add-row")
            Text("Enter cells directly with the keyboard. Removing a row or column removes its cells from this draft only; your saved revision remains unchanged until Save. Native PDF renders labeled rows.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func columnBinding(_ column: Int) -> Binding<String> {
        Binding(get: { table.columns.indices.contains(column) ? table.columns[column] : "" }, set: { value in
            guard table.columns.indices.contains(column) else { return }
            table.columns[column] = value
        })
    }
    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(get: {
            guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return "" }
            return table.rows[row][column]
        }, set: { value in
            guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
            table.rows[row][column] = value
        })
    }
    private func cellLabel(row: Int, column: Int) -> String {
        let label = table.columns.indices.contains(column) && !table.columns[column].isEmpty ? table.columns[column] : "Column \(column + 1)"
        return "Row \(row + 1), \(label)"
    }
}
