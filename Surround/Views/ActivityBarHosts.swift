//
//  ActivityBarHosts.swift
//  Surround
//
//  The Activity bar's SwiftUI hosts on iPhones before the iOS 27 container:
//  the custom bar, which each screen of a tab's stack draws in a bottom inset
//  that is always there, and SwiftUI's bottom accessory on MainView's TabView
//  from iOS 26.1. Both decide in body from the window's bar state, the host
//  policy, the registry's settled place and the docked keyboard's
//  notifications (`ActivityBarHostState.shownBar`), never from geometry, and
//  each draws exactly the value its decision came from. Neither presents
//  anything: the bar's taps go through NavigationService, and Activity opens
//  from MainView's presenters.
//

import Combine
import SwiftUI

// MARK: - What the hosts draw

enum ActivityBarHosting {
    /// Whether the bar carries the window's connection status. It doesn't
    /// yet: NotificationPopup's banner still says it on root screens, so the
    /// bar shows Activity alone, a result or a lead, with no status kind and
    /// no outage on a game's line two.
    static let carriesConnectionStatus = false

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
/// as an iPhone shows one window. It publishes a main-queue turn after a
/// notification, never inside a layout pass.
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
    /// to 26.0, and later releases built without the iOS 26.2 SDK. Only in a
    /// tab's stack (`owningTabRoot`), so sheets, popovers, compatibility
    /// scenes and previews draw none. Nil draws none: Game Detail's routes
    /// and conversations.
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

    /// Whether this window's iPhone TabView hosts the custom bar: what the
    /// policy says for its OS and SDK, and the force flag. The same for the
    /// window's life, as the screen's environment is, so each screen keeps
    /// one identity, with the inset always there inside a hosting window.
    private var windowHostsCustomBar: Bool {
        // The iPad's floating bar and the iOS 27 container's are their
        // containers' own.
        guard iPadTabContext == nil else { return false }
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0)
        guard duoTabContext == nil else { return false }
        #endif
        let facts = ActivityHostPolicy.Facts.current(.swiftUITabView)
        return facts.platform == .iPhone
            && ActivityHostPolicy.hosts(for: facts, overrides: ActivityBarHosting.overrides(afterLaunch: true)).bar
                == .customBar
    }

    func body(content: Content) -> some View {
        if let place, let root = owningTabRoot, windowHostsCustomBar {
            content.modifier(ActivityCustomBarInset(place: place, root: root, bar: nav.activityBar,
                                                    places: nav.activityPlaces, keyboard: .shared))
        } else {
            content
        }
    }
}

/// The inset at a screen's bottom, always present, with the bar inside only
/// while it shows: there is content, no docked keyboard shows and, on a
/// root, the registry doesn't hide it. A pushed game or conversation draws
/// none of its own, so the registry's turn never adds an inset under one.
private struct ActivityCustomBarInset: ViewModifier {
    let place: ActivityCustomBarPlace
    let root: RootView
    @ObservedObject var bar: ActivityBarState
    @ObservedObject var places: ActivityPlaceRegistry
    @ObservedObject var keyboard: ActivityDockedKeyboard
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let facts = ActivityHostPolicy.Facts.current(.swiftUITabView)
        let overrides = ActivityBarHosting.overrides(afterLaunch: true)
        let barContent = ActivityBarHosting.content(
            bar, placement: ActivityHostPolicy.hosts(for: facts, overrides: overrides).connectionStatus
        )
        let state = ActivityBarHostState(facts: facts, overrides: overrides,
                                         placeHidesBar: place == .root && places.hidesActivity(in: root),
                                         hasContent: barContent != nil, isKeyboardOverWindow: keyboard.isShown)
        let shown = state.shownBar == .customBar ? barContent : nil
        // The form comes from the vertical size class: one 48 pt line in
        // compact height, else two lines in 56 pt.
        let traits = ActivityBarTraits(bar: .customBar, container: .swiftUITabView,
                                       isCompactWidth: horizontalSizeClass != .regular,
                                       isCompactHeight: verticalSizeClass == .compact)
        let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZStack {
                    if let shown {
                        ActivityBarView(content: shown, traits: traits, isOffline: ActivityBarHosting.isOffline(bar))
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
    }
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
