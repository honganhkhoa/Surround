//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI
import WidgetKit
import Combine

struct MainView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var ogs: OGSService

    let allowsRemoteActivity: Bool
    
    @State var backgroundTask: PlatformBackgroundTask?
    @State var widgetInfos = [WidgetInfo]()
    @State var firstLaunch = true

    @EnvironmentObject var nav: NavigationService

    init(allowsRemoteActivity: Bool = true) {
        self.allowsRemoteActivity = allowsRemoteActivity
    }

    func updateDisplaySleepPrevention() {
        guard allowsRemoteActivity else { return }
        let hasLiveGame = !ogs.liveGames.isEmpty || ogs.waitingLiveGames > 0
        SystemPlatformServices.shared.setPreventsDisplaySleep(
            scenePhase == .active && hasLiveGame
        )
    }

    func endBackgroundTask() {
        SystemPlatformServices.shared.endBackgroundTask(backgroundTask)
        backgroundTask = nil
    }
    
    func onAppActive(newLaunch: Bool) {
        guard allowsRemoteActivity else { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            if case .success(let widgetInfos) = result {
                self.widgetInfos = widgetInfos
            }
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        ogs.ensureConnect(thenExecute: {
            if ogs.isLoggedIn {
                ogs.updateUIConfig()
                if newLaunch {
                    if let latestOverview = userDefaults[.latestOGSOverview] {
                        if let overviewData = try? JSONSerialization.jsonObject(with: latestOverview) as? [String: Any] {
                            ogs.processOverview(overview: overviewData)
                        }
                    }
                }
                ogs.loadOverview(allowsCache: false, finishCallback: {
                    ogs.subscribeToSeekGraph()
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(5)), execute: {
                        if !nav.home.showingNewGameView {
                            ogs.unsubscribeFromSeekGraphWhenDone()
                        }
                    })
                })
            }
            if nav.main.rootView == .publicGames {
                ogs.fetchPublicGames()
            }
        })
    }
    
    func navigateTo(appURL: URL) {
        if let rootViewName = appURL.host, let rootView = RootView(rawValue: rootViewName) {
            nav.main.rootView = rootView
            switch rootView {
            case .home:
                if appURL.pathComponents.count > 1 {
                    if let ogsGameId = Int(appURL.pathComponents[1]) {
                        nav.home.ogsIdToOpen = ogsGameId
                    }
                }
            case .publicGames:
                if appURL.pathComponents.count > 1 {
                    if let ogsGameId = Int(appURL.pathComponents[1]) {
                        nav.publicGames.ogsIdToOpen = ogsGameId
                    }
                }
            default:
                break
            }
        }
    }

    var body: some View {
        if firstLaunch {
            DispatchQueue.main.async {
                if self.firstLaunch {
                    self.firstLaunch = false
                    if allowsRemoteActivity {
                        self.onAppActive(newLaunch: true)
                    }
                }
            }
        }

        let navigationCurrentView = Binding<RootView>(
            get: { nav.main.rootView },
            set: { nav.main.rootView = $0 }
        )

        return ZStack(alignment: .top) {
            TabView(selection: navigationCurrentView) {
                Tab(value: RootView.home) {
                    RootView.home.navigationView
                } label: {
                    RootView.home.label
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationHome)
                Tab(value: RootView.publicGames) {
                    RootView.publicGames.navigationView
                } label: {
                    RootView.publicGames.label
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationPublicGames)
                if ogs.privateMessagesActivePeerIds.count > 0 {
                    Tab(value: RootView.privateMessages) {
                        RootView.privateMessages.navigationView
                    } label: {
                        if horizontalSizeClass == .compact {
                            Label(
                                "Messages",
                                systemImage:
                                    RootView.privateMessages.systemImage
                            )
                        } else {
                            RootView.privateMessages.label
                        }
                    }
                }
                TabSection("Surround") {
                    Tab(value: RootView.settings) {
                        RootView.settings.navigationView
                    } label: {
                        RootView.settings.label
                    }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationSettings)
                    Tab(value: RootView.about) {
                        RootView.about.navigationView
                    } label: {
                        RootView.about.label
                    }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationAbout)
                }
                .hidden(horizontalSizeClass == .compact)
                .defaultVisibility(.hidden, for: .tabBar)
                TabSection("OGS") {
                    Tab(value: RootView.browser) {
                        RootView.browser.navigationView
                    } label: {
                        RootView.browser.label
                    }
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationBrowser)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .fullScreenCover(isPresented: Binding(
                                get: { nav.main.modalLiveGame != nil },
                                set: { if !$0 { nav.main.modalLiveGame = nil } })
            ) {
                ZStack(alignment: .top) {
                    NavigationStack {
                        GameDetailView(currentGame: nav.main.modalLiveGame)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(action: { nav.main.modalLiveGame = nil }) {
                                        Text("Close")
                                    }
                                }
                            }
                    }
                    if ogs.isLoggedIn {
                        NotificationPopup()
                    }
                }
                .environmentObject(ogs)
                .environmentObject(nav)
            }
            .sheet(isPresented: $nav.main.showWaitingGames) {
                NavigationStack {
                    WaitingGamesView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(action: { nav.main.showWaitingGames = false }) {
                                    Text("Close")
                                }
                            }
                        }
                        .environmentObject(ogs)
                        .environmentObject(nav)
                }
            }
            if ogs.isLoggedIn {
                NotificationPopup()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard allowsRemoteActivity else { return }
            if phase == .active {
                updateDisplaySleepPrevention()
                self.onAppActive(newLaunch: false)
            } else if phase == .background {
                SystemPlatformServices.shared.setPreventsDisplaySleep(false)
                self.backgroundTask = SystemPlatformServices.shared.beginBackgroundTask {
                    self.endBackgroundTask()
                }
                userDefaults[.cachedOGSGames] = [Int: Data]()
                if self.widgetInfos.count > 0 {
                    WidgetCenter.shared.reloadAllTimelines()
                    self.endBackgroundTask()
                } else {
                    ogs.loadOverview(finishCallback: {
                        self.endBackgroundTask()
                    })
                }
            }
        }
        .onReceive(Publishers.CombineLatest(ogs.$liveGames, ogs.$waitingLiveGames), perform: { liveGames, waitingLiveGames in
            guard allowsRemoteActivity else { return }
            SystemPlatformServices.shared.setPreventsDisplaySleep(
                scenePhase == .active && (!liveGames.isEmpty || waitingLiveGames > 0)
            )
        })
        .onOpenURL { url in
            navigateTo(appURL: url)
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainView()
                .environmentObject(OGSService.previewInstance(
                    user: OGSUser(username: "kata-bot", id: 592684),
                    activeGames: [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2]
                ))
            MainView()
                .environmentObject(OGSService.previewInstance())
        }
        .environmentObject(NavigationService.shared)
    }
}
