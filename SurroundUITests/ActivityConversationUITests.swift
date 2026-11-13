//
//  ActivityConversationUITests.swift
//  SurroundUITests
//
//  Conversations in the Activity list, and friend requests that keep their
//  place in Messages' inbox. The Messages button opens the list at
//  Messages, or straight into the only unread conversation; a draft typed in
//  the list is Messages' draft too. Offline UI tests can't send, so a reply
//  is checked up to Send. CI runs the class with the list's journeys, in
//  its Activity phase.
//

import XCTest
import UIKit

#if DEBUG
final class ActivityConversationUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID
    private typealias State = SurroundUITestContract.ActivityFixtureState

    /// `nothing-leads`' unread conversations, newest first.
    private let tenukiTomID = 915_100
    private let quietPineID = 851_006

    // MARK: Journeys

    func testMessagesButtonOpensActivityAtMessages() {
        let app = launch(.nothingLeads)
        let button = element(ID.messagesButton, in: app, matching: .button)
        XCTAssertEqual(unread(button), 2, "The state has two unread conversations")
        tap(button, description: "The Messages button", in: app)
        element(ID.activityList, in: app)
        element(ID.activitySection("messages"), in: app)
        let newest = element(ID.activityRow("conversation-\(tenukiTomID)"), in: app)
        XCTAssertTrue(waitUntilHittable(newest, timeout: 10), "The list opens at Messages")
        let conversation = query("messages.conversation", in: app)
        XCTAssertFalse(conversation.exists, "With two unread conversations, neither opens by itself")
        keepScreenshot("Activity at Messages from the Messages button", in: app)

        tap(newest, description: "tenuki_tom's conversation", in: app)
        element("messages.conversation.profile.\(tenukiTomID)", in: app)
        backToList(leaving: conversation, in: app)
        closeList(in: app)
        XCTAssertTrue(pollUntil(timeout: 10) { self.unread(button) == 1 }, "Reading it in Activity marks it read")

        tap(button, description: "The Messages button, one unread", in: app)
        element("messages.conversation.profile.\(quietPineID)", in: app)
        keepScreenshot("Activity opened straight into the only unread conversation", in: app)
        backToList(leaving: conversation, in: app)
        element(ID.activityRow("conversation-\(quietPineID)"), in: app)
        keepScreenshot("Back from the conversation: the list at Messages", in: app)

        tap(revealInList(query(ID.activityAllMessages, in: app), in: app),
            description: "All messages", in: app)
        XCTAssertTrue(waitForAbsence(query(ID.activityList, in: app), timeout: stateSettleTimeout),
                      "All messages closes the list")
        element(ID.screenMessages, in: app)
    }

    func testAConversationRepliesInPlaceAndKeepsItsDraft() {
        let draft = "Rematch tomorrow at nine?"
        let app = launch(.nothingLeads)
        tap(ID.messagesButton, in: app, matching: .button)
        let row = element(ID.activityRow("conversation-\(tenukiTomID)"), in: app)
        tap(row, description: "tenuki_tom's conversation", in: app)
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

    // MARK: Launching

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Portrait on a phone, landscape on an iPad.
    private var preferredOrientation: UIDeviceOrientation { isPhone ? .portrait : .landscapeLeft }

    private func launch(_ state: State, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [SurroundUITestContract.activityStateLaunchArgument,
                                                        state.rawValue],
                            orientation: preferredOrientation)
        // An iPad keeps a window resized by another run, which could be compact.
        if !isPhone { restoreFullSizeWindow(in: app) }
        element(ID.screenHome, in: app, file: file, line: line)
        return app
    }

    // MARK: Helpers

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The Messages button's unread count.
    private func unread(_ button: XCUIElement) -> Int {
        Int(button.value as? String ?? "") ?? 0
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

    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return waitWithFinalCheck(for: [expectation], timeout: stateSettleTimeout) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return waitWithFinalCheck(for: [gone], timeout: timeout) == .completed
    }

    /// Still there a second later.
    private func staysPresent(_ element: XCUIElement) -> Bool {
        element.exists && !pollUntil(timeout: 1) { !element.exists }
    }
}
#endif
