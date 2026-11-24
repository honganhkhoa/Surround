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
    /// Drafts and pending sends survive a popped game route in this window.
    /// Game Detail observes the store; the root need not redraw on each edit.
    @State private var gameChatSessions = GameChatSessionStore()
    /// This window's request in the app-wide display sleep switch.
    @State private var displaySleepWindow = UUID()
    /// Withdraws the request if this window's views go without an onDisappear.
    @StateObject private var displaySleepLifetime = ViewLifetime()
    /// Records this window's waiting items as they arrive, for Activity's
    /// order. Set once, with the window's Activity stores.
    @State private var activityFirstSeen: ActivityFirstSeenObserver?
    #if targetEnvironment(macCatalyst)
    /// This window's Activity command in the Mac's View menu.
    @State private var activityMenuTarget = ActivityMenuTarget()
    #endif

    @EnvironmentObject var nav: NavigationService

    init(allowsRemoteActivity: Bool = true) {
        self.allowsRemoteActivity = allowsRemoteActivity
    }

    private var messagesBadgeCount: Int { ogs.friendInvitations.count + ogs.privateMessagesUnreadCount }

    private var handledExternalEventRoots: Set<String> {
        Set(RootView.allCases.map(\.rawValue))
    }

    private var keepsDisplayAwake: Bool {
        nav.keepsDisplayAwake(isActive: scenePhase == .active, liveGames: ogs.liveGames,
                              waitingLiveGames: ogs.waitingLiveGames)
    }

    private func setKeepsDisplayAwake(_ keepsAwake: Bool) {
        guard allowsRemoteActivity else { return }
        let window = displaySleepWindow
        SystemPlatformServices.shared.setPreventsDisplaySleep(keepsAwake, for: window)
        if displaySleepLifetime.release == nil {
            displaySleepLifetime.release = {
                SystemPlatformServices.shared.setPreventsDisplaySleep(false, for: window)
            }
        }
    }

    func endBackgroundTask() {
        SystemPlatformServices.shared.endBackgroundTask(backgroundTask)
        backgroundTask = nil
    }

    /// Connects the window's Activity stores and producers to its service,
    /// and its list to this presenter, once. The window's bar state comes
    /// last, so its first value, computed here before the first layout,
    /// reads the stores attached before it, and it speaks the root's first
    /// leads. Roots built without MainView never attach it, so it publishes
    /// nothing there.
    private func attachActivity() {
        guard activityFirstSeen == nil else { return }
        nav.activityResults.attach(client: .live(ogs), navigator: nav,
                                   scheduler: OGSMainQueueWebsocketScheduler.shared)
        nav.activityLastKnown.attach(ogs: ogs)
        activityFirstSeen = ActivityFirstSeenObserver(ogs: ogs)
        let nav = nav, ogs = ogs
        nav.onCloseActivity = { [weak nav] in nav?.main.activity = nil }
        nav.startedGamesRecorder.attach(ogs: ogs, navigation: nav)
        nav.lowTimeHapticWatcher.attach(
            ogs: ogs,
            post: { [weak nav] in nav?.announce($0) },
            isCovered: { [weak ogs] in ogs?.superchatCover != nil },
            gamesOnScreen: { [weak nav] in nav?.ownLiveGameIDsOnScreen ?? [] }
        )
        // The Now section says the window's status where the bar does.
        nav.activityBar.nowSectionSaysStatus = ActivityBarHosting.carriesConnectionStatus
        // VoiceOver hears a started game or a live challenge as it first
        // leads a root screen, once per app from the window in front.
        nav.activityBar.postsFirstLeads = true
        nav.activityBar.attach(ogs: ogs, nav: nav, connection: environment.connectionStatus) { [weak nav, weak ogs] in
            guard let nav, let ogs, let announcement = ActivityBarState.appAnnouncement($0, in: ogs) else { return }
            nav.announce(announcement)
        }
    }

    /// Another account's list, results, drafts and last-known rows don't
    /// carry over.
    private func resetActivity(keepingAccount accountID: Int?) {
        nav.main.activity = nil
        nav.activityResults.reset()
        nav.conversationDrafts.discardDrafts(exceptAccount: accountID)
        nav.activityLastKnown.reset()
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
    
    /// The window's environment for content that UIKit hosts outside this
    /// view's tree: the UIKit containers' tabs and their Activity bar.
    private func windowEnvironment(_ content: some View) -> some View {
        content
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
            .environmentObject(gameChatSessions)
            .environment(\.openURL, environment.openURL)
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.surroundAllowsLocalPersistence, environment.surroundAllowsLocalPersistence)
            .environment(\.surroundAllowsRemoteActivity, allowsRemoteActivity)
            // The window root's, so a game in any tab reads the same source
            // and the window's measured width class and shape.
            .environment(\.connectionStatus, environment.connectionStatus)
            .environment(\.gameControlWindowClass, environment.gameControlWindowClass)
    }

    private func hostedTabContent(_ root: RootView) -> AnyView {
        AnyView(windowEnvironment(root.navigationView
            .id(root == .privateMessages || root == .profile ? ogs.user?.id : nil))
            .modifier(AppReviewHostedPresentation(root: root))
            .environment(\.appReviewCoordinator, environment.appReviewCoordinator)
            .environment(\.appReviewPresentationRelay, environment.appReviewPresentationRelay))
    }

    /// The Activity bar in UIKit's accessory, and the Now section in the
    /// sidebar's bottom bar on iPad and the Mac, with the window's
    /// environment.
    private func hostedAccessoryContent(_ bar: AnyView) -> AnyView {
        AnyView(windowEnvironment(bar))
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
                content: hostedTabContent,
                activityPlaces: nav.activityPlaces,
                activityBar: nav.activityBar,
                accessoryContent: hostedAccessoryContent,
                closeNowSectionPopover: { nav.closeActivityPopover(openedFrom: .nowSection) }
            )
            .ignoresSafeArea()
        } else {
            #if canImport(SwiftUI, _version: 8.0)
            if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone {
                DuoTabContainer(
                    selection: navigationCurrentView,
                    isLoggedIn: ogs.isLoggedIn,
                    messagesBadgeCount: messagesBadgeCount,
                    content: hostedTabContent,
                    activityPlaces: nav.activityPlaces,
                    activityBar: nav.activityBar,
                    accessoryContent: hostedAccessoryContent
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
        // The Mac has no accessory and no minimizing, so it attaches neither.
        // Its Now section is the sidebar's bottom bar, set on the TabView's
        // own controller once the window appears and checked again after
        // each sign-in change, which changes the tabs.
        #if targetEnvironment(macCatalyst)
        .background {
            ActivityMacNowSectionHost(nav: nav, isLoggedIn: ogs.isLoggedIn, menuTarget: activityMenuTarget) { openers in
                hostedAccessoryContent(AnyView(ActivityNowSection(bar: nav.activityBar, openers: openers)))
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        #else
        .modifier(ActivityBottomAccessoryHost(bar: nav.activityBar, places: nav.activityPlaces,
                                              root: nav.main.rootView))
        #endif
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
                .modifier(ActivitySheetPresenter())
            if ogs.isLoggedIn {
                NotificationPopupHost(places: nav.activityPlaces, selectedTab: nav.main.rootView)
            }
        }
        // The popover's anchor, above everything it may be opened from.
        .overlay { ActivityPopoverPresenter() }
        .sheet(item: $nav.main.accountSheet) { destination in
            IPadAccountSheet(destination: destination)
        }
        #if DEBUG
        .modifier(ActivityDebugOpener())
        #endif
        .onAppear(perform: attachActivity)
        .onChange(of: ogs.user?.id) { _, accountID in
            resetActivity(keepingAccount: accountID)
        }
        .onChange(of: ogs.isLoggedIn, initial: true) { _, _ in
            redirectSignedOutAccountDestination()
        }
        .onChange(of: nav.main.rootView) { _, _ in
            redirectSignedOutAccountDestination()
        }
        .onReceive(ogs.$user.map { $0?.id }.removeDuplicates()) { accountID in
            // The account can change while Home is visible and no game route
            // exists to discard its old drafts or cancel pending callbacks.
            gameChatSessions.discardOtherAccounts(keeping: accountID)
        }
        // A friendship action's result shows where the user acted, and is
        // spoken once from here unless a Messages request row took
        // VoiceOver focus for it.
        .onReceive(ogs.$friendshipNotice.compactMap { $0 }) { notice in
            let ogs = ogs, nav = nav
            nav.friendshipConfirmations.receive(
                notice,
                announce: { [weak nav] in nav?.announce($0) },
                dismiss: { [weak ogs] in ogs?.dismissFriendshipNotice(id: notice.id) }
            )
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard allowsRemoteActivity else { return }
            if phase == .active {
                self.onAppActive(newLaunch: false)
            } else if phase == .background {
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
        // Each window asks for itself; the display sleeps only once no
        // window asks, so one window leaving the foreground cannot let
        // another window's live game sleep.
        .onChange(of: keepsDisplayAwake, initial: true) { _, keepsAwake in
            setKeepsDisplayAwake(keepsAwake)
        }
        .onDisappear {
            setKeepsDisplayAwake(false)
        }
        // This window's place in the app-wide announcer, which speaks and
        // plays haptics once per app, for the window the user is in.
        .modifier(AppAnnouncerWindowRegistration(window: nav.announcerWindow))
        #if targetEnvironment(macCatalyst)
        // View > Activity acts on the window in front; the moderator's
        // cover leaves it nothing to open, and signed out there is no
        // Activity.
        .focusedSceneValue(\.activityMenuTarget,
                           ogs.superchatCover == nil && ogs.isLoggedIn ? activityMenuTarget : nil)
        #endif
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
        .environmentObject(gameChatSessions)
    }
}

/// NotificationPopup, while the selected tab doesn't show a game. A game
/// says its connection status itself, and its control and the control's
/// popover carry what the popup's pills and Messages button offer.
/// Conversations keep the popup. A game in a presented stack, such as the
/// iPad Profile sheet, has no tab, so the popup stays under the sheet.
///
/// Both halves settle after the layout pass: the registry a main-queue turn
/// after the screens change, and the selected tab, which changes as soon as
/// one is picked, as this host's copy a turn after it does.
private struct NotificationPopupHost: View {
    @ObservedObject var places: ActivityPlaceRegistry
    let selectedTab: RootView
    @State private var settledTab: RootView

    init(places: ActivityPlaceRegistry, selectedTab: RootView) {
        self.places = places
        self.selectedTab = selectedTab
        _settledTab = State(initialValue: selectedTab)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Always here, so the host follows the selected tab while the
            // popup is unmounted.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            if places.place(in: settledTab).gameID == nil {
                NotificationPopup()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            DispatchQueue.main.async { settledTab = tab }
        }
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
                case .settings:
                    SettingsView()
                        .backgroundStyle(Color(uiColor: .secondarySystemBackground))
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
                .presentationBackground(Color(uiColor: .systemBackground))
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
