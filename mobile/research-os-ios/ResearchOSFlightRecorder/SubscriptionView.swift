import RevenueCat
import RevenueCatUI
import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject private var subscriptions: SubscriptionController
    @State private var showingPaywall = false
    @State private var showingCustomerCenter = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(subscriptions.state.title, systemImage: statusSymbol)
                        .font(.title3.bold())
                    Text(subscriptions.environmentLabel)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("subscriptionEnvironment")
                    Text(subscriptions.state.detail)
                        .foregroundStyle(.secondary)
                    if let message = subscriptions.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Subscription message: \(message)")
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Always free") {
                Label("Work on your first active research project", systemImage: "doc.text.magnifyingglass")
                Label("Repair and confirm bounded wording", systemImage: "checkmark.seal")
                Label("Create, retain, and export your local review", systemImage: "square.and.arrow.up")
                Label("Stress-test one active project in Defense", systemImage: "shield.lefthalf.filled")
                Text("A downgrade never deletes or hides a local review, receipt, or export. Plus is an optional expansion, not a ransom gate around your work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Research Pro Plus") {
                Label("Keep more than one user-created project active", systemImage: "rectangle.stack.badge.plus")
                Label("Rehearse advanced evidence-specific defenses", systemImage: "bubble.left.and.bubble.right")
                Label("Use the Reproducibility workspace", systemImage: "arrow.triangle.2.circlepath")
                Label("Keep and revisit advanced defense history", systemImage: "clock.arrow.circlepath")
                Text("Compare monthly and annual plans at the current localized store price. No free trial is promised. Your existing research stays readable and exportable after Plus ends.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showingPaywall = true
                } label: {
                    Label(
                        subscriptions.state.grantsPlusAccess ? "View plan options" : "Explore Research Pro Plus",
                        systemImage: "rectangle.stack.badge.plus"
                    )
                }
                .disabled(!subscriptions.offeringContractReviewed || subscriptions.offering == nil || subscriptions.isWorking)

                Button {
                    Task { await subscriptions.restorePurchases() }
                } label: {
                    Label("Restore purchases", systemImage: "arrow.clockwise")
                }
                .disabled(!subscriptions.isConfigured || subscriptions.isWorking)

                Button {
                    showingCustomerCenter = true
                } label: {
                    Label("Manage subscription", systemImage: "person.crop.circle")
                }
                .disabled(
                    !subscriptions.isConfigured ||
                    !subscriptions.customerCenterReviewed ||
                    subscriptions.isWorking
                )
                if subscriptions.isConfigured && !subscriptions.customerCenterReviewed {
                    Text("Customer Center stays disabled until its provider configuration has been explicitly reviewed for this build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if subscriptions.isWorking {
                    ProgressView("Checking the store…")
                } else {
                    Button("Refresh status") {
                        Task { await subscriptions.refresh(forceNetwork: true) }
                    }
                    .disabled(!subscriptions.isConfigured)
                }
            }
            Section {
                LabeledContent("Environment", value: subscriptions.environmentLabel)
                LabeledContent("Verification", value: subscriptions.verificationLabel)
                LabeledContent("Offering", value: subscriptions.offeringContractReviewed ? "default checked" : "Not verified")
                if let date = subscriptions.lastCustomerInfoDate {
                    LabeledContent("CustomerInfo fetched", value: date.formatted(date: .abbreviated, time: .standard))
                }
            } header: {
                Text("Provider diagnostics")
            } footer: {
                Text("Purchases and restores update access only from RevenueCat CustomerInfo. Research Pro never stores a local ‘paid’ switch.")
            }
        }
        .navigationTitle("Plus")
        .task { await subscriptions.refresh() }
        .sheet(isPresented: $showingPaywall, onDismiss: {
            Task { await subscriptions.refresh(forceNetwork: true) }
        }) {
            NavigationStack {
                Group {
                    if let offering = subscriptions.offering {
                        NativeSubscriptionPaywallView(offering: offering) { showingPaywall = false }
                    } else {
                        ContentUnavailableView("Plans unavailable", systemImage: "exclamationmark.triangle",
                            description: Text("The reviewed default offering is unavailable in this environment."))
                    }
                }
                // Reserve real layout space for Restore; a floating toolbar can
                // overlay scroll content and lose its accessibility hit region.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            Task { await subscriptions.restorePurchases() }
                        } label: {
                            Text("Restore purchases")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(!subscriptions.isConfigured || subscriptions.isWorking)
                        .accessibilityIdentifier("paywall-restore-purchases")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .navigationTitle("Research Pro Plus")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingPaywall = false }
                            .accessibilityLabel("Close Plus plans")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCustomerCenter, onDismiss: {
            Task { await subscriptions.refresh(forceNetwork: true) }
        }) {
            NavigationStack {
                CustomerCenterView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingCustomerCenter = false }
                        }
                    }
            }
        }
    }

    private var statusSymbol: String {
        if subscriptions.state.grantsPlusAccess { return "checkmark.seal.fill" }
        switch subscriptions.state {
        case .verificationFailed: return "exclamationmark.shield.fill"
        case .loading: return "hourglass"
        default: return "person.crop.circle.badge.checkmark"
        }
    }
}

/// The app owns this screen; it does not require a published remote paywall.
/// Packages, prices and purchase results still come from RevenueCat's SDK.
private struct NativeSubscriptionPaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionController
    let offering: Offering
    let close: () -> Void
    @State private var selectedIdentifier: String?

    private var packages: [Package] {
        offering.availablePackages.sorted {
            ($0.storeProduct.subscriptionPeriod?.unit.rawValue ?? 0) < ($1.storeProduct.subscriptionPeriod?.unit.rawValue ?? 0)
        }
    }
    private var selectedPackage: Package? {
        packages.first(where: { $0.identifier == selectedIdentifier }) ?? packages.first
    }
    private var continueTitle: String {
        switch subscriptions.storeMode {
        case .testStore: "Continue with Test Store"
        case .appleSandbox: "Continue in Apple sandbox"
        default: "Continue with Plus"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(subscriptions.environmentLabel, systemImage: subscriptions.storeMode == .appStore ? "checkmark.shield" : "testtube.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("native-paywall-environment")
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 38))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Take the next question further.")
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("More room for your research. Deeper practice defending it.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    benefit("More active projects", detail: "Keep several research questions moving together.", symbol: "rectangle.stack.badge.plus")
                    benefit("Advanced defense practice", detail: "Compare contradictions, alternatives, and limits against your evidence.", symbol: "bubble.left.and.bubble.right")
                    benefit("Advanced defense history", detail: "Build richer source-specific sessions as evidence changes. Revisit saved history anytime.", symbol: "clock.arrow.circlepath")
                }
                VStack(spacing: 12) {
                    ForEach(packages, id: \.identifier) { package in
                        planCard(package)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        guard let selectedPackage else { return }
                        Task {
                            if await subscriptions.purchase(package: selectedPackage) { close() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if subscriptions.isWorking { ProgressView().tint(.white) }
                            Text(continueTitle).font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPackage == nil || subscriptions.isWorking || !subscriptions.canStartPurchase)
                    .accessibilityIdentifier("confirm-native-purchase")
                    if let selectedPackage {
                        Text("\(selectedPackage.storeProduct.localizedPriceString) every \(duration(selectedPackage)). Renews automatically until cancelled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("native-paywall-renewal-terms")
                    }
                    if subscriptions.storeMode == .testStore {
                        Text("This is RevenueCat Test Store. No real payment is charged. Test renewals may run faster than the displayed plan period.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("No free trial is promised. Your saved research remains readable and exportable after Plus ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let message = subscriptions.message {
                        Text(message).font(.footnote)
                            .accessibilityIdentifier("native-paywall-message")
                    }
                    if let links = subscriptions.legalLinks {
                        HStack(spacing: 24) {
                            Link("Terms of use", destination: links.terms)
                            Link("Privacy policy", destination: links.privacy)
                        }
                        .font(.footnote)
                    } else {
                        Text("Production terms and privacy policy are awaiting account-holder approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("native-subscription-paywall")
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func planCard(_ package: Package) -> some View {
        let selected = selectedPackage?.identifier == package.identifier
        return Button {
            selectedIdentifier = package.identifier
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.storeProduct.subscriptionPeriod?.unit == .year ? "Annual" : "Monthly")
                        .font(.headline)
                    Text("Billed every \(duration(package))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(package.storeProduct.localizedPriceString)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.isWorking)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("native-plan-\(package.identifier)")
    }

    private func duration(_ package: Package) -> String {
        guard let period = package.storeProduct.subscriptionPeriod else { return "billing period" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value; formatter.allowedUnits = .day
        case .week: components.weekOfMonth = period.value; formatter.allowedUnits = .weekOfMonth
        case .month: components.month = period.value; formatter.allowedUnits = .month
        case .year: components.year = period.value; formatter.allowedUnits = .year
        @unknown default: return "billing period"
        }
        return formatter.string(from: components) ?? "billing period"
    }
}
