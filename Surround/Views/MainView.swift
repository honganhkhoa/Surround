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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var ogs: OGSService
    
    @State var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State var widgetInfos = [WidgetInfo]()
    @State var firstLaunch = true

    @EnvironmentObject var nav: NavigationService
    
    func onAppActive(newLaunch: Bool) {
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
                    self.onAppActive(newLaunch: true)
                }
            }
        }
        var compactSizeClass = false
        #if os(iOS)
        compactSizeClass = horizontalSizeClass == .compact
        #endif
        let navigationCurrentView = Binding<RootView?>(
            get: { nav.main.rootView },
            set: { if let rootView = $0 { nav.main.rootView = rootView } }
        )
        return ZStack(alignment: .top) {
            Group {
                if compactSizeClass {
                    NavigationStack {
                        nav.main.rootView.view
                            .modifier(RootViewSwitchingMenu())
                    }
                } else {
                    NavigationSplitView(columnVisibility: Binding(
                        get: { nav.columnVisibility },
                        set: { nav.columnVisibility = $0 })) {
                        List(selection: navigationCurrentView) {
                            RootView.home.navigationLink(currentView: navigationCurrentView)
                            RootView.publicGames.navigationLink(currentView: navigationCurrentView)
                            if ogs.privateMessagesActivePeerIds.count > 0 {
                                RootView.privateMessages.navigationLink(currentView: navigationCurrentView)
                            }
                            Divider()
                            RootView.settings.navigationLink(currentView: navigationCurrentView)
                            RootView.about.navigationLink(currentView: navigationCurrentView)
                            Divider()
                            RootView.browser.navigationLink(currentView: navigationCurrentView)
                            RootView.forums.navigationLink(currentView: navigationCurrentView)
                        }
                        .listStyle(SidebarListStyle())
                        .navigationTitle("Surround")
                    } detail: {
                        NavigationStack {
                            nav.main.rootView.view
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(
                                get: { nav.main.modalLiveGame != nil },
                                set: { if !$0 { nav.main.modalLiveGame = nil } })
            ) {
                ZStack(alignment: .top) {
                    NavigationView {
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
                NavigationView {
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
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                self.onAppActive(newLaunch: false)
            } else if phase == .background {
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                })
                userDefaults[.cachedOGSGames] = [Int: Data]()
                if self.widgetInfos.count > 0 {
                    WidgetCenter.shared.reloadAllTimelines()
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                } else {
                    ogs.loadOverview(finishCallback: {
                        UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                        self.backgroundTaskID = .invalid
                    })
                }
            }
        }
        .onReceive(Publishers.CombineLatest(ogs.$liveGames, ogs.$waitingLiveGames), perform: { liveGames, waitingLiveGames in
            UIApplication.shared.isIdleTimerDisabled = !liveGames.isEmpty || waitingLiveGames > 0
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
