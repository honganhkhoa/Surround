//
//  ActivityBarHosts.swift
//  Surround
//
//  The Activity bar's SwiftUI hosts on iPhones before the iOS 27 container
//  and on iPadOS 18: the custom bar, which each screen of a tab's stack draws
//  in a bottom inset that is always there, and SwiftUI's bottom accessory on
//  MainView's TabView from iOS 26.1. Both decide in body from the window's
//  bar state, the host policy, the registry's settled place, the docked
//  keyboard's notifications and on iPad the sidebar's observable copy
//  (`ActivityBarHostState.shownBar`), never from geometry, and
//  each draws exactly the value its decision came from. Neither presents
//  anything: the bar's taps go through NavigationService, and Activity opens
//  from MainView's presenters.
//

import Combine
import SwiftUI

// MARK: - What the hosts draw

enum ActivityBarHosting {
    /// Whether the bar carries the window's connection status, as far as its
    /// host does (`ActivityHostPolicy.ConnectionStatus`): all of it in the
    /// custom bar before iOS 26 and in the iPad's floating bar, "Can’t reach
    /// OGS" with Retry on iPhones and the Duo from iOS 26, beside the line
    /// under root titles. The Now section's first row says it too.
    static let carriesConnectionStatus = true

    /// What the bar shows where the policy puts the window's status at
    /// `placement`; nil for no bar.
    static func content(_ bar: ActivityBarState,
                        placement: ActivityHostPolicy.ConnectionStatus) -> ActivityBarContent? {
        ActivityBarContent(bar.activity, words: carriesConnectionStatus ? bar.connection.words : nil,
                           placement: placement)
    }

    /// The window's connection is down or not yet up, so Withdraw and a
    /// failed result's Retry dim. View and Open game still work.
    static func isOffline(_ bar: ActivityBarState) -> Bool {
        switch bar.connection.words {
        case .connecting?, .reconnecting?, .unreachable?: true
        case .connected?, nil: false
        }
    }

    /// The policy's Debug overrides, the force and minimize flags
    /// (TESTING.md); none in Release.
    /// - Parameter afterLaunch: The window has first appeared, for the
    ///   minimize flag's after-launch value.
    static func overrides(afterLaunch: Bool) -> ActivityHostPolicy.Overrides {
        #if DEBUG && MAIN_APP
        return ActivityHostPolicy.Overrides(SurroundUITestContract.noticesHostProbe, afterLaunch: afterLaunch)
        #else
        return ActivityHostPolicy.Overrides()
        #endif
    }
}

// MARK: - The docked keyboard

/// Whether a docked software keyboard shows, from the keyboard's
/// notifications (`isAttachedSoftwareKeyboardVisible(from:)`): the custom bar
/// hides while one does, so it never rides on the keyboard. One for the app,
/// as an iPhone shows one window; an iPad window's custom bar reads whether
/// the keyboard covers that window (`IPadTabContext`) instead. It publishes a
/// main-queue turn after a notification, never inside a layout pass.
final class ActivityDockedKeyboard: ObservableObject {
    static let shared = ActivityDockedKeyboard()

    @Published private(set) var isShown = false
    private var subscription: AnyCancellable?

    private init() {
        let platform = SystemPlatformServices.shared
        subscription = platform.keyboardWillChangeFramePublisher
            .map { platform.isAttachedSoftwareKeyboardVisible(from: $0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shown in
                guard let self, isShown != shown else { return }
                isShown = shown
            }
    }
}

// MARK: - The custom bar

/// A screen of a tab's stack that draws the custom bar.
enum ActivityCustomBarPlace {
    /// The tab's root, which the registry hides for a conversation in
    /// Messages' side pane.
    case root
    /// A screen pushed on it that isn't a game or a conversation. It covers
    /// the root itself.
    case pushed
}

extension View {
    /// The custom bar at the screen's bottom, 16 pt from each side and 8 pt
    /// above the tab bar, on iPhones whose SwiftUI TabView hosts it: iOS 18
    /// to 26.0, and later releases built without the iOS 26.2 SDK; on iPad
    /// wherever the policy gives its floating bar to the custom bar, as on
    /// iPadOS 18, centred and at most 400 pt wide; and in Debug wherever the
    /// force flag puts it, the iOS 27 container included. Only in a tab's
    /// stack (`owningTabRoot`), so sheets, popovers, compatibility scenes and
    /// previews draw none. Nil draws none: Game Detail's routes and
    /// conversations.
    func activityCustomBar(_ place: ActivityCustomBarPlace?) -> some View {
        modifier(ActivityCustomBarHost(place: place))
    }
}

private struct ActivityCustomBarHost: ViewModifier {
    let place: ActivityCustomBarPlace?
    @Environment(\.owningTabRoot) private var owningTabRoot
    @Environment(\.iPadTabContext) private var iPadTabContext
    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
    @Environment(\.duoTabContext) private var duoTabContext
    #endif
    @EnvironmentObject private var nav: NavigationService

    /// The container this screen's tab is in.
    private var container: ActivityHostPolicy.Container {
        if iPadTabContext != nil { return .iPadTabContainer }
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        if duoTabContext != nil { return .duoTabContainer }
        #endif
        return .swiftUITabView
    }

    /// Whether this window's container hosts the custom bar: what the policy
    /// says for its OS and SDK, and the force flag, which alone gives it to
    /// the iOS 27 container. On iPad, what it gives the floating bar while
    /// the sidebar is hidden, whatever the sidebar does now. The same for
    /// the window's life, as the screen's environment is, so each screen
    /// keeps one identity, with the inset always there inside a hosting
    /// window.
    private var windowHostsCustomBar: Bool {
        let overrides = ActivityBarHosting.overrides(afterLaunch: true)
        if container == .iPadTabContainer {
            let facts = ActivityHostPolicy.Facts.current(.iPadTabContainer, sidebar: .hidden)
            return facts.platform == .iPad && ActivityHostPolicy.hosts(for: facts, overrides: overrides).bar == .customBar
        }
        let facts = ActivityHostPolicy.Facts.current(container)
        return facts.platform == .iPhone && ActivityHostPolicy.hosts(for: facts, overrides: overrides).bar == .customBar
    }

    func body(content: Content) -> some View {
        if let place, let root = owningTabRoot, windowHostsCustomBar {
            content.modifier(ActivityCustomBarInset(place: place, root: root, container: container,
                                                    iPadTabs: iPadTabContext, bar: nav.activityBar,
                                                    places: nav.activityPlaces, keyboard: .shared))
        } else {
            content
        }
    }
}

/// The inset at a screen's bottom, always present, with the bar inside only
/// while it shows: there is content, no docked keyboard covers the window,
/// on a root the registry doesn't hide it and, on iPad, the sidebar copy says
/// hidden or unavailable. A pushed game or conversation draws none of its
/// own, so the registry's turn never adds an inset under one.
private struct ActivityCustomBarInset: ViewModifier {
    let place: ActivityCustomBarPlace
    let root: RootView
    let container: ActivityHostPolicy.Container
    /// The iPad's context, whose sidebar copy the policy reads: shown as the
    /// sidebar starts to show, hidden once its hide completes, each a turn
    /// later. Never the delivered metrics, which follow layout. It also says
    /// whether a docked keyboard covers this window.
    let iPadTabs: IPadTabContext?
    @ObservedObject var bar: ActivityBarState
    @ObservedObject var places: ActivityPlaceRegistry
    @ObservedObject var keyboard: ActivityDockedKeyboard
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let facts = ActivityHostPolicy.Facts.current(container, sidebar: iPadTabs?.activitySidebar ?? .unavailable)
        let overrides = ActivityBarHosting.overrides(afterLaunch: true)
        let barContent = ActivityBarHosting.content(
            bar, placement: ActivityHostPolicy.hosts(for: facts, overrides: overrides).connectionStatus
        )
        // A Stage Manager window can sit above a keyboard docked under
        // another, and keeps its bar then.
        let keyboardOverWindow = iPadTabs?.activityKeyboardOverWindow ?? keyboard.isShown
        let state = ActivityBarHostState(facts: facts, overrides: overrides,
                                         placeHidesBar: place == .root && places.hidesActivity(in: root),
                                         hasContent: barContent != nil, isKeyboardOverWindow: keyboardOverWindow)
        let shown = state.shownBar == .customBar ? barContent : nil
        // The form comes from the vertical size class: one 48 pt line in
        // compact height, else two lines in 56 pt.
        let traits = ActivityBarTraits(bar: .customBar, container: container,
                                       isCompactWidth: horizontalSizeClass != .regular,
                                       isCompactHeight: verticalSizeClass == .compact)
        let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZStack {
                    if let shown {
                        ActivityBarView(content: shown, traits: traits, isOffline: ActivityBarHosting.isOffline(bar))
                            // On iPad a narrow capsule, centred.
                            .frame(maxWidth: container == .iPadTabContainer ? Self.iPadMaximumWidth : nil)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            #if DEBUG && MAIN_APP
                            .background {
                                ActivityBarStateElement(text: ActivityBarAppliedState.text(
                                    shown, host: .customBar, form: ActivityBarForm(traits)))
                            }
                            #endif
                            .transition(transition)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: shown != nil)
            }
            #if DEBUG && MAIN_APP
            // Only logs: when this screen's bar comes and goes, and why.
            .onChange(of: shown != nil, initial: true) { _, isShown in
                NoticesHostProbeLog.event("bar.custom", [
                    ("root", root.rawValue), ("place", place == .root ? "root" : "pushed"),
                    ("shown", NoticesHostProbeLog.flag(isShown)), ("sidebar", facts.sidebar.rawValue),
                    ("keyboard", NoticesHostProbeLog.flag(keyboardOverWindow)),
                ])
            }
            #endif
    }

    /// The iPad's custom bar is at most this wide.
    static let iPadMaximumWidth: CGFloat = 400
}

// MARK: - SwiftUI's accessory

/// MainView's TabView on iPhones: SwiftUI's bottom accessory from iOS 26.1,
/// and the tab bar's minimize behavior, `.never` on iOS 26. Both are always
/// attached, so the TabView keeps one identity; only their arguments
/// change. The accessory is enabled while the policy says so, the registry
/// doesn't hide the selected tab and the window's bar state has content. A
/// docked keyboard already hides it with the tab bar, so the keyboard isn't
/// an input. Elsewhere (iOS 18 and 26.0, which the custom bar serves) the
/// accessory is never enabled.
struct ActivityBottomAccessoryHost: ViewModifier {
    @ObservedObject var bar: ActivityBarState
    @ObservedObject var places: ActivityPlaceRegistry
    /// The selected tab, read directly (`nav.main.rootView`). The registry is
    /// settled per tab, so a newly selected tab whose top screen is a game
    /// clears the bar in the same pass; a copy settled a turn later would
    /// leave it up for a frame.
    let root: RootView
    /// What the accessory last drew, so the bar keeps it while SwiftUI takes
    /// the accessory away. Held by reference, so keeping it redraws nothing.
    @State private var lastDrawn = ActivityBarLastDrawn()
    #if DEBUG && MAIN_APP
    /// The window has first appeared, for the minimize flag's after-launch
    /// value.
    @State private var afterLaunch = false
    #endif

    init(bar: ActivityBarState, places: ActivityPlaceRegistry, root: RootView) {
        _bar = ObservedObject(wrappedValue: bar)
        _places = ObservedObject(wrappedValue: places)
        self.root = root
    }

    func body(content: Content) -> some View {
        #if DEBUG && MAIN_APP
        let overrides = ActivityBarHosting.overrides(afterLaunch: afterLaunch)
        #else
        let overrides = ActivityBarHosting.overrides(afterLaunch: true)
        #endif
        let facts = ActivityHostPolicy.Facts.current(.swiftUITabView)
        let hosts = ActivityHostPolicy.hosts(for: facts, overrides: overrides)
        let barContent = ActivityBarHosting.content(bar, placement: hosts.connectionStatus)
        let state = ActivityBarHostState(facts: facts, overrides: overrides,
                                         placeHidesBar: places.hidesActivity(in: root), hasContent: barContent != nil)
        let drawn = lastDrawn.keep(barContent)
        content
            .activityBottomAccessory(isEnabled: state.shownBar == .swiftUIAccessory) {
                ActivityAccessoryBar(content: drawn, isOffline: ActivityBarHosting.isOffline(bar))
            }
            .activityTabBarMinimizeBehavior(hosts.minimize)
            #if DEBUG && MAIN_APP
            .onAppear { DispatchQueue.main.async { afterLaunch = true } }
            #endif
    }
}

/// The content a host last drew.
final class ActivityBarLastDrawn {
    private(set) var content: ActivityBarContent?

    /// What to draw: `content`, or while there is none, what was drawn last.
    func keep(_ content: ActivityBarContent?) -> ActivityBarContent? {
        if let content { self.content = content }
        return self.content
    }
}

/// SwiftUI's accessory's content: the bar in the form SwiftUI's placement
/// gives, inline beside a minimized tab bar and expanded otherwise. It holds
/// no state, since SwiftUI tears it down on almost every transition, and
/// presents nothing.
private struct ActivityAccessoryBar: View {
    let content: ActivityBarContent?
    let isOffline: Bool

    var body: some View {
        ActivityAccessoryPlacementReading { placement in
            if let content {
                let traits = ActivityBarTraits(bar: .swiftUIAccessory, container: .swiftUITabView,
                                               placement: placement)
                ActivityBarView(content: content, traits: traits, isOffline: isOffline)
                    #if DEBUG && MAIN_APP
                    .background {
                        ActivityBarStateElement(text: ActivityBarAppliedState.text(
                            content, host: .swiftUIAccessory, form: ActivityBarForm(traits)))
                    }
                    #endif
            }
        }
    }
}
