//
//  ActivityConversationUITests.swift
//  SurroundUITests
//
//  Conversations in the Activity list, and friend requests that keep their
//  place in Messages' inbox. The Activity bar's "3 waiting", or the Now
//  section's row on an iPad with its sidebar shown, opens the list, and a
//  conversation read there leaves the count; a draft typed in the list is
//  Messages' draft too. Messages' own conversations show the live game that
//  needs you in their top bar, and go offline with their window. Offline UI
//  tests can't send, so a reply is checked up to Send. CI runs the class
//  with the list's journeys, in its Activity phase.
//

import XCTest
import UIKit

#if DEBUG
final class ActivityConversationUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias FixtureID = SurroundUITestContract.ActivityFixtureID

    /// `nothing-leads`' unread conversations, newest first.
    private let tenukiTomID = 915_100
    private let quietPineID = 851_006

    // MARK: Journeys

    /// "3 waiting": CedarWave's correspondence challenge and two unread
    /// conversations. The list opens at its top, and opens no conversation
    /// by itself; reading one makes it "2 waiting", and All messages closes
    /// the list on Messages.
    func testMessagesButtonOpensActivityAtMessages() {
        let app = launch(.nothingLeads)
        let waiting = activityLead(nowRow: "waiting", in: app)
        XCTAssertEqual(activityCount(of: waiting), 3, "The state has a challenge and two unread conversations")
        tap(waiting, description: "3 waiting", in: app)
        element(ID.activityList, in: app)
        element(ID.activitySection("messages"), in: app)
        let newest = element(ID.activityRow("conversation-\(tenukiTomID)"), in: app)
        element(ID.activityRow("conversation-\(quietPineID)"), in: app)
        let conversation = query("messages.conversation", in: app)
        XCTAssertFalse(conversation.exists, "Neither unread conversation opens by itself")
        keepScreenshot("Activity from 3 waiting", in: app)

        tap(revealInList(newest, in: app), description: "tenuki_tom's conversation", in: app)
        element("messages.conversation.profile.\(tenukiTomID)", in: app)
        backToList(leaving: conversation, in: app)
        closeList(in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.activityCount(of: waiting) == 2 },
                      "Reading it in Activity makes it 2 waiting")
        keepScreenshot("2 waiting after reading a conversation", in: app)

        tap(waiting, description: "2 waiting", in: app)
        tap(revealInList(query(ID.activityAllMessages, in: app), in: app),
            description: "All messages", in: app)
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "All messages closes the list")
        element(ID.screenMessages, in: app)
    }

    func testAConversationRepliesInPlaceAndKeepsItsDraft() {
        let draft = "Rematch tomorrow at nine?"
        let app = launch(.nothingLeads)
        tap(activityLead(nowRow: "waiting", in: app), description: "3 waiting", in: app)
        let row = element(ID.activityRow("conversation-\(tenukiTomID)"), in: app)
        tap(revealInList(row, in: app), description: "tenuki_tom's conversation", in: app)
        let conversation = element("messages.conversation", in: app)
        let field = element(ID.privateMessageComposer, in: app, matching: .textField)
        tap(field, description: "The reply field", in: app)
        field.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: field, timeout: stateSettleTimeout), "The reply is typed in place")
        XCTAssertTrue(app.buttons["Send message"].firstMatch.exists, "Send stands beside the reply")
        keepScreenshot("A reply typed in Activity", in: app)

        backToList(leaving: conversation, in: app)
        closeList(in: app)
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        tap(ID.privateMessageRow(tenukiTomID), in: app)
        let messagesField = element(ID.privateMessageComposer, in: app, matching: .textField)
        XCTAssertTrue(waitForValue(draft, in: messagesField, timeout: stateSettleTimeout),
                      "Messages keeps the draft typed in Activity")
        keepScreenshot("The draft in Messages", in: app)
    }

    func testFriendRequestResultsStayInPlace() {
        let ids = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        let names = SurroundUITestContract.friendshipFixtureRequestUsernames
        let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.friendshipLaunchArgument],
                            orientation: preferredOrientation)
        if !isPhone { restoreFullSizeWindow(in: app) }
        element(ID.screenHome, in: app)
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)

        tapRequestControl(ID.friendRequestAccept(ids[0]), description: "Accept \(names[0])", in: app)
        let accepted = query(ID.friendRequestResult(ids[0]), in: app)
        XCTAssertTrue(waitForLabel("You and \(names[0]) are friends", of: accepted), "Accept shows its result in place")
        let viewProfile = element(ID.friendRequestViewProfile(ids[0]), in: app, matching: .button)
        XCTAssertEqual(viewProfile.label, "View \(names[0])’s profile")

        tapRequestControl(ID.friendRequestReject(ids[1]), description: "Reject \(names[1])", in: app)
        tap(requiredMenuButton(ID.friendshipRejectQuietly, title: "Reject Quietly", in: app),
            description: "Reject quietly", in: app)
        let rejected = query(ID.friendRequestResult(ids[1]), in: app)
        XCTAssertTrue(waitForLabel("Rejected quietly.", of: rejected), "Reject shows its result in place")
        let pending = element(ID.friendRequestAccept(ids[2]), in: app, matching: .button)
        XCTAssertTrue(accepted.frame.minY < rejected.frame.minY && rejected.frame.minY < pending.frame.minY,
                      "Each result keeps its request's place")
        XCTAssertTrue(staysPresent(accepted), "The results stay")
        keepScreenshot("Messages – friend request results in place", in: app)

        // View profile covers the inbox; after Back, the results have gone.
        tap(viewProfile, description: "View \(names[0])'s profile", in: app)
        assertLoadedProfile(named: names[0], in: app)
        navigateBackFromPlayerProfile(in: app)
        element(ID.screenMessages, in: app)
        XCTAssertFalse(query(ID.friendRequestResult(ids[0]), in: app).exists, "The accept's result has gone")
        XCTAssertFalse(query(ID.friendRequestResult(ids[1]), in: app).exists, "The reject's result has gone")
        element(ID.friendRequestAccept(ids[2]), in: app)
        keepScreenshot("Messages – results gone after View profile and Back", in: app)

        // Another tab clears them too.
        tapRequestControl(ID.friendRequestAccept(ids[2]), description: "Accept \(names[2])", in: app)
        let third = query(ID.friendRequestResult(ids[2]), in: app)
        XCTAssertTrue(waitForLabel("You and \(names[2]) are friends", of: third), "Accept shows its result in place")
        selectMainNavigation(ID.navigationHome, in: app)
        element(ID.screenHome, in: app)
        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        XCTAssertFalse(third.exists, "The result has gone after another tab")
    }

    // MARK: The window's live game and connection in a conversation

    /// `several`: HarborMist's live game on your move needs you, so a
    /// conversation's top bar shows it (`messages.conversation.gameControl`).
    /// - A phone in portrait, Messages in one column: the pushed
    ///   conversation's native icon with its badge of 1, which before iOS 26
    ///   the app draws, with no accessibility value.
    /// - A phone in landscape and an iPad, Messages in two columns: the chip
    ///   in the pane's heading.
    /// - The Duo, in the pose Device Hub set: the rail's icon, pushed or in
    ///   the pane, closed upright and in the wide poses; in a tall pose,
    ///   whose bar is horizontal, the chip in the pane's heading; and none on
    ///   the closed Duo turned sideways, where the icon would push Challenge
    ///   and Profile into More.
    /// - The Mac, signed and under Automation Mode: the chip in the pane's
    ///   heading, then, in the conversation pushed from the peer's profile,
    ///   the toolbar's icon, which XCTest finds by its label, since the Mac's
    ///   toolbar items carry no identifier. Each is clicked at its centre;
    ///   the icon's badge isn't checked, as the Mac's toolbar draws none
    ///   beside a title.
    /// A tap shows the game on Home's route, and the draft typed first is
    /// still in the composer back in Messages.
    func testAConversationShowsTheControlWhileALiveGameNeedsYou() throws {
        #if targetEnvironment(macCatalyst)
        let draft = "Back soon"
        let app = launchMac(.several)
        openPaneConversation(tenukiTomID, in: app)
        let chip = query(ID.messagesConversationGameControl, in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "A live game on your move puts the chip in the pane's heading")
        let heading = query("messages.conversation.heading", in: app).frame
        XCTAssertTrue(chip.label.contains("HarborMist"), "It shows HarborMist's game: \(chip.label)")
        XCTAssertTrue(heading.insetBy(dx: -1, dy: -1).contains(chip.frame),
                      "The chip is in the pane's heading: \(chip.frame) in \(heading)")
        keepWindowScreenshots("The chip in the pane's heading", in: app)
        let field = element(ID.privateMessageComposer, in: app, matching: .textField)
        click(field, name: "The reply field")
        field.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: field, timeout: stateSettleTimeout), "The draft is typed")
        click(chip, name: "The pane's chip")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        keepWindowScreenshots("HarborMist's game from the pane's chip", in: app)
        goBack(in: app)
        element(ID.screenHome, in: app)
        openPaneConversation(tenukiTomID, in: app)
        XCTAssertTrue(waitForValue(draft, in: element(ID.privateMessageComposer, in: app, matching: .textField),
                                   timeout: stateSettleTimeout), "The draft is kept")

        // Pushed from the peer's profile, the conversation's control is the toolbar's icon.
        click(query(ID.profileMessageToolbarEntry(tenukiTomID), in: app), name: "tenuki_tom's profile")
        element(ID.screenPlayerProfile, in: app)
        click(app.buttons.matching(identifier: ID.profileMessage).firstMatch, name: "Message")
        element("messages.conversation", in: app)
        let icon = app.toolbars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label BEGINSWITH %@", ID.messagesConversationGameControl,
            "HarborMist, your move in your live game"
        )).firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "A live game on your move puts the icon in the toolbar")
        attach("\(icon.label) at \(icon.frame), value \(String(describing: icon.value))", name: "The toolbar's icon")
        keepWindowScreenshots("The toolbar's icon in a conversation pushed from the profile", in: app)
        click(icon, name: "The toolbar's icon")
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        goBack(in: app)
        element(ID.screenHome, in: app)
        #else
        let draft = "Back soon"
        let app = launch(.several)
        let place = openConversation(tenukiTomID, in: app)
        if isClosedDuoTurnedSideways(in: app) {
            XCTAssertFalse(pollUntil(timeout: 3) { self.query(ID.messagesConversationGameControl, in: app).exists },
                           "The closed Duo turned sideways shows no control")
            keepScreenshot("No control on the closed Duo turned sideways", in: app)
            return
        }
        let control = gameControl(in: app)
        assertControl(control, place: place, in: app)
        keepScreenshot("The control in a \(place) conversation", in: app)

        let field = element(ID.privateMessageComposer, in: app, matching: .textField)
        focusReplyField(field, in: app)
        field.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: field, timeout: stateSettleTimeout), "The draft is typed")
        tap(gameControl(in: app), description: "The conversation's control", in: app)
        element(ID.gameDetail(FixtureID.harborMistGameID), in: app)
        keepScreenshot("HarborMist's game from the conversation's control", in: app)
        backToHome(in: app)

        selectMainNavigation(ID.navigationMessages, in: app)
        element(ID.screenMessages, in: app)
        openConversation(tenukiTomID, in: app)
        let kept = element(ID.privateMessageComposer, in: app, matching: .textField)
        XCTAssertTrue(waitForValue(draft, in: kept, timeout: stateSettleTimeout), "The draft is kept")

        // A phone turned to landscape: Messages' two columns, the chip in the pane.
        guard isPhone, !isDuo, place == .pushed else { return }
        backToMessages(in: app)
        turnWindow(to: .landscapeLeft, in: app)
        defer { turnWindow(to: .portrait, in: app) }
        XCTAssertEqual(openConversation(tenukiTomID, in: app), .pane, "In landscape Messages has two columns")
        assertControl(gameControl(in: app), place: .pane, in: app)
        keepScreenshot("The control in the pane's heading in landscape", in: app)
        #endif
    }

    /// `several`, online until the conversation shows, then dropped with the
    /// Debug connection command: the window's source says "Reconnecting…"
    /// 2 s after the drop and Can’t reach OGS 30 s after it, however long the
    /// launch and the way to the conversation took. A conversation's Send
    /// dims and reads "Reconnecting…", and the line above its composer
    /// (`activity.conversation.status`) says the status unless a root
    /// carrier beside it does.
    /// - In Messages' pane (a phone in landscape, an iPad, the Duo's wide
    ///   poses): on iPhones and the Duo from iOS 26 it hides while Messages'
    ///   title line says "Reconnecting…", and shows with its Retry at Can’t
    ///   reach OGS, which that line says without one. Before iOS 26 nothing
    ///   beside it says the status, so it shows. On an iPad it hides while
    ///   the sidebar's Now section says the status, and shows once a turn to
    ///   portrait hides the sidebar; the pushed step skips, as Messages
    ///   always has two columns there.
    /// - Pushed (a phone in portrait, the Duo closed upright): the line shows
    ///   above the composer.
    /// - The Mac, signed and under Automation Mode, Messages' pane, launched
    ///   offline as the Mac's other journeys are: the line hides while the
    ///   sidebar's Now section says the status beside it, and at Can’t reach
    ///   OGS too, whose Retry the Now row holds.
    /// A phone starts in landscape, so the pane's steps come inside the
    /// outage's first 30 s, and then turns to portrait for the pushed one.
    func testAConversationGoesOfflineWithTheWindow() throws {
        #if targetEnvironment(macCatalyst)
        let app = launchMac(.several, offline: true)
        openPaneConversation(tenukiTomID, in: app)
        assertSendDims(in: app)
        let line = query(ID.activityConversationStatus, in: app)
        let status = query(ID.rootConnectionStatus, in: app)
        XCTAssertTrue(waitForLabel("Reconnecting to OGS", of: status), "The Now section's first row says the status")
        XCTAssertFalse(line.exists, "Beside the Now section's row the composer's line hides")
        keepWindowScreenshots("Offline in the pane beside the Now section's row", in: app)
        XCTAssertTrue(waitForLabel("Can’t reach OGS", of: status, timeout: 40), "30 s in, the Now row says Can’t reach OGS")
        XCTAssertTrue(query(ID.rootConnectionStatusRetry, in: app).waitForExistence(timeout: 10),
                      "The Now row offers Retry at Can’t reach OGS")
        XCTAssertFalse(pollUntil(timeout: 3) { line.exists },
                       "At Can’t reach OGS too the composer's line hides beside the Now row, which holds the Retry")
        assertSendDims(in: app)
        keepWindowScreenshots("Can’t reach OGS in the Now row beside the pane, no composer line", in: app)
        #else
        let turnsPhone = isPhone && !isDuo
        let app = launch(.several, orientation: turnsPhone ? .landscapeLeft : nil)
        // In landscape an iPad's sidebar, with its Now section, shows.
        if !isPhone { showIPadSidebar(true, in: app) }
        let place = openConversation(tenukiTomID, in: app)
        // The outage starts here, so a slow launch or way to the conversation
        // can't use up its 30 s of Reconnecting… before the checks.
        post(.drop)
        assertSendDims(in: app)
        if place == .pane {
            let line = query(ID.activityConversationStatus, in: app)
            switch rootStatusCarrier(in: app) {
            case .titleLine:
                XCTAssertTrue(pollUntil(timeout: 10) { self.rootStatusReading(in: app).line == .reconnecting },
                              "Messages' title line says Reconnecting…: \(rootStatusReading(in: app))")
                XCTAssertFalse(line.exists, "Beside the title line the composer's line hides")
                keepScreenshot("Offline in the pane: Messages' title line, no composer line", in: app)
                XCTAssertTrue(pollUntil(timeout: 40) { self.rootStatusReading(in: app).line == .unreachable },
                              "30 s in, the title line says Can’t reach OGS")
                assertComposerLine(saying: "Can’t reach OGS", in: app)
                XCTAssertTrue(query(ID.activityConversationStatusRetry, in: app).waitForExistence(timeout: 10),
                              "The composer's line offers Retry, which the title line doesn't")
                keepScreenshot("Can’t reach OGS in the pane, with the composer's Retry", in: app)
            case .floatingBar:
                assertComposerLine(in: app)
                keepScreenshot("Offline in the pane, the composer's line with nothing beside it", in: app)
            case .nowRow:
                XCTAssertTrue(pollUntil(timeout: 10) { self.rootStatusReading(in: app).element == .reconnecting },
                              "The Now section's row says the status")
                XCTAssertFalse(line.exists, "Beside the Now section's row the composer's line hides")
                keepScreenshot("Offline in the pane beside the Now section's row", in: app)
                turnWindow(to: .portrait, in: app)
                showIPadSidebar(false, in: app)
                assertComposerLine(in: app)
                keepScreenshot("Offline in the pane in portrait, the composer's line", in: app)
            }
        }
        guard place == .pushed || turnsPhone else { return }
        if place == .pane {
            // In portrait Messages has one column: the conversation pushed.
            turnWindow(to: .portrait, in: app)
            let peer = query("messages.conversation.profile.\(tenukiTomID)", in: app)
            let pane = query("messages.detailPane", in: app)
            if !pollUntil(timeout: 3, condition: { peer.exists && peer.isHittable && !pane.exists }) {
                XCTAssertEqual(openConversation(tenukiTomID, in: app), .pushed, "In portrait Messages has one column")
            }
            assertSendDims(in: app)
        }
        assertComposerLine(in: app)
        keepScreenshot("An offline pushed conversation's status line above the composer", in: app)
        #endif
    }

    // MARK: Launching

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Portrait on a phone, landscape on an iPad.
    private var preferredOrientation: UIDeviceOrientation { isPhone ? .portrait : .landscapeLeft }

    private func launch(_ state: State, offline: Bool = false, orientation: UIDeviceOrientation? = nil,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.activityStateLaunchArgument, state.rawValue]
        if offline {
            arguments += [SurroundUITestContract.activityConnectionLaunchArgument,
                          SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        }
        let app = launchApp(additionalLaunchArguments: arguments, orientation: orientation ?? preferredOrientation)
        // An iPad keeps a window resized by another run, which could be compact.
        if !isPhone { restoreFullSizeWindow(in: app) }
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    // MARK: Helpers

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Back inside the list's own stack, never the screen's under it, which
    /// a sheet covers, until `pushed` has gone.
    private func backToList(leaving pushed: XCUIElement, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let popover = app.popovers.firstMatch
        let back = visibleBack(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@", "BackButton", "Activity", "Back"
        ), in: popover.exists ? popover : (app as XCUIElement), description: "the list's Back", file: file, line: line)
        guard let back else { return }
        tap(back, description: "Back to Activity", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(pushed, timeout: stateSettleTimeout), "Back shows the list", file: file, line: line)
        element(ID.activityList, in: app, file: file, line: line)
    }

    /// Done on the sheet, or a tap outside the popover.
    private func closeList(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.popovers.firstMatch.exists {
            dismissPopover(in: app, file: file, line: line)
        } else {
            tap(ID.activityDone, in: app, matching: .button, file: file, line: line)
        }
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "The list closes", file: file, line: line)
    }

    /// Scrolls the list until `row` can be tapped, toward the list's middle.
    /// It drags by the window's coordinates, in the list's leading margin
    /// beside the rows: in an iPadOS 27 popover XCTest finds no visible frame
    /// for the list's scroll view, under a zero-size container, so it can't
    /// swipe the element itself; a drag that starts on a row can open it
    /// (seen on iOS 18.6); and on the trailing side a drag can grab the
    /// scroll indicator, which scrolls the other way (seen in an iPadOS 18
    /// sheet).
    private func revealInList(_ row: XCUIElement, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let list = element(ID.activityList, in: app, file: file, line: line)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Expected \(row) in the list", file: file, line: line)
        for _ in 0..<6 {
            let frame = list.frame
            let viewport = frame.insetBy(dx: 0, dy: 60)
            let rowCenter = CGPoint(x: row.frame.midX, y: row.frame.midY)
            if row.isHittable && viewport.contains(rowCenter) { break }
            let limit = min(frame.height * 0.4, 300)
            let distance = viewport.midY - rowCenter.y
            // The scroll view starts to follow about 10 pt into a drag.
            let travel = max(-limit, min(limit, distance + (distance < 0 ? -10 : 10)))
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.minX + 8 - app.frame.minX, dy: frame.midY - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: travel)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return row
    }

    /// A request row's control, scrolled into the inbox's view first.
    private func tapRequestControl(_ identifier: String, description: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let control = element(identifier, in: app, matching: .button, file: file, line: line)
        scrollIntoTappableArea(control, in: app)
        tap(control, description: description, in: app, file: file, line: line)
    }

    private func waitForLabel(_ label: String, of element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: timeout ?? stateSettleTimeout) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return waitWithFinalCheck(for: [gone], timeout: timeout) == .completed
    }

    /// Still there a second later.
    private func staysPresent(_ element: XCUIElement) -> Bool {
        element.exists && !pollUntil(timeout: 1) { !element.exists }
    }

    /// Taps the reply field until it has keyboard focus, twice at most, as
    /// the game's chat composer is focused: on a hosted iPad a tap on it once
    /// left it without focus, so typing found none. A tap that leaves it
    /// without focus is kept, with the hierarchy.
    private func focusReplyField(_ field: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let focused = app.textFields.matching(NSPredicate(
            format: "identifier == %@ AND hasKeyboardFocus == true", ID.privateMessageComposer)).firstMatch
        for attempt in 1...2 {
            tap(field, description: attempt == 1 ? "The reply field" : "The reply field again", in: app,
                file: file, line: line)
            if focused.waitForExistence(timeout: 3) { return }
            attach(app.debugDescription, name: "Accessibility hierarchy – the reply field without focus after tap \(attempt)")
        }
        XCTFail("The reply field takes keyboard focus", file: file, line: line)
    }

    /// Listed and disabled: a control that went away doesn't count.
    private func waitUntilDisabled(_ element: XCUIElement) -> Bool {
        let off = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == false"), object: element)
        return waitWithFinalCheck(for: [off], timeout: stateSettleTimeout) == .completed
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Offline, Send and the reply field dim and read "Reconnecting…".
    private func assertSendDims(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = element(ID.privateMessageComposer, in: app, matching: .textField, file: file, line: line)
        let send = app.buttons["Send message"].firstMatch
        // Send is off with an empty draft too, so only its word tells, and a
        // drop posted to the app takes a moment to bring it: wait for the word.
        XCTAssertTrue(waitUntilDisabled(send), "Offline, Send dims", file: file, line: line)
        XCTAssertTrue(waitForValue("Reconnecting…", in: send, timeout: stateSettleTimeout),
                      "Offline, Send reads Reconnecting…: \(send.value as? String ?? "no value")", file: file, line: line)
        XCTAssertTrue(waitUntilDisabled(field), "Offline, the reply field dims", file: file, line: line)
        XCTAssertTrue(waitForValue("Reconnecting…", in: field, timeout: stateSettleTimeout),
                      "Offline, the reply field reads Reconnecting…: \(field.value as? String ?? "no value")",
                      file: file, line: line)
    }

    #if targetEnvironment(macCatalyst)
    // MARK: The Mac

    /// An Activity state at Home on the Mac, in a window whose content is
    /// 1200 × 760, so Messages has two columns beside the sidebar.
    private func launchMac(_ state: State, offline: Bool = false, file: StaticString = #filePath,
                           line: UInt = #line) -> XCUIApplication {
        var arguments = [SurroundUITestContract.activityStateLaunchArgument, state.rawValue,
                         SurroundUITestContract.catalystWindowSizeLaunchArgument, "1200x760"]
        if offline {
            arguments += [SurroundUITestContract.activityConnectionLaunchArgument,
                          SurroundUITestContract.ActivityFixtureConnection.offline.rawValue]
        }
        let app = launchApp(additionalLaunchArguments: arguments)
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    /// Messages, from the sidebar, then the peer's conversation in its pane,
    /// each clicked at its centre.
    private func openPaneConversation(_ peerID: Int, in app: XCUIApplication, file: StaticString = #filePath,
                                      line: UInt = #line) {
        selectSidebarEntry(ID.navigationMessages, in: app, file: file, line: line)
        element(ID.screenMessages, in: app, file: file, line: line)
        click(query(ID.privateMessageRow(peerID), in: app), name: "The conversation's row", file: file, line: line)
        element("messages.conversation.heading", in: app, file: file, line: line)
        element("messages.conversation.profile.\(peerID)", in: app, file: file, line: line)
    }
    #endif

    #if !targetEnvironment(macCatalyst)
    // MARK: A conversation's top bar and composer

    /// The closed Duo turned sideways: compact width and height, with its
    /// rail beside the content, where Messages has two columns.
    private func isClosedDuoTurnedSideways(in app: XCUIApplication) -> Bool {
        let window = windowFrame(in: app)
        return isDuo && window.width > window.height && window.height < 600
    }

    /// Where Messages shows a conversation: pushed over its inbox in one
    /// column, or in its side pane in two.
    private enum ConversationPlace: String {
        case pushed, pane
    }

    /// Opens the peer's conversation from Messages' inbox, which Messages
    /// shows pushed in one column and in its pane in two.
    @discardableResult
    private func openConversation(_ peerID: Int, in app: XCUIApplication,
                                  file: StaticString = #filePath, line: UInt = #line) -> ConversationPlace {
        if !query(ID.screenMessages, in: app).exists {
            selectMainNavigation(ID.navigationMessages, in: app)
            element(ID.screenMessages, in: app, file: file, line: line)
        }
        let pane = query("messages.detailPane", in: app)
        let place: ConversationPlace = pollUntil(timeout: 3) {
            !(self.listedSnapshot(of: pane)?.frame.isEmpty ?? true)
        } ? .pane : .pushed
        tap(ID.privateMessageRow(peerID), in: app, file: file, line: line)
        element(place == .pane ? "messages.conversation.heading" : "messages.conversation", in: app,
                file: file, line: line)
        element("messages.conversation.profile.\(peerID)", in: app, file: file, line: line)
        return place
    }

    /// The conversation's control, once it can be tapped.
    private func gameControl(in app: XCUIApplication, file: StaticString = #filePath,
                             line: UInt = #line) -> XCUIElement {
        let control = query(ID.messagesConversationGameControl, in: app)
        let shown = pollUntil(timeout: 10) { control.exists && control.isHittable }
        if !shown { attach(app.debugDescription, name: "Accessibility hierarchy – no conversation control") }
        XCTAssertTrue(shown, "A live game on your move puts the control in the conversation's top bar",
                      file: file, line: line)
        return control
    }

    /// The control's form here: the native icon, with its badge of 1 as its
    /// value from iOS 26, on a phone's pushed conversation in portrait and on
    /// the Duo's rail, which runs down the window's edge closed and in the
    /// wide poses; else the chip, which in the pane sits in its heading, as
    /// in the Duo's tall poses, whose bar is horizontal.
    private func assertControl(_ control: XCUIElement, place: ConversationPlace, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        let frame = control.frame
        let value = control.value as? String ?? ""
        let window = windowFrame(in: app)
        let landscapePhone = isPhone && window.width > window.height
        let duoHasItsRail = min(window.width, window.height) < 600 || window.width > window.height
        let expectsIcon = isDuo ? duoHasItsRail : place == .pushed && !landscapePhone
        attach("\(place): \(frame), label \(control.label), value \(value), window \(window)",
               name: "The conversation's control")
        XCTAssertTrue(control.label.contains("HarborMist"), "It shows HarborMist's game: \(control.label)",
                      file: file, line: line)
        if expectsIcon {
            XCTAssertLessThan(frame.width, 70, "The icon, not the chip: \(frame)", file: file, line: line)
            if #available(iOS 26.0, *) {
                XCTAssertTrue(value.contains("1"), "The icon's badge of 1: \(value)", file: file, line: line)
            }
        } else {
            XCTAssertGreaterThanOrEqual(frame.width, 80, "The chip: \(frame)", file: file, line: line)
            if place == .pane {
                let heading = query("messages.conversation.heading", in: app).frame
                XCTAssertTrue(heading.insetBy(dx: -1, dy: -1).contains(frame),
                              "The chip is in the pane's heading: \(frame) in \(heading)", file: file, line: line)
            }
        }
    }

    /// Back from a game on Home's route to Home. iOS 18 names Back after
    /// Home's title, which the in-game control's base form shares.
    private func backToHome(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let backs = app.buttons.matching(NSPredicate(
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
    }

    /// Back from a pushed conversation to Messages' inbox.
    private func backToMessages(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let conversation = query("messages.conversation", in: app)
        let back = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@", "BackButton", "Messages", "Back"
        )).firstMatch
        tap(back, description: "Back to Messages", in: app, file: file, line: line)
        XCTAssertTrue(waitForAbsence(conversation, timeout: stateSettleTimeout), "Back leaves the conversation",
                      file: file, line: line)
        element(ID.screenMessages, in: app, file: file, line: line)
    }

    /// The status line above the composer says the window's status:
    /// `words`, or either while the outage's 30 s run.
    private func assertComposerLine(saying words: String? = nil, in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let status = query(ID.activityConversationStatus, in: app)
        let expected = words.map { [$0] } ?? ["Reconnecting…", "Can’t reach OGS"]
        // One snapshot a read: the line changes as the status turns.
        var reading: XCUIElementSnapshot?
        XCTAssertTrue(pollUntil(timeout: 10) {
            reading = self.listedSnapshot(of: status)
            return reading.map { expected.contains($0.label) } ?? false
        }, "The composer's line says \(expected): \(reading?.label ?? "none")", file: file, line: line)
        guard let lineFrame = reading?.frame else { return }
        let field = query(ID.privateMessageComposer, in: app).frame
        XCTAssertLessThanOrEqual(lineFrame.maxY, field.minY + 1,
                                 "The line is above the composer: \(lineFrame), \(field)", file: file, line: line)
    }
    #endif
}
#endif
