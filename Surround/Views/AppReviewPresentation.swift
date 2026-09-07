import SwiftUI
import StoreKit

private struct AppReviewCoordinatorKey: EnvironmentKey {
    static let defaultValue: AppReviewCoordinator? = nil
}

extension EnvironmentValues {
    /// Absent in previews, offline journeys, and the isolated OGS Beta app.
    var appReviewCoordinator: AppReviewCoordinator? {
        get { self[AppReviewCoordinatorKey.self] }
        set { self[AppReviewCoordinatorKey.self] = newValue }
    }
}

private struct AppReviewPresentationBlockedKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct AppReviewHomeVisibleKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Includes local overlays and popovers that aren't owned by NavigationService.
    func appReviewPresentationBlocked(_ blocked: Bool) -> some View {
        transformPreference(AppReviewPresentationBlockedKey.self) {
            $0 = $0 || blocked
        }
    }
}

@MainActor
private enum AppReviewDependencies {
    static let history = AppReviewHistoryStore(preferences: userDefaults)
}

/// One coordinator per window, with a shared reservation history for the app.
struct AppReviewScene<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @State private var coordinator = AppReviewCoordinator(
        history: AppReviewDependencies.history
    )
    @State private var presentationBlocked = false
    @State private var homeVisible = false
    @ViewBuilder var content: () -> Content

    private var context: AppReviewContext {
        appReviewContext(
            scenePhase: scenePhase,
            ogs: ogs,
            nav: nav,
            homeVisible: homeVisible,
            presentationBlocked: presentationBlocked
        )
    }

    var body: some View {
        content()
            .environment(\.appReviewCoordinator, coordinator)
            .onPreferenceChange(AppReviewPresentationBlockedKey.self) {
                presentationBlocked = $0
            }
            .onPreferenceChange(AppReviewHomeVisibleKey.self) {
                homeVisible = $0
            }
            .onChange(of: context, initial: true) { _, newContext in
                coordinator.updateContext(newContext)
            }
    }
}

@MainActor
private func appReviewContext(
    scenePhase: ScenePhase,
    ogs: OGSService,
    nav: NavigationService,
    homeVisible: Bool,
    presentationBlocked: Bool
) -> AppReviewContext {
    let home = homeVisible && nav.main.rootView == .home
        && nav.home.activeGame == nil
        && !nav.home.showingGameHistory
        && nav.main.modalLiveGame == nil
    let blocked = presentationBlocked
        || nav.pendingGameOpen != nil
        || nav.home.showingNewGameView
        || nav.home.showingPreferredSettings
        || nav.home.showingSettings
        || nav.main.showWaitingGames
        || ogs.isLoadingOverview
        || ogs.socketStatus != .connected
        || ogs.waitingLiveGames > 0
        || !ogs.autoMatchEntryById.isEmpty
        || ogs.pendingRengoGames > 0
        || !ogs.superchatPeerIds.isEmpty
        || !ogs.conditionalMoveSubmissionGameIDs.isEmpty
        || ogs.liveGames.contains { $0.gamePhase != .finished }
        || ogs.activeGames.values.contains { $0.gamePhase == .stoneRemoval }
    return AppReviewContext(
        isActive: scenePhase == .active,
        isBackground: scenePhase == .background,
        userID: ogs.isLoggedIn ? ogs.user?.id : nil,
        isHome: home,
        hasCorrespondenceTurns:
            !ogs.sortedActiveCorrespondenceGamesOnUserTurn.isEmpty,
        isBlocked: blocked
    )
}

/// StoreKit is called from the Home environment, which identifies the correct scene.
struct AppReviewHomePresentation: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.appReviewCoordinator) private var coordinator
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var nav: NavigationService
    @State private var anchor = AppReviewPresentationAnchor()
    @State private var isVisible = false
    var isBlocked: Bool

    func body(content: Content) -> some View {
        content
            .appReviewPresentationBlocked(isBlocked)
            .preference(key: AppReviewHomeVisibleKey.self, value: isVisible)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .background {
                if coordinator != nil {
                    AppReviewWindowAnchor(anchor: anchor)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .task(id: coordinator?.requestID) {
                guard let coordinator else { return }
                await coordinator.requestIfEligible(
                    present: { requestReview() },
                    finalCheck: {
                        let current = appReviewContext(
                            scenePhase: scenePhase,
                            ogs: ogs,
                            nav: nav,
                            homeVisible: isVisible,
                            presentationBlocked: isBlocked
                        )
                        return current.isActive && current.isHome
                            && !current.isBlocked && anchor.canPresent
                    }
                )
            }
    }
}

/// A narrow UIKit check catches system sheets and presentations in child controllers.
/// It inspects only the window containing Home, never a different connected scene.
@MainActor
private final class AppReviewPresentationAnchor {
    weak var view: UIView?

    var canPresent: Bool {
        guard let window = view?.window,
              window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive,
              let root = window.rootViewController else {
            return false
        }
        var ancestor = view
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0 else { return false }
            ancestor = current.superview
        }
        return !hasPresentation(root)
    }

    private func hasPresentation(_ controller: UIViewController) -> Bool {
        controller.presentedViewController != nil
            || controller.isBeingPresented
            || controller.isBeingDismissed
            || controller.children.contains(where: hasPresentation)
    }
}

private struct AppReviewWindowAnchor: UIViewRepresentable {
    let anchor: AppReviewPresentationAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
