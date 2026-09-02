//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI
import WidgetKit
import Combine

private struct SurroundAllowsRemoteActivityKey: EnvironmentKey {
    static let defaultValue = true
}

private struct SurroundAllowsLocalPersistenceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Allows views to start external network, subscription, and authentication work.
    /// Production defaults to enabled; deterministic preview and offline roots opt out.
    var surroundAllowsRemoteActivity: Bool {
        get { self[SurroundAllowsRemoteActivityKey.self] }
        set { self[SurroundAllowsRemoteActivityKey.self] = newValue }
    }

    /// Allows views to persist local preferences and read-state changes.
    /// UI-test roots keep the production default; previews opt out explicitly.
    var surroundAllowsLocalPersistence: Bool {
        get { self[SurroundAllowsLocalPersistenceKey.self] }
        set { self[SurroundAllowsLocalPersistenceKey.self] = newValue }
    }
}

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

    private var handledExternalEventRoots: Set<String> {
        Set(RootView.allCases.map(\.rawValue))
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
                        // Release Home's short-lived refresh ownership. New
                        // Game and Preferred Settings keep independent owners
                        // while their screens remain visible.
                        ogs.unsubscribeFromSeekGraphWhenDone()
                    })
                })
            }
            if nav.main.rootView == .publicGames {
                ogs.fetchPublicGames()
            }
        })
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
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.navigationMessages
                    )
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
                        GameDetailView(currentGame: $nav.main.modalLiveGame)
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
            nav.handle(appURL: url)
        }
        .handlesExternalEvents(
            preferring: scenePhase == .active
                ? handledExternalEventRoots
                : [],
            allowing: handledExternalEventRoots
        )
        .environment(\.surroundAllowsRemoteActivity, allowsRemoteActivity)
    }
}

#if DEBUG
#Preview("Main navigation — Signed in") {
    MainView(allowsRemoteActivity: false)
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: [
                    TestData.Ongoing19x19wBot1,
                    TestData.Ongoing19x19wBot2,
                ]
            )
        )
        .environmentObject(NavigationService())
        .environmentObject(SurroundService.previewInstance())
        .environment(\.surroundAllowsLocalPersistence, false)
}
#endif
