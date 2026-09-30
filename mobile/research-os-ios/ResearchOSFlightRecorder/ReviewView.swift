import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    let record: FlightRecord
    let onReviewRepair: () -> Void

    private var event: JourneyEvent {
        record.journey[min(model.selectedEventIndex, record.journey.count - 1)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SyntheticNotice()

                VStack(alignment: .leading, spacing: 8) {
                    Text(record.project.question)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(record.project.notice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SectionCard(title: "Claim needs review", systemImage: "exclamationmark.bubble") {
                    StatusPill(text: record.driftAlarm.status, color: AppTheme.coral)
                    Text(record.driftAlarm.unsupportedClaim)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(record.driftAlarm.plainReason)
                        .foregroundStyle(.secondary)
                    ForEach(record.phraseFindings) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: finding.status == "SUPPORTED" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(finding.status == "SUPPORTED" ? AppTheme.moss : AppTheme.coral)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("“\(finding.phrase)”").font(.subheadline.bold())
                                Text(finding.note).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ObservationCard(summary: record.dataset.summary)

                SectionCard(title: "Wording supported by this record", systemImage: "text.quote") {
                    Text(record.driftAlarm.supportedClaim)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                        .textSelection(.enabled)
                    Button(action: onReviewRepair) {
                        Label("Review repair options", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                SectionCard(title: "Journey replay", systemImage: "timeline.selection") {
                    Picker("Recorded event", selection: $model.selectedEventIndex) {
                        ForEach(Array(record.journey.enumerated()), id: \.element.id) { index, item in
                            Text("\(index + 1). \(item.title)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.time).font(.caption.monospacedDigit())
                            Spacer()
                            StatusPill(text: event.actor, color: AppTheme.moss)
                        }
                        Text(event.title).font(.headline)
                        Text(event.summary)
                        DisclosureGroup("Technical record") {
                            Text(event.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 4))

                    HStack {
                        Button("Previous", systemImage: "chevron.left") {
                            model.selectEvent(model.selectedEventIndex - 1)
                        }
                        .disabled(model.selectedEventIndex == 0)
                        Spacer()
                        Text("Event \(model.selectedEventIndex + 1) of \(record.journey.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Next", systemImage: "chevron.right") {
                            model.selectEvent(model.selectedEventIndex + 1)
                        }
                        .labelStyle(.titleAndIcon)
                        .disabled(model.selectedEventIndex == record.journey.count - 1)
                    }
                }

                SectionCard(title: "Further checks — not evidence", systemImage: "checklist") {
                    ForEach(record.aiChecks) { check in
                        DisclosureGroup(check.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(check.proposal)
                                Text(check.whyReview)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                    }
                    Text("AI proposals remain quarantined review prompts. They never become evidence or authority by themselves.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }
}

private struct ObservationCard: View {
    let summary: DatasetSummary

    var body: some View {
        SectionCard(title: "What the record observed", systemImage: "chart.bar.doc.horizontal") {
            HStack(spacing: 12) {
                Measure(title: "Quiet", percent: summary.quietAccuracyPercent, count: summary.quietCorrectTotal)
                Measure(title: "Instrumental", percent: summary.musicAccuracyPercent, count: summary.musicCorrectTotal)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("+\(summary.differencePercentagePoints, specifier: "%.1f") percentage points")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.moss)
                Text("Descriptive difference only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(summary.inferenceNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Measure: View {
    let title: String
    let percent: Double
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(percent, specifier: "%.1f")%")
                .font(.title2.bold().monospacedDigit())
            Text("\(count) of 120")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 4))
    }
}
