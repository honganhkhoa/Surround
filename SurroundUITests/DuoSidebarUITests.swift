import XCTest
import UIKit

/// Native Duo overlap checks. Start the simulator in Open pose before running.
final class DuoSidebarUITests: SurroundJourneyUITestCase {
    private var expectsOpenSidebar: Bool {
        ProcessInfo.processInfo.environment["SURROUND_EXPECT_DUO_SIDEBAR"] == "1"
    }

    func testGroupsSelectContentAndOverlayKeepsGridGeometry() throws {
        #if targetEnvironment(macCatalyst)
        if expectsOpenSidebar {
            XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
            return
        }
        throw XCTSkip("This journey exercises the iPhone Duo sidebar.")
        #else
        guard #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone else {
            if expectsOpenSidebar {
                XCTFail("An explicitly requested Duo Open run requires an iOS 27 phone.")
                return
            }
            throw XCTSkip("The owned sidebar requires an iOS 27 phone.")
        }
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.publicGames.rawValue,
        ])
        element("navigation.container.duo", in: app)
        let toggle = app.buttons["Toggle sidebar"].firstMatch
        guard toggle.waitForExistence(timeout: 10) else {
            if expectsOpenSidebar {
                XCTFail("Expected the owned sidebar toggle on an explicitly requested Duo Open run.")
                return
            }
            throw XCTSkip("Run this journey with the Duo in Open pose.")
        }
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
        let game = element(
            SurroundUITestContract.AccessibilityID.publicGame(
                SurroundUITestContract.screenshotPublicGameID
            ), in: app, matching: .button
        )
        let closedFrame = game.frame
        tap(toggle, description: "Reveal the overlay sidebar", in: app)
        let settings = element(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        let sidebarReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: settings
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sidebarReady], timeout: 10), .completed)
        let editButtons = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Edit", "Edit Sidebar", "Edit sidebar"]
        ))
        XCTAssertFalse(editButtons.allElementsBoundByIndex.contains(where: { $0.isHittable }),
                       "Sidebar destination order is owned by the app and must not offer Edit.")
        XCTAssertTrue(app.staticTexts["Surround"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["OGS"].firstMatch.exists)
        let openFrame = game.frame
        XCTAssertEqual(openFrame.minX, closedFrame.minX, accuracy: 1)
        XCTAssertEqual(openFrame.minY, closedFrame.minY, accuracy: 1)
        XCTAssertEqual(openFrame.width, closedFrame.width, accuracy: 1)
        XCTAssertEqual(openFrame.height, closedFrame.height, accuracy: 1)
        keepScreenshot("Duo grouped sidebar over stationary public grid", in: app)

        tap(settings, description: "Select the grouped Settings destination", in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        let sidebarClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !settings.isHittable }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sidebarClosed], timeout: 10), .completed,
                       "Selecting a destination must close the overlay sidebar.")
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationAbout, in: app)
        element(SurroundUITestContract.AccessibilityID.screenAbout, in: app)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationBrowser, in: app)
        element(SurroundUITestContract.AccessibilityID.screenBrowser, in: app)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
        XCTAssertEqual(game.frame.width, closedFrame.width, accuracy: 1)
        #endif
    }
}
