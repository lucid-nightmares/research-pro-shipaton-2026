import SwiftUI

struct LocalReviewView: View {
    @EnvironmentObject private var model: AppModel

    @State private var question = ""
    @State private var evidenceSummary = ""
    @State private var claimNeedingReview = ""
    @State private var boundedWording = ""
    @State private var limitation = ""
    @State private var showingConfirmation = false
    @State private var showingDelete = false
    @State private var shareURL: URL?
    @State private var statusMessage: String?
    @State private var loadedExisting = false

    private var formComplete: Bool {
        [question, evidenceSummary, claimNeedingReview, boundedWording, limitation]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 2_000 }
    }

    var body: some View {
        Form {
            Section {
                Label("Your text stays in this app's protected container. Research OS has no account, cloud sync, advertising, or behavioral analytics. Optional purchase requests never include this text.", systemImage: "lock.shield")
                    .font(.subheadline)
                Text("Do not enter regulated, confidential, or personally identifying research data until your organization has approved the device and backup policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("1. Review") {
                editor("Research question", text: $question, prompt: "What exactly are you trying to learn?")
                editor("Evidence summary", text: $evidenceSummary, prompt: "What did the record actually observe?")
                editor("Claim needing review", text: $claimNeedingReview, prompt: "Which wording may exceed the evidence?")
            }

            Section("2. Repair") {
                editor("Bounded wording", text: $boundedWording, prompt: "Rewrite the claim so its scope matches the record.")
                editor("Limitation that must travel", text: $limitation, prompt: "What must a future reader not infer?")

                Button("Save local draft", systemImage: "square.and.arrow.down") {
                    saveDraft()
                }
                .disabled(!formComplete)

                if model.localReview != nil {
                    Button("Confirm bounded wording", systemImage: "checkmark.seal.fill") {
                        showingConfirmation = true
                    }
                    .disabled(model.localReview?.receiptDigest != nil)
                }
            }

            if let review = model.localReview {
                Section("3. Verify") {
                    LabeledContent("State", value: review.receiptDigest == nil ? "Draft" : "Locally confirmed")
                    if let digest = review.receiptDigest {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Receipt digest").font(.caption).foregroundStyle(.secondary)
                            Text(digest).font(.caption2.monospaced()).textSelection(.enabled)
                        }
                    }
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share local review manifest", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Prepare review manifest", systemImage: "doc.badge.gearshape") {
                            refreshShareURL()
                        }
                    }
                    Button("Delete local review", role: .destructive) { showingDelete = true }
                }
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: 850)
        .frame(maxWidth: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadExistingOnce() }
        .confirmationDialog("Confirm this bounded wording?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Confirm and seal locally") {
                do {
                    _ = try model.confirmLocalReview()
                    statusMessage = "The local review is confirmed. The evidence itself was not independently verified."
                    refreshShareURL()
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your original claim remains in the manifest. Confirmation records your decision; it does not certify the evidence.")
        }
        .confirmationDialog("Delete this local review?", isPresented: $showingDelete) {
            Button("Delete review", role: .destructive) {
                do {
                    try model.deleteLocalReview()
                    clearFields()
                    statusMessage = "The local review was deleted from this app."
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func editor(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextEditor(text: text)
                .frame(minHeight: 82)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            Text("\(text.wrappedValue.count) / 2,000")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(text.wrappedValue.count > 2_000 ? AppTheme.coral : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func saveDraft() {
        do {
            _ = try model.saveLocalReview(
                question: question,
                evidenceSummary: evidenceSummary,
                claimNeedingReview: claimNeedingReview,
                boundedWording: boundedWording,
                limitation: limitation
            )
            statusMessage = "Draft saved locally. Confirm the bounded wording when you are ready."
            refreshShareURL()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadExistingOnce() {
        guard !loadedExisting else { return }
        loadedExisting = true
        guard let review = model.localReview else { return }
        question = review.question
        evidenceSummary = review.evidenceSummary
        claimNeedingReview = review.claimNeedingReview
        boundedWording = review.boundedWording
        limitation = review.limitation
        refreshShareURL()
    }

    private func refreshShareURL() {
        shareURL = try? model.localReviewManifestFile()
    }

    private func clearFields() {
        question = ""
        evidenceSummary = ""
        claimNeedingReview = ""
        boundedWording = ""
        limitation = ""
        shareURL = nil
    }
}
