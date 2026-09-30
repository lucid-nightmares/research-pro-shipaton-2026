import SwiftUI

@main
struct ResearchOSFlightRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @StateObject private var subscriptions = SubscriptionController()
    @StateObject private var workspace = ResearchWorkspaceStore(projects: [])

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(subscriptions)
                .environmentObject(workspace)
                .tint(AppTheme.accent)
                .task {
                    workspace.updateSubscriptionAccess(subscriptions.state)
                    model.load()
                }
                .onChange(of: subscriptions.state) { _, state in
                    workspace.updateSubscriptionAccess(state)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { try? workspace.flushPendingChanges() }
                    else { Task { await subscriptions.refresh() } }
                }
        }
    }
}
