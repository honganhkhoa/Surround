import XCTest
import UIKit

/// Offline journeys through MainView's real Messages tab. Independent device
/// launches cover fixed geometry; native Duo transitions remain separate.
final class MessagesNavigationUITests: SurroundJourneyUITestCase {
    private let friendID = SurroundUITestContract.profileFixturePickerFriendID
    private let searchPlayerID = SurroundUITestContract.profileFixtureOpponentID
    private let firstPeerID = 765_826
    private let secondPeerID = 955_348

    private enum ConversationPresentation { case wideRoot, nativePush }

    func testCompactPlayerSearchBackPreservesQueryAndDraft() throws {
        let app = launchMessages()
        try requireCompact(in: app)
        setSearch("Copper", in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        let draft = "Unsent search conversation"
        enterDraft(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                presentation: .nativePush, in: app), app: app)
        openConversationProfile(searchPlayerID, username: "CopperKoi", in: app)
        back(from: "CopperKoi", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .nativePush, in: app), timeout: 10),
                      "Reopening the searched peer must restore its own draft.")
    }

    func testCompactInlineFriendConversationBackRestoresMessages() throws {
        let app = launchMessages()
        try requireCompact(in: app)
        assertDefaultFriendsStrip(in: app)
        expandFriends(in: app)
        tapFriend(friendID, in: app)
        let draft = "Unsent from inline Friends"
        enterDraft(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                presentation: .nativePush, in: app), app: app)
        openConversationProfile(friendID, username: "BambooPath", in: app)
        back(from: "BambooPath", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        tapVisible("messages.challenge.\(friendID)", in: app)
        assertChallenge(for: "BambooPath", in: app)
        back(from: "Challenge", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        back(from: "BambooPath", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "Inline Friends must not leave a Friends destination below the conversation.")
        XCTAssertFalse(visibleElement("messages.friend.message.\(friendID)", in: app).isSelected,
                       "The compact inbox must not mark a friend as a displayed conversation after Back.")
        // Expansion uses ordinary view lifetime; Back need not force either form.
        tapFriend(friendID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
    }

    func testPlayerSearchProfileBackAndMessageOnlyActions() {
        let app = launchMessages()
        let wide = usesColumns(in: app)
        let bounds = wide ? assertWideRoot(in: app) : nil
        assertDefaultFriendsStrip(in: app)
        setSearch("Copper", in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        assertSearchActionsOnly(for: searchPlayerID, in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        if let bounds {
            assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        }
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        cancelInboxSearch(in: app)
        setSearch("Bamboo", in: app)
        assertSearch("Bamboo", playerID: friendID, in: app)
        assertSearchActionsOnly(for: friendID, in: app)
        let friendProfile = visibleElement("messages.search.profile.\(friendID)", in: app)
        XCTAssertEqual(friendProfile.value as? String, "7k · Friend",
                       "The local friend's rank and friendship must be accessible together.")
        tap("messages.search.message.\(friendID)", in: app, matching: .button)
        assertConversation("BambooPath", peerID: friendID, presentation: wide ? .wideRoot : .nativePush, in: app)
        if !wide { back(from: "BambooPath", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app) }
        assertSearch("Bamboo", playerID: friendID, in: app)
        cancelInboxSearch(in: app)
        if wide { assertConversation("BambooPath", peerID: friendID, presentation: .wideRoot, in: app) }
        assertDefaultFriendsStrip(in: app)
    }

    func testWideFullWidthProfileAndChallengeBackRestoreRootDraftAndQuery() throws {
        let app = launchMessages()
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let draft = "Unsent wide root conversation"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                presentation: .wideRoot, in: app), app: app)
        setSearch("Copper", in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        let searchBounds = element("messages.playerSearchField", in: app, matching: .textField).frame
        let detailBounds = element("messages.detailPane", in: app).frame
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideSearchRoot(in: app, searchBounds: searchBounds, detailBounds: detailBounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        tapVisible("messages.challenge.\(firstPeerID)", in: app)
        assertChallenge(for: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenCustomGame, over: bounds, in: app)
        back(from: "Challenge", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideSearchRoot(in: app, searchBounds: searchBounds, detailBounds: detailBounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "Back must restore the wide root without a conversation pushed over it.")
    }

    func testWideProfileMessageNativeBackRestoresProfileThenRootSelection() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app, matching: .button)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .nativePush, in: app)
        assertFullWidthDestination("messages.conversation", over: bounds, in: app)
        revealNativeOlderHistory(username: "hakhoa", index: 25, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "hakhoa", in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        // The same peer has separate live root and pushed transcripts. Native
        // Back must resume the root's latest view rather than the push's history.
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        openInboxConversation(firstPeerID, in: app)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        let rootDraft = "Unsent original root peer"
        enterDraft(rootDraft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                    presentation: .wideRoot, in: app), app: app)
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app, matching: .button)
        let nestedDraft = "Unsent native Profile message"
        enterDraft(nestedDraft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                      presentation: .nativePush, in: app), app: app)
        assertFullWidthDestination("messages.conversation", over: bounds, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(rootDraft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                                   presentation: .wideRoot, in: app), timeout: 10),
                      "A shared native push must not replace the root's independently selected peer.")
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        XCTAssertTrue(waitForValue(nestedDraft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                                     presentation: .wideRoot, in: app), timeout: 10),
                      "Root selection must restore the draft created for that peer in the native push.")
        XCTAssertNil(visibleBack(from: "Messages", in: app))
    }

    func testWideInlineFriendsAndSearchCancelRetainLatestPeer() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        assertInboxSelection(firstPeerID, in: app)
        let stripPrefix = visibleFriendPrefix("messages.friends.strip", in: app)
        XCTAssertEqual(stripPrefix.first, "messages.friend.message.\(SurroundUITestContract.messagesOverflowRecentFriendID)",
                       "A recent friend's conversation must take priority over alphabetical order.")
        XCTAssertEqual(stripPrefix.dropFirst().first, "messages.friend.message.\(friendID)")
        let expanded = expandFriends(in: app,
            expectedFriendIDs: Array(801_001...801_006) + SurroundUITestContract.messagesOverflowFriendIDs)
        XCTAssertTrue(expanded, "The overflow fixture must expose inline expansion.")
        XCTAssertEqual(visibleFriendPrefix("messages.friends.grid", in: app), stripPrefix,
                       "Expansion must preserve the same recent-first ordering as the strip.")
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertInboxSelection(firstPeerID, in: app)
        tapFriend(SurroundUITestContract.messagesOverflowRecentFriendID, in: app)
        assertConversation("RainyGrove", peerID: SurroundUITestContract.messagesOverflowRecentFriendID,
                           presentation: .wideRoot, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "A direct inline friend selection must remain in the wide root.")
        if expanded { collapseFriends(in: app) }
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        assertInboxSelection(secondPeerID, in: app)
        setSearch("Copper", in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        let draft = "Unsent latest search recipient"
        enterDraft(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                presentation: .wideRoot, in: app), app: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app))
        cancelInboxSearch(in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .wideRoot, in: app), timeout: 10),
                      "Cancel must keep the latest selected recipient and exact draft.")
        // CopperKoi has no thread fixture; neither existing thread is selected.
        assertInboxSelection(nil, in: app)
        assertDefaultFriendsStrip(in: app)
    }

    func testReadingOnePeerPreservesOtherUnreadThreadAndPeerDrafts() {
        let app = launchMessages()
        let wide = usesColumns(in: app)
        if wide {
            assertConversation("hakhoa", peerID: firstPeerID, in: app)
            assertUnread(false, peerID: firstPeerID, in: app)
        } else {
            assertUnread(true, peerID: firstPeerID, in: app)
            openInboxConversation(firstPeerID, in: app)
        }
        let firstDraft = "Unsent draft for hakhoa"
        enterDraft(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), app: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        back(from: "hakhoa", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), timeout: 10))
        if !wide {
            back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        assertUnread(false, peerID: firstPeerID, in: app)
        assertUnread(true, peerID: secondPeerID, in: app)

        openInboxConversation(secondPeerID, in: app)
        let secondComposer = assertConversation("khoahong", peerID: secondPeerID, in: app)
        assertEmptyComposer(secondComposer)
        let secondDraft = "Unsent draft for khoahong"
        enterDraft(secondDraft, in: secondComposer, app: app)
        if !wide {
            back(from: "khoahong", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        assertUnread(false, peerID: secondPeerID, in: app)
        openInboxConversation(firstPeerID, in: app)
        XCTAssertTrue(waitForValue(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), timeout: 10),
                      "Switching peers must restore the first peer's draft without leaking the second peer's text.")
        if !wide {
            back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        openInboxConversation(secondPeerID, in: app)
        XCTAssertTrue(waitForValue(secondDraft, in: assertConversation("khoahong", peerID: secondPeerID, in: app), timeout: 10),
                      "Each peer must retain its own unsent draft after repeated navigation.")
    }

    func testWideScrolledInboxAndPeerHistorySurviveProfileBackAndPeerSwitches() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let allFriendIDs = Array(801_001...801_006) + SurroundUITestContract.messagesOverflowFriendIDs
        XCTAssertTrue(expandFriends(in: app, expectedFriendIDs: allFriendIDs),
                      "The opt-in overflow fixture must offer a real expanded grid.")
        let anchorID = "messages.friend.message.914040"
        let friendAnchor = inboxElement(anchorID, in: app)
        let anchorFrame = friendAnchor.frame
        XCTAssertFalse(query("messages.friends.toggle", in: app).isHittable,
                       "The Friends anchor must be below the initial inbox viewport.")
        revealOlderHistory(username: "hakhoa", index: 25, in: app)
        let firstHistoryWitness = centralVisibleHistoryWitness(username: "hakhoa", in: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        let restoredFriend = query(anchorID, in: app)
        XCTAssertTrue(waitUntilHittable(restoredFriend, timeout: 10),
                      "Native Back must restore the scrolled inbox's visible friend context.")
        XCTAssertEqual(restoredFriend.frame.minY, anchorFrame.minY, accuracy: 16,
                       "Back must preserve the visible inbox anchor, without a reveal gesture.")
        assertHistoryWitnessVisible(firstHistoryWitness, username: "hakhoa", in: app)

        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        revealOlderHistory(username: "khoahong", index: 40, in: app)
        let secondHistoryWitness = centralVisibleHistoryWitness(username: "khoahong", in: app)
        openInboxConversation(firstPeerID, in: app)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertHistoryWitnessVisible(firstHistoryWitness, username: "hakhoa", in: app)
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        assertHistoryWitnessVisible(secondHistoryWitness, username: "khoahong", in: app)
    }

    func testWideInboxRequestRetryAndFullWidthProfileErrorOwnership() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.friendshipLaunchArgument,
            SurroundUITestContract.friendshipFailsOnceLaunchArgument,
        ])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let draft = "Unsent while resolving inbox requests"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                presentation: .wideRoot, in: app), app: app)
        let ids = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        let firstAccept = inboxElement(SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[0]), in: app)
        tap(firstAccept, description: "Accept the offline inbox request whose first response fails", in: app)
        retryFixtureAcceptance(in: app)
        XCTAssertTrue(waitForCondition {
            !self.query(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[0]), in: app).exists
        })
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        let secondProfile = inboxElement(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[1]), in: app)
        let requestCreated = Date(timeIntervalSince1970: 1_789_516_800)
        let relativeAge = requestCreated.formatted(
            Date.RelativeFormatStyle(presentation: .named, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(secondProfile.value as? String, "5k, \(relativeAge)",
                       "The dated request's rank and relative age must be accessible together.")
        tap(secondProfile, description: "Open the other request's full-width Profile", in: app)
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[1]
        assertLoadedProfile(named: username, in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        let banner = element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        let accept = banner.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[1])].firstMatch
        tap(accept, description: "Accept the offline request from its visible Profile", in: app)
        retryFixtureAcceptance(in: app)
        XCTAssertTrue(waitForCondition { !banner.exists })
        XCTAssertTrue(waitForCondition {
            self.query(SurroundUITestContract.AccessibilityID.profileFriendshipAction, in: app).label == "Friends"
        })
        back(from: username, to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        XCTAssertFalse(query(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[1]), in: app).exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "The covered inbox must not replay Profile's resolved error after Back.")
        inboxElement(SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[2]), in: app)
    }

    private func launchMessages(additionalLaunchArguments: [String] = []) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
            SurroundUITestContract.messagesContentLaunchArgument,
        ] + additionalLaunchArguments, orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        return app
    }

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func usesColumns(in app: XCUIApplication) -> Bool {
        let inbox = query("messages.inboxPane", in: app)
        let detail = query("messages.detailPane", in: app)
        return inbox.exists && detail.exists && inbox.frame.width > 1 && detail.frame.width > 1
            && detail.frame.minX >= inbox.frame.maxX - 1
            && query("messages.playerSearchField", in: app).isHittable
    }

    private func requireCompact(in app: XCUIApplication) throws {
        if usesColumns(in: app) {
            throw XCTSkip("Requires the actual compact Messages root; run on an iPhone or Duo Closed.")
        }
    }

    private func requireColumns(in app: XCUIApplication) throws {
        if !usesColumns(in: app) {
            throw XCTSkip("Requires the actual two-column Messages root; run on an iPad or Duo Open/Book.")
        }
    }

    private func visibleElement(_ identifier: String, in app: XCUIApplication,
                                matching type: XCUIElement.ElementType = .button) -> XCUIElement {
        var found: XCUIElement?
        XCTAssertTrue(waitForCondition {
            found = app.descendants(matching: type).matching(identifier: identifier)
                .allElementsBoundByIndex.first(where: { $0.isHittable })
            return found != nil
        }, "Expected a usable \(identifier) on the visible destination.")
        return found ?? query(identifier, in: app)
    }

    private func tapVisible(_ identifier: String, in app: XCUIApplication) {
        tap(visibleElement(identifier, in: app), description: identifier, in: app)
    }

    private func setSearch(_ value: String, in app: XCUIApplication) {
        let field = element("messages.playerSearchField", in: app, matching: .textField)
        tap(field, description: "Focus inbox player search", in: app)
        field.typeText(value)
        XCTAssertTrue(waitForValue(value, in: field, timeout: 10))
    }

    private func assertSearch(_ value: String, playerID: Int, in app: XCUIApplication) {
        XCTAssertTrue(waitForValue(value, in: element("messages.playerSearchField", in: app, matching: .textField), timeout: 10))
        visibleElement("messages.search.profile.\(playerID)", in: app)
        visibleElement("messages.search.message.\(playerID)", in: app)
        element("messages.cancelPlayerSearch", in: app, matching: .button)
    }

    private func assertSearchActionsOnly(for playerID: Int, in app: XCUIApplication) {
        for identifier in [
            "messages.search.challenge.\(playerID)",
            SurroundUITestContract.AccessibilityID.profileFriendshipAction,
            SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
            SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
        ] {
            XCTAssertFalse(query(identifier, in: app).exists, "Search must expose Profile and Message without secondary friendship actions.")
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Sent")).count, 0)
    }

    private func assertDefaultFriendsStrip(in app: XCUIApplication) {
        element("messages.friends.strip", in: app)
        XCTAssertFalse(query("messages.friends.grid", in: app).exists)
        XCTAssertFalse(query("messages.addFriend", in: app).exists)
        XCTAssertFalse(query("messages.friends", in: app).exists, "Friends is inline content, not a destination.")
    }

    private func visibleFriendPrefix(_ identifier: String, in app: XCUIApplication) -> [String] {
        let section = element(identifier, in: app)
        let buttons = section.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "messages.friend.message."
        ))
        return (0..<3).map { index in
            let button = buttons.element(boundBy: index)
            XCTAssertTrue(waitUntilHittable(button, timeout: 10),
                          "The ordered Friends prefix must be visible in its current presentation.")
            return button.identifier
        }
    }

    @discardableResult
    private func expandFriends(in app: XCUIApplication,
                               expectedFriendIDs: [Int] = Array(801_001...801_006)) -> Bool {
        if !query("messages.friends.toggle", in: app).exists {
            let strip = element("messages.friends.strip", in: app)
            XCTAssertTrue(expectedFriendIDs.allSatisfy { id in
                let friend = strip.buttons["messages.friend.message.\(id)"].firstMatch
                return friend.exists && friend.isHittable
                    && friend.frame.minX >= strip.frame.minX - 1
                    && friend.frame.maxX <= strip.frame.maxX + 1
            }, "The toggle may be absent only when every friend fits in the measured row.")
            return false
        }
        tap(inboxElement("messages.friends.toggle", in: app), description: "Expand inline Friends", in: app)
        element("messages.friends.grid", in: app)
        XCTAssertFalse(query("messages.friends.strip", in: app).exists)
        return true
    }

    private func collapseFriends(in app: XCUIApplication) {
        tap(inboxElement("messages.friends.toggle", in: app), description: "Restore the horizontal Friends row", in: app)
        assertDefaultFriendsStrip(in: app)
    }

    private func tapFriend(_ peerID: Int, in app: XCUIApplication) {
        tap(inboxElement("messages.friend.message.\(peerID)", in: app), description: "Select inline friend \(peerID)", in: app)
    }

    @discardableResult
    private func inboxElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let scroll = element("messages.inboxScroll", in: app, matching: .scrollView)
        return elementAfterScrolling(identifier, in: app, within: scroll, matching: .button)
    }

    private func cancelInboxSearch(in app: XCUIApplication) {
        tap("messages.cancelPlayerSearch", in: app, matching: .button)
        XCTAssertTrue(waitForCondition { !self.query("messages.cancelPlayerSearch", in: app).exists })
        element("messages.inboxScroll", in: app, matching: .scrollView)
    }

    private func openInboxConversation(_ peerID: Int, in app: XCUIApplication) {
        tap(inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app),
            description: "Select fixture conversation \(peerID)", in: app)
    }

    @discardableResult
    private func assertConversation(_ username: String, peerID: Int,
                                    presentation: ConversationPresentation? = nil, in app: XCUIApplication) -> XCUIElement {
        let composer = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                                      in: app, matching: .textField)
        XCTAssertEqual(composer.placeholderValue, "Message \(username)")
        let activeComposers = app.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
            .allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(activeComposers.count, 1, "One visible conversation composer must own interaction.")
        let profile = visibleElement(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peerID), in: app)
        XCTAssertTrue(profile.label.contains(username))
        if (presentation ?? (usesColumns(in: app) ? .wideRoot : .nativePush)) == .wideRoot {
            let heading = element("messages.conversation.heading", in: app)
            let identity = heading.staticTexts.matching(NSPredicate(format: "label == %@", username)).firstMatch
            XCTAssertTrue(waitUntilHittable(identity, timeout: 10), "The wide root must visibly identify its selected peer.")
        }
        return composer
    }

    private func enterDraft(_ value: String, in composer: XCUIElement, app: XCUIApplication) {
        tap(composer, description: "Focus the private-message draft", in: app)
        // Return submits messages. Draft journeys never type it.
        let firstCharacter = String(value.prefix(1))
        // Confirm input readiness before the remaining keyboard events. This
        // does not retry or repair a partially entered draft.
        composer.typeText(firstCharacter)
        XCTAssertTrue(waitForValue(firstCharacter, in: composer, timeout: 10),
                      "The focused composer must receive the first keyboard event exactly.")
        composer.typeText(String(value.dropFirst()))
        XCTAssertTrue(waitForValue(value, in: composer, timeout: 10))
    }

    private func openConversationProfile(_ peerID: Int, username: String, in app: XCUIApplication) {
        tapVisible(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peerID), in: app)
        assertLoadedProfile(named: username, in: app)
    }

    private func assertChallenge(for username: String, in app: XCUIApplication) {
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        XCTAssertTrue(app.navigationBars["Challenge"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app).label.contains(username))
    }

    private func assertWideSearchRoot(in app: XCUIApplication, searchBounds: CGRect, detailBounds: CGRect) {
        assertWideRoot(in: app)
        // Scroll-view AX groups can include offscreen extents. Compare the visible
        // search control and detail pane in the same retained search presentation.
        let search = element("messages.playerSearchField", in: app, matching: .textField).frame
        let detail = element("messages.detailPane", in: app).frame
        XCTAssertEqual(search.minX, searchBounds.minX, accuracy: 2)
        XCTAssertEqual(search.maxX, searchBounds.maxX, accuracy: 2)
        XCTAssertEqual(detail.minX, detailBounds.minX, accuracy: 2)
        XCTAssertEqual(detail.maxX, detailBounds.maxX, accuracy: 2)
    }

    @discardableResult
    private func assertWideRoot(in app: XCUIApplication, expectedBounds: CGRect? = nil) -> CGRect {
        let inbox = element("messages.inboxPane", in: app)
        let detail = element("messages.detailPane", in: app)
        XCTAssertTrue(query("messages.playerSearchField", in: app).isHittable)
        XCTAssertGreaterThan(inbox.frame.width, 1)
        XCTAssertGreaterThan(detail.frame.width, 1)
        XCTAssertGreaterThanOrEqual(detail.frame.minX, inbox.frame.maxX - 1)
        let bounds = inbox.frame.union(detail.frame)
        if let expectedBounds {
            XCTAssertEqual(bounds.minX, expectedBounds.minX, accuracy: 2)
            XCTAssertEqual(bounds.width, expectedBounds.width, accuracy: 2)
        }
        return bounds
    }

    private func assertFullWidthDestination(_ identifier: String, over bounds: CGRect, in app: XCUIApplication) {
        var destination: XCUIElement?
        XCTAssertTrue(waitForCondition {
            destination = app.descendants(matching: .any).matching(identifier: identifier)
                .allElementsBoundByIndex.first {
                    $0.frame.width >= bounds.width * 0.9 && $0.frame.intersects(bounds)
                }
            return destination != nil
        }, "The pushed destination must span the allocated Messages content, including both root columns.")
        if let destination {
            XCTAssertLessThanOrEqual(destination.frame.minX, bounds.minX + 24)
            XCTAssertGreaterThanOrEqual(destination.frame.maxX, bounds.maxX - 24)
        }
        XCTAssertFalse(query("messages.playerSearchField", in: app).isHittable, "The full-width push must cover root inbox controls.")
        let detail = query("messages.detailPane", in: app)
        if detail.exists {
            for composer in detail.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
                .allElementsBoundByIndex {
                XCTAssertFalse(composer.isHittable, "The retained root composer must yield interaction to the pushed destination.")
            }
        }
    }

    private func visibleBack(from title: String, in app: XCUIApplication) -> XCUIElement? {
        let identified = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back"))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        if let identified { return identified }
        let buttons = app.navigationBars[title].exists ? app.navigationBars[title].buttons : app.navigationBars.buttons
        return buttons.matching(NSPredicate(format: "label IN %@", ["Messages", "hakhoa", "khoahong", "CopperKoi", "BambooPath"]))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
    }

    private func back(from title: String, to destination: String, in app: XCUIApplication) {
        var control: XCUIElement?
        XCTAssertTrue(waitForCondition {
            control = self.visibleBack(from: title, in: app)
            return control != nil
        }, "A native push must retain a usable Back control.")
        guard let control else { return }
        tap(control, description: "Back from \(title)", in: app)
        let usable: XCUIElement
        switch destination {
        case "messages.conversation":
            usable = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer, in: app, matching: .textField)
        case SurroundUITestContract.AccessibilityID.screenMessages:
            usable = visibleElement("messages.playerSearchField", in: app, matching: .textField)
        case SurroundUITestContract.AccessibilityID.screenPlayerProfile:
            usable = visibleElement(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
        default:
            XCTFail("No restored-control assertion for \(destination)")
            return
        }
        XCTAssertTrue(usable.isHittable, "Back must restore a usable control on its originating screen.")
    }

    private func assertUnread(_ unread: Bool, peerID: Int, in app: XCUIApplication) {
        let row = inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app)
        XCTAssertTrue(waitForCondition { ((row.value as? String) == "Unread conversation") == unread },
                      "Only the viewed peer's unread marker should clear.")
    }

    private func assertInboxSelection(_ selectedPeerID: Int?, in app: XCUIApplication) {
        for peerID in [firstPeerID, secondPeerID] {
            let row = inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app)
            XCTAssertTrue(waitForCondition { row.isSelected == (selectedPeerID == peerID) })
        }
    }

    private func rootTranscript(in app: XCUIApplication) -> XCUIElement {
        let detail = element("messages.detailPane", in: app)
        let transcript = detail.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        return transcript
    }

    private func nativeTranscript(over bounds: CGRect, in app: XCUIApplication) -> XCUIElement {
        var transcript: XCUIElement?
        XCTAssertTrue(waitForCondition {
            let destination = app.descendants(matching: .any).matching(identifier: "messages.conversation")
                .allElementsBoundByIndex.first { conversation in
                    conversation.frame.width >= bounds.width * 0.9 && conversation.frame.intersects(bounds)
                        && conversation.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
                            .allElementsBoundByIndex.contains(where: { $0.isHittable })
                }
            transcript = destination?.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
            return transcript?.exists == true
        }, "Older-history gestures must target the active full-width conversation, not the retained root transcript.")
        return transcript ?? app.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
    }

    private func revealNativeOlderHistory(username: String, index: Int, over bounds: CGRect, in app: XCUIApplication) {
        let transcript = nativeTranscript(over: bounds, in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        for _ in 0..<8 {
            let viewport = transcript.frame.insetBy(dx: 8, dy: 8)
            if marker.exists {
                let frame = marker.frame
                if viewport.contains(frame) && marker.isHittable { break }
                if frame.maxY > viewport.maxY {
                    transcript.swipeUp()
                    continue
                }
            }
            transcript.swipeDown()
        }
        XCTAssertTrue(marker.exists && transcript.frame.insetBy(dx: 8, dy: 8).contains(marker.frame) && marker.isHittable,
                      "The native push must reach a fully visible older message before Back.")
        XCTAssertFalse(transcript.staticTexts["Offline message from \(username)"].firstMatch.isHittable)
    }

    private func assertLatestHistoryVisible(username: String, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertTrue(waitUntilHittable(latest, timeout: 10),
                      "The retained root must resume its latest message without a repair gesture.")
        let older = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: 25)
        )).firstMatch
        XCTAssertFalse(older.isHittable, "The pushed conversation's older context must not replace the root's latest view.")
    }

    private func revealOlderHistory(username: String, index: Int, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        for _ in 0..<8 {
            let viewport = transcript.frame.insetBy(dx: 8, dy: 8)
            if marker.exists {
                let frame = marker.frame
                if viewport.contains(frame) && marker.isHittable { break }
                if frame.maxY > viewport.maxY {
                    transcript.swipeUp()
                    continue
                }
            }
            transcript.swipeDown()
        }
        XCTAssertTrue(marker.exists && transcript.frame.insetBy(dx: 8, dy: 8).contains(marker.frame) && marker.isHittable,
                      "The older message seed must be fully inside the transcript viewport before navigation.")
        assertOlderHistoryVisible(username: username, index: index, in: app)
    }

    private func assertOlderHistoryVisible(username: String, index: Int, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        XCTAssertTrue(waitUntilHittable(marker, timeout: 10),
                      "The selected peer must restore its own older message context without scrolling again.")
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertFalse(latest.isHittable, "History restoration must not silently jump to the newest message.")
    }

    private func centralVisibleHistoryWitness(username: String, in app: XCUIApplication) -> String {
        let transcript = rootTranscript(in: app)
        let detail = element("messages.detailPane", in: app)
        let composer = detail.textFields[SurroundUITestContract.AccessibilityID.privateMessageComposer].firstMatch
        XCTAssertTrue(waitUntilHittable(composer, timeout: 10))
        let bounds = transcript.frame.intersection(app.windows.firstMatch.frame)
        // The ScrollView may extend beneath the composer. Capture only a
        // readable message from the actual unobscured transcript viewport.
        let viewport = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                              height: max(0, min(bounds.maxY, composer.frame.minY) - bounds.minY))
            .insetBy(dx: 8, dy: 8)
        let visible = transcript.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@",
            "Offline history ", " for \(username)\n"
        )).allElementsBoundByIndex.compactMap { message -> (label: String, midY: CGFloat)? in
            let frame = message.frame
            guard viewport.contains(frame) && message.isHittable else { return nil }
            return (message.label, frame.midY)
        }.sorted { $0.midY < $1.midY }
        guard !visible.isEmpty else {
            XCTFail("A readable older-message witness must exist before leaving the peer.")
            return ""
        }
        // Freeze one external AX label before navigation. Native reflow can
        // move it within the viewport; a neighboring label cannot replace it.
        return visible[visible.count / 2].label
    }

    private func assertHistoryWitnessVisible(_ witness: String, username: String, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(format: "label == %@", witness)).firstMatch
        XCTAssertTrue(waitUntilHittable(marker, timeout: 10),
                      "The same pre-navigation reading witness must remain visible without scrolling again.")
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertFalse(latest.isHittable, "History restoration must not silently jump to the newest message.")
    }

    private func assertEmptyComposer(_ composer: XCUIElement) {
        let value = composer.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == composer.placeholderValue, "A new peer must not inherit another peer's draft.")
    }

    private func retryFixtureAcceptance(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Couldn’t accept friend request"].exists)
        XCTAssertEqual(app.alerts.count, 1, "The visible screen must own one error presenter.")
        tap(alert.buttons["Retry"].firstMatch, description: "Retry the offline failed acceptance", in: app)
        XCTAssertTrue(waitForCondition { !alert.exists })
    }

    private func waitForCondition(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
}
