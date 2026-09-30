import SwiftUI

struct VerifyView: View {
    @EnvironmentObject private var model: AppModel
    let record: FlightRecord

    @State private var shareURL: URL?
    @State private var localError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SyntheticNotice()

                SectionCard(
                    title: model.receipt == nil ? "Preview manifest" : "Local manifest ready",
                    systemImage: model.receipt == nil ? "doc.text" : "checkmark.shield.fill"
                ) {
                    StatusPill(
                        text: model.receipt == nil ? "Repair pending" : "Integrity fields complete",
                        color: model.receipt == nil ? AppTheme.coral : AppTheme.moss
                    )
                    LabeledContent("Question", value: record.project.question)
                    LabeledContent("Active claim", value: model.receipt?.after ?? record.driftAlarm.unsupportedClaim)
                    LabeledContent("Evidence", value: record.capsule.evidenceSummary)
                }

                SectionCard(title: "What travels with the record", systemImage: "shippingbox") {
                    ForEach(record.capsule.contents, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                    }
                }

                SectionCard(title: "Limits that stay attached", systemImage: "exclamationmark.shield") {
                    ForEach(record.capsule.limitations, id: \.self) { limitation in
                        Label {
                            Text(limitation).font(.subheadline)
                        } icon: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(AppTheme.coral)
                        }
                    }
                }

                SectionCard(title: "Export", systemImage: "square.and.arrow.up") {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share review manifest", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button("Prepare manifest", systemImage: "doc.badge.gearshape") {
                            refreshShareURL()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("The JSON manifest contains the active claim, evidence summary, attached limitations, and local repair receipt when present. Sharing is always initiated by you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SectionCard(title: "Verification boundary", systemImage: "checkmark.shield") {
                    Text(model.receipt == nil
                         ? "Preview only. Record a repair before treating the manifest as a completed local review."
                         : "The app verifies its bundled example and local receipt structure. It does not claim a scientific rerun, independent validation, or publication.")
                        .foregroundStyle(.secondary)
                }

                if let localError {
                    Text(localError)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.coral)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .onAppear { refreshShareURL() }
        .onChange(of: model.receipt) { _, _ in refreshShareURL() }
    }

    private func refreshShareURL() {
        do {
            shareURL = try model.manifestFile()
            localError = nil
        } catch {
            localError = "The review manifest could not be prepared. \(error.localizedDescription)"
        }
    }
}
