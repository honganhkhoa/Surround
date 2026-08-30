//
//  OGSServiceEventTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import DictionaryCoding
import XCTest

final class OGSServiceEventTests: XCTestCase {
    private final class RejectingURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.notConnectedToInternet)
            )
        }

        override func stopLoading() {}
    }

    private class FakeWebsocket: OGSWebsocketProtocol {
        struct Emission {
            let command: String
            let data: Any
            let hasResultCallback: Bool
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
            emissions.append(.init(
                command: command,
                data: data,
                hasResultCallback: resultCallback != nil
            ))
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

    func testSendChatEmitsOnlyPrimaryClientChannelsWithCompletePayload() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 42))
        let channels: [OGSChatSendChannel] = [
            .main,
            .malkovich,
            .personal,
        ]

        for channel in channels {
            _ = service.sendChat(
                in: game,
                channel: channel,
                body: "message on \(channel.rawValue)"
            )
        }

        let chatEmissions = socket.emissions.filter {
            $0.command == "game/chat"
        }
        XCTAssertEqual(chatEmissions.count, channels.count)

        for (emission, channel) in zip(chatEmissions, channels) {
            let payload = try XCTUnwrap(emission.data as? [String: Any])
            XCTAssertEqual(payload["type"] as? String, channel.rawValue)
            XCTAssertEqual(payload["game_id"] as? Int, 42)
            XCTAssertEqual(payload["move_number"] as? Int, 0)
            XCTAssertEqual(
                payload["body"] as? String,
                "message on \(channel.rawValue)"
            )
            XCTAssertFalse(emission.hasResultCallback)
        }

        XCTAssertEqual(
            Set(chatEmissions.compactMap {
                ($0.data as? [String: Any])?["type"] as? String
            }),
            Set(["main", "malkovich", "personal"])
        )
    }

    func testShareVariationEmitsTypedPayloadWithOfficialMoveAndTrimmedName() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 242))
        game.ogs = service
        service.user = game.blackPlayer
        service.isLoggedIn = true
        var variation = try makeShareableVariation(in: game)
        variation.markups = [
            BoardPoint(row: 2, column: 4): BoardMarkup(label: "A"),
            BoardPoint(row: 0, column: 0): BoardMarkup(
                shapes: [.triangle]
            ),
        ]
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )
        socket.emissions.removeAll()

        try service.shareVariation(
            variation,
            in: game,
            channel: .personal,
            name: "  Study line  \n"
        )

        XCTAssertEqual(socket.emissions.count, 1)
        let emission = try XCTUnwrap(socket.emissions.first)
        XCTAssertEqual(emission.command, "game/chat")
        XCTAssertFalse(emission.hasResultCallback)
        let payload = try XCTUnwrap(emission.data as? [String: Any])
        XCTAssertEqual(payload["game_id"] as? Int, 242)
        XCTAssertEqual(payload["move_number"] as? Int, 2)
        XCTAssertEqual(payload["type"] as? String, "personal")
        let body = try XCTUnwrap(payload["body"] as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "analysis")
        XCTAssertEqual(body["from"] as? Int, 1)
        XCTAssertEqual(body["moves"] as? String, "bb..")
        XCTAssertEqual(body["name"] as? String, "Study line")
        let marks = try XCTUnwrap(body["marks"] as? [String: String])
        XCTAssertEqual(marks["A"], "ec")
        XCTAssertEqual(marks["triangle"], "aa")
    }

    func testShareMarksOnlyVariationFromMainBranchPosition() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 246))
        game.ogs = service
        service.user = game.blackPlayer
        service.isLoggedIn = true
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )
        socket.emissions.removeAll()
        let position = game.currentPosition
        let variation = Variation(
            position: position,
            basePosition: position,
            moves: [],
            markups: [
                BoardPoint(row: 0, column: 0): BoardMarkup(label: "A")
            ]
        )

        try service.shareVariation(
            variation,
            in: game,
            channel: .main,
            name: "Marks only"
        )

        let emission = try XCTUnwrap(socket.emissions.first)
        let payload = try XCTUnwrap(emission.data as? [String: Any])
        let body = try XCTUnwrap(payload["body"] as? [String: Any])
        XCTAssertEqual(body["from"] as? Int, position.lastMoveNumber)
        XCTAssertEqual(body["moves"] as? String, "")
        XCTAssertEqual((body["marks"] as? [String: String])?["A"], "aa")
    }

    func testReceivedMarksOnlyVariationDoesNotMutateLivePosition() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 247))
        game.ogs = service
        let livePosition = game.currentPosition
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )

        socket.deliver(
            name: "game/247/chat",
            data: analysisChatEvent(
                name: "Marks only",
                from: livePosition.lastMoveNumber,
                moves: "",
                marks: ["A": "ec", "triangle": "aa"]
            )
        )

        let receivedVariation = try XCTUnwrap(game.chatLog.last?.variation)
        XCTAssertTrue(game.currentPosition === livePosition)
        XCTAssertTrue(receivedVariation.basePosition === livePosition)
        XCTAssertTrue(receivedVariation.position === livePosition)
        XCTAssertTrue(receivedVariation.moves.isEmpty)
        XCTAssertEqual(
            receivedVariation.markups[BoardPoint(row: 2, column: 4)]?.label,
            "A"
        )
        XCTAssertEqual(
            receivedVariation.markups[
                BoardPoint(row: 0, column: 0)
            ]?.shapes,
            [.triangle]
        )
    }

    func testReceivedTranslatedBotChatWithNullMoveNumberIsRetained() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 248))
        game.ogs = service
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )

        socket.deliver(
            name: "game/248/chat",
            data: [
                "channel": "main",
                "line": [
                    "body": [
                        "type": "translated",
                        "en": "Undo requested",
                    ],
                    "chat_id": "translated-bot-line",
                    "date": 1_700_000_000.0,
                    "move_number": NSNull(),
                    "player_id": 0,
                    "username": "DangoApp",
                ],
            ]
        )

        let receivedLine = try XCTUnwrap(game.chatLog.last)
        XCTAssertEqual(receivedLine.id, "translated-bot-line")
        XCTAssertEqual(receivedLine.body, "Undo requested")
        XCTAssertNil(receivedLine.moveNumber)
        XCTAssertEqual(receivedLine.user.id, 0)
        XCTAssertEqual(receivedLine.user.username, "DangoApp")
    }

    func testReceivedLegacyAnalysisUsesTypedDecoderInServicePath() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 249))
        game.ogs = service
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )

        socket.deliver(
            name: "game/249/chat",
            data: [
                "channel": "main",
                "line": [
                    "body": [
                        "type": "analysis",
                        "branch_move": 1,
                        "moves": "aa",
                        "name": "Legacy branch",
                    ],
                    "chat_id": "legacy-analysis-line",
                    "date": 1_700_000_000.0,
                    "move_number": NSNull(),
                    "player_id": 1,
                    "username": "black",
                ],
            ]
        )

        let receivedLine = try XCTUnwrap(game.chatLog.last)
        XCTAssertTrue(receivedLine.isAnalysis)
        XCTAssertEqual(receivedLine.variationData?.fromMoveNumber, 0)
        XCTAssertEqual(receivedLine.variationData?.moves, "aa")
        XCTAssertNotNil(receivedLine.variation)

        socket.deliver(
            name: "game/249/chat",
            data: [
                "channel": "main",
                "line": [
                    "body": [
                        "type": "analysis",
                        "branch_move": Int.min,
                        "from": 0,
                        "moves": "bb",
                        "name": "Checked legacy branch",
                    ],
                    "chat_id": "checked-legacy-analysis-line",
                    "date": 1_700_000_001.0,
                    "move_number": NSNull(),
                    "player_id": 1,
                    "username": "black",
                ],
            ]
        )

        let checkedLine = try XCTUnwrap(game.chatLog.last)
        XCTAssertEqual(checkedLine.id, "checked-legacy-analysis-line")
        XCTAssertEqual(checkedLine.variationData?.fromMoveNumber, 0)
        XCTAssertEqual(checkedLine.variationData?.moves, "bb")
        XCTAssertNotNil(checkedLine.variation)
    }

    func testShareVariationAutoNamesFromReceivedAndReservedNumbersAndResolvesSpectatorChannel() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 243))
        game.ogs = service
        service.user = OGSUser(
            username: "spectator",
            id: 99,
            ranking: 25,
            uiClass: "",
            professional: false,
            ratings: nil
        )
        service.isLoggedIn = true
        let variation = try makeShareableVariation(in: game)
        service.connect(
            to: game,
            withChat: true,
            owner: .explicit(UUID())
        )
        socket.deliver(
            name: "game/243/chat",
            data: analysisChatEvent(
                name: "Variation 4",
                from: 1,
                moves: "bb..",
                marks: ["A": "ec", "circle": "aa"]
            )
        )
        let receivedVariation = try XCTUnwrap(game.chatLog.last?.variation)
        XCTAssertEqual(
            receivedVariation.markups[BoardPoint(row: 2, column: 4)]?.label,
            "A"
        )
        XCTAssertEqual(
            receivedVariation.markups[BoardPoint(row: 0, column: 0)]?.shapes,
            [.circle]
        )
        socket.emissions.removeAll()

        try service.shareVariation(
            variation,
            in: game,
            channel: .personal,
            name: " \n"
        )
        try service.shareVariation(
            variation,
            in: game,
            channel: .malkovich,
            name: ""
        )
        try service.shareVariation(
            variation,
            in: game,
            channel: .personal,
            name: " v12 appendix "
        )
        try service.shareVariation(
            variation,
            in: game,
            channel: .personal,
            name: ""
        )

        let chatEmissions = socket.emissions.filter { $0.command == "game/chat" }
        XCTAssertEqual(chatEmissions.count, 4)
        XCTAssertEqual(
            chatEmissions.compactMap {
                (($0.data as? [String: Any])?["body"] as? [String: Any])?["name"]
                    as? String
            },
            ["5", "6", "v12 appendix", "13"]
        )
        XCTAssertEqual(
            Set(chatEmissions.compactMap {
                ($0.data as? [String: Any])?["type"] as? String
            }),
            ["main"]
        )
        XCTAssertTrue(chatEmissions.allSatisfy {
            (($0.data as? [String: Any])?["body"] as? [String: Any])?["marks"] == nil
        })
    }

    func testShareVariationRejectsUnavailableSocketChatAndStaleVariationWithoutEmission() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 244))
        game.ogs = service
        service.user = game.blackPlayer
        let variation = try makeShareableVariation(in: game)
        service.connect(
            to: game,
            withChat: false,
            owner: .explicit(UUID())
        )
        socket.emissions.removeAll()

        XCTAssertThrowsError(
            try service.shareVariation(
                variation,
                in: game,
                channel: .main,
                name: "Not logged in"
            )
        )
        service.isLoggedIn = true
        XCTAssertThrowsError(
            try service.shareVariation(
                variation,
                in: game,
                channel: .main,
                name: "No chat"
            )
        )

        let chatOwner = OGSService.GameConnectionOwner.explicit(UUID())
        service.connect(to: game, withChat: true, owner: chatOwner)
        socket.emissions.removeAll()
        socket.authenticated = false
        XCTAssertThrowsError(
            try service.shareVariation(
                variation,
                in: game,
                channel: .main,
                name: "No auth"
            )
        )
        socket.authenticated = true

        let unregisteredPosition = try game.initialPosition.makeMove(
            move: .placeStone(4, 4)
        )
        let staleVariation = Variation(
            position: unregisteredPosition,
            basePosition: game.initialPosition,
            moves: [.placeStone(4, 4)]
        )
        XCTAssertThrowsError(
            try service.shareVariation(
                staleVariation,
                in: game,
                channel: .main,
                name: "Stale"
            )
        )
        XCTAssertFalse(socket.emissions.contains { $0.command == "game/chat" })
    }

    func testShareVariationRejectsDifferentGameInstanceForConnectedGameID() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let connectedGame = Game(ogsGame: try makeEmptyGameData(id: 245))
        let staleGame = Game(ogsGame: try makeEmptyGameData(id: 245))
        connectedGame.ogs = service
        staleGame.ogs = service
        service.user = connectedGame.blackPlayer
        service.isLoggedIn = true
        service.connect(
            to: connectedGame,
            withChat: true,
            owner: .explicit(UUID())
        )
        let staleVariation = try makeShareableVariation(in: staleGame)
        socket.emissions.removeAll()

        XCTAssertThrowsError(
            try service.shareVariation(
                staleVariation,
                in: staleGame,
                channel: .main,
                name: "Stale model"
            )
        )
        XCTAssertFalse(socket.emissions.contains { $0.command == "game/chat" })
    }

    func testGameEventsUpdateConnectedGameAndReconnectSubscription() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let gameData = try makeEmptyGameData(id: 42)
        let game = Game(ogsGame: gameData)
        game.ogs = service

        service.connect(to: game, owner: .explicit(UUID()))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/connect"])

        socket.deliver(
            name: "game/42/move",
            data: ["move_number": 1, "move": [0, 0, 125, false]]
        )
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

    func testConditionalMovesEventRoutesRuntimePayloadAndSurvivesReconnectAndGameData() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 120))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(4, 4))
        let playerID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/120/conditional_moves",
            data: [
                "game_id": 120,
                "player_id": playerID,
                "move_number": 1,
                "moves": twoBranchConditionalMovesRoot(),
            ]
        )

        XCTAssertEqual(game.conditionalMovePlan?.gameID, 120)
        XCTAssertEqual(game.conditionalMovePlan?.ownerID, playerID)
        XCTAssertEqual(game.conditionalMovePlan?.rootMoveNumber, 1)
        XCTAssertEqual(
            game.conditionalMoveBranches.map(\.id),
            ["1:..cc", "1:aabb"]
        )

        socket.dropSocket()
        socket.openSocket(authenticate: true)

        XCTAssertNotNil(game.conditionalMovePlan)
        XCTAssertEqual(
            game.conditionalMoveBranches.map(\.id),
            ["1:..cc", "1:aabb"]
        )

        var gameData = try makeEmptyGameDataPayload(id: 120)
        gameData["moves"] = [[4, 4, 0]]
        socket.deliver(name: "game/120/gamedata", data: gameData)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)
        XCTAssertNotNil(game.conditionalMovePlan)
        XCTAssertEqual(
            game.conditionalMoveBranches.map(\.id),
            ["1:..cc", "1:aabb"]
        )
    }

    func testConditionalMoveSubmissionSendsFullTreeWithoutCallbackAndWaitsForPush() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 125))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(4, 4))
        let ownerID = try XCTUnwrap(game.blackId)
        let plan = try ConditionalMovePlan(
            gameID: 125,
            ownerID: ownerID,
            rootMoveNumber: 1,
            paths: [[.placeStone(0, 0), .placeStone(1, 1)]]
        )
        let completed = expectation(description: "conditional moves acknowledged")
        var completionResult: Result<Void, Error>?
        let cancellable = service.submitConditionalMovePlan(plan, for: game).sink(
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    completionResult = .success(())
                case .failure(let error):
                    completionResult = .failure(error)
                }
                completed.fulfill()
            },
            receiveValue: {}
        )

        let emitted = expectation(description: "conditional command emitted")
        DispatchQueue.main.async { emitted.fulfill() }
        wait(for: [emitted], timeout: 1)

        let emission = try XCTUnwrap(
            socket.emissions.last { $0.command == "game/conditional_moves/set" }
        )
        XCTAssertFalse(emission.hasResultCallback)
        let payload = try XCTUnwrap(emission.data as? [String: Any])
        XCTAssertEqual(payload["game_id"] as? Int, 125)
        XCTAssertEqual(payload["move_number"] as? Int, 1)
        let root = try XCTUnwrap(payload["conditional_moves"] as? [Any])
        XCTAssertEqual(root.count, 2)
        XCTAssertTrue(root[0] is NSNull)
        let children = try XCTUnwrap(root[1] as? [String: Any])
        let firstReply = try XCTUnwrap(children["aa"] as? [Any])
        XCTAssertEqual(firstReply[0] as? String, "bb")
        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(service.isConditionalMoveSubmissionPending(gameID: 125))

        socket.deliver(
            name: "game/125/conditional_moves",
            data: [
                "game_id": 125,
                "player_id": ownerID,
                "move_number": 1,
                "moves": root,
            ]
        )

        wait(for: [completed], timeout: 1)
        withExtendedLifetime(cancellable) {}
        if case .failure(let error) = completionResult {
            XCTFail("Unexpected conditional update failure: \(error)")
        }
        XCTAssertEqual(game.conditionalMovePlan, plan)
        XCTAssertFalse(service.isConditionalMoveSubmissionPending(gameID: 125))
    }

    func testOfflineConditionalMoveSubmissionEchoesAuthoritativeUpdate() async throws {
        let service = makeService(
            socket: OGSOfflineNoOpWebsocket(),
            conditionalMoveSubmissionTimeout: 1
        )
        let game = Game(ogsGame: try makeEmptyGameData(id: 126))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(4, 4))
        let ownerID = try XCTUnwrap(game.blackId)
        let initialPlan = try ConditionalMovePlan(
            gameID: 126,
            ownerID: ownerID,
            rootMoveNumber: 1,
            paths: [
                [.placeStone(0, 0), .placeStone(1, 1)],
                [.placeStone(2, 2), .placeStone(3, 3)],
            ]
        )
        XCTAssertTrue(
            game.setConditionalMovePlan(initialPlan, expectedOwnerID: ownerID)
        )
        let removedBranch = try XCTUnwrap(game.conditionalMoveBranches.first)
        let removedID = removedBranch.variationID
        let replacement = try XCTUnwrap(
            initialPlan.removingVariations([removedID], ownerID: ownerID)
        )
        let completed = expectation(description: "offline conditional echo")
        var completionError: Error?
        let cancellable = service.submitConditionalMovePlan(
            replacement,
            for: game
        ).sink { completion in
            if case .failure(let error) = completion {
                completionError = error
            }
            completed.fulfill()
        } receiveValue: {}

        // The offline echo and its Combine completion are dispatched through
        // the main run loop. Give a contended CI runner enough time to service
        // those callbacks while keeping the production submission timeout at
        // one second so this still exercises the same behavior.
        await fulfillment(of: [completed], timeout: 10)
        withExtendedLifetime(cancellable) {}
        XCTAssertNil(completionError)
        XCTAssertEqual(game.conditionalMovePlan, replacement)
        XCTAssertFalse(
            game.moveTree.isConditionalVariationPosition(
                removedBranch.position
            )
        )
    }

    func testConditionalMovesEventBeforeGameDataRetainsPlanUntilRootHydrates() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let hydrationData = try makeEmptyGameData(id: 124)
        let game = Game(
            width: 5,
            height: 5,
            blackName: hydrationData.players.black.username,
            whiteName: hydrationData.players.white.username,
            gameId: .OGS(124)
        )
        game.blackPlayer = hydrationData.players.black
        game.whitePlayer = hydrationData.players.white
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        let playerID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/124/conditional_moves",
            data: [
                "game_id": 124,
                "player_id": playerID,
                "move_number": 1,
                "moves": oneBranchConditionalMovesRoot(),
            ]
        )

        XCTAssertNil(game.gameData)
        XCTAssertEqual(game.conditionalMovePlan?.rootMoveNumber, 1)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)

        var gameData = try makeEmptyGameDataPayload(id: 124)
        gameData["moves"] = [[4, 4, 0]]
        socket.deliver(name: "game/124/gamedata", data: gameData)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)
        XCTAssertEqual(game.conditionalMovePlan?.rootMoveNumber, 1)
        XCTAssertEqual(game.conditionalMoveBranches.map(\.id), ["1:aabb"])
    }

    func testConditionalMovesEventAcceptsProtocolAliasAndExplicitClearForms() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 121))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        let playerID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/121/conditional_moves",
            data: [
                "game_id": 121,
                "player_id": playerID,
                "move_number": 0,
                "conditional_moves": oneBranchConditionalMovesRoot(),
            ]
        )
        XCTAssertEqual(game.conditionalMoveBranches.map(\.id), ["0:aabb"])

        socket.deliver(
            name: "game/121/conditional_moves",
            data: [
                "game_id": 121,
                "player_id": playerID,
                "move_number": 0,
                "moves": NSNull(),
            ]
        )
        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)

        socket.deliver(
            name: "game/121/conditional_moves",
            data: [
                "game_id": 121,
                "player_id": playerID,
                "move_number": 0,
                "moves": oneBranchConditionalMovesRoot(),
            ]
        )
        XCTAssertNotNil(game.conditionalMovePlan)

        socket.deliver(
            name: "game/121/conditional_moves",
            data: [
                "game_id": 121,
                "player_id": playerID,
                "move_number": 0,
                "conditional_moves": [NSNull(), [String: Any]()],
            ]
        )
        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)

        socket.deliver(
            name: "game/121/conditional_moves",
            data: [
                "game_id": 121,
                "player_id": playerID,
                "move_number": 0,
                "moves": oneBranchConditionalMovesRoot(),
            ]
        )
        XCTAssertNotNil(game.conditionalMovePlan)
        socket.deliver(name: "game/121/phase", data: "finished")
        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)
    }

    func testConditionalMovesEventRejectsWrongGameAndOwnerWithoutReplacingPlan() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 122))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        let playerID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": oneBranchConditionalMovesRoot(),
            ]
        )
        let installedPlan = try XCTUnwrap(game.conditionalMovePlan)

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 999,
                "player_id": playerID,
                "move_number": 0,
                "moves": NSNull(),
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)

        // Both wire moves are valid, but the response repeats the occupied
        // opponent point. The all-illegal update must be transactional.
        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": [
                    NSNull(),
                    ["cc": ["cc", [String: Any]()] as [Any]],
                ] as [Any],
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)
        XCTAssertEqual(game.conditionalMoveBranches.map(\.id), ["0:aabb"])

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": ["aa", [String: Any]()],
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": try XCTUnwrap(game.whiteId),
                "move_number": 0,
                "moves": NSNull(),
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)

        socket.deliver(
            name: "game/999/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": NSNull(),
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": [
                    NSNull(),
                    ["zz": ["AA", [String: Any]()] as [Any]],
                ] as [Any],
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)

        socket.deliver(
            name: "game/122/conditional_moves",
            data: [
                "game_id": 122,
                "player_id": playerID,
                "move_number": 0,
                "moves": [
                    NSNull(),
                    ["aa": ["bb"] as [Any]],
                ] as [Any],
            ]
        )
        XCTAssertEqual(game.conditionalMovePlan, installedPlan)
    }

    func testAcceptedUndoClearsConditionalMoves() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 123))
        game.ogs = service
        service.user = game.blackPlayer
        service.connect(to: game, owner: .explicit(UUID()))
        try game.makeMove(move: .placeStone(4, 4))
        let playerID = try XCTUnwrap(game.blackId)

        socket.deliver(
            name: "game/123/conditional_moves",
            data: [
                "game_id": 123,
                "player_id": playerID,
                "move_number": 1,
                "moves": oneBranchConditionalMovesRoot(),
            ]
        )
        XCTAssertNotNil(game.conditionalMovePlan)

        socket.deliver(
            name: "game/123/undo_requested",
            data: ["move_number": 1, "undo_move_count": 1]
        )
        socket.deliver(
            name: "game/123/undo_accepted",
            data: ["move_number": 1, "undo_move_count": 1]
        )

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)
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
            gameResynchronizationTimeout: 0
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
        let service = makeService(
            socket: socket,
            cachedUsers: try makePublicGameUsers()
        )
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

    func testRapidPublicGameHydratesItsAuthoritativeBoard() throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            cachedUsers: try makePublicGameUsers()
        )
        socket.gamelistResults = [makeShortGameData(id: 260, phase: "play")]

        service.fetchPublicGames()

        let game = try XCTUnwrap(service.publicGames[260])
        XCTAssertNil(game.gameData)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)

        var gameData = try makeEmptyGameDataPayload(id: 260)
        var timeControl = try XCTUnwrap(gameData["time_control"] as? [String: Any])
        timeControl["speed"] = "rapid"
        gameData["time_control"] = timeControl
        gameData["moves"] = [
            [0, 0, 0],
            [1, 0, 0],
            [0, 1, 0],
        ]

        socket.deliver(name: "game/260/gamedata", data: gameData)

        XCTAssertEqual(game.gameData?.timeControl.speed, .rapid)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 3)
        XCTAssertEqual(game.currentPosition[0, 0], .hasStone(.black))
        XCTAssertEqual(game.currentPosition[0, 1], .hasStone(.white))
        XCTAssertEqual(game.currentPosition[1, 0], .hasStone(.black))
    }

    func testMoveEventsRequireHydrationAndSequentialMoveNumbers() throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            cachedUsers: try makePublicGameUsers()
        )
        socket.gamelistResults = [makeShortGameData(id: 261, phase: "play")]
        service.fetchPublicGames()
        let game = try XCTUnwrap(service.publicGames[261])
        socket.emissions.removeAll()

        socket.deliver(
            name: "game/261/move",
            data: ["move_number": 1, "move": [0, 0, 0]]
        )

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertTrue(socket.emissions.isEmpty)

        socket.deliver(
            name: "game/261/move",
            data: ["move_number": 1, "move": [0, 0, 0]]
        )
        XCTAssertTrue(socket.emissions.isEmpty)

        var replacement = try makeEmptyGameDataPayload(id: 261)
        replacement["moves"] = [[0, 0, 0]]
        socket.deliver(name: "game/261/gamedata", data: replacement)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)

        socket.deliver(
            name: "game/261/move",
            data: ["move_number": 2, "move": [1, 0, 0]]
        )
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertEqual(game.currentPosition[0, 1], .hasStone(.white))

        socket.emissions.removeAll()
        socket.deliver(
            name: "game/261/move",
            data: ["move_number": 2, "move": [2, 0, 0]]
        )
        socket.deliver(
            name: "game/261/move",
            data: ["move_number": 4, "move": [3, 0, 0]]
        )
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "game/connect"])

        replacement["moves"] = [[0, 0, 0], [1, 0, 0]]
        socket.deliver(name: "game/261/gamedata", data: replacement)
        socket.emissions.removeAll()
        socket.deliver(name: "game/261/move", data: ["move": [2, 0, 0]])
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "game/connect"])

        socket.deliver(name: "game/261/gamedata", data: replacement)
    }

    func testUndecodableInitialGameDataDoesNotStartReconnectRecovery() throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            cachedUsers: try makePublicGameUsers(),
            gameResynchronizationTimeout: 0
        )
        socket.gamelistResults = [makeShortGameData(id: 262, phase: "play")]
        service.fetchPublicGames()
        let game = try XCTUnwrap(service.publicGames[262])
        socket.emissions.removeAll()
        let reconnect = expectation(description: "Undecodable initial data must not reconnect")
        reconnect.isInverted = true
        socket.onCloseThenReconnect = { reconnect.fulfill() }

        socket.deliver(name: "game/262/gamedata", data: ["game_id": 262])
        socket.deliver(
            name: "game/262/move",
            data: ["move_number": 1, "move": [0, 0, 0]]
        )
        socket.deliver(
            name: "game/262/move",
            data: ["move_number": 2, "move": [1, 0, 0]]
        )

        wait(for: [reconnect], timeout: 0.05)
        XCTAssertNil(game.gameData)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertTrue(socket.emissions.isEmpty)
        XCTAssertEqual(socket.closeThenReconnectCount, 0)
    }

    func testConcurrentResynchronizationsEscalateSharedSocketOnlyOnceUntilRecovery() throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            gameResynchronizationTimeout: 0.01
        )
        let firstGame = Game(ogsGame: try makeEmptyGameData(id: 263))
        let secondGame = Game(ogsGame: try makeEmptyGameData(id: 264))
        firstGame.ogs = service
        secondGame.ogs = service
        service.connect(to: firstGame, owner: .explicit(UUID()))
        service.connect(to: secondGame, owner: .explicit(UUID()))
        socket.emissions.removeAll()
        let firstFallback = expectation(description: "One shared reconnect fallback")
        socket.onCloseThenReconnect = { firstFallback.fulfill() }

        for gameID in [263, 264] {
            socket.deliver(
                name: "game/\(gameID)/move",
                data: ["move_number": 2, "move": [0, 0, 0]]
            )
        }

        wait(for: [firstFallback], timeout: 1)
        XCTAssertEqual(socket.closeThenReconnectCount, 1)
        XCTAssertEqual(
            socket.emissions.map(\.command),
            ["game/disconnect", "game/connect", "game/disconnect", "game/connect"]
        )

        socket.openSocket()
        socket.deliver(name: "game/263/gamedata", data: ["game_id": 263])
        socket.deliver(name: "game/264/gamedata", data: ["game_id": 264])
        socket.emissions.removeAll()
        let repeatedFallback = expectation(description: "Incompatible snapshots must not re-arm fallback")
        repeatedFallback.isInverted = true
        socket.onCloseThenReconnect = { repeatedFallback.fulfill() }

        for gameID in [263, 264] {
            socket.deliver(
                name: "game/\(gameID)/move",
                data: ["move_number": 2, "move": [1, 0, 0]]
            )
        }

        wait(for: [repeatedFallback], timeout: 0.05)
        XCTAssertEqual(socket.closeThenReconnectCount, 1)
        XCTAssertTrue(socket.emissions.isEmpty)

        socket.deliver(
            name: "game/263/gamedata",
            data: try makeEmptyGameDataPayload(id: 263)
        )
        let fallbackAfterRecovery = expectation(description: "Valid data resets recovery cap")
        socket.onCloseThenReconnect = { fallbackAfterRecovery.fulfill() }
        socket.deliver(
            name: "game/263/move",
            data: ["move_number": 2, "move": [2, 0, 0]]
        )

        wait(for: [fallbackAfterRecovery], timeout: 1)
        XCTAssertEqual(socket.closeThenReconnectCount, 2)
    }

    func testReplacementGameDataInvalidatesActiveGameOverviewCache() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(id: 265, phase: "play")
        )
        let game = try XCTUnwrap(service.activeGames[265])
        socket.deliver(
            name: "game/265/gamedata",
            data: try makeEmptyGameDataPayload(id: 265)
        )
        service.preferences[.latestOGSOverviewOutdated] = false
        socket.emissions.removeAll()

        socket.deliver(
            name: "game/265/move",
            data: ["move_number": 2, "move": [0, 0, 0]]
        )
        var replacement = try makeEmptyGameDataPayload(id: 265)
        replacement["moves"] = [[0, 0, 0], [1, 0, 0]]
        socket.deliver(name: "game/265/gamedata", data: replacement)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertEqual(game.currentPosition[0, 0], .hasStone(.black))
        XCTAssertEqual(game.currentPosition[0, 1], .hasStone(.white))
        XCTAssertEqual(socket.emissions.map(\.command), ["game/disconnect", "game/connect"])
        XCTAssertEqual(service.preferences[.latestOGSOverviewOutdated], true)
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
        let canonicalGame = Game(ogsGame: try makeEmptyGameData(id: 54))
        let service = makeService(
            socket: socket,
            cachedUsers: Array(canonicalGame.playerByOGSId.values)
        )
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

    func testAccountIdentityChangeInvalidatesFinishedGameAndChatIntent() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        service.ogsUIConfig = try makeUIConfig(jwt: "old-test-jwt", userID: 1)
        socket.openSocket(authenticate: true)

        let game = Game(ogsGame: try makeEmptyGameData(id: 47, phase: "finished"))
        game.ogs = service
        service.connect(to: game, withChat: true, owner: .explicit(UUID()))
        XCTAssertTrue(
            game.setConditionalMovePlan(
                try ConditionalMovePlan(
                    gameID: 47,
                    ownerID: 1,
                    rootMoveNumber: 0,
                    paths: [[.placeStone(0, 0), .placeStone(1, 1)]]
                )
            )
        )
        XCTAssertNotNil(game.conditionalMovePlan)
        socket.emissions.removeAll()
        let reconnectCountBeforeChange = socket.closeThenReconnectCount

        service.ogsUIConfig = try makeUIConfig(jwt: "new-test-jwt", userID: 2)

        XCTAssertNil(game.conditionalMovePlan)
        XCTAssertTrue(game.conditionalMoveBranches.isEmpty)
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/disconnect" }.count, 1)
        XCTAssertEqual(socket.emissions.filter { $0.command == "chat/part" }.count, 1)
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCountBeforeChange + 1)

        socket.emissions.removeAll()
        socket.openSocket(authenticate: true)
        XCTAssertFalse(socket.emissions.contains { $0.command == "game/connect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/join" })
    }

    func testSameUserJWTRotationPreservesFinishedGameAndChatIntent() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        service.ogsUIConfig = try makeUIConfig(jwt: "old-test-jwt", userID: 1)
        socket.openSocket(authenticate: true)

        let game = Game(ogsGame: try makeEmptyGameData(id: 48, phase: "finished"))
        game.ogs = service
        service.connect(to: game, withChat: true, owner: .explicit(UUID()))
        socket.emissions.removeAll()
        let reconnectCountBeforeRotation = socket.closeThenReconnectCount

        service.ogsUIConfig = try makeUIConfig(jwt: "new-test-jwt", userID: 1)

        XCTAssertFalse(socket.emissions.contains { $0.command == "game/disconnect" })
        XCTAssertFalse(socket.emissions.contains { $0.command == "chat/part" })
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCountBeforeRotation)
        XCTAssertEqual(service.ogsUIConfig?.userJwt, "new-test-jwt")

        socket.dropSocket()
        socket.emissions.removeAll()
        socket.openSocket(authenticate: true)
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 1)
        XCTAssertEqual(socket.emissions.filter { $0.command == "chat/join" }.count, 1)
    }

    func testPushedUserJWTUpdatesConfigWithoutReconnecting() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        service.ogsUIConfig = try makeUIConfig(jwt: "old-test-jwt", userID: 1)
        let reconnectCountBeforePush = socket.closeThenReconnectCount

        socket.deliver(
            name: "user/jwt",
            data: OGSWebsocketJWTUpdate(
                userJwt: "pushed-test-jwt",
                authenticatedUserID: 1
            )
        )

        XCTAssertEqual(service.ogsUIConfig?.userJwt, "pushed-test-jwt")
        XCTAssertEqual(
            socket.authenticationConfigProvider()?.userJwt,
            "pushed-test-jwt"
        )
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCountBeforePush)
    }

    func testPushedJWTFromPreviousAccountDoesNotOverwriteCurrentConfig() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        service.ogsUIConfig = try makeUIConfig(jwt: "old-account-jwt", userID: 1)
        service.ogsUIConfig = try makeUIConfig(jwt: "current-account-jwt", userID: 2)
        let reconnectCountAfterSwitch = socket.closeThenReconnectCount

        socket.deliver(
            name: "user/jwt",
            data: OGSWebsocketJWTUpdate(
                userJwt: "late-old-account-jwt",
                authenticatedUserID: 1
            )
        )

        XCTAssertEqual(service.ogsUIConfig?.user.id, 2)
        XCTAssertEqual(service.ogsUIConfig?.userJwt, "current-account-jwt")
        XCTAssertEqual(socket.closeThenReconnectCount, reconnectCountAfterSwitch)
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
                emissions.append(.init(
                    command: command,
                    data: data,
                    hasResultCallback: resultCallback != nil
                ))
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
        cachedUsers: [OGSUser] = [],
        installsObservers: Bool = false,
        gameResynchronizationTimeout: TimeInterval = 15,
        conditionalMoveSubmissionTimeout: TimeInterval = 10
    ) -> OGSService {
        preferenceSuite = "com.honganhkhoa.Surround.EventTests.\(UUID().uuidString)"
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectingURLProtocol.self]
        configuration.httpCookieStorage = nil
        let httpClient = AlamofireOGSHTTPClient(
            session: Session(configuration: configuration),
            cookieStorage: nil
        )
        var initialState: OGSService.BootstrapState?
        if !cachedUsers.isEmpty {
            var state = OGSService.BootstrapState()
            state.cachedUsersById = Dictionary(
                cachedUsers.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            initialState = state
        }
        return OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: UserDefaults(suiteName: preferenceSuite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: installsObservers,
            gameResynchronizationTimeout: gameResynchronizationTimeout,
            conditionalMoveSubmissionTimeout: conditionalMoveSubmissionTimeout,
            initialState: initialState
        )
    }

    private func makePublicGameUsers() throws -> [OGSUser] {
        let data = try JSONSerialization.data(withJSONObject: [
            ["id": 1, "username": "black"],
            ["id": 2, "username": "white"],
        ])
        return try JSONDecoder().decode([OGSUser].self, from: data)
    }

    private func makeShareableVariation(in game: Game) throws -> Variation {
        let branchPoint = try game.makeMove(move: .placeStone(0, 0))
        try game.makeMove(move: .placeStone(0, 1))
        let branch = try game.makeMove(
            move: .placeStone(1, 1),
            fromAnalyticsPosition: branchPoint
        )
        let terminal = try game.makeMove(
            move: .pass,
            fromAnalyticsPosition: branch
        )
        return try XCTUnwrap(game.moveTree.variation(to: terminal))
    }

    private func analysisChatEvent(
        name: String,
        from: Int,
        moves: String,
        marks: [String: String]? = nil
    ) -> [String: Any] {
        var body: [String: Any] = [
            "type": "analysis",
            "from": from,
            "moves": moves,
            "name": name,
        ]
        if let marks {
            body["marks"] = marks
        }
        return [
            "channel": "main",
            "line": [
                "body": body,
                "chat_id": "received-analysis-\(name)",
                "date": 1_700_000_000.0,
                "move_number": 2,
                "player_id": 1,
                "professional": false,
                "ranking": 25.0,
                "ui_class": "",
                "username": "black",
            ],
        ]
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

    private func oneBranchConditionalMovesRoot() -> [Any] {
        [
            NSNull(),
            [
                "aa": ["bb", [String: Any]()] as [Any],
            ],
        ]
    }

    private func twoBranchConditionalMovesRoot() -> [Any] {
        [
            NSNull(),
            [
                "..": ["cc", [String: Any]()] as [Any],
                "aa": ["bb", [String: Any]()] as [Any],
            ],
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
