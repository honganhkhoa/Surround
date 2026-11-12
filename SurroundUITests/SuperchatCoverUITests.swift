//
//  SuperchatCoverUITests.swift
//  SurroundUITests
//
//  The moderator superchat cover's offline journeys. `--surround-activity-state
//  superchat` starts covered, and the Debug commands, posted through the
//  Darwin notify center, start and end other superchats (TESTING.md). The
//  fixture starts its superchat once per launch, so a journey that needs it
//  again relaunches. XCTest still lists the elements under the cover, so the
//  journeys check that they aren't hittable and that a tap where they sit
//  changes nothing.
//

import XCTest
import UIKit

#if DEBUG
final class SuperchatCoverUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias FixtureID = SurroundUITestContract.ActivityFixtureID

    private let fixtureGameID = SurroundUITestContract.fixtureGameID
    private let harborMistGameID = SurroundUITestContract.ActivityFixtureID.harborMistGameID
    private let moderatorMessage = "Hello, I'm a moderator. Please reply here before you play on."
    private let title = "Moderator chat"
    private let subtitle = "Surround is locked until the moderator ends this chat. You can read and reply."
    private let ended = "The moderator ended this chat."
    private let reconnecting = "Reconnecting…"

    // MARK: Journeys

    func testTheCoverRisesAtLaunchAndBlocksTheApp() {
        let app = launchCovered()
        let cover = element(ID.superchatCover, in: app)
        let message = cover.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", moderatorMessage)).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "The cover shows the moderator's message")
        XCTAssertEqual(element(ID.superchatCoverTitle, in: app).label, title)
        XCTAssertEqual(element(ID.superchatCoverSubtitle, in: app).label, subtitle)
        assertLiveGame(harborMistGameID, opponent: "HarborMist", turn: "Your move", in: app)
        assertLiveGame(fixtureGameID, opponent: "OrbitFox", turn: "Their move", in: app)
        keepScreenshot("Cover at launch", in: app)

        assertCovered([ID.screenHome, ID.homeGame(fixtureGameID), ID.homeGame(harborMistGameID)], in: app)
        tap(at: query(ID.homeGame(fixtureGameID), in: app).frame, in: app)
        XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.gameDetail(self.fixtureGameID), in: app).exists },
                       "A tap where Home's game sits opens nothing under the cover")
        XCTAssertTrue(cover.exists, "The tap leaves the cover up")
    }

    func testDoneAfterTheEndLowersTheCoverAndKeepsTheChatInMessages() throws {
        try skipOnTheMac()
        let app = launchCovered()
        let cover = element(ID.superchatCover, in: app)
        post(.end)
        XCTAssertEqual(element(ID.superchatCoverEnded, in: app).label, ended)
        let done = element(ID.superchatCoverDone, in: app, matching: .button)
        keepScreenshot("The end card with Done", in: app)
        tap(done, description: "Done on the end card", in: app)
        XCTAssertTrue(waitForAbsence(cover, timeout: stateSettleTimeout), "Done lowers the cover")
        XCTAssertTrue(waitUntilHittable(query(ID.homeGame(fixtureGameID), in: app), timeout: stateSettleTimeout),
                      "Home is usable once the cover is down")

        openModeratorConversation(in: app)
        XCTAssertEqual(element(ID.messagesSuperchatEnded, in: app).label, ended,
                       "Messages › WardenKestrel says the chat ended")
        keepScreenshot("Messages › WardenKestrel after Done", in: app)
    }

    func testTheLatestLinkWaitsForDone() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iOS only: it hands links over through the iOS system; on the Mac, links are checked by hand.")
        #else
        let app = launchCovered()
        let cover = element(ID.superchatCover, in: app)
        for gameID in [fixtureGameID, harborMistGameID] {
            openLink(URL(string: "surround://home/\(gameID)")!)
            XCTAssertTrue(cover.waitForExistence(timeout: 10), "The cover stays over link \(gameID)")
            XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.gameDetail(gameID), in: app).exists },
                           "Link \(gameID) waits while covered")
            XCTAssertTrue(waitUntilNotHittable(query(ID.homeGame(fixtureGameID), in: app), timeout: 10),
                          "Home stays covered after link \(gameID)")
        }
        keepScreenshot("Two links held under the cover", in: app)
        endAndDone(in: app)
        // AppRouteTests proves that the first link never ran: every route
        // clears what earlier ones left, so the screen can't tell.
        element(ID.gameDetail(harborMistGameID), in: app)
        keepScreenshot("The latest link's game after Done", in: app)
        #endif
    }

    func testOfflineTheCoverStaysWithReconnecting() {
        // The offline root's network path is always satisfied, so
        // "Reconnecting…" shows 2 s after the rise (ConnectionStatusModel).
        var app = launchCovered([SurroundUITestContract.activityConnectionLaunchArgument,
                                 SurroundUITestContract.ActivityFixtureConnection.offline.rawValue])
        let launched = Date()
        let status = element(ID.superchatCoverStatus, in: app)
        let reveal = Date().timeIntervalSince(launched)
        XCTAssertEqual(status.label, reconnecting)
        let reply = element(ID.superchatCoverReply, in: app, matching: .textField)
        let send = element(ID.superchatCoverSend, in: app, matching: .button)
        XCTAssertTrue(waitUntilDisabled(reply), "Offline, the reply field is off")
        XCTAssertTrue(waitForValue(reconnecting, in: reply, timeout: stateSettleTimeout),
                      "Offline, the reply field reads Reconnecting…")
        // Send is off in every offline UI test (no remote activity), so only
        // its value tells; PrivateMessageComposerStateTests checks the rule.
        XCTAssertFalse(send.isEnabled, "Offline, Send is off")
        XCTAssertTrue(waitForValue(reconnecting, in: send, timeout: stateSettleTimeout),
                      "Offline, Send reads Reconnecting…")
        keepScreenshot("Offline cover reconnecting", in: app)
        app.terminate()

        // The same run without the flag: past the reveal, nothing reads Reconnecting….
        app = launchCovered()
        Thread.sleep(forTimeInterval: max(reveal, 2) + 2)
        XCTAssertFalse(query(ID.superchatCoverStatus, in: app).exists, "Online, the cover shows no Reconnecting…")
        let onlineReply = element(ID.superchatCoverReply, in: app, matching: .textField)
        let onlineSend = element(ID.superchatCoverSend, in: app, matching: .button)
        XCTAssertNotEqual(onlineReply.value as? String, reconnecting, "Online, the reply field doesn't read Reconnecting…")
        XCTAssertNotEqual(onlineSend.value as? String, reconnecting, "Online, Send doesn't read Reconnecting…")
        XCTAssertTrue(onlineReply.isEnabled, "Online, the reply field is on")
        keepScreenshot("Online cover, the same run", in: app)
    }

    func testAReconnectWithoutAResendLiftsTheCover() throws {
        try skipOnTheMac()
        let app = launchCovered()
        let cover = element(ID.superchatCover, in: app)
        let done = query(ID.superchatCoverDone, in: app)
        let posted = Date()
        post(.reconnect)
        var offeredDone = false
        let lifted = pollUntil(timeout: 15) {
            if done.exists { offeredDone = true }
            return !cover.exists
        }
        let seconds = Date().timeIntervalSince(posted)
        attach("The cover lifted \(String(format: "%.1f", seconds)) s after the reconnect", name: "Lift timing")
        XCTAssertTrue(lifted, "Within 15 s of a reconnect without a re-send, the cover is gone")
        XCTAssertFalse(offeredDone, "A missed end lifts the cover without Done")
        XCTAssertGreaterThanOrEqual(seconds, 8, "The cover waits out the 10 s re-send window first")

        openModeratorConversation(in: app)
        XCTAssertEqual(element(ID.messagesSuperchatEnded, in: app).label, ended,
                       "Messages › WardenKestrel says the chat ended")
        keepScreenshot("Messages › WardenKestrel after a lift", in: app)
    }

    func testSeveralModeratorsNewestFirst() throws {
        try skipOnTheMac()
        let app = launchCovered()
        let cover = element(ID.superchatCover, in: app)
        post(.startSecond)
        let sentinelID = ID.superchatCoverModerator(FixtureID.secondModeratorID)
        let wardenID = ID.superchatCoverModerator(FixtureID.moderatorID)
        let sentinel = element(sentinelID, in: app, matching: .button)
        let warden = element(wardenID, in: app, matching: .button)
        assertSelected(sentinelID, in: app)
        assertNotSelected(wardenID, in: app)
        XCTAssertLessThan(sentinel.frame.minX, warden.frame.minX, "The newest moderator's chip comes first")
        keepScreenshot("Two moderators, SentinelHeron selected", in: app)

        post(.endSecond)
        XCTAssertTrue(waitForValue(ended, in: sentinel, timeout: stateSettleTimeout),
                      "SentinelHeron's chip says the chat ended")
        XCTAssertTrue(cover.exists, "WardenKestrel is still on, so the cover stays")
        element(ID.superchatCoverEnded, in: app)
        XCTAssertFalse(query(ID.superchatCoverDone, in: app).exists, "No Done while WardenKestrel is still on")
        keepScreenshot("SentinelHeron ended, WardenKestrel still on", in: app)

        post(.end)
        element(ID.superchatCoverDone, in: app, matching: .button)
        keepScreenshot("Both ended: Done", in: app)
    }

    func testTheModeratorsEchoNeverCovers() throws {
        try skipOnTheMac()
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.activityStateLaunchArgument,
            SurroundUITestContract.ActivityFixtureState.liveYourMove.rawValue,
        ], orientation: preferredOrientation)
        element(ID.screenHome, in: app)
        let game = element(ID.homeGame(harborMistGameID), in: app, matching: .button)
        let cover = query(ID.superchatCover, in: app)
        post(.echo)
        XCTAssertFalse(pollUntil(timeout: 3) { cover.exists }, "The moderator's own echo never covers")
        XCTAssertTrue(waitUntilHittable(game, timeout: stateSettleTimeout), "Home stays usable after the echo")
        keepScreenshot("Home after the echo", in: app)

        // The commands reach this run: a start covers, and the echo left no
        // moderator behind, so there are no chips.
        post(.start)
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "A start after the echo covers")
        let chipPrefix = String(ID.superchatCoverModerator(0).dropLast())
        XCTAssertEqual(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", chipPrefix)).count, 0,
                       "One moderator, no chips: the echo added none")
    }

    func testLargestTextLandscapeFits() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iOS only: it turns the device.")
        #else
        // Offline, so the header also holds Reconnecting…: its tallest form.
        let app = launchCovered(["-UIPreferredContentSizeCategoryName",
                                 UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                                 SurroundUITestContract.activityConnectionLaunchArgument,
                                 SurroundUITestContract.ActivityFixtureConnection.offline.rawValue],
                                orientation: .landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.width > app.frame.height }, "The app turns to landscape")
        element(ID.superchatCoverStatus, in: app)
        assertCoverFits("landscape", in: app)
        // The end card, in both orientations: beside a long line, Done's label
        // would break inside the word.
        post(.end)
        assertEndCardFits("landscape", in: app)
        // On a phone, landscape gives two columns; portrait is the one column
        // where the header's 40% cap applies.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pollUntil(timeout: 10) { app.frame.height > app.frame.width }, "The app turns to portrait")
        assertCoverFits("portrait", in: app)
        assertEndCardFits("portrait", in: app)
        #endif
    }

    func testAHeldGameOpensAtFullBoardSizeOnIPad() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iPad only: the Mac has no hidden sidebar.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only: the hidden sidebar's full-size board.")
        let app = launchApp()
        element(ID.screenHome, in: app)
        let settingsRow = app.cells.matching(identifier: ID.navigationSettings).firstMatch
        XCTAssertTrue(waitUntilHittable(settingsRow, timeout: 10), "Landscape opens with the sidebar shown")
        guard let hide = nativeSidebarToggle(in: app) else { return XCTFail("Expected the sidebar's own toggle") }
        tap(hide, description: "Fold the sidebar into the top tab bar", in: app)
        // As testIPadLandscapeSidebarChoiceSurvivesGames checks it: a hidden
        // sidebar's row can also leave the tree.
        let folded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: settingsRow)
        XCTAssertEqual(waitWithFinalCheck(for: [folded], timeout: 10), .completed, "The sidebar is hidden")

        tap(ID.homeGamePlayerInfo(fixtureGameID), in: app)
        element(ID.gameDetail(fixtureGameID), in: app)
        let plainWidth = try XCTUnwrap(settledBoardWidth(in: app), "A plain open measures the board")
        keepScreenshot("Plain open, sidebar hidden", in: app)
        returnToActiveGames(in: app)

        for lift in ["Done", "a lift"] {
            post(.start)
            let cover = element(ID.superchatCover, in: app)
            openLink(URL(string: "surround://home/\(fixtureGameID)")!)
            XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.gameDetail(self.fixtureGameID), in: app).exists },
                           "The game's link waits while covered")
            XCTAssertTrue(cover.exists, "The cover stays over the link")
            if lift == "Done" {
                endAndDone(in: app)
            } else {
                post(.reconnect)
                XCTAssertTrue(waitForAbsence(cover, timeout: 15), "A reconnect without a re-send lifts the cover")
            }
            element(ID.gameDetail(fixtureGameID), in: app)
            let width = try XCTUnwrap(settledBoardWidth(in: app), "The replayed game's board settles")
            keepScreenshot("Held game replayed by \(lift)", in: app)
            XCTAssertEqual(width, plainWidth, accuracy: 1,
                           "The game replayed by \(lift) opens at the plain open's board width")
            // A hidden sidebar's row can also leave the tree.
            XCTAssertFalse(settingsRow.exists && settingsRow.isHittable, "The sidebar stays hidden")
            returnToActiveGames(in: app)
        }
        #endif
    }

    // MARK: Presentations under the cover

    func testTheCoverHidesASheet() throws {
        try skipUnlessPresentations()
        let app = launchPlain()
        tap(ID.homeNewGame, in: app, matching: .button)
        let newGame = element(ID.screenNewGame, in: app)
        let close = element(ID.newGameClose, in: app, matching: .button)
        assertCoverHides("sheet (Home › New game)", target: close, in: app) { newGame.exists }
    }

    func testTheCoverHidesAPopover() throws {
        try skipUnlessPresentations()
        let gameIDs = SurroundUITestContract.liveBannerCorrespondenceGameIDs
        let app = launchPlain([SurroundUITestContract.liveGameBannerNavigationLaunchArgument])

        // Home › Appearance; a tap on the other display mode would change it.
        let appearance = app.navigationBars.buttons.matching(identifier: ID.homeAppearance).firstMatch
        tap(appearance, description: "Open Appearance", in: app)
        let mode = element(ID.homeDisplayMode, in: app, matching: .segmentedControl)
        func selectedMode() -> String? {
            mode.buttons.allElementsBoundByIndex.first(where: \.isSelected)?.label
        }
        let selected = try XCTUnwrap(selectedMode(), "One display mode is selected")
        let other = mode.buttons[selected == "Compact" ? "Large" : "Compact"].firstMatch
        let popover = app.popovers.firstMatch
        assertCoverHides("popover (Home › Appearance)", target: other, in: app) {
            popover.exists && selectedMode() == selected
        }
        dismissPopover(in: app)

        // Game Detail's Active games; a tap on the other game would switch to it.
        let firstGame = elementAfterScrolling(ID.homeGame(gameIDs[0]), in: app)
        scrollIntoTappableArea(firstGame, in: app)
        tap(firstGame, description: "Open the first correspondence game", in: app)
        let detail = element(ID.gameDetail(gameIDs[0]), in: app)
        openActiveGames(in: app)
        let activeGames = element(ID.gameActiveGamesPopover, in: app)
        let otherGame = activeGames.descendants(matching: .button)
            .matching(identifier: ID.gameActiveGamesEntry(gameIDs[1])).firstMatch
        assertCoverHides("popover (Game Detail › Active games)", target: otherGame, in: app) {
            activeGames.exists && detail.exists
        }
    }

    func testTheCoverHidesAnAlert() throws {
        try skipUnlessPresentations()
        let app = launchPlain()
        tap(ID.homeGamePlayerInfo(fixtureGameID), in: app)
        element(ID.gameDetail(fixtureGameID), in: app)
        tap(ID.gameActionsMenu, in: app)
        tap(requiredMenuButton(ID.gameResign, title: "Resign", in: app), description: "Resign", in: app)
        let alert = app.alerts["Are you sure you want to resign this game?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Resign asks first")
        // A tap on Dismiss would close it; Resign is never touched.
        assertCoverHides("alert (Resign)", target: alert.buttons["Dismiss"].firstMatch, in: app) { alert.exists }
    }

    func testTheCoverHidesAConfirmationDialog() throws {
        try skipUnlessPresentations()
        let app = launchPlain([SurroundUITestContract.friendshipLaunchArgument])
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let reject = element(ID.friendRequestReject(playerID), in: app, matching: .button)
        scrollIntoTappableArea(reject, in: app)
        tap(reject, description: "Review the rejection choices", in: app)
        let notify = requiredMenuButton(ID.friendshipRejectNotify, title: "Reject and Let Them Know", in: app)
        let quietly = requiredMenuButton(ID.friendshipRejectQuietly, title: "Reject Quietly", in: app)
        // A tap on Reject Quietly would answer the request and close the dialog.
        assertCoverHides("confirmation dialog (Reject)", target: quietly, in: app) {
            notify.exists && reject.exists
        }
    }

    func testTheCoverHidesAContextMenu() throws {
        try skipUnlessPresentations()
        let app = launchPlain()
        let row = element(ID.homeGame(fixtureGameID), in: app, matching: .button)
        // Black in the bundled game-26268404.json, shown as OrbitFox.
        let opponentID = 797_416
        let viewProfile = openProfileContextMenu(
            for: row, expecting: ID.profileGameMenuEntry(fixtureGameID, opponentID), in: app)
        let profile = query(ID.screenPlayerProfile, in: app)
        // A tap on View Profile would open OrbitFox's profile.
        assertCoverHides("context menu (Home game row)", target: viewProfile, in: app) {
            viewProfile.exists && !profile.exists
        }
    }

    func testTheCoverHidesAShareSheet() throws {
        try skipUnlessPresentations()
        let app = launchPlain()
        openOwnProfileFromMainNavigation(in: app)
        tap(ID.profileShare, in: app)
        // A tap on Copy would copy the link and close the sheet.
        let copy = shareSheetCopy(in: app)
        // The sheet's rows sit in its remote container, which hit-tests in
        // its own process: on iOS 18.6 XCTest calls Copy hittable under the
        // cover, as it does the Safari view's buttons.
        assertCoverHides("share sheet (Share profile)", target: copy, in: app,
                         hitTestedElsewhere: true) { copy.exists }
    }

    func testTheCoverHidesASafariView() throws {
        try skipUnlessPresentations()
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iOS only: Catalyst opens biography links in Safari.")
        #else
        let server = try ProfileBiographyBrowserServer()
        addTeardownBlock { server.stop() }
        let url = try server.start()
        let app = launchPlain([SurroundUITestContract.profileBiographyLaunchArgument],
                              environment: ["SURROUND_UI_BIOGRAPHY_BROWSER_URL": url.absoluteString])
        openOwnProfileFromMainNavigation(in: app)
        tap(reveal(query(ID.profileAbout, in: app),
                   scrolling: app.scrollViews[ID.screenPlayerProfile].firstMatch, in: app),
            description: "Read the full biography", in: app)
        element(ID.screenPlayerAbout, in: app)
        let web = element(ID.profileBiographyContent, in: app, matching: .webView)
        tap(reveal(web.links["Open local biography page"].firstMatch, scrolling: web, in: app),
            description: "Open the test's loopback page in a Safari view", in: app)
        _ = try server.waitForRequest()
        let page = app.webViews.staticTexts[ProfileBiographyBrowserServer.pageMarker].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "The Safari view shows the loopback page")
        // A tap on its Done or Close would close it. Bound by index: on an
        // iPad the profile's own sheet has a Done of its own underneath.
        let closes = app.buttons.matching(NSPredicate(
            format: "label IN %@ AND identifier != %@", ["Close", "Done"], ID.superchatCoverDone))
        var close: XCUIElement?
        XCTAssertTrue(pollUntil(timeout: 30) {
            close = closes.allElementsBoundByIndex.first(where: \.isHittable)
            return close != nil
        }, "The Safari view shows its own Done or Close")
        guard let close else { return }
        assertCoverHides("Safari view (biography link)", target: close, in: app,
                         hitTestedElsewhere: true) { page.exists }
        #endif
    }

    // MARK: Launching

    /// Portrait on a phone, landscape on an iPad (ignored on the Mac).
    private var preferredOrientation: UIDeviceOrientation {
        UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft
    }

    /// The superchat state, covered from the first frame.
    private func launchCovered(_ arguments: [String] = [], orientation: UIDeviceOrientation? = nil,
                               file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.activityStateLaunchArgument,
            SurroundUITestContract.ActivityFixtureState.superchat.rawValue,
        ] + arguments, orientation: orientation ?? preferredOrientation)
        element(ID.superchatCover, in: app, file: file, line: line)
        return app
    }

    /// The plain offline journey, whose service hears the Debug commands.
    private func launchPlain(_ arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: arguments, launchEnvironment: environment,
                            orientation: preferredOrientation)
        element(ID.screenHome, in: app)
        return app
    }

    /// The journeys that post Debug commands run on iOS. On the Mac, where
    /// Darwin commands also reach the sandboxed app, they are checked by
    /// hand.
    private func skipOnTheMac() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("iOS only: on the Mac, the Debug-command journeys are checked by hand.")
        #endif
    }

    /// Off unless asked for: CI's iPad lane would run them, and the share
    /// sheet and Safari view are system UI a hosted simulator may draw
    /// differently.
    private func skipUnlessPresentations() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SURROUND_UI_SUPERCHAT_PRESENTATIONS"] == "1",
                          "Set TEST_RUNNER_SURROUND_UI_SUPERCHAT_PRESENTATIONS=1 to raise the cover over presentations.")
        try skipOnTheMac()
    }

    // MARK: The cover

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// `.end`, then Done on the end card; waits for the cover to go.
    private func endAndDone(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let cover = query(ID.superchatCover, in: app)
        post(.end)
        tap(element(ID.superchatCoverDone, in: app, matching: .button, file: file, line: line),
            description: "Done on the end card", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(cover, timeout: stateSettleTimeout), "Done lowers the cover", file: file, line: line)
    }

    private func assertLiveGame(_ gameID: Int, opponent: String, turn: String, in app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        let row = element(ID.superchatCoverLiveGame(gameID), in: app, file: file, line: line)
        XCTAssertTrue(row.label.contains(opponent) && row.label.contains(turn),
                      "The cover lists the live game with \(opponent), \(turn): \(row.label)", file: file, line: line)
    }

    /// Elements XCTest still lists under the cover, none of which a tap reaches.
    private func assertCovered(_ identifiers: [String], in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        for identifier in identifiers {
            XCTAssertTrue(waitUntilNotHittable(query(identifier, in: app), timeout: 10),
                          "\(identifier) is listed under the cover and isn't hittable", file: file, line: line)
        }
    }

    /// Messages › WardenKestrel, whose composer shows Messages' ended line.
    private func openModeratorConversation(in app: XCUIApplication,
                                           file: StaticString = #filePath, line: UInt = #line) {
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app, file: file, line: line)
        tap(element(ID.privateMessageRow(FixtureID.moderatorID), in: app, matching: .button, file: file, line: line),
            description: "WardenKestrel's conversation", in: app, file: file, line: line)
    }

    /// Raises the cover over an open presentation and records its
    /// verdict: covered, its element takes no tap, and after the end and Done
    /// it is still there and usable. `unchanged` says the presentation is as
    /// it was. `hitTestedElsewhere`: the element lives in another process
    /// (the Safari view's, or a share sheet's remote rows), whose hit test
    /// can't see the cover, so XCTest may report it hittable underneath.
    /// There the verdict keeps XCTest's answer, and the tap at its frame is
    /// the input check.
    private func assertCoverHides(_ kind: String, target: XCUIElement, in app: XCUIApplication,
                                  hitTestedElsewhere: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  unchanged: @escaping () -> Bool) {
        XCTAssertTrue(waitUntilHittable(target, timeout: stateSettleTimeout),
                      "The \(kind) is open and usable before the cover", file: file, line: line)
        let frame = target.frame
        keepScreenshot("\(kind) – open", in: app)
        let cover = query(ID.superchatCover, in: app)
        var verdict = PresentationVerdict(kind: kind, hitTestedElsewhere: hitTestedElsewhere)
        post(.start)
        verdict.covered = cover.waitForExistence(timeout: 10)
        if verdict.covered {
            verdict.listedUnderneath = target.exists
            verdict.notHittable = waitUntilNotHittable(target, timeout: 10)
            keepScreenshot("\(kind) – covered", in: app)
            tap(at: frame, in: app)
            verdict.tapChangedNothing = !pollUntil(timeout: 3) { !unchanged() } && cover.exists
            keepScreenshot("\(kind) – covered, after a tap at its element", in: app)
            post(.end)
            let done = query(ID.superchatCoverDone, in: app)
            if done.waitForExistence(timeout: 10), waitUntilHittable(done, timeout: stateSettleTimeout) {
                activate(done)
                verdict.lowered = waitForAbsence(cover, timeout: stateSettleTimeout)
            }
            if verdict.lowered {
                verdict.stillThereAfterDone = waitUntilHittable(target, timeout: stateSettleTimeout) && unchanged()
                keepScreenshot("\(kind) – after Done", in: app)
            }
        }
        attach(verdict.description, name: "Presentation verdict – \(kind)")
        FileHandle.standardOutput.write(Data("[SuperchatCoverVerdict] \(verdict)\n".utf8))
        if !verdict.passes {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – \(kind)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(verdict.covered, "The cover rises over the \(kind)", file: file, line: line)
        XCTAssertTrue(verdict.listedUnderneath, "The \(kind) stays under the cover", file: file, line: line)
        if !hitTestedElsewhere {
            XCTAssertTrue(verdict.notHittable, "The \(kind)'s element isn't hittable under the cover",
                          file: file, line: line)
        }
        XCTAssertTrue(verdict.tapChangedNothing, "A tap at the \(kind)'s element changes nothing", file: file, line: line)
        XCTAssertTrue(verdict.lowered, "Done lowers the cover over the \(kind)", file: file, line: line)
        XCTAssertTrue(verdict.stillThereAfterDone, "The \(kind) is still there and usable after Done",
                      file: file, line: line)
    }

    private struct PresentationVerdict: CustomStringConvertible {
        let kind: String
        let hitTestedElsewhere: Bool
        var covered = false
        var listedUnderneath = false
        var notHittable = false
        var tapChangedNothing = false
        var lowered = false
        var stillThereAfterDone = false

        var passes: Bool {
            covered && listedUnderneath && (notHittable || hitTestedElsewhere) && tapChangedNothing && lowered
                && stillThereAfterDone
        }

        var description: String {
            "\(kind): covered=\(covered) listedUnderneath=\(listedUnderneath) notHittable=\(notHittable)"
                + (hitTestedElsewhere ? " (hit-tested in its own process; not asserted)" : "")
                + " tapChangedNothing=\(tapChangedNothing) lowered=\(lowered) stillThereAfterDone=\(stillThereAfterDone)"
        }
    }

    // MARK: Fit at the largest text size

    private struct CoverFrames: Equatable {
        var cover, title, subtitle, conversation: CGRect
        /// The reply field and Send.
        var replyRow: CGRect
        /// The header's own scroll view, where it has one.
        var headerScroll: CGRect?
        /// Where the header's content starts in its scroll view, unscrolled:
        /// the top of the safe area the cover lays out in.
        var safeAreaTop: CGFloat?
        /// Reconnecting…, offline.
        var status: CGRect?
    }

    /// One snapshot, so every frame comes from the same layout.
    private func coverFrames(in app: XCUIApplication) -> CoverFrames? {
        guard let root = try? app.snapshot() else { return nil }
        func flattened(_ start: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            var nodes = [XCUIElementSnapshot]()
            var pending = [start]
            while let node = pending.popLast() {
                nodes.append(node)
                pending.append(contentsOf: node.children)
            }
            return nodes
        }
        let all = flattened(root)
        guard let cover = all.first(where: { $0.identifier == ID.superchatCover }) else { return nil }
        let nodes = flattened(cover)
        func frame(where matches: (XCUIElementSnapshot) -> Bool) -> CGRect? { nodes.first(where: matches)?.frame }
        // By identifier, so a fit run in another language measures the same texts.
        guard let titleFrame = frame(where: { $0.identifier == ID.superchatCoverTitle }),
              let subtitleFrame = frame(where: { $0.identifier == ID.superchatCoverSubtitle }),
              let conversation = frame(where: { $0.identifier == ID.profileConversation }),
              let reply = frame(where: { $0.identifier == ID.superchatCoverReply }),
              let send = frame(where: { $0.identifier == ID.superchatCoverSend }) else { return nil }
        let titleCenter = CGPoint(x: titleFrame.midX, y: titleFrame.midY)
        let headerScroll = frame { node in
            node.elementType == .scrollView && node.identifier != ID.profileConversation
                && node.frame.contains(titleCenter)
        }
        let headerContent = frame { node in
            node.children.contains { $0.identifier == ID.superchatCoverTitle }
        }
        return CoverFrames(cover: cover.frame, title: titleFrame, subtitle: subtitleFrame, conversation: conversation,
                           replyRow: reply.union(send), headerScroll: headerScroll,
                           safeAreaTop: headerScroll == nil ? nil : headerContent?.minY,
                           status: frame { $0.identifier == ID.superchatCoverStatus })
    }

    /// Frames for these identifiers inside the cover, from one snapshot;
    /// nil until every one is there.
    private func coverFrames(_ identifiers: [String], in app: XCUIApplication) -> [String: CGRect]? {
        guard let root = try? app.snapshot() else { return nil }
        var pending: [XCUIElementSnapshot] = [root]
        var cover: XCUIElementSnapshot?
        while cover == nil, let node = pending.popLast() {
            if node.identifier == ID.superchatCover { cover = node }
            pending.append(contentsOf: node.children)
        }
        guard let cover else { return nil }
        var frames = [String: CGRect]()
        pending = [cover]
        while let node = pending.popLast() {
            if identifiers.contains(node.identifier), frames[node.identifier] == nil {
                frames[node.identifier] = node.frame
            }
            pending.append(contentsOf: node.children)
        }
        return frames.count == identifiers.count ? frames : nil
    }

    /// After `.end`, at the largest text size: Done sits under the end card's
    /// line, the card starts inside the conversation, and the reply row ends
    /// on screen, so Done can be reached in either orientation.
    private func assertEndCardFits(_ context: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let done = element(ID.superchatCoverDone, in: app, matching: .button, file: file, line: line)
        let identifiers = [ID.superchatCover, ID.profileConversation, ID.superchatCoverEnded,
                           ID.superchatCoverDone, ID.superchatCoverReply]
        var previous: [String: CGRect]?
        var settled: [String: CGRect]?
        _ = pollUntil(timeout: stateSettleTimeout) {
            let frames = coverFrames(identifiers, in: app)
            defer { previous = frames }
            if let frames, frames == previous { settled = frames }
            return settled != nil
        }
        keepScreenshot("Largest text, the end card, \(context)", in: app)
        guard let frames = settled, let cover = frames[ID.superchatCover],
              let conversation = frames[ID.profileConversation], let ended = frames[ID.superchatCoverEnded],
              let doneFrame = frames[ID.superchatCoverDone], let reply = frames[ID.superchatCoverReply] else {
            attach(app.debugDescription, name: "Accessibility hierarchy – the end card, \(context)")
            return XCTFail("\(context): the end card's frames settle", file: file, line: line)
        }
        attach("""
            \(context)
            cover \(cover)
            conversation \(conversation)
            ended line \(ended)
            Done \(doneFrame)
            reply field \(reply)
            """, name: "End card frames, \(context)")
        XCTAssertGreaterThanOrEqual(doneFrame.minY, ended.maxY - 1, "\(context): Done sits under the line",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(ended.minY, conversation.minY - 1,
                                    "\(context): the end card starts inside the conversation", file: file, line: line)
        XCTAssertLessThanOrEqual(reply.maxY, cover.maxY + 1, "\(context): the reply row ends on screen",
                                 file: file, line: line)
        XCTAssertTrue(done.isHittable, "\(context): Done can be tapped", file: file, line: line)
    }

    /// By frames, because XCUITest can't see truncation. One column: the
    /// header takes at most 40% of the cover's height (plus 1 pt) and the
    /// conversation is taller. Two columns: the header's pane leads and the
    /// conversation keeps the cover's full height beside it. Either way the
    /// subtitle stays within the header's width and wraps to at least twice
    /// the title's height.
    ///
    /// XCTest reports the cover's frame as the whole window, and its scroll
    /// views reaching into the safe area, while the cover lays out in the
    /// safe area. So one column's heights are measured from the safe area's
    /// top (where the header's scrolling content starts) to the composer's
    /// bottom, 10 pt below the reply row (PrivateMessageComposer's padding).
    private func assertCoverFits(_ context: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        var previous: CoverFrames?
        var settled: CoverFrames?
        _ = pollUntil(timeout: stateSettleTimeout) {
            let frames = coverFrames(in: app)
            defer { previous = frames }
            if let frames, frames == previous { settled = frames }
            return settled != nil
        }
        keepScreenshot("Largest text, \(context)", in: app)
        guard let frames = settled else {
            attach(app.debugDescription, name: "Accessibility hierarchy – largest text, \(context)")
            return XCTFail("The cover's frames settle in \(context)", file: file, line: line)
        }
        let cover = frames.cover, conversation = frames.conversation
        let usesColumns = conversation.minX > cover.minX + 1
        let header = frames.headerScroll ?? (usesColumns
            ? CGRect(x: cover.minX, y: cover.minY, width: conversation.minX - cover.minX, height: cover.height)
            : CGRect(x: cover.minX, y: cover.minY, width: cover.width, height: conversation.minY - cover.minY))
        // One column, in the safe area: from its top to the composer's bottom.
        let top = frames.safeAreaTop ?? cover.minY
        let bottom = frames.replyRow.maxY + 10
        let headerHeight = conversation.minY - top
        let contentHeight = bottom - top
        attach("""
            \(context), \(usesColumns ? "two columns" : "one column")
            cover \(cover)
            header \(header) (own scroll view: \(frames.headerScroll != nil))
            title \(frames.title)
            Reconnecting… \(frames.status.map { "\($0)" } ?? "not shown")
            subtitle \(frames.subtitle)
            conversation \(conversation)
            reply row \(frames.replyRow)
            """ + (usesColumns ? "" : """

            safe area from \(top) to the composer's bottom \(bottom): header \(headerHeight) of \(contentHeight) \
            (cap \(contentHeight * 0.4)), conversation \(bottom - conversation.minY)
            """), name: "Largest text frames, \(context)")
        if usesColumns {
            XCTAssertLessThanOrEqual(header.maxX, conversation.minX + 1,
                                     "\(context): the header's pane leads the conversation", file: file, line: line)
            XCTAssertGreaterThanOrEqual(cover.maxY - conversation.minY, cover.height - 1,
                                        "\(context): the conversation keeps the cover's full height",
                                        file: file, line: line)
        } else {
            if frames.safeAreaTop == nil {
                attach(app.debugDescription, name: "Accessibility hierarchy – largest text, \(context)")
            }
            XCTAssertNotNil(frames.safeAreaTop, "\(context): the header scrolls inside its cap at the largest text size",
                            file: file, line: line)
            XCTAssertLessThanOrEqual(headerHeight, contentHeight * 0.4 + 1,
                                     "\(context): the header takes at most 40% of the cover", file: file, line: line)
            XCTAssertGreaterThan(bottom - conversation.minY, headerHeight,
                                 "\(context): the conversation is taller than the header", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(frames.subtitle.minX, header.minX - 1,
                                    "\(context): the subtitle starts within the header", file: file, line: line)
        XCTAssertLessThanOrEqual(frames.subtitle.maxX, header.maxX + 1,
                                 "\(context): the subtitle ends within the header", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frames.subtitle.height, frames.title.height * 2,
                                    "\(context): the subtitle wraps instead of truncating", file: file, line: line)
        // The journey runs offline, so Reconnecting… is part of the header.
        XCTAssertNotNil(frames.status, "\(context): offline, the header shows Reconnecting…", file: file, line: line)
        if let status = frames.status {
            // Beside the title at this size, both would break inside a word.
            XCTAssertGreaterThanOrEqual(status.minY, frames.title.maxY - 1,
                                        "\(context): Reconnecting… sits under the title", file: file, line: line)
            XCTAssertLessThanOrEqual(status.maxX, header.maxX + 1,
                                     "\(context): Reconnecting… stays within the header", file: file, line: line)
        }
    }

    // MARK: Helpers

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return waitWithFinalCheck(for: [gone], timeout: timeout) == .completed
    }

    /// Still listed, but a tap there reaches something else: the cover.
    private func waitUntilNotHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let covered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == false"), object: element)
        return waitWithFinalCheck(for: [covered], timeout: timeout) == .completed
    }

    /// Listed and disabled: a field that went away doesn't count.
    private func waitUntilDisabled(_ element: XCUIElement) -> Bool {
        let off = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == false"), object: element)
        return waitWithFinalCheck(for: [off], timeout: stateSettleTimeout) == .completed
    }

    #if !targetEnvironment(macCatalyst)
    /// Hands a link to the running app, as a tap on it elsewhere would.
    /// `XCUIApplication.open(_:)` terminates the app and launches it again with
    /// the link, so the link would land in a fresh process.
    private func openLink(_ url: URL) {
        XCUIDevice.shared.system.open(url)
    }
    #endif

    /// A tap at a frame's center, by position, so it reaches whatever is on top there.
    private func tap(at frame: CGRect, in app: XCUIApplication) {
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - app.frame.minX, dy: frame.midY - app.frame.minY))
        #if targetEnvironment(macCatalyst)
        point.click()
        #else
        point.tap()
        #endif
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The width of the board on screen once three samples agree. Game Detail
    /// keeps a hidden board in a slot shrunk to nothing.
    private func settledBoardWidth(in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) -> CGFloat? {
        func shownBoard() -> CGRect? {
            guard let root = try? app.snapshot() else { return nil }
            var boards = [CGRect]()
            var pending: [XCUIElementSnapshot] = [root]
            while let node = pending.popLast() {
                if node.identifier == ID.gameBoard, node.frame.width > 1, node.frame.intersects(app.frame) {
                    boards.append(node.frame)
                }
                pending.append(contentsOf: node.children)
            }
            return boards.max { $0.width < $1.width }
        }
        var previous: CGRect?
        var agreeing = 0
        let settled = pollUntil(timeout: stateSettleTimeout) {
            guard let frame = shownBoard() else {
                previous = nil
                agreeing = 0
                return false
            }
            if let previous, abs(previous.minX - frame.minX) <= 0.5, abs(previous.minY - frame.minY) <= 0.5,
               abs(previous.width - frame.width) <= 0.5, abs(previous.height - frame.height) <= 0.5 {
                agreeing += 1
            } else {
                agreeing = 1
            }
            previous = frame
            return agreeing >= 3
        }
        XCTAssertTrue(settled, "The game board settles", file: file, line: line)
        if let previous { attach("Board \(previous)", name: "Board frame") }
        return settled ? previous?.width : nil
    }

    private func returnToActiveGames(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Active games"
        )).firstMatch
        tap(back, description: "Back to Active games", in: app, file: file, line: line)
        XCTAssertTrue(app.navigationBars["Active games"].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(waitForAbsence(query(ID.gameDetail(fixtureGameID), in: app), timeout: stateSettleTimeout),
                      "Back leaves the game", file: file, line: line)
    }

    /// Game Detail's Active games, from its toolbar or the bar's overflow.
    private func openActiveGames(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let direct = app.buttons.matching(identifier: ID.gameActiveGamesButton).firstMatch
        let overflow = app.buttons.matching(NSPredicate(
            format: "identifier IN %@ OR label == %@",
            ["OverflowBarButtonItem", "BottomOverflowBarButtonItem", "More"], "More"
        )).firstMatch
        XCTAssertTrue(pollUntil(timeout: 10) { direct.exists || overflow.isHittable },
                      "Expected Active games or its toolbar overflow", file: file, line: line)
        if direct.exists {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iOS 27 can leave the hidden tab bar's frame over this bottom
                // item, so tap its center rather than wait for hittability.
                activate(direct, at: CGVector(dx: 0.5, dy: 0.5))
            } else {
                tap(direct, description: "Active games", in: app, file: file, line: line)
            }
        } else {
            tap(overflow, description: "The game toolbar's overflow", in: app, file: file, line: line)
            tap(requiredMenuButton(ID.gameActiveGamesButton, title: "Active games", in: app, file: file, line: line),
                description: "Active games in the overflow", in: app, file: file, line: line)
        }
    }

    /// The system share sheet's Copy action, which a link always offers.
    private func shareSheetCopy(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let copy = app.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %lu OR elementType == %lu) AND (label == %@ OR identifier == %@)",
            XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue, "Copy", "Copy"
        )).firstMatch
        let appeared = copy.waitForExistence(timeout: 30)
        if !appeared { attach(app.debugDescription, name: "Accessibility hierarchy – no share sheet Copy") }
        XCTAssertTrue(appeared, "The share sheet offers Copy", file: file, line: line)
        return copy
    }

    /// Swipes up in a scroll view or web view until the element is in view.
    private func reveal(_ target: XCUIElement, scrolling container: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(container.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<16 {
            if target.exists && target.isHittable { return target }
            container.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(waitUntilHittable(target, timeout: 10), "Expected \(target) in view after scrolling",
                      file: file, line: line)
        return target
    }
}
#endif
