import XCTest
import UIKit

/// Run in Open for sidebar coverage or Closed for the same pushed-profile route.
/// This starts from MainView rather than a standalone profile or game fixture.
final class DuoProfileSidebarUITests: SurroundJourneyUITestCase {
    private var expectsOpenSidebar: Bool {
        ProcessInfo.processInfo.environment["SURROUND_EXPECT_DUO_SIDEBAR"] == "1"
    }

    func testOwnProfileTabRemainsResponsiveAcrossSidebarToggles() throws {
        #if targetEnvironment(macCatalyst)
        if expectsOpenSidebar {
            XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
            return
        }
        throw XCTSkip("This regression exercises the owned iPhone sidebar.")
        #else
        guard #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone else {
            if expectsOpenSidebar {
                XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
                return
            }
            throw XCTSkip("This regression requires an iOS 27 phone.")
        }
        let app = launchHomeWithProfileContent()
        element("navigation.container.duo", in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        let toggle = sidebarToggle(in: app)
        guard toggle.waitForExistence(timeout: expectsOpenSidebar ? 10 : 2) else {
            if expectsOpenSidebar {
                XCTFail("The explicitly requested Open run must expose Home's native sidebar.")
                return
            }
            throw XCTSkip("The own Profile tab regression requires Open; pushed-profile navigation also runs in Closed.")
        }

        // Reproduce the original route exactly: Home's sidebar selects the
        // account Profile tab, rather than pushing another player's profile.
        tap(toggle, description: "Open Home's native sidebar", in: app)
        let settings = element(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        XCTAssertTrue(waitUntilHittable(settings, timeout: 10))
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationProfile, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        let profileScreen = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertSidebarCollapsed(settings)
        let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(header.staticTexts["You"].exists)
        let closedFrame = settledFrame(of: header, in: app)

        for cycle in 1...2 {
            tap(sidebarToggle(in: app), description: "Open sidebar on the own Profile tab, cycle \(cycle)", in: app)
            XCTAssertTrue(waitUntilHittable(settings, timeout: 10),
                          "Opening the sidebar on the own Profile tab must complete.")
            assertSameFrame(settledFrame(of: header, in: app), closedFrame,
                            "The sidebar must cover stationary own Profile content.")
            keepScreenshot("Own Profile tab – sidebar open \(cycle)", in: app)
            tap(sidebarToggle(in: app), description: "Close sidebar on the same own Profile tab", in: app)
            assertSidebarCollapsed(settings)
            assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
            assertSameFrame(settledFrame(of: header, in: app), closedFrame,
                            "Closing the sidebar must preserve the own Profile body's geometry.")
        }

        // Verify an actual response after the animation round trips. Merely
        // reading a still-rendered profile would not detect an unresponsive UI.
        tap(sidebarToggle(in: app), description: "Open sidebar to leave Profile", in: app)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        let leftProfile = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: profileScreen
        )
        XCTAssertEqual(XCTWaiter.wait(for: [leftProfile], timeout: 10), .completed,
                       "Selecting Home must leave the own Profile tab after repeated sidebar toggles.")
        assertSidebarCollapsed(settings)
        keepScreenshot("Home after own Profile sidebar round trips", in: app)
        #endif
    }

    func testPushedProfileRemainsResponsiveAcrossSidebarTogglesAndBack() throws {
        #if targetEnvironment(macCatalyst)
        if expectsOpenSidebar {
            XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
            return
        }
        throw XCTSkip("This regression exercises the owned iPhone tab container.")
        #else
        guard #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone else {
            if expectsOpenSidebar {
                XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
                return
            }
            throw XCTSkip("This regression requires an iOS 27 phone.")
        }

        let app = launchHomeWithProfileContent()
        element("navigation.container.duo", in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)

        let gameID = SurroundUITestContract.screenshotPrimaryGameID
        let game = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app
        )
        scrollIntoTappableArea(game, in: app)
        tap(game, description: "Open the Home fixture game through the normal shell", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let boardValue = try XCTUnwrap(board.value as? String)

        // Reenter from the same retained game. One successful initial layout
        // must not hide a regression when the pushed host is used again.
        for visit in 1...2 {
            tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
                SurroundUITestContract.profileFixtureOpponentID
            ), in: app, matching: .button)
            assertLoadedProfile(named: "CopperKoi", in: app)
            element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
            assertProfileBackIsVisible(in: app)

            let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            let closedFrame = settledFrame(of: header, in: app)
            let toggle = sidebarToggle(in: app)
            let hasSidebarToggle = toggle.waitForExistence(timeout: expectsOpenSidebar ? 10 : 2)
            if expectsOpenSidebar {
                XCTAssertTrue(hasSidebarToggle,
                              "The explicitly requested Open run must expose the sidebar on a pushed profile.")
            }

            // Closed has no sidebar; it still executes both profile pushes,
            // visible Back checks, and the returned-game state assertions.
            if hasSidebarToggle {
                XCTAssertTrue(waitUntilHittable(toggle, timeout: 10),
                              "The profile's native sidebar toggle must remain usable.")
                for cycle in 1...2 {
                    tap(sidebarToggle(in: app), description: "Open sidebar on profile, visit \(visit), cycle \(cycle)", in: app)
                    let settings = element(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
                    XCTAssertTrue(waitUntilHittable(settings, timeout: 10),
                                  "Opening the native sidebar must complete and expose its destinations.")
                    assertSameFrame(settledFrame(of: header, in: app), closedFrame,
                                    "The sidebar must cover stationary profile content.")
                    keepScreenshot("Pushed profile \(visit) – sidebar open \(cycle)", in: app)

                    // Close through native chrome without selecting a tab or
                    // replacing the pushed destination. A stuck layout loop
                    // cannot satisfy this action and its following Back check.
                    tap(sidebarToggle(in: app), description: "Close sidebar on the same profile", in: app)
                    assertSidebarCollapsed(settings)
                    assertLoadedProfile(named: "CopperKoi", in: app)
                    assertSameFrame(settledFrame(of: header, in: app), closedFrame,
                                    "Closing the sidebar must preserve the profile's body geometry.")
                    assertProfileBackIsVisible(in: app)
                }
            }

            let profileScreen = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
            guard let back = assertProfileBackIsVisible(in: app) else { return }
            tap(back, description: "Back from the pushed profile to its originating game", in: app)
            let returned = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: profileScreen
            )
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed,
                           "The visible Back control must pop the profile after sidebar round trips.")
            element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
            XCTAssertEqual(board.value as? String, boardValue,
                           "Back must return to the retained game and its exact board position.")
            XCTAssertTrue(waitUntilHittable(element(
                SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
                    SurroundUITestContract.profileFixtureOpponentID
                ), in: app, matching: .button
            ), timeout: 10), "The returned game must accept another profile entry.")
        }
        keepScreenshot("Game after repeated pushed-profile sidebar round trips", in: app)
        #endif
    }

    private func launchHomeWithProfileContent() -> XCUIApplication {
        launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
        ], orientation: .portrait)
    }

    private func sidebarToggle(in app: XCUIApplication) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "ToggleSidebar", "Toggle sidebar"
        ))
        return candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
            ?? candidates.firstMatch
    }

    @discardableResult
    private func assertProfileBackIsVisible(in app: XCUIApplication) -> XCUIElement? {
        // Duo can retain an inaccessible navigation-bar copy while the usable
        // BackButton lives in the vertical toolbar. Resolve the visible copy.
        let candidates = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Back"
        ))
        var back: XCUIElement?
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            back = candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
            return back != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed,
                      "A pushed profile must retain a visible, usable Back control.")
        guard let back else { return nil }
        XCTAssertGreaterThan(back.frame.width, 0)
        XCTAssertGreaterThan(back.frame.height, 0)
        let viewport = nativeWindowFrame(in: app)
        let intersectsWindow = viewport.map { back.frame.intersects($0) } ?? false
        if !intersectsWindow { keepWindowGeometryDiagnostic(for: back, in: app) }
        XCTAssertTrue(intersectsWindow,
                      "The visible Back control must intersect the owned native window. \(windowGeometryDescription(for: back, in: app))")
        return back
    }

    private func assertSidebarCollapsed(_ settings: XCUIElement) {
        let collapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !settings.exists || !settings.isHittable }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 10), .completed,
                       "Closing the native sidebar must complete on the retained destination.")
    }

    private func settledFrame(of element: XCUIElement, in app: XCUIApplication) -> CGRect {
        var previous: CGRect?
        var consecutive = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists else { consecutive = 0; return false }
            let frame = element.frame
            guard let viewport = self.nativeWindowFrame(in: app),
                  frame.width > 1, frame.height > 1, frame.intersects(viewport) else {
                consecutive = 0
                return false
            }
            if let previous, self.framesMatch(frame, previous, tolerance: 0.5) {
                consecutive += 1
            } else {
                consecutive = 1
            }
            previous = frame
            return consecutive >= 3
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 10)
        if result != .completed { keepWindowGeometryDiagnostic(for: element, in: app) }
        XCTAssertEqual(result, .completed,
                       "The loaded profile's observable body frame must settle inside the native window. \(windowGeometryDescription(for: element, in: app))")
        return element.frame
    }

    private func nativeWindowFrame(in app: XCUIApplication) -> CGRect? {
        // Application.frame can retain the previous Duo display/orientation.
        // Find the actual UIWindow that owns our tab container instead.
        let windows = app.windows.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > 1 && $0.frame.height > 1
        }
        let owned = windows.first { window in
            window.identifier == "navigation.container.duo"
                || window.descendants(matching: .any)
                    .matching(identifier: "navigation.container.duo").firstMatch.exists
        }
        if let owned { return owned.frame }
        // Some accessibility snapshots flatten the container's identifier.
        // A single native window is unambiguous; multiple windows require the
        // ownership match above instead of selecting an unrelated overlay.
        return windows.count == 1 ? windows[0].frame : nil
    }

    private func windowGeometryDescription(for element: XCUIElement, in app: XCUIApplication) -> String {
        let windows = app.windows.allElementsBoundByIndex.enumerated().map { index, window in
            "window[\(index)] identifier=\(window.identifier) frame=\(window.frame)"
        }.joined(separator: "; ")
        return "element=\(element.identifier) frame=\(element.frame); nativeViewport=\(String(describing: nativeWindowFrame(in: app))); applicationFrame=\(app.frame); \(windows)"
    }

    private func keepWindowGeometryDiagnostic(for element: XCUIElement, in app: XCUIApplication) {
        let diagnostic = XCTAttachment(string: windowGeometryDescription(for: element, in: app))
        diagnostic.name = "Duo profile native window geometry"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }

    private func framesMatch(_ actual: CGRect, _ expected: CGRect, tolerance: CGFloat) -> Bool {
        abs(actual.minX - expected.minX) <= tolerance
            && abs(actual.minY - expected.minY) <= tolerance
            && abs(actual.width - expected.width) <= tolerance
            && abs(actual.height - expected.height) <= tolerance
    }

    private func assertSameFrame(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, message)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, message)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, message)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1, message)
    }
}
