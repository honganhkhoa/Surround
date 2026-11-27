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

    /// `verified` is the policy's own minimizing floors unless a test gives
    /// others.
    private func hosts(_ platform: Policy.Platform, _ container: Policy.Container, _ release: Policy.Release,
                       sdk: Bool = true, sidebar: Policy.Sidebar = .unavailable,
                       overrides: Policy.Overrides = .init(),
                       verified: [Policy.Container: Policy.Release] = Policy.verifiedMinimizingContainers) -> Policy.Hosts {
        Policy.hosts(for: .init(platform: platform, container: container, release: release,
                                sdkHasHostAPIs: sdk, sidebar: sidebar),
                     overrides: overrides, verifiedMinimizing: verified)
    }

    /// Every container verified from the earliest release.
    private let everyContainer = Dictionary(uniqueKeysWithValues: Policy.Container.allCases.map { ($0, Policy.Release.iOS18) })
    private let ios26 = [Policy.Release.iOS26_0, .iOS26_1]
    private let ios27 = [Policy.Release.iOS27_0, .iOS27_1, .iOS27_2]

    func testIPhoneTabViewUsesSwiftUIsAccessoryFromIOS26_1() {
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS18),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .floatingBar, minimize: nil))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_0),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .rootSubtitle, minimize: .never))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1),
                       .init(bar: .swiftUIAccessory, nowSection: nil, connectionStatus: .rootSubtitle, minimize: .never))
        for release in ios27 {
            XCTAssertEqual(hosts(.iPhone, .swiftUITabView, release),
                           .init(bar: .swiftUIAccessory, nowSection: nil, connectionStatus: .rootSubtitle,
                                 minimize: .never),
                           "iOS 27 built with the 26.2 SDK but not 27's: \(release)")
        }
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, verified: [.swiftUITabView: .iOS26_1]).minimize,
                       .onScrollDown)
    }

    func testTheIPhoneTabViewNeverMinimizesOnIOS26() {
        XCTAssertNil(Policy.verifiedMinimizingContainers[.swiftUITabView])
        for release in ios26 + ios27 {
            XCTAssertEqual(hosts(.iPhone, .swiftUITabView, release).minimize, .never, "\(release)")
        }
    }

    func testIPadFloatsTheBarOnlyWithoutAShownSidebar() {
        for sidebar in [Policy.Sidebar.hidden, .unavailable] {
            XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS18, sidebar: sidebar, verified: everyContainer),
                           .init(bar: .customBar, nowSection: .iPadSidebar, connectionStatus: .floatingBar,
                                 minimize: nil),
                           "\(sidebar)")
            for release in ios26 + ios27 {
                XCTAssertEqual(hosts(.iPad, .iPadTabContainer, release, sidebar: sidebar, verified: everyContainer),
                               .init(bar: .uiKitAccessory, nowSection: .iPadSidebar,
                                     connectionStatus: .floatingBar, minimize: nil),
                               "\(release) \(sidebar)")
            }
        }
        for release in Policy.Release.allCases {
            XCTAssertEqual(hosts(.iPad, .iPadTabContainer, release, sidebar: .shown, verified: everyContainer),
                           .init(bar: nil, nowSection: .iPadSidebar, connectionStatus: .nowSectionFirstRow,
                                 minimize: nil),
                           "The Now section's first row says the status on every iPadOS: \(release)")
        }
    }

    func testTheIPadsFloatingBarHasOneEntryPerRelease() {
        XCTAssertEqual(Policy.iPadFloatingBar(on: .iOS18), .customBar)
        for release in Policy.Release.allCases where release >= .iOS26_0 {
            XCTAssertEqual(Policy.iPadFloatingBar(on: release), .uiKitAccessory,
                           "Every release from 26 gets the system's bar: \(release)")
            XCTAssertEqual(hosts(.iPad, .iPadTabContainer, release, sidebar: .hidden).bar,
                           Policy.iPadFloatingBar(on: release), "\(release)")
        }
        XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS27_0, sdk: false, sidebar: .hidden).bar, .customBar,
                       "Without the host APIs every release takes iPadOS 18's entry.")
    }

    func testTheMacSaysItsStatusInTheNowSectionAndNeverGetsAnAccessoryOrMinimizing() {
        let mac = Policy.Hosts(bar: nil, nowSection: .macSidebar, connectionStatus: .nowSectionFirstRow, minimize: nil)
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

    func testEveryIOS27IPhoneUsesUIKitsAccessoryAndMinimizesFrom27_0() {
        XCTAssertEqual(Policy.verifiedMinimizingContainers, [.duoTabContainer: .iOS27_0])
        for release in ios27 {
            for sdk in [false, true] {
                let label = "\(release) sdk=\(sdk)"
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk),
                               .init(bar: .uiKitAccessory, nowSection: nil, connectionStatus: .rootSubtitle,
                                     minimize: .onScrollDown),
                               label)
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk, verified: [:]).minimize,
                               .never, "A container whose tab failed keeps .never in every tab: \(label)")
                XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release, sdk: sdk,
                                     verified: [.swiftUITabView: .iOS18]).minimize,
                               .never, label)
            }
        }
    }

    func testTheDuosReleaseComesFromTheOSAgainstItsFloor() {
        let floor27_2: [Policy.Container: Policy.Release] = [.duoTabContainer: .iOS27_2]
        XCTAssertEqual(hosts(.iPhone, .duoTabContainer, .iOS27_0, verified: floor27_2).minimize, .never)
        XCTAssertEqual(hosts(.iPhone, .duoTabContainer, .iOS27_1, verified: floor27_2).minimize, .never)
        XCTAssertEqual(hosts(.iPhone, .duoTabContainer, .iOS27_2, verified: floor27_2).minimize, .onScrollDown,
                       "The policy tells 27.0 and 27.1 from 27.2.")
        for release in [Policy.Release.iOS18] + ios26 {
            XCTAssertEqual(hosts(.iPhone, .duoTabContainer, release), hosts(.iPhone, .duoTabContainer, .iOS27_0),
                           "The container exists only from iOS 27, so an earlier release reads as 27.0: \(release)")
        }
    }

    func testAReleaseComesFromTheOSVersion() {
        func release(_ major: Int, _ minor: Int, _ patch: Int = 0) -> Policy.Release {
            Policy.Release(OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
        }
        XCTAssertEqual(release(18, 6), .iOS18)
        XCTAssertEqual(release(17, 5), .iOS18, "Anything before 26 takes iOS 18's row.")
        XCTAssertEqual(release(26, 0), .iOS26_0)
        XCTAssertEqual(release(26, 0, 1), .iOS26_0)
        XCTAssertEqual(release(26, 1), .iOS26_1)
        XCTAssertEqual(release(26, 5), .iOS26_1)
        XCTAssertEqual(release(27, 0), .iOS27_0)
        XCTAssertEqual(release(27, 1), .iOS27_1)
        XCTAssertEqual(release(27, 2), .iOS27_2)
        XCTAssertEqual(release(27, 2, 1), .iOS27_2)
        XCTAssertEqual(release(27, 4), .iOS27_2)
        XCTAssertEqual(release(28, 0), .iOS27_2, "Every later release takes 27.2's row.")
        XCTAssertEqual(Policy.Release.allCases, [.iOS18, .iOS26_0, .iOS26_1, .iOS27_0, .iOS27_1, .iOS27_2],
                       "The releases go from earliest to latest.")
    }

    func testAnSDKWithoutTheHostAPIsActsAsIOS18() {
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, sdk: false),
                       hosts(.iPhone, .swiftUITabView, .iOS18))
        XCTAssertEqual(hosts(.iPhone, .swiftUITabView, .iOS26_1, sdk: false),
                       .init(bar: .customBar, nowSection: nil, connectionStatus: .floatingBar, minimize: nil))
        XCTAssertEqual(hosts(.iPad, .iPadTabContainer, .iOS26_1, sdk: false, sidebar: .hidden),
                       .init(bar: .customBar, nowSection: .iPadSidebar, connectionStatus: .floatingBar, minimize: nil))
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
            for release in ios26 + ios27 {
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
                                switch result.connectionStatus {
                                case .floatingBar:
                                    // A floating bar is there to say it.
                                    XCTAssertNotNil(result.bar, label)
                                    if container == .swiftUITabView {
                                        XCTAssertEqual(result.bar, .customBar, label)
                                    }
                                case .rootSubtitle:
                                    XCTAssertNotEqual(container, .iPadTabContainer, "Never under iPad titles: \(label)")
                                    XCTAssertNotNil(result.bar, "The bar carries Retry: \(label)")
                                case .nowSectionFirstRow:
                                    XCTAssertNil(result.bar, label)
                                    XCTAssertNotNil(result.nowSection, label)
                                }
                                if container == .iPadTabContainer, platform != .mac {
                                    XCTAssertEqual(result.connectionStatus,
                                                   sidebar == .shown ? .nowSectionFirstRow : .floatingBar, label)
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
                                    XCTAssertEqual(result.connectionStatus, .nowSectionFirstRow, label)
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(combinations, 648)
    }
}

#if DEBUG
extension ActivityHostPolicyTests {
    private typealias Probe = SurroundUITestContract.NoticesHostProbe
    private typealias C = SurroundUITestContract

    func testNoticesHostProbeIsNilWithoutItsFlags() throws {
        XCTAssertNil(try Probe.parse(["Surround", "--surround-ui-testing"]))
        XCTAssertNil(try Probe.parse([]))
    }

    func testNoticesHostProbeParsesBothFlags() throws {
        let arguments = ["Surround", C.noticesTabBarMinimizeLaunchArgument, "on-scroll-down-after-launch"]
        XCTAssertEqual(try Probe.parse(arguments), Probe(forcesCustomBar: false, tabBarMinimize: .onScrollDownAfterLaunch))
        XCTAssertEqual(try Probe.parse(arguments + [C.noticesForceCustomBarLaunchArgument]),
                       Probe(forcesCustomBar: true, tabBarMinimize: .onScrollDownAfterLaunch))
        XCTAssertEqual(try Probe.parse([C.noticesForceCustomBarLaunchArgument]), Probe(forcesCustomBar: true))
    }

    func testMalformedProbeValuesThrow() {
        let flag = C.noticesTabBarMinimizeLaunchArgument
        XCTAssertThrowsError(try Probe.parse([C.noticesForceCustomBarLaunchArgument, flag])) {
            XCTAssertEqual($0 as? Probe.ParseError, .missingValue(flag: flag))
        }
        XCTAssertThrowsError(try Probe.parse([flag, "sometimes"])) {
            XCTAssertEqual($0 as? Probe.ParseError, .invalidValue(flag: flag, value: "sometimes"))
        }
        XCTAssertThrowsError(try Probe.parse([flag, C.noticesForceCustomBarLaunchArgument])) {
            XCTAssertEqual($0 as? Probe.ParseError,
                           .invalidValue(flag: flag, value: C.noticesForceCustomBarLaunchArgument))
        }
    }

    func testTheFirstFlagOccurrenceWins() throws {
        let flag = C.noticesTabBarMinimizeLaunchArgument
        XCTAssertEqual(try Probe.parse([flag, "never", flag, "automatic"])?.tabBarMinimize, .never)
    }

    func testProbeOverridesSwitchMinimizingAfterLaunch() throws {
        let probe = try XCTUnwrap(try Probe.parse([C.noticesTabBarMinimizeLaunchArgument,
                                                   "on-scroll-down-after-launch"]))
        XCTAssertEqual(Policy.Overrides(probe, afterLaunch: false), .init(forcesCustomBar: false, minimize: .never))
        XCTAssertEqual(Policy.Overrides(probe, afterLaunch: true), .init(forcesCustomBar: false, minimize: .onScrollDown))
        XCTAssertEqual(Policy.Overrides(nil, afterLaunch: true), Policy.Overrides())
        XCTAssertEqual(Policy.Overrides(nil, afterLaunch: false), Policy.Overrides())
        for (value, minimize) in [("automatic", Policy.Minimize.automatic), ("never", .never),
                                  ("on-scroll-down", .onScrollDown), ("on-scroll-up", .onScrollUp)] {
            let probe = try XCTUnwrap(try Probe.parse([C.noticesTabBarMinimizeLaunchArgument, value]))
            XCTAssertEqual(Policy.Overrides(probe, afterLaunch: false).minimize, minimize, value)
            XCTAssertEqual(Policy.Overrides(probe, afterLaunch: true).minimize, minimize, value)
        }
        let forced = try XCTUnwrap(try Probe.parse([C.noticesForceCustomBarLaunchArgument]))
        XCTAssertEqual(Policy.Overrides(forced, afterLaunch: true), .init(forcesCustomBar: true, minimize: nil))
        // The iPhone TabView on 26.1 goes from .never to .onScrollDown once the window appears.
        let facts = Policy.Facts(platform: .iPhone, container: .swiftUITabView, release: .iOS26_1,
                                 sdkHasHostAPIs: true)
        XCTAssertEqual(Policy.hosts(for: facts, overrides: .init(probe, afterLaunch: false)).minimize, .never)
        XCTAssertEqual(Policy.hosts(for: facts, overrides: .init(probe, afterLaunch: true)).minimize, .onScrollDown)
    }
}
#endif
