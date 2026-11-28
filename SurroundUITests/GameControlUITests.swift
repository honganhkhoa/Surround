//
//  GameControlUITests.swift
//  SurroundUITests
//
//  The in-game control's journeys: the form it takes in a game's bar and in
//  Zen, what a tap and a touch and hold do, where a switch goes, what its
//  popover holds, and where a game says that its connection is down. In the
//  live-banner fixture the control of each correspondence game is the chip
//  for the live game on your move; the Activity states
//  (`--surround-activity-state`) give the other forms. A tap on the chip
//  switches games, so a journey that wants the popover from it holds it;
//  the forms whose tap opens the popover are tapped. When the control moves
//  to another bar, Game Detail closes the popover and clears the window's
//  Activity request; at the largest text sizes a hold still opens the
//  popover, never the bar's Large Content Viewer.
//

import XCTest
import UIKit

#if DEBUG
final class GameControlUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias FixtureID = SurroundUITestContract.ActivityFixtureID

    /// The live-banner fixture's first correspondence game.
    private let gameID = SurroundUITestContract.liveBannerCorrespondenceGameIDs[0]
    /// The live game on your move in the live-banner fixture, and every
    /// Activity state's game.
    private let liveGameID = SurroundUITestContract.fixtureGameID
    /// The plain fixture's public game, which the user only watches.
    private let publicGameID = 25_291_907
    private let reconnecting = "Reconnecting…"
    private let cantReachOGS = "Can’t reach OGS"
    private let blackClock = "game.clock.black", whiteClock = "game.clock.white"
    private let largestText = [
        "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
    ]
    private static let iOSOnly =
        "iOS only: on the Mac the control is a native toolbar item, as testTheMacsControlOpensThePopover checks."

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Portrait on a phone, where the control is in the bottom bar; an
    /// iPad's wide top bar in landscape.
    private var preferredOrientation: UIDeviceOrientation { isPhone ? .portrait : .landscapeLeft }

    // MARK: Switching

    /// On Home's route the chip switches in place: the live game takes the
    /// correspondence game's place in Home's stack, and Public games keeps
    /// its own. A game hides the tab bar, so the correspondence game comes
    /// to Home from the public game's popover: Activity's correspondence row
    /// opens it on Home's route and leaves Public games' stack as it was.
    func testTheChipSwitchesInPlaceOnHomesRoute() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launchLiveBanner()
        openThePublicGame(in: app)
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        let popover = openGameControlPopover(in: app)
        tap(ID.activityRow("correspondence-games"), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "The row closes the popover")
        var opened: Int?
        XCTAssertTrue(pollUntil(timeout: 10) {
            opened = SurroundUITestContract.liveBannerCorrespondenceGameIDs.first {
                query(ID.gameDetail($0), in: app).exists
            }
            return opened != nil
        }, "Activity's row opens a correspondence game on Home's route")
        guard let opened else { return }
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        keepScreenshot("A correspondence game on Home's route", in: app)

        tapTheControl(in: app)
        element(ID.gameDetail(liveGameID), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.gameDetail(opened), in: app).exists },
                      "The live game takes the correspondence game's place")
        assertFirstState("base +0", in: app)
        XCTAssertFalse(query(ID.gameActiveGamesPopover, in: app).exists, "A tap on the chip opens no popover")
        keepScreenshot("The chip's game shown in place", in: app)
        backToHome(from: liveGameID, in: app)

        selectMainNavigation(ID.navigationPublicGames, in: app)
        XCTAssertTrue(query(ID.gameDetail(publicGameID), in: app).exists(within: 10),
                      "Public games keeps its stack: its game is still there")
        keepScreenshot("Public games still shows its game", in: app)
        #endif
    }

    /// A touch and hold on the chip opens one popover: the picker of
    /// same-speed games above Activity's sections. An entry switches in
    /// place and closes the popover.
    func testHoldOpensThePickerAboveActivity() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launchLiveBanner()
        openFromHome(gameID, in: app)
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        let popover = openGameControlPopover(in: app)
        let carousel = element(ID.gameActiveGamesCarousel, in: app)
        element(ID.activityList, in: app)
        let liveGames = element(ID.activitySection("liveGames"), in: app)
        XCTAssertTrue(waitForSettledFrame(of: carousel), "The picker settles")
        let sections = popover.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.section."))
            .allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
        attach(([carousel] + sections).map { "\($0.identifier) \($0.frame)" }.joined(separator: "\n"),
               name: "The picker and Activity's sections")
        XCTAssertTrue(sections.contains { $0.identifier == liveGames.identifier }, "Activity lists the live game")
        for section in sections {
            XCTAssertLessThanOrEqual(carousel.frame.maxY, section.frame.minY + 1,
                                     "The picker comes before \(section.identifier)")
        }
        for id in SurroundUITestContract.liveBannerCorrespondenceGameIDs {
            element(ID.gameActiveGamesEntry(id), in: app)
        }
        keepScreenshot("The picker above Activity", in: app)

        let second = SurroundUITestContract.liveBannerCorrespondenceGameIDs[1]
        tap(ID.gameActiveGamesEntry(second), in: app, matching: .button)
        element(ID.gameDetail(second), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "Picking a game closes the popover")
        XCTAssertFalse(query(ID.gameDetail(gameID), in: app).exists, "The pick switches in place")
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        #endif
    }

    /// Off Home's route the chip goes through Home: the live game shows on
    /// Home's route, and Game history's stack goes.
    func testOffHomesRouteTheChipGoesThroughHome() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launchLiveBanner()
        let historyGameID = SurroundUITestContract.liveBannerHistoryGameID
        let history = elementAfterScrolling(ID.homeHistoryViewAll, in: app, matching: .button)
        scrollIntoTappableArea(history, in: app)
        tap(history, description: "Open Game history", in: app)
        let list = element(ID.screenGameHistory, in: app)
        // Home keeps its own row for the game behind the pushed list.
        let row = list.descendants(matching: .any).matching(identifier: ID.homeHistoryGame(historyGameID)).firstMatch
        XCTAssertTrue(row.exists(within: 10), "Game history lists the finished game")
        scrollIntoTappableArea(row, in: app)
        tap(row, description: "Open the finished game from Game history", in: app)
        element(ID.gameDetail(historyGameID), in: app)
        assertFirstState("chip game-\(liveGameID) +0", in: app)

        tapTheControl(in: app)
        element(ID.gameDetail(liveGameID), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) {
            !query(ID.gameDetail(historyGameID), in: app).exists && !query(ID.screenGameHistory, in: app).exists
        }, "Through Home: Game history and its game go")
        keepScreenshot("The chip's game shown through Home", in: app)
        backToHome(from: liveGameID, in: app)
        #endif
    }

    /// A game opened from the iPad's account sheet is in the sheet's own
    /// stack, so its chip goes through Home, which closes the sheet. The
    /// own profile lists the user's finished games, not their active ones,
    /// so the game is the finished one in its Game history.
    func testTheIPadProfileSheetsChipClosesTheSheet() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        try XCTSkipIf(isPhone, "iPad only: a phone's own profile isn't a sheet.")
        let app = launchLiveBanner()
        let historyGameID = SurroundUITestContract.liveBannerHistoryGameID
        openOwnProfileFromMainNavigation(in: app)
        let profile = app.scrollViews.matching(identifier: ID.screenPlayerProfile).firstMatch
        let row = elementAfterScrolling(ID.profileHistoryGame(historyGameID), in: app, within: profile)
        tap(row, description: "Open the finished game from the own profile", in: app)
        // Pushed in the sheet's stack, over the profile.
        element(ID.gameDetail(historyGameID), in: app)
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        keepScreenshot("The chip in the account sheet's game", in: app)

        tapTheControl(in: app)
        // The sheet held the profile and this game: both go with it.
        XCTAssertTrue(pollUntil(timeout: 10) {
            !query(ID.gameDetail(historyGameID), in: app).exists && !query(ID.screenPlayerProfile, in: app).exists
                && !query("account.sheet.done", in: app).exists
        }, "The chip's tap closes the sheet")
        element(ID.gameDetail(liveGameID), in: app)
        keepScreenshot("The chip's game after the sheet closed", in: app)
        backToHome(from: liveGameID, in: app)
        #endif
    }

    /// The Mac's control is the toolbar's native item with the system's
    /// badge. A click opens the popover, whose Live games section leads
    /// with the chip's game, and Escape closes it; nothing switches.
    /// Needs a signed build and Automation Mode.
    func testTheMacsControlOpensThePopover() throws {
        #if !targetEnvironment(macCatalyst)
        throw XCTSkip("Mac only: an iOS bar's control is a custom item.")
        #else
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
            SurroundUITestContract.catalystWindowSizeLaunchArgument, "900x700",
        ])
        element(ID.screenHome, in: app)
        openFromHome(gameID, in: app)
        // A native toolbar item reaches XCTest without its identifier on
        // the Mac, so the item is found by the game its label names.
        let control = app.toolbars.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "OrbitFox, your move")).firstMatch
        XCTAssertTrue(control.exists(within: 10), "The toolbar shows the native item")
        attach("label \(control.label)\nvalue \(String(describing: control.value))\nframe \(control.frame)",
               name: "The native item")
        keepScreenshot("The native item with its count", in: app)
        // The native label names the chip's game without its time.
        XCTAssertTrue(control.label.hasPrefix("OrbitFox, your move in your live game"),
                      "The item names the live game on your move: \(control.label)")
        XCTAssertFalse(control.label.hasSuffix("left"), "The native label carries no time: \(control.label)")

        control.click()
        let popover = element(ID.gameActiveGamesPopover, in: app)
        element(ID.activitySection("liveGames"), in: app)
        let rows = popover.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.row.game-"))
            .allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
        let first = rows.min { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(first?.identifier, ID.activityRow("game-\(liveGameID)"),
                       "Live games leads with the chip's game: \(rows.map(\.identifier))")
        keepScreenshot("The popover from a click", in: app)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "Escape closes the popover")
        XCTAssertTrue(query(ID.gameDetail(gameID), in: app).exists && !query(ID.gameDetail(liveGameID), in: app).exists,
                      "Nothing switches")
        #endif
    }

    // MARK: The popover

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
        XCTAssertLessThan(control.frame.midY, windowFrame(in: app).midY, "The control is in the top bar")
        holdGameControl(control)
        XCTAssertTrue(popover.exists(within: 10), "A hold opens the popover again from the new bar")
        XCTAssertTrue(waitForValue("gameControl", in: request, timeout: 10),
                      "The new popover made its own request: \(String(describing: request.value))")
        assertStillShowingTheGame(bannerGame, in: app)
        keepScreenshot("Popover from the landscape bar", in: app)
        dismissPopover(in: app)
        XCTAssertTrue(waitForValue("none", in: request, timeout: 10),
                      "Closing the popover clears its request: \(String(describing: request.value))")
        #endif
    }

    /// The popover stays while Activity empties under it. In a game you
    /// only watch, the inbox counts the challenge; the popover's row offers
    /// View, whose card rejects it, and the row keeps "Rejected" until the
    /// popover closes. With nothing left, the slot then hides.
    func testThePopoverStaysWhenActivityEmpties() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.challengeReceived, actionsSucceed: true)
        openThePublicGame(in: app)
        assertFirstState("inbox 1", in: app)
        let control = theControl(in: app)
        XCTAssertEqual(control.label, "Activity", "The inbox form")
        XCTAssertEqual(control.value as? String, "1 waiting", "The inbox counts the challenge")
        tapTheControl(in: app)
        let popover = element(ID.gameActiveGamesPopover, in: app)
        let challenge = "challenge-\(FixtureID.usualChallengeID)"
        let view = element(ID.activityRow(challenge, .view), in: app, matching: .button)
        XCTAssertFalse(query(ID.activityRow(challenge, .accept), in: app).exists,
                       "In a game's popover a challenge offers View")
        keepScreenshot("The inbox's popover", in: app)

        tap(view, description: "View CedarWave's challenge", in: app)
        let card = app.popovers.firstMatch.navigationBars["Challenge"].firstMatch
        XCTAssertTrue(card.exists(within: 10), "View pushes the challenge's card inside the popover")
        tap(cardButton("Reject", in: app), description: "Reject on the challenge's card", in: app)
        let result = query(ID.activityRowResult(challenge), in: app)
        XCTAssertTrue(waitForLabel("Rejected", of: result), "Back in the list, the row says Rejected")
        XCTAssertTrue(staysPresent(popover), "The popover stays when Activity empties")
        XCTAssertTrue(query(ID.activityList, in: app).exists && result.exists, "The list keeps the row's result")
        keepScreenshot("The popover after Activity emptied", in: app)

        dismissPopover(in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.gameActiveGamesButton, in: app).exists },
                      "With nothing waiting and no picker, the slot hides once its popover closes")
        #endif
    }

    /// A game you only watch has no picker: the control is the inbox, with
    /// what waits as its count.
    func testSpectatedGamesShowTheInbox() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.nothingLeads)
        openThePublicGame(in: app)
        assertFirstState("inbox 3", in: app)
        let control = theControl(in: app)
        XCTAssertEqual(control.label, "Activity", "The inbox form")
        XCTAssertEqual(control.value as? String, "3 waiting", "The inbox's count")
        keepScreenshot("The inbox in a game you watch", in: app)
        tapTheControl(in: app)
        let popover = element(ID.gameActiveGamesPopover, in: app)
        element(ID.activityList, in: app)
        XCTAssertFalse(popover.descendants(matching: .any).matching(identifier: ID.gameActiveGamesCarousel)
            .firstMatch.exists, "A game you watch has no picker")
        #endif
    }

    /// While you play live, what waits shows as a dot on the control, whose
    /// tap opens the popover.
    func testPlayingLiveTurnsWaitingIntoADot() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.challengeReceived)
        openFromHome(liveGameID, in: app)
        assertFirstState("dot", in: app)
        let control = theControl(in: app)
        XCTAssertEqual(control.label, "Active games", "The base form, with its dot")
        XCTAssertEqual(control.value as? String, "New activity waiting", "The dot says what waits")
        keepScreenshot("The dot while you play live", in: app)
        tapTheControl(in: app)
        element(ID.gameActiveGamesPopover, in: app)
        element(ID.activityRow("challenge-\(FixtureID.usualChallengeID)"), in: app)
        #endif
    }

    /// At game over the opponent's challenge comes first in the popover,
    /// above Activity's sections, with no picker: the only live game is the
    /// finished one. A live Accept closes the popover and opens the new game.
    func testGameOverShowsTheCardFirst() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.rematchOffered, actionsSucceed: true)
        openFromHome(liveGameID, in: app)
        let card = "challenge-\(FixtureID.rematchChallengeID)"
        assertFirstState("card \(card) +0", in: app)
        XCTAssertTrue(theControl(in: app).label.hasPrefix("Challenge from OrbitFox"), "The game-over form")
        tapTheControl(in: app)
        let popover = element(ID.gameActiveGamesPopover, in: app)
        let row = element(ID.activityRow(card), in: app)
        XCTAssertTrue(waitForSettledFrame(of: row), "The card settles")
        let others = popover.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                                  "activity.section.", "activity.row."))
            .allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty && !$0.identifier.hasPrefix(row.identifier) }
        for other in others {
            XCTAssertLessThan(row.frame.minY, other.frame.minY, "The card comes before \(other.identifier)")
        }
        XCTAssertFalse(query(ID.activitySection("challengesReceived"), in: app).exists,
                       "The card's challenge stays out of Challenges received")
        XCTAssertFalse(popover.descendants(matching: .any).matching(identifier: ID.gameActiveGamesCarousel)
            .firstMatch.exists, "No picker: the only live game is over")
        keepScreenshot("The card first", in: app)

        tap(ID.activityRow(card, .accept), in: app, matching: .button)
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "A live Accept closes the popover")
        element(ID.gameDetail(FixtureID.acceptedGameID(FixtureID.rematchChallengeID)), in: app)
        keepScreenshot("The accepted game", in: app)
        #endif
    }

    // MARK: Fit

    /// The chip keeps Analyze and Chat in the bar beside a third mode, in
    /// French, at the largest text size, in a theme that adds its own bar
    /// item: it takes the frame its window's width gives at that size, and
    /// the bar folds nothing into More. In a phone's portrait bottom bar that
    /// frame is 160 points from 402 points wide, 120 from 375 with three
    /// modes, 44 below; in top bars it is 96.
    func testTheControlNeverHidesAnalyzeOrChat() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
            SurroundUITestContract.liveGameBannerConditionalMovesLaunchArgument,
            SurroundUITestContract.themeLaunchArgument, "flowingInk",
        ] + largestText, orientation: preferredOrientation, language: "fr")
        defer { XCUIDevice.shared.orientation = preferredOrientation }
        prepareWindow(of: app)
        element(ID.screenHome, in: app)
        openFromHome(SurroundUITestContract.conditionalMovesFixtureGameID, in: app)
        assertFirstState("chip game-\(liveGameID) +0", in: app)
        assertTheChipKeepsTheModes(in: isPhone ? "the portrait bottom bar" : "the wide top bar", app: app)
        if isPhone {
            turn(to: .landscapeLeft, in: app)
            assertTheChipKeepsTheModes(in: "the landscape top bar", app: app)
        }
        #endif
    }

    /// At accessibility sizes the bar gives a custom item the Large Content
    /// Viewer, whose touch and hold shows an enlarged copy and turns the
    /// release into a tap, which on the chip switches games. The control
    /// takes the viewer off: a hold opens the popover and the game stays,
    /// in the bottom bar and the landscape top bar on a phone, and in the
    /// wide top bar on an iPad.
    func testAtTheLargestTextSizeAHoldOpensThePopover() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The Mac's native item takes no hold.")
        #else
        let app = launchLiveBanner(largestText)
        defer { XCUIDevice.shared.orientation = preferredOrientation }
        openTheGameFromHome(in: app)
        assertTheControlIsTheChip(in: app)
        assertAHoldOpensThePopover(in: isPhone ? "the bottom bar" : "the wide top bar", game: bannerGame, app: app)
        if isPhone {
            turn(to: .landscapeLeft, in: app)
            assertAHoldOpensThePopover(in: "the landscape top bar", game: bannerGame, app: app)
        }
        #endif
    }

    // MARK: Zen

    /// In Zen the control shows only another live game on your move, with
    /// no count, in the form the layout gives it. From a correspondence game
    /// a tap leaves Zen for the live game; from a live game Zen stays. A
    /// challenge alone shows nothing.
    func testZenShowsOnlyAnotherLiveGameOnYourMove() throws {
        let harborMist = FixtureID.harborMistGameID
        var app = launch(.several)
        openFromHome(FixtureID.correspondenceGameIDs[0], in: app)
        assertFirstState("chip game-\(harborMist) +3", in: app)
        enterZen(in: app)
        var zen = theZenControl(in: app)
        assertZenForm(of: zen, in: app)
        XCTAssertTrue(zen.label.hasPrefix("HarborMist, your move in your live game"),
                      "Zen shows HarborMist's game: \(zen.label)")
        XCTAssertFalse(zen.label.contains("more"), "No count in Zen: \(zen.label)")
        // A custom form has no value in Zen; a native item's badge of 1 reads as one item.
        XCTAssertTrue(["", "1 item"].contains(zen.value as? String ?? ""),
                      "No count in Zen: \(String(describing: zen.value))")
        keepScreenshot("Zen in a correspondence game", in: app)
        activate(zen, at: CGVector(dx: 0.5, dy: 0.5))
        element(ID.gameDetail(harborMist), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.gameZenExit, in: app).exists },
                      "From a correspondence game, Zen ends")
        app.terminate()

        app = launch(.liveYourMove)
        openFromHome(liveGameID, in: app)
        enterZen(in: app)
        zen = theZenControl(in: app)
        assertZenForm(of: zen, in: app)
        keepScreenshot("Zen in a live game", in: app)
        activate(zen, at: CGVector(dx: 0.5, dy: 0.5))
        element(ID.gameDetail(harborMist), in: app)
        XCTAssertTrue(query(ID.gameZenExit, in: app).exists(within: 10),
                      "From a live game to a live game, Zen stays")
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.gameZenControl, in: app).exists },
                      "HarborMist's game has no other live game on your move")
        app.terminate()

        app = launch(.challengeReceived)
        openFromHome(liveGameID, in: app)
        enterZen(in: app)
        XCTAssertFalse(pollUntil(timeout: 3) { query(ID.gameZenControl, in: app).exists },
                       "A challenge alone shows nothing in Zen")
        keepScreenshot("Zen with a challenge waiting", in: app)
    }

    // MARK: Connection status

    /// In play the clocks carry the mark: the to-move clock in the body,
    /// then the header's chips in Chat and Analyze. The title slot never
    /// shows the capsule there.
    func testOfflinePlayKeepsTheClockMark() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.liveYourMove, offline: true)
        openFromHome(FixtureID.harborMistGameID, in: app)
        assertTheMark(onA: .body, in: "Play", app: app)
        assertNoCapsule(for: 2, in: "Play", app: app)
        keepScreenshot("The clock's mark in play", in: app)
        // A phone's Chat and Analyze move the clocks into the header.
        setMode(.chat, on: true, in: app)
        assertTheMark(onA: isPhone ? .headerChip : nil, in: "Chat", app: app)
        assertNoCapsule(for: 1, in: "Chat", app: app)
        keepScreenshot("The mark in Chat", in: app)
        setMode(.chat, on: false, in: app)
        setMode(.analyze, on: true, in: app)
        assertTheMark(onA: isPhone ? .headerChip : nil, in: "Analyze", app: app)
        assertNoCapsule(for: 1, in: "Analyze", app: app)
        keepScreenshot("The mark in Analyze", in: app)
        setMode(.analyze, on: false, in: app)
        #endif
    }

    /// A game opened during an outage, with no clock in play, has its
    /// status in the title slot from its first frame, and Accept dims. In
    /// Chat and Analyze one clock carries the mark instead.
    func testOpeningAGameDuringAnOutageShowsItsStatusAtOnce() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.stoneRemoval, offline: true)
        // The window's status shows two seconds into the outage.
        Thread.sleep(forTimeInterval: 3)
        openFromHome(FixtureID.stoneRemovalGameID, in: app)
        let capsule = query(ID.gameConnectionStatus, in: app)
        XCTAssertTrue(capsule.exists, "The capsule shows from the game's first read")
        XCTAssertTrue([reconnecting, cantReachOGS].contains(capsule.label), "The capsule: \(capsule.label)")
        XCTAssertFalse(pollUntil(timeout: 5) { !capsule.exists }, "The capsule stays")
        let accept = app.buttons.matching(NSPredicate(format: "label == %@", "Accept")).firstMatch
        XCTAssertTrue(accept.exists(within: 10), "Stone removal offers Accept")
        XCTAssertFalse(accept.isEnabled, "Offline, Accept is disabled")
        XCTAssertEqual(accept.value as? String, reconnecting, "Accept says why")
        keepScreenshot("The capsule and Accept", in: app)

        setMode(.chat, on: true, in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !capsule.exists }, "Chat has no capsule")
        assertOneClockCarriesTheMark(in: "Chat", app: app)
        keepScreenshot("One clock's mark in Chat", in: app)
        setMode(.chat, on: false, in: app)
        setMode(.analyze, on: true, in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !capsule.exists }, "Analyze has no capsule")
        assertOneClockCarriesTheMark(in: "Analyze", app: app)
        keepScreenshot("One clock's mark in Analyze", in: app)
        setMode(.analyze, on: false, in: app)
        #endif
    }

    /// A switch in place during an outage moves the status with the game:
    /// the clock's mark in the live game in play, and in the game in stone
    /// removal, picked from the popover's Live games, the capsule at once.
    func testSwitchingInPlaceDuringAnOutageMovesTheStatus() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.stoneRemoval, offline: true)
        openFromHome(liveGameID, in: app)
        let capsule = query(ID.gameConnectionStatus, in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { markedClocks(in: app).contains { $0.identifier == blackClock } },
                      "OrbitFox's clock, which is to move, carries the mark")
        XCTAssertFalse(capsule.exists, "In play there is no capsule")
        assertFirstState("chip game-\(FixtureID.stoneRemovalGameID) +0", in: app)
        keepScreenshot("The mark in the live game", in: app)

        let popover = openGameControlPopover(in: app)
        tap(ID.activityRow("game-\(FixtureID.stoneRemovalGameID)"), in: app)
        element(ID.gameDetail(FixtureID.stoneRemovalGameID), in: app)
        XCTAssertTrue(capsule.exists, "The capsule shows at once in the game switched to")
        XCTAssertFalse(query(ID.gameDetail(liveGameID), in: app).exists, "The row switches in place")
        XCTAssertTrue(pollUntil(timeout: 10) { !popover.exists }, "The switch closes the popover")
        keepScreenshot("The capsule after the switch", in: app)
        #endif
    }

    /// After the game, offline: the capsule, and Rematch disabled.
    func testOfflineGameOverDisablesRematch() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.rematchOffered, offline: true)
        openFromHome(liveGameID, in: app)
        let capsule = element(ID.gameConnectionStatus, in: app)
        XCTAssertTrue([reconnecting, cantReachOGS].contains(capsule.label), "The capsule: \(capsule.label)")
        let rematch = element(ID.gameRematch, in: app, matching: .button)
        XCTAssertFalse(rematch.isEnabled, "Offline, Rematch is disabled")
        XCTAssertEqual(rematch.value as? String, reconnecting, "Rematch says why")
        keepScreenshot("The capsule and Rematch disabled", in: app)
        #endif
    }

    /// Thirty seconds into an outage the capsule says OGS can't be reached,
    /// with Retry where both fit, and the words alone where they don't; the
    /// popover offers Retry then. Retry in the slot reads Reconnecting… again.
    func testCantReachOGSOffersRetry() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.stoneRemoval, offline: true)
        defer { XCUIDevice.shared.orientation = preferredOrientation }
        openFromHome(FixtureID.stoneRemovalGameID, in: app)
        let capsule = element(ID.gameConnectionStatus, in: app)
        // The outage began at launch; its words change 30 s into it.
        XCTAssertTrue(waitForLabel(cantReachOGS, of: capsule, timeout: 40),
                      "Thirty seconds in, the capsule says \(cantReachOGS): \(capsule.label)")
        let retry = query(ID.gameConnectionStatusRetry, in: app)
        if !(retry.exists && retry.isHittable) {
            keepScreenshot("The words alone", in: app)
            let popover = openGameControlPopover(in: app)
            XCTAssertTrue(waitForLabel(cantReachOGS, of: element(ID.activityStatus, in: app)),
                          "The popover's status line says it too")
            element(ID.activityStatusRetry, in: app, matching: .button)
            dismissPopover(in: app)
            XCTAssertFalse(popover.exists)
            XCTAssertTrue(isPhone, "A full-size iPad window fits Retry beside the words")
            // A phone's landscape bar fits both.
            turn(to: .landscapeLeft, in: app)
        }
        XCTAssertTrue(pollUntil(timeout: 10) { retry.exists && retry.isHittable }, "The slot offers Retry")
        keepScreenshot("Retry in the slot", in: app)
        tap(retry, description: "Retry in the title slot", in: app)
        XCTAssertTrue(waitForLabel(reconnecting, of: capsule, timeout: 10), "Retry reads \(reconnecting) again")
        keepScreenshot("After Retry", in: app)
        #endif
    }

    /// The connection commands take the socket down and back. With no clock
    /// in play the capsule waits two seconds, as the window's status does,
    /// and goes with the restore; in play the to-move clock's mark comes
    /// from the socket at once.
    func testADropAndRestoreMovesTheStatus() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip(Self.iOSOnly)
        #else
        let app = launch(.stoneRemoval)
        openFromHome(FixtureID.stoneRemovalGameID, in: app)
        let capsule = query(ID.gameConnectionStatus, in: app)
        XCTAssertFalse(pollUntil(timeout: 2) { capsule.exists }, "Online, no capsule")
        let dropped = Date()
        post(.drop)
        var capsuleDelay: TimeInterval?
        XCTAssertTrue(pollUntil(timeout: 10) {
            guard capsule.exists else { return false }
            capsuleDelay = Date().timeIntervalSince(dropped)
            return true
        }, "A drop shows the capsule")
        attach("The capsule showed \(capsuleDelay.map { String(format: "%.2f", $0) } ?? "never") s after the drop",
               name: "The capsule's delay")
        XCTAssertGreaterThanOrEqual(capsuleDelay ?? 0, 1.5, "The capsule waits about two seconds after the drop")
        keepScreenshot("The capsule after a drop", in: app)
        post(.restore)
        XCTAssertTrue(pollUntil(timeout: 10) { !capsule.exists }, "The restore takes the capsule away")
        backToHome(from: FixtureID.stoneRemovalGameID, in: app)

        openFromHome(liveGameID, in: app)
        XCTAssertTrue(markedClocks(in: app).isEmpty, "Online, no clock carries the mark")
        let droppedAgain = Date()
        post(.drop)
        var markDelay: TimeInterval?
        // One snapshot a read, so a read's own time hardly counts.
        XCTAssertTrue(pollUntil(timeout: 10) {
            guard markedClocks(in: app).contains(where: { $0.identifier == blackClock }) else { return false }
            markDelay = Date().timeIntervalSince(droppedAgain)
            return true
        }, "A drop marks OrbitFox's clock, which is to move")
        attach("The mark showed \(markDelay.map { String(format: "%.2f", $0) } ?? "never") s after the drop",
               name: "The mark's delay")
        XCTAssertLessThan(markDelay ?? .infinity, 2, "The mark comes from the socket, before the window's status")
        XCTAssertFalse(capsule.exists, "In play there is no capsule")
        keepScreenshot("The mark after a drop", in: app)
        post(.restore)
        XCTAssertTrue(pollUntil(timeout: 10) { markedClocks(in: app).isEmpty }, "The restore takes the mark away")
        #endif
    }

    // MARK: Launching

    /// The live-banner fixture at Home.
    private func launchLiveBanner(_ extra: [String] = [], file: StaticString = #filePath,
                                  line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.liveGameBannerNavigationLaunchArgument,
        ] + extra, orientation: preferredOrientation)
        prepareWindow(of: app)
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    /// An Activity state at Home, on the frozen fixture clock.
    private func launch(_ state: State, offline: Bool = false, actionsSucceed: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.activityStateLaunchArgument, state.rawValue]
        if offline {
            arguments += [SurroundUITestContract.activityConnectionLaunchArgument,
                          SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        }
        if actionsSucceed {
            arguments += [SurroundUITestContract.activityActionsLaunchArgument,
                          SurroundUITestContract.ActivityActions.succeed.rawValue]
        }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: preferredOrientation)
        prepareWindow(of: app)
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    /// An iPad keeps a window another run resized: these journeys start full size.
    private func prepareWindow(of app: XCUIApplication) {
        #if !targetEnvironment(macCatalyst)
        if !isPhone { restoreFullSizeWindow(in: app) }
        #endif
    }

    // MARK: Navigating

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens a game from Home's list once bounded drags of Home's own
    /// content have brought the row's centre clear of the bars. A row not
    /// yet in the tree lies below, and once two drags in a row no longer
    /// move the list, above: one such drag can be a drag the list never
    /// took. At the largest text sizes the row can lie seven drags down,
    /// past the three drags after which `HomeRowSearch` turns, so the drags
    /// leave room for a search that turns at the list's end.
    private func openFromHome(_ gameID: Int, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let home = app.scrollViews.matching(identifier: ID.screenHome).firstMatch
        XCTAssertTrue(home.exists(within: 10), "Expected Home's list", file: file, line: line)
        let row = home.buttons.matching(identifier: ID.homeGame(gameID)).firstMatch
        let maxDrags = 16
        var drags = 0
        var liesAbove = false
        var listBeforeDrag: [CGRect]?
        // Drags in a row that left the list where it stood, and the search's turns.
        var stillDrags = 0
        var turns = 0
        #if !targetEnvironment(macCatalyst)
        // A drag that carries the row past the viewport is followed by
        // shorter ones the other way, so the search settles.
        var damping: CGFloat = 1
        var draggedUp: Bool?
        #endif
        for attempt in 0...maxDrags {
            let viewport = homeViewport(in: app)
            let isClear = row.exists && viewport.contains(CGPoint(x: row.frame.midX, y: row.frame.midY))
            #if targetEnvironment(macCatalyst)
            // On the Mac XCTest calls Home's rows unhittable even with
            // nothing over them, so a click at the row's centre opens it.
            if isClear {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                element(ID.gameDetail(gameID), in: app, file: file, line: line)
                return
            }
            #else
            if isClear, row.isHittable {
                tap(row, description: "Open game \(gameID) from Home", in: app, file: file, line: line)
                element(ID.gameDetail(gameID), in: app, file: file, line: line)
                return
            }
            #endif
            guard attempt < maxDrags, !viewport.isEmpty else { break }
            drags += 1
            let delta: CGFloat
            if row.exists {
                delta = row.frame.midY - viewport.midY
                listBeforeDrag = nil
                stillDrags = 0
            } else {
                // A list dragged at its end springs back to where it stood,
                // so it is read once it has stopped. One drag that left it
                // there may be a drag it never took: the search turns at the
                // second in a row, which starts further from the edge.
                let list = settledListFrames(home)
                if listStoodStill(list, since: listBeforeDrag) {
                    stillDrags += 1
                    if stillDrags == 2 {
                        liesAbove.toggle()
                        stillDrags = 0
                        turns += 1
                    }
                } else {
                    stillDrags = 0
                }
                listBeforeDrag = list
                delta = liesAbove ? -viewport.height : viewport.height
            }
            #if targetEnvironment(macCatalyst)
            // A scroll at a point in Home's visible list. On the Mac XCTest
            // finds no hit point for Home's scroll view, nor for the app,
            // whose frame there is empty; a swipe on the window lands on
            // its title bar.
            let window = app.windows.firstMatch
            let point = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: viewport.midX - window.frame.minX, dy: viewport.midY - window.frame.minY))
            let distance = max(40, min(abs(delta), viewport.height * 0.6))
            point.scroll(byDeltaX: 0, deltaY: delta >= 0 ? -distance : distance)
            #else
            // Only a found row's correction shortens the next drag; turning
            // a search the other way doesn't.
            if row.exists, let draggedUp, draggedUp != (delta >= 0) { damping /= 2 }
            draggedUp = delta >= 0
            let distance = max(40, min(abs(delta), viewport.height * (row.exists ? 0.6 : 0.8)) * damping)
            let inset = stillDrags == 1 ? viewport.height / 4 : 4
            let startY = delta >= 0 ? viewport.maxY - inset : viewport.minY + inset
            let origin = home.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - home.frame.minX, dy: startY - home.frame.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: delta >= 0 ? -distance : distance))
            // Slowly, and held before lifting, so Home stops where the drag ends.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            #endif
        }
        XCTFail("Expected game \(gameID) on Home, clear of its bars, after \(drags) drags and \(turns) turns",
                file: file, line: line)
    }

    /// Every frame in Home's list, from one snapshot.
    private func homeListFrames(_ home: XCUIElement) -> [CGRect] {
        guard let root = try? home.snapshot() else { return [] }
        var frames = [CGRect]()
        var pending: [XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            frames.append(node.frame)
            pending.append(contentsOf: node.children)
        }
        return frames
    }

    /// Home's list once two reads in a row agree, so that a list still
    /// springing back from its end isn't taken to have moved.
    private func settledListFrames(_ home: XCUIElement) -> [CGRect] {
        var list = homeListFrames(home)
        _ = pollUntil(timeout: 1) {
            let again = homeListFrames(home)
            defer { list = again }
            return listStoodStill(again, since: list)
        }
        return list
    }

    /// Whether a drag left Home's list where it stood, as at the list's end.
    private func listStoodStill(_ list: [CGRect], since before: [CGRect]?) -> Bool {
        guard let before, !list.isEmpty, list.count == before.count else { return false }
        return zip(list, before).allSatisfy { abs($0.minY - $1.minY) < 1 }
    }

    /// Home's visible content: its clipped frame in the window, from its top
    /// edge, since nothing floats over the top of Home's content, to above
    /// the bottom chrome, a tab bar, the Activity bar or a docked keyboard,
    /// wherever Home's frame ends.
    private func homeViewport(in app: XCUIApplication) -> CGRect {
        let window = windowFrame(in: app)
        var viewport = app.descendants(matching: .any).matching(identifier: ID.screenHome)
            .allElementsBoundByIndex.map(\.frame)
            .filter { !$0.isEmpty && $0.intersects(window) }
            .reduce(window) { $0.intersection($1) }
            .insetBy(dx: 8, dy: 8)
        if let chromeTop = bottomChromeTop(over: viewport, in: app), chromeTop - 8 < viewport.maxY {
            viewport.size.height = max(0, chromeTop - 8 - viewport.minY)
        }
        return viewport
    }

    private func openTheGameFromHome(in app: XCUIApplication) {
        openFromHome(gameID, in: app)
    }

    private func openThePublicGame(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        selectMainNavigation(ID.navigationPublicGames, in: app)
        element(ID.screenPublicGames, in: app, file: file, line: line)
        tap(ID.publicGame(publicGameID), in: app, file: file, line: line)
        element(ID.gameDetail(publicGameID), in: app, file: file, line: line)
    }

    /// Back from a game to Home, on whose route the game was. iOS 18 names
    /// Back after Home's title, which the control's base form shares.
    private func backToHome(from gameID: Int, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let backs = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR (identifier != %@ AND (label == %@ OR label == %@))",
            "BackButton", ID.gameActiveGamesButton, "Active games", "Back"
        ))
        var back: XCUIElement?
        XCTAssertTrue(pollUntil(timeout: 10) {
            back = backs.allElementsBoundByIndex.first { $0.isHittable }
            return back != nil
        }, "Expected the game's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back to Home", in: app, file: file, line: line)
        element(ID.screenHome, in: app, file: file, line: line)
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.gameDetail(gameID), in: app).exists },
                      "Back returns to Home, on whose route the game was", file: file, line: line)
    }

    /// Turns the device and waits until the window has the new shape and
    /// the same frame on two reads in a row: mid-turn, its frame is skewed.
    private func turn(to orientation: UIDeviceOrientation, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.orientation = orientation
        var previous: CGRect?
        XCTAssertTrue(pollUntil(timeout: 10) {
            let window = windowFrame(in: app)
            defer { previous = window }
            return (window.width > window.height) == orientation.isLandscape && window == previous
        }, "Expected the window to turn and settle: \(windowFrame(in: app))", file: file, line: line)
    }

    private func enterZen(in app: XCUIApplication) {
        activateZenControl(ID.gameZenEnter, in: app)
        element(ID.gameZenExit, in: app)
    }

    // MARK: The control

    /// The control's state as it first drew for the game on screen
    /// (`GameControlSlot.testDescription`).
    private func assertFirstState(_ expected: String, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let firstState = element(ID.gameControlFirstState, in: app, file: file, line: line)
        XCTAssertTrue(pollUntil(timeout: 10) { firstState.value as? String == expected },
                      "The control first draws \(expected), not \(String(describing: firstState.value))",
                      file: file, line: line)
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
            control.exists && !control.frame.isEmpty && windowFrame(in: app).contains(control.frame)
        }, "Expected the in-game control on screen", file: file, line: line)
        return control
    }

    /// A tap at the control's centre, where a person taps it: the chip
    /// switches, and the forms without a game open the popover.
    private func tapTheControl(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        activate(theControl(in: app, file: file, line: line), at: CGVector(dx: 0.5, dy: 0.5))
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
        let offset = CGVector(dx: 0.5, dy: 0.5)
        keepScreenshot("Largest text, \(form), before the holds", in: app)

        control.coordinate(withNormalizedOffset: offset).press(forDuration: 3)
        XCTAssertTrue(popover.exists(within: 5), "In \(form) a hold opens the popover",
                      file: file, line: line)
        assertStillShowingTheGame(game, in: app, file: file, line: line)
        keepScreenshot("Largest text, \(form), the popover after a hold", in: app)
        dismissPopover(in: app, file: file, line: line)

        let away = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        theControl(in: app, file: file, line: line).coordinate(withNormalizedOffset: offset)
            .press(forDuration: 1, thenDragTo: away, withVelocity: .default, thenHoldForDuration: 0.5)
        XCTAssertTrue(popover.exists(within: 5),
                      "In \(form) the hold itself opens the popover, with no Large Content Viewer",
                      file: file, line: line)
        assertStillShowingTheGame(game, in: app, file: file, line: line)
        dismissPopover(in: app, file: file, line: line)
    }

    /// The chip beside the three modes in one bar, in the frame its form and
    /// window give it at the largest text size, with no More; Analyze and
    /// Chat each open their panel from the bar, and close it again.
    private func assertTheChipKeepsTheModes(in form: String, app: XCUIApplication,
                                            file: StaticString = #filePath, line: UInt = #line) {
        var window = windowFrame(in: app)
        let control = app.buttons.matching(identifier: ID.gameActiveGamesButton).firstMatch
        let shown = pollUntil(timeout: 10) {
            window = windowFrame(in: app)
            return control.exists && !control.frame.isEmpty && window.contains(control.frame)
        }
        let modes = [("Conditional moves", query(ID.gameConditionalButton, in: app)),
                     ("Analyze", gameAnalyzeControl(in: app)), ("Chat", gameChatControl(in: app))]
        let overflow = app.buttons.matching(NSPredicate(
            format: "identifier ENDSWITH %@ OR label IN %@", "OverflowBarButtonItem", ["More", "Plus"]
        )).firstMatch
        // The frames first, so a missing chip still shows where the modes are.
        attach((["window \(window)", shown ? "control \(control.frame) label \(control.label)" : "control absent"]
                + modes.map { "\($0.0) \($0.1.exists ? "\($0.1.frame) hittable \($0.1.isHittable)" : "absent")" }
                + [overflow.exists ? "More \(overflow.frame)" : "More absent"]).joined(separator: "\n"),
               name: "Frames in \(form)")
        keepScreenshot("The chip beside three modes in \(form)", in: app)
        XCTAssertTrue(shown, "In \(form) the chip is on screen beside the modes", file: file, line: line)
        let inTopBar = control.frame.midY < window.midY
        let width: CGFloat = inTopBar ? 96 : window.width < 375 ? 44 : window.width < 402 ? 120 : 160
        XCTAssertEqual(control.frame.width, width, accuracy: 1, "In \(form) the chip is \(Int(width)) points wide",
                       file: file, line: line)
        XCTAssertEqual(control.frame.height, 44, accuracy: 1, "In \(form) the chip is 44 points high",
                       file: file, line: line)
        XCTAssertFalse(overflow.exists, "In \(form) the bar folds nothing into More", file: file, line: line)
        for (name, mode) in modes {
            XCTAssertTrue(mode.exists && !mode.frame.isEmpty && window.contains(mode.frame),
                          "In \(form) \(name) is in the bar", file: file, line: line)
            XCTAssertEqual(mode.frame.midY, control.frame.midY, accuracy: 12,
                           "In \(form) \(name) is in the chip's bar", file: file, line: line)
            XCTAssertFalse(mode.frame.intersects(control.frame), "In \(form) \(name) is clear of the chip",
                           file: file, line: line)
        }
        for mode in [Mode.analyze, .chat] {
            setMode(mode, on: true, in: app, file: file, line: line)
            setMode(mode, on: false, in: app, file: file, line: line)
        }
    }

    // MARK: Zen's control

    private func theZenControl(in app: XCUIApplication, file: StaticString = #filePath,
                               line: UInt = #line) -> XCUIElement {
        let zen = app.buttons.matching(identifier: ID.gameZenControl).firstMatch
        XCTAssertTrue(pollUntil(timeout: 10) {
            zen.exists && !zen.frame.isEmpty && windowFrame(in: app).contains(zen.frame)
        }, "Expected Zen's control on screen", file: file, line: line)
        return zen
    }

    /// The form where the layout fixes it: the 96-point top-bar chip before
    /// Exit in a phone's portrait bar, and the circle beside Exit, at its
    /// top, in a full-size iPad window. Other layouts are only tapped.
    private func assertZenForm(of zen: XCUIElement, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        #if !targetEnvironment(macCatalyst)
        let exit = element(ID.gameZenExit, in: app, file: file, line: line)
        let window = windowFrame(in: app)
        let (control, exitFrame) = (zen.frame, exit.frame)
        attach("window \(window)\nzen \(control) label \(zen.label)\nexit \(exitFrame)", name: "Zen's control")
        guard !query("navigation.container.duo", in: app).exists else { return }
        if isPhone && window.height > window.width {
            XCTAssertEqual(control.width, 96, accuracy: 1, "The top bar's chip", file: file, line: line)
            XCTAssertEqual(control.height, 44, accuracy: 1, "The top bar's chip", file: file, line: line)
            XCTAssertLessThanOrEqual(control.maxX, exitFrame.minX + 1, "The chip comes before Exit",
                                     file: file, line: line)
            XCTAssertTrue(control.minY < exitFrame.maxY && exitFrame.minY < control.maxY, "The chip is in Exit's bar",
                          file: file, line: line)
        } else if !isPhone && min(window.width, window.height) >= 700 {
            XCTAssertLessThanOrEqual(control.maxX, exitFrame.minX + 1, "The circle is beside Exit",
                                     file: file, line: line)
            XCTAssertEqual(control.minY, exitFrame.minY, accuracy: 1, "The circle shares Exit's top",
                           file: file, line: line)
        }
        #endif
    }

    // MARK: Connection status

    private enum ClockPlace { case body, headerChip }

    /// A clock as one snapshot of the app read it.
    private struct ClockRead {
        let identifier: String
        let frame: CGRect
        let value: String
    }

    /// The clocks on screen whose VoiceOver value starts with the mark's
    /// words, from one snapshot: a query each would take longer than the
    /// two seconds a journey times.
    private func markedClocks(in app: XCUIApplication) -> [ClockRead] {
        guard let root = try? app.snapshot() else { return [] }
        let window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        var marked: [ClockRead] = []
        var pending = [root]
        while let node = pending.popLast() {
            if node.elementType == .button, [blackClock, whiteClock].contains(node.identifier),
               let value = node.value as? String, value.hasPrefix(reconnecting),
               node.frame.width > 1, node.frame.height > 1, window.intersects(node.frame) {
                marked.append(ClockRead(identifier: node.identifier, frame: node.frame, value: value))
            }
            pending.append(contentsOf: node.children)
        }
        return marked
    }

    /// The user's clock, which is to move, carries the mark: a body clock
    /// is taller than the bar's 44-point chips.
    private func assertTheMark(onA place: ClockPlace?, in mode: String, app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        var marked: [ClockRead] = []
        XCTAssertTrue(pollUntil(timeout: 10) {
            marked = markedClocks(in: app).filter { $0.identifier == whiteClock }
            return !marked.isEmpty
        }, "In \(mode) the to-move clock carries the mark", file: file, line: line)
        attach(marked.map { "\($0.identifier) \($0.frame) \($0.value)" }.joined(separator: "\n"),
               name: "Marked clocks in \(mode)")
        guard let place else { return }
        XCTAssertTrue(marked.contains { place == .body ? $0.frame.height > 50 : $0.frame.height <= 50 },
                      "In \(mode) the mark is on the \(place == .body ? "body clock" : "header's chip")",
                      file: file, line: line)
    }

    /// With no clock in play, one clock carries the mark.
    private func assertOneClockCarriesTheMark(in mode: String, app: XCUIApplication,
                                              file: StaticString = #filePath, line: UInt = #line) {
        var marked: [ClockRead] = []
        XCTAssertTrue(pollUntil(timeout: 10) {
            marked = markedClocks(in: app)
            return !marked.isEmpty
        }, "In \(mode) a clock carries the mark", file: file, line: line)
        attach(marked.map { "\($0.identifier) \($0.frame) \($0.value)" }.joined(separator: "\n"),
               name: "Marked clocks in \(mode)")
        XCTAssertEqual(Set(marked.map(\.identifier)).count, 1, "In \(mode) one clock carries the mark",
                       file: file, line: line)
    }

    private enum Mode: String { case analyze = "Analyze", chat = "Chat" }

    /// Opens or closes a mode's panel with a tap at the mode's centre in the
    /// bar, as the control is pressed: iOS 27 can report a bottom-bar item
    /// as not hittable under the hidden tab bar's accessibility frame.
    private func setMode(_ mode: Mode, on: Bool, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        let control = mode == .analyze ? gameAnalyzeControl(in: app) : gameChatControl(in: app)
        let panel = query(mode == .analyze ? ID.gameAnalyzeControlBar : ID.gameChatLog, in: app)
        guard panel.exists != on else { return }
        XCTAssertTrue(pollUntil(timeout: 10) {
            control.exists && !control.frame.isEmpty && windowFrame(in: app).contains(control.frame)
        }, "Expected \(mode.rawValue) in the bar", file: file, line: line)
        activate(control, at: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(pollUntil(timeout: 10) { panel.exists == on },
                      "\(mode.rawValue) \(on ? "opens" : "closes") from the bar", file: file, line: line)
    }

    private func assertNoCapsule(for seconds: TimeInterval, in mode: String, app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(pollUntil(timeout: seconds) { query(ID.gameConnectionStatus, in: app).exists },
                       "In \(mode) the title slot never shows the capsule", file: file, line: line)
    }

    // MARK: Helpers

    /// A pushed challenge card's own button, which has no identifier.
    private func cardButton(_ label: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier == ''", label))
        var shown: XCUIElement?
        XCTAssertTrue(pollUntil(timeout: 10) {
            shown = buttons.allElementsBoundByIndex.first { $0.isHittable }
            return shown != nil
        }, "The card shows \(label)", file: file, line: line)
        return shown ?? buttons.firstMatch
    }

    private func waitForLabel(_ label: String, of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: timeout) == .completed
    }

    /// Still there a second later: a dismissal would have begun by then.
    private func staysPresent(_ element: XCUIElement) -> Bool {
        element.exists && !pollUntil(timeout: 1) { !element.exists }
    }

    /// The same frame on two reads in a row: a popover has stopped moving.
    private func waitForSettledFrame(of element: XCUIElement) -> Bool {
        var previous: CGRect?
        return pollUntil(timeout: 10) {
            let frame = element.exists ? element.frame : nil
            defer { previous = frame }
            return frame != nil && frame == previous
        }
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
