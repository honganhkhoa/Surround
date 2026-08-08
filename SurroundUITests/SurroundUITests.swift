//
//  SurroundUITests.swift
//  SurroundUITests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest
import UIKit

final class SurroundUITests: XCTestCase {
    private func activateZenControl(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if targetEnvironment(macCatalyst)
        element(
            identifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        app.typeKey("z", modifierFlags: [.control, .option])
        #else
        tap(
            identifier,
            in: app,
            matching: .button,
            file: file,
            line: line
        )
        #endif
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif

        let app = XCUIApplication()
        app.launchArguments = [SurroundUITestContract.launchArgument]
            + additionalLaunchArguments
        app.launch()
        #if targetEnvironment(macCatalyst)
        app.activate()
        #endif
        return app
    }

    @discardableResult
    private func element(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app
            .descendants(matching: elementType)
            .matching(identifier: identifier)
            .firstMatch
        let appeared = element.waitForExistence(timeout: 10)
        if !appeared {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – missing \(identifier)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            appeared,
            "Expected element with identifier \(identifier)",
            file: file,
            line: line
        )
        return element
    }

    private func tap(
        _ identifier: String,
        in app: XCUIApplication,
        matching elementType: XCUIElement.ElementType = .any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = element(
            identifier,
            in: app,
            matching: elementType,
            file: file,
            line: line
        )
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [hittable], timeout: 10)
        if result != .completed {
            let hierarchy = XCTAttachment(
                string: """
                Element:
                \(element.debugDescription)

                Application hierarchy:
                \(app.debugDescription)
                """
            )
            hierarchy.name = "Accessibility hierarchy – not hittable \(identifier)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(
            result,
            .completed,
            "Expected element with identifier \(identifier) to be hittable",
            file: file,
            line: line
        )
        #if targetEnvironment(macCatalyst)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func scrollIntoTappableArea(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<4 {
            #if targetEnvironment(macCatalyst)
            let overlapsTabBar = false
            #else
            let overlapsTabBar = element.frame.maxY > app.frame.maxY - 100
            #endif
            guard !element.isHittable || overlapsTabBar else {
                return
            }
            app.swipeUp()
        }
    }

    func testTopLevelNavigation() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Top-level navigation requires the regular-width iPad or Mac layout."
        )

        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])

        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationPublicGames, in: app)
        element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationMessages, in: app)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationAbout, in: app)
        element(SurroundUITestContract.AccessibilityID.screenAbout, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationBrowser, in: app)
        element(SurroundUITestContract.AccessibilityID.screenBrowser, in: app)

        tap(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    func testFixtureGameOpens() {
        let app = launchApp()
        let gameID = SurroundUITestContract.fixtureGameID

        tap(SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        element(SurroundUITestContract.AccessibilityID.gameOptions, in: app)
    }

    func testHomeHistoryRetryRecoversAndKeepsNavigationAvailable() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.homeHistoryFailsOnceLaunchArgument,
        ])

        let error = element(
            SurroundUITestContract.AccessibilityID.homeHistoryError,
            in: app
        )
        let retry = element(
            SurroundUITestContract.AccessibilityID.homeHistoryRetry,
            in: app,
            matching: .button
        )
        // XCTest can call an element hittable while its frame still overlaps
        // the tab bar. Move Retry only when it is obscured or in that zone.
        scrollIntoTappableArea(retry, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryRetry,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.homeHistoryGame(
                SurroundUITestContract.homeHistoryRetryFixtureGameID
            ),
            in: app
        )
        let errorDisappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: error
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [errorDisappeared], timeout: 10),
            .completed,
            "Expected the history error to disappear after Retry succeeds."
        )

        let viewAll = element(
            SurroundUITestContract.AccessibilityID.homeHistoryViewAll,
            in: app,
            matching: .button
        )
        scrollIntoTappableArea(viewAll, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryViewAll,
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.screenGameHistory, in: app)
        element(
            SurroundUITestContract.AccessibilityID.gameHistoryEmpty,
            in: app
        )
    }

    func testZenModeRoundTrip() {
        let app = launchApp()

        tap(
            SurroundUITestContract.AccessibilityID.homeGame(SurroundUITestContract.fixtureGameID),
            in: app
        )
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenEnter,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        activateZenControl(
            SurroundUITestContract.AccessibilityID.gameZenExit,
            in: app
        )
        element(SurroundUITestContract.AccessibilityID.gameZenEnter, in: app)
    }

    func testFinishedGameOffersRematchEditor() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameHistory.rawValue,
        ])

        tap(
            SurroundUITestContract.AccessibilityID.homeHistoryGame(
                SurroundUITestContract.screenshotHistoryGameIDs[0]
            ),
            in: app
        )
        tap(
            SurroundUITestContract.AccessibilityID.gameRematch,
            in: app,
            matching: .button
        )
        element(
            SurroundUITestContract.AccessibilityID.screenCustomGame,
            in: app
        )
        element(
            SurroundUITestContract.AccessibilityID.gameRematchOpponent,
            in: app
        )
    }
}
