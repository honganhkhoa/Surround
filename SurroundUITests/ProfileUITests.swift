//
//  ProfileUITests.swift
//  SurroundUITests
//
//  Offline profile and friendship journeys. CI runs this class in its own job
//  so that neither half of the journey suite outgrows its step limit.
//

import XCTest
import UIKit

final class ProfileUITests: SurroundJourneyUITestCase {
    private func revealCustomGameControl(
        _ identifier: String,
        in app: XCUIApplication,
        matching type: XCUIElement.ElementType = .any
    ) -> XCUIElement {
        let control = element(identifier, in: app, matching: type)
        let scroll = app.scrollViews.containing(.textField, identifier: SurroundUITestContract.AccessibilityID.customGameName).firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            let safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            if control.isHittable && safeFrame.contains(control.frame) { return control }
            if control.frame.minY < safeFrame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(control.isHittable, "Expected form control \(identifier) to be visible.")
        return control
    }

    private func launchProfileContent(
        scene: SurroundUITestContract.CompatibilityScene = .home,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            scene.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
        ] + additionalLaunchArguments, orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
    }

    private func openProfileContentFromHome(in app: XCUIApplication) {
        let gameID = SurroundUITestContract.screenshotPrimaryGameID
        let row = elementAfterScrolling(SurroundUITestContract.AccessibilityID.homeGame(gameID), in: app)
        openProfileContextMenu(for: row, in: app)
        tap(requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, SurroundUITestContract.profileFixtureOpponentID),
            title: "View Profile", in: app
        ), description: "Open CopperKoi's profile", in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
    }

    @discardableResult
    private func revealProfileControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let scroll = app.scrollViews[SurroundUITestContract.AccessibilityID.screenPlayerProfile].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let interactionPoint = CGVector(dx: 0.5, dy: 0.5)
        for _ in 0..<14 {
            let safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            guard control.exists else {
                // A lazy grid does not expose the target's position until
                // its row approaches the viewport.
                scroll.swipeUp()
                continue
            }
            let targetFrame = control.frame
            let center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let visibleEnough = safeFrame.contains(targetFrame)
                || (targetFrame.height > safeFrame.height && safeFrame.contains(center))
            if visibleEnough && control.isHittable { return control }
            // Full swipes can repeatedly overshoot a large Dynamic Type
            // headline. Move toward its measured center in bounded steps.
            guard dragScrollView(
                scroll,
                axis: .vertical,
                targetFrame: validInteractionFrame(targetFrame, interactionPoint: interactionPoint),
                containerFrame: safeFrame,
                interactionPoint: interactionPoint
            ) else { break }
        }
        keepInteractionHierarchy(control, container: scroll, in: app,
                                 reason: "unable to reveal profile control \(identifier)")
        XCTFail("Expected visible profile control \(identifier).")
        return control
    }

    private func backToProfile(from navigationTitle: String, destinationID: String, in app: XCUIApplication) {
        // Regular-width layouts also expose the sidebar's navigation bar.
        // Scope Back to the destination we actually opened.
        let destination = element(destinationID, in: app)
        let navigationBar = app.navigationBars[navigationTitle].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let identifiedBack = navigationBar.buttons.matching(identifier: "BackButton").firstMatch
        let back = identifiedBack.exists ? identifiedBack : navigationBar.buttons.firstMatch
        tap(back, description: "Return to profile", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertFalse(destination.exists, "Back must leave the \(navigationTitle) destination, even when the profile shares its title.")
    }

    func testProfileActiveGamesPreviewAndNavigationReuse() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        keepScreenshot("Profile – identity and ratings", in: app)
        let activeIDs = SurroundUITestContract.profileFixtureActiveGameIDs
        for gameID in activeIDs.prefix(3) {
            revealProfileControl(SurroundUITestContract.AccessibilityID.profileActiveGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[3])).firstMatch.exists,
            "The profile preview must stop after three active games.")
        keepScreenshot("Profile – active games preview", in: app)
        let seeAll = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllActiveGames, in: app)
        tap(seeAll, description: "See all profile active games", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileActiveGames, in: app)
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[3]), in: app)
        let firstGame = element(SurroundUITestContract.AccessibilityID.profileActiveGame(activeIDs[0]), in: app)
        scrollIntoTappableArea(firstGame, in: app)
        tap(firstGame, description: "Open a profile's active game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(activeIDs[0]), in: app)
        tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
            SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        // Reuse the earlier profile. Its Back must reach Home directly,
        // rather than stacking a second profile over the game and list.
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    private func launchFriendship(
        scene: SurroundUITestContract.CompatibilityScene = .home,
        failsOnce: Bool = false,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        var arguments = [SurroundUITestContract.friendshipLaunchArgument]
        if failsOnce {
            arguments.append(SurroundUITestContract.friendshipFailsOnceLaunchArgument)
        }
        return launchProfileContent(scene: scene, additionalLaunchArguments: arguments + additionalLaunchArguments)
    }

    @discardableResult
    private func assertFriendshipState(_ state: String, in app: XCUIApplication) -> XCUIElement {
        let action = revealProfileControl(SurroundUITestContract.AccessibilityID.profileFriendshipAction, in: app)
        let labels = ["none": "Add friend", "requestSent": "Request sent", "friends": "Friends"]
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", labels[state] ?? state), object: action
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                      "Expected the profile's friendship state to become \(state).")
        return action
    }

    private func tapFriendshipDialogAction(_ identifier: String, title: String, in app: XCUIApplication) {
        let action = requiredMenuButton(identifier, title: title, in: app)
        if !action.isHittable {
            // At accessibility text sizes UIKit gives a confirmation sheet's
            // actions their own scroll view, separate from the title/message.
            // Reveal the action inside that native sheet, never in the profile
            // scroll view underneath its popover.
            let actionsScroll = app.sheets.scrollViews.containing(NSPredicate(
                format: "elementType == %lu AND (identifier == %@ OR label == %@)",
                XCUIElement.ElementType.button.rawValue, identifier, title
            )).firstMatch
            for _ in 0..<4 where !action.isHittable {
                guard actionsScroll.exists else { break }
                actionsScroll.swipeUp()
            }
            if action.isHittable {
                keepScreenshot("Friendship confirmation – revealed \(title)", in: app)
            }
        }
        tap(action, description: title, in: app)
    }

    private func openRemoveFriendConfirmation(in app: XCUIApplication) {
        tap(assertFriendshipState("friends", in: app), description: "Open friendship actions", in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.profileRemoveFriend,
                                  title: "Remove friend", in: app)
        requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                           title: "Remove friend", in: app)
    }

    private func cancelFriendshipConfirmation(
        in app: XCUIApplication,
        at dismissalPoint: XCUICoordinate,
        containing confirmation: XCUIElement,
        restoring identifier: String
    ) {
        let popover = app.popovers.firstMatch
        if popover.exists {
            // iOS 27 can use a popover on iPhone as well as iPad. Its frame
            // may cover the previously visible navigation title, so choose
            // an observed point outside the actual presented popover.
            let bounds = app.frame.insetBy(dx: 20, dy: 20)
            let presentedFrame = popover.frame
            let candidates = [
                CGPoint(x: bounds.midX, y: presentedFrame.maxY + 20),
                CGPoint(x: presentedFrame.maxX + 20, y: bounds.midY),
                CGPoint(x: presentedFrame.minX - 20, y: bounds.midY),
                CGPoint(x: bounds.midX, y: presentedFrame.minY - 20),
            ]
            guard let outside = candidates.first(where: { bounds.contains($0) && !presentedFrame.contains($0) }) else {
                XCTFail("Expected space outside the confirmation popover to cancel it.")
                return
            }
            let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: outside.x - app.frame.minX, dy: outside.y - app.frame.minY
            ))
            dismissPopover(in: app, at: point, containing: confirmation, restoring: [identifier])
            return
        }
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let cancel = app.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex.first(where: \.isHittable)
            XCTAssertNotNil(cancel, "The phone confirmation sheet must offer Cancel.")
            guard let cancel else { return }
            tap(cancel, description: "Cancel the friendship confirmation", in: app)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: confirmation
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
            element(identifier, in: app)
            return
        }
        #endif
        // Regular-width confirmation dialogs omit Cancel. Dismiss their
        // popover outside its bounds, without activating a control beneath it.
        dismissPopover(in: app, at: dismissalPoint, containing: confirmation, restoring: [identifier])
    }

    private func assertFriendRequestRemoved(_ playerID: Int, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let request = app.buttons[SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID)].firstMatch
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: request)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: timeout), .completed,
                       "A completed request must leave the Home request list.")
    }

    private func retryFriendshipError(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "A failed friendship action must explain the error.")
        tap(alert.buttons["Retry"].firstMatch, description: "Retry the failed friendship action", in: app)
    }

    private func revealHomeFriendRequest(_ playerID: Int, in app: XCUIApplication) -> XCUIElement {
        let control = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID),
                                            in: app, matching: .button)
        let scroll = element(SurroundUITestContract.AccessibilityID.screenHome, in: app, matching: .scrollView)
        let header = app.staticTexts[SurroundUITestContract.AccessibilityID.homeFriendRequests].firstMatch
        let navigationBar = app.navigationBars["Active games"].firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<10 {
            let viewport = scroll.frame.intersection(app.frame)
            var top = navigationBar.exists ? max(viewport.minY, navigationBar.frame.maxY) : viewport.minY
            if header.exists, header.frame.intersects(viewport) { top = max(top, header.frame.maxY) }
            let bottom = tabBar.exists ? min(viewport.maxY, tabBar.frame.minY) : viewport.maxY
            let safeFrame = CGRect(x: viewport.minX, y: top + 8, width: viewport.width,
                                   height: max(0, bottom - top - 16))
            if control.isHittable, safeFrame.contains(control.frame) { return control }
            if safeFrame.isEmpty {
                scroll.swipeUp()
            } else if !dragScrollView(scroll, axis: .vertical, targetFrame: control.frame,
                                      containerFrame: safeFrame, interactionPoint: CGVector(dx: 0.5, dy: 0.5)) {
                break
            }
        }
        keepInteractionHierarchy(control, container: scroll, in: app,
                                 reason: "unable to reveal friendship identity below pinned Home header")
        XCTFail("The friendship identity must fit below Home's pinned section header before tapping.")
        return control
    }

    func testFriendRequestAcceptSynchronizesProfileHomeAndOpponentPicker() {
        let app = launchFriendship()
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        let profileEntry = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID),
                                                in: app, matching: .button)
        scrollIntoTappableArea(profileEntry, in: app)
        keepScreenshot("Friendship – incoming requests on Home", in: app)
        tap(profileEntry, description: "View the incoming friend's profile", in: app)
        assertLoadedProfile(named: username, in: app)
        element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        assertFriendshipState("friends", in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        keepScreenshot("Friendship – accepted from profile", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertFriendRequestRemoved(playerID, in: app)
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(
            SurroundUITestContract.friendshipFixtureRequestPlayerIDs[1]), in: app, matching: .button)

        // The picker consumes the shared friends list. Enter from a different
        // profile so the new friend cannot appear just as a selected opponent.
        openProfileContentFromHome(in: app)
        tap(SurroundUITestContract.AccessibilityID.profileChallenge, in: app, matching: .button)
        let opponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent,
                                              in: app, matching: .button)
        tap(opponent, description: "Choose a challenge opponent", in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        let newFriend = elementAfterScrolling(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID),
                                             in: app, matching: .button)
        scrollIntoTappableArea(newFriend, in: app)
        tap(newFriend, description: "Open the accepted friend from the picker", in: app)
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
    }

    func testFriendRequestRejectionCanCancelNotifyOrStayQuiet() {
        let app = launchFriendship()
        let playerIDs = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        for (index, playerID) in playerIDs.prefix(2).enumerated() {
            let reject = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
                                               in: app, matching: .button)
            scrollIntoTappableArea(reject, in: app)
            let dismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "Active games")
            tap(reject, description: "Review rejection choices", in: app)
            let confirmation = requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                                                  title: "Reject and Let Them Know", in: app)
            requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly,
                               title: "Reject Quietly", in: app)
            if index == 0 {
                cancelFriendshipConfirmation(in: app, at: dismissalPoint, containing: confirmation,
                                             restoring: SurroundUITestContract.AccessibilityID.screenHome)
                XCTAssertTrue(reject.exists, "Cancelling must leave the request available.")
                tap(reject, description: "Reopen rejection choices", in: app)
            }
            tapFriendshipDialogAction(index == 0
                ? SurroundUITestContract.AccessibilityID.friendshipRejectQuietly
                : SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                title: index == 0 ? "Reject Quietly" : "Reject and Let Them Know", in: app)
            assertFriendRequestRemoved(playerID, in: app)
        }
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerIDs[2]),
                              in: app, matching: .button)
        keepScreenshot("Friendship – only the unanswered request remains", in: app)
    }

    func testRemovingFriendUpdatesPickerAndSendingRequestPersistsAcrossNavigation() {
        let app = launchFriendship(scene: .opponentPicker)
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        let dismissalPoint = popoverDismissalPoint(in: app, navigationTitle: "BambooPath")
        openRemoveFriendConfirmation(in: app)
        let confirmation = requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                              title: "Remove friend", in: app)
        cancelFriendshipConfirmation(in: app, at: dismissalPoint, containing: confirmation,
                                     restoring: SurroundUITestContract.AccessibilityID.screenPlayerProfile)
        assertFriendshipState("friends", in: app)
        openRemoveFriendConfirmation(in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                  title: "Remove friend", in: app)
        assertFriendshipState("none", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID)].exists,
                       "The removed friend must disappear from the picker's friends list.")

        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Find the former friend", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        tap(assertFriendshipState("none", in: app), description: "Send a friend request", in: app)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled,
                       "A sent request must not allow duplicate submissions.")
        navigateBackFromPlayerProfile(in: app)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled,
                       "Returning to the profile must retain the pending request.")
        keepScreenshot("Friendship – request sent", in: app)
    }

    func testFriendshipAcceptAndSendFailuresCanRetryWithoutLosingState() {
        let app = launchFriendship(failsOnce: true)
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let accept = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
                                           in: app, matching: .button)
        scrollIntoTappableArea(accept, in: app)
        tap(accept, description: "Accept with a simulated connection failure", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        tap(alert.buttons["Cancel"].firstMatch, description: "Dismiss the failed acceptance", in: app)
        XCTAssertTrue(accept.exists, "A failed acceptance must preserve its request.")
        XCTAssertTrue(accept.isEnabled, "A failed action must unlock its controls.")
        tap(accept, description: "Accept the retained request", in: app)
        assertFriendRequestRemoved(playerID, in: app)

        openProfileContentFromHome(in: app)
        tap(assertFriendshipState("none", in: app), description: "Send with a simulated connection failure", in: app)
        retryFriendshipError(in: app)
        XCTAssertFalse(assertFriendshipState("requestSent", in: app).isEnabled)
    }

    func testRemovingFriendFailureCanRetry() {
        let app = launchFriendship(scene: .opponentPicker, failsOnce: true)
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        openRemoveFriendConfirmation(in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRemoveConfirm,
                                  title: "Remove friend", in: app)
        retryFriendshipError(in: app)
        assertFriendshipState("none", in: app)
        navigateBackFromPlayerProfile(in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID)].exists)
    }

    func testFriendshipFailureArrivingAfterOpeningProfileCanRetryWithoutReentry() {
        let app = launchFriendship(failsOnce: true, additionalLaunchArguments: [
            SurroundUITestContract.friendshipSlowResponseLaunchArgument,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        let accept = elementAfterScrolling(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
                                           in: app, matching: .button)
        scrollIntoTappableArea(accept, in: app)
        tap(accept, description: "Start accepting the request on Home", in: app)
        tap(entry, description: "Open the sender's profile while acceptance is pending", in: app)
        assertLoadedProfile(named: username, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists,
                       "The profile must share Home's pending action and prevent another submission.")

        let failure = app.alerts.firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 20),
                      "The failure must appear on the already-open profile without leaving and reentering it.")
        tap(failure.buttons["Retry"].firstMatch, description: "Retry Home's failed acceptance from the profile", in: app)
        let friendship = app.buttons[SurroundUITestContract.AccessibilityID.profileFriendshipAction].firstMatch
        XCTAssertTrue(friendship.waitForExistence(timeout: 20))
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        assertFriendRequestRemoved(playerID, in: app)
    }

    func testFriendshipFailureArrivingAfterReturningHomeCanRetryWithoutReentry() {
        let app = launchFriendship(failsOnce: true, additionalLaunchArguments: [
            SurroundUITestContract.friendshipSlowResponseLaunchArgument,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        tap(entry, description: "Open the incoming friend's profile", in: app)
        assertLoadedProfile(named: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists,
                       "Home must share the profile's pending acceptance.")

        let failure = app.alerts.firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 20),
                      "A failure after leaving the profile must appear on Home without reopening the profile.")
        tap(failure.buttons["Retry"].firstMatch, description: "Retry the profile's failed acceptance from Home", in: app)
        assertFriendRequestRemoved(playerID, in: app, timeout: 20)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
    }

    func testFriendRequestRemainsUsableInDarkModeAtLargestDynamicType() {
        let app = launchFriendship(additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let entry = revealHomeFriendRequest(playerID, in: app)
        tap(entry, description: "Open an incoming request at the largest text size", in: app)
        assertLoadedProfile(named: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        let identity = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue("dark", in: identity, timeout: 10))
        for identifier in [
            SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
            SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
            SurroundUITestContract.AccessibilityID.profileChallenge,
            SurroundUITestContract.AccessibilityID.profileMessage,
        ] {
            XCTAssertTrue(revealProfileControl(identifier, in: app).isHittable,
                          "Each incoming-request and profile action must remain reachable at the largest text size.")
        }
        keepScreenshot("Friendship – incoming request in dark and largest Dynamic Type", in: app)
        let reject = revealProfileControl(SurroundUITestContract.AccessibilityID.friendRequestReject(playerID), in: app)
        tap(reject, description: "Reject an incoming request at the largest text size", in: app)
        tapFriendshipDialogAction(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly,
                                  title: "Reject Quietly", in: app)
        XCTAssertTrue(assertFriendshipState("none", in: app).isHittable)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        keepScreenshot("Friendship – Add friend after rejection at the largest text size", in: app)
    }

    func testProfileHistoryAndHeadToHeadUseCorrectPerspective() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        let summary = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHeadToHeadSummary, in: app)
        let summaryText = summary.label + " " + (summary.value as? String ?? "")
        for total in ["14", "9", "1"] {
            XCTAssertTrue(summaryText.contains(total), "Head-to-head must display server totals, independently of its five recent results.")
        }
        let historyIDs = SurroundUITestContract.profileFixtureHistoryGameIDs
        for (gameID, result) in zip(historyIDs, ["Win", "Loss", "Draw", "Win", "Loss"]) {
            let recent = element(SurroundUITestContract.AccessibilityID.profileHeadToHeadRecent(gameID), in: app)
            XCTAssertTrue((recent.label + " " + (recent.value as? String ?? "")).contains(result),
                          "Recent results must use the signed-in viewer's perspective.")
        }
        keepScreenshot("Profile – viewer-relative head-to-head", in: app)
        let previewCount = UIDevice.current.userInterfaceIdiom == .phone ? 2 : 4
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        for gameID in historyIDs.prefix(previewCount) {
            element(SurroundUITestContract.AccessibilityID.profileHistoryGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[previewCount])).firstMatch.exists,
            "The profile history preview must show two games on phone and four at regular width.")
        let history = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllHistory, in: app)
        tap(history, description: "See the player's complete game history", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let generalFirst = element(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        XCTAssertTrue(generalFirst.label.contains("Loss"), "General history must use CopperKoi's result, not the viewer's win.")
        XCTAssertTrue(generalFirst.label.contains("You"), "The signed-in player must use the You identity in another player's history.")
        XCTAssertFalse(generalFirst.label.contains("JuniperStone"), "The self-opponent row should not replace You with the signed-in username.")
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs.last!), in: app)
        backToProfile(from: "Game history", destinationID: SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let headToHeadHistory = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHeadToHeadHistory, in: app)
        XCTAssertTrue(headToHeadHistory.label.contains("See all games"))
        XCTAssertFalse(headToHeadHistory.label.contains("24"),
                       "The filtered history link must not imply its feed has the server record's total number of games.")
        tap(headToHeadHistory, description: "Open history against this player", in: app)
        element(SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        let filteredFirst = element(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[0]), in: app)
        XCTAssertTrue(filteredFirst.label.contains("Win"), "Head-to-head history must agree with the viewer's record.")
        XCTAssertTrue(filteredFirst.label.contains("CopperKoi"))
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs.last!), in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[5])).firstMatch.exists,
            "The filtered history must exclude CopperKoi's game against a different player.")
    }

    func testShortProfileHistoryDoesNotOfferRedundantSeeAll() {
        let app = launchProfileContent(additionalLaunchArguments: [
            SurroundUITestContract.profileShortHistoryLaunchArgument,
        ])
        openProfileContentFromHome(in: app)
        let historyIDs = SurroundUITestContract.profileFixtureHistoryGameIDs
        for gameID in historyIDs.prefix(2) {
            _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(gameID), in: app)
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileHistoryGame(historyIDs[2])).firstMatch.exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileAllHistory].exists,
                       "When every finished game is already in the preview, neither phone nor wide layouts should offer See all games.")
        keepScreenshot("Profile history – complete two-game preview", in: app)
    }

    func testProfileRatingsCategoriesAndPreferencePersistence() {
        let app = launchProfileContent()
        openProfileContentFromHome(in: app)
        for category in ["overall", "19x19", "13x13", "9x9", "blitz", "live", "correspondence"] {
            element(SurroundUITestContract.AccessibilityID.profileRatingCategory(category), in: app)
        }
        let nine = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((nine.value as? String ?? "").contains("Provisional"), "A category at deviation 160 is provisional even with a stable overall rating.")
        let overall = element(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app)
        XCTAssertFalse((overall.value as? String ?? "").contains("Provisional"))
        tap(nine, description: "Select provisional 9×9 rating", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(headline.label.contains("Provisional"))
        XCTAssertFalse(headline.label.contains("±"), "A provisional Rank headline uses its likely range instead of a deviation subtitle.")
        keepScreenshot("Profile ratings – category-specific provisional rank", in: app)
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        XCTAssertTrue(headline.label.contains("1650") || headline.label.contains("1,650"))
        XCTAssertTrue(headline.label.contains("±"), "Numeric Rating mode keeps the category's deviation, including provisional categories.")
        navigateBackFromPlayerProfile(in: app)
        openProfileContentFromHome(in: app)
        let mode = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        XCTAssertTrue(mode.buttons.element(boundBy: 1).isSelected, "The Rank/Rating preference must survive reopening a profile.")
        let reloadedHeadline = element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(reloadedHeadline.label.contains("1875") || reloadedHeadline.label.contains("1,875"))
        let thirteen = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(thirteen.value as? String, "No rated games")
        tap(thirteen, description: "Select the unrated 13×13 category", in: app)
        let missingHeadline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertEqual(missingHeadline.label, "No rated games", "A missing category needs only its explanation, without a placeholder or subtitle.")
        keepScreenshot("Profile ratings – missing 13×13 data", in: app)
    }

    func testOwnProfileOmitsOpponentSectionsAndHonorsHiddenRatings() {
        let app = launchProfileContent(scene: .settings)
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        element(SurroundUITestContract.AccessibilityID.profileRatings, in: app)
        keepScreenshot("Own profile – supporter identity and section margins", in: app)
        for identifier in [SurroundUITestContract.AccessibilityID.profileActiveGames,
                           SurroundUITestContract.AccessibilityID.profileHeadToHead] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists)
        }
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllHistory, in: app)
        keepScreenshot("Own profile – ratings and game history", in: app)
        navigateBackFromPlayerProfile(in: app)
        let hideRatings = app.switches["Hide ranks and ratings"].firstMatch
        XCTAssertTrue(hideRatings.waitForExistence(timeout: 10))
        scrollIntoTappableArea(hideRatings, in: app)
        // SwiftUI includes the wide label in a switch's accessibility frame.
        // Activate the trailing switch rather than empty label space.
        activate(hideRatings, at: CGVector(dx: 0.95, dy: 0.5))
        XCTAssertTrue(waitForValue("1", in: hideRatings, timeout: 10))
        let profileEntry = element(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        scrollIntoTappableArea(profileEntry, in: app)
        tap(profileEntry, description: "Reopen own profile with ratings hidden", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileRatings).firstMatch.exists,
            "Hide ranks and ratings must remove the entire rating section.")
        element(SurroundUITestContract.AccessibilityID.profileEdit, in: app)
        element(SurroundUITestContract.AccessibilityID.profileGameHistory, in: app)
    }

    func testProfileRatingsRemainUsableInDarkModeAtLargestDynamicType() {
        let app = launchProfileContent(scene: .settings, additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        let identity = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10), "The own-profile title remains Profile.")
        XCTAssertTrue(waitForValue("dark", in: identity, timeout: 10))
        keepScreenshot("Own profile – supporter identity in dark and largest Dynamic Type", in: app)
        let provisional = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((provisional.value as? String ?? "").contains("Provisional"))
        tap(provisional, description: "Choose provisional category at the largest text size", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(headline.label.contains("Provisional"))
        XCTAssertFalse(headline.label.contains("±"))
        keepScreenshot("Profile ratings – dark and largest Dynamic Type headline", in: app)

        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        XCTAssertTrue(headline.label.contains("1650") || headline.label.contains("1,650"))
        let missing = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(missing.value as? String, "No rated games")
        tap(missing, description: "Choose missing category at the largest text size", in: app)
        XCTAssertEqual(element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app).label, "No rated games")
        let correspondence = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("correspondence"), in: app)
        XCTAssertTrue((correspondence.value as? String ?? "").contains("1950")
            || (correspondence.value as? String ?? "").contains("1,950"))
        keepScreenshot("Profile ratings – dark and largest Dynamic Type rows", in: app)
        tap(correspondence, description: "Choose the longest category label at the largest text size", in: app)
        let finalHeadline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertTrue(finalHeadline.label.contains("1950") || finalHeadline.label.contains("1,950"))
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileHistoryGame(
            SurroundUITestContract.screenshotHistoryGameIDs[0]), in: app)
        keepScreenshot("Profile history – dark and largest Dynamic Type", in: app)
    }

    func testEmptyProfileSectionsAndIndependentCategoryRating() {
        let app = launchProfileContent(scene: .opponentPicker)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(
            SurroundUITestContract.profileFixturePickerFriendID), in: app, matching: .button)
        assertLoadedProfile(named: "BambooPath", in: app)
        for message in ["No active games", "No games together yet", "No finished games yet"] {
            XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10),
                          "An empty section must have a clear explanation: \(message).")
        }
        let overall = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app)
        XCTAssertTrue((overall.value as? String ?? "").contains("Provisional"))
        let live = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("live"), in: app)
        XCTAssertFalse((live.value as? String ?? "").contains("Provisional"),
                       "A stable category must remain stable when the overall rating is provisional.")
        tap(live, description: "Select the independently stable live rating", in: app)
        let headline = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        XCTAssertFalse(headline.label.contains("Provisional"))
        keepScreenshot("Profile – stable category despite provisional overall", in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileAllHistory].exists,
                       "An empty preview should not offer a redundant See all games action.")
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        assertNotSelected(SurroundUITestContract.AccessibilityID.opponentSelection(
            SurroundUITestContract.profileFixturePickerFriendID), in: app)
    }

    func testProfileSectionFailuresPreserveIdentityRatingsAndActions() {
        let app = launchProfileContent(scene: .activeGameBoard, additionalLaunchArguments: [
            SurroundUITestContract.profileSectionsUnavailableLaunchArgument,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
            SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        element(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
        element(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileRatings, in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileError).firstMatch.exists,
            "An unavailable section must not replace the loaded profile with a whole-page error.")
        for message in ["Couldn’t load active games", "Couldn’t load head-to-head record", "Couldn’t load game history"] {
            XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10),
                          "Missing section data must report its own error: \(message).")
        }
        let nine = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        tap(nine, description: "Select 9×9 before retrying independent profile sections", in: app)
        let headline = element(SurroundUITestContract.AccessibilityID.profileRatingHeadline, in: app)
        let selectedHeadline = headline.label
        XCTAssertTrue(selectedHeadline.contains("Provisional"))
        for retryID in [SurroundUITestContract.AccessibilityID.profileHeadToHeadRetry,
                        SurroundUITestContract.AccessibilityID.profileActiveGamesRetry,
                        SurroundUITestContract.AccessibilityID.gameHistoryRetry] {
            let retry = revealProfileControl(retryID, in: app)
            tap(retry, description: "Retry the failed profile section", in: app)
            element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.profileLoading).firstMatch.exists,
                "A section retry must retain the loaded profile instead of restarting its page load.")
            XCTAssertEqual(headline.label, selectedHeadline,
                           "A section retry must preserve the independently selected 9×9 rating category.")
            element(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
            element(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        }
        element(SurroundUITestContract.AccessibilityID.gameHistoryError, in: app)
        keepScreenshot("Profile – independent section errors retain useful content", in: app)
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        backToProfile(from: "CopperKoi", destinationID: SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.profileConversation).firstMatch.exists,
            "Returning from Message must reveal the retained profile, not an unrelated history screen.")
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(
            SurroundUITestContract.screenshotPrimaryGameID), in: app)
    }

    func testHomeGameMenusOpenOpponentProfilesWithoutOpeningGames() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])
        let games = [
            (SurroundUITestContract.screenshotPrimaryGameID,
             SurroundUITestContract.AccessibilityID.homeGame(SurroundUITestContract.screenshotPrimaryGameID),
             SurroundUITestContract.profileFixtureOpponentID, "CopperKoi"),
            (SurroundUITestContract.screenshotHistoryGameIDs[0],
             SurroundUITestContract.AccessibilityID.homeHistoryGame(SurroundUITestContract.screenshotHistoryGameIDs[0]),
             851_001, "CedarWave"),
        ]
        for (gameID, rowID, playerID, username) in games {
            let row = elementAfterScrolling(rowID, in: app)
            openProfileContextMenu(for: row, in: app)
            let profileAction = requiredMenuButton(
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, playerID),
                title: "View Profile", in: app
            )
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(
                    gameID, SurroundUITestContract.profileFixtureOwnerID
                )
            ).firstMatch.exists, "Game menus should offer the opponent, excluding the viewer.")
            tap(profileAction, description: "View \(username)'s profile", in: app)
            assertLoadedProfile(named: username, in: app)
            navigateBackFromPlayerProfile(in: app)
            element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
            XCTAssertTrue(row.exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.gameDetail(gameID)
            ).firstMatch.exists, "Opening the context-menu profile must not also open the game.")
        }
    }

    func testGameHistoryMenuOpensOpponentProfile() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameHistory.rawValue,
        ])
        let gameID = SurroundUITestContract.screenshotHistoryGameIDs[0]
        let row = element(SurroundUITestContract.AccessibilityID.homeHistoryGame(gameID), in: app)
        openProfileContextMenu(for: row, in: app)
        tap(requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 851_001),
            title: "View Profile", in: app
        ), description: "View the historical opponent's profile", in: app)
        assertLoadedProfile(named: "CedarWave", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenGameHistory, in: app)
        XCTAssertTrue(row.exists)
        // A normal row tap must keep its existing game-navigation behavior.
        tap(row, description: "Open the historical game", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
    }

    func testPublicGameMenuOffersBothPlayers() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.publicGames.rawValue,
        ])
        let gameID = SurroundUITestContract.screenshotPublicGameID
        let row = element(SurroundUITestContract.AccessibilityID.publicGame(gameID), in: app)
        for (playerID, username) in [(901_001, "MapleLeaf"), (901_002, "SilverPine")] {
            openProfileContextMenu(for: row, in: app)
            // The shared title is intentionally identical. Resolve by player
            // ID so this proves that each item selects its own participant.
            let black = element(SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 901_001), in: app)
            let white = element(SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 901_002), in: app)
            XCTAssertTrue(black.exists && white.exists)
            if playerID == 901_001 {
                keepScreenshot("Public game – profile actions for both players", in: app)
            }
            tap(element(
                SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, playerID), in: app
            ), description: "View \(username)'s profile", in: app)
            assertLoadedProfile(named: username, in: app)
            navigateBackFromPlayerProfile(in: app)
            element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
            XCTAssertTrue(row.exists)
        }
        tap(row, description: "Open the public game normally", in: app)
        element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
    }

    func testChallengeIdentityOpensProfileWithoutAccepting() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.openChallenges.rawValue,
        ])
        let entryID = SurroundUITestContract.AccessibilityID.profileChallengeEntry(91_001, 801_001)
        let entry = elementAfterScrolling(entryID, in: app, matching: .button)
        scrollIntoTappableArea(entry, in: app)
        keepScreenshot("Challenge card – compact profile target", in: app)
        tap(entry, description: "View the challenger", in: app)
        assertLoadedProfile(named: "BambooPath", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpenChallenges, in: app)
        element(entryID, in: app, matching: .button)
        XCTAssertTrue(app.buttons["Accept"].firstMatch.exists,
                      "Viewing a challenger must leave their challenge available.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testRengoPlayerMenuOpensProfileForNonOrganizer() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.rengoOpenChallenges.rawValue,
        ])
        let prefix = SurroundUITestContract.AccessibilityID.profileRengoMenuPrefix
        let avatars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        XCTAssertTrue(avatars.firstMatch.waitForExistence(timeout: 10))
        // The fixture's twenty challenges are grouped and sorted by clock.
        // Exercise the first visible participant, without hunting a specific
        // card across the entire challenge list.
        let avatar = avatars.allElementsBoundByIndex.first(where: { $0.isHittable })
            ?? avatars.firstMatch
        scrollIntoTappableArea(avatar, in: app)
        let menuID = avatar.identifier
        let identifiers = menuID.dropFirst(prefix.count).split(separator: ".")
        guard identifiers.count == 2,
              let challengeID = Int(identifiers[0]),
              let playerID = Int(identifiers[1]) else {
            XCTFail("Expected a Rengo menu identifying its challenge and player: \(menuID)")
            return
        }
        let playerLabel = avatar.label
        let username = playerLabel.range(of: " [", options: .backwards)
            .map { String(playerLabel[..<$0.lowerBound]) } ?? playerLabel
        tap(avatar, description: "Open the Rengo player's menu", in: app)
        let profileAction = requiredMenuButton(
            SurroundUITestContract.AccessibilityID.profileRengoEntry(challengeID, playerID),
            title: "View Profile", in: app
        )
        XCTAssertFalse(app.buttons["Move to White team"].exists)
        XCTAssertFalse(app.menuItems["Move to White team"].exists,
                       "A nonorganizer must not gain team-management actions.")
        tap(profileAction, description: "View the Rengo player's profile", in: app)
        assertLoadedProfile(named: username, in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpenChallenges, in: app)
        element(menuID, in: app)
    }

    func testOwnProfileFromSettingsOffersAccountActions() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.settings.rawValue,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        element(SurroundUITestContract.AccessibilityID.profileEdit, in: app)
        element(SurroundUITestContract.AccessibilityID.profileShare, in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileMessage].exists)

        keepScreenshot("Own profile – loaded from Settings", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
    }

    func testOwnProfileFromMainNavigationUsesLightAppearance() {
        assertOwnProfileAppearance(.light)
    }

    func testOwnProfileFromMainNavigationUsesDarkAppearance() {
        assertOwnProfileAppearance(.dark)
    }

    private func assertOwnProfileAppearance(_ appearance: SurroundUITestContract.Appearance) {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument,
            appearance.rawValue,
        ])
        let homeSettings = app.navigationBars.buttons["Settings"].firstMatch
        if homeSettings.waitForExistence(timeout: 2) {
            tap(homeSettings, description: "Home Settings", in: app)
        } else {
            // An expanded navigation sidebar replaces the Home toolbar button.
            tap(SurroundUITestContract.AccessibilityID.navigationSettings, in: app)
        }
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue(appearance.rawValue, in: header, timeout: 10),
                      "The profile must resolve the requested appearance, independent of the test host.")
        keepScreenshot("Own profile – \(appearance.rawValue) appearance", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
    }

    func testGameAnalysisSurvivesTabSwitchesWithAndWithoutProfile() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone,
                      "This journey exercises the regular-width analysis controls and tabs.")
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.home.rawValue,
        ])
        let game = elementAfterScrolling(
            SurroundUITestContract.AccessibilityID.homeGame(
                SurroundUITestContract.screenshotPrimaryGameID), in: app)
        scrollIntoTappableArea(game, in: app)
        tap(game, description: "Open game for analysis", in: app)
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzeToggle, in: app)
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzePrevious, in: app)
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let markerMenu = element(SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu, in: app)
        tap(markerMenu, description: "Choose analysis tool", in: app)
        tap(analyzeMenuItem(SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool("letters"),
                            catalystTitle: "Letters", in: app), description: "Letters", in: app)
        let markerPoint = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        markerPoint.click()
        #else
        markerPoint.tap()
        #endif
        let markedBoard = board.value as? String
        XCTAssertTrue(markedBoard?.contains("|marks:A=") == true)

        func selectTab(_ identifier: String) {
            let tabs = app.descendants(matching: .any).matching(identifier: identifier)
            if !tabs.allElementsBoundByIndex.contains(where: { $0.isHittable }) {
                tap(app.buttons["Toggle sidebar"], description: "Show navigation sidebar", in: app)
            }
            var visibleTab: XCUIElement?
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                visibleTab = tabs.allElementsBoundByIndex.first(where: { $0.isHittable })
                return visibleTab != nil
            }, object: nil)
            guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed,
                  let tab = visibleTab else {
                return XCTFail("Expected a visible tab: \(identifier)")
            }
            tap(tab, description: identifier, in: app)
        }

        for profileIsOpen in [false, true] {
            if profileIsOpen {
                tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
                    SurroundUITestContract.profileFixtureOpponentID), in: app, matching: .button)
                element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            }
            selectTab(SurroundUITestContract.AccessibilityID.navigationPublicGames)
            element(SurroundUITestContract.AccessibilityID.screenPublicGames, in: app)
            selectTab(SurroundUITestContract.AccessibilityID.navigationHome)
            if profileIsOpen {
                element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
                navigateBackFromPlayerProfile(in: app)
            }
            element(SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar, in: app)
            XCTAssertEqual(board.value as? String, markedBoard,
                           "Switching tabs must preserve the retained game's position and markers.")
            XCTAssertEqual(markerMenu.value as? String, "Letters, Next label: B")
        }
    }

    func testProfileActionsPreserveGameAnalysisAndMarkers() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let initialBoardValue = board.value as? String
        tap(SurroundUITestContract.AccessibilityID.gameAnalyzeNext, in: app)
        XCTAssertNotEqual(board.value as? String, initialBoardValue,
                          "Use a different position so a fixture reset cannot mimic preservation.")
        let markerMenu = element(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu,
            in: app
        )
        tap(markerMenu, description: "Analysis marker menu", in: app)
        let letters = analyzeMenuItem(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerTool("letters"),
            catalystTitle: "Letters",
            in: app
        )
        tap(letters, description: "Letters marker tool", in: app)
        let markerPoint = board.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        #if targetEnvironment(macCatalyst)
        markerPoint.click()
        #else
        markerPoint.tap()
        #endif
        let markedBoardValue = board.value as? String
        XCTAssertTrue(markedBoardValue?.contains("|marks:A=") == true)

        let opponentID = SurroundUITestContract.profileFixtureOpponentID
        #if targetEnvironment(macCatalyst)
        let profileEntryID = SurroundUITestContract.AccessibilityID
            .profileBannerAvatarEntry(opponentID)
        #else
        // Compact analysis replaces the banner with the move tree; its
        // opponent title opens the same profile without leaving analysis.
        let profileEntryID = UIDevice.current.userInterfaceIdiom == .phone
            ? SurroundUITestContract.AccessibilityID.profileGameTitleEntry(opponentID)
            : SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(opponentID)
        #endif
        tap(
            profileEntryID,
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        keepScreenshot("Other profile – opened from analysis", in: app)

        tap(SurroundUITestContract.AccessibilityID.profileChallenge, in: app)
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        XCTAssertTrue(app.staticTexts["CopperKoi"].exists,
                      "Challenge should preselect the profile's player.")
        backToProfile(from: "Challenge", destinationID: SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)

        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        element(SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        XCTAssertTrue(app.navigationBars["CopperKoi"].exists,
                      "Message should open the profile's conversation.")
        backToProfile(from: "CopperKoi", destinationID: SurroundUITestContract.AccessibilityID.profileConversation, in: app)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar, in: app)
        XCTAssertEqual(board.value as? String, markedBoardValue,
                       "Profile navigation must preserve the analysis position and markups.")
        XCTAssertEqual(markerMenu.value as? String, "Letters, Next label: B",
                       "The selected analysis tool must survive the profile round trip.")
    }

    func testChatSenderProfilePreservesSelectedChatPreview() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameChat.rawValue,
        ])
        dismissSoftwareKeyboardIfNeeded(in: app)
        let selectedLine = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-1"
        )
        let otherLine = SurroundUITestContract.AccessibilityID.gameChatLine(
            "app-store-chat-2"
        )
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            // After dismissing the keyboard, the short compact chat viewport
            // can retain an unmaterialized first lazy row even at scroll 0%.
            // Expand chat with its normal control before selecting that row.
            tap(SurroundUITestContract.AccessibilityID.gameChatBoardHide, in: app)
        }
        #endif
        tapChatItem(selectedLine, in: app, matching: .button)
        assertSelected(selectedLine, in: app)
        let selectedBubble = element(selectedLine, in: app, matching: .button)
        XCTAssertTrue(selectedBubble.label.contains("JuniperStone"),
                      "A message must announce its sender independently of the profile button.")
        XCTAssertTrue(selectedBubble.label.contains("Good luck — have a great game!"))
        #if !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone {
            tap(SurroundUITestContract.AccessibilityID.gameChatBoardShow, in: app)
        }
        #endif
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let previewValue = board.value as? String
        XCTAssertNotNil(previewValue)

        tapChatItem(
            SurroundUITestContract.AccessibilityID.profileChatEntry("app-store-chat-2"),
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        navigateBackFromPlayerProfile(in: app)

        assertSelected(selectedLine, in: app)
        assertNotSelected(otherLine, in: app)
        XCTAssertEqual(board.value as? String, previewValue,
                       "Opening a sender profile must keep the selected chat preview.")
    }

    func testPickerProfilePreservesSearchWithoutSelectingOpponent() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.opponentPicker.rawValue,
        ])
        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Search opponents", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        let playerID = SurroundUITestContract.profileFixturePickerFriendID
        let selectionID = SurroundUITestContract.AccessibilityID.opponentSelection(playerID)
        assertNotSelected(selectionID, in: app)
        tap(
            SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID),
            in: app,
            matching: .button
        )
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        element(SurroundUITestContract.AccessibilityID.profileSelectOpponent, in: app, matching: .button)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertEqual(search.value as? String, "Bamboo")
        assertNotSelected(selectionID, in: app)
        tap(selectionID, in: app, matching: .button)
        assertSelected(selectionID, in: app)
    }

    func testPickerProfilesSelectDifferentOpponentsWithoutReplacingEditedChallenge() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.customGame.rawValue,
        ])
        let draftName = "Profile draft retained"
        let name = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameName, in: app, matching: .textField)
        tap(name, description: "Challenge game name", in: app)
        let oldName = name.value as? String ?? ""
        let trailingEdge = name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        trailingEdge.click()
        #else
        trailingEdge.tap()
        #endif
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + draftName + "\n")
        XCTAssertTrue(waitForValue(draftName, in: name, timeout: 10))

        _ = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameSpeed, in: app, matching: .segmentedControl)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.customGameSpeed, app: app)
        _ = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponentMode, in: app, matching: .segmentedControl)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.customGameOpponentMode, app: app)

        for (query, playerID, username) in [
            ("Bamboo", 801_001, "BambooPath"),
            ("Misty", 801_002, "MistyMountain"),
        ] {
            let opponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app, matching: .button)
            tap(opponent, description: "Choose draft opponent", in: app)
            let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
            tap(search, description: "Search draft opponents", in: app)
            search.typeText(query + "\n")
            XCTAssertTrue(waitForValue(query, in: search, timeout: 10))
            tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
            element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
            tap(SurroundUITestContract.AccessibilityID.profileSelectOpponent, in: app, matching: .button)

            element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.screenPlayerProfile).firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(identifier: SurroundUITestContract.AccessibilityID.screenOpponentPicker).firstMatch.exists)
            let selectedOpponent = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app, matching: .button)
            XCTAssertTrue(selectedOpponent.label.contains(username), "The existing draft should use the newly selected opponent.")
            let preservedName = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameName, in: app, matching: .textField)
            XCTAssertEqual(preservedName.value as? String, draftName)
            let speed = revealCustomGameControl(SurroundUITestContract.AccessibilityID.customGameSpeed, in: app, matching: .segmentedControl)
            XCTAssertTrue(speed.buttons.element(boundBy: 1).isSelected,
                          "Profile selection must retain the draft's correspondence setting.")
        }
    }

    func testSavedSettingsProfileBackPreservesPickerWithoutSubmittingChallenge() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.preferredSettings.rawValue,
        ])
        // SwiftUI applies the card's identifier to its child buttons.
        let chooseOpponent = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            SurroundUITestContract.AccessibilityID.preferredSetting(0), "Select your opponent "
        )).firstMatch
        tap(chooseOpponent, description: "Choose saved-setting opponent", in: app)
        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Search saved-setting opponents", in: app)
        search.typeText("Bamboo\n")
        XCTAssertTrue(waitForValue("Bamboo", in: search, timeout: 10))
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(801_001), in: app, matching: .button)
        element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        element(SurroundUITestContract.AccessibilityID.profileChallengeWithSettings, in: app, matching: .button)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileSelectOpponent].exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileChallenge].exists)
        navigateBackFromPlayerProfile(in: app)

        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertEqual(search.value as? String, "Bamboo")
        assertNotSelected(SurroundUITestContract.AccessibilityID.opponentSelection(801001), in: app)
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "BackButton", "Preferred Settings"
        )).firstMatch
        tap(back, description: "Cancel saved-setting opponent selection", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPreferredSettings, in: app)
        XCTAssertTrue(chooseOpponent.isEnabled)
    }

    func testUnavailableProfileCanRetryAndNavigateBack() {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.settings.rawValue,
            SurroundUITestContract.unavailableProfileLaunchArgument,
        ])
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        element(SurroundUITestContract.AccessibilityID.profileError, in: app)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.profileLoaded)
            .firstMatch.exists)
        tap(SurroundUITestContract.AccessibilityID.profileRetry, in: app)
        element(SurroundUITestContract.AccessibilityID.profileError, in: app)
        keepScreenshot("Profile – unavailable with retry", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
    }
}
