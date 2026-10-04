import SwiftUI
import XCTest

final class StackRouterTests: XCTestCase {
    private typealias Router = StackRouter
    private typealias User = OGSUser
    private typealias Draft = ChallengeDraft

    private let viewerID = 100
    private var firstPlayer: User { User(username: "First player", id: 101) }
    private var secondPlayer: User { User(username: "Second player", id: 102) }

    func testBiographyPlayerLinksLoadByIDAndKeepTheirSourceAboutForBack() {
        let router = Router()
        let profile = OGSPlayerProfile(user: firstPlayer, about: "A linked biography")
        router.openProfile(firstPlayer)
        router.openAbout(profile)
        router.openProfile(playerID: secondPlayer.id)

        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: nil),
                                     .playerAbout(firstPlayer.id),
                                     .profile(playerID: secondPlayer.id, selectionID: nil)])
        XCTAssertNil(router.users[secondPlayer.id], "An ID-only link must not invent the player's name.")
        XCTAssertEqual(router.aboutProfilesByPlayer[firstPlayer.id]?.about, profile.about)

        router.path.removeLast()
        XCTAssertEqual(router.path.last, .playerAbout(firstPlayer.id))
        XCTAssertEqual(router.aboutProfilesByPlayer[firstPlayer.id]?.about, profile.about)
        router.path.removeLast()
        XCTAssertTrue(router.aboutProfilesByPlayer.isEmpty)
        XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)
    }

    func testBiographyRoutesPreserveConversationDraftAndHistoryAcrossColumnsAndBack() {
        let router = Router()
        let draft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        draft.wrappedValue = "Unsent before reading About"
        let bookmark = router.conversationScrollBookmark(for: firstPlayer.id, accountID: viewerID)
        bookmark.isAtEndOfChat = false
        bookmark.messageKey = "older-message"
        router.presentMessagesConversation(firstPlayer)
        router.openProfile(firstPlayer)
        router.openAbout(OGSPlayerProfile(user: firstPlayer, about: "Read more"))
        router.openProfile(playerID: secondPlayer.id)

        router.showMessagesColumns(true, peer: firstPlayer)
        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: nil),
                                     .playerAbout(firstPlayer.id),
                                     .profile(playerID: secondPlayer.id, selectionID: nil)])
        router.showMessagesColumns(false, peer: firstPlayer)
        XCTAssertEqual(router.path.first, .messagesConversation(firstPlayer.id))
        router.returnTo(.messagesConversation(firstPlayer.id))

        XCTAssertEqual(draft.wrappedValue, "Unsent before reading About")
        XCTAssertTrue(router.conversationScrollBookmark(for: firstPlayer.id, accountID: viewerID) === bookmark)
        XCTAssertEqual(bookmark.messageKey, "older-message")
        XCTAssertFalse(bookmark.isAtEndOfChat)
        XCTAssertTrue(router.aboutProfilesByPlayer.isEmpty)
        XCTAssertNil(router.users[secondPlayer.id])
    }

    func testBiographyGameIDLinkReusesOriginalGameAncestor() {
        let router = Router()
        let nav = NavigationService()
        let service = OGSService.previewInstance(user: firstPlayer)
        let game = Game(width: 19, height: 19, blackName: "Black", whiteName: "White", gameId: .OGS(123))
        nav.home.activeGame = game
        router.present(.homeGame)
        router.openProfile(firstPlayer)
        router.openAbout(OGSPlayerProfile(user: firstPlayer, about: "Original game"))

        router.openGame(gameID: 123, using: nav, service: service)

        XCTAssertEqual(router.path, [.homeGame])
        XCTAssertTrue(nav.home.activeGame === game)
        XCTAssertTrue(router.games.isEmpty)
        XCTAssertTrue(router.aboutProfilesByPlayer.isEmpty)
    }

    func testUncachedBiographyGameRetainsAboutAndAcceptsOnlyItsOwnLoadedModel() {
        let router = Router()
        let nav = NavigationService()
        let service = OGSService.previewInstance(user: firstPlayer)
        let game = Game(width: 19, height: 19, blackName: "Black", whiteName: "White", gameId: .OGS(123))
        let wrongGame = Game(width: 9, height: 9, blackName: "Other Black", whiteName: "Other White", gameId: .OGS(124))
        router.openAbout(OGSPlayerProfile(user: firstPlayer, about: "Game link"))
        router.openGame(gameID: 123, using: nav, service: service)

        XCTAssertEqual(router.path, [.playerAbout(firstPlayer.id), .game(123)])
        XCTAssertNil(router.games[123])
        router.updateGame(wrongGame, for: 123)
        XCTAssertNil(router.games[123])
        router.updateGame(game, for: 123)
        XCTAssertTrue(router.games[123] === game)
        router.openProfile(secondPlayer)
        router.openGame(gameID: 123, using: nav, service: service)
        XCTAssertEqual(router.path, [.playerAbout(firstPlayer.id), .game(123)])
        router.path.removeLast()
        router.updateGame(game, for: 123)
        XCTAssertTrue(router.games.isEmpty, "A late response must not revive a popped game.")
        XCTAssertNotNil(router.aboutProfilesByPlayer[firstPlayer.id])
        router.path.removeLast()
        XCTAssertTrue(router.aboutProfilesByPlayer.isEmpty)
    }

    func testInvalidBiographyIDsLeaveNavigationUntouched() {
        let router = Router()
        let nav = NavigationService()
        let service = OGSService.previewInstance(user: firstPlayer)
        router.openAbout(OGSPlayerProfile(user: firstPlayer, about: "Biography"))
        for invalidID in [0, -1] {
            router.openProfile(playerID: invalidID)
            router.openGame(gameID: invalidID, using: nav, service: service)
        }
        XCTAssertEqual(router.path, [.playerAbout(firstPlayer.id)])
        XCTAssertTrue(router.games.isEmpty)
        XCTAssertEqual(router.aboutProfilesByPlayer[firstPlayer.id]?.about, "Biography")
    }

    func testProfileGameReturnsToExistingGameAndPreservesItsModel() throws {
        let router = Router()
        let nav = NavigationService()
        let game = Game(width: 19, height: 19, blackName: "Black", whiteName: "White", gameId: .OGS(123))
        nav.home.activeGame = game
        router.present(.homeGame)
        router.openProfile(firstPlayer)
        router.openHistory(for: firstPlayer)
        router.openGame(game, using: nav)
        XCTAssertEqual(router.path, [.homeGame])
        XCTAssertTrue(nav.home.activeGame === game)
        XCTAssertTrue(router.games.isEmpty)
        XCTAssertTrue(router.users.isEmpty)
    }

    func testNestedProfileGameRoutesReuseAndReleaseTheirState() {
        let router = Router()
        let nav = NavigationService()
        let game = Game(width: 19, height: 19, blackName: "Black", whiteName: "White", gameId: .OGS(123))
        router.openProfile(firstPlayer)
        router.openGame(game, using: nav)
        router.openProfile(secondPlayer)
        router.openHistory(for: secondPlayer, opponentID: firstPlayer.id)
        router.openGame(game, using: nav)
        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: nil), .game(123)])
        XCTAssertTrue(router.games[123] === game)
        XCTAssertNil(router.users[secondPlayer.id])
        router.path.removeLast()
        XCTAssertTrue(router.games.isEmpty)
    }

    func testProfileListsRetainOnlyTheirOwnPayloads() throws {
        let router = Router()
        let service = OGSService.previewInstance(user: firstPlayer)
        let games = try XCTUnwrap(service.profileActiveGames(from: .init(user: firstPlayer, activeGames: [])))
        router.openActiveGames(games, for: firstPlayer)
        router.openHistory(for: firstPlayer, opponentID: secondPlayer.id)
        router.openHistory(for: firstPlayer, opponentID: secondPlayer.id)
        XCTAssertEqual(router.path, [.playerActiveGames(firstPlayer.id),
                                    .playerHistory(playerID: firstPlayer.id, opponentID: secondPlayer.id)])
        XCTAssertTrue(router.activeGamesByPlayer[firstPlayer.id] === games)
        router.path.removeAll()
        XCTAssertTrue(router.users.isEmpty)
        XCTAssertTrue(router.games.isEmpty)
        XCTAssertTrue(router.activeGamesByPlayer.isEmpty)
    }

    func testMessageFromConversationProfileReturnsToExistingConversation() {
        let router = Router()
        router.openConversation(firstPlayer)
        router.openProfile(firstPlayer)
        router.openConversation(firstPlayer)

        XCTAssertEqual(router.path, [.conversation(firstPlayer.id)])
        XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)
    }

    func testConversationAvatarReturnsToExistingProfileWithoutStacking() {
        let router = Router()
        router.present(.waitingGames)
        router.openProfile(firstPlayer)
        router.openConversation(firstPlayer)
        router.openProfile(firstPlayer)

        XCTAssertEqual(router.path, [.waitingGames, .profile(playerID: firstPlayer.id, selectionID: nil)])
        router.path.removeLast()
        XCTAssertEqual(router.path, [.waitingGames])
        XCTAssertTrue(router.users.isEmpty)
    }

    func testCompactRootAndProfileMessageToSamePeerKeepDistinctBackDestinations() {
        let router = Router()
        let messageDraft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        messageDraft.wrappedValue = "Return to this conversation"
        let rootConversation = StackRoute.messagesConversation(firstPlayer.id)
        let profile = StackRoute.profile(playerID: firstPlayer.id, selectionID: nil)

        router.presentMessagesConversation(firstPlayer)
        router.openProfile(firstPlayer)
        router.openConversation(firstPlayer)

        XCTAssertEqual(router.path, [rootConversation, profile, .conversation(firstPlayer.id)])
        router.path.removeLast()
        XCTAssertEqual(router.path, [rootConversation, profile],
                       "Profile's Message action must return to Profile, even for the root recipient.")
        XCTAssertEqual(messageDraft.wrappedValue, "Return to this conversation")

        router.path.removeLast()
        XCTAssertEqual(router.path, [rootConversation])
        XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)

        router.path.removeLast()
        XCTAssertTrue(router.path.isEmpty, "Compact root Back must reveal the inbox.")
        XCTAssertTrue(router.users.isEmpty)
        router.presentMessagesConversation(firstPlayer)
        XCTAssertEqual(router.path, [rootConversation])
        XCTAssertEqual(
            router.conversationDraft(for: firstPlayer.id, accountID: viewerID).wrappedValue,
            "Return to this conversation"
        )
    }

    func testConversationDraftsStayWithTheirAccountAndPeer() {
        let router = Router()
        let first = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        let second = router.conversationDraft(for: secondPlayer.id, accountID: viewerID)
        let otherAccount = router.conversationDraft(for: firstPlayer.id, accountID: 200)
        first.wrappedValue = "First account, first peer"
        second.wrappedValue = "First account, second peer"
        otherAccount.wrappedValue = "Other account, first peer"

        XCTAssertEqual(
            router.conversationDraft(for: firstPlayer.id, accountID: viewerID).wrappedValue,
            "First account, first peer"
        )
        XCTAssertEqual(second.wrappedValue, "First account, second peer")
        XCTAssertEqual(otherAccount.wrappedValue, "Other account, first peer")

        let signedOut = router.conversationDraft(for: firstPlayer.id, accountID: nil)
        signedOut.wrappedValue = "Signed-out text"
        XCTAssertEqual(signedOut.wrappedValue, "")
        XCTAssertEqual(first.wrappedValue, "First account, first peer")
        first.wrappedValue = ""
        XCTAssertEqual(second.wrappedValue, "First account, second peer")
        XCTAssertEqual(otherAccount.wrappedValue, "Other account, first peer")
    }

    func testConversationHistoryBookmarkStaysWithAccountAndPeerAcrossRouteRolesAndBack() {
        let router = Router()
        let accountID = 847
        let peer = User(username: "Selected peer", id: 765826)
        let bookmark = router.conversationScrollBookmark(for: peer.id, accountID: accountID)
        bookmark.messageKey = "older-history-message"
        bookmark.isAtEndOfChat = false

        router.presentMessagesConversation(peer)
        router.openProfile(peer)
        router.openConversation(peer)
        XCTAssertEqual(router.path, [
            .messagesConversation(peer.id), .profile(playerID: peer.id, selectionID: nil),
            .conversation(peer.id),
        ])

        for _ in 0..<3 {
            let current = router.conversationScrollBookmark(for: peer.id, accountID: accountID)
            XCTAssertTrue(current === bookmark)
            XCTAssertEqual(current.messageKey, "older-history-message")
            XCTAssertFalse(current.isAtEndOfChat)
            router.path.removeLast()
        }
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.users.isEmpty)
        let returned = router.conversationScrollBookmark(for: peer.id, accountID: accountID)
        XCTAssertTrue(returned === bookmark)
        XCTAssertEqual(returned.messageKey, "older-history-message")
        XCTAssertFalse(returned.isAtEndOfChat)

        let otherAccount = router.conversationScrollBookmark(for: peer.id, accountID: accountID + 1)
        let otherPeer = router.conversationScrollBookmark(for: peer.id + 1, accountID: accountID)
        for fresh in [otherAccount, otherPeer] {
            XCTAssertFalse(fresh === bookmark)
            XCTAssertNil(fresh.messageKey)
            XCTAssertTrue(fresh.isAtEndOfChat)
        }
    }

    func testConversationHistoryBookmarkUsesMiddleVisibleMessageInTranscriptOrder() {
        let bookmark = PrivateMessageScrollBookmark()
        bookmark.isAtEndOfChat = false
        let orderedKeys = (1...50).map { "history-\($0)" }

        bookmark.rememberVisibleMessages(
            ["history-42", "history-38", "unknown", "history-40", "history-39", "history-41", "history-39"],
            orderedKeys: orderedKeys
        )

        XCTAssertEqual(bookmark.messageKey, "history-40")
        XCTAssertFalse(bookmark.isAtEndOfChat)
    }

    func testConversationHistoryBookmarkIgnoresMissingTargetsAndLatestMode() {
        let bookmark = PrivateMessageScrollBookmark()
        bookmark.isAtEndOfChat = false
        bookmark.messageKey = "retained-history"

        bookmark.rememberVisibleMessages([], orderedKeys: ["another-message"])
        bookmark.rememberVisibleMessages(["removed-message"], orderedKeys: ["another-message"])
        XCTAssertEqual(bookmark.messageKey, "retained-history")

        bookmark.isAtEndOfChat = true
        bookmark.rememberVisibleMessages(["latest-message"], orderedKeys: ["latest-message"])
        XCTAssertEqual(bookmark.messageKey, "retained-history")
        XCTAssertTrue(bookmark.isAtEndOfChat)
    }

    func testChangingToColumnsKeepsCoveredProfileChallengeAndMessageDraft() throws {
        let router = Router()
        router.presentMessagesConversation(firstPlayer)
        router.openProfile(secondPlayer)
        router.openChallenge(for: secondPlayer)
        let challengeDraft = try XCTUnwrap(router.drafts.values.first)
        edit(challengeDraft)
        let messageDraft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        messageDraft.wrappedValue = "Keep composing"

        router.showMessagesColumns(true, peer: firstPlayer)

        XCTAssertEqual(router.path, [
            .profile(playerID: secondPlayer.id, selectionID: nil), .challenge(challengeDraft.id),
        ])
        XCTAssertTrue(router.drafts[challengeDraft.id] === challengeDraft)
        assertEditsRetained(challengeDraft)
        XCTAssertEqual(router.users[secondPlayer.id]?.id, secondPlayer.id)
        XCTAssertNil(router.users[firstPlayer.id],
                     "The wide root owns its selected peer independently of the route cache.")
        XCTAssertEqual(messageDraft.wrappedValue, "Keep composing")
    }

    func testReturningToInboxAndSelectingAnotherCompactPeerKeepsBothDrafts() {
        let router = Router()
        let first = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        let second = router.conversationDraft(for: secondPlayer.id, accountID: viewerID)
        first.wrappedValue = "First peer's unfinished message"
        second.wrappedValue = "Second peer's unfinished message"
        router.presentMessagesConversation(firstPlayer)

        router.path.removeLast()
        XCTAssertTrue(router.path.isEmpty)
        router.presentMessagesConversation(secondPlayer)
        XCTAssertEqual(router.path, [.messagesConversation(secondPlayer.id)])
        XCTAssertEqual(first.wrappedValue, "First peer's unfinished message")
        XCTAssertEqual(second.wrappedValue, "Second peer's unfinished message")
        router.path.removeLast()
        XCTAssertTrue(router.users.isEmpty)
        router.presentMessagesConversation(firstPlayer)
        XCTAssertEqual(router.path, [.messagesConversation(firstPlayer.id)])
        XCTAssertEqual(first.wrappedValue, "First peer's unfinished message")
        XCTAssertEqual(second.wrappedValue, "Second peer's unfinished message")
    }

    func testMessagesFullHistoryBackPreservesOriginsAndMessageDraft() throws {
        let router = Router()
        router.presentMessagesConversation(firstPlayer)
        router.openProfile(secondPlayer)
        router.openChallenge(for: secondPlayer)
        let challengeDraft = try XCTUnwrap(router.drafts.values.first)
        edit(challengeDraft)
        let messageDraft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        messageDraft.wrappedValue = "Retain while backing out"
        let profile = StackRoute.profile(playerID: secondPlayer.id, selectionID: nil)

        XCTAssertEqual(router.path, [
            .messagesConversation(firstPlayer.id), profile, .challenge(challengeDraft.id),
        ])
        assertEditsRetained(challengeDraft)

        router.path.removeLast()

        XCTAssertEqual(router.path, [.messagesConversation(firstPlayer.id), profile])
        XCTAssertNil(router.drafts[challengeDraft.id])
        XCTAssertEqual(router.users[secondPlayer.id]?.id, secondPlayer.id)
        XCTAssertEqual(messageDraft.wrappedValue, "Retain while backing out")

        router.path.removeLast()

        XCTAssertEqual(router.path, [.messagesConversation(firstPlayer.id)])
        XCTAssertNil(router.users[secondPlayer.id])
        XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)
        XCTAssertEqual(messageDraft.wrappedValue, "Retain while backing out")

        router.path.removeLast()

        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.users.isEmpty)
        XCTAssertEqual(messageDraft.wrappedValue, "Retain while backing out")
    }

    func testWideRootProfileChallengeBackReturnsToInboxAndKeepsMessageDraft() throws {
        let router = Router()
        let messageDraft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        messageDraft.wrappedValue = "Keep the wide recipient's draft"
        router.openProfile(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let challengeDraft = try XCTUnwrap(router.drafts.values.first)
        edit(challengeDraft)
        let profile = StackRoute.profile(playerID: firstPlayer.id, selectionID: nil)

        XCTAssertEqual(router.path, [profile, .challenge(challengeDraft.id)])
        assertEditsRetained(challengeDraft)

        router.path.removeLast()

        XCTAssertEqual(router.path, [profile])
        XCTAssertNil(router.drafts[challengeDraft.id])
        XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)

        router.path.removeLast()

        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.users.isEmpty)
        XCTAssertEqual(messageDraft.wrappedValue, "Keep the wide recipient's draft")
    }

    func testRepeatedPoseChangesPreserveSamePeerProfileMessageAndChallengeSuffix() throws {
        let router = Router()
        router.presentMessagesConversation(firstPlayer)
        router.openProfile(firstPlayer)
        router.openConversation(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let challengeDraft = try XCTUnwrap(router.drafts.values.first)
        edit(challengeDraft)
        let messageDraft = router.conversationDraft(for: firstPlayer.id, accountID: viewerID)
        messageDraft.wrappedValue = "Keep across pose changes"
        let coveredRoutes: [StackRoute] = [
            .profile(playerID: firstPlayer.id, selectionID: nil),
            .conversation(firstPlayer.id), .challenge(challengeDraft.id),
        ]

        for usesColumns in [true, false, true, false] {
            router.showMessagesColumns(usesColumns, peer: firstPlayer)

            let compactRoot: [StackRoute] = usesColumns ? [] : [.messagesConversation(firstPlayer.id)]
            XCTAssertEqual(router.path, compactRoot + coveredRoutes,
                           "Only the compact root route may change while destinations cover Messages.")
            XCTAssertTrue(router.drafts[challengeDraft.id] === challengeDraft)
            assertEditsRetained(challengeDraft)
            XCTAssertEqual(messageDraft.wrappedValue, "Keep across pose changes")
            XCTAssertEqual(router.users[firstPlayer.id]?.id, firstPlayer.id)
        }
    }

    func testPoseNormalizationWithoutRootPeerKeepsProfileMessageHistory() {
        let router = Router()
        router.openProfile(firstPlayer)
        router.openConversation(secondPlayer)
        let history = router.path

        router.showMessagesColumns(false, peer: nil)
        XCTAssertEqual(router.path, history)
        router.showMessagesColumns(true, peer: nil)
        XCTAssertEqual(router.path, history)
        XCTAssertEqual(Set(router.users.keys), [firstPlayer.id, secondPlayer.id])
    }

    private func pickerID(in router: Router) throws -> UUID {
        let id: UUID?
        if case .opponentPicker(let pickerID) = router.path.last { id = pickerID }
        else { id = nil }
        return try XCTUnwrap(id, "Expected the test setup to present an opponent picker")
    }

    private func edit(_ draft: Draft) {
        draft.gameName = "Preserved draft"
        draft.isRanked = false
        draft.isPrivate = true
        draft.boardWidth = 13
        draft.boardHeight = 13
        draft.timeControlSpeed = .correspondence
        draft.pauseOnWeekend = false
        draft.handicap = 3
        draft.automaticColor = false
        draft.yourColor = .white
        draft.rulesSet = .chinese
        draft.komi = 7.5
        draft.analysisDisabled = true
    }

    private func assertEditsRetained(_ draft: Draft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(draft.gameName, "Preserved draft", file: file, line: line)
        XCTAssertFalse(draft.isRanked, file: file, line: line)
        XCTAssertTrue(draft.isPrivate, file: file, line: line)
        XCTAssertEqual(draft.boardWidth, 13, file: file, line: line)
        XCTAssertEqual(draft.boardHeight, 13, file: file, line: line)
        XCTAssertEqual(draft.timeControlSpeed, .correspondence, file: file, line: line)
        XCTAssertFalse(draft.pauseOnWeekend, file: file, line: line)
        XCTAssertEqual(draft.handicap, 3, file: file, line: line)
        XCTAssertFalse(draft.automaticColor, file: file, line: line)
        XCTAssertEqual(draft.yourColor, .white, file: file, line: line)
        XCTAssertEqual(draft.rulesSet, .chinese, file: file, line: line)
        XCTAssertEqual(draft.komi, 7.5, file: file, line: line)
        XCTAssertTrue(draft.analysisDisabled, file: file, line: line)
    }

    func testNestedChallengeReusesExistingDraftAndKeepsGameAncestor() throws {
        let router = Router()
        router.present(.homeGame)
        router.openProfile(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let draft = try XCTUnwrap(router.drafts.values.first)
        edit(draft)
        router.openOpponentPicker(for: draft)
        let selectionID = try pickerID(in: router)
        router.openProfile(secondPlayer, selectionID: selectionID)

        router.openChallenge(for: secondPlayer)

        XCTAssertEqual(router.path, [
            .homeGame, .profile(playerID: firstPlayer.id, selectionID: nil), .challenge(draft.id),
        ])
        XCTAssertEqual(router.drafts.count, 1)
        XCTAssertTrue(router.drafts[draft.id] === draft)
        XCTAssertEqual(draft.opponent?.id, secondPlayer.id)
        XCTAssertEqual(draft.challenge.challenged?.id, secondPlayer.id)
        XCTAssertFalse(draft.isOpen)
        XCTAssertTrue(router.selections.isEmpty)
        assertEditsRetained(draft)
    }

    func testRepeatedProfileSelectionsReturnToSameEditedDraft() throws {
        let router = Router()
        router.openChallenge(for: firstPlayer)
        let draft = try XCTUnwrap(router.drafts.values.first)
        edit(draft)

        for player in [secondPlayer, firstPlayer, secondPlayer] {
            router.openOpponentPicker(for: draft)
            let selectionID = try pickerID(in: router)
            router.openProfile(player, selectionID: selectionID)
            router.selectOpponent(player, selectionID: selectionID, viewerID: viewerID)

            XCTAssertEqual(router.path, [.challenge(draft.id)])
            XCTAssertTrue(router.drafts[draft.id] === draft)
            XCTAssertEqual(draft.opponent?.id, player.id)
            XCTAssertEqual(draft.challenge.challenged?.id, player.id)
            XCTAssertTrue(router.selections.isEmpty)
            assertEditsRetained(draft)
        }
    }

    func testRootDraftSurvivesPickerAndProfileSelectionWithoutCreatingAnotherChallenge() throws {
        let router = Router()
        let draft = Draft()
        edit(draft)
        router.openOpponentPicker(for: draft)
        let selectionID = try pickerID(in: router)
        router.openProfile(secondPlayer, selectionID: selectionID)

        router.selectOpponent(secondPlayer, selectionID: selectionID, viewerID: viewerID)

        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(draft.opponent?.id, secondPlayer.id)
        XCTAssertFalse(draft.isOpen)
        XCTAssertTrue(router.selections.isEmpty)
        assertEditsRetained(draft)
    }

    func testInspectingAndBackingOutOfSavedSettingsProfileDoesNotInvokeCallback() throws {
        let router = Router()
        var selectedIDs: [Int] = []
        router.openSavedSettingsOpponentPicker { selectedIDs.append($0.id) }
        let selectionID = try pickerID(in: router)
        router.openProfile(firstPlayer, selectionID: selectionID)
        XCTAssertTrue(selectedIDs.isEmpty)

        router.remove(.profile(playerID: firstPlayer.id, selectionID: selectionID))
        XCTAssertEqual(router.path, [.opponentPicker(selectionID)])
        XCTAssertNotNil(router.selections[selectionID])
        XCTAssertTrue(selectedIDs.isEmpty)

        router.remove(.opponentPicker(selectionID))
        router.selectOpponent(firstPlayer, selectionID: selectionID, viewerID: viewerID)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.selections.isEmpty)
        XCTAssertTrue(selectedIDs.isEmpty, "A stale selection must not submit a saved challenge.")
    }

    func testSavedSettingsSelectionConsumesCallbackBeforeReentryAndDuplicateTap() throws {
        let router = Router()
        var selectedIDs: [Int] = []
        var selectionID: UUID?
        router.openSavedSettingsOpponentPicker { [self] user in
            selectedIDs.append(user.id)
            XCTAssertTrue(router.path.isEmpty)
            XCTAssertTrue(router.selections.isEmpty)
            if let selectionID {
                router.selectOpponent(secondPlayer, selectionID: selectionID, viewerID: viewerID)
            }
        }
        let id = try pickerID(in: router)
        selectionID = id
        router.openProfile(firstPlayer, selectionID: id)

        router.selectOpponent(firstPlayer, selectionID: id, viewerID: viewerID)
        router.selectOpponent(secondPlayer, selectionID: id, viewerID: viewerID)

        XCTAssertEqual(selectedIDs, [firstPlayer.id])
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertTrue(router.drafts.isEmpty)
    }

    func testInvalidAndSelfSelectionKeepPickerAvailableWithoutCallingOut() throws {
        let router = Router()
        var callbacks = 0
        router.openSavedSettingsOpponentPicker { _ in callbacks += 1 }
        let id = try pickerID(in: router)
        for user in [User(username: "Invalid", id: 0), User(username: "Self", id: viewerID)] {
            router.selectOpponent(user, selectionID: id, viewerID: viewerID)
            XCTAssertEqual(router.path, [.opponentPicker(id)])
            XCTAssertNotNil(router.selections[id])
            XCTAssertEqual(callbacks, 0)
        }
        router.openProfile(firstPlayer, selectionID: UUID())
        XCTAssertEqual(router.path, [.opponentPicker(id)])
    }

    func testPoppingRoutesReleasesOnlyTheirOwnedDraftAndSelection() throws {
        let router = Router()
        router.openProfile(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let draft = try XCTUnwrap(router.drafts.values.first)
        router.openOpponentPicker(for: draft)
        let id = try pickerID(in: router)
        router.openProfile(secondPlayer, selectionID: id)

        router.remove(.profile(playerID: secondPlayer.id, selectionID: id))
        XCTAssertTrue(router.drafts[draft.id] === draft)
        XCTAssertNotNil(router.selections[id])
        router.remove(.opponentPicker(id))
        XCTAssertTrue(router.drafts[draft.id] === draft)
        XCTAssertTrue(router.selections.isEmpty)
        router.remove(.challenge(draft.id))
        XCTAssertTrue(router.drafts.isEmpty)
        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: nil)])
    }

    func testResetPreservesGameAncestorAndDiscardsProfileFlowState() throws {
        let router = Router()
        router.present(.homeGame)
        router.openProfile(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let draft = try XCTUnwrap(router.drafts.values.first)
        router.openOpponentPicker(for: draft)
        let id = try pickerID(in: router)
        router.openProfile(secondPlayer, selectionID: id)

        router.reset(preserving: .homeGame)

        XCTAssertEqual(router.path, [.homeGame])
        XCTAssertTrue(router.users.isEmpty)
        XCTAssertTrue(router.drafts.isEmpty)
        XCTAssertTrue(router.selections.isEmpty)
        router.reset(preserving: .publicGame)
        XCTAssertTrue(router.path.isEmpty, "A missing preserved route should return to the stack root.")
    }

    func testSystemPathPopReleasesChallengeAndPickerState() throws {
        let router = Router()
        router.openProfile(firstPlayer)
        router.openChallenge(for: firstPlayer)
        let draft = try XCTUnwrap(router.drafts.values.first)
        router.openOpponentPicker(for: draft)
        _ = try pickerID(in: router)

        router.path.removeLast()
        XCTAssertTrue(router.selections.isEmpty)
        XCTAssertTrue(router.drafts[draft.id] === draft)
        router.path.removeLast()
        XCTAssertTrue(router.drafts.isEmpty)
        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: nil)])
    }

    func testRootPickerCanSelectAgainAfterReturningFromProfile() {
        let router = Router()
        var selected: User?
        let registration = router.registerRootPicker(user: Binding(
            get: { selected }, set: { selected = $0 }
        ))
        withExtendedLifetime(registration) {
            let selection = registration.selection
            for player in [firstPlayer, secondPlayer] {
                router.openProfile(player, selectionID: selection.id)
                router.selectOpponent(player, selectionID: selection.id, viewerID: viewerID)
                XCTAssertTrue(router.path.isEmpty)
                XCTAssertNotNil(router.selections[selection.id])
                XCTAssertEqual(selected?.id, player.id)
                XCTAssertEqual(selection.selectedUser()?.id, player.id)
            }
        }
    }

    func testRootPickerRegistrationSurvivesCoveringButEndsWithItsOwner() {
        let router = Router()
        var selected: User?
        var registration: RootOpponentSelection? = router.registerRootPicker(user: Binding(
            get: { selected }, set: { selected = $0 }
        ))
        let id = registration!.selection.id
        router.openProfile(firstPlayer, selectionID: id)
        router.setActive(false)
        XCTAssertNotNil(router.selections[id])

        registration = nil

        XCTAssertNil(router.selections[id])
        router.selectOpponent(firstPlayer, selectionID: id, viewerID: viewerID)
        XCTAssertNil(selected, "A destroyed root picker must no longer receive selections.")
        router.openProfile(secondPlayer, selectionID: id)
        XCTAssertEqual(router.path, [.profile(playerID: firstPlayer.id, selectionID: id)])
    }

    func testRootPickerRegistrationDoesNotRetainRouter() {
        var router: Router? = Router()
        weak var retainedRouter = router
        let registration = router!.registerRootPicker(user: .constant(nil))

        router = nil

        withExtendedLifetime(registration) {
            XCTAssertNil(retainedRouter)
        }
    }

    func testUserCacheRetainsOnlyPlayersReferencedByRemainingRoutes() {
        let router = Router()
        router.openProfile(firstPlayer)
        router.openConversation(firstPlayer)
        router.openProfile(secondPlayer)
        XCTAssertEqual(Set(router.users.keys), [firstPlayer.id, secondPlayer.id])

        router.path.removeLast()

        XCTAssertEqual(Set(router.users.keys), [firstPlayer.id])
        router.path.removeLast()
        XCTAssertNotNil(router.users[firstPlayer.id], "The earlier profile still needs this player.")
        router.reset(preserving: nil)
        XCTAssertTrue(router.users.isEmpty)
    }

    func testAnotherPickerRequestReusesTheSingleActiveDraft() throws {
        let router = Router()
        let firstDraft = Draft()
        edit(firstDraft)
        router.openOpponentPicker(for: firstDraft)
        let firstSelection = try pickerID(in: router)
        router.openProfile(firstPlayer, selectionID: firstSelection)

        router.openOpponentPicker(for: Draft())

        XCTAssertEqual(router.path, [.opponentPicker(firstSelection)])
        XCTAssertEqual(router.drafts.count, 1)
        XCTAssertTrue(router.drafts[firstDraft.id] === firstDraft)
        assertEditsRetained(firstDraft)
        XCTAssertTrue(router.users.isEmpty)
    }

    func testLiveGameReplacesHistoryBeforeItsBindingFinishesClosing() {
        for includesHistoryGame in [false, true] {
            let router = Router()
            router.present(.gameHistory)
            if includesHistoryGame {
                router.present(.historyGame)
                router.openProfile(firstPlayer)
            }

            router.present(.homeGame)
            router.remove(.gameHistory)
            router.remove(.historyGame)

            XCTAssertEqual(router.path, [.homeGame])
            XCTAssertTrue(router.users.isEmpty)
        }
    }

    func testLiveGameOpensAfterHistoryBindingFinishesClosing() {
        let router = Router()
        router.present(.gameHistory)
        router.present(.historyGame)

        router.remove(.gameHistory)
        router.present(.homeGame)

        XCTAssertEqual(router.path, [.homeGame])
    }

    func testHistoryReplacesHomeGameBeforeItsBindingFinishesClosing() {
        let router = Router()
        router.present(.homeGame)
        router.openProfile(firstPlayer)

        router.present(.gameHistory)
        router.remove(.homeGame)

        XCTAssertEqual(router.path, [.gameHistory])
        XCTAssertTrue(router.users.isEmpty)
    }

    @MainActor
    func testClosingHistoryBranchClearsItsGameWithoutDiscardingNewHomeGame() {
        let nav = NavigationService()
        let homeGame = Game(
            width: 13, height: 13, blackName: "Home Black", whiteName: "Home White",
            gameId: .OGS(43)
        )
        nav.home.activeGame = homeGame
        nav.home.activeGameShowsCarousel = false
        nav.home.showingGameHistory = true
        nav.gameHistory.activeGame = Game(
            width: 19, height: 19, blackName: "History Black", whiteName: "History White",
            gameId: .OGS(42)
        )

        nav.closeGameHistory()

        XCTAssertFalse(nav.home.showingGameHistory)
        XCTAssertNil(nav.gameHistory.activeGame)
        XCTAssertTrue(nav.home.activeGame === homeGame)
        XCTAssertFalse(nav.home.activeGameShowsCarousel)
    }
}
