import SwiftUI

struct RepairView: View {
    @EnvironmentObject private var model: AppModel
    let record: FlightRecord
    let onRecorded: () -> Void

    @State private var showingConfirmation = false
    @State private var showingReset = false
    @State private var localError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SyntheticNotice()

                if let receipt = model.receipt {
                    recordedReceipt(receipt)
                } else {
                    SectionCard(title: "Before — unsupported", systemImage: "xmark.seal") {
                        Text(record.repair.before)
                            .font(.title3.weight(.semibold))
                        Text("Causality and population exceed the record.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.coral)
                    }

                    SectionCard(title: "Choose a bounded repair", systemImage: "person.crop.circle.badge.checkmark") {
                        ForEach(RepairChoice.allCases) { choice in
                            Button {
                                model.selectedChoice = choice
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: model.selectedChoice == choice ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.label).font(.headline)
                                        Text(text(for: choice))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(
                                    model.selectedChoice == choice ? AppTheme.accent.opacity(0.10) : Color(.tertiarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(choice.label). \(text(for: choice))")
                            .accessibilityAddTraits(model.selectedChoice == choice ? .isSelected : [])
                        }

                        Text(record.repair.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            showingConfirmation = true
                        } label: {
                            Label("Record this local decision", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    SectionCard(title: "Authority boundary", systemImage: "hand.raised") {
                        Text("Research OS proposes. You decide. This action creates one durable local iOS receipt; it does not silently rewrite the original example or claim external scientific approval.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let localError {
                    Text(localError)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.coral)
                        .accessibilityLabel("Error: \(localError)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .confirmationDialog(
            "Record this local repair?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Record repair") {
                do {
                    _ = try model.recordDecision()
                    onRecorded()
                } catch {
                    localError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original stays visible. The selected wording and an integrity digest are stored on this device.")
        }
        .confirmationDialog("Reset the local example?", isPresented: $showingReset) {
            Button("Delete local receipt", role: .destructive) {
                do { try model.resetLocalDecision() }
                catch { localError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only the receipt created on this device. The bundled synthetic record is unchanged.")
        }
    }

    private func text(for choice: RepairChoice) -> String {
        choice == .recommended ? record.repair.recommended : record.repair.alternative
    }

    @ViewBuilder
    private func recordedReceipt(_ receipt: RepairReceipt) -> some View {
        SectionCard(title: "Repair recorded locally", systemImage: "checkmark.seal.fill") {
            StatusPill(text: "Original preserved", color: AppTheme.moss)
            Text(receipt.after)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            LabeledContent("Authority", value: receipt.authority)
            LabeledContent("Recorded", value: receipt.recordedAt.formatted(date: .abbreviated, time: .shortened))
            VStack(alignment: .leading, spacing: 4) {
                Text("Receipt digest").font(.caption).foregroundStyle(.secondary)
                Text(receipt.contentDigest)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
            Button("Continue to verification", systemImage: "arrow.right", action: onRecorded)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Reset local example", role: .destructive) { showingReset = true }
                .font(.footnote)
        }
    }
}
