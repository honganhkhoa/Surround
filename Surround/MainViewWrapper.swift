//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct MainViewWrapper: View {
    @SceneStorage("sceneID") var sceneID = UUID().uuidString

    @ViewBuilder
    var body: some View {
        #if DEBUG && MAIN_APP
        if SurroundUITestContract.isEnabled {
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
        guard let game = ogs.offlineUITestFinishedGames.first else {
            preconditionFailure(
                "The compatibility fixture is missing its finished game."
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
        PositioningView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class PositioningView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let windowScene = window?.windowScene else { return }

            DispatchQueue.main.async {
                guard OfflineUITestWindowCoordinator.claim(windowScene) else {
                    UIApplication.shared.requestSceneSessionDestruction(
                        windowScene.session,
                        options: nil
                    )
                    return
                }

                for session in UIApplication.shared.openSessions
                    where session.persistentIdentifier != windowScene.session.persistentIdentifier {
                    UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
                }

                guard windowScene.activationState != .unattached else { return }

                let preferences = UIWindowScene.GeometryPreferences.Mac(
                    systemFrame: CGRect(x: 100, y: 100, width: 1200, height: 760)
                )
                windowScene.requestGeometryUpdate(preferences)
            }
        }
    }
}

private enum OfflineUITestWindowCoordinator {
    private static var claimedSessionIdentifier: String?

    static func claim(_ windowScene: UIWindowScene) -> Bool {
        let sessionIdentifier = windowScene.session.persistentIdentifier
        if let claimedSessionIdentifier {
            return claimedSessionIdentifier == sessionIdentifier
        } else {
            claimedSessionIdentifier = sessionIdentifier
            return true
        }
    }
}
#endif
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainViewWrapper()
    }
}
