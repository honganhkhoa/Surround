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
        case iOS18
        case iOS26_0
        /// 26.1 up to 27.
        case iOS26_1
        case iOS27_0
        case iOS27_1
        /// 27.2 and later.
        case iOS27_2

        static func < (lhs: Release, rhs: Release) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The release a version of iOS or iPadOS runs. Below 26 is iOS 18's
        /// row; 26.1 and its updates are one step, and so is 27.2 with every
        /// later release.
        init(_ version: OperatingSystemVersion) {
            switch (version.majorVersion, version.minorVersion) {
            case (..<26, _): self = .iOS18
            case (26, 0): self = .iOS26_0
            case (26, _): self = .iOS26_1
            case (27, 0): self = .iOS27_0
            case (27, 1): self = .iOS27_1
            default: self = .iOS27_2
            }
        }
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
    /// Where a window says its connection status.
    enum ConnectionStatus: String {
        /// iPhones and the Duo from iOS 26: the line under root titles, with
        /// "Can’t reach OGS" and Retry in the bar.
        case rootSubtitle
        /// The floating bar says all of it: the custom bar before iOS 26, and
        /// the iPad's floating bar, custom or the system's, on every iPadOS.
        case floatingBar
        /// The Now section's first row, with Retry: the iPad while its
        /// sidebar shows, on every iPadOS, and the Mac.
        case nowSectionFirstRow
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

    /// Debug overrides; production passes none.
    struct Overrides: Equatable {
        var forcesCustomBar = false
        var minimize: Minimize?
    }

    /// Containers whose tab bar a scrolled run showed minimizing in every
    /// tab, each from the earliest release a run verified. A container that
    /// isn't here, or a release before its floor, keeps .never; so does a
    /// whole container once one of its tabs fails.
    static let verifiedMinimizingContainers: [Container: Release] = [.duoTabContainer: .iOS27_0]

    /// The iPad's floating bar while its sidebar is hidden or the window is
    /// compact, one entry per release: the custom bar on iPadOS 18, and the
    /// system's from 26, which the coordinator clears as soon as a game is
    /// asked for, so the game's board never lays out beside it.
    static func iPadFloatingBar(on release: Release) -> Bar {
        switch release {
        case .iOS18: .customBar
        case .iOS26_0: .uiKitAccessory
        case .iOS26_1: .uiKitAccessory
        // A turn on 27.0 can leave the sidebar's toggle blank while the
        // system's bar and the Now section show together; .customBar here
        // gives 27.0 and 27.1 the custom bar instead.
        case .iOS27_0, .iOS27_1: .uiKitAccessory
        case .iOS27_2: .uiKitAccessory
        }
    }

    static func hosts(for facts: Facts, overrides: Overrides = Overrides(),
                      verifiedMinimizing: [Container: Release] = verifiedMinimizingContainers) -> Hosts {
        // Catalyst shares swiftUITabs but never gets an accessory or minimizing.
        if facts.platform == .mac {
            return Hosts(bar: nil, nowSection: .macSidebar, connectionStatus: .nowSectionFirstRow, minimize: nil)
        }
        let release: Release = switch facts.container {
        // It exists only on iOS 27 with the iOS 27 SDK, so nothing earlier
        // can be the OS's.
        case .duoTabContainer: max(facts.release, .iOS27_0)
        case .swiftUITabView, .iPadTabContainer: facts.sdkHasHostAPIs ? facts.release : .iOS18
        }
        var hosts = Hosts(bar: nil, nowSection: nil, connectionStatus: .floatingBar, minimize: nil)
        switch facts.container {
        case .duoTabContainer:
            hosts.bar = .uiKitAccessory
            hosts.connectionStatus = .rootSubtitle
        case .iPadTabContainer:
            // iPad status stays where iPadOS 18 has it on every release: no
            // line under the titles of its top tab bar.
            hosts.nowSection = .iPadSidebar
            if facts.sidebar == .shown {
                hosts.connectionStatus = .nowSectionFirstRow
            } else {
                hosts.bar = iPadFloatingBar(on: release)
            }
        case .swiftUITabView:
            hosts.bar = release >= .iOS26_1 ? .swiftUIAccessory : .customBar
            if release >= .iOS26_0 { hosts.connectionStatus = .rootSubtitle }
        }
        if overrides.forcesCustomBar, hosts.bar != nil { hosts.bar = .customBar }
        // Only iPhone tab bars minimize; the custom bar keeps them full size.
        if facts.platform == .iPhone, release >= .iOS26_0 {
            if let forced = overrides.minimize {
                hosts.minimize = forced
            } else if hosts.bar != .customBar, let floor = verifiedMinimizing[facts.container], release >= floor {
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
