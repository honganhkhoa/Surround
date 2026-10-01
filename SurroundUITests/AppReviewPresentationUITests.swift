import XCTest
import UIKit

/// Exercises the production scene and owned per-tab hosting boundary with
/// offline game data and in-memory, deliberately ineligible review history.
final class AppReviewPresentationUITests: SurroundJourneyUITestCase {
    func testHostedPreferencesTrackNavigationAndPendingPresentation() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The owned tab hosting boundary is an iOS phone feature.")
        #else
        guard #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The owned tab hosting boundary requires an iOS 27 phone.")
        }
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.appReviewPresentationLaunchArgument,
        ], orientation: .portrait)
        element("navigation.container.duo", in: app)
        let status = element(SurroundUITestContract.AccessibilityID.appReviewContext, in: app)

        func assertContext(home: Bool, blocked: Bool) {
            let expected = "home=\(home);blocked=\(blocked)"
            print("APP-REVIEW-ASSERT expected=\(expected) actual=\(String(describing: status.value))")
            let settled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", expected), object: status
            )
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                           "The scene must receive the hosted presentation state: \(expected); actual: \(String(describing: status.value)).")
        }

        func assertHostedCoordinator(_ root: String) {
            let probe = element(
                SurroundUITestContract.AccessibilityID.appReviewHostedCoordinator(root), in: app
            )
            XCTAssertEqual(probe.value as? String, "present",
                           "The production review coordinator must reach the hosted \(root) root.")
        }

        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertHostedCoordinator("home")
        assertContext(home: true, blocked: false)
        tap(SurroundUITestContract.AccessibilityID.appReviewPendingToggle, in: app)
        assertContext(home: true, blocked: true)

        // An inactive retained host must not keep the selected tab blocked.
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
        assertHostedCoordinator("publicGames")
        assertContext(home: false, blocked: false)
        selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertContext(home: true, blocked: true)
        tap(SurroundUITestContract.AccessibilityID.appReviewPendingToggle, in: app)
        assertContext(home: true, blocked: false)

        let gameID = SurroundUITestContract.fixtureGameID
        let game = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app
        )
        scrollIntoTappableArea(game, in: app)
        tap(game, description: "Open the offline game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        assertHostedCoordinator("home")
        assertContext(home: false, blocked: false)
        // Regular layouts put Back in the vertical toolbar. A hidden
        // navigation-bar copy may remain in the accessibility hierarchy.
        let backs = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            "BackButton", "Active games", "Back"
        ))
        var back: XCUIElement?
        let visibleBack = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            back = backs.allElementsBoundByIndex.first(where: { $0.isHittable })
            return back != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleBack], timeout: 10), .completed,
                       "Expected the game toolbar's visible Back control.")
        if let back { tap(back, description: "Return to Home", in: app) }
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertContext(home: true, blocked: false)
        #endif
    }
}
