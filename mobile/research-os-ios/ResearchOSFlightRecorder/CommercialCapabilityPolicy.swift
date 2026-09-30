import Foundation

enum CommercialCapability: Equatable {
    case createAdditionalActiveProject
    case standardDefense
    case advancedDefense
    case advancedWorkspace
}

enum CommercialCapabilityDecision: Equatable {
    case freeFloor
    case activePlus
    case retainedAfterDowngrade
    case requiresPlus

    var allowsUse: Bool { self != .requiresPlus }

    /// Downgraded work remains inspectable and exportable, but a stale local
    /// marker cannot silently become an authority for further paid mutations.
    var allowsMutation: Bool {
        self == .freeFloor || self == .activePlus
    }
}

struct CommercialCapabilityPolicy {
    static func decision(
        for capability: CommercialCapability,
        subscriptionState: SubscriptionAccessState,
        activeUserProjectCount: Int,
        project: ResearchProject? = nil
    ) -> CommercialCapabilityDecision {
        if subscriptionState.grantsPlusAccess { return .activePlus }

        switch capability {
        case .createAdditionalActiveProject:
            return activeUserProjectCount == 0 ? .freeFloor : .requiresPlus
        case .standardDefense:
            // The one-project free floor includes a real objection/response
            // worksheet. Plus expands capacity and adds advanced surfaces.
            return .freeFloor
        case .advancedDefense:
            // Starting a richer session requires live entitlement authority.
            // Reading or exporting any saved session is never gated here.
            return .requiresPlus
        case .advancedWorkspace:
            guard let project else { return .requiresPlus }
            return project.plusWorkspaceActivatedAt == nil ? .requiresPlus : .retainedAfterDowngrade
        }
    }
}


/// A provider abstraction for exercising expiration at the action boundary in
/// tests. The running UI supplies only its RevenueCat SubscriptionController.
@MainActor
protocol SubscriptionStatusRefreshing: AnyObject {
    var state: SubscriptionAccessState { get }
    func refresh(forceNetwork: Bool) async
}

enum CommercialActionGate {
    @MainActor
    static func refreshAccess(using provider: any SubscriptionStatusRefreshing,
                              workspace: ResearchWorkspaceStore) async -> SubscriptionAccessState {
        await provider.refresh(forceNetwork: true)
        let current = provider.state
        // Do not depend on SwiftUI's later onChange delivery before a command.
        workspace.updateSubscriptionAccess(current)
        return current
    }
}
