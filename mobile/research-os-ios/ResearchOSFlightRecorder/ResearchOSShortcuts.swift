#if canImport(AppIntents)
import AppIntents

struct OpenResearchOSIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Research OS"
    static let description = IntentDescription("Opens Research OS so you can review a project or capture an inbox item.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ResearchOSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenResearchOSIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Review research in \(.applicationName)"
            ],
            shortTitle: "Open Research OS",
            systemImageName: "checkmark.shield"
        )
    }
}
#endif
