//
//  ActivityListUITests.swift
//  SurroundUITests
//
//  The Activity list's offline journeys: how its openers show it, what its
//  rows offer, and what each action leaves in place. `--surround-activity-state`
//  picks the data. `--surround-activity-open sheet|game-popover` opens the
//  list where no opener shows offline, and `--surround-activity-actions`
//  makes the offline service answer Accept, Reject and Withdraw (TESTING.md).
//  At regular width every real opener shows a popover, so the journeys find
//  the list by `activity.list` and check the style only where it is the
//  point. None of them focuses a text field. Three run only on the Mac,
//  signed and under Automation Mode: its sidebar's Now section and its
//  View > Activity command.
//

import XCTest
import UIKit

#if DEBUG
final class ActivityListUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias FixtureID = SurroundUITestContract.ActivityFixtureID
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias Open = SurroundUITestContract.ActivityOpen
    private typealias Actions = SurroundUITestContract.ActivityActions

    private let baseGameID = SurroundUITestContract.fixtureGameID
    private let reconnecting = "Reconnecting…"
    private let cantReachOGS = "Can’t reach OGS"
    private var liveSearch: String { "waiting-quick-match-\(FixtureID.liveQuickMatchUUID)" }
    private var correspondenceSearch: String { "waiting-quick-match-\(FixtureID.correspondenceQuickMatchUUID)" }

    // MARK: Opening the list

    func testHomeSearchingOpensTheSheetWithEverySection() {
        let app = launch(.several)
        tap(ID.homeSearching, in: app)
        element(ID.activityList, in: app)
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10), "The list is titled Activity")
        if isPhone {
            XCTAssertTrue(waitUntilHittable(query(ID.activityDone, in: app), timeout: 10), "The sheet has Done")
            XCTAssertFalse(app.popovers.firstMatch.exists, "At compact width Home's card opens a sheet")
        } else {
            XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 10),
                          "At regular width Home's card opens a popover")
            XCTAssertFalse(query(ID.activityDone, in: app).exists, "A popover has no Done")
        }
        keepScreenshot(isPhone ? "Activity sheet from Home's card" : "Activity popover from Home's card", in: app)

        let sections = ["liveGames", "challengesReceived", "waiting", "correspondence", "messages"]
        // The last is CedarWave's, read and from before the launch: the app
        // lists every read conversation, as Messages does.
        let rows = ["game-\(FixtureID.harborMistGameID)", "game-\(baseGameID)", "challenge-\(FixtureID.usualChallengeID)",
                    correspondenceSearch, "waiting-open-\(FixtureID.openChallengeID)", liveSearch,
                    "correspondence-games", "conversation-915100", "conversation-851006", "conversation-916001",
                    "conversation-851001"]
        let frames = settledFrames(sections.map(ID.activitySection) + rows.map { ID.activityRow($0) }, in: app)
        assertTopToBottom(sections.map(ID.activitySection), in: frames, "Sections follow the design's order")
        assertTopToBottom(rows.map { ID.activityRow($0) }, in: frames, "Rows follow the model's order")
        revealInList(query(ID.activityRow("conversation-851001"), in: app), in: app)
        keepScreenshot("Activity's last section: four conversations and All messages", in: app)
    }

    func testNothingWaitingSaysSo() {
        let app = launch(.nothingWaiting, open: .sheet)
        let empty = element(ID.activityEmpty, in: app)
        XCTAssertTrue(empty.label.contains("Nothing waiting"), "The empty list says so: \(empty.label)")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.row.")).firstMatch.exists,
                       "An empty list has no rows")
        keepScreenshot("Activity – nothing waiting", in: app)
    }

    // MARK: Challenges

    func testInlineAcceptOnlyForUsualChallenges() {
        let usualID = "challenge-\(FixtureID.usualChallengeID)"
        var app = launch(.challengeReceived, open: .sheet)
        let accept = element(ID.activityRow(usualID, .accept), in: app, matching: .button)
        let reject = element(ID.activityRow(usualID, .reject), in: app, matching: .button)
        XCTAssertEqual(accept.label, "Accept CedarWave’s challenge")
        XCTAssertEqual(reject.label, "Reject CedarWave’s challenge")
        XCTAssertTrue(accept.isEnabled && reject.isEnabled, "A usual challenge takes Accept and Reject in place")
        XCTAssertFalse(query(ID.activityRow(usualID, .view), in: app).exists, "A usual challenge needs no View")
        XCTAssertFalse(warning(in: app).exists, "A usual challenge has no warning")
        keepScreenshot("Activity – a usual challenge with Reject and Accept", in: app)
        app.terminate()

        let unusualID = "challenge-\(FixtureID.unusualChallengeID)"
        app = launch(.unusualChallenge, open: .sheet)
        let view = element(ID.activityRow(unusualID, .view), in: app, matching: .button)
        XCTAssertEqual(view.label, "View the challenge from JadeLantern")
        XCTAssertTrue(warning(in: app).waitForExistence(timeout: 10), "The unusual challenge shows its warning")
        XCTAssertFalse(query(ID.activityRow(unusualID, .accept), in: app).exists, "No Accept in place for it")
        XCTAssertFalse(query(ID.activityRow(unusualID, .reject), in: app).exists, "No Reject in place for it")
        keepScreenshot("Activity – an unusual challenge with its warning and View", in: app)

        tap(view, description: "View JadeLantern's challenge", in: app)
        let card = app.navigationBars["Challenge"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "View pushes the challenge's card")
        XCTAssertTrue(cardButton("Accept", in: app).exists && cardButton("Reject", in: app).exists,
                      "The card decides with its own Accept and Reject")
        keepScreenshot("Activity – the unusual challenge's card", in: app)
        backToList(leaving: card, in: app)
        element(ID.activityRow(unusualID, .view), in: app)
    }

    func testAGamesPopoverUsesView() {
        let usualID = "challenge-\(FixtureID.usualChallengeID)"
        let app = launch(.challengeReceived, open: .gamePopover)
        element(ID.gameDetail(baseGameID), in: app)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "Over a game, Activity is a popover")
        let view = element(ID.activityRow(usualID, .view), in: app, matching: .button)
        XCTAssertFalse(query(ID.activityRow(usualID, .accept), in: app).exists,
                       "In a game's popover even a usual challenge offers View, not Accept")
        XCTAssertFalse(query(ID.activityRow("game-\(baseGameID)"), in: app).exists,
                       "The game on screen isn't listed")
        keepScreenshot("Activity – a game's popover with View", in: app)

        tap(view, description: "View CedarWave's challenge", in: app)
        let card = popover.navigationBars["Challenge"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "View pushes the challenge's card inside the popover")
        XCTAssertTrue(cardButton("Accept", in: app).exists, "The card decides with its own Accept")
        keepScreenshot("Activity – the challenge's card in a game's popover", in: app)
        backToList(leaving: card, in: app)
        XCTAssertTrue(popover.exists, "Back keeps the popover")
    }

    func testAcceptingALiveChallengeOpensTheGame() {
        let usualID = "challenge-\(FixtureID.usualChallengeID)"
        let app = launch(.challengeReceived, open: .sheet, actions: .succeed)
        tap(ID.activityRow(usualID, .accept), in: app, matching: .button)
        let list = query(ID.activityList, in: app)
        XCTAssertTrue(waitForAbsence(list, timeout: stateSettleTimeout), "A live Accept closes the list")
        element(ID.gameDetail(FixtureID.acceptedGameID(FixtureID.usualChallengeID)), in: app)
        keepScreenshot("Activity – the accepted live game opened", in: app)
    }

    func testAcceptingACorrespondenceChallengeStays() {
        let challengeID = "challenge-\(FixtureID.correspondenceChallengeID)"
        let gameID = FixtureID.acceptedGameID(FixtureID.correspondenceChallengeID)
        let app = launch(.nothingLeads, actions: .succeed)
        // The challenge pill shows off Home.
        selectMainNavigation(ID.navigationPublicGames, in: app)
        element(ID.screenPublicGames, in: app)
        tap(ID.challengeBanner, in: app)
        element(ID.activityList, in: app)
        tap(ID.activityRow(challengeID, .accept), in: app, matching: .button)
        let result = query(ID.activityRowResult(challengeID), in: app)
        XCTAssertTrue(waitForLabel("Game started", of: result), "A correspondence Accept says the game started")
        let openGame = element(ID.activityRow(challengeID, .openGame), in: app, matching: .button)
        XCTAssertTrue(waitForAbsence(query(ID.challengeBanner, in: app), timeout: stateSettleTimeout),
                      "The challenge has gone, and so has its pill")
        XCTAssertTrue(query(ID.activityList, in: app).exists, "The list stays for a correspondence game")
        keepScreenshot("Activity – Game started with Open game", in: app)

        tap(openGame, description: "Open the game the challenge started", in: app)
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "Open game closes the list")
        element(ID.gameDetail(gameID), in: app)
        keepScreenshot("Activity – the started correspondence game", in: app)
    }

    // MARK: Withdrawing

    func testWithdrawShowsItsResultAndCouldntWithdraw() {
        let openID = "waiting-open-\(FixtureID.openChallengeID)"
        let app = launch(.waiting, actions: .succeed)
        tap(ID.homeSearching, in: app)
        element(ID.activityList, in: app)
        // The search first: the socket never confirms it, so it fails after 8 s.
        let sent = Date()
        tap(ID.activityRow(liveSearch, .withdraw), in: app, matching: .button)
        tap(ID.activityRow(openID, .withdraw), in: app, matching: .button)
        let withdrawn = query(ID.activityRowResult(openID), in: app)
        XCTAssertTrue(waitForLabel("Withdrawn", of: withdrawn), "OGS's reply withdraws the open challenge")
        keepScreenshot("Activity – Withdrawn in place, a search still withdrawing", in: app)

        let failure = query(ID.activityRowResult(liveSearch), in: app)
        XCTAssertTrue(waitForLabel("Couldn’t withdraw", of: failure, timeout: 20),
                      "An unconfirmed search can't be withdrawn")
        let waited = Date().timeIntervalSince(sent)
        attach(String(format: "Couldn’t withdraw after %.1f s", waited), name: "Quick Match withdraw timing")
        XCTAssertGreaterThanOrEqual(waited, 7.5, "The search waits 8 s for OGS to confirm")
        let retry = element(ID.activityRow(liveSearch, .retry), in: app, matching: .button)
        XCTAssertTrue(retry.isEnabled, "Retry is offered")
        XCTAssertEqual(withdrawn.label, "Withdrawn", "The withdrawn challenge keeps its result")
        keepScreenshot("Activity – Couldn’t withdraw with Retry", in: app)
    }

    // MARK: Offline

    func testOfflineDimsActionsButViewAndOpenWork() {
        let usualID = "challenge-\(FixtureID.usualChallengeID)"
        let openID = "waiting-open-\(FixtureID.openChallengeID)"
        var app = launch(.several, open: .sheet, offline: true)
        // The line reads Reconnecting… for 30 s, then Can’t reach OGS with
        // Retry; the actions read Reconnecting… throughout.
        XCTAssertTrue(waitForLabel(reconnecting, of: element(ID.activityStatus, in: app)),
                      "Offline, the list says Reconnecting…")
        keepScreenshot("Activity offline – Reconnecting…, actions off", in: app)

        // A conversation pushed inside the list says why its composer is off.
        let conversationRow = revealInList(query(ID.activityRow("conversation-915100"), in: app), in: app)
        tap(conversationRow, description: "Open tenuki_tom's conversation", in: app)
        let conversation = element("messages.conversation", in: app)
        // A slow runner can reach the conversation after the 30 s.
        XCTAssertTrue(waitForLabel(in: [reconnecting, cantReachOGS], of: element(ID.activityConversationStatus, in: app)),
                      "The conversation shows the list's offline line")
        let field = element(ID.privateMessageComposer, in: app, matching: .textField)
        let send = app.buttons["Send message"].firstMatch
        XCTAssertTrue(waitUntilDisabled(field), "Offline, the reply field is off")
        XCTAssertEqual(field.value as? String, reconnecting, "Offline, the reply field reads Reconnecting…")
        XCTAssertTrue(waitUntilDisabled(send), "Offline, Send is off")
        XCTAssertEqual(send.value as? String, reconnecting, "Offline, Send reads Reconnecting…")
        keepScreenshot("Activity offline – a conversation's composer off", in: app)
        backToList(leaving: conversation, in: app)
        let status = element(ID.activityStatus, in: app)
        XCTAssertTrue([reconnecting, cantReachOGS].contains(status.label),
                      "Back in the list, its own line still shows: \(status.label)")

        // Read where they are: a control scrolled out of view still says
        // whether it's on.
        for (control, name) in [(ID.activityRow(usualID, .accept), "Accept"), (ID.activityRow(usualID, .reject), "Reject"),
                                (ID.activityRow(openID, .withdraw), "Withdraw"),
                                (ID.activityRow(liveSearch, .withdraw), "the search's Withdraw")] {
            let button = element(control, in: app, matching: .button)
            XCTAssertTrue(waitUntilDisabled(button), "Offline, \(name) is off")
            XCTAssertEqual(button.value as? String, reconnecting, "Offline, \(name) reads Reconnecting…")
        }
        if status.label == cantReachOGS {
            XCTAssertTrue(query(ID.activityStatusRetry, in: app).exists, "Can’t reach OGS offers Retry")
            revealListTop(status, in: app)
            keepScreenshot("Activity offline – Can’t reach OGS with Retry", in: app)
        }
        app.terminate()

        // View and the rows that open games don't need OGS.
        let unusualID = "challenge-\(FixtureID.unusualChallengeID)"
        app = launch(.unusualChallenge, open: .sheet, offline: true)
        element(ID.activityStatus, in: app)
        let view = element(ID.activityRow(unusualID, .view), in: app, matching: .button)
        XCTAssertTrue(view.isEnabled, "Offline, View still works")
        tap(view, description: "View JadeLantern's challenge offline", in: app)
        let card = app.navigationBars["Challenge"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Offline, View pushes the challenge's card")
        for name in ["Accept", "Reject"] {
            let button = cardButton(name, in: app)
            XCTAssertTrue(waitUntilDisabled(button), "Offline, the card's \(name) is off")
            XCTAssertEqual(button.value as? String, reconnecting, "Offline, the card's \(name) reads Reconnecting…")
        }
        keepScreenshot("Activity offline – the card's Accept and Reject off", in: app)
        backToList(leaving: card, in: app)
        tap(ID.activityRow("game-\(baseGameID)"), in: app)
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "Opening a game closes the list")
        element(ID.gameDetail(baseGameID), in: app)
    }

    // MARK: Games

    func testTheCorrespondenceRowOpensTheMostUrgentGame() {
        let app = launch(.correspondenceYourMove, open: .sheet)
        let row = element(ID.activityRow("correspondence-games"), in: app)
        XCTAssertTrue(row.label.contains("Your move in 3 games"), "One row for the three games: \(row.label)")
        tap(row, description: "Open the most urgent correspondence game", in: app)
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "Opening a game closes the list")
        element(ID.gameDetail(FixtureID.correspondenceGameIDs[0]), in: app)
    }

    // MARK: Popovers that outlive their openers

    /// The state's only live waiting item is the sent rematch, which OGS
    /// can withdraw; `waiting`'s live search would keep the pill, since the
    /// socket never confirms a cancel offline.
    /// In a game, the in-game control opens Activity as a popover, which
    /// stays once the item it was opened for resolves. The finished game's
    /// control leads with the rematch card; the sent rematch waits below.
    func testTheControlOpensAPopoverInAGame() {
        let sentID = "waiting-sent-\(FixtureID.rematchSentChallengeID)"
        let app = launch(.rematchBothAsked, actions: .succeed)
        tap(ID.homeGame(baseGameID), in: app)
        element(ID.gameDetail(baseGameID), in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { !query(ID.waitingBanner, in: app).exists },
                      "A game shows no waiting pill")
        _ = openGameControlPopover(in: app)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "In a game, the control opens a popover")
        element(ID.activityList, in: app)
        keepScreenshot("Activity – a game's popover from the control", in: app)

        tap(ID.activityRow(sentID, .withdraw), in: app, matching: .button)
        XCTAssertTrue(waitForLabel("Withdrawn", of: query(ID.activityRowResult(sentID), in: app)),
                      "The rematch is withdrawn")
        XCTAssertTrue(staysPresent(popover), "The popover stays after the waiting item resolves")
        XCTAssertTrue(query(ID.activityList, in: app).exists && query(ID.activityRowResult(sentID), in: app).exists,
                      "The list stays with its result")
        keepScreenshot("Activity – the popover after the waiting item resolved", in: app)
    }

    /// As the control's journey: the sent rematch is the one search
    /// that can be withdrawn offline.
    func testRegularWidthIsAPopoverFromTheSearchingCard() throws {
        try XCTSkipIf(isPhone, "iPad only: at compact width Home's card opens the sheet.")
        let sentID = "waiting-sent-\(FixtureID.rematchSentChallengeID)"
        let app = launch(.rematchBothAsked, actions: .succeed)
        let card = element(ID.homeSearching, in: app)
        let cardFrame = card.frame
        tap(card, description: "Home's Searching card", in: app)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "At regular width Home's card opens a popover")
        element(ID.activityList, in: app)
        XCTAssertFalse(query(ID.activityDone, in: app).exists, "A popover has no Done")
        let frame = popover.frame
        attach("card \(cardFrame)\npopover \(frame)", name: "Searching card and popover frames")
        XCTAssertTrue(frame.midX >= cardFrame.minX && frame.midX <= cardFrame.maxX,
                      "The popover hangs from the card")
        XCTAssertLessThan(max(0, frame.minY - cardFrame.maxY), 60, "The popover starts at the card")
        keepScreenshot("Activity – the popover from Home's card", in: app)

        tap(ID.activityRow(sentID, .withdraw), in: app, matching: .button)
        XCTAssertTrue(waitForLabel("Withdrawn", of: query(ID.activityRowResult(sentID), in: app)),
                      "The last search is withdrawn")
        XCTAssertTrue(waitForAbsence(card, timeout: stateSettleTimeout), "With no search left, the card goes")
        XCTAssertTrue(staysPresent(popover), "The popover stays after its card goes")
        keepScreenshot("Activity – the popover after Home's card went", in: app)
    }

    #if targetEnvironment(macCatalyst)
    // MARK: The Mac's Now section and its Activity command

    /// The Mac's sidebar ends in the Now section: HarborMist's game, then
    /// CedarWave's challenge with View, and All activity, below the last tab
    /// row at 900 × 600 and at the window's bottom through a live resize to
    /// 1200 × 760. XCTest reaches the rows and All activity by their
    /// identifiers, never the section's, and a click at a frame's centre
    /// acts: All activity and the challenge's row open Activity as a popover
    /// in a window of its own, which Escape closes; View pushes the
    /// challenge's card in it; the game's row opens the game, over which the
    /// section leaves it out. Every root keeps the window title the desktop
    /// capture contract pins.
    func testTheMacsNowSectionOpensActivityAndItsRows() {
        let app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.several.rawValue],
                            size: CGSize(width: 900, height: 600))
        let game = query(ID.activityNowRow(harborMist), in: app)
        let challenge = query(ID.activityNowRow(usualChallenge), in: app)
        let view = query(ID.activityNowRowAction(usualChallenge), in: app)
        let all = query(ID.activityNowAll, in: app)
        for (element, name) in [(game, "HarborMist's game"), (challenge, "CedarWave's challenge"),
                                (view, "its View"), (all, "All activity")] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "The Now section shows \(name)")
        }
        XCTAssertFalse(query(ID.activityNowRowAction(harborMist), in: app).exists, "A live game's row has no action")
        attach("label \(all.label)\nvalue \(String(describing: all.value))", name: "All activity")
        assertNowSection(at: "900 × 600", rows: [game, challenge], all: all, in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("The Mac's Now section at 900 × 600", in: app)

        openPopover(byClicking: all, name: "All activity", in: app)
        openPopover(byClicking: challenge, name: "the challenge's row", in: app)
        // The card is pushed at once, so the list itself is never in sight.
        let windows = app.windows.count
        click(view, name: "View")
        XCTAssertTrue(app.navigationBars["Challenge"].firstMatch.waitForExistence(timeout: 10),
                      "View pushes the challenge's card")
        XCTAssertGreaterThan(app.windows.count, windows, "View opens a popover, a window of its own")
        keepWindowScreenshots("The challenge's card from View", in: app)
        closeWithEscape("View's popover", in: app)

        click(game, name: "HarborMist's game")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        XCTAssertTrue(waitForAbsence(game, timeout: stateSettleTimeout), "Over its game the section leaves it out")
        XCTAssertTrue(challenge.exists && all.exists, "The section keeps the rest over the game")
        keepWindowScreenshots("The Now section over HarborMist's game", in: app)
        goBack(in: app)
        element(ID.screenHome, in: app)
        XCTAssertTrue(game.waitForExistence(timeout: 10), "Back on Home, the game's row comes back")

        resizeMacWindow(toContent: CGSize(width: 1200, height: 760), in: app)
        assertNowSection(at: "1200 × 760 after a live resize", rows: [game, challenge], all: all, in: app)
        keepWindowScreenshots("The Mac's Now section at 1200 × 760", in: app)

        for (entry, title) in Self.macRootTitles {
            selectSidebarEntry(entry, in: app)
            assertWindowTitle(title, in: app)
            XCTAssertTrue(all.waitForExistence(timeout: 10), "The section shows beside \(title)")
        }
    }

    /// View > Activity and ⇧⌘A open Activity as All activity does: while the
    /// Now section shows, a popover where All activity's own opens, which
    /// Escape closes, and over a game too, with the game left out of it.
    /// With nothing waiting there is no section, the window's title stays,
    /// and they open the sheet, which Done closes.
    func testTheMacsActivityCommandOpensActivity() {
        var app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.several.rawValue],
                            size: CGSize(width: 900, height: 600))
        let all = query(ID.activityNowAll, in: app)
        XCTAssertTrue(all.waitForExistence(timeout: 10), "The Now section shows All activity")
        let fromAllActivity = openPopover(byClicking: all, name: "All activity", in: app)

        chooseActivityInViewMenu(in: app)
        let fromMenu = assertPopover("View > Activity", in: app)
        XCTAssertEqual(fromMenu.midX, fromAllActivity.midX, accuracy: 2, "The menu's popover hangs from All activity")
        XCTAssertEqual(fromMenu.midY, fromAllActivity.midY, accuracy: 2, "The menu's popover hangs from All activity")
        keepWindowScreenshots("Activity from View > Activity", in: app)
        closeWithEscape("the menu's popover", in: app)

        app.typeKey("a", modifierFlags: [.command, .shift])
        let fromShortcut = assertPopover("⇧⌘A", in: app)
        XCTAssertEqual(fromShortcut.midY, fromAllActivity.midY, accuracy: 2, "The shortcut's popover hangs from All activity")
        closeWithEscape("the shortcut's popover", in: app)

        click(query(ID.activityNowRow(harborMist), in: app), name: "HarborMist's game")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        assertPopover("⇧⌘A over a game", in: app)
        XCTAssertFalse(query(ID.activityRow(harborMist), in: app).exists, "The game on screen isn't listed")
        keepWindowScreenshots("Activity from ⇧⌘A over a game", in: app)
        closeWithEscape("the game's popover", in: app)
        app.terminate()

        app = launchMac([SurroundUITestContract.activityStateLaunchArgument, State.nothingWaiting.rawValue],
                        size: CGSize(width: 900, height: 600))
        assertNoNowSection("Nothing waiting", in: app)
        assertWindowTitle("Active games", in: app)
        keepWindowScreenshots("No Now section with nothing waiting", in: app)
        chooseActivityInViewMenu(in: app)
        closeSheet("View > Activity with nothing waiting", in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        closeSheet("⇧⌘A with nothing waiting", in: app)
    }

    /// Signed out nothing waits, so the sidebar has no Now section at
    /// 900 × 600 or after a live resize to 1200 × 760, and the roots keep
    /// the contract's window titles. There is no Activity either, so View >
    /// Activity is off and ⇧⌘A opens nothing.
    func testTheMacsSidebarHasNoNowSectionSignedOut() {
        let app = launchMac([SurroundUITestContract.signedOutOfflineLaunchArgument],
                            size: CGSize(width: 900, height: 600), screen: nil)
        assertWindowTitle("Welcome", in: app)
        assertNoNowSection("Signed out at 900 × 600", in: app)
        keepWindowScreenshots("Signed out at 900 × 600", in: app)
        assertActivityInViewMenuIsOff(in: app)
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.activityList, in: app).exists },
                       "Signed out, ⇧⌘A opens no Activity")
        resizeMacWindow(toContent: CGSize(width: 1200, height: 760), in: app)
        assertNoNowSection("Signed out at 1200 × 760", in: app)
        keepWindowScreenshots("Signed out at 1200 × 760", in: app)
        for (entry, title) in Self.macRootTitles where entry != ID.navigationMessages && entry != ID.navigationHome {
            selectSidebarEntry(entry, in: app)
            assertWindowTitle(title, in: app)
        }
        assertNoNowSection("Signed out on Web version", in: app)
    }

    /// The roots the desktop capture contract pins, with their window titles
    /// (CompatibilityScreenshotTests), Home last.
    private static let macRootTitles: [(entry: String, title: String)] = [
        (ID.navigationPublicGames, "Public live games"), (ID.navigationMessages, "Messages"),
        (ID.navigationSettings, "Settings"), (ID.navigationAbout, "About"),
        (ID.navigationBrowser, "Web version"), (ID.navigationHome, "Active games"),
    ]

    private var harborMist: String { "game-\(FixtureID.harborMistGameID)" }
    private var usualChallenge: String { "challenge-\(FixtureID.usualChallengeID)" }

    /// A launch whose window content has `size`, at Home or `screen`.
    private func launchMac(_ arguments: [String], size: CGSize, screen: String? = ID.screenHome,
                           file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: arguments + [
            SurroundUITestContract.catalystWindowSizeLaunchArgument, "\(Int(size.width))x\(Int(size.height))",
        ])
        XCTAssertTrue(pollUntil(timeout: 15) { self.contentSize(in: app, isAbout: size) },
                      "The window's content is \(size): \(String(describing: contentSize(in: app)))",
                      file: file, line: line)
        if let screen { element(screen, in: app, file: file, line: line) }
        return app
    }

    /// The window's content size, as the app's window geometry element says
    /// it ("900x600|…").
    private func contentSize(in app: XCUIApplication) -> CGSize? {
        let value = query(ID.catalystWindowGeometry, in: app).value as? String ?? ""
        let size = value.split(separator: "|").first?.split(separator: "x").compactMap { Double($0) } ?? []
        return size.count == 2 ? CGSize(width: size[0], height: size[1]) : nil
    }

    /// The app's own window, not a popover's: the scene's, or the largest.
    private func mainWindow(_ app: XCUIApplication) -> XCUIElement {
        let scene = app.windows.matching(identifier: "SceneWindow").firstMatch
        if scene.exists { return scene }
        let windows = app.windows.allElementsBoundByIndex.filter(\.exists)
        return windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? app.windows.firstMatch
    }

    /// A click at the element's centre: on the Mac XCTest calls the content
    /// unhittable even with nothing over it.
    private func click(_ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Expected \(name)", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    /// The toolbar's Back: by its identifier, or by its label, never the
    /// in-game control.
    private func goBack(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let backs = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR (identifier != %@ AND (label == %@ OR label == %@) AND elementType IN %@)",
            "BackButton", ID.gameActiveGamesButton, "Back", "Active games",
            [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.toolbarButton.rawValue]
        ))
        var back: XCUIElement?
        let found = pollUntil(timeout: 10) {
            back = backs.allElementsBoundByIndex.first { $0.exists && !$0.frame.isEmpty }
            return back != nil
        }
        if !found { attach(app.debugDescription, name: "Accessibility hierarchy – no Back") }
        XCTAssertTrue(found, "Expected the game's Back", file: file, line: line)
        if let back { click(back, name: "Back", file: file, line: line) }
    }

    /// The section in the sidebar's 220 pt column: its rows in order below
    /// the last tab row, then All activity at the window's bottom.
    private func assertNowSection(at name: String, rows: [XCUIElement], all: XCUIElement, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let window = mainWindow(app).frame
        let lastTab = query(ID.navigationBrowser, in: app).frame
        let frames = (rows + [all]).map(\.frame)
        attach((["window \(window)", "Web version \(lastTab)"]
                + zip(rows + [all], frames).map { "\($0.identifier) \($1)" }).joined(separator: "\n"),
               name: "The Now section at \(name)")
        for (element, frame) in zip(rows + [all], frames) {
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                          "\(name): \(element.identifier) is in the window", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.minX + 221,
                                     "\(name): \(element.identifier) is in the sidebar", file: file, line: line)
        }
        XCTAssertEqual(frames.map(\.minY), frames.map(\.minY).sorted(), "\(name): the rows, then All activity",
                       file: file, line: line)
        XCTAssertFalse(lastTab.isEmpty, "\(name): the sidebar lists Web version", file: file, line: line)
        if let first = frames.first, !lastTab.isEmpty {
            XCTAssertGreaterThan(first.minY, lastTab.maxY, "\(name): the section is clear of the last tab row",
                                 file: file, line: line)
        }
        XCTAssertLessThanOrEqual(window.maxY - all.frame.maxY, 20, "\(name): All activity is at the window's bottom",
                                 file: file, line: line)
    }

    private func assertNoNowSection(_ name: String, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let section = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.now.")).firstMatch
        XCTAssertFalse(pollUntil(timeout: 3) { section.exists }, "\(name): no Now section", file: file, line: line)
    }

    /// The main window's title, exactly as the desktop capture contract pins
    /// it: no subtitle joins it.
    private func assertWindowTitle(_ expected: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        var title = ""
        let found = pollUntil(timeout: 10) {
            title = self.mainWindow(app).title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title == expected
        }
        XCTAssertTrue(found, "The window's title is '\(expected)'; found '\(title)'", file: file, line: line)
    }

    /// Clicks `opener`: Activity opens as a popover in a window of its own,
    /// which Escape closes. The list's frame, where the popover hangs.
    @discardableResult
    private func openPopover(byClicking opener: XCUIElement, name: String, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let windows = app.windows.count
        click(opener, name: name, file: file, line: line)
        let frame = assertPopover(name, in: app, file: file, line: line)
        XCTAssertGreaterThan(app.windows.count, windows, "\(name)'s popover is a window of its own",
                             file: file, line: line)
        keepWindowScreenshots("Activity from \(name)", in: app)
        closeWithEscape("\(name)'s popover", in: app, file: file, line: line)
        return frame
    }

    /// Activity is open as a popover, which has no Done. The list's frame.
    @discardableResult
    private func assertPopover(_ name: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let list = element(ID.activityList, in: app, file: file, line: line)
        XCTAssertFalse(query(ID.activityDone, in: app).exists, "\(name) opens a popover, which has no Done",
                       file: file, line: line)
        var frame = CGRect.null
        _ = pollUntil(timeout: 5) {
            let current = list.frame
            defer { frame = current }
            return !current.isEmpty && current == frame
        }
        attach("\(name): list \(frame)\nwindows \(app.windows.allElementsBoundByIndex.map(\.frame))",
               name: "Activity's popover from \(name)")
        return frame
    }

    private func closeWithEscape(_ name: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "Escape closes \(name)", file: file, line: line)
    }

    /// Activity is open as the sheet, with nothing waiting in it; Done
    /// closes it.
    private func closeSheet(_ name: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let list = element(ID.activityList, in: app, file: file, line: line)
        let done = query(ID.activityDone, in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 10), "\(name) opens the sheet, with Done", file: file, line: line)
        XCTAssertTrue(query(ID.activityEmpty, in: app).waitForExistence(timeout: 10), "\(name): nothing waiting",
                      file: file, line: line)
        keepWindowScreenshots("Activity's sheet from \(name)", in: app)
        click(done, name: "Done", file: file, line: line)
        XCTAssertTrue(waitForAbsence(list, timeout: stateSettleTimeout), "Done closes \(name)'s sheet",
                      file: file, line: line)
    }

    /// Chooses View > Activity in the menu bar.
    private func chooseActivityInViewMenu(in app: XCUIApplication, file: StaticString = #filePath,
                                          line: UInt = #line) {
        let view = app.menuBars.menuBarItems["View"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 10), "The menu bar has View", file: file, line: line)
        view.click()
        let item = view.menuItems["Activity"].firstMatch
        if !item.waitForExistence(timeout: 5) {
            attach(app.menuBars.firstMatch.debugDescription, name: "The menu bar")
        }
        XCTAssertTrue(item.exists, "View has Activity", file: file, line: line)
        XCTAssertTrue(item.isEnabled, "View > Activity is enabled", file: file, line: line)
        item.click()
    }

    /// View has Activity, off: the window in front has no Activity.
    private func assertActivityInViewMenuIsOff(in app: XCUIApplication, file: StaticString = #filePath,
                                               line: UInt = #line) {
        let view = app.menuBars.menuBarItems["View"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 10), "The menu bar has View", file: file, line: line)
        view.click()
        let item = view.menuItems["Activity"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "View has Activity", file: file, line: line)
        XCTAssertFalse(item.isEnabled, "View > Activity is off signed out", file: file, line: line)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// Drags the window's bottom right corner until its content is `size`,
    /// as a person resizes it: a live resize.
    private func resizeMacWindow(toContent size: CGSize, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<4 {
            guard let current = contentSize(in: app), !contentSize(in: app, isAbout: size) else { break }
            let delta = CGVector(dx: size.width - current.width, dy: size.height - current.height)
            let corner = mainWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.click(forDuration: 0.6, thenDragTo: corner.withOffset(delta))
            _ = pollUntil(timeout: 3) { self.contentSize(in: app, isAbout: size) }
        }
        XCTAssertTrue(contentSize(in: app, isAbout: size),
                      "A live resize brings the window's content to \(size): \(String(describing: contentSize(in: app)))",
                      file: file, line: line)
    }

    /// The window's content is `size` to within 6 points either way: a live
    /// resize stops a few points short, as it gave 1198 × 759 and 1196 × 758
    /// for 1200 × 760, and a corrective drag that small doesn't take.
    private func contentSize(in app: XCUIApplication, isAbout size: CGSize) -> Bool {
        guard let measured = contentSize(in: app) else { return false }
        return abs(measured.width - size.width) <= 6 && abs(measured.height - size.height) <= 6
    }

    /// Selects a root from the sidebar by its identifier, with a click at its
    /// centre: XCTest calls the Mac's sidebar entries unhittable.
    private func selectSidebarEntry(_ identifier: String, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        click(app.descendants(matching: .any).matching(identifier: identifier).firstMatch, name: identifier,
              file: file, line: line)
    }

    /// The main window, and any window beside it, such as a popover's.
    private func keepWindowScreenshots(_ name: String, in app: XCUIApplication) {
        let main = mainWindow(app)
        guard main.exists else { return }
        let attachment = XCTAttachment(screenshot: main.screenshot(), quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        for (index, other) in app.windows.allElementsBoundByIndex.enumerated()
        where other.exists && other.frame != main.frame && !other.frame.isEmpty {
            let extra = XCTAttachment(screenshot: other.screenshot(), quality: .original)
            extra.name = "\(name) (window \(index))"
            extra.lifetime = .keepAlways
            add(extra)
        }
    }
    #endif

    // MARK: Launching

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Portrait on a phone, landscape on an iPad.
    private var preferredOrientation: UIDeviceOrientation { isPhone ? .portrait : .landscapeLeft }

    /// The state's launch on the frozen fixture clock, at Home or with the
    /// list the Debug opener shows.
    private func launch(_ state: State, open: Open? = nil, actions: Actions? = nil, offline: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.activityStateLaunchArgument, state.rawValue]
        if offline {
            arguments += [SurroundUITestContract.activityConnectionLaunchArgument,
                          SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        }
        if let open { arguments += [SurroundUITestContract.activityOpenLaunchArgument, open.rawValue] }
        if let actions { arguments += [SurroundUITestContract.activityActionsLaunchArgument, actions.rawValue] }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: preferredOrientation)
        // An iPad keeps a window resized by another run, which could be compact.
        if !isPhone { restoreFullSizeWindow(in: app) }
        element(open == nil ? ID.screenHome : ID.activityList, in: app, file: file, line: line)
        return app
    }

    // MARK: Helpers

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The unusual challenge's warning line in the list. Home's own card of
    /// the challenge, under the list, shows it too.
    private func warning(in app: XCUIApplication) -> XCUIElement {
        query(ID.activityList, in: app).descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Custom komi")).firstMatch
    }

    /// A pushed challenge card's own Accept or Reject, which have no
    /// identifier. Home's card of the same challenge, under the list, has
    /// them too, so this is the one a tap reaches.
    private func cardButton(_ label: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier == ''", label))
        var shown: XCUIElement?
        let found = pollUntil(timeout: 10) {
            shown = buttons.allElementsBoundByIndex.first { $0.isHittable }
            return shown != nil
        }
        if !found {
            attach(app.debugDescription, name: "Accessibility hierarchy – no card \(label)")
        }
        XCTAssertTrue(found, "The card shows \(label)", file: file, line: line)
        return shown ?? buttons.firstMatch
    }

    /// Back inside the list's own stack, never the screen's under it, until
    /// `pushed` has gone.
    private func backToList(leaving pushed: XCUIElement, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let popover = app.popovers.firstMatch
        let bars = popover.exists ? popover.navigationBars : app.navigationBars
        let back = bars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@", "BackButton", "Activity", "Back"
        )).firstMatch
        tap(back, description: "Back to Activity", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(pushed, timeout: stateSettleTimeout), "Back shows the list", file: file, line: line)
        element(ID.activityList, in: app, file: file, line: line)
    }

    /// Scrolls the list until `row` can be tapped, toward the list's middle.
    @discardableResult
    private func revealInList(_ row: XCUIElement, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let list = element(ID.activityList, in: app, file: file, line: line)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Expected \(row) in the list", file: file, line: line)
        for _ in 0..<6 {
            let viewport = list.frame.insetBy(dx: 0, dy: 60)
            let rowCenter = CGPoint(x: row.frame.midX, y: row.frame.midY)
            if row.isHittable && viewport.contains(rowCenter) { break }
            drag(list, by: viewport.midY - rowCenter.y, in: app)
        }
        XCTAssertTrue(waitUntilHittable(row, timeout: 10), "Expected \(row) in view", file: file, line: line)
        return row
    }

    /// Scrolls the list back to its top, until its first line, `top`, shows
    /// below the list's bar. It drags only as far as the line is hidden, so
    /// a sheet already at its top is never pulled down.
    private func revealListTop(_ top: XCUIElement, in app: XCUIApplication) {
        let list = query(ID.activityList, in: app)
        let bar = app.navigationBars["Activity"].firstMatch
        for _ in 0..<6 {
            let hidden = bar.frame.maxY - top.frame.minY
            if hidden <= 0 { return }
            drag(list, by: hidden + 8, in: app)
        }
    }

    /// One drag that moves the list's content by about `distance` (down when
    /// positive, at most 300 pt), then a hold so it stops there. It drags by
    /// the window's coordinates, in the list's leading margin beside the
    /// rows: in an iPadOS 27 popover XCTest finds no visible frame for the
    /// list's scroll view, under a zero-size container, so it can't swipe
    /// the element itself; a drag that starts on a row can open it (seen on
    /// iOS 18.6); and on the trailing side a drag can grab the scroll
    /// indicator, which scrolls the other way (seen in an iPadOS 18 sheet).
    private func drag(_ list: XCUIElement, by distance: CGFloat, in app: XCUIApplication) {
        let frame = list.frame
        let limit = min(frame.height * 0.4, 300)
        // The scroll view starts to follow about 10 pt into a drag.
        let travel = max(-limit, min(limit, distance + (distance < 0 ? -10 : 10)))
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + 8 - app.frame.minX, dy: frame.midY - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: travel)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Frames for these identifiers from one snapshot, once two in a row agree.
    private func settledFrames(_ identifiers: [String], in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) -> [String: CGRect] {
        func frames() -> [String: CGRect]? {
            guard let root = try? app.snapshot() else { return nil }
            var found = [String: CGRect]()
            var pending: [XCUIElementSnapshot] = [root]
            while let node = pending.popLast() {
                if identifiers.contains(node.identifier), found[node.identifier] == nil {
                    found[node.identifier] = node.frame
                }
                pending.append(contentsOf: node.children)
            }
            return found.count == identifiers.count ? found : nil
        }
        var previous: [String: CGRect]?
        var settled: [String: CGRect]?
        _ = pollUntil(timeout: stateSettleTimeout) {
            let current = frames()
            defer { previous = current }
            if let current, current == previous { settled = current }
            return settled != nil
        }
        if settled == nil {
            attach(app.debugDescription, name: "Accessibility hierarchy – the list's rows")
        }
        XCTAssertNotNil(settled, "Every section and row is listed", file: file, line: line)
        return settled ?? [:]
    }

    private func assertTopToBottom(_ identifiers: [String], in frames: [String: CGRect], _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let tops = identifiers.compactMap { frames[$0]?.minY }
        guard tops.count == identifiers.count else { return }
        attach(zip(identifiers, tops).map { "\($0) \($1)" }.joined(separator: "\n"), name: message)
        XCTAssertEqual(tops, tops.sorted(), message, file: file, line: line)
        XCTAssertEqual(Set(tops).count, tops.count, "\(message): one row per place", file: file, line: line)
    }

    private func waitForLabel(_ label: String, of element: XCUIElement,
                              timeout: TimeInterval? = nil) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: timeout ?? stateSettleTimeout) == .completed
    }

    private func waitForLabel(in labels: [String], of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label IN %@", labels), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: stateSettleTimeout) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return waitWithFinalCheck(for: [gone], timeout: timeout) == .completed
    }

    /// Listed and disabled: a control that went away doesn't count.
    private func waitUntilDisabled(_ element: XCUIElement) -> Bool {
        let off = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == false"), object: element)
        return waitWithFinalCheck(for: [off], timeout: stateSettleTimeout) == .completed
    }

    /// Still there a second later: a dismissal would have begun by then.
    private func staysPresent(_ element: XCUIElement) -> Bool {
        element.exists && !pollUntil(timeout: 1) { !element.exists }
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
