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
        let center = CGVector(dx: 0.5, dy: 0.5)
        for _ in 0..<12 {
            let safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            if control.isHittable && safeFrame.contains(control.frame) { return control }
            // A full swipe on an 11-inch iPad overshoots the control and is
            // still scrolling when the next frame is read, so the search can
            // swing past it until it runs out. Move toward it in bounded steps.
            guard dragScrollView(
                scroll,
                axis: .vertical,
                targetFrame: validInteractionFrame(control.frame, interactionPoint: center),
                containerFrame: safeFrame,
                interactionPoint: center
            ) else { break }
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
        tap(openProfileContextMenu(
            for: row,
            expecting: SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, SurroundUITestContract.profileFixtureOpponentID),
            in: app
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
            var safeFrame = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            // The scroll view extends behind system chrome. A large history
            // card can exceed the visible reading area even when it is shorter
            // than the full-screen accessibility frame.
            let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
                .filter { !$0.isEmpty && $0.intersects(safeFrame) }
            if let top = bars.map(\.maxY).max(), top > safeFrame.minY {
                safeFrame = CGRect(x: safeFrame.minX, y: top + 12,
                                   width: safeFrame.width,
                                   height: max(0, safeFrame.maxY - top - 12))
            }
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
                interactionPoint: interactionPoint,
                dragVelocity: XCUIGestureVelocity(rawValue: 60),
                dragHoldDuration: 0.2
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
        scene: SurroundUITestContract.CompatibilityScene = .opponentPicker,
        failsOnce: Bool = false,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        var arguments = [SurroundUITestContract.friendshipLaunchArgument]
        if failsOnce {
            arguments.append(SurroundUITestContract.friendshipFailsOnceLaunchArgument)
        }
        return launchProfileContent(scene: scene, additionalLaunchArguments: arguments + additionalLaunchArguments)
    }

    private func setFriendshipPickerSearch(_ query: String, in app: XCUIApplication) {
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        let search = element(SurroundUITestContract.AccessibilityID.opponentSearch, in: app)
        tap(search, description: "Search friendship profiles", in: app)
        let oldValue = search.value as? String ?? ""
        let oldText = oldValue == search.placeholderValue ? "" : oldValue
        let end = search.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        #if targetEnvironment(macCatalyst)
        end.click()
        #else
        end.tap()
        #endif
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldText.count) + query + "\n")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = search.value as? String ?? ""
            return value == query || (query.isEmpty && value == search.placeholderValue)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                       "The picker should retain the requested search text.")
    }

    private func openFriendshipProfileFromPicker(_ playerID: Int, username: String, in app: XCUIApplication) {
        setFriendshipPickerSearch(username, in: app)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: username, in: app)
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
        let request = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.profileFriendRequest).firstMatch
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: request)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: timeout), .completed,
                       "A completed request must leave the sender profile's incoming-request banner.")
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestReject(playerID)].exists)
    }

    private func retryFriendshipError(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "A failed friendship action must explain the error.")
        tap(alert.buttons["Retry"].firstMatch, description: "Retry the failed friendship action", in: app)
    }
    func testIPadAccountSheetsShareEntryPointsAndPreserveSelectedTab() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This prototype uses iPad account sheets.")
        #else
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "This prototype preserves the existing phone account navigation.")
        let app = launchProfileContent(additionalLaunchArguments: [
            SurroundUITestContract.messagesContentLaunchArgument,
        ])
        let id = SurroundUITestContract.AccessibilityID.self
        let peerID = 765_826
        let draft = "Unsent draft while trying iPad account sheets"

        func assertAccountTabsAbsent() {
            for (identifier, title) in [(id.navigationProfile, "Profile"), (id.navigationSettings, "Settings")] {
                XCTAssertFalse(app.tabBars.buttons[title].exists,
                               "Account actions must not add a \(title) top tab.")
                XCTAssertFalse(app.tabBars.descendants(matching: .any)
                    .matching(identifier: identifier).firstMatch.exists)
            }
        }

        func dismissAccountSheet(returningTo destinationID: String) {
            let done = element("account.sheet.done", in: app, matching: .button)
            tap(done, description: "Dismiss the account sheet", in: app)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: done
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: stateSettleTimeout), .completed,
                           "Done must dismiss the account sheet.")
            XCTAssertTrue(element(destinationID, in: app).isHittable,
                          "Done must reveal the previously selected primary tab.")
            assertAccountTabsAbsent()
        }

        func visibleSidebarRow(_ identifier: String) -> XCUIElement? {
            let cells = app.cells.matching(identifier: identifier).allElementsBoundByIndex
            return cells.first(where: { $0.isHittable })
                ?? app.descendants(matching: .any).matching(identifier: identifier)
                    .allElementsBoundByIndex.first(where: { $0.elementType != .staticText && $0.isHittable })
        }

        func openSidebarAccountSheet(_ identifier: String, title: String) {
            if visibleSidebarRow(identifier) == nil {
                tap(app.buttons["Toggle sidebar"].firstMatch,
                    description: "Show the native navigation sidebar", in: app)
            }
            var entry: XCUIElement?
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                entry = visibleSidebarRow(identifier)
                return entry != nil
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                           "The native \(title) sidebar row must remain available.")
            guard let entry,
                  let messages = visibleSidebarRow(id.navigationMessages),
                  let profile = visibleSidebarRow(id.navigationProfile),
                  let settings = visibleSidebarRow(id.navigationSettings),
                  let about = visibleSidebarRow(id.navigationAbout),
                  let web = visibleSidebarRow(id.navigationBrowser) else {
                return XCTFail("Expected the original native sidebar rows.")
            }
            let surround = app.staticTexts["Surround"].firstMatch
            XCTAssertTrue(surround.exists && surround.isHittable)
            XCTAssertLessThan(messages.frame.midY, profile.frame.midY)
            XCTAssertLessThan(profile.frame.midY, surround.frame.midY)
            XCTAssertLessThan(settings.frame.midY, about.frame.midY)
            XCTAssertTrue(about.label.contains("About & Support"),
                          "The sidebar must retain the full About & Support label.")
            XCTAssertLessThan(about.frame.midY, web.frame.midY)
            tap(entry, description: "Open native sidebar \(title)", in: app)
        }

        func assertConversationDraftRetained() {
            let composers = app.textFields.matching(identifier: id.privateMessageComposer)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let active = composers.allElementsBoundByIndex.filter { $0.isHittable }
                return active.count == 1 && active[0].placeholderValue == "Message hakhoa"
                    && active[0].value as? String == draft
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                           "The selected Messages peer and its unsent draft must survive the sheet.")
            let selectedPeer = element(id.profileMessageToolbarEntry(peerID), in: app)
            XCTAssertTrue(selectedPeer.isHittable && selectedPeer.label.contains("hakhoa"))
        }

        assertAccountTabsAbsent()
        selectMainNavigation(id.navigationMessages, in: app)
        element(id.screenMessages, in: app)
        let inbox = element("messages.inboxScroll", in: app, matching: .scrollView)
        tap(elementAfterScrolling(id.privateMessageRow(peerID), in: app, within: inbox, matching: .button),
            description: "Select hakhoa's offline conversation", in: app)
        let composer = element(id.privateMessageComposer, in: app, matching: .textField)
        XCTAssertEqual(composer.placeholderValue, "Message hakhoa")
        tap(composer, description: "Write a draft before opening account sheets", in: app)
        composer.typeText(String(draft.prefix(1)))
        XCTAssertTrue(waitForValue(String(draft.prefix(1)), in: composer, timeout: 10))
        composer.typeText(String(draft.dropFirst()))
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))

        for visit in 1...2 {
            openSidebarAccountSheet(id.navigationProfile, title: "Profile")
            assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
            element("account.sheet.done", in: app, matching: .button)
            keepScreenshot("iPad prototype – sidebar Profile over Messages visit \(visit)", in: app)
            dismissAccountSheet(returningTo: id.screenMessages)
            assertConversationDraftRetained()
        }

        openSidebarAccountSheet(id.navigationSettings, title: "Settings")
        element(id.screenSettings, in: app)
        tap(id.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        navigateBackFromPlayerProfile(in: app)
        element(id.screenSettings, in: app)
        keepScreenshot("iPad prototype – Settings after nested Profile Back", in: app)
        dismissAccountSheet(returningTo: id.screenMessages)
        assertConversationDraftRetained()

        tap(id.profileMessageToolbarEntry(peerID), in: app, matching: .button)
        assertLoadedProfile(named: "hakhoa", in: app)
        openSidebarAccountSheet(id.navigationSettings, title: "Settings")
        element(id.screenSettings, in: app)
        dismissAccountSheet(returningTo: id.screenPlayerProfile)
        assertLoadedProfile(named: "hakhoa", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(id.screenMessages, in: app)
        assertConversationDraftRetained()
        keepScreenshot("iPad prototype – Messages stack and draft after modal visits", in: app)

        selectMainNavigation(id.navigationPublicGames, in: app)
        element(id.screenPublicGames, in: app)
        selectMainNavigation(id.navigationMessages, in: app)
        element(id.screenMessages, in: app)
        assertConversationDraftRetained()

        selectMainNavigation(id.navigationHome, in: app)
        element(id.screenHome, in: app)
        let account = app.buttons[id.accountMenu].firstMatch
        if !account.exists || !account.isHittable {
            let hideSidebar = app.buttons["Hide Sidebar"].firstMatch
            let toggleSidebar = app.buttons["Toggle sidebar"].firstMatch
            tap(hideSidebar.exists ? hideSidebar : toggleSidebar,
                description: "Show the top tab bar and avatar menu", in: app)
        }
        for (identifier, title) in [(id.navigationHome, "Home"),
                                    (id.navigationPublicGames, "Public games"),
                                    (id.navigationMessages, "Messages")] {
            let primary = app.buttons[identifier].firstMatch
            XCTAssertTrue(primary.waitForExistence(timeout: 10),
                          "The top bar must retain an independent \(title) control.")
            XCTAssertTrue(primary.isHittable,
                          "The \(title) control must be visible without opening a group menu.")
        }
        let about = app.buttons[id.navigationAbout].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 10) && about.isHittable)
        XCTAssertEqual(about.label, "About")
        tap(about, description: "Open the localized About top tab", in: app)
        element(id.screenAbout, in: app)
        selectMainNavigation(id.navigationHome, in: app)
        element(id.screenHome, in: app)
        keepScreenshot("iPad prototype – independent primary top controls", in: app)
        tap(id.accountMenu, in: app, matching: .button)
        tap(requiredMenuButton(id.accountMenuProfile, title: "Profile", in: app),
            description: "Open avatar Profile sheet", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        let history = revealProfileControl(id.profileAllHistory, in: app)
        tap(history, description: "Open history inside the Profile sheet", in: app)
        element(id.screenProfileGameHistory, in: app)
        keepScreenshot("iPad prototype – Profile sheet nested game history", in: app)
        backToProfile(from: "Game history", destinationID: id.screenProfileGameHistory, in: app)
        element("account.sheet.done", in: app, matching: .button)
        dismissAccountSheet(returningTo: id.screenHome)

        tap(id.accountMenu, in: app, matching: .button)
        tap(requiredMenuButton(id.accountMenuSettings, title: "Settings", in: app),
            description: "Open avatar Settings sheet", in: app)
        element(id.screenSettings, in: app)
        keepScreenshot("iPad prototype – avatar Settings sheet", in: app)
        dismissAccountSheet(returningTo: id.screenHome)
        #endif
    }

    func testCompactAccountMenuPushesOwnProfileAndOpensSettings() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                      "The avatar account menu uses the compact iPhone layout.")
        let app = launchProfileContent(additionalLaunchArguments: [
            SurroundUITestContract.friendshipLaunchArgument,
        ])
        let account = element(SurroundUITestContract.AccessibilityID.accountMenu, in: app, matching: .button)
        let originalTabCount = app.tabBars.buttons.count
        XCTAssertTrue((account.value as? String ?? "").contains("JuniperStone"),
                      "The avatar menu must announce the current user.")
        tap(account, description: "Open account menu", in: app)
        XCTAssertFalse(menuButton("account.friend-requests", title: "Friend requests", in: app).exists,
                       "The account menu must not offer the removed Friend requests shortcut.")
        requiredMenuButton(SurroundUITestContract.AccessibilityID.accountMenuSettings,
                           title: "Settings", in: app)
        requiredMenuButton(SurroundUITestContract.AccessibilityID.accountMenuLogout,
                           title: "Log out", in: app)
        tap(requiredMenuButton(SurroundUITestContract.AccessibilityID.accountMenuProfile,
                               title: "Profile", in: app), description: "Open own Profile", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        XCTAssertFalse(app.tabBars.buttons["Profile"].exists,
                       "Opening the own profile must not add a temporary Profile tab.")
        XCTAssertFalse(app.tabBars.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationProfile).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "profile.friend-requests").firstMatch.exists,
                       "The own profile must not contain the removed incoming-request list.")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "friend-request.profile.")).firstMatch.exists)
        keepScreenshot("Own profile – pushed from the account menu", in: app)
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        XCTAssertEqual(app.tabBars.buttons.count, originalTabCount,
                       "Returning from Profile must preserve the original main navigation tabs.")
        tap(SurroundUITestContract.AccessibilityID.accountMenu, in: app, matching: .button)
        tap(requiredMenuButton(SurroundUITestContract.AccessibilityID.accountMenuSettings,
                               title: "Settings", in: app), description: "Open Settings", in: app)
        let settingsScreen = element(SurroundUITestContract.AccessibilityID.screenSettings, in: app)
        let settingsBar = app.navigationBars["Settings"].firstMatch
        let settingsDone = settingsBar.buttons["Done"].firstMatch
        XCTAssertTrue(settingsDone.waitForExistence(timeout: 10))
        let homeScreen = app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.screenHome).firstMatch
        let doneFrameBeforeTap = settingsDone.frame
        func recordSettingsDismissalState(_ phase: String) {
            let state = XCTAttachment(string: """
                Phase: \(phase)
                Settings exists: \(settingsScreen.exists)
                Settings Done exists: \(settingsDone.exists)
                Home exists: \(homeScreen.exists)
                Tap target: Settings navigation bar's Done button
                Done frame before tap: \(doneFrameBeforeTap)
                Done frame center: \(CGPoint(x: doneFrameBeforeTap.midX, y: doneFrameBeforeTap.midY))
                """)
            state.name = "Settings dismissal state – \(phase)"
            state.lifetime = .keepAlways
            add(state)
        }
        recordSettingsDismissalState("before Done")
        tap(settingsDone, description: "Dismiss Settings to return to Home", in: app)
        let settingsDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: settingsScreen
        )
        let dismissalResult = XCTWaiter.wait(for: [settingsDismissed], timeout: stateSettleTimeout)
        recordSettingsDismissalState("after Done wait: \(dismissalResult)")
        if dismissalResult != .completed {
            keepScreenshot("Settings dismissal failed after Done", in: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy – Settings dismissal failed after Done"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(dismissalResult, .completed, "Done must dismiss Settings and return to Home.")
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
        tap(SurroundUITestContract.AccessibilityID.accountMenu, in: app, matching: .button)
        tap(requiredMenuButton(SurroundUITestContract.AccessibilityID.accountMenuLogout,
                               title: "Log out", in: app), description: "Log out from the account menu", in: app)
        let signIn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Sign in to your OGS account")).firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "Logging out should show the Welcome sign-in action.")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.navigationMessages).firstMatch.exists,
            "Messages navigation must disappear after logging out.")
        XCTAssertFalse(app.tabBars.buttons["Messages"].exists)
    }

    func testFriendRequestAcceptSynchronizesProfileAndOpponentPicker() {
        let app = launchFriendship()
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        openFriendshipProfileFromPicker(playerID, username: username, in: app)
        element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        assertFriendshipState("friends", in: app)
        assertFriendRequestRemoved(playerID, in: app)
        keepScreenshot("Friendship – accepted from the sender profile", in: app)
        navigateBackFromPlayerProfile(in: app)

        // Clear the search to prove membership in the picker's friends list,
        // rather than merely finding the same user in cached search results.
        setFriendshipPickerSearch("", in: app)
        let newFriend = elementAfterScrolling(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID),
                                             in: app, matching: .button)
        scrollIntoTappableArea(newFriend, in: app)
        tap(newFriend, description: "Open the accepted friend from the friends list", in: app)
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
        assertFriendRequestRemoved(playerID, in: app)
    }

    func testFriendRequestRejectionCanCancelNotifyOrStayQuiet() {
        let app = launchFriendship()
        let playerIDs = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        let usernames = SurroundUITestContract.friendshipFixtureRequestUsernames
        for (index, playerID) in playerIDs.prefix(2).enumerated() {
            openFriendshipProfileFromPicker(playerID, username: usernames[index], in: app)
            let reject = revealProfileControl(SurroundUITestContract.AccessibilityID.friendRequestReject(playerID), in: app)
            let dismissalPoint = popoverDismissalPoint(in: app, navigationTitle: usernames[index])
            tap(reject, description: "Review rejection choices", in: app)
            let confirmation = requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                                                  title: "Reject and Let Them Know", in: app)
            requiredMenuButton(SurroundUITestContract.AccessibilityID.friendshipRejectQuietly,
                               title: "Reject Quietly", in: app)
            if index == 0 {
                cancelFriendshipConfirmation(in: app, at: dismissalPoint, containing: confirmation,
                                             restoring: SurroundUITestContract.AccessibilityID.screenPlayerProfile)
                XCTAssertTrue(reject.exists, "Cancelling must leave the request available.")
                tap(reject, description: "Reopen rejection choices", in: app)
            }
            tapFriendshipDialogAction(index == 0
                ? SurroundUITestContract.AccessibilityID.friendshipRejectQuietly
                : SurroundUITestContract.AccessibilityID.friendshipRejectNotify,
                title: index == 0 ? "Reject Quietly" : "Reject and Let Them Know", in: app)
            assertFriendshipState("none", in: app)
            assertFriendRequestRemoved(playerID, in: app)
            navigateBackFromPlayerProfile(in: app)
        }
        openFriendshipProfileFromPicker(playerIDs[2], username: usernames[2], in: app)
        element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerIDs[2]), in: app)
        keepScreenshot("Friendship – the unanswered sender still offers its request", in: app)
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
        openFriendshipProfileFromPicker(playerID,
                                       username: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        let accept = revealProfileControl(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app)
        tap(accept, description: "Accept with a simulated connection failure", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        tap(alert.buttons["Cancel"].firstMatch, description: "Dismiss the failed acceptance", in: app)
        XCTAssertTrue(accept.exists, "A failed acceptance must preserve its request.")
        XCTAssertTrue(accept.isEnabled, "A failed action must unlock its controls.")
        tap(accept, description: "Accept the retained request", in: app)
        assertFriendshipState("friends", in: app)
        assertFriendRequestRemoved(playerID, in: app)
        navigateBackFromPlayerProfile(in: app)

        openFriendshipProfileFromPicker(SurroundUITestContract.profileFixtureOpponentID,
                                       username: "CopperKoi", in: app)
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

    private func launchPendingFriendshipAcceptance() -> XCUIApplication {
        let app = launchFriendship(failsOnce: true, additionalLaunchArguments: [
            SurroundUITestContract.friendshipGatedResponseLaunchArgument,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        openFriendshipProfileFromPicker(playerID, username: username, in: app)
        tap(SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID), in: app, matching: .button)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists,
                       "Pending acceptance must prevent another submission.")
        let release = element(SurroundUITestContract.AccessibilityID.friendshipReleaseResponse,
                              in: app, matching: .button)
        XCTAssertTrue(waitForValue("held", in: release, timeout: 10),
                      "The fixture must hold the response before navigating away.")
        XCTAssertTrue(release.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        return app
    }

    private func releaseHeldFriendshipResponse(in app: XCUIApplication) -> XCUIElement {
        let release = element(SurroundUITestContract.AccessibilityID.friendshipReleaseResponse,
                              in: app, matching: .button)
        XCTAssertTrue(waitForValue("held", in: release, timeout: 10),
                      "The response must remain pending until the destination is visible.")
        tap(release, description: "Deliver the held friendship failure", in: app)
        return release
    }

    func testFriendshipFailureArrivingOnPickerSurvivesProfileReentry() {
        let app = launchPendingFriendshipAcceptance()
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.screenPlayerProfile).firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let release = releaseHeldFriendshipResponse(in: app)
        XCTAssertTrue(waitForValue("delivered", in: release, timeout: 10),
                      "The failure must finish on the picker before reopening the sender profile.")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: SurroundUITestContract.AccessibilityID.screenPlayerProfile).firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "The closed sender profile must not present an alert over the picker.")
        keepScreenshot("Friendship – failure delivered while the sender profile is closed", in: app)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        retryFriendshipError(in: app)
        assertLoadedProfile(named: username, in: app)
        assertFriendshipState("friends", in: app)
        assertFriendRequestRemoved(playerID, in: app)
    }

    func testFriendshipFailureArrivingOnReopenedProfileCanRetry() {
        let app = launchPendingFriendshipAcceptance()
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        navigateBackFromPlayerProfile(in: app)
        element(SurroundUITestContract.AccessibilityID.screenOpponentPicker, in: app)
        tap(SurroundUITestContract.AccessibilityID.profilePickerEntry(playerID), in: app, matching: .button)
        assertLoadedProfile(named: username, in: app)
        element(SurroundUITestContract.AccessibilityID.friendRequestBusy(playerID), in: app)
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID)].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists,
                       "The reopened profile must be visible before the held failure arrives.")
        keepScreenshot("Friendship – reopened sender profile before response delivery", in: app)
        _ = releaseHeldFriendshipResponse(in: app)
        retryFriendshipError(in: app)
        assertFriendshipState("friends", in: app)
        assertFriendRequestRemoved(playerID, in: app)
    }

    func testFriendRequestRemainsUsableInDarkModeAtLargestDynamicType() {
        let app = launchFriendship(additionalLaunchArguments: [
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        openFriendshipProfileFromPicker(playerID,
                                       username: SurroundUITestContract.friendshipFixtureRequestUsernames[0], in: app)
        let identity = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue("dark", in: identity, timeout: 10))
        for identifier in [
            SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
            SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
            SurroundUITestContract.AccessibilityID.profileSelectOpponent,
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

    func testHistoryKeepsResultsWhenOneBoardPreviewIsUnavailable() {
        let app = launchProfileContent(additionalLaunchArguments: [
            SurroundUITestContract.historyPreviewUnavailableLaunchArgument,
        ])
        openProfileContentFromHome(in: app)
        let ids = SurroundUITestContract.profileFixtureHistoryGameIDs
        let firstID = SurroundUITestContract.AccessibilityID.profileHistoryGame(ids[0])
        let secondID = SurroundUITestContract.AccessibilityID.profileHistoryGame(ids[1])
        let first = revealProfileControl(firstID, in: app)
        let previewFailed = NSPredicate(format: "label CONTAINS %@", "Board unavailable")
        expectation(for: previewFailed, evaluatedWith: first)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(first.label.contains("Loss"))
        XCTAssertTrue(first.label.contains("Resignation"))
        XCTAssertTrue(first.label.contains("Board unavailable"),
                      "The row must distinguish a missing replay from an empty final board.")
        let second = revealProfileControl(secondID, in: app)
        XCTAssertTrue(second.label.contains("Win"))
        XCTAssertFalse(second.label.contains("Board unavailable"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameHistoryError).firstMatch.exists,
            "One replay failure must not mark the successful history listing as failed.")
        keepScreenshot("Profile history – one unavailable board retains valid results", in: app)

        tap(revealProfileControl(SurroundUITestContract.AccessibilityID.profileHeadToHeadHistory, in: app),
            description: "Open head-to-head history with one unavailable replay", in: app)
        let filtered = element(firstID, in: app)
        XCTAssertTrue(filtered.label.contains("Win"), "The listing keeps the viewer's head-to-head perspective.")
        XCTAssertTrue(filtered.label.contains("CopperKoi"))
        XCTAssertTrue(filtered.label.contains("Board unavailable"))
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(ids.last!), in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameHistoryError).firstMatch.exists)
        keepScreenshot("Head-to-head history – remaining pages survive a preview failure", in: app)

        backToProfile(from: "Game history", destinationID: SurroundUITestContract.AccessibilityID.screenProfileGameHistory, in: app)
        tap(revealProfileControl(SurroundUITestContract.AccessibilityID.profileAllHistory, in: app),
            description: "Reopen general history after preview demand was cancelled", in: app)
        let reopened = element(firstID, in: app)
        XCTAssertTrue(reopened.label.contains("Loss"))
        XCTAssertTrue(reopened.label.contains("Board unavailable"))
        elementAfterScrolling(SurroundUITestContract.AccessibilityID.profileHistoryGame(ids.last!), in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
            SurroundUITestContract.AccessibilityID.gameHistoryError).firstMatch.exists)
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
            let identifier = SurroundUITestContract.AccessibilityID.profileRatingCategory(category)
            element(identifier, in: app)
            XCTAssertFalse(app.buttons[identifier].exists, "Rating categories are display-only cells.")
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "profile.rating-headline").firstMatch.exists,
                       "The category table must not repeat a large selected-category headline.")
        let nine = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((nine.value as? String ?? "").contains("Provisional"), "A category at deviation 160 is provisional even with a stable overall rating.")
        XCTAssertTrue((nine.value as? String ?? "").contains("Likely range"))
        XCTAssertFalse((nine.value as? String ?? "").contains("±"))
        let overall = element(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app)
        XCTAssertFalse((overall.value as? String ?? "").contains("Provisional"))
        let key = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingKey, in: app)
        XCTAssertEqual(key.label, "? means provisional — the range shows the likely rank.")
        keepScreenshot("Profile ratings – seven display-only rank categories", in: app)

        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        XCTAssertTrue((nine.value as? String ?? "").contains("1650"))
        XCTAssertTrue((nine.value as? String ?? "").contains("±160"))
        XCTAssertTrue((nine.value as? String ?? "").contains("Provisional"),
                      "The numeric provisional state must be explicit to VoiceOver independently of gray text.")
        XCTAssertTrue((overall.value as? String ?? "").contains("1875"), "The switch updates every category.")
        let correspondence = element(SurroundUITestContract.AccessibilityID.profileRatingCategory("correspondence"), in: app)
        XCTAssertTrue((correspondence.value as? String ?? "").contains("1950"))
        XCTAssertTrue(key.label.contains("Gray ratings are provisional"))
        let thirteen = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(thirteen.value as? String, "No rated games")
        keepScreenshot("Profile ratings – all numeric categories and missing 13×13", in: app)

        navigateBackFromPlayerProfile(in: app)
        openProfileContentFromHome(in: app)
        let mode = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        XCTAssertTrue(mode.buttons.element(boundBy: 1).isSelected, "The Rank/Rating preference must survive reopening a profile.")
        XCTAssertTrue((element(SurroundUITestContract.AccessibilityID.profileRatingCategory("overall"), in: app).value as? String ?? "").contains("1875"))
        XCTAssertTrue((element(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app).value as? String ?? "").contains("1650"))
    }

    func testOwnProfileOmitsOpponentSectionsAndHonorsHiddenRatings() {
        let app = launchProfileContent(scene: .settings)
        tap(SurroundUITestContract.AccessibilityID.profileSettingsEntry, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        element(SurroundUITestContract.AccessibilityID.profileRatings, in: app)
        let key = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingKey, in: app)
        XCTAssertEqual(key.label, "? means provisional — the range shows the likely rank.",
                       "The provisional legend must also read naturally on the signed-in player's own Profile.")
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
        XCTAssertTrue((provisional.value as? String ?? "").contains("Likely range"))
        XCTAssertFalse((provisional.value as? String ?? "").contains("±"))
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9")].exists)
        let thirteen = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertGreaterThan(thirteen.frame.minY, provisional.frame.minY,
                             "Accessibility sizes show one category per row.")
        XCTAssertEqual(thirteen.value as? String, "No rated games")
        keepScreenshot("Profile ratings – dark and largest Dynamic Type rank rows", in: app)

        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingMode, in: app)
        selectSegment(at: 1, in: SurroundUITestContract.AccessibilityID.profileRatingMode, app: app)
        let numericProvisional = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("9x9"), in: app)
        XCTAssertTrue((numericProvisional.value as? String ?? "").contains("1650"))
        XCTAssertTrue((numericProvisional.value as? String ?? "").contains("Provisional"))
        let missing = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("13x13"), in: app)
        XCTAssertEqual(missing.value as? String, "No rated games")
        let correspondence = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingCategory("correspondence"), in: app)
        XCTAssertTrue((correspondence.value as? String ?? "").contains("1950"))
        XCTAssertEqual(correspondence.label, "Correspondence", "Category names must retain their full label.")
        _ = revealProfileControl(SurroundUITestContract.AccessibilityID.profileRatingKey, in: app)
        keepScreenshot("Profile ratings – dark and largest Dynamic Type numeric rows", in: app)
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
        XCTAssertFalse(app.buttons[SurroundUITestContract.AccessibilityID.profileRatingCategory("live")].exists)
        XCTAssertTrue((live.value as? String ?? "").contains("±"))
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
        let categoryValue = nine.value as? String
        XCTAssertTrue((categoryValue ?? "").contains("Provisional"))
        for retryID in [SurroundUITestContract.AccessibilityID.profileHeadToHeadRetry,
                        SurroundUITestContract.AccessibilityID.profileActiveGamesRetry,
                        SurroundUITestContract.AccessibilityID.gameHistoryRetry] {
            let retry = revealProfileControl(retryID, in: app)
            tap(retry, description: "Retry the failed profile section", in: app)
            element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier:
                SurroundUITestContract.AccessibilityID.profileLoading).firstMatch.exists,
                "A section retry must retain the loaded profile instead of restarting its page load.")
            XCTAssertEqual(nine.value as? String, categoryValue,
                           "A section retry must preserve the category's displayed rating.")
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
            let profileAction = openProfileContextMenu(
                for: row,
                expecting: SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, playerID),
                in: app
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
        tap(openProfileContextMenu(
            for: row,
            expecting: SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 851_001),
            in: app
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
            openProfileContextMenu(
                for: row,
                expecting: SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, 901_001),
                in: app
            )
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
        let usesAccountMenu = app.buttons[SurroundUITestContract.AccessibilityID.accountMenu].waitForExistence(timeout: 2)
        openOwnProfileFromMainNavigation(in: app)
        let header = element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app)
        XCTAssertTrue(waitForValue(appearance.rawValue, in: header, timeout: 10),
                      "The profile must resolve the requested appearance, independent of the test host.")
        keepScreenshot("Own profile – \(appearance.rawValue) appearance", in: app)
        #if !targetEnvironment(macCatalyst)
        let usesIPadAccountSheets = UIDevice.current.userInterfaceIdiom == .pad
        #else
        let usesIPadAccountSheets = false
        #endif
        if usesIPadAccountSheets {
            let done = element("account.sheet.done", in: app, matching: .button)
            tap(done, description: "Dismiss the own Profile appearance sheet", in: app)
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: done
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: stateSettleTimeout), .completed)
        } else if usesAccountMenu {
            navigateBackFromPlayerProfile(in: app)
        } else {
            selectMainNavigation(SurroundUITestContract.AccessibilityID.navigationHome, in: app)
        }
        element(SurroundUITestContract.AccessibilityID.screenHome, in: app)
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

    func testProfileActionsPreserveGameAnalysisAndMarkers() throws {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.gameAnalysis.rawValue,
        ])
        try XCTSkipIf(
            app.segmentedControls[SurroundUITestContract.AccessibilityID.gameDisplayModePicker].exists,
            "Compact Analyze has no player banner; the standard navigation title is not a profile action."
        )
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
        let profileEntryID = SurroundUITestContract.AccessibilityID
            .profileBannerAvatarEntry(opponentID)
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
        let oldName = name.value as? String ?? ""
        // Acquire focus and place the caret in one interaction. A second tap
        // can land on the keyboard while its presentation moves the field.
        XCTAssertTrue(waitUntilHittable(name, timeout: 10),
                      "The challenge game name must be hittable before acquiring focus.")
        activate(name, at: CGVector(dx: 0.95, dy: 0.5))
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
