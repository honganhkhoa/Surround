//
//  ActivityHostPolicyTests.swift
//  SurroundTests
//
//  Which surface hosts Activity's bar and Now section in each window, where
//  connection status goes and how the tab bar minimizes.
//

import XCTest

final class ActivityHostPolicyTests: XCTestCase {
    private typealias Policy = ActivityHostPolicy

    private func hosts(_ platform: Policy.Platform, _ container: Policy.Container, _ release: Policy.Release,
                       sdk: Bool = true, sidebar: Policy.Sidebar = .unavailable,
                       overrides: Policy.Overrides = .init(), verified: Set<Policy.Container> = []) -> Policy.Hosts {
        Policy.hosts(for: .init(platform: platform, container: container, release: release,
                                sdkHasHostAPIs: sdk, sidebar: sidebar),
                     overrides: overrides, verifiedMinimizing: verified)
    }

    private let everyContainer = Set(Policy.Container.allCases)

    func testIPhoneTabViewUsesSwiftUIsAccessoryFromIOS26_1() {
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS18),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .customBar, minimize: nil))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_0),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .rootSubtitle, minimize: .never))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1),
                       .init(bar: .swiftUIAccessory, nowSection: nil, connectionStatus: .rootSubtitle, minimize: .never))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, verified: [.swiftUITabView]).minimize, .onScrollDown)
    }

    func testIPadFloatsTheBarOnlyWithoutAShownSidebar() {
        for sidebar in [Policy.Sidebar.hidden, .unavailable] {
            XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS18, sidebar: sidebar, verified: everyContainer),
                           .init(bar: .customBar, nowSection: .iPadSidebar, connectionStatus: .customBar, minimize: nil),
                           "\(sidebar)")
            for release in [Policy.Release.iOS26_0, .iOS26_1] {
                XCTAssertEqual(hosts(.iPad, .iPadTabContainer, release, sidebar: sidebar, verified: everyContainer),
                               .init(bar: .uiKitAccessory, nowSection: .iPadSidebar,
                                     connectionStatus: .rootSubtitle, minimize: nil),
                               "\(release) \(sidebar)")
            }
        }
        XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS18, sidebar: .shown, verified: everyContainer),
                       .init(bar: nil, nowSection: .iPadSidebar, connectionStatus: .nowSectionFirstRow, minimize: nil))
        for release in [Policy.Release.iOS26_0, .iOS26_1] {
            XCTAssertEqual(hosts(.iPad, .iPadTabContainer, release, sidebar: .shown, verified: everyContainer),
                           .init(bar: nil, nowSection: .iPadSidebar, connectionStatus: .rootSubtitle, minimize: nil),
                           "\(release)")
        }
    }

    func testTheMacNeverGetsAnAccessoryOrMinimizing() {
        let mac = Policy.Hosts(bar: nil, nowSection: .macSidebar, connectionStatus: .windowSubtitle, minimize: nil)
        let forced = Policy.Overrides(forcesCustomBar: true, minimize: .onScrollDown)
        for container in Policy.Container.allCases {
            for release in Policy.Release.allCases {
                for sdk in [false, true] {
                    let label = "\(container) \(release) sdk=\(sdk)"
                    XCTAssertEqual(hosts(.mac, container, release, sdk: sdk, verified: everyContainer), mac, label)
                    XCTAssertEqual(hosts(.mac, container, release, sdk: sdk, overrides: forced,
                                         verified: everyContainer), mac, label)
                }
            }
        }
    }

    func testEveryIOS27IPhoneUsesUIKitsAccessory() {
        for release in Policy.Release.allCases {
            for sdk in [false, true] {
                let label = "\(release) sdk=\(sdk)"
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk),
                               .init(bar: .uiKitAccessory, nowSection: nil, connectionStatus: .rootSubtitle,
                                     minimize: .never),
                               label)
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk, verified: [.duoTabContainer]).minimize,
                               .onScrollDown, label)
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk, verified: [.swiftUITabView]).minimize,
                               .never, label)
            }
        }
    }

    func testAnSDKWithoutTheHostAPIsActsAsIOS18() {
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, sdk: false),
                       hosts(.iPhone, .swiftUITabView, .iOS18))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, sdk: false),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .customBar, minimize: nil))
        XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS26_1, sdk: false, sidebar: .hidden),
                       .init(bar: .customBar, nowSection: .iPadSidebar, connectionStatus: .customBar, minimize: nil))
        // Every row except the Duo's turns into its iOS 18 row.
        for (platform, container) in [(Policy.Platform.iPhone, Policy.Container.swiftUITabView),
                                      (.iPad, .iPadTabContainer)] {
            for release in Policy.Release.allCases {
                for sidebar in Policy.Sidebar.allCases {
                    XCTAssertEqual(hosts(platform, container, release, sdk: false, sidebar: sidebar,
                                         verified: everyContainer),
                                   hosts(platform, container, .iOS18, sidebar: sidebar, verified: everyContainer),
                                   "\(platform) \(container) \(release) \(sidebar)")
                }
            }
        }
    }

    func testForcedCustomBarReplacesOnlyAFloatingBar() {
        let forced = Policy.Overrides(forcesCustomBar: true)
        for release in Policy.Release.allCases {
            XCTAssertNil(hosts(.iPad, .iPadTabContainer, release, sidebar: .shown, overrides: forced,
                               verified: everyContainer).bar, "\(release)")
            for sidebar in [Policy.Sidebar.hidden, .unavailable] {
                let iPad = hosts(.iPad, .iPadTabContainer, release, sidebar: sidebar, overrides: forced,
                                 verified: everyContainer)
                XCTAssertEqual(iPad.bar, .customBar, "\(release) \(sidebar)")
                XCTAssertNil(iPad.minimize, "\(release) \(sidebar)")
            }
            for container in [Policy.Container.swiftUITabView, .duoTabContainer] {
                let phone = hosts(.iPhone, container, release, overrides: forced, verified: everyContainer)
                XCTAssertEqual(phone.bar, .customBar, "\(container) \(release)")
                let minimizes = container == .duoTabContainer || release >= .iOS26_0
                XCTAssertEqual(phone.minimize, minimizes ? .never : nil, "\(container) \(release)")
            }
        }
    }

    func testForcedMinimizeAppliesOnlyToIPhoneFromIOS26() {
        for minimize in Policy.Minimize.allCases {
            let forced = Policy.Overrides(minimize: minimize)
            XCTAssertNil(hosts(.iPhone, .swiftUITabView, .iOS18, overrides: forced).minimize, "\(minimize)")
            for release in Policy.Release.allCases {
                for sidebar in Policy.Sidebar.allCases {
                    XCTAssertNil(hosts(.iPad, .iPadTabContainer, release, sidebar: sidebar,
                                       overrides: forced).minimize, "\(minimize) \(release) \(sidebar)")
                }
                XCTAssertNil(hosts(.mac, .swiftUITabView, release, overrides: forced).minimize, "\(minimize) \(release)")
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, overrides: forced).minimize, minimize,
                               "\(minimize) \(release)")
            }
            for release in [Policy.Release.iOS26_0, .iOS26_1] {
                XCTAssertEqual(hosts(.iPhone, .swiftUITabView, release, overrides: forced).minimize, minimize,
                               "\(minimize) \(release)")
            }
        }
    }

    func testEveryCombinationKeepsTheHostRules() {
        var combinations = 0
        for platform in Policy.Platform.allCases {
            for container in Policy.Container.allCases {
                for release in Policy.Release.allCases {
                    for sdk in [false, true] {
                        for sidebar in Policy.Sidebar.allCases {
                            for forcesCustomBar in [false, true] {
                                combinations += 1
                                let result = hosts(platform, container, release, sdk: sdk, sidebar: sidebar,
                                                   overrides: .init(forcesCustomBar: forcesCustomBar),
                                                   verified: everyContainer)
                                let label = "\(platform) \(container) \(release) sdk=\(sdk) \(sidebar) "
                                    + "forced=\(forcesCustomBar): \(result)"
                                if result.connectionStatus == .customBar {
                                    XCTAssertEqual(result.bar, .customBar, label)
                                }
                                if result.connectionStatus == .nowSectionFirstRow {
                                    XCTAssertNil(result.bar, label)
                                    XCTAssertEqual(result.nowSection, .iPadSidebar, label)
                                }
                                if result.bar == .swiftUIAccessory {
                                    XCTAssertEqual(container, .swiftUITabView, label)
                                    XCTAssertTrue(sdk && release >= .iOS26_1, label)
                                }
                                if result.bar == .uiKitAccessory {
                                    XCTAssertNotEqual(container, .swiftUITabView, label)
                                    if container == .iPadTabContainer {
                                        XCTAssertTrue(sdk && release >= .iOS26_0, label)
                                    }
                                }
                                if result.minimize != nil {
                                    XCTAssertEqual(platform, .iPhone, label)
                                }
                                if result.bar == .customBar, result.minimize != nil {
                                    XCTAssertEqual(result.minimize, .never, label)
                                }
                                if platform == .mac {
                                    XCTAssertNil(result.bar, label)
                                    XCTAssertNil(result.minimize, label)
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(combinations, 324)
    }
}
