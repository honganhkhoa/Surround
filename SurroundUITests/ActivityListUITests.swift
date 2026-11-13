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
//  point. None of them focuses a text field.
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
        let rows = ["game-\(FixtureID.harborMistGameID)", "game-\(baseGameID)", "challenge-\(FixtureID.usualChallengeID)",
                    correspondenceSearch, "waiting-open-\(FixtureID.openChallengeID)", liveSearch,
                    "correspondence-games", "conversation-915100", "conversation-851006", "conversation-916001"]
        let frames = settledFrames(sections.map(ID.activitySection) + rows.map { ID.activityRow($0) }, in: app)
        assertTopToBottom(sections.map(ID.activitySection), in: frames, "Sections follow the design's order")
        assertTopToBottom(rows.map { ID.activityRow($0) }, in: frames, "Rows follow the model's order")
        XCTAssertFalse(query(ID.activityRow("conversation-851001"), in: app).exists,
                       "The conversation read before the session starts isn't listed")
        revealInList(query(ID.activityRow("conversation-916001"), in: app), in: app)
        keepScreenshot("Activity's last section: three conversations and All messages", in: app)
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
        XCTAssertTrue(waitForLabel(reconnecting, of: element(ID.activityConversationStatus, in: app)),
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
        XCTAssertTrue([reconnecting, "Can’t reach OGS"].contains(status.label),
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
        if status.label == "Can’t reach OGS" {
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
    func testTheWaitingPillOpensAPopoverInAGame() {
        let sentID = "waiting-sent-\(FixtureID.rematchSentChallengeID)"
        let app = launch(.rematchBothAsked, actions: .succeed)
        tap(ID.homeGame(baseGameID), in: app)
        element(ID.gameDetail(baseGameID), in: app)
        let pill = element(ID.waitingBanner, in: app)
        tap(pill, description: "The waiting pill", in: app)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10), "In a game, the waiting pill opens a popover")
        element(ID.activityList, in: app)
        keepScreenshot("Activity – a game's popover from the waiting pill", in: app)

        tap(ID.activityRow(sentID, .withdraw), in: app, matching: .button)
        XCTAssertTrue(waitForLabel("Withdrawn", of: query(ID.activityRowResult(sentID), in: app)),
                      "The rematch is withdrawn")
        XCTAssertTrue(waitForAbsence(pill, timeout: stateSettleTimeout), "With nothing live waiting, the pill goes")
        XCTAssertTrue(staysPresent(popover), "The popover stays after its pill goes")
        XCTAssertTrue(query(ID.activityList, in: app).exists && query(ID.activityRowResult(sentID), in: app).exists,
                      "The list stays with its result")
        keepScreenshot("Activity – the popover after its pill went", in: app)
    }

    /// As the waiting pill's journey: the sent rematch is the one search
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
