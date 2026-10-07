import SwiftUI
import StoreKit
import Observation

private struct AppReviewCoordinatorKey: EnvironmentKey {
    static let defaultValue: AppReviewCoordinator? = nil
}

private struct AppReviewPresentationRelayKey: EnvironmentKey {
    static let defaultValue: AppReviewPresentationRelay? = nil
}

extension EnvironmentValues {
    /// Absent in previews, ordinary offline journeys, and the isolated OGS Beta app.
    var appReviewCoordinator: AppReviewCoordinator? {
        get { self[AppReviewCoordinatorKey.self] }
        set { self[AppReviewCoordinatorKey.self] = newValue }
    }

    var appReviewPresentationRelay: AppReviewPresentationRelay? {
        get { self[AppReviewPresentationRelayKey.self] }
        set { self[AppReviewPresentationRelayKey.self] = newValue }
    }
}

/// Hosted roots retain preferences independently of the outer scene. Each root
/// owns an entry, and only the scene's selected, visible root contributes to
/// review eligibility. Scene-level SwiftUI views retain their preferences.
@MainActor
@Observable
final class AppReviewPresentationRelay {
    struct Presentation: Equatable {
        var homeVisible = false
        var blocked = false
    }

    private struct HostedPresentation: Equatable {
        let root: RootView
        let isVisible: Bool
        let presentation: Presentation
    }

    private var hostedPresentations = [UUID: HostedPresentation]()

    fileprivate func update(owner: UUID, root: RootView, isVisible: Bool, homeVisible: Bool, blocked: Bool) {
        let value = HostedPresentation(
            root: root,
            isVisible: isVisible,
            presentation: Presentation(homeVisible: homeVisible, blocked: blocked)
        )
        guard hostedPresentations[owner] != value else { return }
        hostedPresentations[owner] = value
    }

    fileprivate func remove(owner: UUID) {
        hostedPresentations.removeValue(forKey: owner)
    }

    func presentation(for root: RootView) -> Presentation {
        hostedPresentations.values
            .filter { $0.root == root && $0.isVisible }
            .reduce(into: Presentation()) { result, entry in
                result.homeVisible = result.homeVisible || entry.presentation.homeVisible
                result.blocked = result.blocked || entry.presentation.blocked
            }
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
    @State private var coordinator: AppReviewCoordinator
    @State private var presentationRelay = AppReviewPresentationRelay()
    @State private var presentationBlocked = false
    @State private var homeVisible = false
    @ViewBuilder var content: () -> Content

    init(coordinator: AppReviewCoordinator? = nil, @ViewBuilder content: @escaping () -> Content) {
        _coordinator = State(initialValue: coordinator ?? AppReviewCoordinator(
            history: AppReviewDependencies.history
        ))
        self.content = content
    }

    private var context: AppReviewContext {
        let hosted = presentationRelay.presentation(for: nav.main.rootView)
        return appReviewContext(
            scenePhase: scenePhase,
            ogs: ogs,
            nav: nav,
            homeVisible: homeVisible || hosted.homeVisible,
            presentationBlocked: presentationBlocked || hosted.blocked
        )
    }

    var body: some View {
        content()
            .environment(\.appReviewCoordinator, coordinator)
            .environment(\.appReviewPresentationRelay, presentationRelay)
            .onPreferenceChange(AppReviewPresentationBlockedKey.self) {
                presentationBlocked = $0
            }
            .onPreferenceChange(AppReviewHomeVisibleKey.self) {
                homeVisible = $0
            }
            .onChange(of: context, initial: true) { _, newContext in
                #if DEBUG && MAIN_APP
                if SurroundUITestContract.testsAppReviewPresentation {
                    let hosted = presentationRelay.presentation(for: nav.main.rootView)
                    print("APP-REVIEW-CONTEXT root=\(nav.main.rootView.rawValue) home=\(newContext.isHome) blocked=\(newContext.isBlocked) hostedHome=\(hosted.homeVisible) hostedBlocked=\(hosted.blocked) sceneBlocked=\(presentationBlocked) overviewLoading=\(ogs.isLoadingOverview) socket=\(ogs.socketStatus)")
                }
                #endif
                coordinator.updateContext(newContext)
            }
            #if DEBUG && MAIN_APP
            .overlay(alignment: .bottomLeading) {
                if SurroundUITestContract.testsAppReviewPresentation {
                    Text("App review context")
                        .font(.caption2)
                        .padding(4)
                        .background(.regularMaterial)
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.appReviewContext)
                        .accessibilityValue(Text(verbatim: "home=\(context.isHome);blocked=\(context.isBlocked)"))
                }
            }
            #endif
    }
}

/// Applied outside the hosted NavigationStack so its preferences include root
/// content, pushed destinations, and local presentation blockers.
struct AppReviewHostedPresentation: ViewModifier {
    @Environment(\.appReviewPresentationRelay) private var relay
    @State private var owner = UUID()
    @State private var isVisible = false
    @State private var homeVisible = false
    @State private var blocked = false
    let root: RootView

    private func publish() {
        relay?.update(owner: owner, root: root, isVisible: isVisible, homeVisible: homeVisible, blocked: blocked)
    }

    func body(content: Content) -> some View {
        content
            #if DEBUG && MAIN_APP
            .overlay(alignment: .bottomTrailing) {
                if SurroundUITestContract.testsAppReviewPresentation {
                    AppReviewHostedUITestProbe(root: root)
                }
            }
            #endif
            .onPreferenceChange(AppReviewHomeVisibleKey.self) {
                homeVisible = $0
                publish()
            }
            .onPreferenceChange(AppReviewPresentationBlockedKey.self) {
                blocked = $0
                publish()
            }
            .onAppear {
                isVisible = true
                publish()
            }
            .onDisappear {
                isVisible = false
                relay?.remove(owner: owner)
            }
            // Some UIKit hosting integrations also forward preferences to the
            // outer SwiftUI graph. Consume these after the local readers so a
            // retained, inactive tab cannot block through the scene's reader.
            .transformPreference(AppReviewHomeVisibleKey.self) { $0 = false }
            .transformPreference(AppReviewPresentationBlockedKey.self) { $0 = false }
    }
}

#if DEBUG && MAIN_APP
/// A local pending presentation exercises the actual preference modifier inside
/// the hosting boundary without a network request or a system review prompt.
private struct AppReviewHostedUITestProbe: View {
    @Environment(\.appReviewCoordinator) private var coordinator
    @State private var pending = false
    let root: RootView

    var body: some View {
        VStack(spacing: 4) {
            Text("Hosted review coordinator")
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.appReviewHostedCoordinator(root.rawValue))
                .accessibilityValue(coordinator == nil ? "absent" : "present")
            Button(pending ? "Finish pending UI" : "Start pending UI") {
                pending.toggle()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.appReviewPendingToggle)
        }
        .font(.caption2)
        .padding(4)
        .background(.regularMaterial)
        .appReviewPresentationBlocked(pending)
    }
}
#endif

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
    let blocked = presentationBlocked
        || nav.pendingGameOpen != nil
        || nav.home.showingNewGameView
        || nav.home.showingPreferredSettings
        || nav.home.showingSettings
        || nav.main.accountSheet != nil
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
    @Environment(\.appReviewPresentationRelay) private var presentationRelay
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
                                || (presentationRelay?.presentation(for: .home).blocked ?? false)
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
