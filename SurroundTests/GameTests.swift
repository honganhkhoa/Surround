//
//  GameTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 21/05/2021.
//

import XCTest
import DictionaryCoding
import Combine

class GameTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParsingOngoingGameWithFreeHandicapPlacement() throws {
        let game = GameTests.sampleGame(ogsId: 26268396)
        
        XCTAssertNil(game.gameData?.outcome)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 81)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(13, 13))
        XCTAssertEqual(game.currentPosition.nextToMove, .black)

        XCTAssertEqual(game.positionByLastMoveNumber[2]?.nextToMove, .black)
        XCTAssertEqual(game.positionByLastMoveNumber[3]?.nextToMove, .black)
        XCTAssertEqual(game.positionByLastMoveNumber[8]?.nextToMove, .white)
        
        BoardPositionTests.assertPositionEqual(position: game.currentPosition, visualStrings: [
            "-------------------",
            "-------------------",
            "------b-----b------",
            "-b-b-b-b-b---b-b---",
            "-wb---b---------bb-",
            "-------------b-ww--",
            "-------------------",
            "-bb-----------b-w--",
            "-wb----------------",
            "-w-b-----b---bbb-w-",
            "--w----------bwbw--",
            "--wbbbb---bbbw-bbw-",
            "---wwbwb--bwww-bw--",
            "--w--wwb-ww--wbbw--",
            "-------ww-----ww---",
            "---b-----b----wb---",
            "--w----w-------ww--",
            "-------------------",
            "-------------------"
        ])
    }

    func testGameDeallocatesWhenOnlyPlayerCacheSubscriptionRemains() {
        let service = OGSService.previewInstance()
        weak var weakGame: Game?

        withExtendedLifetime(service) {
            var game: Game? = Game(
                width: 5,
                height: 5,
                blackName: "black",
                whiteName: "white",
                gameId: .OGS(1)
            )
            weakGame = game
            game?.ogs = service

            XCTAssertNotNil(game?.playerCacheObservingCancellable)
            game = nil
            XCTAssertNil(weakGame)

            // Break the historical cycle if this assertion is run against a
            // regressed implementation, so the failed test cleans up after itself.
            weakGame?.ogs = nil
        }
    }

    func testPlayerCacheRefreshPublishesOneRosterAndSkipsUnchangedValues() {
        let game = Game(width: 5, height: 5, blackName: "Black", whiteName: "White", gameId: .OGS(1))
        game.blackPlayer = OGSUser(username: "Black", id: -101)
        game.whitePlayer = OGSUser(username: "White", id: -102)
        var black = game.blackPlayer!
        var white = game.whitePlayer!
        black.icon = "https://example.invalid/black.png"
        white.icon = "https://example.invalid/white.png"
        var rosters = [[Int: OGSUser]]()
        var changes = 0
        let rosterObservation = game.$playerByOGSId.dropFirst().sink { rosters.append($0) }
        let gameObservation = game.objectWillChange.sink { changes += 1 }
        defer {
            rosterObservation.cancel()
            gameObservation.cancel()
        }

        game.mergeCachedPlayers([black.id: black, white.id: white])

        XCTAssertEqual(rosters.count, 1)
        XCTAssertEqual(rosters.first?[black.id]?.icon, black.icon)
        XCTAssertEqual(rosters.first?[white.id]?.icon, white.icon)
        XCTAssertEqual(game.blackPlayer?.icon, black.icon)
        XCTAssertEqual(game.whitePlayer?.icon, white.icon)

        changes = 0
        game.mergeCachedPlayers([black.id: black, white.id: white])
        XCTAssertEqual(rosters.count, 1)
        XCTAssertEqual(changes, 0)
    }

    func testAnalysisAvailabilityRespectsDisabledSettingUntilGameFinishes() throws {
        let game = GameTests.sampleGame(ogsId: 26_268_396)
        game.gameData?.disableAnalysis = true

        let participant = try XCTUnwrap(game.blackPlayer)
        let participantService = OGSService.previewInstance(user: participant)
        withExtendedLifetime(participantService) {
            game.ogs = participantService

            game.gamePhase = .play
            XCTAssertTrue(game.isUserPlaying)
            XCTAssertFalse(game.analysisAvailable)

            game.autoScoringDone = true
            game.gamePhase = .stoneRemoval
            XCTAssertFalse(game.analysisAvailable)

            game.gamePhase = .finished
            XCTAssertTrue(game.analysisAvailable)
        }

        let spectatorService = OGSService.previewInstance(
            user: OGSUser(username: "Spectator", id: -1)
        )
        withExtendedLifetime(spectatorService) {
            game.ogs = spectatorService
            game.gamePhase = .play
            XCTAssertFalse(game.isUserPlaying)
            XCTAssertTrue(game.analysisAvailable)
        }
    }

    func testRequiresUserActionUsesAcceptanceDuringStoneRemoval() throws {
        let game = GameTests.sampleGame(ogsId: 27_053_412)
        let blackId = try XCTUnwrap(game.blackPlayer?.id)
        let whiteId = try XCTUnwrap(game.whitePlayer?.id)
        let removedStones = try XCTUnwrap(game.currentPosition.removedStones)

        XCTAssertEqual(game.gamePhase, .stoneRemoval)
        XCTAssertEqual(game.clock?.currentPlayerId, blackId)
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: blackId))
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: whiteId))
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: -1))

        game.removedStonesAccepted[.black] = []
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: blackId))

        game.removedStonesAccepted[.black] = removedStones
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: blackId))
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: whiteId))

        game.removedStonesAccepted[.white] = removedStones
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: blackId))
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: whiteId))
    }

    func testRequiresUserActionUsesClockOutsideStoneRemoval() throws {
        let game = GameTests.sampleGame(ogsId: 27_053_412)
        let blackId = try XCTUnwrap(game.blackPlayer?.id)
        let whiteId = try XCTUnwrap(game.whitePlayer?.id)

        game.gamePhase = .play
        XCTAssertEqual(game.clock?.currentPlayerId, blackId)
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: blackId))
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: whiteId))

        game.gamePhase = .finished
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: blackId))
        XCTAssertFalse(game.requiresUserAction(forPlayerWithId: whiteId))
    }
    
    func testMarkAllChatAsReadPublishesOnlyWhenUnreadCountChanges() throws {
        let suite = "GameTests.chat-read.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(42))
        game.preferences = preferences
        game.addChatLine(try chatLine(id: "first", timestamp: 1))
        XCTAssertEqual(game.chatUnreadCount, 1)

        var changes = 0
        let observation = game.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }

        game.markAllChatAsRead()
        XCTAssertEqual(game.chatUnreadCount, 0)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(preferences[.lastSeenChatIdByOGSGameId]?[42], "first")

        game.markAllChatAsRead()
        game.markAllChatAsRead()
        XCTAssertEqual(changes, 1, "Repeated appearance callbacks must not invalidate the game again.")

        game.addChatLine(try chatLine(id: "second", timestamp: 2))
        XCTAssertEqual(game.chatUnreadCount, 1)
        let changesBeforeReading = changes
        game.markAllChatAsRead()
        XCTAssertEqual(game.chatUnreadCount, 0)
        XCTAssertEqual(changes, changesBeforeReading + 1)
        XCTAssertEqual(preferences[.lastSeenChatIdByOGSGameId]?[42], "second")
        game.markAllChatAsRead()
        XCTAssertEqual(changes, changesBeforeReading + 1)
    }

    func testMarkAllChatAsReadUpdatesReadPositionWhenCountIsAlreadyZero() throws {
        let suite = "GameTests.chat-read-position.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(43))
        game.preferences = preferences
        game.chatLog = [
            try chatLine(id: "first", timestamp: 1),
            try chatLine(id: "second", timestamp: 2),
        ]
        XCTAssertEqual(game.chatUnreadCount, 0)

        var changes = 0
        let observation = game.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }
        game.markAllChatAsRead()
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(preferences[.lastSeenChatIdByOGSGameId]?[43], "second")

        // The read index still has to advance, even without a count change.
        game.addChatLine(try chatLine(id: "third", timestamp: 3))
        XCTAssertEqual(game.chatUnreadCount, 1)
        game.markAllChatAsRead()
        XCTAssertEqual(game.chatUnreadCount, 0)
        XCTAssertEqual(preferences[.lastSeenChatIdByOGSGameId]?[43], "third")
    }

    func testRengoUpdateWaitsForMissingPlayersWithoutChangingOrder() {
        let game = GameTests.sampleGame(ogsId: 26_268_396)
        game.gameData?.rengo = true
        let black = OGSUser(username: "Black", id: -101)
        let white = OGSUser(username: "White", id: -102)
        let missing = OGSUser(username: "Arriving player", id: -103)
        game.playerByOGSId = [black.id: black, white.id: white]
        game.latestPlayerUpdate = OGSPlayerUpdate(
            rengoTeams: .init(black: [missing.id, black.id], white: [white.id])
        )

        XCTAssertTrue(game.hasUnresolvedRengoPlayers)
        XCTAssertNil(game.orderedRengoTeam[.black])
        XCTAssertNil(game.currentPlayer(with: .black))
        XCTAssertEqual(game.currentPlayer(with: .white)?.id, white.id)

        // A move without another team update must not forget the pending order.
        game.latestPlayerUpdate = nil
        game.mergeCachedPlayers([missing.id: missing])

        XCTAssertFalse(game.hasUnresolvedRengoPlayers)
        XCTAssertEqual(game.orderedRengoTeam[.black]?.map(\.id), [missing.id, black.id])
        XCTAssertEqual(game.currentPlayer(with: .black)?.id, missing.id)
        XCTAssertEqual(game.orderedRengoTeam[.white]?.map(\.id), [white.id])
    }

    func testRengoNewOrderReplacesPendingOrderAndRefreshesPlayerDetails() {
        let game = GameTests.sampleGame(ogsId: 26_268_396)
        game.gameData?.rengo = true
        let first = OGSUser(username: "First", id: -111)
        var second = OGSUser(username: "Second", id: -112)
        game.playerByOGSId = [first.id: first, second.id: second]
        game.latestPlayerUpdate = OGSPlayerUpdate(
            rengoTeams: .init(black: [-113, first.id], white: [second.id])
        )
        game.latestPlayerUpdate = OGSPlayerUpdate(
            rengoTeams: .init(black: [second.id, first.id], white: [])
        )
        game.playerByOGSId[-113] = OGSUser(username: "Obsolete member", id: -113)
        second.icon = "https://example.invalid/avatar.png"
        game.playerByOGSId[second.id] = second

        XCTAssertFalse(game.hasUnresolvedRengoPlayers)
        XCTAssertEqual(game.orderedRengoTeam[.black]?.map(\.id), [second.id, first.id])
        XCTAssertEqual(game.orderedRengoTeam[.black]?.first?.icon, second.icon)
        XCTAssertEqual(game.currentPlayer(with: .black)?.id, second.id)
        XCTAssertEqual(game.orderedRengoTeam[.white], [])
        XCTAssertNil(game.currentPlayer(with: .white))
    }

    func testIncompleteRengoRosterPublishesActivePlayerChanges() {
        let game = GameTests.sampleGame(ogsId: 26_268_396)
        game.gameData?.rengo = true
        let first = OGSUser(username: "First", id: -121)
        let next = OGSUser(username: "Next", id: -122)
        game.playerByOGSId = [first.id: first]
        game.latestPlayerUpdate = OGSPlayerUpdate(
            rengoTeams: .init(black: [first.id, -123], white: [])
        )
        var publications = 0
        let observation = game.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }

        game.latestPlayerUpdate = OGSPlayerUpdate(
            rengoTeams: .init(black: [next.id, -123], white: [])
        )
        XCTAssertGreaterThan(publications, 0)
        XCTAssertNil(game.currentPlayer(with: .black))
        publications = 0
        game.playerByOGSId[next.id] = next

        XCTAssertGreaterThan(publications, 0)
        XCTAssertEqual(game.currentPlayer(with: .black)?.id, next.id)
        XCTAssertNil(game.orderedRengoTeam[.black])
    }

    private func chatLine(id: String, timestamp: Double) throws -> OGSChatLine {
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSChatLine.self, from: [
            "channel": "main",
            "line": [
                "chat_id": id, "date": timestamp, "player_id": 1,
                "username": "player", "body": "Hello",
            ],
        ])
    }

    static func sampleGame(ogsId: Int) -> Game {
        let fileURL = Bundle(for: GameTests.self).url(forResource: "game-\(ogsId)", withExtension: "json")!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try! decoder.decode(OGSGame.self, from: Data(contentsOf: fileURL))
        let game = Game(ogsGame: ogsGame)
        if let chatURL = Bundle.main.url(forResource: "chat-\(ogsId)", withExtension: "json") {
            if let chatLines = try? JSONSerialization.jsonObject(with: Data(contentsOf: chatURL)) as? [[String: Any]] {
                let dictDecoder = DictionaryDecoder()
                dictDecoder.keyDecodingStrategy = .convertFromSnakeCase
                for chatLine in chatLines {
                    if let line = try? dictDecoder.decode(OGSChatLine.self, from: chatLine) {
                        game.addChatLine(line)
                    }
                }
            }
        }
        return game
    }
}
