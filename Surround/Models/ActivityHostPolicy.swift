//
//  ActivityHostPolicy.swift
//  Surround
//
//  Which surfaces host Activity in one window, where connection status goes
//  and how the tab bar minimizes. Pure, so every combination is unit-tested.
//  MainView still picks the container.
//

import Foundation

enum ActivityHostPolicy {
    enum Platform: String, CaseIterable { case iPhone, iPad, mac }

    /// The root container MainView builds for the window.
    enum Container: String, CaseIterable {
        /// MainView.swiftUITabs: iPhone before iOS 27 or without its SDK; Mac Catalyst.
        case swiftUITabView
        /// DuoTabContainer: every iPhone on iOS 27, built with the iOS 27 SDK.
        case duoTabContainer
        /// IPadTabContainer: every iPad, from iPadOS 18.
        case iPadTabContainer
    }

    /// The running OS in the steps the hosts care about.
    enum Release: Int, Comparable, CaseIterable {
        case iOS18, iOS26_0, iOS26_1   // iOS26_1: 26.1 and later
        static func < (lhs: Release, rhs: Release) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// IPadTabContainer's sidebar, from container state, never from geometry.
    enum Sidebar: String, CaseIterable {
        case unavailable   // compact width: a bottom tab bar
        case hidden        // available and closed: the top tab bar
        case shown         // open, beside or over the content
    }

    struct Facts: Equatable {
        var platform: Platform
        var container: Container
        var release: Release
        /// Built with the iOS 26.2 SDK (SwiftUI 7.2.5) or later. Without it the
        /// hosts compile out and the window acts as on iOS 18.
        var sdkHasHostAPIs: Bool
        var sidebar: Sidebar = .unavailable
    }

    enum Bar: String { case swiftUIAccessory, uiKitAccessory, customBar }
    enum NowSection: String { case iPadSidebar, macSidebar }
    enum ConnectionStatus: String {
        case rootSubtitle         // navigationSubtitle under root titles
        case customBar            // the custom bar's line two, before iOS 26
        case nowSectionFirstRow   // with Retry, iPadOS 18 with the sidebar shown
        case windowSubtitle       // Mac
    }
    enum Minimize: String, CaseIterable { case automatic, never, onScrollDown, onScrollUp }
    /// Where SwiftUI or UIKit says an accessory sits; `notInAccessory` is UIKit's `.none`.
    enum AccessoryPlacement: String { case expanded, inline, notInAccessory, unspecified, unavailable }

    struct Hosts: Equatable {
        var bar: Bar?                    // nil: no floating bar in this state
        var nowSection: NowSection?      // shows whenever its sidebar does
        var connectionStatus: ConnectionStatus
        var minimize: Minimize?          // nil: leave the tab bar alone
    }

    /// Debug probe overrides; production passes none.
    struct Overrides: Equatable {
        var forcesCustomBar = false
        var minimize: Minimize?
    }

    /// Containers whose tab bar a device check showed minimizing in every
    /// tab. Empty until one passes, so accessory hosts keep .never.
    static let verifiedMinimizingContainers: Set<Container> = []

    static func hosts(for facts: Facts, overrides: Overrides = Overrides(),
                      verifiedMinimizing: Set<Container> = verifiedMinimizingContainers) -> Hosts {
        // Catalyst shares swiftUITabs but never gets an accessory or minimizing.
        if facts.platform == .mac {
            return Hosts(bar: nil, nowSection: .macSidebar, connectionStatus: .windowSubtitle, minimize: nil)
        }
        let release: Release = switch facts.container {
        case .duoTabContainer: .iOS26_1   // it exists only on iOS 27 with the iOS 27 SDK
        case .swiftUITabView, .iPadTabContainer: facts.sdkHasHostAPIs ? facts.release : .iOS18
        }
        let hasSubtitle = release >= .iOS26_0
        var hosts = Hosts(bar: nil, nowSection: nil,
                          connectionStatus: hasSubtitle ? .rootSubtitle : .customBar, minimize: nil)
        switch facts.container {
        case .duoTabContainer:
            hosts.bar = .uiKitAccessory
        case .iPadTabContainer:
            hosts.nowSection = .iPadSidebar
            if facts.sidebar == .shown {
                if !hasSubtitle { hosts.connectionStatus = .nowSectionFirstRow }
            } else {
                hosts.bar = hasSubtitle ? .uiKitAccessory : .customBar
            }
        case .swiftUITabView:
            hosts.bar = release >= .iOS26_1 ? .swiftUIAccessory : .customBar
        }
        if overrides.forcesCustomBar, hosts.bar != nil { hosts.bar = .customBar }
        // Only iPhone tab bars minimize; the custom bar keeps them full size.
        if facts.platform == .iPhone, release >= .iOS26_0 {
            if let forced = overrides.minimize {
                hosts.minimize = forced
            } else if hosts.bar != .customBar, verifiedMinimizing.contains(facts.container) {
                hosts.minimize = .onScrollDown
            } else {
                hosts.minimize = .never
            }
        }
        return hosts
    }
}

#if DEBUG
extension ActivityHostPolicy.Overrides {
    /// The probe flags as the policy reads them; `afterLaunch` is false until
    /// the window first appears.
    init(_ probe: SurroundUITestContract.NoticesHostProbe?, afterLaunch: Bool) {
        self.init()
        guard let probe else { return }
        forcesCustomBar = probe.forcesCustomBar
        switch probe.tabBarMinimize {
        case nil: minimize = nil
        case .automatic?: minimize = .automatic
        case .never?: minimize = .never
        case .onScrollDown?: minimize = .onScrollDown
        case .onScrollUp?: minimize = .onScrollUp
        case .onScrollDownAfterLaunch?: minimize = afterLaunch ? .onScrollDown : .never
        }
    }
}
#endif
