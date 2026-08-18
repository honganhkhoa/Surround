//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct MainViewWrapper: View {
    @SceneStorage("sceneID") var sceneID = UUID().uuidString

    #if DEBUG && MAIN_APP
    private struct PreviewDependencies {
        let ogs: OGSService
        let sgs: SurroundService
        let nav: NavigationService
    }

    private let previewDependencies: PreviewDependencies?

    init() {
        previewDependencies = nil
    }

    init(
        previewOGS: OGSService,
        previewSGS: SurroundService,
        previewNavigation: NavigationService
    ) {
        previewDependencies = PreviewDependencies(
            ogs: previewOGS,
            sgs: previewSGS,
            nav: previewNavigation
        )
    }
    #endif

    @ViewBuilder
    var body: some View {
        #if DEBUG && MAIN_APP
        if let previewDependencies {
            previewRootView(using: previewDependencies)
        } else if SurroundUITestContract.isEnabled {
            OfflineUITestRootView()
        } else {
            productionRootView
        }
        #else
        productionRootView
        #endif
    }

    private var productionRootView: some View {
        let ogs = OGSService.instance(forSceneWithID: sceneID)
        let sgs = SurroundService.shared
        let nav = NavigationService.instance(forSceneWithID: sceneID)
        return MainView()
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
    }

    #if DEBUG && MAIN_APP
    private func previewRootView(
        using dependencies: PreviewDependencies
    ) -> some View {
        MainView(allowsRemoteActivity: false)
            .environmentObject(dependencies.ogs)
            .environmentObject(dependencies.sgs)
            .environmentObject(dependencies.nav)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            .environment(\.surroundAllowsLocalPersistence, false)
    }
    #endif
}

#if DEBUG && MAIN_APP
private struct OfflineUITestRootView: View {
    @StateObject private var ogs: OGSService
    @StateObject private var sgs: SurroundService
    @StateObject private var nav: NavigationService
    private let compatibilityScene:
        SurroundUITestContract.CompatibilityScene?

    init() {
        let ogs = OGSService.offlineUITestInstance()
        let sgs = SurroundService.offlineUITestInstance
        let nav = NavigationService()
        let compatibilityScene = SurroundUITestContract.compatibilityScene

        if let compatibilityScene {
            sgs.initializeProductsForPreview()
            nav.configureForCompatibilityScreenshot(compatibilityScene)
        }

        _ogs = StateObject(wrappedValue: ogs)
        _sgs = StateObject(wrappedValue: sgs)
        _nav = StateObject(wrappedValue: nav)
        self.compatibilityScene = compatibilityScene
    }

    var body: some View {
        Group {
            if let compatibilityScene {
                CompatibilityScreenshotRootView(scene: compatibilityScene)
            } else {
                MainView(allowsRemoteActivity: false)
            }
        }
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            #if targetEnvironment(macCatalyst)
            .background(CatalystUITestWindowPositioner())
            #endif
    }
}

private extension NavigationService {
    func configureForCompatibilityScreenshot(
        _ scene: SurroundUITestContract.CompatibilityScene
    ) {
        switch scene {
        case .publicGames:
            main.rootView = .publicGames
        case .messagesInbox:
            main.rootView = .privateMessages
        case .settings:
            main.rootView = .settings
        case .about:
            main.rootView = .about
        case .browser:
            main.rootView = .browser
        default:
            main.rootView = .home
        }
    }
}

private struct CompatibilityScreenshotRootView: View {
    let scene: SurroundUITestContract.CompatibilityScene

    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var sgs: SurroundService
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedOpponent: OGSUser?
    @State private var blitzTimeControl =
        TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
    @State private var liveTimeControl =
        TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
    @State private var correspondenceTimeControl =
        TimeControlSpeed.correspondence.defaultTimeOptions[0]
            .timeControlObject
    @State private var timeControlSpeed = TimeControlSpeed.live
    @State private var isBlitz = false
    @State private var pauseOnWeekend = true
    @State private var rulesSet = OGSRule.japanese
    @State private var komi = OGSRule.japanese.defaultKomi

    private var primaryGame: Game {
        guard let game = ogs.activeGames[
            SurroundUITestContract.screenshotPrimaryGameID
        ] else {
            preconditionFailure(
                "The compatibility fixture is missing its primary game."
            )
        }
        return game
    }

    private var finishedGame: Game {
        let targetGameID = SurroundUITestContract.screenshotHistoryGameIDs[0]
        guard let game = ogs.offlineUITestFinishedGames.first(where: {
            $0.ogsID == targetGameID
        }) else {
            preconditionFailure(
                "The compatibility fixture is missing finished game \(targetGameID)."
            )
        }
        if SurroundUITestContract.simulatesAnalysisDisabled {
            precondition(
                game.gameData?.disableAnalysis == true,
                "The finished playback fixture must disable analysis."
            )
        }
        return game
    }

    private var publicGame: Game {
        guard let game = ogs.publicGames[
            SurroundUITestContract.screenshotPublicGameID
        ] else {
            preconditionFailure(
                "The compatibility fixture is missing its public game."
            )
        }
        return game
    }

    private var messagePeer: OGSUser {
        guard let peerID = ogs.privateMessagesActivePeerIds.sorted().first,
        let firstMessage = ogs.privateMessagesByPeerId[peerID]?.first else {
            preconditionFailure(
                "The compatibility fixture is missing its private messages."
            )
        }
        return firstMessage.from.id == peerID
            ? firstMessage.from
            : firstMessage.to
    }

    private var preferredSetting: OGSChallengeTemplate {
        guard let setting = ogs.remoteSettings[
            .preferredGameSettings
        ]?.first else {
            preconditionFailure(
                "The compatibility fixture is missing its preferred setting."
            )
        }
        return setting
    }

    @ViewBuilder
    private var sceneView: some View {
        switch scene {
        case .welcome, .home, .publicGames, .messagesInbox, .browser:
            MainView(allowsRemoteActivity: false)
        case .settings:
            if horizontalSizeClass == .compact {
                NavigationStack {
                    SettingsView()
                }
            } else {
                MainView(allowsRemoteActivity: false)
            }
        case .about:
            if horizontalSizeClass == .compact {
                NavigationStack {
                    AboutView()
                }
            } else {
                MainView(allowsRemoteActivity: false)
            }
        case .gameHistory:
            NavigationStack {
                GameHistoryView()
            }
        case .messageThread:
            NavigationStack {
                PrivateMessageLog(peer: messagePeer)
                    .navigationTitle(messagePeer.username)
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .thanks:
            NavigationStack {
                ThanksView()
            }
        case .supporter:
            NavigationStack {
                SupporterView()
            }
        case .unsupportedGoogle:
            NavigationStack {
                UnsupportedGoogleLoginView()
            }
        case .activeGameBoard:
            NavigationStack {
                GameDetailView(currentGame: primaryGame)
            }
        case .gameAnalysis:
            NavigationStack {
                GameDetailView(
                    currentGame: primaryGame,
                    analyzeMode: true
                )
            }
        case .zenMode:
            NavigationStack {
                GameDetailView(
                    currentGame: primaryGame,
                    zenMode: true
                )
            }
        case .gameOptions:
            NavigationStack {
                GameDetailView(
                    currentGame: primaryGame,
                    showSettings: true
                )
            }
        case .finishedGamePlayback:
            NavigationStack {
                GameDetailView(
                    currentGame: finishedGame,
                    allowsActiveGamesCarousel: false,
                    analyzeMode: true
                )
            }
        case .publicGameSpectator:
            NavigationStack {
                GameDetailView(
                    currentGame: publicGame,
                    allowsActiveGamesCarousel: false
                )
            }
        case .quickMatch:
            newGameScene(option: .quickMatch)
        case .openChallenges, .rengoOpenChallenges:
            newGameScene(option: .openChallenges)
        case .customGame:
            newGameScene(option: .custom)
        case .opponentPicker:
            NavigationStack {
                UserSelectionView(user: $selectedOpponent)
                    .navigationTitle("Select your opponent ")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .advancedTime:
            NavigationStack {
                TimeSystemPickerView(
                    blitzTimeControl: $blitzTimeControl,
                    liveTimeControl: $liveTimeControl,
                    correspondenceTimeControl: $correspondenceTimeControl,
                    timeControlSpeed: $timeControlSpeed,
                    isBlitz: $isBlitz,
                    pauseOnWeekend: $pauseOnWeekend
                )
            }
        case .advancedRules:
            NavigationStack {
                RulesPickerView(
                    rulesSet: $rulesSet,
                    komi: $komi
                )
            }
        case .waitingGames:
            NavigationStack {
                WaitingGamesView()
            }
        case .preferredSettings:
            NavigationStack {
                PreferredSettingsView()
                    .navigationTitle("Preferred Settings")
            }
        case .preferredSettingEditor:
            NavigationStack {
                CustomGameForm(
                    initialChallenge: preferredSetting,
                    mode: .editPreferredSetting(original: preferredSetting)
                )
                .navigationTitle("Edit preferred setting")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .gameChat:
            NavigationStack {
                GameDetailView(currentGame: primaryGame)
            }
        }
    }

    private func newGameScene(
        option: NewGameView.NewGameOption
    ) -> some View {
        NavigationStack {
            NewGameView(newGameOption: option)
                .navigationTitle("New game")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    var body: some View {
        sceneView
            .modifier(
                CompatibilityScreenshotReadinessModifier(scene: scene)
            )
    }
}

private struct CompatibilityScreenshotReadinessModifier: ViewModifier {
    let scene: SurroundUITestContract.CompatibilityScene
    @State private var isReady = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isReady && scene != .gameOptions {
                    Text(verbatim: scene.rawValue)
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID
                                .compatibilityScreen(scene)
                        )
                }
            }
            .task(id: scene) {
                isReady = false
                // Let navigation, lazy fixture lists, and the first layout pass
                // settle before XCTest treats the route as capture-ready.
                try? await Task.sleep(nanoseconds: 600_000_000)
                isReady = true
            }
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystUITestWindowPositioner: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        PositioningView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class PositioningView: UIView {
        private var effectiveGeometryObservation: NSKeyValueObservation?
        private var ownsWindowScene = false
        private var geometryUpdateCompleted = false
        private var geometryRequestInFlight = false
        private var geometryUpdateAttempts = 0
        private var geometryRetryScheduled = false
        private var geometryRetryCount = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            accessibilityIdentifier = SurroundUITestContract.AccessibilityID
                .catalystWindowGeometry
            accessibilityLabel = "Catalyst window content size"
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()

            effectiveGeometryObservation?.invalidate()
            effectiveGeometryObservation = nil
            ownsWindowScene = false
            updateAccessibilityGeometry()
            guard let windowScene = window?.windowScene else { return }

            effectiveGeometryObservation = windowScene.observe(
                \.effectiveGeometry,
                options: [.initial, .new]
            ) { [weak self, weak windowScene] _, _ in
                DispatchQueue.main.async {
                    guard let self,
                          let windowScene,
                          self.window?.windowScene === windowScene else {
                        return
                    }
                    self.updateAccessibilityGeometry()
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.window?.windowScene === windowScene else {
                    return
                }
                let claim = OfflineUITestWindowCoordinator.claim(windowScene)
                switch claim {
                case .rejected:
                    UIApplication.shared.requestSceneSessionDestruction(
                        windowScene.session,
                        options: nil
                    )
                    return
                case .freshDefault:
                    accessibilityIdentifier = SurroundUITestContract
                        .AccessibilityID.catalystFreshWindowGeometry
                case .primary:
                    break
                }

                if claim == .primary,
                   SurroundUITestContract.shouldUseCatalystDefaultWindowSize {
                    OfflineUITestWindowCoordinator.openFreshDefaultScene(
                        from: windowScene
                    )
                } else {
                    for session in UIApplication.shared.openSessions
                        where session.persistentIdentifier
                            != windowScene.session.persistentIdentifier {
                        UIApplication.shared.requestSceneSessionDestruction(
                            session,
                            options: nil
                        )
                    }
                }

                isAccessibilityElement = true
                ownsWindowScene = true
                updateAccessibilityGeometry()
                setNeedsLayout()
                scheduleGeometryUpdateIfReady()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateAccessibilityGeometry()
            scheduleGeometryUpdateIfReady()
        }

        private func scheduleGeometryUpdateIfReady() {
            guard ownsWindowScene,
                  !geometryRequestInFlight,
                  !geometryRetryScheduled,
                  geometryUpdateAttempts < 3,
                  let window,
                  bounds.width > 0,
                  bounds.height > 0,
                  window.windowScene?.activationState != .unattached else {
                return
            }

            guard let contentSize = requestedContentSize else {
                geometryUpdateCompleted = true
                return
            }
            if geometryUpdateCompleted,
               contentSizeApproximatelyMatches(bounds.size, contentSize) {
                return
            }

            geometryUpdateCompleted = false
            geometryRequestInFlight = true
            DispatchQueue.main.async { [weak self] in
                self?.requestGeometryUpdate()
            }
        }

        private func requestGeometryUpdate() {
            guard let window,
                  let windowScene = window.windowScene else {
                retryGeometryUpdate()
                return
            }

            guard windowScene.activationState == .foregroundActive else {
                retryGeometryUpdate()
                return
            }

            guard !windowScene.isFullScreen else {
                geometryRequestInFlight = false
                return
            }

            guard let contentSize = requestedContentSize else {
                geometryRequestInFlight = false
                geometryUpdateCompleted = true
                return
            }
            let currentSystemFrame = windowScene.effectiveGeometry.systemFrame
            let currentContentSize = bounds.size
            guard !currentSystemFrame.isNull,
                  !currentSystemFrame.isInfinite,
                  currentSystemFrame.width.isFinite,
                  currentSystemFrame.height.isFinite,
                  currentSystemFrame.width > 0,
                  currentSystemFrame.height > 0,
                  currentContentSize.width.isFinite,
                  currentContentSize.height.isFinite,
                  currentContentSize.width > 0,
                  currentContentSize.height > 0 else {
                retryGeometryUpdate()
                return
            }

            if contentSizeApproximatelyMatches(
                currentContentSize,
                contentSize
            ) {
                updateAccessibilityGeometry()
                geometryRequestInFlight = false
                geometryUpdateCompleted = true
                return
            }

            let contentToSystemScale =
                currentSystemFrame.width / currentContentSize.width
            guard contentToSystemScale.isFinite,
                  contentToSystemScale > 0 else {
                retryGeometryUpdate()
                return
            }
            let chromeSize = CGSize(
                width: max(
                    0,
                    currentSystemFrame.width
                        - currentContentSize.width * contentToSystemScale
                ),
                height: max(
                    0,
                    currentSystemFrame.height
                        - currentContentSize.height * contentToSystemScale
                )
            )
            let targetSystemSize = CGSize(
                width: contentSize.width * contentToSystemScale
                    + chromeSize.width,
                height: contentSize.height * contentToSystemScale
                    + chromeSize.height
            )
            let targetSystemFrame = CGRect(
                origin: currentSystemFrame.origin,
                size: targetSystemSize
            )
            if let sizeRestrictions = windowScene.sizeRestrictions {
                print(
                    "Offline UI-test window size restrictions: "
                        + "minimum \(sizeRestrictions.minimumSize); "
                        + "maximum \(sizeRestrictions.maximumSize)."
                )
            }
            print(
                "Offline UI-test window geometry request: content "
                    + "\(Int(currentContentSize.width))x"
                    + "\(Int(currentContentSize.height)) -> "
                    + "\(Int(contentSize.width))x\(Int(contentSize.height)); "
                    + "system \(currentSystemFrame) -> \(targetSystemFrame)."
            )
            let preferences = UIWindowScene.GeometryPreferences.Mac(
                systemFrame: targetSystemFrame
            )
            geometryUpdateAttempts += 1
            let requestAttempt = geometryUpdateAttempts
            windowScene.requestGeometryUpdate(preferences) { [weak self] error in
                guard let self,
                      geometryUpdateAttempts == requestAttempt else {
                    return
                }
                print(
                    "Offline UI-test window geometry update failed: "
                        + error.localizedDescription
                )
                retryGeometryUpdate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                [weak self] in
                guard let self,
                      geometryRequestInFlight,
                      geometryUpdateAttempts == requestAttempt,
                      self.window != nil else { return }
                let updatedContentSize = bounds.size
                updateAccessibilityGeometry()
                guard contentSizeApproximatelyMatches(
                    updatedContentSize,
                    contentSize
                ) else {
                    print(
                        "Offline UI-test window geometry update did not "
                            + "reach \(Int(contentSize.width))x"
                            + "\(Int(contentSize.height)); content is "
                            + "\(Int(updatedContentSize.width))x"
                            + "\(Int(updatedContentSize.height))."
                    )
                    retryGeometryUpdate()
                    return
                }
                geometryRequestInFlight = false
                geometryUpdateCompleted = true
            }
        }

        private func retryGeometryUpdate() {
            geometryRequestInFlight = false
            geometryUpdateCompleted = false
            guard geometryUpdateAttempts < 3,
                  !geometryRetryScheduled,
                  geometryRetryCount < 30 else {
                return
            }

            geometryRetryCount += 1
            geometryRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                [weak self] in
                guard let self else { return }
                geometryRetryScheduled = false
                setNeedsLayout()
                scheduleGeometryUpdateIfReady()
            }
        }

        private func updateAccessibilityGeometry() {
            let contentSize = bounds.size
            guard window != nil,
                  contentSize.width.isFinite,
                  contentSize.height.isFinite,
                  contentSize.width > 0,
                  contentSize.height > 0 else {
                accessibilityValue = "unavailable"
                return
            }

            let contentGeometry = formattedGeometry(contentSize)
            let windowGeometry = formattedGeometry(window?.bounds.size)
            let systemGeometry = formattedGeometry(
                window?.windowScene?.effectiveGeometry.systemFrame.size
            )
            let presentation = window?.windowScene?.isFullScreen == true
                ? "full-screen"
                : "windowed"
            let geometryComponents = [
                contentGeometry,
                "window-\(windowGeometry)",
                "system-\(systemGeometry)",
                presentation,
            ]
            accessibilityValue = geometryComponents.joined(separator: "|")
        }

        private func formattedGeometry(_ size: CGSize?) -> String {
            guard let size else { return "unavailable" }
            return [
                Int(size.width.rounded()),
                Int(size.height.rounded()),
            ]
                .map(String.init)
                .joined(separator: "x")
        }

        private func contentSizeApproximatelyMatches(
            _ first: CGSize,
            _ second: CGSize
        ) -> Bool {
            abs(first.width - second.width) <= 0.5
                && abs(first.height - second.height) <= 0.5
        }

        private var requestedContentSize: CGSize? {
            if SurroundUITestContract.shouldUseCatalystDefaultWindowSize {
                return nil
            }
            return SurroundUITestContract.catalystWindowSize
                ?? CGSize(width: 1_200, height: 760)
        }

        deinit {
            effectiveGeometryObservation?.invalidate()
        }
    }
}

private enum OfflineUITestWindowCoordinator {
    enum Claim: Equatable {
        case primary
        case freshDefault
        case rejected
    }

    private static var claimedSessionIdentifier: String?
    private static var defaultSizeBootstrapSessionIdentifier: String?
    private static var defaultSizeBootstrapSessionIdentifiers = Set<String>()
    private static var freshDefaultRequestStarted = false
    private static var freshDefaultSessionIdentifier: String?

    static func claim(_ windowScene: UIWindowScene) -> Claim {
        let sessionIdentifier = windowScene.session.persistentIdentifier
        if SurroundUITestContract.shouldUseCatalystDefaultWindowSize {
            if let freshDefaultSessionIdentifier {
                return freshDefaultSessionIdentifier == sessionIdentifier
                    ? .freshDefault
                    : .rejected
            }
            if let defaultSizeBootstrapSessionIdentifier {
                if defaultSizeBootstrapSessionIdentifier
                    == sessionIdentifier {
                    return .primary
                }

                guard freshDefaultRequestStarted,
                      !defaultSizeBootstrapSessionIdentifiers.contains(
                        sessionIdentifier
                      ) else {
                    return .rejected
                }

                // A sessionless activation request creates exactly one fresh
                // WindowGroup scene after the restored bootstrap sessions.
                freshDefaultSessionIdentifier = sessionIdentifier
                claimedSessionIdentifier = sessionIdentifier
                return .freshDefault
            }

            defaultSizeBootstrapSessionIdentifier = sessionIdentifier
            claimedSessionIdentifier = sessionIdentifier
            return .primary
        }
        if let claimedSessionIdentifier {
            return claimedSessionIdentifier == sessionIdentifier
                ? .primary
                : .rejected
        } else {
            claimedSessionIdentifier = sessionIdentifier
            return .primary
        }
    }

    static func openFreshDefaultScene(from bootstrapScene: UIWindowScene) {
        guard SurroundUITestContract.shouldUseCatalystDefaultWindowSize,
              defaultSizeBootstrapSessionIdentifier
                == bootstrapScene.session.persistentIdentifier,
              !freshDefaultRequestStarted else {
            return
        }

        let openSessions = UIApplication.shared.openSessions
        defaultSizeBootstrapSessionIdentifiers = Set(
            openSessions.map(\.persistentIdentifier)
        )
        freshDefaultRequestStarted = true

        for session in openSessions
            where session.persistentIdentifier
                != bootstrapScene.session.persistentIdentifier {
            UIApplication.shared.requestSceneSessionDestruction(
                session,
                options: nil
            )
        }

        UIApplication.shared.activateSceneSession(
            for: UISceneSessionActivationRequest()
        ) { error in
            print(
                "Offline UI-test fresh default scene activation failed: "
                    + error.localizedDescription
            )
        }
    }
}
#endif
#endif

#if DEBUG && MAIN_APP
private struct MainViewWrapperPreview: View {
    @StateObject private var ogs = OGSService.previewInstance()
    @StateObject private var sgs = SurroundService.previewInstance()
    @StateObject private var nav = NavigationService()

    var body: some View {
        MainViewWrapper(
            previewOGS: ogs,
            previewSGS: sgs,
            previewNavigation: nav
        )
    }
}

#Preview("App shell — Signed out") {
    MainViewWrapperPreview()
}
#endif
