import SwiftUI
import XCTest

final class StackRouterTests: XCTestCase {
    private typealias Router = StackRouter
    private typealias User = OGSUser
    private typealias Draft = ChallengeDraft

    private let viewerID = 100
    private var firstPlayer: User { User(username: "First player", id: 101) }
    private var secondPlayer: User { User(username: "Second player", id: 102) }

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
