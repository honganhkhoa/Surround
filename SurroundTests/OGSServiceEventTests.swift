//
//  OGSServiceEventTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import DictionaryCoding
import XCTest

// Async tests share the main actor with service timers and socket callbacks.
// @Published emits before storing its new value, so an expectation must not
// resume a test midway through the callback's remaining state updates.
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

    private final class QuickMatchStatsURLProtocol: URLProtocol {
        enum Plan {
            case response(statusCode: Int, body: Data)
            case failure(URLError)
            case hold
        }

        private static let lock = NSLock()
        private static var plans = [String: [Plan]]()
        private static var requests = [URLRequest]()
        private static var requestObservers = [String: () -> Void]()
        private static var stopObservers = [String: () -> Void]()

        static func reset() {
            lock.lock()
            plans.removeAll()
            requests.removeAll()
            requestObservers.removeAll()
            stopObservers.removeAll()
            lock.unlock()
        }

        static func ranks(in request: URLRequest) -> String? {
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.path == "/termination-api/automatch-stats" else {
                return nil
            }
            return components.queryItems?.first { $0.name == "ranks" }?.value
        }

        static func enqueue(_ plan: Plan, ranks: String) {
            lock.lock()
            plans[ranks, default: []].append(plan)
            lock.unlock()
        }

        static func observeNextRequest(ranks: String, _ observer: @escaping () -> Void) {
            lock.lock()
            requestObservers[ranks] = observer
            lock.unlock()
        }

        static func requestSnapshot() -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }

        static func observeNextStop(ranks: String, _ observer: @escaping () -> Void) {
            lock.lock()
            stopObservers[ranks] = observer
            lock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(
            for request: URLRequest
        ) -> URLRequest { request }

        override func startLoading() {
            let ranks = Self.ranks(in: request) ?? ""
            Self.lock.lock()
            Self.requests.append(request)
            var pendingPlans = Self.plans[ranks, default: []]
            let plan = pendingPlans.isEmpty
                ? Plan.failure(URLError(.resourceUnavailable))
                : pendingPlans.removeFirst()
            Self.plans[ranks] = pendingPlans
            let observer = Self.requestObservers.removeValue(forKey: ranks)
            Self.lock.unlock()
            observer?()

            switch plan {
            case .response(let statusCode, let body):
                respond(statusCode: statusCode, body: body)
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            case .hold:
                break
            }
        }

        override func stopLoading() {
            let ranks = Self.ranks(in: request) ?? ""
            Self.lock.lock()
            let observer = Self.stopObservers.removeValue(forKey: ranks)
            Self.lock.unlock()
            observer?()
        }

        private func respond(statusCode: Int, body: Data) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class QuickMatchStatsEventMonitor: EventMonitor {
        let queue = DispatchQueue.main
        private var observedRequests = Set<UUID>()
        private var completionObservers = [String: (AFDataResponse<Data?>) -> Void]()

        func observeCompletion(
            ranks: String,
            _ observer: @escaping (AFDataResponse<Data?>) -> Void
        ) {
            completionObservers[ranks] = observer
        }

        func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
            guard let urlRequest = request.request,
                  let ranks = QuickMatchStatsURLProtocol.ranks(in: urlRequest),
                  observedRequests.insert(request.id).inserted,
                  let observer = completionObservers.removeValue(forKey: ranks) else {
                return
            }
            // didParseResponse precedes the service callback. A second response
            // handler runs after responseJSON's handler on the same main queue.
            request.response(queue: .main, completionHandler: observer)
        }
    }

    private class FakeWebsocket: OGSWebsocketProtocol {
        struct Emission {
            let command: String
            let data: Any?
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

        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
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
        QuickMatchStatsURLProtocol.reset()
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

    @MainActor
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
            override func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
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

    func testOverviewSortsTiedCorrespondenceGamesByGameID() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket, installsObservers: false)
        let fixture = try makeEmptyGameData(id: 100)
        service.user = fixture.players.black

        let gameIDs = [308, 301, 306, 303, 305, 302, 307, 304]
        service.processOverview(overview: [
            "active_games": try gameIDs.map {
                try makeOverviewGameData(
                    id: $0,
                    speed: "correspondence",
                    currentPlayerID: fixture.players.black.id
                )
            },
        ])

        let sortedGames = service.sortedActiveCorrespondenceGamesOnUserTurn
        let timesLeft = sortedGames.compactMap {
            $0.clock?.blackTime.thinkingTimeLeft
        }
        XCTAssertEqual(timesLeft.count, gameIDs.count)
        XCTAssertEqual(Set(timesLeft).count, 1)
        XCTAssertEqual(
            sortedGames.compactMap(\.ogsID),
            gameIDs.sorted()
        )
    }

    func testFindAutomatchRequiresAnOpenAuthenticatedSocket() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        var lifecycleEvents = [OGSAutomatchLifecycleEvent.Kind]()
        let lifecycleCancellable = service.automatchLifecycleEvents.sink {
            lifecycleEvents.append($0.kind)
        }
        defer { lifecycleCancellable.cancel() }
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "service-test-id")

        XCTAssertTrue(service.findAutomatch(entry: entry))

        let emission = try XCTUnwrap(socket.emissions.last)
        XCTAssertEqual(emission.command, "automatch/find_match")
        let payload = try XCTUnwrap(emission.data as? [String: Any])
        XCTAssertEqual(payload["uuid"] as? String, "service-test-id")
        XCTAssertNil(payload["time_control"])
        let options = try XCTUnwrap(
            payload["size_speed_options"] as? [[String: Any]]
        )
        XCTAssertEqual(options.first?["size"] as? String, "9x9")
        XCTAssertEqual(options.first?["speed"] as? String, "rapid")
        XCTAssertEqual(options.first?["system"] as? String, "fischer")
        XCTAssertEqual(service.autoMatchEntryById[entry.uuid], entry)

        socket.deliver(name: "automatch/start", data: [
            "uuid": entry.uuid,
            "game_id": 901,
        ])
        XCTAssertEqual(
            lifecycleEvents.last,
            .started(
                uuid: entry.uuid,
                gameID: 901,
                requestedLocally: true
            )
        )

        socket.opened = false
        XCTAssertFalse(service.findAutomatch(entry: entry))

        socket.opened = true
        socket.authenticated = false
        XCTAssertFalse(service.findAutomatch(entry: entry))
        XCTAssertFalse(service.cancelAutomatch(entry: entry))

        socket.opened = false
        socket.authenticated = true
        XCTAssertFalse(service.cancelAutomatch(entry: entry))

        XCTAssertEqual(socket.emissions.count, 1)
    }

    func testFindAutomatchDoesNotReplaceRestoredLiveSearch() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let restoredEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-live-entry")
        let replacementEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "replacement-live-entry")

        socket.deliver(
            name: "automatch/entry",
            data: restoredEntry.jsonObject
        )

        XCTAssertEqual(service.activeLiveAutomatchEntry, restoredEntry)
        XCTAssertFalse(service.findAutomatch(entry: replacementEntry))
        XCTAssertTrue(socket.emissions.isEmpty)
        XCTAssertEqual(
            service.autoMatchEntryById,
            [restoredEntry.uuid: restoredEntry]
        )

        let correspondenceEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "additional-correspondence-entry")
        XCTAssertTrue(service.findAutomatch(entry: correspondenceEntry))
        XCTAssertEqual(
            socket.emissions.last?.command,
            "automatch/find_match"
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry, restoredEntry)
        XCTAssertEqual(service.autoMatchEntryById.count, 2)
    }

    func testRealtimeGameStartedNotificationCancelsLiveAutomatch() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "live-search-before-direct-game")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        socket.deliver(name: "notification", data: [
            "id": "game-started-902",
            "type": "gameStarted",
            "game_id": 902,
            "speed": "rapid",
        ])

        let cancellations = socket.emissions.filter {
            $0.command == "automatch/cancel"
        }
        XCTAssertEqual(cancellations.count, 1)
        XCTAssertEqual(
            (try XCTUnwrap(cancellations.first?.data as? [String: Any]))["uuid"]
                as? String,
            liveEntry.uuid
        )
        socket.deliver(name: "automatch/start", data: [
            "uuid": liveEntry.uuid,
            "game_id": 902,
        ])
        XCTAssertNil(service.activeLiveAutomatchEntry)
    }

    func testCurrentStartDuringConfirmationReconciliationCancelsLiveSearch() {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 60,
            automatchConfirmationTimeout: 60
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "live-search-awaiting-confirmation")

        XCTAssertTrue(service.findAutomatch(entry: liveEntry))
        service.handleAutomatchConfirmationTimeout(for: liveEntry.uuid)
        XCTAssertTrue(service.isReconcilingAutomatches)

        socket.deliver(name: "notification", data: [
            "id": "current-start-during-confirmation-list",
            "type": "gameStarted",
            "game_id": 915,
            "speed": "rapid",
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    func testServerEchoWithoutTimestampKeepsLocalSubmissionBoundary() {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchConfirmationTimeout: 60,
            currentTime: 2_000_000_120
        )
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_120_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "local-entry-with-timestampless-echo")

        XCTAssertTrue(service.findAutomatch(entry: liveEntry))
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        socket.deliver(name: "notification", data: [
            "id": "start-before-local-submission",
            "type": "gameStarted",
            "game_id": 926,
            "speed": "rapid",
            "timestamp": 1_999_999_999,
        ])
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        socket.deliver(name: "notification", data: [
            "id": "start-after-local-submission",
            "type": "gameStarted",
            "game_id": 927,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    func testTimestampLessDuplicatePreservesKnownServerCreationTimestamp()
        throws
    {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "timestamped-entry-then-duplicate")

        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                service.autoMatchEntryById[liveEntry.uuid]?.creationTimestamp
            ),
            1_999_999_900,
            accuracy: 0.001
        )

        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        XCTAssertEqual(
            try XCTUnwrap(
                service.autoMatchEntryById[liveEntry.uuid]?.creationTimestamp
            ),
            1_999_999_900,
            accuracy: 0.001
        )
    }

    @MainActor
    func testRealtimeGameStartedNotificationBeforeRestoredEntryCancelsOnce()
        async throws
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let notification: [String: Any] = [
            "id": "game-started-before-restored-entry",
            "type": "gameStarted",
            "game_id": 908,
            "speed": "rapid",
            // Exercise the millisecond form used by some OGS notifications.
            "timestamp": 2_000_000_000_000 as NSNumber,
        ]
        let correspondenceEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-correspondence-entry")
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-live-entry-after-notification")
        let reconciliationFinished = expectation(
            description: "Current game start replay was reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_000_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])
        socket.deliver(name: "notification", data: notification)
        socket.deliver(name: "notification", data: notification)
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        // A correspondence replay must not consume the pending realtime start.
        socket.deliver(
            name: "automatch/entry",
            data: correspondenceEntry.jsonObject
        )
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_999
            )
        )
        socket.deliver(name: "notification", data: notification)
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let cancellations = socket.emissions.filter {
            $0.command == "automatch/cancel"
        }
        XCTAssertEqual(cancellations.count, 1)
        XCTAssertEqual(
            (try XCTUnwrap(cancellations.first?.data as? [String: Any]))["uuid"]
                as? String,
            liveEntry.uuid
        )
    }

    @MainActor
    func testCompletedHistoricalGameBeforeRestoredEntryDoesNotCancelSearch()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "search-restored-after-finished-game")
        let reconciliationFinished = expectation(
            description: "Historical completed game replay was reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: [
            "id": "historical-start-before-end",
            "type": "gameStarted",
            "game_id": 911,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(name: "notification", data: [
            "id": "historical-end-before-entry",
            "type": "gameEnded",
            "game_id": 911,
            "timestamp": 1_900_000_120,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testGameEndedAfterRestoredEntrySuppressesPendingCurrentStart() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "search-restored-before-game-ended")
        let reconciliationFinished = expectation(
            description: "Late completion in notification replay was observed"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: [
            "id": "start-before-restored-entry",
            "type": "gameStarted",
            "game_id": 912,
            "speed": "blitz",
            "time": 2_000_000_000,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        socket.deliver(name: "notification", data: [
            "id": "end-after-restored-entry",
            "type": "gameEnded",
            "game_id": 912,
            "time": 2_000_000_001,
        ])

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testColdLaunchOldUnfinishedStartDoesNotCancelRestoredSearch() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .fischer
        ).makeAutomatchEntry(uuid: "cold-launch-restored-search")
        let reconciliationFinished = expectation(
            description: "Cold-launch notification replay was reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: [
            "id": "old-unfinished-game-start",
            "type": "gameStarted",
            "game_id": 913,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_950_000_000
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testStalePreDisconnectActiveGameDoesNotOverrideHistoricalStartAge()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let staleGameID = 917

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: staleGameID,
                phase: "play",
                timePerMove: 60
            )
        )
        XCTAssertNotNil(service.activeGames[staleGameID])
        socket.deliver(name: "surround/socketClosed")
        XCTAssertNotNil(
            service.activeGames[staleGameID],
            "Active games remain visible while the socket reconnects."
        )

        let reconciliationFinished = expectation(
            description: "Historical start ignored after reconnect"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }
        let restoredEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "search-restored-with-stale-active-game")

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: [
            "id": "old-start-for-stale-active-game",
            "type": "gameStarted",
            "game_id": staleGameID,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                restoredEntry,
                creationTimestamp: 1_950_000_000
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, restoredEntry.uuid)
    }

    @MainActor
    func testCurrentActiveGameDoesNotOverrideNewerAutomatchTimestamp()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let activeGameID = 918
        let restoredEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "search-restored-with-current-active-game")
        let reconciliationFinished = expectation(
            description: "Current active game reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: activeGameID,
                phase: "play",
                timePerMove: 60
            )
        )
        socket.deliver(name: "notification", data: [
            "id": "old-start-for-current-active-game",
            "type": "gameStarted",
            "game_id": activeGameID,
            "speed": "blitz",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                restoredEntry,
                creationTimestamp: 1_950_000_000
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, restoredEntry.uuid)
    }

    @MainActor
    func testActiveGameNewerThanAutomatchCancelsDespiteAbsoluteAge() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let activeGameID = 924
        let restoredEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "older-search-with-current-active-game")
        let reconciliationFinished = expectation(
            description: "Ordered active game replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: activeGameID,
                phase: "play",
                timePerMove: 60
            )
        )
        socket.deliver(name: "notification", data: [
            "id": "newer-start-for-current-active-game",
            "type": "gameStarted",
            "game_id": activeGameID,
            "speed": "blitz",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                restoredEntry,
                creationTimestamp: 1_800_000_000
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testLateActiveGameStartOlderThanAutomatchDoesNotCancel() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let activeGameID = 919
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: activeGameID,
                phase: "play",
                timePerMove: 60
            )
        )
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "late-search-with-current-active-game")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_950_000_000
            )
        )
        socket.deliver(name: "notification", data: [
            "id": "late-old-start-for-current-active-game",
            "type": "gameStarted",
            "game_id": activeGameID,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testLateActiveGameStartNewerThanAutomatchCancels() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let activeGameID = 925
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: activeGameID,
                phase: "play",
                timePerMove: 60
            )
        )
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "older-search-with-late-active-start")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_800_000_000
            )
        )
        socket.deliver(name: "notification", data: [
            "id": "late-newer-start-for-current-active-game",
            "type": "gameStarted",
            "game_id": activeGameID,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testLateHistoricalStartAfterReplayWindowDoesNotCancelSearch() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay window finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_000_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "search-before-late-history")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "late-historical-game-start",
            "type": "gameStarted",
            "game_id": 914,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(name: "notification", data: [
            "id": "invalid-future-game-start",
            "type": "gameStarted",
            "game_id": 916,
            "speed": "rapid",
            "timestamp": 2_100_000_000,
        ])

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testPendingGameStartedNotificationExpiresBeforeNewLocalSearch() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            automatchConfirmationTimeout: 60
        )
        let notification: [String: Any] = [
            "id": "game-started-without-restored-entry",
            "type": "gameStarted",
            "game_id": 909,
            "speed": "blitz",
        ]
        let reconciliationFinished = expectation(
            description: "Authenticated automatch replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: notification)
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let localEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "new-local-search-after-reconciliation")
        XCTAssertTrue(service.findAutomatch(entry: localEntry))

        socket.deliver(name: "notification", data: notification)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry, localEntry)
    }

    @MainActor
    func testSocketCloseDiscardsPendingGameStartedNotificationGeneration()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let notification: [String: Any] = [
            "id": "game-started-across-reconnect",
            "type": "gameStarted",
            "game_id": 910,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ]
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "live-entry-after-second-authentication")

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: notification)
        socket.deliver(name: "surround/socketClosed")

        let reconciliationFinished = expectation(
            description: "Second authenticated replay was reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_000_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])
        socket.deliver(name: "notification", data: notification)
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testReplayWithoutCreationTimestampKeepsSearchEvenForActiveGame()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-search-without-ordering")
        let reconciliationFinished = expectation(
            description: "Ambiguous replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(id: 920, phase: "play", timePerMove: 60)
        )
        socket.deliver(name: "notification", data: [
            "id": "active-start-without-search-ordering",
            "type": "gameStarted",
            "game_id": 920,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ])
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testFreshPongCorrectsDeviceClockForLateNotificationRecency() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished before late push"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_120_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "late-search-with-clock-skew")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "current-start-with-clock-skew",
            "type": "gameStarted",
            "game_id": 921,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
        XCTAssertEqual(socket.drift, 120_000, accuracy: 0.001)
    }

    @MainActor
    func testFreshPongCorrectsSlowDeviceClockForLateNotificationRecency()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 1_999_999_880
        )
        let reconciliationFinished = expectation(
            description: "Replay finished on a slow device clock"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)
        socket.deliver(name: "net/pong", data: [
            "client": 1_999_999_880_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "late-search-with-slow-clock")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "current-start-with-slow-clock",
            "type": "gameStarted",
            "game_id": 923,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
        XCTAssertEqual(socket.drift, -120_000, accuracy: 0.001)
    }

    @MainActor
    func testLateNotificationWithoutCurrentConnectionPongIsConservative()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished without a pong"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "late-search-without-clock-sample")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "ambiguous-start-without-clock-sample",
            "type": "gameStarted",
            "game_id": 922,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testKnownNewerServerOrderingCancelsWithoutPongOrActiveGame()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished without a pong"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "ordered-search-without-clock-sample")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )
        socket.deliver(name: "notification", data: [
            "id": "ordered-start-without-clock-sample",
            "type": "gameStarted",
            "game_id": 928,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testLateServerEntryReconsidersNewerOrphanGameStart() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished before game start"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)
        socket.deliver(name: "notification", data: [
            "id": "orphan-start-before-entry",
            "type": "gameStarted",
            "game_id": 929,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ])
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "entry-after-current-start")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testLateServerEntryIgnoresOlderAndCompletedOrphanStarts() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished before orphan events"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)
        socket.deliver(name: "notification", data: [
            "id": "old-orphan-start-before-entry",
            "type": "gameStarted",
            "game_id": 930,
            "speed": "rapid",
            "timestamp": 1_900_000_000,
        ])
        socket.deliver(name: "notification", data: [
            "id": "completed-orphan-start-before-entry",
            "type": "gameStarted",
            "game_id": 931,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ])
        socket.deliver(name: "notification", data: [
            "id": "completed-orphan-end-before-entry",
            "type": "gameEnded",
            "game_id": 931,
            "timestamp": 2_000_000_001,
        ])

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "entry-after-old-and-completed-starts")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_950_000_000
            )
        )

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry?.uuid, liveEntry.uuid)
    }

    @MainActor
    func testReconnectReplaysHandledOrphanBeforeRestoredEntry() async throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01
        )
        let firstReconciliationFinished = expectation(
            description: "Initial authenticated replay finished"
        )
        let firstCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in firstReconciliationFinished.fulfill() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [firstReconciliationFinished], timeout: 1)
        firstCancellable.cancel()

        let notification: [String: Any] = [
            "id": "orphan-replayed-after-reconnect",
            "type": "gameStarted",
            "game_id": 932,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ]
        socket.deliver(name: "notification", data: notification)
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        socket.deliver(name: "surround/socketClosed")
        let secondReconciliationFinished = expectation(
            description: "Reconnect replay correlated restored entry"
        )
        let secondCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in secondReconciliationFinished.fulfill() }
        defer { secondCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "notification", data: notification)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "entry-restored-after-orphan-replay")
        socket.deliver(
            name: "automatch/entry",
            data: inboundAutomatchPayload(
                liveEntry,
                creationTimestamp: 1_999_999_900
            )
        )

        await fulfillment(of: [secondReconciliationFinished], timeout: 1)

        let cancellations = socket.emissions.filter {
            $0.command == "automatch/cancel"
        }
        XCTAssertEqual(cancellations.count, 1)
        XCTAssertEqual(
            (try XCTUnwrap(cancellations.first?.data as? [String: Any]))["uuid"]
                as? String,
            liveEntry.uuid
        )
    }

    @MainActor
    func testFreshPongReconsidersInconclusiveStartForLocalSearch() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            automatchConfirmationTimeout: 60,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished before local search"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "local-search-before-first-pong")
        XCTAssertTrue(service.findAutomatch(entry: liveEntry))
        socket.deliver(name: "notification", data: [
            "id": "current-start-before-first-pong",
            "type": "gameStarted",
            "game_id": 933,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_120_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testFreshPongUsesRecencyForTimestampLessRestoredEntry() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Authenticated replay finished before restored entry"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-search-before-first-pong")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "current-start-for-timestampless-restored-entry",
            "type": "gameStarted",
            "game_id": 934,
            "speed": "rapid",
            "timestamp": 2_000_000_001,
        ])
        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )

        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_120_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testJSONNumberOneTimestampIsNotRejectedAsBoolean() async throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 1
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .fischer
        ).makeAutomatchEntry(uuid: "numeric-one-timestamp-search")
        let reconciliationFinished = expectation(
            description: "Numeric-one timestamp replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(id: 2, phase: "play", timePerMove: 60)
        )
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"numeric-one-time","type":"gameStarted","game_id":2,"speed":"blitz","timestamp":1}"#
            )
        )
        var entryPayload = liveEntry.jsonObject
        // Keep this deliberately in seconds: values this close to the epoch
        // are ambiguous with the server's usual millisecond wire form, while
        // this fixture specifically exercises JSON NSNumber(1) vs Bool.
        entryPayload["timestamp"] = 0.5 as NSNumber
        socket.deliver(name: "automatch/entry", data: entryPayload)

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    @MainActor
    func testJSONBooleanTimestampIsRejected() async throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 1
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .fischer
        ).makeAutomatchEntry(uuid: "boolean-timestamp-search")
        let reconciliationFinished = expectation(
            description: "Boolean timestamp replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "active_game",
            data: makeShortGameData(id: 2, phase: "play", timePerMove: 60)
        )
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"boolean-time","type":"gameStarted","game_id":2,"speed":"blitz","timestamp":true}"#
            )
        )
        var entryPayload = liveEntry.jsonObject
        entryPayload["timestamp"] = 0.5 as NSNumber
        socket.deliver(name: "automatch/entry", data: entryPayload)

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
    }

    @MainActor
    func testJSONNumberOneGameIDCorrelatesCompletion() async throws {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "numeric-one-game-id-search")
        let reconciliationFinished = expectation(
            description: "Numeric-one game completion replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(name: "net/pong", data: [
            "client": 2_000 as NSNumber,
            "server": 2_000 as NSNumber,
        ])
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"numeric-one-game-start","type":"gameStarted","game_id":1,"speed":"rapid","timestamp":2}"#
            )
        )
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"numeric-one-game-end","type":"gameEnded","game_id":1,"timestamp":2}"#
            )
        )
        var entryPayload = liveEntry.jsonObject
        entryPayload["timestamp"] = 1 as NSNumber
        socket.deliver(name: "automatch/entry", data: entryPayload)

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
    }

    @MainActor
    func testJSONBooleanGameIDDoesNotCorrelateCompletionForGameOne()
        async throws
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2
        )
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "boolean-game-id-search")
        let reconciliationFinished = expectation(
            description: "Boolean game ID completion replay finished"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        socket.deliver(name: "surround/socketAuthenticated")
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"numeric-game-start-before-boolean-end","type":"gameStarted","game_id":1,"speed":"rapid","timestamp":2}"#
            )
        )
        socket.deliver(
            name: "notification",
            data: try jsonDictionary(
                #"{"id":"boolean-game-end","type":"gameEnded","game_id":true,"timestamp":2}"#
            )
        )
        var entryPayload = liveEntry.jsonObject
        entryPayload["timestamp"] = 1 as NSNumber
        socket.deliver(name: "automatch/entry", data: entryPayload)

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    func testPositiveIntegerRejectsJSONBridgeAndOverflowEdges() throws {
        let service = makeService(socket: FakeWebsocket())
        let values = try jsonDictionary(
            #"{"one":1,"zero":0,"max":9223372036854775807,"overflow":9223372036854775808,"fraction":1.5,"boolean":true}"#
        )

        XCTAssertEqual(service.positiveInteger(values["one"]), 1)
        XCTAssertNil(service.positiveInteger(values["zero"]))
        XCTAssertEqual(service.positiveInteger(values["max"]), Int.max)
        XCTAssertNil(service.positiveInteger(values["overflow"]))
        XCTAssertNil(service.positiveInteger(values["fraction"]))
        XCTAssertNil(service.positiveInteger(values["boolean"]))
    }

    func testCorrespondenceGameStartedNotificationDoesNotCancelLiveAutomatch() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "live-search-kept-for-correspondence")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        socket.deliver(
            name: "notification",
            data: [
                "id": "game-started-903",
                "type": "gameStarted",
                "game_id": 903,
                "speed": "correspondence",
            ]
        )

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry, liveEntry)
    }

    func testActiveGameReplayDoesNotCancelLiveAutomatch() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "live-search-during-reconnect")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)

        socket.deliver(
            name: "active_game",
            data: makeShortGameData(
                id: 905,
                phase: "play",
                timePerMove: 60
            )
        )

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry, liveEntry)
        XCTAssertNotNil(service.activeGames[905])
    }

    func testAutomatchStartBeforeGameStartedNotificationDoesNotCancelAgain() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "automatch-starts-first")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "automatch/start", data: [
            "uuid": liveEntry.uuid,
            "game_id": 906,
        ])

        socket.deliver(name: "notification", data: [
            "id": "game-started-906",
            "type": "gameStarted",
            "game_id": 906,
            "speed": "rapid",
        ])

        XCTAssertTrue(
            socket.emissions.allSatisfy { $0.command != "automatch/cancel" }
        )
        XCTAssertNil(service.activeLiveAutomatchEntry)
    }

    func testReplayedGameStartedNotificationDoesNotCancelNewerAutomatch() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let firstEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .blitz,
            system: .fischer
        ).makeAutomatchEntry(uuid: "search-before-notification")
        let newerEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "search-after-notification")
        let notification: [String: Any] = [
            "id": "replayed-game-started",
            "type": "gameStarted",
            "game_id": 907,
            "speed": "rapid",
        ]

        socket.deliver(name: "automatch/entry", data: firstEntry.jsonObject)
        socket.deliver(name: "notification", data: notification)
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
        socket.deliver(name: "automatch/cancel", data: [
            "uuid": firstEntry.uuid,
        ])
        socket.deliver(name: "automatch/entry", data: newerEntry.jsonObject)

        socket.deliver(name: "notification", data: notification)

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
        XCTAssertEqual(service.activeLiveAutomatchEntry, newerEntry)
    }

    func testFindAutomatchWaitsForReconnectReconciliation() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "premature-live-entry")

        socket.deliver(name: "surround/socketAuthenticated")
        XCTAssertTrue(service.isReconcilingAutomatches)
        XCTAssertEqual(socket.emissions.last?.command, "automatch/list")
        XCTAssertTrue(
            (socket.emissions.last?.data as? [String: Any])?.isEmpty
                == true
        )
        let emissionCount = socket.emissions.count

        XCTAssertFalse(service.findAutomatch(entry: entry))
        XCTAssertEqual(socket.emissions.count, emissionCount)
        XCTAssertTrue(service.autoMatchEntryById.isEmpty)
    }

    func testAnonymousAuthenticationRequestsAutomatchListExactlyOnce() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)

        XCTAssertNil(socket.authenticationConfigProvider())

        socket.deliver(name: "surround/socketAuthenticated")

        XCTAssertTrue(service.isReconcilingAutomatches)
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/list" }.count,
            1
        )
    }

    @MainActor
    func testPongBeforeDelayedAnonymousAuthenticationRemainsFresh()
        async
    {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            currentTime: 2_000_000_120
        )
        let reconciliationFinished = expectation(
            description: "Delayed anonymous authentication reconciled"
        )
        let reconciliationCancellable = service.$isReconcilingAutomatches
            .dropFirst()
            .first { !$0 }
            .sink { _ in reconciliationFinished.fulfill() }
        defer { reconciliationCancellable.cancel() }

        XCTAssertNil(socket.authenticationConfigProvider())
        socket.openSocket()
        socket.deliver(name: "net/pong", data: [
            "client": 2_000_000_120_000 as NSNumber,
            "server": 2_000_000_000_000 as NSNumber,
        ])
        socket.markAuthenticated()

        await fulfillment(of: [reconciliationFinished], timeout: 1)

        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "restored-after-delayed-anonymous-auth")
        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        socket.deliver(name: "notification", data: [
            "id": "current-start-after-delayed-anonymous-auth",
            "type": "gameStarted",
            "game_id": 927,
            "speed": "rapid",
            "timestamp": 2_000_000_000,
        ])

        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/cancel" }.count,
            1
        )
    }

    func testAutomatchLifecycleRemovesIndividualAndAllSearches() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        var lifecycleEvents = [OGSAutomatchLifecycleEvent.Kind]()
        let lifecycleCancellable = service.automatchLifecycleEvents.sink {
            lifecycleEvents.append($0.kind)
        }
        defer { lifecycleCancellable.cancel() }
        let liveEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "live-entry")
        let firstCorrespondenceEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "correspondence-entry-1")
        let secondCorrespondenceEntry = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 19,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "correspondence-entry-2")

        for entry in [
            liveEntry,
            firstCorrespondenceEntry,
            secondCorrespondenceEntry,
        ] {
            socket.deliver(name: "automatch/entry", data: entry.jsonObject)
        }
        XCTAssertEqual(service.autoMatchEntryById.count, 3)

        socket.deliver(name: "automatch/start", data: [
            "uuid": liveEntry.uuid,
            "game_id": 123,
        ])
        XCTAssertNil(service.autoMatchEntryById[liveEntry.uuid])
        XCTAssertEqual(
            lifecycleEvents.last,
            .started(
                uuid: liveEntry.uuid,
                gameID: 123,
                requestedLocally: false
            )
        )

        socket.deliver(name: "automatch/cancel", data: [
            "uuid": firstCorrespondenceEntry.uuid,
        ])
        XCTAssertNil(
            service.autoMatchEntryById[firstCorrespondenceEntry.uuid]
        )
        XCTAssertNotNil(
            service.autoMatchEntryById[secondCorrespondenceEntry.uuid]
        )
        XCTAssertEqual(
            lifecycleEvents.last,
            .cancelled(
                uuid: firstCorrespondenceEntry.uuid,
                removedCount: 1
            )
        )

        socket.deliver(name: "automatch/cancel", data: [
            "uuid": "unknown-entry",
        ])
        XCTAssertEqual(
            lifecycleEvents.last,
            .cancelled(uuid: "unknown-entry", removedCount: 0)
        )

        socket.deliver(name: "automatch/entry", data: liveEntry.jsonObject)
        XCTAssertEqual(service.autoMatchEntryById.count, 2)
        socket.deliver(name: "automatch/cancel", data: [
            "uuid": NSNull(),
        ])

        XCTAssertTrue(service.autoMatchEntryById.isEmpty)
        XCTAssertEqual(
            lifecycleEvents.last,
            .cancelled(uuid: nil, removedCount: 2)
        )
    }

    func testAutomatchListReplayRestoresEntriesAfterAuthentication() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .live,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "replayed-entry")

        socket.deliver(name: "automatch/entry", data: entry.jsonObject)
        XCTAssertNotNil(service.autoMatchEntryById[entry.uuid])

        socket.deliver(name: "surround/socketAuthenticated")
        XCTAssertTrue(service.isReconcilingAutomatches)
        XCTAssertEqual(service.autoMatchEntryById[entry.uuid], entry)
        XCTAssertEqual(socket.emissions.last?.command, "automatch/list")
        XCTAssertTrue(
            (socket.emissions.last?.data as? [String: Any])?.isEmpty
                == true
        )

        socket.deliver(name: "automatch/entry", data: entry.jsonObject)
        XCTAssertNotNil(service.autoMatchEntryById[entry.uuid])
    }

    @MainActor
    func testAutomatchReconciliationRemovesAnEntryMissingFromReplay() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            automatchConfirmationTimeout: 60
        )
        var lifecycleEvents = [OGSAutomatchLifecycleEvent.Kind]()
        let reconciled = expectation(
            description: "Missing automatch entry reconciled"
        )
        let lifecycleCancellable = service.automatchLifecycleEvents.sink {
            lifecycleEvents.append($0.kind)
            if $0.kind == .notFoundAfterReconciliation(
                uuid: "missing-replayed-entry"
            ) {
                reconciled.fulfill()
            }
        }
        defer { lifecycleCancellable.cancel() }
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .live,
            system: .fischer
        ).makeAutomatchEntry(uuid: "missing-replayed-entry")

        socket.deliver(name: "automatch/entry", data: entry.jsonObject)
        socket.deliver(name: "surround/socketAuthenticated")
        await fulfillment(of: [reconciled], timeout: 1)

        XCTAssertNil(service.autoMatchEntryById[entry.uuid])
        XCTAssertFalse(service.isReconcilingAutomatches)
        XCTAssertEqual(
            lifecycleEvents.last,
            .notFoundAfterReconciliation(uuid: entry.uuid)
        )
    }

    @MainActor
    func testUnconfirmedOutboundAutomatchReconcilesInsteadOfStayingForever() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            automatchConfirmationTimeout: 0.01
        )
        var lifecycleEvents = [OGSAutomatchLifecycleEvent.Kind]()
        let reconciled = expectation(
            description: "Unconfirmed outbound automatch reconciled"
        )
        let lifecycleCancellable = service.automatchLifecycleEvents.sink {
            lifecycleEvents.append($0.kind)
            if $0.kind == .notFoundAfterReconciliation(
                uuid: "unconfirmed-outbound-entry"
            ) {
                reconciled.fulfill()
            }
        }
        defer { lifecycleCancellable.cancel() }
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .rapid,
            system: .fischer
        ).makeAutomatchEntry(uuid: "unconfirmed-outbound-entry")

        XCTAssertTrue(service.findAutomatch(entry: entry))
        XCTAssertNotNil(service.autoMatchEntryById[entry.uuid])
        await fulfillment(of: [reconciled], timeout: 1)

        XCTAssertNil(service.autoMatchEntryById[entry.uuid])
        XCTAssertTrue(
            socket.emissions.contains {
                $0.command == "automatch/list"
                    && ($0.data as? [String: Any])?.isEmpty == true
            }
        )
        XCTAssertEqual(
            lifecycleEvents.last,
            .notFoundAfterReconciliation(uuid: entry.uuid)
        )
    }

    func testConfirmedRequestTimerCannotReconcileNewerRequest() {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 60,
            automatchConfirmationTimeout: 60
        )
        let confirmedEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "confirmed-request-a")
        let newerEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "unconfirmed-request-b")

        XCTAssertTrue(service.findAutomatch(entry: confirmedEntry))
        socket.deliver(
            name: "automatch/entry",
            data: confirmedEntry.jsonObject
        )
        XCTAssertTrue(service.findAutomatch(entry: newerEntry))
        let emissionCount = socket.emissions.count

        service.handleAutomatchConfirmationTimeout(for: confirmedEntry.uuid)

        XCTAssertEqual(socket.emissions.count, emissionCount)
        XCTAssertFalse(service.isReconcilingAutomatches)
        XCTAssertEqual(service.autoMatchEntryById[newerEntry.uuid], newerEntry)

        service.handleAutomatchConfirmationTimeout(for: newerEntry.uuid)

        XCTAssertTrue(service.isReconcilingAutomatches)
        XCTAssertEqual(socket.emissions.last?.command, "automatch/list")
    }

    @MainActor
    func testExpiredConfirmationWaitsForActiveReconciliation() async {
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            automatchReconciliationTimeout: 0.01,
            automatchConfirmationTimeout: 60
        )
        let firstEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 9,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "first-expired-request")
        let queuedEntry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "queued-expired-request")
        let queuedReconciled = expectation(
            description: "Queued automatch reconciliation completed"
        )
        let lifecycleCancellable = service.automatchLifecycleEvents.sink {
            if $0.kind == .notFoundAfterReconciliation(
                uuid: queuedEntry.uuid
            ) {
                queuedReconciled.fulfill()
            }
        }
        defer { lifecycleCancellable.cancel() }

        XCTAssertTrue(service.findAutomatch(entry: firstEntry))
        XCTAssertTrue(service.findAutomatch(entry: queuedEntry))
        service.handleAutomatchConfirmationTimeout(for: firstEntry.uuid)
        XCTAssertTrue(service.isReconcilingAutomatches)
        service.handleAutomatchConfirmationTimeout(for: queuedEntry.uuid)

        await fulfillment(of: [queuedReconciled], timeout: 1)

        XCTAssertNil(service.autoMatchEntryById[queuedEntry.uuid])
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "automatch/list" }.count,
            2
        )
    }

    func testDegradedInboundAutomatchEntryRemainsCancellable() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let uuid = "future-automatch-id"

        socket.deliver(name: "automatch/entry", data: [
            "uuid": uuid,
            "size_speed_options": [
                ["size": "9x9", "speed": "hyper", "system": "canadian"],
            ],
            "rules": ["condition": "optional", "value": "future-rules"],
            "handicap": "future-handicap-shape",
        ])

        let entry = try XCTUnwrap(service.autoMatchEntryById[uuid])
        XCTAssertEqual(entry.uuid, uuid)
        XCTAssertTrue(entry.sizeSpeedOptions.isEmpty)

        XCTAssertTrue(service.cancelAutomatch(entry: entry))

        let emission = try XCTUnwrap(socket.emissions.last)
        XCTAssertEqual(emission.command, "automatch/cancel")
        let payload = try XCTUnwrap(emission.data as? [String: String])
        XCTAssertEqual(payload, ["uuid": uuid])
    }

    func testAvailableAutomatchParserKeepsOnlyStrictKnownOptions() throws {
        let entry = try XCTUnwrap(OGSAutomatchAvailableEntry([
            "uuid": "available-id",
            "player": [
                "id": 42,
                "bounded_rank": 20.5,
            ],
            "preferences": [
                "lower_rank_diff": 2,
                "upper_rank_diff": 4,
                "size_speed_options": [
                    [
                        "size": "9x9",
                        "speed": "rapid",
                        "system": "fischer",
                    ],
                    [
                        "size": "9x9",
                        "speed": "rapid",
                        "system": "fischer",
                    ],
                    [
                        "size": "13x13",
                        "speed": "rapid",
                        "system": "future-clock",
                    ],
                    [
                        "size": "19x19",
                        "speed": "live",
                    ],
                ],
            ],
        ]))

        XCTAssertEqual(entry.uuid, "available-id")
        XCTAssertEqual(entry.playerID, 42)
        XCTAssertEqual(entry.playerBoundedRank, 20.5)
        XCTAssertEqual(entry.lowerRankDifference, 2)
        XCTAssertEqual(entry.upperRankDifference, 4)
        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .rapid,
                    system: .fischer
                ),
            ]
        )

        let degraded = try XCTUnwrap(
            OGSAutomatchAvailableEntry(["uuid": "degraded-id"])
        )
        XCTAssertTrue(degraded.sizeSpeedOptions.isEmpty)
        XCTAssertNil(degraded.playerID)
        XCTAssertNil(degraded.playerBoundedRank)
        XCTAssertNil(degraded.lowerRankDifference)
        XCTAssertNil(degraded.upperRankDifference)
    }

    func testAvailableAutomatchParserRejectsUnsafeNumericCoercions() throws {
        let entry = try XCTUnwrap(OGSAutomatchAvailableEntry([
            "uuid": "strict-numbers",
            "player": [
                "id": true,
                "bounded_rank": Double.infinity,
            ],
            "preferences": [
                "lower_rank_diff": 1.5,
                "upper_rank_diff": -1,
                "size_speed_options": [],
            ],
        ]))

        XCTAssertNil(entry.playerID)
        XCTAssertNil(entry.playerBoundedRank)
        XCTAssertNil(entry.lowerRankDifference)
        XCTAssertNil(entry.upperRankDifference)
    }

    func testActivityParsersDistinguishJSONNumbersFromBooleans() throws {
        let availabilityObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"""
            {
              "uuid": "json-numbers",
              "player": { "id": 1, "bounded_rank": 20 },
              "preferences": {
                "lower_rank_diff": 0,
                "upper_rank_diff": 1,
                "size_speed_options": [
                  { "size": "9x9", "speed": "rapid", "system": "fischer" }
                ]
              }
            }
            """#.utf8)) as? [String: Any]
        )
        let entry = try XCTUnwrap(
            OGSAutomatchAvailableEntry(availabilityObject)
        )
        XCTAssertEqual(entry.playerID, 1)
        XCTAssertEqual(entry.playerBoundedRank, 20)
        XCTAssertEqual(entry.lowerRankDifference, 0)
        XCTAssertEqual(entry.upperRankDifference, 1)

        let statsObject = try JSONSerialization.jsonObject(with: Data(#"""
        {
          "9x9": {
            "rapid": { "fischer": 1, "byoyomi": 0 },
            "live": { "fischer": true }
          }
        }
        """#.utf8))
        let stats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: statsObject)
        )
        XCTAssertEqual(stats.total(boardSize: 9), 1)
        XCTAssertEqual(stats.realtimeTotal(boardSize: 9), 1)
        XCTAssertEqual(
            stats.count(
                boardSize: 9,
                speed: .rapid,
                system: .fischer
            ),
            1
        )
    }

    func testQuickMatchPopularityUsesOfficialStrictThresholds() throws {
        let boundaryStats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": ["rapid": ["fischer": 33]],
                "13x13": ["rapid": ["fischer": 33]],
                "19x19": ["rapid": ["fischer": 34]],
            ])
        )
        let aboveBoundaryStats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": ["rapid": ["fischer": 331]],
                "13x13": ["rapid": ["fischer": 334]],
                "19x19": ["rapid": ["fischer": 335]],
            ])
        )

        XCTAssertEqual(
            activitySnapshot(popularity: boundaryStats)
                .status(forBoardSize: 9),
            .none
        )
        XCTAssertEqual(
            activitySnapshot(popularity: aboveBoundaryStats)
                .status(forBoardSize: 9),
            .popular
        )

        let clockBoundaryStats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": [
                    "rapid": ["fischer": 2, "byoyomi": 2],
                    "live": ["fischer": 3, "byoyomi": 3],
                ],
            ])
        )
        let clockAboveBoundaryStats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": [
                    "rapid": ["fischer": 3, "byoyomi": 2],
                    "live": ["fischer": 3, "byoyomi": 3],
                ],
            ])
        )

        XCTAssertEqual(
            activitySnapshot(popularity: clockBoundaryStats).status(
                for: .rapid,
                system: .fischer,
                boardSizes: [9]
            ),
            .none
        )
        XCTAssertEqual(
            activitySnapshot(popularity: clockAboveBoundaryStats).status(
                for: .rapid,
                system: .fischer,
                boardSizes: [9]
            ),
            .popular
        )
    }

    func testPopularityRankQueryPreservesTheUsersFractionalRank() {
        XCTAssertEqual(
            OGSQuickMatchPopularityStats.rankQueryParameter(
                userRank: 28.25,
                lowerRankDifference: 2,
                upperRankDifference: 1
            ),
            "26.25,27.25,28.25,29.25"
        )
        XCTAssertNil(
            OGSQuickMatchPopularityStats.rankQueryParameter(
                userRank: 28.25,
                lowerRankDifference: 10,
                upperRankDifference: 1
            )
        )
        XCTAssertEqual(
            OGSQuickMatchPopularityStats.rankQueryParameter(
                userRank: 28,
                lowerRankDifference: 2,
                upperRankDifference: 1
            ),
            "26,27,28,29"
        )
    }

    func testPopularityParserRejectsOverflowingServerTotals() {
        XCTAssertNil(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": [
                    "rapid": [
                        "fischer": Int.max,
                        "byoyomi": 1,
                    ],
                ],
            ])
        )
        XCTAssertNil(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": [
                    "rapid": ["fischer": Int.max],
                    "live": ["byoyomi": 1],
                ],
            ])
        )
        XCTAssertNil(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": ["future-speed": ["future-system": Int.max]],
                "13x13": ["rapid": ["fischer": 1]],
            ])
        )
    }

    func testPopularityParserIsTolerantWithoutChangingDenominators() throws {
        XCTAssertNil(OGSQuickMatchPopularityStats(jsonObject: "future-shape"))
        let empty = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [:])
        )
        XCTAssertEqual(empty.totalAcrossBoardSizes, 0)

        let stats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": [
                    "rapid": [
                        "fischer": 3,
                        "byoyomi": true,
                    ],
                    "future-speed": [
                        "future-system": 100,
                    ],
                    "live": [
                        "fischer": -4,
                        "byoyomi": 2.5,
                    ],
                ],
            ])
        )

        XCTAssertEqual(stats.total(boardSize: 9), 103)
        XCTAssertEqual(stats.realtimeTotal(boardSize: 9), 3)
        XCTAssertEqual(
            stats.count(
                boardSize: 9,
                speed: .rapid,
                system: .fischer
            ),
            3
        )
    }

    func testQuickMatchActivityAppliesMutualRankFilters() throws {
        let cases: [(String, Int?, Double?, Int?, Int?, Bool)] = [
            ("self", 10, 20, 3, 3, false),
            ("lower-inclusive", 11, 17, 3, 3, true),
            ("upper-inclusive", 12, 22, 2, 3, true),
            ("below-range", 13, 16.9, 9, 9, false),
            ("above-range", 14, 22.1, 9, 9, false),
            ("peer-too-narrow-lower", 15, 22, 1, 9, false),
            ("peer-lower-inclusive", 16, 22, 2, 9, true),
            ("peer-too-narrow-upper", 17, 18, 9, 1, false),
            ("peer-upper-inclusive", 18, 18, 9, 2, true),
            ("missing-id", nil, 20, 3, 3, false),
            ("missing-rank", 19, nil, 3, 3, false),
            ("missing-lower", 20, 20, nil, 3, false),
            ("missing-upper", 21, 20, 3, nil, false),
        ]

        for (uuid, playerID, rank, lower, upper, expectedWaiting) in cases {
            let entry = try XCTUnwrap(
                availableEntry(
                    uuid: uuid,
                    playerID: playerID,
                    boundedRank: rank,
                    lowerRankDifference: lower,
                    upperRankDifference: upper
                )
            )
            let snapshot = activitySnapshot(availableEntries: [entry])
            XCTAssertEqual(
                snapshot.status(forBoardSize: 9),
                expectedWaiting ? .playersWaiting : .none,
                uuid
            )
        }
    }

    func testQuickMatchActivityPrecedenceMultipleAndCorrespondence() throws {
        let stats = try XCTUnwrap(
            OGSQuickMatchPopularityStats(jsonObject: [
                "9x9": ["rapid": ["fischer": 1, "byoyomi": 9]],
                "13x13": ["rapid": ["fischer": 1, "byoyomi": 9]],
                "19x19": ["rapid": ["fischer": 8, "byoyomi": 2]],
            ])
        )
        let waitingOn13 = try XCTUnwrap(
            availableEntry(
                uuid: "waiting-13",
                playerID: 11,
                boundedRank: 20,
                lowerRankDifference: 3,
                upperRankDifference: 3,
                options: [[
                    "size": "13x13",
                    "speed": "rapid",
                    "system": "fischer",
                ]]
            )
        )
        let snapshot = activitySnapshot(
            availableEntries: [waitingOn13],
            popularity: stats
        )

        XCTAssertEqual(
            snapshot.status(
                for: .rapid,
                system: .fischer,
                boardSizes: [9, 13]
            ),
            .playersWaiting
        )
        XCTAssertEqual(
            snapshot.status(
                for: .rapid,
                system: .fischer,
                boardSizes: [9]
            ),
            .none
        )
        XCTAssertEqual(
            snapshot.status(
                for: .rapid,
                system: .fischer,
                boardSizes: [19]
            ),
            .popular
        )
        XCTAssertEqual(
            snapshot.status(
                for: .rapid,
                system: .byoyomi,
                boardSizes: [13]
            ),
            .popular
        )
        XCTAssertEqual(
            snapshot.status(
                for: .correspondence,
                system: .fischer,
                boardSizes: [9, 13, 19]
            ),
            .popular
        )
    }

    func testAutomatchAvailabilitySubscriptionReconnectsAndCleansUp() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let payload = availableEntryPayload(
            uuid: "available-live",
            playerID: 11,
            boundedRank: 20,
            lowerRankDifference: 3,
            upperRankDifference: 3
        )

        service.subscribeToAutomatchAvailability()
        XCTAssertEqual(
            socket.emissions.last?.command,
            "automatch/available/subscribe"
        )

        socket.deliver(name: "automatch/available/add", data: payload)
        XCTAssertNotNil(service.automatchAvailableEntryByID["available-live"])
        socket.deliver(
            name: "automatch/available/remove",
            data: "available-live"
        )
        XCTAssertNil(service.automatchAvailableEntryByID["available-live"])

        socket.deliver(name: "automatch/available/add", data: payload)
        socket.dropSocket()
        XCTAssertTrue(service.automatchAvailableEntryByID.isEmpty)
        socket.openSocket(authenticate: true)
        XCTAssertEqual(
            socket.emissions.filter {
                $0.command == "automatch/available/subscribe"
            }.count,
            2
        )

        service.unsubscribeFromAutomatchAvailability()
        XCTAssertEqual(
            socket.emissions.last?.command,
            "automatch/available/unsubscribe"
        )
        socket.deliver(name: "automatch/available/add", data: payload)
        XCTAssertTrue(service.automatchAvailableEntryByID.isEmpty)
    }

    func testGameCountSubscriptionAndUnsubscriptionUseTheGlobalChannel() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)

        service.subscribeToGameCount()
        XCTAssertEqual(
            socket.emissions.last?.command,
            "gamelist/count/subscribe"
        )
        XCTAssertEqual(
            (socket.emissions.last?.data as? [String: String])?["channel"],
            ""
        )

        service.unsubscribeFromGameCount()
        XCTAssertEqual(
            socket.emissions.last?.command,
            "gamelist/count/unsubscribe"
        )
        XCTAssertEqual(
            (socket.emissions.last?.data as? [String: String])?["channel"],
            ""
        )
    }

    func testQuickMatchPopularityRequestLifecycle() throws {
        QuickMatchStatsURLProtocol.reset()
        let monitor = QuickMatchStatsEventMonitor()
        let socket = FakeWebsocket()
        let service = makeService(
            socket: socket,
            urlProtocolClass: QuickMatchStatsURLProtocol.self,
            eventMonitors: [monitor]
        )
        service.subscribeToAutomatchAvailability()

        // These are deadlines, not sleeps: a busy CI runner can take more than
        // two seconds to start a request, while normal completions return early.
        let requestTimeout: TimeInterval = 10
        let normalRanks = "26,27,28,29"
        var publishedTotals = [Int]()
        let updates = service.$quickMatchPopularityStats.dropFirst().sink {
            publishedTotals.append($0.totalAcrossBoardSizes)
        }
        defer { updates.cancel() }

        func waitForRequests(
            _ expectations: [XCTestExpectation],
            file: StaticString = #filePath,
            line: UInt = #line
        ) -> Bool {
            let result = XCTWaiter.wait(for: expectations, timeout: requestTimeout)
            XCTAssertEqual(
                result, .completed,
                "Waiting for: \(expectations.map(\.expectationDescription).joined(separator: ", "))",
                file: file, line: line
            )
            return result == .completed
        }

        func completion(
            _ description: String,
            ranks: String,
            cancelled: Bool = false
        ) -> XCTestExpectation {
            let completed = XCTestExpectation(description: description)
            monitor.observeCompletion(ranks: ranks) { response in
                if cancelled {
                    XCTAssertTrue(response.error?.isExplicitlyCancelledError == true)
                }
                completed.fulfill()
            }
            return completed
        }

        QuickMatchStatsURLProtocol.enqueue(.response(
            statusCode: 200,
            body: Data(#"{"9x9":{"rapid":{"fischer":4}}}"#.utf8)
        ), ranks: normalRanks)
        let validUpdate = completion("valid stats processed", ranks: normalRanks)
        service.refreshQuickMatchPopularityStats(
            userRank: 28,
            lowerRankDifference: 2,
            upperRankDifference: 1
        )
        guard waitForRequests([validUpdate]) else { return }
        XCTAssertEqual(service.quickMatchPopularityStats.totalAcrossBoardSizes, 4)
        XCTAssertEqual(publishedTotals, [4])

        let request = try XCTUnwrap(
            QuickMatchStatsURLProtocol.requestSnapshot().last
        )
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(components.path, "/termination-api/automatch-stats")
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "ranks" }?.value,
            normalRanks
        )

        QuickMatchStatsURLProtocol.enqueue(.response(
            statusCode: 200,
            body: Data("{}".utf8)
        ), ranks: normalRanks)
        let emptyUpdate = completion("valid empty stats processed", ranks: normalRanks)
        service.refreshQuickMatchPopularityStats(
            userRank: 28,
            lowerRankDifference: 2,
            upperRankDifference: 1
        )
        guard waitForRequests([emptyUpdate]) else { return }
        XCTAssertEqual(service.quickMatchPopularityStats, .empty)
        XCTAssertEqual(publishedTotals, [4, 0])

        QuickMatchStatsURLProtocol.enqueue(.response(
            statusCode: 200,
            body: Data(#"{"13x13":{"rapid":{"fischer":7}}}"#.utf8)
        ), ranks: normalRanks)
        let replacementUpdate = completion("replacement stats processed", ranks: normalRanks)
        service.refreshQuickMatchPopularityStats(
            userRank: 28,
            lowerRankDifference: 2,
            upperRankDifference: 1
        )
        guard waitForRequests([replacementUpdate]) else { return }
        XCTAssertEqual(service.quickMatchPopularityStats.totalAcrossBoardSizes, 7)
        XCTAssertEqual(publishedTotals, [4, 0, 7])

        for (description, plan) in [
            ("malformed response processed", QuickMatchStatsURLProtocol.Plan.response(
                statusCode: 200,
                body: Data("[]".utf8)
            )),
            ("failed response processed", .failure(URLError(.timedOut))),
        ] {
            QuickMatchStatsURLProtocol.enqueue(plan, ranks: normalRanks)
            let processed = completion(description, ranks: normalRanks)
            service.refreshQuickMatchPopularityStats(
                userRank: 28,
                lowerRankDifference: 2,
                upperRankDifference: 1
            )
            // Observe publications through the service callback, rather than
            // letting an inverted timeout pass before the response is handled.
            guard waitForRequests([processed]) else { return }
            XCTAssertEqual(publishedTotals, [4, 0, 7])
            XCTAssertEqual(service.quickMatchPopularityStats.totalAcrossBoardSizes, 7)
        }

        let supersededRanks = "19,20,21"
        QuickMatchStatsURLProtocol.enqueue(.hold, ranks: supersededRanks)
        let firstStarted = XCTestExpectation(description: "superseded request started")
        QuickMatchStatsURLProtocol.observeNextRequest(ranks: supersededRanks) {
            firstStarted.fulfill()
        }
        let firstCompleted = completion(
            "superseded cancellation processed", ranks: supersededRanks, cancelled: true
        )
        service.refreshQuickMatchPopularityStats(
            userRank: 20,
            lowerRankDifference: 1,
            upperRankDifference: 1
        )
        guard waitForRequests([firstStarted]) else { return }
        let firstStopped = XCTestExpectation(description: "superseded request stopped")
        QuickMatchStatsURLProtocol.observeNextStop(ranks: supersededRanks) {
            firstStopped.fulfill()
        }

        let supersedingRanks = "20,21,22"
        QuickMatchStatsURLProtocol.enqueue(.response(
            statusCode: 200,
            body: Data(#"{"19x19":{"rapid":{"fischer":9}}}"#.utf8)
        ), ranks: supersedingRanks)
        let supersedingUpdate = completion("newer response processed", ranks: supersedingRanks)
        service.refreshQuickMatchPopularityStats(
            userRank: 21,
            lowerRankDifference: 1,
            upperRankDifference: 1
        )
        // Await both callbacks before checking that the cancelled predecessor
        // cannot overwrite the replacement. URLSession discards responses sent
        // through a URLProtocol after cancellation.
        guard waitForRequests([firstStopped, firstCompleted, supersedingUpdate]) else { return }
        XCTAssertEqual(publishedTotals, [4, 0, 7, 9])
        XCTAssertEqual(service.quickMatchPopularityStats.totalAcrossBoardSizes, 9)

        QuickMatchStatsURLProtocol.enqueue(.hold, ranks: normalRanks)
        let cancellationStarted = XCTestExpectation(description: "request before unsubscribe")
        QuickMatchStatsURLProtocol.observeNextRequest(ranks: normalRanks) {
            cancellationStarted.fulfill()
        }
        let unsubscribeCompleted = completion(
            "unsubscribe cancellation processed", ranks: normalRanks, cancelled: true
        )
        service.refreshQuickMatchPopularityStats(
            userRank: 28,
            lowerRankDifference: 2,
            upperRankDifference: 1
        )
        guard waitForRequests([cancellationStarted]) else { return }
        let unsubscribeCancelled = XCTestExpectation(description: "unsubscribe cancels request")
        QuickMatchStatsURLProtocol.observeNextStop(ranks: normalRanks) {
            unsubscribeCancelled.fulfill()
        }
        service.unsubscribeFromAutomatchAvailability()
        guard waitForRequests([unsubscribeCancelled, unsubscribeCompleted]) else { return }
        XCTAssertEqual(service.quickMatchPopularityStats, .empty)

        service.subscribeToAutomatchAvailability()
        QuickMatchStatsURLProtocol.enqueue(.hold, ranks: normalRanks)
        let accountRequestStarted = XCTestExpectation(description: "request before account switch")
        QuickMatchStatsURLProtocol.observeNextRequest(ranks: normalRanks) {
            accountRequestStarted.fulfill()
        }
        let accountSwitchCompleted = completion(
            "account switch cancellation processed", ranks: normalRanks, cancelled: true
        )
        service.refreshQuickMatchPopularityStats(
            userRank: 28,
            lowerRankDifference: 2,
            upperRankDifference: 1
        )
        guard waitForRequests([accountRequestStarted]) else { return }
        let accountSwitchCancelled = XCTestExpectation(description: "account switch cancels request")
        QuickMatchStatsURLProtocol.observeNextStop(ranks: normalRanks) {
            accountSwitchCancelled.fulfill()
        }
        service.ogsUIConfig = try makeUIConfig(jwt: "new-account", userID: 2)
        guard waitForRequests([accountSwitchCancelled, accountSwitchCompleted]) else { return }
        XCTAssertEqual(service.quickMatchPopularityStats, .empty)
    }

    func testSeekGraphSubscriptionWaitsForAuthenticationAndReconnects() {
        let socket = FakeWebsocket()
        socket.authenticated = false
        let service = makeService(socket: socket)
        service.user = OGSUser(username: "current", id: 1, rank: 25)

        service.subscribeToSeekGraph()
        XCTAssertFalse(
            socket.emissions.contains { $0.command == "seek_graph/connect" }
        )

        socket.markAuthenticated()
        XCTAssertEqual(
            socket.emissions.filter {
                $0.command == "seek_graph/connect"
            }.count,
            1
        )

        service.subscribeToSeekGraph()
        service.unsubscribeFromSeekGraphWhenDone()
        XCTAssertFalse(
            socket.emissions.contains {
                $0.command == "seek_graph/disconnect"
            }
        )

        socket.dropSocket()
        socket.openSocket(authenticate: true)
        XCTAssertEqual(
            socket.emissions.filter {
                $0.command == "seek_graph/connect"
            }.count,
            2
        )
        service.onSeekGraphEvent(data: [])

        service.unsubscribeFromSeekGraphWhenDone()
        XCTAssertEqual(
            socket.emissions.last?.command,
            "seek_graph/disconnect"
        )
    }

    func testSeekGraphReconnectReplacesThePreviousSnapshot() {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        service.user = OGSUser(username: "current", id: 1, rank: 25)

        service.subscribeToSeekGraph()
        service.onSeekGraphEvent(data: [seekGraphChallengePayload(id: 10)])
        XCTAssertNotNil(service.eligibleOpenChallengeById[10])

        socket.dropSocket()
        XCTAssertTrue(service.eligibleOpenChallengeById.isEmpty)

        socket.openSocket(authenticate: true)
        service.onSeekGraphEvent(data: [])
        XCTAssertTrue(service.eligibleOpenChallengeById.isEmpty)
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "seek_graph/connect" }.count,
            2
        )
    }

    func testSeekGraphAccountSwitchClearsAccountOwnedSnapshot() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        service.ogsUIConfig = try makeUIConfig(jwt: "old", userID: 1)
        socket.openSocket(authenticate: true)
        service.user = OGSUser(username: "old", id: 1, rank: 25)
        service.subscribeToSeekGraph()
        service.onSeekGraphEvent(
            data: [seekGraphChallengePayload(id: 11, challengerID: 1)]
        )
        XCTAssertNotNil(service.openChallengeSentById[11])

        service.ogsUIConfig = try makeUIConfig(jwt: "new", userID: 2)

        XCTAssertTrue(service.openChallengeSentById.isEmpty)
        XCTAssertTrue(service.eligibleOpenChallengeById.isEmpty)
        socket.openSocket(authenticate: true)
        XCTAssertEqual(
            socket.emissions.filter { $0.command == "seek_graph/connect" }.count,
            2,
            "The visible screen keeps ownership, but the old account's request does not."
        )
    }

    private func activitySnapshot(
        availableEntries: [OGSAutomatchAvailableEntry] = [],
        popularity: OGSQuickMatchPopularityStats = .empty
    ) -> OGSQuickMatchActivitySnapshot {
        OGSQuickMatchActivitySnapshot(
            availableEntries: availableEntries,
            popularity: popularity,
            currentUserID: 10,
            currentRank: 20,
            lowerRankDifference: 3,
            upperRankDifference: 2
        )
    }

    private func availableEntry(
        uuid: String,
        playerID: Int?,
        boundedRank: Double?,
        lowerRankDifference: Int?,
        upperRankDifference: Int?,
        options: [[String: Any]] = [[
            "size": "9x9",
            "speed": "rapid",
            "system": "fischer",
        ]]
    ) -> OGSAutomatchAvailableEntry? {
        OGSAutomatchAvailableEntry(
            availableEntryPayload(
                uuid: uuid,
                playerID: playerID,
                boundedRank: boundedRank,
                lowerRankDifference: lowerRankDifference,
                upperRankDifference: upperRankDifference,
                options: options
            )
        )
    }

    private func availableEntryPayload(
        uuid: String,
        playerID: Int?,
        boundedRank: Double?,
        lowerRankDifference: Int?,
        upperRankDifference: Int?,
        options: [[String: Any]] = [[
            "size": "9x9",
            "speed": "rapid",
            "system": "fischer",
        ]]
    ) -> [String: Any] {
        var player = [String: Any]()
        if let playerID { player["id"] = playerID }
        if let boundedRank { player["bounded_rank"] = boundedRank }
        var preferences: [String: Any] = [
            "size_speed_options": options,
        ]
        if let lowerRankDifference {
            preferences["lower_rank_diff"] = lowerRankDifference
        }
        if let upperRankDifference {
            preferences["upper_rank_diff"] = upperRankDifference
        }
        return [
            "uuid": uuid,
            "player": player,
            "preferences": preferences,
        ]
    }

    private func seekGraphChallengePayload(
        id: Int,
        challengerID: Int = 2
    ) -> [String: Any] {
        [
            "challenge_id": id,
            "user_id": challengerID,
            "username": "player-\(challengerID)",
            "rank": 25.0,
            "min_rank": 5,
            "max_rank": 38,
            "game_id": id + 1_000,
            "name": "Event test",
            "ranked": false,
            "handicap": 0,
            "komi": NSNull(),
            "rules": "japanese",
            "width": 9,
            "height": 9,
            "challenger_color": "black",
            "disable_analysis": false,
            "time_control_parameters": [
                "per_move": 20,
                "pause_on_weekends": false,
                "speed": "live",
                "system": "simple",
                "time_control": "simple",
            ],
            "rengo": false,
            "rengo_nominees": [],
            "rengo_black_team": [],
            "rengo_white_team": [],
            "rengo_participants": [],
            "rengo_casual_mode": false,
            "rengo_auto_start": 0,
        ]
    }

    private func makeService(
        socket: OGSWebsocketProtocol,
        cachedUsers: [OGSUser] = [],
        urlProtocolClass: AnyClass = RejectingURLProtocol.self,
        eventMonitors: [EventMonitor] = [],
        installsObservers: Bool = false,
        gameResynchronizationTimeout: TimeInterval = 15,
        conditionalMoveSubmissionTimeout: TimeInterval = 10,
        automatchReconciliationTimeout: TimeInterval = 5,
        automatchConfirmationTimeout: TimeInterval = 8,
        currentTime: TimeInterval = 2_000_000_000
    ) -> OGSService {
        preferenceSuite = "com.honganhkhoa.Surround.EventTests.\(UUID().uuidString)"
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [urlProtocolClass]
        configuration.httpCookieStorage = nil
        let httpClient = AlamofireOGSHTTPClient(
            session: Session(configuration: configuration, eventMonitors: eventMonitors),
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
            automatchReconciliationTimeout: automatchReconciliationTimeout,
            automatchConfirmationTimeout: automatchConfirmationTimeout,
            currentTime: { currentTime },
            initialState: initialState
        )
    }

    private func inboundAutomatchPayload(
        _ entry: OGSAutomatchEntry,
        creationTimestamp: TimeInterval
    ) -> [String: Any] {
        var payload = entry.jsonObject
        payload["timestamp"] = creationTimestamp * 1_000
        return payload
    }

    private func jsonDictionary(_ source: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(source.utf8))
                as? [String: Any]
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

    private func makeShortGameData(
        id: Int,
        phase: String,
        timePerMove: Int? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "phase": phase,
            "width": 5,
            "height": 5,
            "black": ["id": 1, "username": "black"],
            "white": ["id": 2, "username": "white"],
        ]
        if let timePerMove {
            result["time_per_move"] = timePerMove
        }
        return result
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
