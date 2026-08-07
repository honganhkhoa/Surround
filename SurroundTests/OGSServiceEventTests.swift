//
//  OGSServiceEventTests.swift
//  SurroundTests
//

import XCTest
import DictionaryCoding

final class OGSServiceEventTests: XCTestCase {
    private class FakeWebsocket: OGSWebsocketProtocol {
        struct Emission {
            let command: String
            let data: Any
        }

        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks: [() -> Void] = []
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = true
        var opened = true
        var status = OGSWebsocketStatus.connected
        var drift = 0.0
        var latency = 0.0
        var emissions = [Emission]()
        var gamelistResults: [[String: Any]]?
        private(set) var closeThenReconnectCount = 0
        var onCloseThenReconnect: (() -> Void)?

        func connect() {
            openSocket()
        }

        func openSocket(authenticate: Bool = false) {
            opened = true
            authenticated = false
            status = .connected
            onStatusChanged?()
            let tasks = onConnectTasks
            onConnectTasks = []
            tasks.forEach { $0() }
            deliver(name: "surround/socketOpened")
            if authenticate {
                markAuthenticated()
            }
        }

        func markAuthenticated() {
            authenticated = true
            deliver(name: "surround/socketAuthenticated")
        }

        func dropSocket() {
            opened = false
            authenticated = false
            status = .reconnecting
            onStatusChanged?()
            deliver(name: "surround/socketClosed")
        }

        func close() {
            opened = false
            authenticated = false
            status = .disconnected
            onStatusChanged?()
        }

        func reconnectIfNeeded() {}
        func closeThenReconnect() {
            closeThenReconnectCount += 1
            onCloseThenReconnect?()
            dropSocket()
        }

        func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
            emissions.append(.init(command: command, data: data))
            if command == "gamelist/query", let gamelistResults {
                resultCallback?(["results": gamelistResults], nil)
            } else {
                resultCallback?(nil, nil)
            }
        }

        func deliver(name: String, data: Any? = nil) {
            serverEventCallback?(name, data)
        }
    }

    private var preferenceSuite: String!

    override func tearDown() {
        if let preferenceSuite {
            UserDefaults.standard.removePersistentDomain(forName: preferenceSuite)
        }
        super.tearDown()
    }

    func testGameEventsUpdateConnectedGameAndReconnectSubscription() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let gameData = try makeEmptyGameData(id: 42)
        let game = Game(ogsGame: gameData)
        game.ogs = service

        service.connect(to: game, owner: .explicit(UUID()))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/connect"])

        socket.deliver(name: "game/42/move", data: ["move": [0, 0, 125, false]])
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(0, 0))
        XCTAssertEqual(game.currentPosition[0, 0], .hasStone(.black))

        socket.deliver(name: "game/42/undo_requested", data: 1)
        XCTAssertEqual(game.undoRequest, OGSUndoRequest(moveNumber: 1))

        socket.deliver(name: "game/42/undo_accepted", data: 1)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)

        socket.deliver(name: "game/42/phase", data: "stone removal")
        XCTAssertEqual(game.gamePhase, .stoneRemoval)

        socket.dropSocket()
        socket.openSocket(authenticate: true)
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 2)
    }

    func testUndoRequestEventsSupportObjectStringAndCancellation() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 142))
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))

        socket.deliver(name: "game/142/undo_requested", data: "7")
        XCTAssertEqual(game.undoRequest, OGSUndoRequest(moveNumber: 7))

        socket.deliver(
            name: "game/142/undo_requested",
            data: [
                "move_number": "8",
                "requested_by": 123,
                "undo_move_count": 0,
            ]
        )
        XCTAssertEqual(
            game.undoRequest,
            OGSUndoRequest(moveNumber: 8, requestedBy: 123, moveCount: 1)
        )

        socket.deliver(name: "game/142/undo_requested", data: true)
        XCTAssertEqual(
            game.undoRequest,
            OGSUndoRequest(moveNumber: 8, requestedBy: 123, moveCount: 1)
        )

        socket.deliver(
            name: "game/142/undo_requested",
            data: ["move_number": "not-a-move"]
        )
        XCTAssertEqual(
            game.undoRequest,
            OGSUndoRequest(moveNumber: 8, requestedBy: 123, moveCount: 1)
        )

        socket.deliver(name: "game/142/undo_canceled")
        XCTAssertNil(game.undoRequest)
    }

    func testUndoAcceptedUsesPositiveObjectMoveCount() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 143))
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(0, 0))
        try game.makeMove(move: .placeStone(1, 0))
        let requesterID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/143/undo_requested",
            data: [
                "move_number": 2,
                "requested_by": requesterID,
                "undo_move_count": 1,
            ]
        )
        socket.deliver(
            name: "game/143/undo_accepted",
            data: ["move_number": 2, "undo_move_count": 2]
        )

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.currentPosition.lastMove)
        XCTAssertNil(game.undoRequest)
    }

    func testLegacyUndoAcceptedFallsBackToRequestedMoveCount() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 150))
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(0, 0))
        try game.makeMove(move: .placeStone(1, 0))

        socket.deliver(
            name: "game/150/undo_requested",
            data: ["move_number": 2, "undo_move_count": 2]
        )
        socket.deliver(name: "game/150/undo_accepted", data: 2)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.undoRequest)
    }

    func testUndoAcceptedWithoutPendingRequestResynchronizesOnlyThatGame() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        let game = Game(ogsGame: try makeEmptyGameData(id: 144))
        let otherGame = Game(ogsGame: try makeEmptyGameData(id: 244))
        game.ogs = service
        otherGame.ogs = service
        let ownerID = UUID()
        service.connect(to: game, withChat: true, owner: .explicit(ownerID))
        service.connect(to: otherGame, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(0, 0))
        try game.makeMove(move: .placeStone(1, 0))
        let staleBranchRoot = try XCTUnwrap(game.positionByLastMoveNumber[1])
        let staleFinalPosition = game.currentPosition
        socket.emissions.removeAll()
        let reconnectCount = socket.closeThenReconnectCount

        socket.deliver(
            name: "game/144/undo_accepted",
            data: ["move_number": 2, "undo_move_count": 2]
        )

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(1, 0))
        XCTAssertNil(game.undoRequest)
        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/disconnect", "chat/part", "game/connect", "chat/join"]
        )
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCount)
        XCTAssertEqual(
            (socket.emissions[0].data as? [String: Any])?["game_id"] as? Int,
            144
        )
        XCTAssertEqual(
            (socket.emissions[2].data as? [String: Any])?["game_id"] as? Int,
            144
        )
        XCTAssertEqual(
            (socket.emissions[2].data as? [String: Any])?["chat"] as? Bool,
            true
        )

        socket.emissions.removeAll()
        socket.deliver(
            name: "game/144/undo_accepted",
            data: ["move_number": 2, "undo_move_count": 2]
        )
        XCTAssertTrue(socket.emissions.isEmpty)

        socket.deliver(
            name: "game/144/gamedata",
            data: try makeEmptyGameDataPayload(id: 144)
        )

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.positionByLastMoveNumber[1])
        XCTAssertNil(game.positionByLastMoveNumber[2])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[1]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[1]?[1] === staleBranchRoot)
        XCTAssertTrue(
            game.moveTree.variation(to: staleFinalPosition)?.basePosition === game.initialPosition
        )

        socket.deliver(name: "game/244/phase", data: "stone removal")
        XCTAssertEqual(otherGame.gamePhase, .stoneRemoval)

        socket.emissions.removeAll()
        service.releaseConnection(gameID: 144, owner: .explicit(ownerID))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "chat/part"])
    }

    func testUndoResynchronizationTimeoutFallsBackToSocketReconnect() throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            installsObservers: false,
            undoResynchronizationTimeout: 0
        )
        let game = Game(ogsGame: try makeEmptyGameData(id: 245))
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(0, 0))
        socket.emissions.removeAll()
        let fallback = expectation(description: "Undo recovery falls back to socket reconnect")
        socket.onCloseThenReconnect = { fallback.fulfill() }

        socket.deliver(
            name: "game/245/undo_accepted",
            data: ["move_number": 1, "undo_move_count": 1]
        )

        wait(for: [fallback], timeout: 1)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)
        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/disconnect", "game/connect"]
        )
        XCTAssertEqual(socket.closeThenReconnectCount, 1)
    }

    func testUndoCommandsUseCurrentMoveNumber() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 145))
        try game.makeMove(move: .placeStone(0, 0))

        service.requestUndo(game: game)
        service.acceptUndo(game: game)
        service.cancelUndo(game: game)

        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/undo/request", "game/undo/accept", "game/undo/cancel"]
        )
        for emission in socket.emissions {
            let payload = try XCTUnwrap(emission.data as? [String: Any])
            XCTAssertEqual(payload["game_id"] as? Int, 145)
            XCTAssertEqual(payload["move_number"] as? Int, 1)
        }
    }

    func testInitialGameDataDecodesLegacyAndObjectUndoRequests() throws {
        XCTAssertEqual(
            try makeEmptyGameData(id: 146, undoRequested: 4).undoRequested,
            OGSUndoRequest(moveNumber: 4)
        )
        XCTAssertEqual(
            try makeEmptyGameData(id: 147, undoRequested: "5").undoRequested,
            OGSUndoRequest(moveNumber: 5)
        )
        XCTAssertEqual(
            try makeEmptyGameData(
                id: 148,
                undoRequested: [
                    "move_number": "6",
                    "requested_by": 321,
                    "undo_move_count": 2,
                ]
            ).undoRequested,
            OGSUndoRequest(moveNumber: 6, requestedBy: 321, moveCount: 2)
        )
        XCTAssertEqual(
            try makeEmptyGameData(
                id: 149,
                undoRequested: ["move_number": 7, "undo_move_count": -3]
            ).undoRequested,
            OGSUndoRequest(moveNumber: 7, moveCount: 1)
        )
    }

    func testReleasedFinishedGameDoesNotConnectWhenSocketOpens() throws {
        let socket = FakeWebsocket()
        socket.dropSocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 43, phase: "finished"))
        game.ogs = service
        let ownerID = UUID()

        service.connect(to: game, withChat: true, owner: .explicit(ownerID))
        service.releaseConnection(gameID: 43, owner: .explicit(ownerID))
        socket.openSocket(authenticate: true)

        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testReleasedPlayerGameDoesNotConnectAfterAuthentication() throws {
        let socket = FakeWebsocket()
        socket.authenticated = false
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 44))
        game.ogs = service
        service.user = game.blackPlayer
        let ownerID = UUID()

        service.connect(to: game, withChat: true, owner: .explicit(ownerID))
        service.releaseConnection(gameID: 44, owner: .explicit(ownerID))
        socket.markAuthenticated()

        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testReleasedFinishedGameDoesNotReconnectAfterSocketDrop() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 45, phase: "finished"))
        game.ogs = service
        let ownerID = UUID()

        service.connect(to: game, withChat: true, owner: .explicit(ownerID))
        socket.emissions.removeAll()
        socket.dropSocket()
        service.releaseConnection(gameID: 45, owner: .explicit(ownerID))
        socket.openSocket(authenticate: true)

        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testStaleSameIDGameCannotReleaseCanonicalConnection() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let canonicalGame = Game(ogsGame: try makeEmptyGameData(id: 48))
        let staleGame = Game(ogsGame: try makeEmptyGameData(id: 48))
        canonicalGame.ogs = service
        staleGame.ogs = service
        let canonicalOwnerID = UUID()
        let staleOwnerID = UUID()

        service.connect(
            to: canonicalGame,
            withChat: true,
            owner: .explicit(canonicalOwnerID)
        )
        service.connect(
            to: staleGame,
            withChat: true,
            owner: .explicit(staleOwnerID)
        )
        socket.emissions.removeAll()
        service.disconnect(from: staleGame, owner: .explicit(staleOwnerID))

        XCTAssertTrue(socket.emissions.isEmpty)
        socket.dropSocket()
        socket.openSocket(authenticate: true)
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 1)
        XCTAssertEqual(socket.emissions.filter { $0.command == "chat/join" }.count, 1)
    }

    func testActiveGameRemainsDesiredWhenDetailReleasesIt() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        socket.deliver(name: "active_game", data: makeShortGameData(id: 46, phase: "play"))
        let game = try XCTUnwrap(service.activeGames[46])
        let detailOwnerID = UUID()
        service.connect(to: game, withChat: true, owner: .detail(detailOwnerID))

        socket.emissions.removeAll()
        socket.dropSocket()
        service.releaseConnection(gameID: 46, owner: .detail(detailOwnerID))
        socket.openSocket(authenticate: true)

        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 1)
    }

    func testFinishedActiveGameReopensWithHistoryModelAsCanonicalConnection() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        var activeEvent = makeShortGameData(id: 49, phase: "play")
        socket.deliver(name: "active_game", data: activeEvent)
        let formerActiveGame = try XCTUnwrap(service.activeGames[49])

        socket.emissions.removeAll()
        activeEvent["phase"] = "finished"
        socket.deliver(name: "active_game", data: activeEvent)

        XCTAssertNil(service.activeGames[49])
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect"])

        let historyGame = Game(ogsGame: try makeEmptyGameData(id: 49, phase: "finished"))
        historyGame.ogs = service
        let detailOwnerID = UUID()
        let connectedGame = service.connect(
            to: historyGame,
            withChat: true,
            owner: .detail(detailOwnerID)
        )

        XCTAssertTrue(connectedGame === historyGame)
        socket.deliver(name: "game/49/phase", data: "stone removal")
        XCTAssertEqual(historyGame.gamePhase, .stoneRemoval)
        XCTAssertNotEqual(formerActiveGame.gamePhase, .stoneRemoval)

        socket.emissions.removeAll()
        service.releaseConnection(gameID: 49, owner: .detail(detailOwnerID))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "chat/part"])

        socket.emissions.removeAll()
        socket.dropSocket()
        socket.openSocket(authenticate: true)
        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
    }

    func testFinishedActiveGameKeepsVisibleDetailOwnerUntilDetailCloses() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        var activeEvent = makeShortGameData(id: 50, phase: "play")
        socket.deliver(name: "active_game", data: activeEvent)
        let game = try XCTUnwrap(service.activeGames[50])
        let detailOwnerID = UUID()
        service.connect(to: game, withChat: true, owner: .detail(detailOwnerID))

        socket.emissions.removeAll()
        activeEvent["phase"] = "finished"
        socket.deliver(name: "active_game", data: activeEvent)

        XCTAssertNil(service.activeGames[50])
        XCTAssertTrue(socket.emissions.isEmpty)
        socket.deliver(name: "game/50/phase", data: "stone removal")
        XCTAssertEqual(game.gamePhase, .stoneRemoval)

        service.releaseConnection(gameID: 50, owner: .detail(detailOwnerID))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "chat/part"])
    }

    func testPublicGameRefreshReleasesOnlyPublicListOwners() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let historyGame = Game(ogsGame: try makeEmptyGameData(id: 51, phase: "finished"))
        historyGame.ogs = service
        let detailOwnerID = UUID()
        service.connect(to: historyGame, withChat: true, owner: .detail(detailOwnerID))

        socket.emissions.removeAll()
        socket.gamelistResults = [makeShortGameData(id: 52, phase: "play")]
        service.fetchPublicGames()

        XCTAssertFalse(socket.emissions.contains { emission in
            emission.command == "game/disconnect"
                && (emission.data as? [String: Any])?["game_id"] as? Int == 51
        })
        socket.deliver(name: "game/51/phase", data: "stone removal")
        XCTAssertEqual(historyGame.gamePhase, .stoneRemoval)

        socket.emissions.removeAll()
        socket.gamelistResults = []
        service.fetchPublicGames()

        XCTAssertTrue(socket.emissions.contains { emission in
            emission.command == "game/disconnect"
                && (emission.data as? [String: Any])?["game_id"] as? Int == 52
        })
        XCTAssertFalse(socket.emissions.contains { emission in
            emission.command == "game/disconnect"
                && (emission.data as? [String: Any])?["game_id"] as? Int == 51
        })
    }

    func testDetailOwnersAreIndependentAndChatDowngradesToPublicConnection() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 53, phase: "finished"))
        game.ogs = service
        let firstDetailOwnerID = UUID()
        let secondDetailOwnerID = UUID()

        service.connect(to: game, owner: .publicGames)
        service.connect(to: game, withChat: true, owner: .detail(firstDetailOwnerID))
        service.connect(to: game, withChat: true, owner: .detail(secondDetailOwnerID))
        socket.emissions.removeAll()

        service.releaseConnection(gameID: 53, owner: .detail(firstDetailOwnerID))
        XCTAssertTrue(socket.emissions.isEmpty)

        service.releaseConnection(gameID: 53, owner: .detail(secondDetailOwnerID))
        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/disconnect", "chat/part", "game/connect"]
        )

        socket.emissions.removeAll()
        socket.dropSocket()
        socket.openSocket(authenticate: true)
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 1)
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })

        socket.emissions.removeAll()
        service.releaseConnection(gameID: 53, owner: .publicGames)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect"])
    }

    func testGameDetailCoordinatorReturnsCanonicalGameForRepeatedSameIDAcquisition() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let canonicalGame = Game(ogsGame: try makeEmptyGameData(id: 55))
        let staleGame = Game(ogsGame: try makeEmptyGameData(id: 55))
        canonicalGame.ogs = service
        staleGame.ogs = service

        service.connect(
            to: canonicalGame,
            withChat: true,
            owner: .explicit(UUID())
        )
        socket.emissions.removeAll()

        var coordinator = GameDetailConnectionCoordinator(ownerID: UUID())
        let firstAcquisition = coordinator.connect(to: staleGame, using: service)
        let secondAcquisition = coordinator.connect(to: staleGame, using: service)

        XCTAssertTrue(firstAcquisition === canonicalGame)
        XCTAssertTrue(secondAcquisition === canonicalGame)
        XCTAssertEqual(coordinator.connectedGameID, 55)
        XCTAssertTrue(socket.emissions.isEmpty)
    }

    func testGameDetailCoordinatorSwitchReleasesOldGameBeforeConnectingNewGame() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let firstGame = Game(ogsGame: try makeEmptyGameData(id: 56))
        let secondGame = Game(ogsGame: try makeEmptyGameData(id: 57))
        firstGame.ogs = service
        secondGame.ogs = service
        var coordinator = GameDetailConnectionCoordinator(ownerID: UUID())

        coordinator.connect(to: firstGame, using: service)
        socket.emissions.removeAll()
        coordinator.connect(to: secondGame, using: service)

        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/disconnect", "chat/part", "game/connect", "chat/join"]
        )
        guard socket.emissions.count == 4 else {
            return
        }
        XCTAssertEqual(
            (socket.emissions[0].data as? [String: Any])?["game_id"] as? Int,
            56
        )
        XCTAssertEqual(
            (socket.emissions[1].data as? [String: Any])?["channel"] as? String,
            "game-56"
        )
        XCTAssertEqual(
            (socket.emissions[2].data as? [String: Any])?["game_id"] as? Int,
            57
        )
        XCTAssertEqual(
            (socket.emissions[2].data as? [String: Any])?["chat"] as? Bool,
            true
        )
        XCTAssertEqual(
            (socket.emissions[3].data as? [String: Any])?["channel"] as? String,
            "game-57"
        )
        XCTAssertEqual(coordinator.connectedGameID, 57)
    }

    func testGameDetailCoordinatorReleaseIsIdempotentAndPreventsReconnect() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 58))
        game.ogs = service
        var coordinator = GameDetailConnectionCoordinator(ownerID: UUID())

        coordinator.connect(to: game, using: service)
        socket.emissions.removeAll()

        coordinator.release(using: service)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "chat/part"])
        XCTAssertNil(coordinator.connectedGameID)

        coordinator.release(using: service)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "chat/part"])

        socket.emissions.removeAll()
        socket.dropSocket()
        socket.openSocket(authenticate: true)

        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testPublicRefreshReusesDesiredCanonicalModelWhileSocketIsDown() throws {
        let socket = FakeWebsocket()
        socket.dropSocket()
        let service = makeService(socket: socket)
        let canonicalGame = Game(ogsGame: try makeEmptyGameData(id: 54))
        canonicalGame.ogs = service
        service.connect(to: canonicalGame, owner: .explicit(UUID()))

        socket.gamelistResults = [makeShortGameData(id: 54, phase: "play")]
        service.fetchPublicGames()

        XCTAssertEqual(service.sortedPublicGames.count, 1)
        XCTAssertTrue(service.sortedPublicGames[0] === canonicalGame)

        socket.openSocket(authenticate: true)
        socket.deliver(name: "game/54/phase", data: "stone removal")
        XCTAssertEqual(canonicalGame.gamePhase, .stoneRemoval)
    }

    func testAuthenticationChangeInvalidatesFinishedGameAndChatIntent() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        service.ogsUIConfig = try makeUIConfig(jwt: "old-test-jwt", userID: 1)
        socket.openSocket(authenticate: true)

        let game = Game(ogsGame: try makeEmptyGameData(id: 47, phase: "finished"))
        game.ogs = service
        service.connect(to: game, withChat: true, owner: .explicit(UUID()))
        socket.emissions.removeAll()
        let reconnectCountBeforeChange = socket.closeThenReconnectCount

        service.ogsUIConfig = try makeUIConfig(jwt: "new-test-jwt", userID: 2)

        XCTAssertEqual(socket.emissions.filter { $0.command == "game/disconnect" }.count, 1)
        XCTAssertEqual(socket.emissions.filter { $0.command == "chat/part" }.count, 1)
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCountBeforeChange + 1)

        socket.emissions.removeAll()
        socket.openSocket(authenticate: true)
        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testMalformedAndUnknownGameEventsAreIgnored() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 77))
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))

        socket.deliver(name: "game/not-an-id/move", data: ["move": [0, 0]])
        socket.deliver(name: "game/77/move", data: ["move": []])
        socket.deliver(name: "game/77/move", data: ["move": ["bad", "data"]])
        socket.deliver(name: "game/77/not-a-real-event", data: ["anything": true])
        socket.deliver(name: "net/pong", data: [String: Double]())

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.currentPosition.lastMove)
    }

    func testMoveAcknowledgementErrorBecomesPublisherFailure() throws {
        final class RejectingWebsocket: FakeWebsocket {
            override func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
                emissions.append(.init(command: command, data: data))
                resultCallback?(nil, ["move": "illegal move"])
            }
        }

        let socket = RejectingWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 88))
        game.ogs = service
        let completed = expectation(description: "move rejected")
        var receivedError: Error?
        let cancellable = service.submitMove(move: .placeStone(0, 0), forGame: game).sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            },
            receiveValue: { XCTFail("Rejected move must not succeed") }
        )

        wait(for: [completed], timeout: 1)
        withExtendedLifetime(cancellable) {}
        XCTAssertEqual(receivedError?.localizedDescription, "move: illegal move")
    }

    func testStoneAcceptanceIncludesTheRequiredStrictSekiFlag() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 99))

        service.acceptRemovedStone(game: game)

        let emission = try XCTUnwrap(socket.emissions.last)
        XCTAssertEqual(emission.command, "game/removed_stones/accept")
        let data = try XCTUnwrap(emission.data as? [String: Any])
        XCTAssertEqual(data["game_id"] as? Int, 99)
        XCTAssertEqual(data["stones"] as? String, "")
        XCTAssertEqual(data["strict_seki_mode"] as? Bool, false)
    }

    func testFinishedActiveGameEventRemovesGameWithoutCreatingFinishedGames() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        var event = makeShortGameData(id: 101, phase: "finished")

        socket.deliver(name: "active_game", data: event)

        XCTAssertNil(service.activeGames[101])
        XCTAssertTrue(socket.emissions.isEmpty)

        event["phase"] = "play"
        socket.deliver(name: "active_game", data: event)
        XCTAssertNotNil(service.activeGames[101])
        XCTAssertEqual(socket.emissions.map(\.command), ["game/connect"])

        event["phase"] = "finished"
        socket.deliver(name: "active_game", data: event)
        XCTAssertNil(service.activeGames[101])
        XCTAssertEqual(socket.emissions.map(\.command), ["game/connect", "game/disconnect"])
    }

    func testFinishedActiveGameEventImmediatelyRemovesGameFromDerivedPresentationCollections() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        let fixture = try makeEmptyGameData(id: 100)
        service.user = fixture.players.black

        let onUserTurnID = 101
        let notOnUserTurnID = 102
        let liveID = 103
        service.processOverview(overview: [
            "active_games": [
                try makeOverviewGameData(
                    id: onUserTurnID,
                    speed: "correspondence",
                    currentPlayerID: fixture.players.black.id
                ),
                try makeOverviewGameData(
                    id: notOnUserTurnID,
                    speed: "correspondence",
                    currentPlayerID: fixture.players.white.id
                ),
                try makeOverviewGameData(
                    id: liveID,
                    speed: "live",
                    currentPlayerID: fixture.players.black.id
                ),
            ],
        ])

        XCTAssertEqual(
            service.sortedActiveCorrespondenceGamesOnUserTurn.compactMap(\.ogsID),
            [onUserTurnID]
        )
        XCTAssertEqual(
            service.sortedActiveCorrespondenceGamesNotOnUserTurn.compactMap(\.ogsID),
            [notOnUserTurnID]
        )
        XCTAssertEqual(
            service.sortedActiveCorrespondenceGames.compactMap(\.ogsID),
            [onUserTurnID, notOnUserTurnID]
        )
        XCTAssertEqual(service.liveGames.compactMap(\.ogsID), [liveID])

        for gameID in [onUserTurnID, notOnUserTurnID, liveID] {
            socket.deliver(
                name: "active_game",
                data: makeShortGameData(id: gameID, phase: "finished")
            )

            XCTAssertNil(service.activeGames[gameID])
            XCTAssertFalse(
                service.sortedActiveCorrespondenceGamesOnUserTurn.contains {
                    $0.ogsID == gameID
                }
            )
            XCTAssertFalse(
                service.sortedActiveCorrespondenceGamesNotOnUserTurn.contains {
                    $0.ogsID == gameID
                }
            )
            XCTAssertFalse(
                service.sortedActiveCorrespondenceGames.contains {
                    $0.ogsID == gameID
                }
            )
            XCTAssertFalse(service.liveGames.contains { $0.ogsID == gameID })
        }
    }

    private func makeService(
        socket: OGSWebsocketProtocol,
        installsObservers: Bool = true,
        undoResynchronizationTimeout: TimeInterval = 15
    ) -> OGSService {
        preferenceSuite = "com.honganhkhoa.Surround.EventTests.\(UUID().uuidString)"
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        return OGSService(
            environment: environment,
            httpClient: AlamofireOGSHTTPClient.isolated(),
            preferences: UserDefaults(suiteName: preferenceSuite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: installsObservers,
            undoResynchronizationTimeout: undoResynchronizationTimeout
        )
    }

    private func makeShortGameData(id: Int, phase: String) -> [String: Any] {
        [
            "id": id,
            "phase": phase,
            "width": 5,
            "height": 5,
            "black": ["id": 1, "username": "black"],
            "white": ["id": 2, "username": "white"],
        ]
    }

    private func makeOverviewGameData(
        id: Int,
        speed: String,
        currentPlayerID: Int
    ) throws -> [String: Any] {
        let bundle = Bundle(for: OGSServiceEventTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "game-25076729", withExtension: "json")
        )
        var gameData = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        gameData["game_id"] = id
        gameData["game_name"] = "event-test-\(id)"
        gameData["width"] = 5
        gameData["height"] = 5
        gameData["moves"] = []
        gameData["phase"] = "play"
        gameData["outcome"] = NSNull()
        gameData["winner"] = NSNull()

        var timeControl = try XCTUnwrap(gameData["time_control"] as? [String: Any])
        timeControl["speed"] = speed
        gameData["time_control"] = timeControl

        var clock = try XCTUnwrap(gameData["clock"] as? [String: Any])
        clock["game_id"] = id
        clock["current_player"] = currentPlayerID
        gameData["clock"] = clock

        let players = try XCTUnwrap(gameData["players"] as? [String: Any])
        return [
            "id": id,
            "phase": "play",
            "width": 5,
            "height": 5,
            "black": players["black"] as Any,
            "white": players["white"] as Any,
            "json": gameData,
        ]
    }

    private func makeEmptyGameData(
        id: Int,
        phase: String = "play",
        undoRequested: Any? = nil
    ) throws -> OGSGame {
        let object = try makeEmptyGameDataPayload(
            id: id,
            phase: phase,
            undoRequested: undoRequested
        )
        // Socket `gamedata` and overview payloads both use this decoder in
        // production, including its nested snake-case key conversion.
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: object)
    }

    private func makeEmptyGameDataPayload(
        id: Int,
        phase: String = "play",
        undoRequested: Any? = nil
    ) throws -> [String: Any] {
        let bundle = Bundle(for: OGSServiceEventTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-25076729", withExtension: "json"))
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["game_id"] = id
        object["game_name"] = "event-test-\(id)"
        object["width"] = 5
        object["height"] = 5
        object["moves"] = []
        object["phase"] = phase
        object["outcome"] = NSNull()
        object["winner"] = NSNull()
        if let undoRequested {
            object["undo_requested"] = undoRequested
        } else {
            object.removeValue(forKey: "undo_requested")
        }
        return object
    }

    private func makeUIConfig(jwt: String, userID: Int) throws -> OGSUIConfig {
        let data = try JSONSerialization.data(withJSONObject: [
            "csrf_token": "test-csrf",
            "user_jwt": jwt,
            "user": [
                "username": "player-\(userID)",
                "id": userID,
                "anonymous": false,
            ],
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSUIConfig.self, from: data)
    }
}
