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

private struct MainTabPlacement: ViewModifier {
    let horizontalSizeClass: UserInterfaceSizeClass?

    func body(content: Content) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        if #available(iOS 27.0, *) {
            content.defaultTabBarPlacement(
                UIDevice.current.userInterfaceIdiom == .phone
                    && horizontalSizeClass == .regular
                    ? .sidebar : .automatic
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct MainView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.self) private var environment
    @EnvironmentObject private var sgs: SurroundService
    @EnvironmentObject var ogs: OGSService

    let allowsRemoteActivity: Bool
    
    @State var backgroundTask: PlatformBackgroundTask?
    @State var widgetInfos = [WidgetInfo]()
    @State var firstLaunch = true

    @EnvironmentObject var nav: NavigationService

    init(allowsRemoteActivity: Bool = true) {
        self.allowsRemoteActivity = allowsRemoteActivity
    }

    private var messagesBadgeCount: Int { ogs.friendInvitations.count + ogs.privateMessagesUnreadCount }

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

    private func redirectSignedOutAccountDestination() {
        guard !ogs.isLoggedIn else { return }
        if nav.main.rootView == .profile || nav.main.rootView == .privateMessages {
            nav.main.rootView = .home
        }
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
    
    private func hostedTabContent(_ root: RootView) -> AnyView {
        AnyView(root.navigationView
            .id(root == .privateMessages || root == .profile ? ogs.user?.id : nil)
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
            .environment(\.openURL, environment.openURL)
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.surroundAllowsLocalPersistence, environment.surroundAllowsLocalPersistence)
            .environment(\.surroundAllowsRemoteActivity, allowsRemoteActivity)
            .modifier(AppReviewHostedPresentation(root: root))
            .environment(\.appReviewCoordinator, environment.appReviewCoordinator)
            .environment(\.appReviewPresentationRelay, environment.appReviewPresentationRelay))
    }

    @ViewBuilder
    private var tabNavigation: some View {
        let navigationCurrentView = Binding<RootView>(
            get: { nav.main.rootView },
            set: { nav.main.rootView = $0 }
        )
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if NavigationService.usesIPadAccountSheets {
            IPadTabContainer(
                selection: navigationCurrentView,
                isLoggedIn: ogs.isLoggedIn,
                messagesBadgeCount: messagesBadgeCount,
                onAccountSheet: { nav.main.accountSheet = $0 },
                content: hostedTabContent
            )
            .ignoresSafeArea()
        } else {
            #if canImport(SwiftUI, _version: 8.0)
            if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone {
                DuoTabContainer(
                    selection: navigationCurrentView,
                    isLoggedIn: ogs.isLoggedIn,
                    messagesBadgeCount: messagesBadgeCount,
                    content: hostedTabContent
                )
                // UIKit owns the window and keyboard avoidance.
                .ignoresSafeArea()
            } else {
                swiftUITabs(selection: navigationCurrentView)
            }
            #else
            swiftUITabs(selection: navigationCurrentView)
            #endif
        }
        #else
        swiftUITabs(selection: navigationCurrentView)
        #endif
    }

    private func swiftUITabs(selection: Binding<RootView>) -> some View {
        TabView(selection: selection) {
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
            if ogs.isLoggedIn {
                Tab(value: RootView.privateMessages) {
                    RootView.privateMessages.navigationView.id(ogs.user?.id)
                } label: {
                    RootView.privateMessages.label
                }
                .badge(messagesBadgeCount)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.navigationMessages
                )
            }
            Tab(value: RootView.profile) {
                RootView.profile.navigationView
            } label: {
                RootView.profile.label
            }
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationProfile)
            .tabPlacement(.sidebarOnly)
            .hidden(
                nav.main.rootView != .profile
                    && (!ogs.isLoggedIn || horizontalSizeClass == .compact)
            )
            // Compact iPhone tab bars ignore sidebar-only placement.
            // Retain the selected secondary tab and its stack through a
            // fold; hide it only after another destination is selected.
            TabSection("Surround") {
                Tab(value: RootView.settings) {
                    RootView.settings.navigationView
                } label: {
                    RootView.settings.label
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationSettings)
                .tabPlacement(.sidebarOnly)
                .hidden(
                    horizontalSizeClass == .compact
                        && nav.main.rootView != .settings
                )
                Tab(value: RootView.about) {
                    RootView.about.navigationView
                } label: {
                    RootView.about.label
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.navigationAbout)
                .tabPlacement(.sidebarOnly)
                .hidden(
                    horizontalSizeClass == .compact
                        && nav.main.rootView != .about
                )
            }
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
        .modifier(MainTabPlacement(horizontalSizeClass: horizontalSizeClass))
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
        return ZStack(alignment: .top) {
            tabNavigation
            .sheet(isPresented: $nav.main.showWaitingGames) {
                AppNavigationStack {
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
        .sheet(item: $nav.main.accountSheet) { destination in
            IPadAccountSheet(destination: destination)
        }
        .onChange(of: ogs.isLoggedIn, initial: true) { _, _ in
            redirectSignedOutAccountDestination()
        }
        .onChange(of: nav.main.rootView) { _, _ in
            redirectSignedOutAccountDestination()
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
            // Every main window can handle general activation, including a
            // Home Screen return. AppRoute still validates incoming URLs.
            allowing: ["*"]
        )
        .environment(\.surroundAllowsRemoteActivity, allowsRemoteActivity)
    }
}

private struct IPadAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: AccountSheet

    private var navigation: some View {
        AppNavigationStack {
            Group {
                switch destination {
                case .profile: AccountProfileView()
                case .settings: SettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("account.sheet.done")
                }
            }
        }
    }

    var body: some View {
        if destination == .profile {
            navigation.presentationSizing(.page)
        } else {
            navigation
        }
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
