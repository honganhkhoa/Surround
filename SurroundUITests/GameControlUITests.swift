//
//  GameControlUITests.swift
//  SurroundUITests
//
//  The in-game control's journeys. In the live-banner fixture the control
//  of each correspondence game is the chip for the live game on your move,
//  so a tap would switch to that game and a touch and hold opens the
//  control's popover instead. When the control moves to another bar, Game
//  Detail closes the popover and clears the window's Activity request; at
//  the largest text sizes a hold still opens the popover, never the bar's
//  Large Content Viewer.
//

import XCTest
import UIKit

#if DEBUG
final class GameControlUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    private let gameID = SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
    private let largestText = [
        "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
    ]

    /// Turning the phone moves the control from the bottom bar to the top
    /// bar. The old item's popover closes and its request goes, and the new
    /// item opens the popover again.
    func testRotatingClosesThePopoverAndItsRequest() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The Mac doesn't turn.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "On an iPad the control keeps its bar when the window turns.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ], orientation: .portrait)
        defer { XCUIDevice.shared.orientation = .portrait }
        openTheGameFromHome(in: app)
        assertTheControlIsTheChip(in: app)
        let request = element(ID.debugActivityRequest, in: app)

        let popover = openGameControlPopover(in: app)
        XCTAssertTrue(waitForValue("gameControl", in: request, timeout: 10),
                      "The popover made the window's request: \(String(describing: request.value))")
        keepScreenshot("Popover from the bottom bar", in: app)

        turn(to: .landscapeLeft, in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "Turning closes the popover")
        XCTAssertTrue(waitForValue("none", in: request, timeout: 10),
                      "Turning clears its request: \(String(describing: request.value))")
        keepScreenshot("Landscape after the turn", in: app)

        let control = theControl(in: app)
        XCTAssertLessThan(control.frame.midY, app.frame.midY, "The control is in the top bar")
        holdGameControl(control, at: gameControlHoldOffset(control, in: app))
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "A hold opens the popover again from the new bar")
        XCTAssertTrue(waitForValue("gameControl", in: request, timeout: 10),
                      "The new popover made its own request: \(String(describing: request.value))")
        assertStillShowingTheGame(bannerGame, in: app)
        keepScreenshot("Popover from the landscape bar", in: app)
        dismissPopover(in: app)
        XCTAssertTrue(waitForValue("none", in: request, timeout: 10),
                      "Closing the popover clears its request: \(String(describing: request.value))")
        #endif
    }

    /// At accessibility sizes the bar gives a custom item the Large Content
    /// Viewer, whose touch and hold shows an enlarged copy and turns the
    /// release into a tap, which on the chip switches games. The control
    /// takes the viewer off: a hold opens the popover and the game stays,
    /// in the bottom bar and the landscape top bar on a phone, and in the
    /// wide top bar on an iPad. Activity's live-your-move state shows your
    /// live game with HarborMist's game as the chip, and draws no live-game
    /// pill over the bar, which at this size would cover the whole control.
    func testAtTheLargestTextSizeAHoldOpensThePopover() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The Mac's native item takes no hold.")
        #else
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let orientation: UIDeviceOrientation = isPhone ? .portrait : .landscapeLeft
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.activityStateLaunchArgument,
            SurroundUITestContract.ActivityFixtureState.liveYourMove.rawValue,
            SurroundUITestContract.activityOpenLaunchArgument,
            SurroundUITestContract.ActivityOpen.gamePopover.rawValue,
        ] + largestText, orientation: orientation)
        defer { XCUIDevice.shared.orientation = orientation }
        if !isPhone { restoreFullSizeWindow(in: app) }
        let game = (shown: SurroundUITestContract.fixtureGameID,
                    chip: SurroundUITestContract.ActivityFixtureID.harborMistGameID)
        element(ID.gameDetail(game.shown), in: app)
        // The launch opens the control's popover once; close it first.
        let popover = app.descendants(matching: .any).matching(identifier: ID.gameActiveGamesPopover).firstMatch
        if popover.waitForExistence(timeout: 10) { dismissPopover(in: app) }
        assertTheControlIsTheChip(in: app)
        assertAHoldOpensThePopover(in: isPhone ? "the bottom bar" : "the wide top bar", game: game, app: app)
        if isPhone {
            turn(to: .landscapeLeft, in: app)
            assertAHoldOpensThePopover(in: "the landscape top bar", game: game, app: app)
        }
        #endif
    }

    // MARK: Helpers

    private func openTheGameFromHome(in app: XCUIApplication) {
        let row = elementAfterScrolling(ID.homeGame(gameID), in: app)
        scrollIntoTappableArea(row, in: app)
        tap(row, description: "Open the first correspondence game", in: app)
        element(ID.gameDetail(gameID), in: app)
    }

    /// The chip, whose tap would switch games: a popover that opens and a
    /// game that stays show that the press was taken as a hold.
    private func assertTheControlIsTheChip(in app: XCUIApplication,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let firstState = element(ID.gameControlFirstState, in: app, file: file, line: line)
        XCTAssertTrue(pollUntil(timeout: 10) { (firstState.value as? String)?.hasPrefix("chip") == true },
                      "The control is the chip: \(String(describing: firstState.value))", file: file, line: line)
    }

    private func theControl(in app: XCUIApplication, file: StaticString = #filePath,
                            line: UInt = #line) -> XCUIElement {
        let control = app.buttons.matching(identifier: ID.gameActiveGamesButton).firstMatch
        XCTAssertTrue(pollUntil(timeout: 10) {
            control.exists && !control.frame.isEmpty && app.frame.contains(control.frame)
        }, "Expected the in-game control on screen", file: file, line: line)
        return control
    }

    private func turn(to orientation: UIDeviceOrientation, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(pollUntil(timeout: 10) { (app.frame.width > app.frame.height) == orientation.isLandscape },
                      "Expected the window to turn: \(app.frame)", file: file, line: line)
    }

    /// The live-banner fixture's: its first correspondence game, whose chip
    /// is the live game 26268404.
    private var bannerGame: (shown: Int, chip: Int) {
        (gameID, SurroundUITestContract.fixtureGameID)
    }

    private func assertStillShowingTheGame(_ game: (shown: Int, chip: Int), in app: XCUIApplication,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: ID.gameDetail(game.shown)).firstMatch.exists,
                      "No switch: game \(game.shown) is still on screen", file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: ID.gameDetail(game.chip)).firstMatch.exists,
                       "No switch to the chip's game \(game.chip)", file: file, line: line)
    }

    /// A three-second hold that lifts on the control, then a hold that
    /// moves off the control before it lifts. The viewer would take the
    /// second press, and its release away from the item would do nothing,
    /// so the popover opens only when the hold fired with the finger down:
    /// press timing alone, which treats a long press's release as a hold,
    /// can't open it.
    private func assertAHoldOpensThePopover(in form: String, game: (shown: Int, chip: Int), app: XCUIApplication,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let popover = app.descendants(matching: .any).matching(identifier: ID.gameActiveGamesPopover).firstMatch
        let control = theControl(in: app, file: file, line: line)
        let offset = gameControlHoldOffset(control, in: app)
        keepScreenshot("Largest text, \(form), before the holds", in: app)

        control.coordinate(withNormalizedOffset: offset).press(forDuration: 3)
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "In \(form) a hold opens the popover",
                      file: file, line: line)
        assertStillShowingTheGame(game, in: app, file: file, line: line)
        keepScreenshot("Largest text, \(form), the popover after a hold", in: app)
        dismissPopover(in: app, file: file, line: line)

        let away = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        theControl(in: app, file: file, line: line).coordinate(withNormalizedOffset: offset)
            .press(forDuration: 1, thenDragTo: away, withVelocity: .default, thenHoldForDuration: 0.5)
        XCTAssertTrue(popover.waitForExistence(timeout: 5),
                      "In \(form) the hold itself opens the popover, with no Large Content Viewer",
                      file: file, line: line)
        assertStillShowingTheGame(game, in: app, file: file, line: line)
        dismissPopover(in: app, file: file, line: line)
    }
}
#endif
