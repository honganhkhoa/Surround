import XCTest
import UIKit

/// Exercises the UIKit tab/sidebar shell, rather than a standalone Zen fixture.
/// Set Duo to the named pose in Device Hub before its case; XCTest rotation can
/// report success without rotating that display. The SURROUND_EXPECT_* flags
/// make an explicitly requested destination fail instead of skipping a mismatch.
final class GameDetailZenChromeUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    func testRegularIPhoneLandscapeZenReclaimsNavigationBand() throws {
        let expected = ProcessInfo.processInfo.environment["SURROUND_EXPECT_REGULAR_PHONE_ZEN"] == "1"
        guard try requireSupportedPhone(expected: expected) else { return }
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = launchHome(orientation: .landscapeLeft)
        guard try requireSidebar(in: app, expected: expected) else { return }
        openFixtureGame(in: app)
        let diagnostic = layoutDiagnostic(in: app)
        let window = try XCTUnwrap(nativeWindowFrame(in: app))
        guard try require(
            window.width > window.height
                && !diagnostic.contains(";division("),
            expected: expected,
            message: "Configure an ordinary iPhone with regular width in landscape, such as iPhone Max."
        ) else { return }
        try assertZenRoundTrip(in: app)
    }

    func testDuoOpenTallZenReclaimsNavigationBand() throws {
        let expected = ProcessInfo.processInfo.environment["SURROUND_EXPECT_DUO_OPEN_TALL_ZEN"] == "1"
        guard try requireSupportedPhone(expected: expected) else { return }
        // Guest orientation setters do not reliably rotate Duo's active
        // display. Keep the operator-selected Open tall pose unchanged.
        let app = launchHome(orientation: .unknown)
        guard try requireSidebar(in: app, expected: expected) else { return }
        openFixtureGame(in: app)
        let diagnostic = layoutDiagnostic(in: app)
        let window = try XCTUnwrap(nativeWindowFrame(in: app))
        let windows = app.windows.allElementsBoundByIndex.enumerated().map {
            "window[\($0.offset)] id=\($0.element.identifier) frame=\($0.element.frame)"
        }.joined(separator: ";")
        let prerequisite = "ownedWindow=\(window);sensor=\(XCUIDevice.shared.orientation.rawValue);\(windows);\(diagnostic)"
        print("[DuoOpenTallZenPrerequisite] \(prerequisite)")
        let evidence = XCTAttachment(string: prerequisite)
        evidence.name = "Duo Open tall Zen prerequisite"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard try require(
            window.height > window.width
                && !diagnostic.contains(";division(active=true"),
            expected: expected,
            message: "Configure Duo Open tall with regular width and no active fold division."
        ) else { return }
        try assertZenRoundTrip(in: app)
    }

    func testDuoBookWideZenHidesNavigationChrome() throws {
        let expected = ProcessInfo.processInfo.environment["SURROUND_EXPECT_DUO_BOOK_WIDE_ZEN"] == "1"
        guard try requireSupportedPhone(expected: expected) else { return }
        let app = launchHome(orientation: .unknown)
        guard try requireSidebar(in: app, expected: expected) else { return }
        openFixtureGame(in: app)
        let diagnostic = layoutDiagnostic(in: app)
        let window = try XCTUnwrap(nativeWindowFrame(in: app))
        let division = diagnosticFrame(after: ";division(active=true,frame=(", in: diagnostic)
        let prerequisite = "ownedWindow=\(window);\(diagnostic)"
        print("[DuoBookWideZenPrerequisite] \(prerequisite)")
        let evidence = XCTAttachment(string: prerequisite)
        evidence.name = "Duo Book wide Zen prerequisite"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard try require(
            window.width > window.height
                && division.map { $0.height > $0.width } == true,
            expected: expected,
            message: "Configure Duo Book wide with regular width and an active vertical fold division."
        ) else { return }
        try assertZenRoundTrip(in: app, normallyHidesNavigationBar: true)
    }

    private func requireSupportedPhone(expected: Bool) throws -> Bool {
        #if targetEnvironment(macCatalyst)
        return try require(false, expected: expected, message: "This Zen regression requires an iOS 27 phone.")
        #else
        if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone { return true }
        return try require(false, expected: expected, message: "This Zen regression requires an iOS 27 phone.")
        #endif
    }

    private func require(_ condition: Bool, expected: Bool, message: String) throws -> Bool {
        guard condition else {
            if expected {
                XCTFail("The explicitly requested Zen regression cannot run. " + message)
                return false
            }
            throw XCTSkip(message)
        }
        return true
    }

    private func requireSidebar(in app: XCUIApplication, expected: Bool) throws -> Bool {
        let available = pollUntil(timeout: expected ? 10 : 2) {
            self.nativeSidebarToggle(in: app) != nil
        }
        return try require(available, expected: expected,
                           message: "The native phone sidebar must be available in regular width.")
    }

    private func launchHome(orientation: UIDeviceOrientation) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.emptyMessagesLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
            SurroundUITestContract.gameDetailDesignArtboardLaunchArgument, "1",
        ], orientation: orientation)
        element(ID.screenHome, in: app)
        return app
    }

    private func openFixtureGame(in app: XCUIApplication) {
        let game = element(ID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
                           in: app, matching: .button)
        let home = app.scrollViews[ID.screenHome].firstMatch
        for _ in 0..<4 {
            guard let window = nativeWindowFrame(in: app) else {
                XCTFail("The Home fixture must have an identifiable native window.")
                return
            }
            let top = max(window.minY + 8, app.navigationBars.firstMatch.frame.maxY + 8)
            let target = game.frame
            if game.isHittable && target.minY >= top && target.maxY <= window.maxY - 42 { break }
            let upper = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
            let lower = home.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.70))
            let moveDown = target.minY < top
            (moveDown ? upper : lower).press(forDuration: 0.05,
                thenDragTo: moveDown ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        tap(game, description: "Open the fixture through Home's native navigation", in: app)
        element(ID.gameBoard, in: app)
    }

    private func assertZenRoundTrip(in app: XCUIApplication,
                                    normallyHidesNavigationBar: Bool = false) throws {
        let board = element(ID.gameBoard, in: app)
        let boardValue = try XCTUnwrap(board.value as? String)
        let before = try settledContentFrame(in: app)
        let navigationFrame: CGRect?
        if normallyHidesNavigationBar {
            XCTAssertTrue(visibleNavigationBars(in: app).isEmpty,
                          "Book wide already hides the normal game's navigation bar.")
            XCTAssertTrue(waitUntilHittable(element(ID.gameSidebarToggle, in: app, matching: .button), timeout: 10),
                          "Book wide exposes its own sidebar control outside Zen.")
            navigationFrame = nil
        } else {
            navigationFrame = try XCTUnwrap(visibleNavigationBars(in: app).first,
                                            "The normal game must reserve a native navigation band before entering Zen.").frame
        }
        XCTAssertGreaterThanOrEqual(before.width, 600, "This regression requires the regular phone game layout.")
        XCTAssertNotNil(nativeSidebarToggle(in: app), "The normal game exposes its native sidebar.")

        activateZenControl(ID.gameZenEnter, in: app)
        assertZenChrome(in: app)
        let zenFrame = try settledContentFrame(in: app)
        print("[ZenNavigationBand] before=\(before);navigationBar=\(String(describing: navigationFrame));zen=\(zenFrame);window=\(String(describing: nativeWindowFrame(in: app)))")
        // Hiding just the Sidebar item would leave the empty navigation band.
        if let navigationFrame {
            XCTAssertLessThanOrEqual(zenFrame.minY, navigationFrame.minY + 2,
                                     "Zen's game scene uses the former navigation band's top edge.")
            XCTAssertGreaterThanOrEqual(zenFrame.height, before.height + navigationFrame.height - 2,
                                        "Zen returns the navigation band's height to the game layout.")
        } else {
            let window = try XCTUnwrap(nativeWindowFrame(in: app))
            XCTAssertLessThanOrEqual(zenFrame.minY, window.minY + 2,
                                     "Book wide Zen reclaims the top of its native window.")
            XCTAssertGreaterThanOrEqual(zenFrame.height, before.height - 2,
                                        "Removing Book wide's tray keeps the game content's available height.")
        }
        XCTAssertEqual(board.value as? String, boardValue)
        keepScreenshot(normallyHidesNavigationBar ? "Duo Book wide Zen hides navigation chrome"
                                                 : "Regular phone Zen uses the navigation band", in: app)

        tap(ID.gameZenExit, in: app, matching: .button)
        XCTAssertTrue(pollUntil(timeout: 10) {
            let navigationRestored = normallyHidesNavigationBar
                ? self.visibleNavigationBars(in: app).isEmpty && app.buttons[ID.gameSidebarToggle].exists
                : !self.visibleNavigationBars(in: app).isEmpty
            return self.nativeSidebarToggle(in: app) != nil
                && navigationRestored
                && app.buttons[ID.gameZenEnter].exists
        }, "Exit restores the normal game controls and native navigation sidebar.")
        XCTAssertFalse(app.buttons[ID.gameZenExit].exists)
        XCTAssertEqual(board.value as? String, boardValue)

        let sidebar = try XCTUnwrap(nativeSidebarToggle(in: app))
        tap(sidebar, description: "Open the restored sidebar after exiting Zen", in: app)
        let settings = element(ID.navigationSettings, in: app)
        XCTAssertTrue(waitUntilHittable(settings, timeout: 10), "The restored sidebar responds to input.")
        let closeSidebar = try XCTUnwrap(nativeSidebarToggle(in: app))
        tap(closeSidebar, description: "Close the restored sidebar", in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !settings.isHittable })
        XCTAssertEqual(board.value as? String, boardValue)
    }

    private func assertZenChrome(in app: XCUIApplication) {
        let exit = element(ID.gameZenExit, in: app, matching: .button)
        XCTAssertTrue(waitUntilHittable(exit, timeout: 10),
                      "Exit Zen remains reachable from the game content.")
        XCTAssertTrue(pollUntil(timeout: 10) {
            self.nativeSidebarToggle(in: app) == nil && self.visibleNavigationBars(in: app).isEmpty
        }, "Zen hides the native Sidebar control and navigation bar.")
        XCTAssertFalse(exit.frame.intersects(element(ID.gameBoard, in: app).frame),
                       "Exit Zen stays clear of the board.")
        for identifier in ["game.clock.black", "game.clock.white"] {
            XCTAssertFalse(exit.frame.intersects(element(identifier, in: app).frame),
                           "Exit Zen stays clear of both clocks.")
        }
    }

    private func visibleNavigationBars(in app: XCUIApplication) -> [XCUIElement] {
        guard let window = nativeWindowFrame(in: app) else { return [] }
        return app.navigationBars.allElementsBoundByIndex.filter {
            $0.exists && !$0.frame.isEmpty && $0.frame.intersects(window) && $0.isHittable
        }
    }

    private func nativeWindowFrame(in app: XCUIApplication) -> CGRect? {
        let windows = app.windows.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.width > 1 && $0.frame.height > 1
        }
        let owned = windows.first {
            $0.identifier == "navigation.container.duo"
                || $0.descendants(matching: .any)
                    .matching(identifier: "navigation.container.duo").firstMatch.exists
        }
        if let owned { return owned.frame }
        return windows.count == 1 ? windows[0].frame : nil
    }

    private func layoutDiagnostic(in app: XCUIApplication) -> String {
        element("game.layout.geometry", in: app).value as? String ?? ""
    }

    private func contentFrame(from diagnostic: String) -> CGRect? {
        diagnosticFrame(after: ";global=(", in: diagnostic)
    }

    private func diagnosticFrame(after prefix: String, in diagnostic: String) -> CGRect? {
        guard let start = diagnostic.range(of: prefix)?.upperBound,
              let end = diagnostic[start...].firstIndex(of: ")") else { return nil }
        let values = diagnostic[start..<end].split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func settledContentFrame(in app: XCUIApplication) throws -> CGRect {
        let geometry = element("game.layout.geometry", in: app)
        var lastFrame: CGRect?
        var stableSince = Date()
        XCTAssertTrue(pollUntil(timeout: 10) {
            guard let diagnostic = geometry.value as? String,
                  let frame = self.contentFrame(from: diagnostic), !frame.isEmpty else { return false }
            if frame == lastFrame { return Date().timeIntervalSince(stableSince) >= 0.5 }
            lastFrame = frame
            stableSince = Date()
            return false
        }, "The game scene geometry must settle before comparing the navigation reservation.")
        return try XCTUnwrap(lastFrame)
    }
}
