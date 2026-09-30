import SwiftUI
import UIKit

enum AppTheme {
    // UI-01: Semantic foregrounds and surfaces follow light/dark appearance.
    static let ink = Color.primary
    static let paper = Color(uiColor: .secondarySystemBackground)
    static let accent = adaptive(light: 0x245CC5, dark: 0x9ABFFF)
    static let gold = adaptive(light: 0x855500, dark: 0xF3CB75)
    static let coral = adaptive(light: 0xB42318, dark: 0xFFB4AC)
    static let moss = adaptive(light: 0x216348, dark: 0x8ED5AF)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct SyntheticNotice: View {
    var body: some View {
        // UI-02: Plain context strip; no decorative warning-colored card.
        Label("Invented example · on this device", systemImage: "doc.text")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityLabel("Invented example data. Stored only on this device.")
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        // UI-03: Document sections replace nested floating cards.
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        // UI-04: Status stays readable without color or capsule decoration.
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ResearchKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.accessibilityIdentifier("dismiss-keyboard")
                }
            }
    }
}

extension View {
    func researchKeyboard() -> some View { modifier(ResearchKeyboardModifier()) }
}
