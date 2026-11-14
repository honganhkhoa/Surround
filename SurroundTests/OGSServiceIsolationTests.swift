//
//  OGSServiceIsolationTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import XCTest

final class OGSServiceIsolationTests: XCTestCase {
    private final class StubWebsocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks = [() -> Void]()
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = false
        var opened = false
        var status = OGSWebsocketStatus.disconnected
        var drift = 0.0
        var latency = 0.0
        /// The account the socket authenticated as; tests set it.
        var authenticatedUserID: Int?
        private(set) var reconnectCount = 0
        private(set) var emittedCommands = [String]()
        /// Each emitted command's `player_id`, beside `emittedCommands`.
        private(set) var emittedPlayerIDs = [Int?]()
        /// Runs as each command leaves, with its `player_id`.
        var onEmit: ((String, Int?) -> Void)?
        var nextCallbackError: [String: String]?
        var defersPrivateMessageAcknowledgements = false
        private(set) var privateMessageCallbacks = [OGSWebsocketResultCallback]()

        /// The peers whose conversations OGS was asked to replay, in order.
        var loadedConversations: [Int] {
            zip(emittedCommands, emittedPlayerIDs).compactMap { command, playerID in
                command == "chat/pm/load" ? playerID : nil
            }
        }

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() { reconnectCount += 1 }

        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            let playerID = (data as? [String: Any])?["player_id"] as? Int
            emittedCommands.append(command)
            emittedPlayerIDs.append(playerID)
            onEmit?(command, playerID)
            if command == "chat/pm", defersPrivateMessageAcknowledgements, let resultCallback {
                privateMessageCallbacks.append(resultCallback)
                return
            }
            resultCallback?(nil, nextCallbackError)
            nextCallbackError = nil
        }

        func resetEmittedCommands() {
            emittedCommands.removeAll()
            emittedPlayerIDs.removeAll()
        }

        func acknowledgeNextPrivateMessage(with data: [String: Any]) {
            let callback = privateMessageCallbacks.removeFirst()
            callback(data, nil)
        }
    }

    /// Runs a superchat store's re-send deadlines only when the test advances it.
    private final class ManualScheduler: OGSWebsocketScheduling {
        private final class Cancellation: Cancellable {
            private var handler: (() -> Void)?
            init(_ handler: @escaping () -> Void) { self.handler = handler }
            func cancel() {
                handler?()
                handler = nil
            }
        }

        private var nextID = 0
        private var work = [Int: (delay: TimeInterval, block: () -> Void)]()

        /// The delays of the deadlines still to come.
        var pendingDelays: [TimeInterval] { work.values.map { $0.delay } }

        func async(_ block: @escaping () -> Void) { block() }

        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            nextID += 1
            let id = nextID
            work[id] = (delay, block)
            return Cancellation { [weak self] in self?.work.removeValue(forKey: id) }
        }

        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            preconditionFailure("The store schedules one deadline at a time.")
        }

        /// Runs every pending deadline, as if the re-send window passed.
        /// Work that an earlier one cancels doesn't run.
        func advance() {
            for id in work.keys.sorted() {
                guard let due = work.removeValue(forKey: id) else { continue }
                due.block()
            }
        }
    }

    private final class StubURLProtocol: URLProtocol {
        static let lock = NSLock()
        static var requests = [URLRequest]()
        static var cookieStorageByUsername = [String: HTTPCookieStorage]()
        static var rejectedUsernames = Set<String>()
        static var gameDetailBody: Data?
        static var gameDetailBodies = [Int: Data]()
        static var gameDetailGate: DispatchSemaphore?
        static var gameDetailStarted: (() -> Void)?
        static var gameDetailStopped: (() -> Void)?
        static var gameDetailReleased: (() -> Void)?
        static var gameHistoryBody: Data?

        private let deliveryLock = NSRecursiveLock()
        private var isStopped = false
        private var hasFinishedLoading = false
        private var gameDetailStop: (() -> Void)?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            Self.lock.unlock()

            let path = request.url?.path ?? ""
            let body: Data
            var headers = [String: String]()
            var statusCode = 200
            var responseGate: DispatchSemaphore?
            var responseStarted: (() -> Void)?
            var responseReleased: (() -> Void)?

            switch path {
            case "/api/v0/login":
                let username = request.value(forHTTPHeaderField: "X-Surround-Test-Username") ?? "unknown"
                Self.lock.lock()
                let cookieStorage = Self.cookieStorageByUsername[username]
                let isRejected = Self.rejectedUsernames.contains(username)
                Self.lock.unlock()
                if isRejected {
                    statusCode = 401
                    body = Data(#"{"error":"invalid credentials"}"#.utf8)
                } else {
                    let userID = username == "player-one" ? 101 : 202
                    body = Data(#"{"csrf_token":"csrf-\#(username)","user_jwt":"jwt-\#(username)","user":{"username":"\#(username)","id":\#(userID),"anonymous":false}}"#.utf8)
                    headers["Set-Cookie"] = "sessionid=session-\(username); Path=/; Secure"
                    if let cookie = HTTPCookie(properties: [
                        .name: "sessionid",
                        .value: "session-\(username)",
                        .domain: request.url?.host ?? "ogs.test",
                        .path: "/",
                        .secure: "TRUE"
                    ]) {
                        // Custom URL protocols bypass URLSession's normal cookie
                        // persistence, so reproduce that platform behavior here.
                        cookieStorage?.setCookie(cookie)
                    }
                }
            case "/api/v1/ui/friends":
                body = Data(#"{"friends":[]}"#.utf8)
            case "/api/v1/ui/overview":
                body = Data("{}".utf8)
            case _ where path.hasPrefix("/api/v1/players/")
                && path.hasSuffix("/game_history"):
                Self.lock.lock()
                body = Self.gameHistoryBody ?? Data("{}".utf8)
                Self.lock.unlock()
            case _ where path.hasPrefix("/api/v1/games/"):
                Self.lock.lock()
                let gameID = Int(path.split(separator: "/").last ?? "")
                body = gameID.flatMap { Self.gameDetailBodies[$0] }
                    ?? Self.gameDetailBody ?? Data("{}".utf8)
                responseGate = Self.gameDetailGate
                responseStarted = Self.gameDetailStarted
                responseReleased = Self.gameDetailReleased
                deliveryLock.lock()
                gameDetailStop = Self.gameDetailStopped
                deliveryLock.unlock()
                Self.lock.unlock()
            default:
                body = Data("{}".utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            responseStarted?()
            if let responseGate {
                // Keep the URL loading thread free to deliver stopLoading().
                // A bounded wait also prevents a failed test from leaking a worker.
                let released = responseReleased
                DispatchQueue.global(qos: .userInitiated).async {
                    if responseGate.wait(timeout: .now() + 10) == .success {
                        self.deliver(response: response, body: body)
                    } else {
                        self.deliveryLock.lock()
                        if !self.isStopped {
                            self.hasFinishedLoading = true
                            self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                        }
                        self.deliveryLock.unlock()
                    }
                    released?()
                }
            } else {
                deliver(response: response, body: body)
            }
        }

        private func deliver(response: HTTPURLResponse, body: Data) {
            deliveryLock.lock()
            defer { deliveryLock.unlock() }
            guard !isStopped else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            hasFinishedLoading = true
        }

        override func stopLoading() {
            deliveryLock.lock()
            let stopped = !isStopped && !hasFinishedLoading ? gameDetailStop : nil
            isStopped = true
            deliveryLock.unlock()
            stopped?()
        }

        static func recordedRequests(forPath path: String) -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests.filter { $0.url?.path == path }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var preferenceSuites = [String]()

    override func setUp() {
        super.setUp()
        StubURLProtocol.lock.lock()
        StubURLProtocol.requests = []
        StubURLProtocol.cookieStorageByUsername = [:]
        StubURLProtocol.rejectedUsernames = []
        StubURLProtocol.gameDetailBody = nil
        StubURLProtocol.gameDetailBodies = [:]
        StubURLProtocol.gameDetailGate = nil
        StubURLProtocol.gameDetailStarted = nil
        StubURLProtocol.gameDetailStopped = nil
        StubURLProtocol.gameDetailReleased = nil
        StubURLProtocol.gameHistoryBody = nil
        StubURLProtocol.lock.unlock()
    }
    override func tearDown() {
        cancellables.removeAll()
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    func testEnvironmentDerivesMatchingWebSocketOrigins() {
        XCTAssertEqual(OGSEnvironment.production.rootURL.absoluteString, "https://online-go.com")
        XCTAssertEqual(OGSEnvironment.production.websocketURL.absoluteString, "wss://online-go.com")
        XCTAssertEqual(OGSEnvironment.beta.rootURL.absoluteString, "https://beta.online-go.com")
        XCTAssertEqual(OGSEnvironment.beta.websocketURL.absoluteString, "wss://beta.online-go.com")

        let local = OGSEnvironment(rootURL: URL(string: "http://127.0.0.1:8080")!)
        XCTAssertEqual(local.websocketURL.absoluteString, "ws://127.0.0.1:8080")
    }

    func testGetGameDetailDoesNotCreateWebSocketIntent() throws {
        let gameID = 48
        _ = try installGameDetailResponse(gameID: gameID)

        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "game-detail"
        )
        let completed = expectation(description: "game detail fetched")
        var receivedGame: Game?
        var receivedError: Error?

        service.getGameDetail(gameID: gameID)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 {
                        receivedError = error
                    }
                    completed.fulfill()
                },
                receiveValue: { receivedGame = $0 }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 5)
        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedGame?.ogsID, gameID)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
        XCTAssertEqual(socket.reconnectCount, 0)
    }

    func testGameDetailResponseFromPreviousAuthenticationContextIsDiscarded() throws {
        let gameID = 50
        let ogsGame = try installGameDetailResponse(gameID: gameID)
        let responseGate = DispatchSemaphore(value: 0)
        let requestStarted = expectation(description: "old-account game detail request started")

        StubURLProtocol.lock.lock()
        StubURLProtocol.gameDetailGate = responseGate
        StubURLProtocol.gameDetailStarted = { requestStarted.fulfill() }
        StubURLProtocol.lock.unlock()

        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "stale-game-detail"
        )
        let completed = expectation(description: "old-account response discarded")
        var receivedGame: Game?
        var receivedError: Error?

        service.getGameDetail(gameID: gameID)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 {
                        receivedError = error
                    }
                    completed.fulfill()
                },
                receiveValue: { receivedGame = $0 }
            )
            .store(in: &cancellables)

        wait(for: [requestStarted], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(jwt: "new-account-jwt", userID: 2)

        let newAccountGame = Game(ogsGame: ogsGame)
        newAccountGame.ogs = service
        service.connect(to: newAccountGame, owner: .explicit(UUID()))
        socket.resetEmittedCommands()

        responseGate.signal()
        wait(for: [completed], timeout: 5)

        XCTAssertNotNil(receivedError)
        XCTAssertNil(receivedGame)
        XCTAssertNil(newAccountGame.ogsRawData)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
    }

    func testFinishedGameDataFromPreviousAuthenticationContextIsNotDeliveredOrCached() throws {
        let gameID = 51
        _ = try installGameDetailResponse(gameID: gameID)
        FinishedGameCache.shared.clear()
        let responseGate = DispatchSemaphore(value: 0)
        let requestStarted = expectation(description: "old-account finished detail request started")

        StubURLProtocol.lock.lock()
        StubURLProtocol.gameDetailGate = responseGate
        StubURLProtocol.gameDetailStarted = { requestStarted.fulfill() }
        StubURLProtocol.lock.unlock()

        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "stale-finished-detail"
        )
        let completed = expectation(description: "old-account finished detail discarded")
        var receivedDetail: FinishedGameDetail?
        var receivedError: Error?

        service.loadFinishedGameData(gameID: gameID)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 {
                        receivedError = error
                    }
                    completed.fulfill()
                },
                receiveValue: { receivedDetail = $0 }
            )
            .store(in: &cancellables)

        wait(for: [requestStarted], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(jwt: "new-account-jwt", userID: 2)
        responseGate.signal()
        wait(for: [completed], timeout: 5)

        XCTAssertNotNil(receivedError)
        XCTAssertNil(receivedDetail)
        XCTAssertNil(FinishedGameCache.shared.data(forGameID: gameID))
    }

    func testGetGameDetailReusesCanonicalConnectedGame() throws {
        let gameID = 49
        let ogsGame = try installGameDetailResponse(gameID: gameID)
        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "canonical-game-detail"
        )
        let canonicalGame = Game(ogsGame: ogsGame)
        canonicalGame.ogs = service
        service.connect(to: canonicalGame, owner: .explicit(UUID()))
        socket.resetEmittedCommands()

        let completed = expectation(description: "canonical game detail fetched")
        var receivedGame: Game?
        service.getGameDetail(gameID: gameID)
            .sink(
                receiveCompletion: { _ in completed.fulfill() },
                receiveValue: { receivedGame = $0 }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 5)
        XCTAssertTrue(receivedGame === canonicalGame)
        XCTAssertNotNil(canonicalGame.ogsRawData)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
    }

    @MainActor
    func testCancelledGameDetailTaskStopsTransportWithoutLateModelMutation() async throws {
        let gameID = 845_011
        let ogsGame = try installGameDetailResponse(gameID: gameID)
        FinishedGameCache.shared.clear()
        defer { FinishedGameCache.shared.clear() }
        let responseGate = DispatchSemaphore(value: 0)
        defer { responseGate.signal() }
        let requestStarted = expectation(description: "linked-game transport started")
        let requestStopped = expectation(description: "Back cancels linked-game transport")
        let responseReleased = expectation(description: "delayed response released after Back")
        StubURLProtocol.lock.withLock {
            StubURLProtocol.gameDetailGate = responseGate
            StubURLProtocol.gameDetailStarted = { requestStarted.fulfill() }
            StubURLProtocol.gameDetailStopped = { requestStopped.fulfill() }
            StubURLProtocol.gameDetailReleased = { responseReleased.fulfill() }
        }

        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "cancelled-linked-game"
        )
        let canonicalGame = Game(ogsGame: ogsGame)
        canonicalGame.ogs = service
        service.connect(to: canonicalGame, owner: .explicit(UUID()))
        socket.resetEmittedCommands()
        let lateModelMutation = expectation(description: "cancelled response must not enrich the canonical game")
        lateModelMutation.isInverted = true
        canonicalGame.$ogsRawData.dropFirst().sink { _ in lateModelMutation.fulfill() }
            .store(in: &cancellables)

        let router = StackRouter()
        router.present(.playerAbout(101))
        router.present(.game(gameID))
        let taskFinished = expectation(description: "linked-game task cancelled")
        let task = Task { @MainActor in
            defer { taskFinished.fulfill() }
            do {
                for try await game in service.getGameDetail(gameID: gameID).values {
                    try Task.checkCancellation()
                    router.updateGame(game, for: gameID)
                    return
                }
            } catch {
                if !Task.isCancelled { XCTFail("Unexpected game-detail error: \(error)") }
            }
        }
        defer { task.cancel() }

        await fulfillment(of: [requestStarted], timeout: 5)
        router.remove(.game(gameID))
        task.cancel()
        await fulfillment(of: [requestStopped, taskFinished], timeout: 5)
        responseGate.signal()
        await fulfillment(of: [responseReleased], timeout: 5)
        await fulfillment(of: [lateModelMutation], timeout: 0.25)

        XCTAssertEqual(router.path, [.playerAbout(101)])
        XCTAssertTrue(router.games.isEmpty)
        XCTAssertTrue(service.knownProfileGame(gameID: gameID) === canonicalGame)
        XCTAssertNil(canonicalGame.ogsRawData)
        XCTAssertNil(FinishedGameCache.shared.data(forGameID: gameID))
        XCTAssertTrue(socket.emittedCommands.isEmpty)
    }

    @MainActor
    func testCancellingOneGameDetailSubscriberDoesNotCancelAnother() async throws {
        let gameID = 845_012
        _ = try installGameDetailResponse(gameID: gameID)
        let responseGate = DispatchSemaphore(value: 0)
        defer {
            responseGate.signal()
            responseGate.signal()
        }
        let requestsStarted = expectation(description: "each subscriber owns its game-detail transport")
        requestsStarted.expectedFulfillmentCount = 2
        let firstRequestStopped = expectation(description: "first subscriber cancels only its transport")
        let responsesReleased = expectation(description: "both delayed workers released")
        responsesReleased.expectedFulfillmentCount = 2
        StubURLProtocol.lock.withLock {
            StubURLProtocol.gameDetailGate = responseGate
            StubURLProtocol.gameDetailStarted = { requestsStarted.fulfill() }
            StubURLProtocol.gameDetailStopped = { firstRequestStopped.fulfill() }
            StubURLProtocol.gameDetailReleased = { responsesReleased.fulfill() }
        }

        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "independent-game-detail-subscribers"
        )
        let publisher = service.getGameDetail(gameID: gameID)
        let cancelledDelivery = expectation(description: "cancelled subscriber has no delivery")
        cancelledDelivery.isInverted = true
        let first = publisher.sink(
            receiveCompletion: { _ in cancelledDelivery.fulfill() },
            receiveValue: { _ in cancelledDelivery.fulfill() }
        )
        defer { first.cancel() }
        let secondCompleted = expectation(description: "second subscriber completes normally")
        var receivedGame: Game?
        var receivedError: Error?
        publisher.sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                secondCompleted.fulfill()
            },
            receiveValue: { receivedGame = $0 }
        ).store(in: &cancellables)

        await fulfillment(of: [requestsStarted], timeout: 5)
        first.cancel()
        await fulfillment(of: [firstRequestStopped], timeout: 5)
        responseGate.signal()
        responseGate.signal()
        await fulfillment(of: [secondCompleted, responsesReleased], timeout: 5)
        await fulfillment(of: [cancelledDelivery], timeout: 0.25)

        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedGame?.ogsID, gameID)
        XCTAssertEqual(StubURLProtocol.recordedRequests(forPath: "/api/v1/games/\(gameID)").count, 2)
    }

    func testProfileActiveGamesReuseConnectedModelsWithoutConnectionOwnership() throws {
        var gameData = try makeFinishedGameDetail(gameID: 50).ogsGame
        gameData.phase = .play
        gameData.outcome = nil
        gameData.winner = nil
        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "canonical-profile-active-game"
        )
        let game = Game(ogsGame: gameData)
        game.ogs = service
        let owner = OGSService.GameConnectionOwner.explicit(UUID())
        service.connect(to: game, owner: owner)
        socket.resetEmittedCommands()
        let profile = OGSPlayerProfile(
            user: gameData.players.black,
            activeGames: [.init(gameData: gameData)]
        )

        let store = try XCTUnwrap(service.profileActiveGames(from: profile))
        XCTAssertTrue(store.resolvedGames.isEmpty)
        XCTAssertTrue(store.game(for: try XCTUnwrap(store.entries.first)) === game)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
        game.gamePhase = .finished
        store.refreshMembership()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.resolvedGames.isEmpty)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
        service.disconnect(from: game, owner: owner)
        XCTAssertTrue(socket.emittedCommands.contains("game/disconnect"),
                      "The profile must not retain its own connection owner")
    }

    func testProfileActiveGamesHydrateCanonicalSummaryWithoutReplacingLiveDetail() throws {
        var gameData = try makeFinishedGameDetail(gameID: 51).ogsGame
        gameData.phase = .play
        gameData.outcome = nil
        gameData.winner = nil
        let socket = StubWebsocket()
        socket.opened = true
        socket.authenticated = true
        socket.status = .connected
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "hydrate-canonical-profile-summary"
        )
        let game = Game(
            width: gameData.width, height: gameData.height,
            blackName: gameData.players.black.username,
            whiteName: gameData.players.white.username,
            gameId: .OGS(gameData.gameId)
        )
        game.blackPlayer = gameData.players.black
        game.whitePlayer = gameData.players.white
        game.ogs = service
        let owner = OGSService.GameConnectionOwner.explicit(UUID())
        service.connect(to: game, owner: owner)
        socket.resetEmittedCommands()
        let profile = OGSPlayerProfile(
            user: gameData.players.black,
            activeGames: [.init(gameData: gameData)]
        )

        let store = try XCTUnwrap(service.profileActiveGames(from: profile))
        XCTAssertTrue(store.resolvedGames.isEmpty)
        XCTAssertNil(game.gameData, "Initial counting must not hydrate canonical summaries")
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(store.game(for: entry) === game)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, gameData.moves.count)
        XCTAssertNotNil(game.gameData)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
        var fresherData = gameData
        fresherData.gameName = "Fresher live detail"
        game.gameData = fresherData
        XCTAssertTrue(store.game(for: entry) === game)
        XCTAssertEqual(game.gameData?.gameName, "Fresher live detail")
        XCTAssertTrue(socket.emittedCommands.isEmpty)

        // A phase event can arrive before detail. Its finished state must not
        // be overwritten by an older playing snapshot from the profile.
        game.gameData = nil
        game.gamePhase = .finished
        store.refreshMembership()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.resolvedGames.isEmpty)
        XCTAssertEqual(service.profileActiveGames(from: profile)?.entries.count, 0)
        XCTAssertNil(game.gameData)
        service.disconnect(from: game, owner: owner)
        XCTAssertTrue(socket.emittedCommands.contains("game/disconnect"))
    }

    func testFinishedGamesUseOfficialHistoryEndpointAndReuseExistingModels() throws {
        let response = try JSONSerialization.data(withJSONObject: [
            "count": 3,
            "next": "https://ogs.test/api/v1/players/101/game_history/?page=3",
            "previous": NSNull(),
            "results": [
                makeHistoryResult(id: 61, blackID: 101, whiteID: 201),
                makeHistoryResult(id: 60, blackID: 202, whiteID: 101),
            ],
        ])
        StubURLProtocol.lock.lock()
        StubURLProtocol.gameHistoryBody = response
        StubURLProtocol.lock.unlock()

        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "game-history"
        )
        let existing = Game(
            width: 9,
            height: 9,
            blackName: "existing-black",
            whiteName: "existing-white",
            gameId: .OGS(61)
        )
        existing.ogs = service
        let completed = expectation(description: "history page fetched")
        var receivedGames = [Game]()
        var hasNextPage = false
        var receivedError: Error?

        service.fetchFinishedGames(
            playerId: 101,
            page: 2,
            pageSize: 25,
            reusing: [61: existing]
        )
        .sink(
            receiveCompletion: {
                if case .failure(let error) = $0 {
                    receivedError = error
                }
                completed.fulfill()
            },
            receiveValue: {
                receivedGames = $0.games
                hasNextPage = $0.hasNextPage
            }
        )
        .store(in: &cancellables)

        wait(for: [completed], timeout: 5)
        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedGames.compactMap(\.ogsID), [61, 60])
        XCTAssertTrue(receivedGames.first === existing)
        XCTAssertTrue(hasNextPage)

        StubURLProtocol.lock.lock()
        let requests = StubURLProtocol.requests
        StubURLProtocol.lock.unlock()
        let request = try XCTUnwrap(requests.last)
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(request.url?.path, "/api/v1/players/101/game_history")
        XCTAssertEqual(query["ordering"], "-ended")
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["page_size"], "25")
        XCTAssertEqual(query["bot_game"], "false")
        XCTAssertNil(query["ended__isnull"])
    }

    func testHistoryListingSurvivesIndependentPreviewFailures() throws {
        let gameIDs = [761, 762, 763]
        FinishedGameCache.shared.clear()
        defer { FinishedGameCache.shared.clear() }
        let results = gameIDs.enumerated().map { index, gameID in
            var result = makeHistoryResult(id: gameID, blackID: 101, whiteID: 201)
            result["outcome"] = "Resignation"
            result["black_lost"] = index == 2
            result["white_lost"] = index != 2
            return result
        }
        let historyBody = try JSONSerialization.data(withJSONObject: [
            "results": results, "next": "https://ogs.test/next", "count": 4,
        ])
        let detailBodies = try Dictionary(uniqueKeysWithValues: [761, 763].map { gameID in
            (gameID, try JSONSerialization.data(withJSONObject: makeFinishedGameDetail(gameID: gameID).rawData))
        })
        let gate = DispatchSemaphore(value: 0)
        let detailsStarted = expectation(description: "three preview requests started")
        detailsStarted.expectedFulfillmentCount = 3
        StubURLProtocol.lock.lock()
        StubURLProtocol.gameHistoryBody = historyBody
        StubURLProtocol.gameDetailBodies = detailBodies.merging(
            [762: Data(#"{"gamedata":{}}"#.utf8)], uniquingKeysWith: { first, _ in first }
        )
        StubURLProtocol.gameDetailGate = gate
        StubURLProtocol.gameDetailStarted = { detailsStarted.fulfill() }
        StubURLProtocol.lock.unlock()

        let socket = StubWebsocket()
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket, label: "independent-history-previews"
        )
        let listingCompleted = expectation(description: "listing available before any preview")
        var games = [Game]()
        var hasNextPage = false
        var listingError: Error?
        service.fetchFinishedGames(playerId: 101, page: 1, pageSize: 3)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion { listingError = error }
                listingCompleted.fulfill()
            }, receiveValue: { page in
                games = page.games
                hasNextPage = page.hasNextPage
            })
            .store(in: &cancellables)
        wait(for: [listingCompleted], timeout: 5)
        XCTAssertNil(listingError)
        XCTAssertTrue(hasNextPage)
        XCTAssertEqual(games.compactMap(\.ogsID), gameIDs)
        XCTAssertEqual(games.map { $0.historySummary?.result(for: 101) }, [.win, .win, .loss])
        XCTAssertTrue(games.allSatisfy { $0.gameData == nil && $0.finishedHistoryPosition == nil })
        StubURLProtocol.lock.lock()
        let detailRequestsBeforeLoading = StubURLProtocol.requests.filter {
            $0.url?.path.hasPrefix("/api/v1/games/") == true
        }
        StubURLProtocol.lock.unlock()
        XCTAssertTrue(detailRequestsBeforeLoading.isEmpty)

        let previewsCompleted = expectation(description: "each preview reaches its own result")
        previewsCompleted.expectedFulfillmentCount = games.count
        for game in games {
            game.$historyDetailState
                .filter { $0 == .ready || $0 == .unavailable }
                .prefix(1)
                .sink { _ in previewsCompleted.fulfill() }
                .store(in: &cancellables)
        }
        let loader = FinishedGamePreviewLoader()
        defer { loader.cancel() }
        loader.load(games: games, using: service)
        wait(for: [detailsStarted], timeout: 5)
        XCTAssertEqual(games.map(\.historyDetailState), [.loading, .loading, .loading])
        for _ in gameIDs { gate.signal() }
        wait(for: [previewsCompleted], timeout: 5)

        XCTAssertEqual(games.compactMap(\.ogsID), gameIDs)
        XCTAssertEqual(games.map(\.historyDetailState), [.ready, .unavailable, .ready])
        XCTAssertEqual(games.map { $0.historySummary?.result(for: 101) }, [.win, .win, .loss])
        XCTAssertNotNil(games[0].finishedHistoryPosition)
        XCTAssertNil(games[1].finishedHistoryPosition)
        XCTAssertNotNil(games[2].finishedHistoryPosition)
        XCTAssertTrue(socket.emittedCommands.isEmpty)
    }

    func testCancellingFinishedPreviewStopsTransportAndPreservesSummary() throws {
        let gameID = 764
        FinishedGameCache.shared.clear()
        defer { FinishedGameCache.shared.clear() }
        _ = try installGameDetailResponse(gameID: gameID)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let started = expectation(description: "preview HTTP started")
        let stopped = expectation(description: "preview HTTP cancelled")
        let released = expectation(description: "delayed cancelled response released")
        StubURLProtocol.lock.withLock {
            StubURLProtocol.gameDetailGate = gate
            StubURLProtocol.gameDetailStarted = { started.fulfill() }
            StubURLProtocol.gameDetailStopped = { stopped.fulfill() }
            StubURLProtocol.gameDetailReleased = { released.fulfill() }
        }
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "cancelled-history-preview"
        )
        let game = makeHistoryGame(id: gameID)
        let summary = FinishedGameSummary(
            gameID: gameID, blackPlayerID: 101, whitePlayerID: 201, width: 9, height: 9,
            outcome: "Resignation", blackLost: false, whiteLost: true
        )
        game.historySummary = summary
        let loader = FinishedGamePreviewLoader()
        loader.load(games: [game], using: service)
        wait(for: [started], timeout: 5)
        loader.cancel()
        wait(for: [stopped], timeout: 5)
        gate.signal()
        wait(for: [released], timeout: 5)
        XCTAssertEqual(game.historyDetailState, .notRequested)
        XCTAssertEqual(game.historySummary, summary)
        XCTAssertNil(game.finishedHistoryPosition)
        XCTAssertNil(game.gameData)
        XCTAssertNil(FinishedGameCache.shared.data(forGameID: gameID))
    }

    func testHydratedFinishedGamesSurviveSameUserJWTRotation() throws {
        let gameID = 62
        FinishedGameCache.shared.clear()
        defer { FinishedGameCache.shared.clear() }
        _ = try installGameDetailResponse(gameID: gameID)
        let response = try JSONSerialization.data(withJSONObject: [
            "count": 1,
            "next": NSNull(),
            "previous": NSNull(),
            "results": [
                makeHistoryResult(id: gameID, blackID: 101, whiteID: 201),
            ],
        ])
        let responseGate = DispatchSemaphore(value: 0)
        let requestStarted = expectation(description: "history detail request started")

        StubURLProtocol.lock.lock()
        StubURLProtocol.gameHistoryBody = response
        StubURLProtocol.gameDetailGate = responseGate
        StubURLProtocol.gameDetailStarted = { requestStarted.fulfill() }
        StubURLProtocol.lock.unlock()

        let socket = StubWebsocket()
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "unused"),
            socket: socket,
            label: "same-user-jwt-history"
        )
        service.ogsUIConfig = try makeUIConfig(jwt: "old-test-jwt", userID: 101)
        let reconnectCountBeforeRotation = socket.reconnectCount
        let completed = expectation(description: "hydrated history delivered")
        var receivedGames = [Game]()
        var receivedError: Error?

        service.fetchHydratedFinishedGames(
            playerId: 101,
            page: 1,
            pageSize: 10
        )
        .sink(
            receiveCompletion: {
                if case .failure(let error) = $0 {
                    receivedError = error
                }
                completed.fulfill()
            },
            receiveValue: { receivedGames = $0.games }
        )
        .store(in: &cancellables)

        wait(for: [requestStarted], timeout: 5)
        service.ogsUIConfig = try makeUIConfig(jwt: "new-test-jwt", userID: 101)
        responseGate.signal()
        wait(for: [completed], timeout: 5)

        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedGames.compactMap(\.ogsID), [gameID])
        XCTAssertEqual(receivedGames.first?.gameData?.gameId, gameID)
        XCTAssertEqual(socket.reconnectCount, reconnectCountBeforeRotation)
    }

    func testFinishedGameDetailLoadingIsBoundedAtomicAndOrdered() throws {
        let gameIDs = [701, 702, 703, 704]
        let games = gameIDs.map(makeHistoryGame(id:))
        let subjects = Dictionary(
            uniqueKeysWithValues: gameIDs.map {
                ($0, PassthroughSubject<FinishedGameDetail, Error>())
            }
        )
        var requestedGameIDs = [Int]()
        var activeRequestCount = 0
        var peakRequestCount = 0
        var loadedGames: [(game: Game, detail: FinishedGameDetail?)]?
        var receivedError: Error?
        let completed = expectation(description: "all detail loaded")

        OGSService.loadingFinishedGameDetails(
            for: games,
            maximumConcurrentRequests: 2
        ) { gameID in
            requestedGameIDs.append(gameID)
            activeRequestCount += 1
            peakRequestCount = max(peakRequestCount, activeRequestCount)
            return subjects[gameID]!
                .handleEvents(receiveCompletion: { _ in
                    activeRequestCount -= 1
                })
                .eraseToAnyPublisher()
        }
        .sink(
            receiveCompletion: {
                if case .failure(let error) = $0 {
                    receivedError = error
                }
                completed.fulfill()
            },
            receiveValue: { loadedGames = $0 }
        )
        .store(in: &cancellables)

        XCTAssertEqual(requestedGameIDs, [701, 702])
        XCTAssertNil(loadedGames)

        subjects[702]?.send(try makeFinishedGameDetail(gameID: 702))
        subjects[702]?.send(completion: .finished)
        XCTAssertEqual(requestedGameIDs, [701, 702, 703])
        XCTAssertNil(loadedGames)

        subjects[703]?.send(try makeFinishedGameDetail(gameID: 703))
        subjects[703]?.send(completion: .finished)
        XCTAssertEqual(requestedGameIDs, [701, 702, 703, 704])
        XCTAssertNil(loadedGames)

        subjects[704]?.send(try makeFinishedGameDetail(gameID: 704))
        subjects[704]?.send(completion: .finished)
        XCTAssertNil(loadedGames)

        subjects[701]?.send(try makeFinishedGameDetail(gameID: 701))
        subjects[701]?.send(completion: .finished)
        wait(for: [completed], timeout: 5)

        XCTAssertNil(receivedError)
        XCTAssertEqual(peakRequestCount, 2)
        XCTAssertEqual(loadedGames?.compactMap { $0.game.ogsID }, gameIDs)
        XCTAssertEqual(
            loadedGames?.compactMap { $0.detail?.ogsGame.gameId },
            gameIDs
        )
    }

    func testFinishedGameDetailLoadingFailurePublishesNoLightweightGames() {
        enum ExpectedError: Error {
            case failed
        }

        let games = [makeHistoryGame(id: 711), makeHistoryGame(id: 712)]
        let subjects = [
            711: PassthroughSubject<FinishedGameDetail, Error>(),
            712: PassthroughSubject<FinishedGameDetail, Error>(),
        ]
        var receivedGames = false
        var receivedError: Error?
        let completed = expectation(description: "detail page failed atomically")

        OGSService.loadingFinishedGameDetails(
            for: games,
            maximumConcurrentRequests: 2,
            loadDetail: { subjects[$0]!.eraseToAnyPublisher() }
        )
        .sink(
            receiveCompletion: {
                if case .failure(let error) = $0 {
                    receivedError = error
                }
                completed.fulfill()
            },
            receiveValue: { _ in receivedGames = true }
        )
        .store(in: &cancellables)

        subjects[711]?.send(completion: .failure(ExpectedError.failed))
        wait(for: [completed], timeout: 5)

        XCTAssertNotNil(receivedError)
        XCTAssertFalse(receivedGames)
        XCTAssertTrue(games.allSatisfy { $0.gameData == nil })
    }

    func testFinishedGameDetailLoadingSkipsCompleteReusableGame() throws {
        let completeGame = makeHistoryGame(id: 721)
        let completeDetail = try makeFinishedGameDetail(gameID: 721)
        OGSService.applyFinishedGameDetail(completeDetail, to: completeGame)
        let lightweightGame = makeHistoryGame(id: 722)
        let lightweightDetail = try makeFinishedGameDetail(gameID: 722)
        var requestedGameIDs = [Int]()
        var loadedGames: [(game: Game, detail: FinishedGameDetail?)]?
        let completed = expectation(description: "only missing detail loaded")

        OGSService.loadingFinishedGameDetails(
            for: [completeGame, lightweightGame],
            maximumConcurrentRequests: 4
        ) { gameID in
            requestedGameIDs.append(gameID)
            return Just(lightweightDetail)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        .sink(
            receiveCompletion: { _ in completed.fulfill() },
            receiveValue: { loadedGames = $0 }
        )
        .store(in: &cancellables)

        wait(for: [completed], timeout: 5)
        XCTAssertEqual(requestedGameIDs, [722])
        XCTAssertTrue(loadedGames?[0].game === completeGame)
        XCTAssertNil(loadedGames?[0].detail)
        XCTAssertTrue(loadedGames?[1].game === lightweightGame)
        XCTAssertEqual(loadedGames?[1].detail?.ogsGame.gameId, 722)
    }

    func testFinishedGameDetailLoadingRefreshesReusedLiveGameWithoutFinalResult() throws {
        let gameID = 723
        let reusedGame = makeHistoryGame(id: gameID)
        let finishedDetail = try makeFinishedGameDetail(gameID: gameID)
        var liveGameData = finishedDetail.ogsGame
        liveGameData.phase = .play
        liveGameData.outcome = nil
        liveGameData.winner = nil
        reusedGame.ogsRawData = finishedDetail.rawData
        reusedGame.gameData = liveGameData
        // The websocket phase event updates `gamePhase`, but does not update
        // the result fields inside the previously loaded `gameData`.
        reusedGame.gamePhase = .finished

        var requestedGameIDs = [Int]()
        var loadedGames: [(game: Game, detail: FinishedGameDetail?)]?
        let completed = expectation(description: "stale live detail refreshed")

        OGSService.loadingFinishedGameDetails(
            for: [reusedGame],
            maximumConcurrentRequests: 4
        ) { requestedGameID in
            requestedGameIDs.append(requestedGameID)
            return Just(finishedDetail)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        .sink(
            receiveCompletion: { _ in completed.fulfill() },
            receiveValue: { loadedGames = $0 }
        )
        .store(in: &cancellables)

        wait(for: [completed], timeout: 5)
        XCTAssertEqual(requestedGameIDs, [gameID])
        XCTAssertTrue(loadedGames?.first?.game === reusedGame)
        XCTAssertEqual(loadedGames?.first?.detail?.ogsGame.outcome, finishedDetail.ogsGame.outcome)
        XCTAssertEqual(loadedGames?.first?.detail?.ogsGame.winner, finishedDetail.ogsGame.winner)
    }

    func testApplyingFinishedGameDetailPreservesListingPlayersAndReplaysBoard() throws {
        let detail = try makeFinishedGameDetail(gameID: 731)
        let game = makeHistoryGame(id: 731)
        let listedBlack = try makeUser(
            id: detail.ogsGame.players.black.id,
            username: "fresh-black",
            ranking: 31
        )
        let listedWhite = try makeUser(
            id: detail.ogsGame.players.white.id,
            username: "fresh-white",
            ranking: 22
        )
        game.blackPlayer = listedBlack
        game.whitePlayer = listedWhite

        var staleRawData = detail.rawData
        staleRawData["players"] = [
            "black": [
                "id": listedBlack.id,
                "username": "stale-black",
                "ranking": 1,
            ],
            "white": [
                "id": listedWhite.id,
                "username": "stale-white",
                "ranking": 2,
            ],
        ]

        OGSService.applyFinishedGameDetail(
            FinishedGameDetail(
                ogsGame: detail.ogsGame,
                rawData: staleRawData
            ),
            to: game
        )

        XCTAssertEqual(game.blackPlayer?.username, listedBlack.username)
        XCTAssertEqual(game.blackPlayer?.ranking, listedBlack.ranking)
        XCTAssertEqual(game.blackPlayer?.formattedRank, listedBlack.formattedRank)
        XCTAssertEqual(game.blackPlayer?.usernameAndRank(hidesRank: false), listedBlack.usernameAndRank(hidesRank: false))
        XCTAssertEqual(game.whitePlayer?.username, listedWhite.username)
        XCTAssertEqual(game.whitePlayer?.ranking, listedWhite.ranking)
        XCTAssertEqual(game.whitePlayer?.formattedRank, listedWhite.formattedRank)
        XCTAssertEqual(game.whitePlayer?.usernameAndRank(hidesRank: false), listedWhite.usernameAndRank(hidesRank: false))
        XCTAssertEqual(game.gameData?.gameId, 731)
        XCTAssertEqual(
            game.currentPosition.lastMoveNumber,
            detail.ogsGame.moves.count
        )
        XCTAssertNotNil(game.ogsRawData)
    }

    func testApplyingFinishedDetailPreservesListingDisplayAgainstCachedRatingsAndPlayerUpdates() throws {
        for hasPlayerUpdate in [false, true] {
            let gameID = hasPlayerUpdate ? 734 : 733
            let base = try makeFinishedGameDetail(gameID: gameID)
            let blackID = base.ogsGame.players.black.id
            let whiteID = base.ogsGame.players.white.id
            let listedBlack = try makeUser(id: blackID, username: "fresh-black", ranking: 31)
            let listedWhite = try makeUser(id: whiteID, username: "fresh-white", ranking: 22)
            let oldRatings: [String: Any] = [
                "overall": ["rating": 1_400, "deviation": 60, "volatility": 0.06],
            ]
            let cachedBlack: [String: Any] = [
                "id": blackID, "username": "cached-black", "ranking": 1, "ratings": oldRatings,
            ]
            let cachedWhite: [String: Any] = [
                "id": whiteID, "username": "cached-white", "ranking": 2, "ratings": oldRatings,
            ]
            let detail = try makeFinishedGameDetail(gameID: gameID) { payload in
                payload["players"] = ["black": cachedBlack, "white": cachedWhite]
                payload["player_pool"] = [String(blackID): cachedBlack, String(whiteID): cachedWhite]
                var moves: [[Any]] = [[0, 0], [1, 0], [0, 1]]
                if hasPlayerUpdate {
                    moves[1] = [1, 0, 0, false, ["player_update": [
                        "players": ["black": blackID, "white": whiteID],
                        "rengo_teams": [String: Any](),
                    ]]]
                }
                payload["moves"] = moves
            }
            let game = makeHistoryGame(id: gameID)
            game.blackPlayer = listedBlack
            game.whitePlayer = listedWhite

            OGSService.applyFinishedGameDetail(detail, to: game)

            XCTAssertEqual(game.blackPlayer, listedBlack)
            XCTAssertEqual(game.whitePlayer, listedWhite)
            XCTAssertEqual(game.blackPlayer?.formattedRank, listedBlack.formattedRank)
            XCTAssertEqual(game.whitePlayer?.formattedRank, listedWhite.formattedRank)
            XCTAssertEqual(game.blackPlayer?.usernameAndRank(hidesRank: false), listedBlack.usernameAndRank(hidesRank: false))
            XCTAssertEqual(game.whitePlayer?.usernameAndRank(hidesRank: false), listedWhite.usernameAndRank(hidesRank: false))
            XCTAssertEqual(game.playerByOGSId[blackID], listedBlack)
            XCTAssertEqual(game.playerByOGSId[whiteID], listedWhite)
            XCTAssertEqual(game.finishedHistoryPosition?.lastMoveNumber, 3)

            game.latestPlayerUpdate = OGSPlayerUpdate(players: .init(black: blackID, white: whiteID))
            XCTAssertEqual(game.blackPlayer, listedBlack, "A repeated update must resolve the repaired player pool")
            XCTAssertEqual(game.whitePlayer, listedWhite)
        }
    }

    func testApplyingFinishedDetailPreservesChangedPlayerIDsAndRengoOrder() throws {
        for isRengo in [false, true] {
            let gameID = isRengo ? 736 : 735
            let base = try makeFinishedGameDetail(gameID: gameID)
            let blackID = base.ogsGame.players.black.id
            let whiteID = base.ogsGame.players.white.id
            let listedBlack = try makeUser(id: blackID, username: "fresh-original-black", ranking: 31)
            let listedWhite = try makeUser(id: whiteID, username: "fresh-original-white", ranking: 22)
            let nextBlackID = 900_301
            let nextWhiteID = 900_302
            let cachedBlack: [String: Any] = ["id": blackID, "username": "old-black", "ranking": 1]
            let cachedWhite: [String: Any] = ["id": whiteID, "username": "old-white", "ranking": 2]
            let nextBlack: [String: Any] = ["id": nextBlackID, "username": "Next black", "ranking": 25]
            let nextWhite: [String: Any] = ["id": nextWhiteID, "username": "Next white", "ranking": 24]
            let detail = try makeFinishedGameDetail(gameID: gameID) { payload in
                payload["players"] = ["black": cachedBlack, "white": cachedWhite]
                payload["player_pool"] = [
                    String(blackID): cachedBlack, String(whiteID): cachedWhite,
                    String(nextBlackID): nextBlack, String(nextWhiteID): nextWhite,
                ]
                payload["rengo"] = isRengo
                var update: [String: Any] = ["players": ["black": nextBlackID, "white": nextWhiteID]]
                if isRengo {
                    payload["rengo_teams"] = ["black": [cachedBlack, nextBlack], "white": [cachedWhite, nextWhite]]
                    update["rengo_teams"] = ["black": [nextBlackID, blackID], "white": [nextWhiteID, whiteID]]
                }
                payload["moves"] = [[0, 0], [1, 0, 0, false, ["player_update": update]], [0, 1]] as [[Any]]
            }
            let game = makeHistoryGame(id: gameID)
            game.blackPlayer = listedBlack
            game.whitePlayer = listedWhite

            OGSService.applyFinishedGameDetail(detail, to: game)

            XCTAssertEqual(game.blackPlayer?.id, nextBlackID)
            XCTAssertEqual(game.whitePlayer?.id, nextWhiteID)
            XCTAssertEqual(game.blackPlayer?.username, "Next black")
            XCTAssertEqual(game.whitePlayer?.username, "Next white")
            XCTAssertEqual(game.playerByOGSId[blackID], listedBlack)
            XCTAssertEqual(game.playerByOGSId[whiteID], listedWhite)
            XCTAssertEqual(game.currentPlayer(with: .black)?.id, nextBlackID)
            XCTAssertEqual(game.currentPlayer(with: .white)?.id, nextWhiteID)
            XCTAssertEqual(game.finishedHistoryPosition?.lastMoveNumber, 3)
            if isRengo {
                XCTAssertEqual(game.orderedRengoTeam[.black]?.map(\.id), [nextBlackID, blackID])
                XCTAssertEqual(game.orderedRengoTeam[.white]?.map(\.id), [nextWhiteID, whiteID])
                XCTAssertEqual(game.orderedRengoTeam[.black]?.last, listedBlack)
                XCTAssertEqual(game.orderedRengoTeam[.white]?.last, listedWhite)
            }

            game.latestPlayerUpdate = try XCTUnwrap(detail.ogsGame.moves[1].extra?.playerUpdate)
            XCTAssertEqual(game.blackPlayer?.id, nextBlackID)
            XCTAssertEqual(game.whitePlayer?.id, nextWhiteID)
            if isRengo {
                XCTAssertEqual(game.orderedRengoTeam[.black]?.map(\.id), [nextBlackID, blackID])
                XCTAssertEqual(game.orderedRengoTeam[.white]?.map(\.id), [nextWhiteID, whiteID])
            }
        }
    }

    func testApplyingCachedFinishedDetailRetainsFreshListingAnnulment() throws {
        let detail = try makeFinishedGameDetail(gameID: 732)
        let game = makeHistoryGame(id: 732)
        game.historyAnnulled = true
        var cachedRawData = detail.rawData
        cachedRawData["annulled"] = false

        OGSService.applyFinishedGameDetail(
            FinishedGameDetail(ogsGame: detail.ogsGame, rawData: cachedRawData),
            to: game
        )

        XCTAssertEqual(game.historyAnnulled, true)
        XCTAssertEqual(game.ogsRawData?["annulled"] as? Bool, true)
        XCTAssertNotNil(game.ogsRawData?["gamedata"])
    }

    func testMergingFinishedGamesPreservesFirstInstanceAndDeduplicatesPages() {
        let first = makeHistoryGame(id: 5)
        let retained = makeHistoryGame(id: 4)
        let overlapping = makeHistoryGame(id: 4)
        let incoming = makeHistoryGame(id: 3)
        let repeatedIncoming = makeHistoryGame(id: 3)

        let merged = OGSService.mergingFinishedGames(
            [first, retained],
            with: [overlapping, incoming, repeatedIncoming]
        )

        XCTAssertEqual(merged.compactMap(\.ogsID), [5, 4, 3])
        XCTAssertTrue(merged[1] === retained)
        XCTAssertTrue(merged[2] === incoming)
    }

    func testHistoryPaginationAutoAdvancesPastDuplicateOnlyPage() throws {
        var pagination = GameHistoryPaginationState()
        let firstRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        let retained = makeHistoryGame(id: 5)

        XCTAssertEqual(
            pagination.finish(
                .success(games: [retained], hasNextPage: true),
                for: firstRequest,
                currentPlayerID: 101
            ),
            .finished
        )

        let duplicateRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        XCTAssertEqual(duplicateRequest.page, 2)
        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 5)], hasNextPage: true),
                for: duplicateRequest,
                currentPlayerID: 101
            ),
            .loadNextPage
        )
        XCTAssertEqual(pagination.games.compactMap(\.ogsID), [5])
        XCTAssertTrue(pagination.games[0] === retained)

        let continuedRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        XCTAssertEqual(continuedRequest.page, 3)
    }

    func testHistoryPaginationStopsAutoAdvanceAfterUniquePage() throws {
        var pagination = GameHistoryPaginationState()
        let firstRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        _ = pagination.finish(
            .success(games: [makeHistoryGame(id: 5)], hasNextPage: true),
            for: firstRequest,
            currentPlayerID: 101
        )
        let secondRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))

        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 4)], hasNextPage: true),
                for: secondRequest,
                currentPlayerID: 101
            ),
            .finished
        )
        XCTAssertEqual(pagination.games.compactMap(\.ogsID), [5, 4])
        XCTAssertEqual(pagination.nextPage, 3)
        XCTAssertTrue(pagination.hasMore)
        XCTAssertFalse(pagination.isLoading)
    }

    func testHistoryPaginationStopsAfterThreeConsecutiveNoProgressPages() throws {
        var pagination = GameHistoryPaginationState()
        let firstRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        _ = pagination.finish(
            .success(games: [makeHistoryGame(id: 5)], hasNextPage: true),
            for: firstRequest,
            currentPlayerID: 101
        )

        for expectedPage in 2...3 {
            let duplicateRequest = try XCTUnwrap(
                pagination.beginRequest(playerID: 101)
            )
            XCTAssertEqual(duplicateRequest.page, expectedPage)
            XCTAssertEqual(
                pagination.finish(
                    .success(
                        games: [makeHistoryGame(id: 5)],
                        hasNextPage: true
                    ),
                    for: duplicateRequest,
                    currentPlayerID: 101
                ),
                .loadNextPage
            )
        }

        let cappedRequest = try XCTUnwrap(
            pagination.beginRequest(playerID: 101)
        )
        XCTAssertEqual(cappedRequest.page, 4)
        XCTAssertEqual(
            pagination.finish(
                .success(
                    games: [makeHistoryGame(id: 5)],
                    hasNextPage: true
                ),
                for: cappedRequest,
                currentPlayerID: 101
            ),
            .finished
        )
        XCTAssertFalse(pagination.hasMore)
        XCTAssertFalse(pagination.isLoading)
        XCTAssertNil(pagination.beginRequest(playerID: 101))
    }

    func testHistoryPaginationProgressResetsNoProgressLimit() throws {
        var pagination = GameHistoryPaginationState()
        let firstRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        _ = pagination.finish(
            .success(games: [makeHistoryGame(id: 5)], hasNextPage: true),
            for: firstRequest,
            currentPlayerID: 101
        )

        for _ in 0..<2 {
            let duplicateRequest = try XCTUnwrap(
                pagination.beginRequest(playerID: 101)
            )
            XCTAssertEqual(
                pagination.finish(
                    .success(
                        games: [makeHistoryGame(id: 5)],
                        hasNextPage: true
                    ),
                    for: duplicateRequest,
                    currentPlayerID: 101
                ),
                .loadNextPage
            )
        }

        let progressRequest = try XCTUnwrap(
            pagination.beginRequest(playerID: 101)
        )
        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 4)], hasNextPage: true),
                for: progressRequest,
                currentPlayerID: 101
            ),
            .finished
        )

        let duplicateAfterProgressRequest = try XCTUnwrap(
            pagination.beginRequest(playerID: 101)
        )
        XCTAssertEqual(
            pagination.finish(
                .success(
                    games: [makeHistoryGame(id: 4)],
                    hasNextPage: true
                ),
                for: duplicateAfterProgressRequest,
                currentPlayerID: 101
            ),
            .loadNextPage
        )
        XCTAssertTrue(pagination.hasMore)
    }

    func testHistoryPaginationStopsAtFinalDuplicatePage() throws {
        var pagination = GameHistoryPaginationState()
        let firstRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        _ = pagination.finish(
            .success(games: [makeHistoryGame(id: 5)], hasNextPage: true),
            for: firstRequest,
            currentPlayerID: 101
        )
        let finalRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))

        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 5)], hasNextPage: false),
                for: finalRequest,
                currentPlayerID: 101
            ),
            .finished
        )
        XCTAssertFalse(pagination.hasMore)
        XCTAssertNil(pagination.beginRequest(playerID: 101))
    }

    func testHistoryPaginationGatesRequestsWhileLoadingAndAllowsRetryAfterFailure() throws {
        var pagination = GameHistoryPaginationState()
        XCTAssertNil(pagination.beginRequest(playerID: nil))

        let request = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        XCTAssertTrue(pagination.isLoading)
        XCTAssertNil(pagination.beginRequest(playerID: 101))
        XCTAssertNil(pagination.beginRequest(playerID: 202))

        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 5)], hasNextPage: false),
                for: request,
                currentPlayerID: 202
            ),
            .ignored
        )
        XCTAssertTrue(pagination.isLoading)

        XCTAssertEqual(
            pagination.finish(
                .failure,
                for: request,
                currentPlayerID: 101
            ),
            .finished
        )
        XCTAssertTrue(pagination.loadedOnce)
        XCTAssertTrue(pagination.hasMore)
        XCTAssertFalse(pagination.isLoading)
        XCTAssertTrue(pagination.lastRequestFailed)

        let retryRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        XCTAssertEqual(retryRequest.page, request.page)
        XCTAssertTrue(pagination.isLoading)
        XCTAssertFalse(pagination.lastRequestFailed)
    }

    func testHistoryPaginationIgnoresStaleResultAfterReset() throws {
        var pagination = GameHistoryPaginationState()
        let staleRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))

        // Resetting for the same numeric player still starts a new generation.
        pagination.reset(playerID: 101)
        let currentRequest = try XCTUnwrap(pagination.beginRequest(playerID: 101))
        XCTAssertEqual(currentRequest.page, 1)

        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 5)], hasNextPage: false),
                for: staleRequest,
                currentPlayerID: 101
            ),
            .ignored
        )
        XCTAssertTrue(pagination.isLoading)
        XCTAssertTrue(pagination.games.isEmpty)

        XCTAssertEqual(
            pagination.finish(
                .success(games: [makeHistoryGame(id: 4)], hasNextPage: false),
                for: currentRequest,
                currentPlayerID: 101
            ),
            .finished
        )
        XCTAssertEqual(pagination.games.compactMap(\.ogsID), [4])
        XCTAssertFalse(pagination.isLoading)
    }

    func testTwoLoginsKeepCookiesPreferencesAndUsersIsolated() async throws {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let firstHTTP = makeHTTPClient(responseUsername: "player-one")
        let secondHTTP = makeHTTPClient(responseUsername: "player-two")
        let firstSocket = StubWebsocket()
        let secondSocket = StubWebsocket()
        let first = makeService(environment: environment, httpClient: firstHTTP, socket: firstSocket, label: "one")
        let second = makeService(environment: environment, httpClient: secondHTTP, socket: secondSocket, label: "two")

        let firstLogin = expectation(description: "first login")
        let secondLogin = expectation(description: "second login")
        var loginErrors = [Error]()

        first.login(username: "player-one", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { loginErrors.append(error) }
                    firstLogin.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        second.login(username: "player-two", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { loginErrors.append(error) }
                    secondLogin.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [firstLogin, secondLogin], timeout: 5)
        XCTAssertTrue(loginErrors.isEmpty)
        XCTAssertEqual(first.user?.id, 101)
        XCTAssertEqual(second.user?.id, 202)
        XCTAssertTrue(first.isLoggedIn)
        XCTAssertTrue(second.isLoggedIn)

        XCTAssertEqual(cookie(named: "sessionid", in: firstHTTP.cookieStorage), "session-player-one")
        XCTAssertEqual(cookie(named: "sessionid", in: secondHTTP.cookieStorage), "session-player-two")
        XCTAssertEqual(cookie(named: "csrftoken", in: firstHTTP.cookieStorage), "csrf-player-one")
        XCTAssertEqual(cookie(named: "csrftoken", in: secondHTTP.cookieStorage), "csrf-player-two")
        XCTAssertNotEqual(first.ogsUIConfig?.userJwt, second.ogsUIConfig?.userJwt)
        XCTAssertEqual(firstSocket.reconnectCount, 1)
        XCTAssertEqual(secondSocket.reconnectCount, 1)
        XCTAssertEqual(firstSocket.authenticationConfigProvider()?.userJwt, "jwt-player-one")
        XCTAssertEqual(secondSocket.authenticationConfigProvider()?.userJwt, "jwt-player-two")

        let remoteSettingsKey = OGSRemoteSettingKey<[OGSChallengeTemplate]>.preferredGameSettings
        let storedSettings = OGSRemoteSettingValue<[OGSChallengeTemplate]>(
            value: [],
            replication: .RemoteOnly,
            modified: Date()
        )
        first.preferences.set(try JSONEncoder().encode(storedSettings), forKey: remoteSettingsKey.name)
        XCTAssertNotNil(first.remoteSettings[remoteSettingsKey])
        XCTAssertNil(second.remoteSettings[remoteSettingsKey])

        let firstGame = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(1))
        let secondGame = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(2))
        firstGame.ogs = first
        secondGame.ogs = second
        XCTAssertTrue(firstGame.preferences === first.preferences)
        XCTAssertTrue(secondGame.preferences === second.preferences)

        let loginRequests = StubURLProtocol.recordedRequests(
            forPath: "/api/v0/login"
        )
        XCTAssertEqual(loginRequests.count, 2)
    }

    func testPrivateMessageUnreadCountTracksIncomingConversations() throws {
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-messages"),
            label: "private-message-unread"
        )
        try signInForPrivateMessageTest(service, userID: 101)

        service.setUpNewPeerIfNecessary(peerId: 42)
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)
        XCTAssertTrue(service.privateMessagesUnreadPeerIds.isEmpty)

        let first = privateMessage(from: 42, to: 101, id: "first", timestamp: 100)
        service.handlePrivateMessage(first)
        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "older-history", timestamp: 99))
        service.handlePrivateMessage(first)
        service.handlePrivateMessage(privateMessage(from: 101, to: 42, id: "reply", timestamp: 102))
        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "second", timestamp: 101))
        XCTAssertEqual(service.privateMessagesUnreadCount, 1)
        XCTAssertEqual(service.privateMessagesUnreadPeerIds, [42])
        XCTAssertEqual(service.privateMessagesByPeerId[42]?.map(\.content.timestamp), [99, 100, 101, 102])

        service.markPrivateMessageThreadAsRead(peerId: 42)
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)
        XCTAssertEqual(
            service.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?[101]?[42],
            101
        )
        service.handlePrivateMessage(privateMessage(from: 101, to: 42, id: "next-reply", timestamp: 104))
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)
        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "third", timestamp: 103))
        XCTAssertEqual(service.privateMessagesUnreadPeerIds, [42])
        XCTAssertEqual(service.privateMessagesUnreadCount, 1)
    }

    func testPrivateMessageUnreadPublishesOnlyWhenUnreadStateChanges() throws {
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-unread-publications"),
            label: "private-message-unread-publications"
        )
        try signInForPrivateMessageTest(service, userID: 101)
        var peerPublications = [Set<Int>]()
        var countPublications = [Int]()
        service.$privateMessagesUnreadPeerIds
            .dropFirst()
            .sink { peerPublications.append($0) }
            .store(in: &cancellables)
        service.$privateMessagesUnreadCount
            .dropFirst()
            .sink { countPublications.append($0) }
            .store(in: &cancellables)

        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "first", timestamp: 100))
        XCTAssertEqual(peerPublications, [Set([42])])
        XCTAssertEqual(countPublications, [1])

        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "already-unread", timestamp: 101))
        XCTAssertEqual(peerPublications, [Set([42])], "Another message in an unread thread must not republish equal unread state.")
        XCTAssertEqual(countPublications, [1])

        service.markPrivateMessageThreadAsRead(peerId: 42)
        XCTAssertEqual(peerPublications, [Set([42]), Set<Int>()])
        XCTAssertEqual(countPublications, [1, 0])
        XCTAssertEqual(service.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?[101]?[42], 101)

        service.markPrivateMessageThreadAsRead(peerId: 42)
        service.markPrivateMessageThreadAsRead(peerId: 42)
        XCTAssertEqual(peerPublications, [Set([42]), Set<Int>()], "Repeated visible read checks must not invalidate the unread hierarchy.")
        XCTAssertEqual(countPublications, [1, 0])

        service.handlePrivateMessage(privateMessage(from: 42, to: 101, id: "new-unread", timestamp: 102))
        XCTAssertEqual(peerPublications, [Set([42]), Set<Int>(), Set([42])])
        XCTAssertEqual(countPublications, [1, 0, 1])
        XCTAssertEqual(service.privateMessagesUnreadPeerIds, [42])
    }

    func testPrivateMessageReadMarkersAndHistoryPeersStayWithTheirAccount() throws {
        let socket = StubWebsocket()
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-accounts"),
            socket: socket,
            label: "private-message-accounts"
        )
        try signInForPrivateMessageTest(service, userID: 101)
        let firstAccountMessage = privateMessage(from: 42, to: 101, id: "account-one", timestamp: 100)
        service.handlePrivateMessage(firstAccountMessage)
        service.markPrivateMessageThreadAsRead(peerId: 42)
        XCTAssertEqual(service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101], [42])

        try signInForPrivateMessageTest(service, userID: 202)
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)
        XCTAssertTrue(service.privateMessagesUnreadPeerIds.isEmpty)
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)
        socket.resetEmittedCommands()
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        XCTAssertFalse(socket.emittedCommands.contains("chat/pm/load"))

        service.handlePrivateMessage(firstAccountMessage)
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)
        let secondAccountMessage = privateMessage(from: 42, to: 202, id: "account-two", timestamp: 100)
        service.handlePrivateMessage(secondAccountMessage)
        XCTAssertEqual(service.privateMessagesUnreadPeerIds, [42])

        try signInForPrivateMessageTest(service, userID: 101)
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)
        socket.resetEmittedCommands()
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        XCTAssertEqual(socket.emittedCommands.filter { $0 == "chat/pm/load" }.count, 1)
        service.handlePrivateMessage(firstAccountMessage)
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)
        XCTAssertEqual(service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[202], [42])

        service.logout()
        XCTAssertEqual(service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101], [42])
        XCTAssertEqual(service.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?[101]?[42], 100)
        try signInForPrivateMessageTest(service, userID: 101)
        socket.resetEmittedCommands()
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        XCTAssertEqual(socket.emittedCommands.filter { $0 == "chat/pm/load" }.count, 1)
    }

    func testRecentPrivateMessagePeersKeepTimestampOrderAcrossHistoryReplayAndEviction() throws {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: "private-message-recent-peers")
        let first = makeService(
            environment: environment,
            httpClient: httpClient,
            label: "private-message-recent-peers"
        )
        try signInForPrivateMessageTest(first, userID: 101)
        for peerID in 1...50 {
            first.handlePrivateMessage(privateMessage(
                from: peerID, to: 101, id: "original-\(peerID)", timestamp: Double(peerID)
            ))
        }
        XCTAssertEqual(
            first.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101],
            Array((1...50).reversed())
        )

        let secondSocket = StubWebsocket()
        let second = OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: first.preferences,
            ogsWebsocket: secondSocket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        try signInForPrivateMessageTest(second, userID: 101)
        secondSocket.serverEventCallback?("surround/socketAuthenticated", nil)
        XCTAssertEqual(secondSocket.emittedCommands.filter { $0 == "chat/pm/load" }.count, 50)

        // Socket history arrives in load order, rather than timestamp order.
        for peerID in 1...50 {
            second.handlePrivateMessage(privateMessage(
                from: peerID, to: 101, id: "replayed-\(peerID)", timestamp: Double(peerID)
            ))
        }
        XCTAssertEqual(
            second.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101],
            Array((1...50).reversed())
        )

        second.handlePrivateMessage(privateMessage(
            from: 51, to: 101, id: "new-peer", timestamp: 51
        ))
        XCTAssertEqual(
            second.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101],
            [51] + Array((2...50).reversed())
        )
        XCTAssertNil(
            second.preferences[.latestPrivateMessageTimestampByOGSAccountAndPeerID]?[101]?[1]
        )

        second.handlePrivateMessage(privateMessage(
            from: 101, to: 2, id: "new-reply", timestamp: 52
        ))
        XCTAssertEqual(
            Array(second.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101]?.prefix(3) ?? []),
            [2, 51, 50]
        )
        second.handlePrivateMessage(privateMessage(
            from: 3, to: 101, id: "old-late-replay", timestamp: 2
        ))
        XCTAssertEqual(
            Array(second.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101]?.prefix(3) ?? []),
            [2, 51, 50]
        )
    }

    func testRecentPrivateMessagePeerOrderMigratesAfterAllSavedPeersReload() throws {
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-recency-migration"),
            label: "private-message-recency-migration"
        )
        try signInForPrivateMessageTest(service, userID: 101)
        service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID] = [101: [2, 3, 1]]

        service.handlePrivateMessage(privateMessage(
            from: 1, to: 101, id: "oldest", timestamp: 1
        ))
        service.handlePrivateMessage(privateMessage(
            from: 2, to: 101, id: "middle", timestamp: 2
        ))
        XCTAssertEqual(
            service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101],
            [2, 3, 1]
        )

        service.handlePrivateMessage(privateMessage(
            from: 3, to: 101, id: "newest", timestamp: 3
        ))
        XCTAssertEqual(
            service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[101],
            [3, 2, 1]
        )
    }

    func testPrivateMessageSendFailureSeparatesDefiniteRejectionFromMissingAcknowledgement() throws {
        XCTAssertEqual(
            PrivateMessageSendFailure.classify(OGSServiceError.notLoggedIn), .notSent
        )
        XCTAssertEqual(
            PrivateMessageSendFailure.classify(URLError(.timedOut)),
            .deliveryUnconfirmed
        )
        XCTAssertEqual(
            PrivateMessageSendFailure.classify(OGSServiceError.invalidJSON),
            .deliveryUnconfirmed
        )

        let socket = StubWebsocket()
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-send-failure"),
            socket: socket,
            label: "private-message-send-failure"
        )
        try signInForPrivateMessageTest(service, userID: 101)
        socket.nextCallbackError = ["error": "message rejected"]
        let rejected = expectation(description: "server rejected the private message")
        service.sendPrivateMessage(
            to: OGSUser(username: "player-42", id: 42), message: "hello"
        )
        .sink { completion in
            if case .failure(let error) = completion {
                XCTAssertEqual(PrivateMessageSendFailure.classify(error), .notSent)
                rejected.fulfill()
            }
        } receiveValue: { _ in
            XCTFail("A rejected message must not be acknowledged")
        }
        .store(in: &cancellables)
        wait(for: [rejected], timeout: 1)

        socket.nextCallbackError = [
            "connection": "not connected",
            "not_sent": "not connected"
        ]
        let preSendFailure = expectation(description: "private message never left the device")
        service.sendPrivateMessage(
            to: OGSUser(username: "player-42", id: 42), message: "hello again"
        )
        .sink { completion in
            if case .failure(let error) = completion {
                XCTAssertEqual(PrivateMessageSendFailure.classify(error), .notSent)
                preSendFailure.fulfill()
            }
        } receiveValue: { _ in
            XCTFail("An unsent message must not be acknowledged")
        }
        .store(in: &cancellables)
        wait(for: [preSendFailure], timeout: 1)

        socket.nextCallbackError = ["timeout": "no acknowledgement"]
        let unconfirmed = expectation(description: "private message delivery is unconfirmed")
        service.sendPrivateMessage(
            to: OGSUser(username: "player-42", id: 42), message: "third attempt"
        )
        .sink { completion in
            if case .failure(let error) = completion {
                XCTAssertEqual(
                    PrivateMessageSendFailure.classify(error), .deliveryUnconfirmed
                )
                unconfirmed.fulfill()
            }
        } receiveValue: { _ in
            XCTFail("A timed-out message must not be acknowledged")
        }
        .store(in: &cancellables)
        wait(for: [unconfirmed], timeout: 1)
    }

    func testLegacyPrivateMessageReadMarkersMigrateOnlyToTheirSavedAccount() throws {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: "private-message-read-migration")
        let first = makeService(
            environment: environment,
            httpClient: httpClient,
            label: "private-message-read-migration"
        )
        try signInForPrivateMessageTest(first, userID: 101)
        first.preferences[.lastSeenPrivateMessageByOGSUserId] = [42: 100, 43: 90]
        first.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID] = [101: [42: 150]]

        let restored = OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: first.preferences,
            ogsWebsocket: StubWebsocket(),
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        XCTAssertEqual(
            restored.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?[101],
            [42: 150, 43: 90]
        )
        XCTAssertTrue(restored.preferences[.lastSeenPrivateMessageByOGSUserId]?.isEmpty == true)
        try signInForPrivateMessageTest(restored, userID: 202)
        restored.handlePrivateMessage(privateMessage(
            from: 42, to: 202, id: "new-account-unread", timestamp: 100
        ))
        XCTAssertEqual(restored.privateMessagesUnreadPeerIds, [42])
        XCTAssertNil(restored.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?[202])
    }

    func testUnownedLegacyPrivateMessageReadMarkersDoNotHideNewAccountMessages() throws {
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-unowned-markers"),
            label: "private-message-unowned-markers"
        )
        service.preferences[.lastSeenPrivateMessageByOGSUserId] = [42: 500]
        try signInForPrivateMessageTest(service, userID: 202)
        service.handlePrivateMessage(privateMessage(
            from: 42, to: 202, id: "unread", timestamp: 100
        ))
        XCTAssertEqual(service.privateMessagesUnreadPeerIds, [42])
        XCTAssertTrue(service.preferences[.lastSeenPrivateMessageByOGSUserId]?.isEmpty == true)
        XCTAssertTrue(service.preferences[.lastSeenPrivateMessageByOGSAccountAndPeerID]?.isEmpty == true)
    }

    func testPrivateMessageAcknowledgementMustMatchSendingAccountAndPeer() throws {
        let socket = StubWebsocket()
        socket.defersPrivateMessageAcknowledgements = true
        let service = makeService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: makeHTTPClient(responseUsername: "private-message-acknowledgements"),
            socket: socket,
            label: "private-message-acknowledgements"
        )
        try signInForPrivateMessageTest(service, userID: 101)
        let peer = OGSUser(username: "player-42", id: 42)
        var acknowledgedMessage: OGSPrivateMessage?
        service.sendPrivateMessage(to: peer, message: "hello")
            .sink(
                receiveCompletion: { if case .failure = $0 { XCTFail("Matching acknowledgement must succeed") } },
                receiveValue: { acknowledgedMessage = $0 }
            )
            .store(in: &cancellables)
        XCTAssertEqual(socket.privateMessageCallbacks.count, 1)
        XCTAssertNil(acknowledgedMessage)
        socket.acknowledgeNextPrivateMessage(with: privateMessagePayload(from: 101, to: 42, id: "acknowledged"))
        XCTAssertEqual(acknowledgedMessage?.content.id, "acknowledged")
        XCTAssertEqual(service.privateMessagesByPeerId[42]?.count, 1)
        XCTAssertEqual(service.privateMessagesUnreadCount, 0)

        var wrongPeerFailure: PrivateMessageSendFailure?
        service.sendPrivateMessage(to: peer, message: "next message")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { wrongPeerFailure = .classify(error) }
                },
                receiveValue: { _ in XCTFail("Another peer's acknowledgement must not clear a draft") }
            )
            .store(in: &cancellables)
        XCTAssertEqual(socket.privateMessageCallbacks.count, 1)
        socket.acknowledgeNextPrivateMessage(with: privateMessagePayload(from: 101, to: 43, id: "wrong-peer"))
        XCTAssertEqual(wrongPeerFailure, .deliveryUnconfirmed)
        XCTAssertNil(service.privateMessagesByPeerId[43])

        var changedAccountFailure: PrivateMessageSendFailure?
        service.sendPrivateMessage(to: peer, message: "message before switching account")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { changedAccountFailure = .classify(error) }
                },
                receiveValue: { _ in XCTFail("An old account's acknowledgement must not clear the active draft") }
            )
            .store(in: &cancellables)
        XCTAssertEqual(socket.privateMessageCallbacks.count, 1)
        try signInForPrivateMessageTest(service, userID: 202)
        socket.acknowledgeNextPrivateMessage(with: privateMessagePayload(from: 101, to: 42, id: "stale-account"))
        XCTAssertEqual(changedAccountFailure, .deliveryUnconfirmed)
        XCTAssertTrue(service.privateMessagesByPeerId.isEmpty)
    }

    func testReadingPrivateMessageInOneSceneUpdatesAnotherScene() throws {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: "private-message-scenes")
        let first = makeService(
            environment: environment,
            httpClient: httpClient,
            label: "private-message-scenes"
        )
        try signInForPrivateMessageTest(first, userID: 101)
        let secondSocket = StubWebsocket()
        let second = OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: first.preferences,
            ogsWebsocket: secondSocket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        try signInForPrivateMessageTest(second, userID: 101)
        let message = privateMessage(from: 42, to: 101, id: "cross-scene", timestamp: 100)
        first.handlePrivateMessage(message)
        second.handlePrivateMessage(message)
        XCTAssertEqual(first.privateMessagesUnreadCount, 1)
        XCTAssertEqual(second.privateMessagesUnreadCount, 1)

        let secondSceneUpdated = expectation(description: "second scene updates its unread count")
        second.$privateMessagesUnreadCount
            .dropFirst()
            .filter { $0 == 0 }
            .first()
            .sink { _ in secondSceneUpdated.fulfill() }
            .store(in: &cancellables)
        first.markPrivateMessageThreadAsRead(peerId: 42)
        wait(for: [secondSceneUpdated], timeout: 2)
        XCTAssertTrue(second.privateMessagesUnreadPeerIds.isEmpty)

        let secondSceneCleared = expectation(description: "second scene clears old account messages")
        second.$privateMessagesByPeerId
            .dropFirst()
            .filter { $0.isEmpty }
            .first()
            .sink { _ in secondSceneCleared.fulfill() }
            .store(in: &cancellables)
        try signInForPrivateMessageTest(first, userID: 202)
        second.handlePrivateMessage(message)
        second.handlePrivateMessage(privateMessage(from: 42, to: 202, id: "new-account", timestamp: 101))
        var staleSendFailed = false
        second.sendPrivateMessage(
            to: OGSUser(username: "player-42", id: 42), message: "stale"
        )
            .sink(
                receiveCompletion: { if case .failure = $0 { staleSendFailed = true } },
                receiveValue: { _ in XCTFail("Stale account must not send a private message") }
            )
            .store(in: &cancellables)
        wait(for: [secondSceneCleared], timeout: 2)
        XCTAssertTrue(second.privateMessagesByPeerId.isEmpty)
        XCTAssertTrue(staleSendFailed)
        XCTAssertFalse(secondSocket.emittedCommands.contains("chat/pm"))
    }

    // MARK: - Superchats: who an event is for, and the store's waits

    func testASuperchatCoversTheSignedInAccount() throws {
        let (store, _) = makeSuperchatStore()
        let (first, firstSocket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-covers"
        )
        let (second, secondSocket) = try makeSuperchatWindow(userID: superchatPlayer, store: store, sharing: first)
        XCTAssertNil(first.superchatCover)
        XCTAssertNil(second.superchatCover)

        firstSocket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        let cover = try XCTUnwrap(store.covers[superchatPlayer], "The event reached the app's store.")
        XCTAssertEqual(cover.moderators.map(\.id), [moderator])
        XCTAssertTrue(cover.isOn)
        XCTAssertEqual(first.superchatCover, cover)
        XCTAssertEqual(second.superchatCover, cover, "A window whose socket heard nothing is covered too.")
        XCTAssertEqual(firstSocket.loadedConversations, [moderator], "The conversation loads into Messages.")

        // A window opened later is covered as soon as it joins the store.
        let (third, _) = try makeSuperchatWindow(userID: superchatPlayer, store: store, sharing: first)
        XCTAssertEqual(third.superchatCover, cover)

        // The end, heard by another window, reaches every window.
        secondSocket.serverEventCallback?(
            "private-superchat", superchat(moderator, enable: false, player: superchatPlayer)
        )
        for window in [first, second, third] {
            XCTAssertEqual(window.superchatCover?.awaitsDone, true)
            XCTAssertEqual(window.superchatEndings, [moderator: SuperchatEnding(at: 1_000, wasMissed: false)])
        }
        store.done(accountID: superchatPlayer)
        for window in [first, second, third] {
            XCTAssertNil(window.superchatCover, "Done in any window clears every window.")
        }
    }

    func testTheModeratorsOwnEchoNeverCovers() throws {
        let (store, _) = makeSuperchatStore()
        // The moderator's own account: OGS sends its connections a copy.
        let (service, socket) = try makeSuperchatWindow(
            userID: moderator, store: store, isModerator: true, label: "superchat-echo"
        )
        // The copy names the player. Without a player_id, only the echo check decides.
        for payload in [
            superchat(moderator, player: superchatPlayer),
            superchat(moderator, player: nil),
            superchat(moderator, enable: false, player: nil),
        ] {
            socket.serverEventCallback?("private-superchat", payload)
        }
        XCTAssertTrue(store.covers.isEmpty)
        XCTAssertNil(service.superchatCover)
        XCTAssertEqual(socket.loadedConversations, [], "No conversation with itself.")
        XCTAssertNil(service.privateMessagesByPeerId[moderator])
    }

    func testAnEventForAnotherPlayerIsIgnored() throws {
        let (store, _) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-other-player"
        )
        // A player_id that is present and isn't this account's: a copy from
        // a socket still speaking for another account.
        let otherPlayerIDs: [Any] = [otherPlayer, "\(otherPlayer)", 0, NSNull()]
        for playerID in otherPlayerIDs {
            var payload = superchat(moderator, player: nil)
            payload["player_id"] = playerID
            socket.serverEventCallback?("private-superchat", payload)
        }
        XCTAssertTrue(store.covers.isEmpty)
        XCTAssertNil(service.superchatCover)
        XCTAssertEqual(socket.loadedConversations, [])

        // Without a player_id, the socket's identity decides, as on the web.
        socket.serverEventCallback?("private-superchat", superchat(moderator, player: nil))
        XCTAssertEqual(store.covers[superchatPlayer]?.moderators.map(\.id), [moderator])
        XCTAssertEqual(service.superchatCover?.isOn, true)

        // Another player's end doesn't end this account's superchat.
        socket.serverEventCallback?(
            "private-superchat", superchat(moderator, enable: false, player: otherPlayer)
        )
        XCTAssertEqual(service.superchatCover?.isOn, true)
    }

    func testSuperusersAreExemptButAdminsAndModeratorsAreNot() throws {
        let roles: [(name: String, isSuperuser: Bool?, uiClass: String?, isModerator: Bool?, isCovered: Bool)] = [
            ("is_superuser", true, nil, nil, false),
            ("ui_class admin", nil, "admin", nil, true),
            ("is_moderator", nil, nil, true, true),
            ("is_superuser false", false, nil, nil, true),
        ]
        for role in roles {
            let (store, _) = makeSuperchatStore()
            let (service, socket) = try makeSuperchatWindow(
                userID: superchatPlayer, store: store, isSuperuser: role.isSuperuser,
                uiClass: role.uiClass, isModerator: role.isModerator, label: "superchat-role"
            )
            XCTAssertEqual(service.user?.isSuperuser, role.isSuperuser, role.name)
            if role.uiClass != nil { XCTAssertEqual(service.user?.isOGSAdmin, true, role.name) }
            if role.isModerator == true { XCTAssertEqual(service.user?.isOGSModerator, true, role.name) }

            socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
            XCTAssertEqual(store.covers[superchatPlayer] != nil, role.isCovered, role.name)
            XCTAssertEqual(service.superchatCover?.isOn == true, role.isCovered, role.name)
            XCTAssertEqual(
                socket.loadedConversations, [moderator], "\(role.name): the conversation still loads into Messages."
            )
        }
    }

    func testAnEventFromASocketOfAnotherAccountIsIgnored() throws {
        let (store, scheduler) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-socket-account"
        )
        // The socket still speaks for another account, or for none while it's down.
        let identities: [Int?] = [otherPlayer, nil]
        for identity in identities {
            socket.authenticatedUserID = identity
            XCTAssertNil(service.superchatAccountID, "\(String(describing: identity))")
            socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
            socket.serverEventCallback?("private-superchat", superchat(moderator, player: nil))
        }
        XCTAssertTrue(store.covers.isEmpty)
        XCTAssertNil(service.superchatCover)
        XCTAssertEqual(socket.loadedConversations, [])

        socket.authenticatedUserID = superchatPlayer
        XCTAssertEqual(service.superchatAccountID, superchatPlayer)
        socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        XCTAssertEqual(service.superchatCover?.isOn, true)

        // Nor can such a socket's authentication lift the cover.
        socket.authenticatedUserID = otherPlayer
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        socket.serverEventCallback?(
            "surround/socketAuthenticationAnswered",
            OGSWebsocketAuthenticationAnswer(userID: otherPlayer, outcome: .confirmed)
        )
        XCTAssertEqual(scheduler.pendingDelays, [], "No wait opened.")
        scheduler.advance()
        XCTAssertEqual(service.superchatCover?.isOn, true)
    }

    func testAStaleWindowNeitherCoversNorLiftsButIsCovered() throws {
        let saved = makeSuperchatPreferences(label: "superchat-stale-saved")
        let (store, scheduler) = makeSuperchatStore(preferences: saved)
        let (first, firstSocket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-stale"
        )
        let (stale, staleSocket) = try makeSuperchatWindow(userID: superchatPlayer, store: store, sharing: first)
        let (third, thirdSocket) = try makeSuperchatWindow(userID: superchatPlayer, store: store, sharing: first)

        // Before the switch, windows 2 and 3 wait for the first account's
        // re-send. OGS answered window 2, so its deadline runs; it didn't
        // answer window 3, whose deadline starts at its next pong.
        firstSocket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        let firstCover = try XCTUnwrap(store.covers[superchatPlayer])
        func authenticate(_ socket: StubWebsocket, answered outcome: OGSWebsocketAuthenticationAnswer.Outcome) {
            socket.serverEventCallback?("surround/socketAuthenticated", nil)
            socket.serverEventCallback?(
                "surround/socketAuthenticationAnswered",
                OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: outcome)
            )
        }
        authenticate(staleSocket, answered: .confirmed)
        authenticate(thirdSocket, answered: .unanswered)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])

        // Window 1 signs in as another account; windows 2 and 3 keep the first one.
        try signInForPrivateMessageTest(first, userID: otherPlayer)
        firstSocket.authenticatedUserID = otherPlayer
        drainMainQueue()
        XCTAssertEqual(stale.user?.id, superchatPlayer)
        XCTAssertEqual(stale.superchatCoverAccountID, otherPlayer, "Its cover follows the stored sign-in.")
        XCTAssertNil(stale.superchatAccountID, "It hears for no account.")

        // So they drop the first account's re-send, and the change ended both
        // waits: no deadline runs or starts, and that account keeps its cover.
        XCTAssertEqual(scheduler.pendingDelays, [], "The change ended window 2's wait.")
        for socket in [staleSocket, thirdSocket] {
            socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
            socket.serverEventCallback?("net/pong", pong)
        }
        XCTAssertEqual(scheduler.pendingDelays, [], "Window 3's pong started nothing.")
        scheduler.advance()
        XCTAssertEqual(store.covers, [superchatPlayer: firstCover], "Nothing lifted the first account's cover.")
        XCTAssertEqual(saved[.superchatModeratorsByOGSAccountID], [superchatPlayer: firstCover.moderators])

        firstSocket.serverEventCallback?("private-superchat", superchat(moderator, player: otherPlayer))
        let cover = try XCTUnwrap(store.covers[otherPlayer])
        XCTAssertEqual(first.superchatCover, cover)
        XCTAssertEqual(stale.superchatCover, cover, "The stale window is covered.")

        // Window 2's socket hears superchats as its own account, or as the
        // stored one after reconnecting with the shared sign-in. None of
        // them counts, and its authentications open no wait.
        for identity in [superchatPlayer, otherPlayer] {
            staleSocket.authenticatedUserID = identity
            staleSocket.serverEventCallback?("private-superchat", superchat(secondModerator, player: identity))
            staleSocket.serverEventCallback?(
                "private-superchat", superchat(moderator, enable: false, player: identity)
            )
            staleSocket.serverEventCallback?("surround/socketAuthenticated", nil)
            staleSocket.serverEventCallback?(
                "surround/socketAuthenticationAnswered",
                OGSWebsocketAuthenticationAnswer(userID: identity, outcome: .confirmed)
            )
            staleSocket.serverEventCallback?("net/pong", pong)
        }
        XCTAssertEqual(
            store.covers, [superchatPlayer: firstCover, otherPlayer: cover], "Window 2's events changed nothing."
        )
        XCTAssertTrue(store.endings.isEmpty)
        XCTAssertEqual(scheduler.pendingDelays, [], "Its authentications opened no wait.")
        scheduler.advance()
        XCTAssertEqual(stale.superchatCover, cover, "So nothing lifts.")

        // A live end heard by window 1 gives windows 2 and 3 Done.
        firstSocket.serverEventCallback?(
            "private-superchat", superchat(moderator, enable: false, player: otherPlayer)
        )
        for window in [stale, third] {
            XCTAssertEqual(window.superchatCover?.awaitsDone, true)
            XCTAssertEqual(window.superchatEndings, [moderator: SuperchatEnding(at: 1_000, wasMissed: false)])
        }
    }

    func testSocketLifecycleOpensAnswersAndCancelsWaits() throws {
        let (store, scheduler) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-lifecycle"
        )
        let window = SuperchatStore.resendWindow
        func event(_ name: String, _ data: Any? = nil) { socket.serverEventCallback?(name, data) }
        func answer(_ outcome: OGSWebsocketAuthenticationAnswer.Outcome, for userID: Int? = nil) {
            event(
                "surround/socketAuthenticationAnswered",
                OGSWebsocketAuthenticationAnswer(userID: userID ?? superchatPlayer, outcome: outcome)
            )
        }
        event("private-superchat", superchat(moderator, player: superchatPlayer))

        // Authenticated: a wait opens, and OGS's answer starts its deadline.
        event("surround/socketAuthenticated")
        XCTAssertEqual(scheduler.pendingDelays, [], "No deadline before OGS answers.")
        answer(.confirmed, for: otherPlayer)
        XCTAssertEqual(scheduler.pendingDelays, [], "An answer for another identity starts nothing.")
        answer(.confirmed)
        XCTAssertEqual(scheduler.pendingDelays, [window])
        // Closed: the wait is cancelled, so its deadline lifts nothing.
        event("surround/socketClosed")
        XCTAssertEqual(scheduler.pendingDelays, [])
        scheduler.advance()
        XCTAssertEqual(service.superchatCover?.isOn, true)

        // Rejected: the wait closes, and no ping starts a deadline.
        event("surround/socketAuthenticated")
        answer(.rejected)
        event("net/pong", pong)
        XCTAssertEqual(scheduler.pendingDelays, [])

        // Unanswered after a ping: the deadline starts at the timeout.
        event("surround/socketAuthenticated")
        event("net/pong", pong)
        XCTAssertEqual(scheduler.pendingDelays, [], "A ping alone starts nothing.")
        answer(.unanswered)
        XCTAssertEqual(scheduler.pendingDelays, [window])
        event("surround/socketClosed")
        XCTAssertEqual(scheduler.pendingDelays, [])

        // Unanswered before any ping: the deadline starts at the next pong.
        event("surround/socketAuthenticated")
        answer(.unanswered)
        XCTAssertEqual(scheduler.pendingDelays, [])
        event("net/pong", pong)
        XCTAssertEqual(scheduler.pendingDelays, [window])
        scheduler.advance()
        XCTAssertNil(service.superchatCover, "No re-send: the cover lifted by itself.")
        XCTAssertEqual(service.superchatEndings, [moderator: SuperchatEnding(at: 1_000, wasMissed: true)])
    }

    func testAWaitThroughTheBackgroundLiftsAtAPingAfterTheReturn() throws {
        let (store, scheduler) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-background"
        )
        socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        socket.serverEventCallback?(
            "surround/socketAuthenticationAnswered",
            OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: .confirmed)
        )
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])

        // The app leaves and comes back before the system suspends it: the
        // socket stays open, so it never authenticates again.
        store.enterBackground()
        store.enterForeground()
        XCTAssertEqual(scheduler.pendingDelays, [], "The deadline waits for a ping after the return.")
        socket.serverEventCallback?("net/pong", pong)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])
        scheduler.advance()
        XCTAssertNil(service.superchatCover, "No re-send came: the cover lifted by itself.")
        XCTAssertEqual(service.superchatEndings, [moderator: SuperchatEnding(at: 1_000, wasMissed: true)])
    }

    func testAnEndIsTimedByOGSClockForTheEndedLine() throws {
        let (store, _) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-ended-line"
        )
        // The device's clock reads 1_000 s, and a pong puts OGS's 5 s ahead.
        socket.serverEventCallback?(
            "net/pong", ["client": 1_000_000 as NSNumber, "server": 1_005_000 as NSNumber]
        )
        XCTAssertEqual(socket.drift, -5_000)
        socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        // The moderator's last message, which OGS stamped 2 s before the end.
        service.handlePrivateMessage(
            privateMessage(from: moderator, to: superchatPlayer, id: "last", timestamp: 1_003)
        )
        socket.serverEventCallback?("private-superchat", superchat(moderator, enable: false, player: superchatPlayer))
        XCTAssertEqual(service.superchatEndings, [moderator: SuperchatEnding(at: 1_005, wasMissed: false)])
        XCTAssertTrue(service.showsSuperchatEndedLine(peerID: moderator), "The last message came before the end.")
        service.handlePrivateMessage(
            privateMessage(from: superchatPlayer, to: moderator, id: "reply", timestamp: 1_010)
        )
        XCTAssertFalse(service.showsSuperchatEndedLine(peerID: moderator), "A message after the end hides the line.")

        // An end is never before the conversation's newest message, even
        // where OGS stamped it later than the pong's estimate of its clock.
        socket.serverEventCallback?("private-superchat", superchat(secondModerator, player: superchatPlayer))
        service.handlePrivateMessage(
            privateMessage(from: secondModerator, to: superchatPlayer, id: "second-last", timestamp: 1_009)
        )
        socket.serverEventCallback?(
            "private-superchat", superchat(secondModerator, enable: false, player: superchatPlayer)
        )
        XCTAssertEqual(service.superchatEndings[secondModerator], SuperchatEnding(at: 1_009, wasMissed: false))
        XCTAssertTrue(service.showsSuperchatEndedLine(peerID: secondModerator))
    }

    func testAMissedEndIsTimedByOGSClockForTheEndedLine() throws {
        // The device's clock, which the store and the window share, runs
        // 5 s ahead of OGS's.
        final class Clock { var now: TimeInterval = 1_005 }
        let clock = Clock()
        let (store, scheduler) = makeSuperchatStore(now: { clock.now })
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-missed-end-line", currentTime: { clock.now }
        )
        socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        service.handlePrivateMessage(
            privateMessage(from: moderator, to: superchatPlayer, id: "history", timestamp: 990)
        )

        // A reconnect at OGS's 1_000: OGS confirms it, and its first pong
        // gives a drift of 5 s. No re-send comes.
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        socket.serverEventCallback?(
            "surround/socketAuthenticationAnswered",
            OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: .confirmed)
        )
        socket.serverEventCallback?(
            "net/pong", ["client": 1_005_000 as NSNumber, "server": 1_000_000 as NSNumber]
        )
        XCTAssertEqual(socket.drift, 5_000)

        // The wait runs out at the device's 1_015, OGS's 1_010.
        clock.now = 1_015
        scheduler.advance()
        XCTAssertNil(service.superchatCover, "No re-send came: the cover lifted by itself.")
        XCTAssertEqual(service.superchatEndings, [moderator: SuperchatEnding(at: 1_010, wasMissed: true)])
        XCTAssertTrue(service.showsSuperchatEndedLine(peerID: moderator), "The history came before the end.")
        service.handlePrivateMessage(
            privateMessage(from: moderator, to: superchatPlayer, id: "after", timestamp: 1_011)
        )
        XCTAssertFalse(service.showsSuperchatEndedLine(peerID: moderator), "A message after the end hides the line.")
    }

    func testTheModeratorsNameComesFromTheEvent() throws {
        let (store, _) = makeSuperchatStore()
        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-name"
        )
        XCTAssertNil(service.cachedUsersById[moderator], "No profile of the moderator is cached.")

        socket.serverEventCallback?(
            "private-superchat", superchat(moderator, player: superchatPlayer, username: "moderator-name")
        )
        XCTAssertEqual(store.covers[superchatPlayer]?.moderators.map(\.username), ["moderator-name"])
        XCTAssertEqual(service.superchatCover?.moderators.map(\.username), ["moderator-name"])
        XCTAssertNil(service.cachedUsersById[moderator], "The name came from the event alone.")
    }

    func testAccountChangesKeepEachAccountsCover() throws {
        let (store, scheduler) = makeSuperchatStore()
        let (first, firstSocket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-accounts"
        )
        let (second, _) = try makeSuperchatWindow(userID: superchatPlayer, store: store, sharing: first)
        firstSocket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        let firstCover = try XCTUnwrap(store.covers[superchatPlayer])
        // Window 1's connection waits for the first account's re-send.
        firstSocket.serverEventCallback?("surround/socketAuthenticated", nil)
        firstSocket.serverEventCallback?(
            "surround/socketAuthenticationAnswered",
            OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: .confirmed)
        )
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])

        // Window 1 signs in as another account. Its reset leaves the first
        // account's cover in the store, and each window follows the new sign-in.
        try signInForPrivateMessageTest(first, userID: otherPlayer)
        firstSocket.authenticatedUserID = otherPlayer
        XCTAssertEqual(scheduler.pendingDelays, [], "The switch ended the first account's wait before reconnecting.")
        scheduler.advance()
        XCTAssertEqual(store.covers, [superchatPlayer: firstCover])
        XCTAssertNil(first.superchatCover, "The new account has no cover.")
        drainMainQueue()
        XCTAssertNil(second.superchatCover, "The change reached window 2 too.")

        firstSocket.serverEventCallback?("private-superchat", superchat(secondModerator, player: otherPlayer))
        let secondCover = try XCTUnwrap(store.covers[otherPlayer])
        XCTAssertEqual(store.covers, [superchatPlayer: firstCover, otherPlayer: secondCover])
        XCTAssertEqual(first.superchatCover, secondCover)
        XCTAssertEqual(second.superchatCover, secondCover)

        // Back to the first account: its cover is still there, in both windows.
        try signInForPrivateMessageTest(first, userID: superchatPlayer)
        firstSocket.authenticatedUserID = superchatPlayer
        drainMainQueue()
        XCTAssertEqual(first.superchatCover, firstCover)
        XCTAssertEqual(second.superchatCover, firstCover)
        XCTAssertEqual(store.covers, [superchatPlayer: firstCover, otherPlayer: secondCover])
    }

    func testASignedOutWindowIsCoveredOnceAnotherWindowSignsIn() throws {
        let (store, _) = makeSuperchatStore()
        let (first, firstSocket) = try makeSuperchatWindow(userID: nil, store: store, label: "superchat-signed-out")
        let (second, _) = try makeSuperchatWindow(userID: nil, store: store, sharing: first)
        XCTAssertFalse(first.isLoggedIn)
        XCTAssertFalse(second.isLoggedIn)
        XCTAssertNil(second.superchatCoverAccountID)

        // Window 1 signs in. Window 2 hasn't checked its own sign-in since,
        // but its cover follows the stored one, which it hears for no account.
        try signInForPrivateMessageTest(first, userID: superchatPlayer)
        firstSocket.authenticatedUserID = superchatPlayer
        drainMainQueue()
        XCTAssertFalse(second.isLoggedIn)
        XCTAssertEqual(second.superchatCoverAccountID, superchatPlayer)
        XCTAssertNil(second.superchatAccountID)

        firstSocket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
        let cover = try XCTUnwrap(store.covers[superchatPlayer])
        XCTAssertEqual(first.superchatCover, cover)
        XCTAssertEqual(second.superchatCover, cover, "The signed-out window is covered too.")
        let presentation = try XCTUnwrap(SuperchatCoverPresentation(
            cover: cover, selectedModeratorID: nil, windowUserID: second.user?.id, accountID: superchatPlayer
        ))
        XCTAssertTrue(presentation.isStale, "It shows the header and the end card, not the conversation.")
        XCTAssertFalse(presentation.showsReplyField)
        XCTAssertFalse(presentation.showsLiveGames)

        // Window 1 signs out: with no stored sign-in, neither window is covered.
        first.logout()
        drainMainQueue()
        XCTAssertNil(first.superchatCover)
        XCTAssertNil(second.superchatCover, "The sign-out reached window 2 too.")
        XCTAssertEqual(store.covers[superchatPlayer], cover, "The account's cover waits for its next sign-in.")
    }

    func testAServiceThatGoesAwayEndsItsWait() throws {
        let (store, scheduler) = makeSuperchatStore()
        weak var released: OGSService?
        do {
            let (service, socket) = try makeSuperchatWindow(
                userID: superchatPlayer, store: store, label: "superchat-released"
            )
            released = service
            socket.serverEventCallback?("private-superchat", superchat(moderator, player: superchatPlayer))
            socket.serverEventCallback?("surround/socketAuthenticated", nil)
            socket.serverEventCallback?(
                "surround/socketAuthenticationAnswered",
                OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: .confirmed)
            )
            XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow], "A confirmed wait.")
        }
        XCTAssertNil(released, "The window's service went away.")
        XCTAssertEqual(scheduler.pendingDelays, [], "Its deinit ended the wait.")
        scheduler.advance()
        XCTAssertEqual(store.covers[superchatPlayer]?.isOn, true, "The deadline lifts nothing.")
    }

    func testEachAuthenticationAsksForEveryModeratorStillOn() throws {
        // What a relaunch restores: a superchat still on, saved by an earlier
        // launch, from a moderator this window never loaded (no messages and
        // no recent-peer entry). Another moderator's superchat started and
        // ended live since.
        let saved = makeSuperchatPreferences(label: "superchat-saved")
        let (earlier, _) = makeSuperchatStore(preferences: saved)
        earlier.receive(enable: true, moderatorID: moderator, username: "moderator", accountID: superchatPlayer)
        let (store, scheduler) = makeSuperchatStore(preferences: saved)
        store.receive(enable: true, moderatorID: secondModerator, username: "second", accountID: superchatPlayer)
        store.receive(enable: false, moderatorID: secondModerator, username: nil, accountID: superchatPlayer)
        XCTAssertEqual(store.covers[superchatPlayer]?.moderators.map(\.id), [secondModerator, moderator])
        XCTAssertEqual(store.covers[superchatPlayer]?.moderators.map(\.isOn), [false, true])

        let (service, socket) = try makeSuperchatWindow(
            userID: superchatPlayer, store: store, label: "superchat-asks"
        )
        XCTAssertTrue(service.privateMessagesActivePeerIds.isEmpty)
        XCTAssertNil(service.preferences[.recentPrivateMessagePeerIDsByOGSAccountID]?[superchatPlayer])
        socket.resetEmittedCommands()

        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        XCTAssertEqual(socket.loadedConversations, [moderator], "Only the moderator still on is asked for.")
        XCTAssertEqual(service.privateMessagesActivePeerIds, [moderator], "Its thread waits for the replay.")

        // The request leaves before the wait opens. A connection that
        // authenticates again without closing first (connect() on an open
        // socket) shows it: its request still finds the earlier wait's
        // deadline, which opening the new wait cancels.
        socket.serverEventCallback?(
            "surround/socketAuthenticationAnswered",
            OGSWebsocketAuthenticationAnswer(userID: superchatPlayer, outcome: .confirmed)
        )
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])
        let moderatorID = moderator
        var deadlinesAtRequest: [TimeInterval]?
        socket.onEmit = { command, playerID in
            if command == "chat/pm/load", playerID == moderatorID { deadlinesAtRequest = scheduler.pendingDelays }
        }
        socket.resetEmittedCommands()
        socket.serverEventCallback?("surround/socketAuthenticated", nil)
        socket.onEmit = nil
        XCTAssertEqual(socket.loadedConversations, [moderator])
        XCTAssertEqual(deadlinesAtRequest, [SuperchatStore.resendWindow], "The request left first,")
        XCTAssertEqual(scheduler.pendingDelays, [], "then the new wait opened.")
    }

    func testSubmitMoveWithoutGameDataFailsInsteadOfHanging() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let service = makeService(
            environment: environment,
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "move"
        )
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(42))
        let completed = expectation(description: "publisher completed")
        var receivedError: Error?

        service.submitMove(move: .pass, forGame: game)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    completed.fulfill()
                },
                receiveValue: { XCTFail("A move without game data must not succeed") }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 1)
        XCTAssertNotNil(receivedError)
    }

    func testToggleRemovedStonesWithoutGameDataFailsInsteadOfHanging() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let service = makeService(
            environment: environment,
            httpClient: makeHTTPClient(responseUsername: "unused"),
            label: "stones"
        )
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(43))
        let completed = expectation(description: "publisher completed")
        var receivedError: Error?

        service.toggleRemovedStones(stones: [[0, 0]], forGame: game)
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    completed.fulfill()
                },
                receiveValue: { XCTFail("Stone removal without game data must not succeed") }
            )
            .store(in: &cancellables)

        wait(for: [completed], timeout: 1)
        XCTAssertNotNil(receivedError)
    }

    func testFailedAccountSwitchClearsThePreviousIdentity() {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: "player-one")
        let socket = StubWebsocket()
        let service = makeService(
            environment: environment,
            httpClient: httpClient,
            socket: socket,
            label: "failed-switch"
        )
        let firstLogin = expectation(description: "initial login")
        service.login(username: "player-one", password: "not-logged")
            .sink(
                receiveCompletion: { _ in firstLogin.fulfill() },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        wait(for: [firstLogin], timeout: 5)
        XCTAssertTrue(service.isLoggedIn)

        StubURLProtocol.lock.lock()
        StubURLProtocol.rejectedUsernames.insert("player-one")
        StubURLProtocol.lock.unlock()

        let rejectedLogin = expectation(description: "rejected login")
        var receivedError: Error?
        service.login(username: "another-player", password: "not-logged")
            .sink(
                receiveCompletion: {
                    if case .failure(let error) = $0 { receivedError = error }
                    rejectedLogin.fulfill()
                },
                receiveValue: { _ in XCTFail("Rejected credentials must not produce a config") }
            )
            .store(in: &cancellables)
        wait(for: [rejectedLogin], timeout: 5)

        XCTAssertNotNil(receivedError)
        XCTAssertFalse(service.isLoggedIn)
        XCTAssertNil(service.user)
        XCTAssertNil(service.ogsUIConfig)
        XCTAssertNil(cookie(named: "sessionid", in: httpClient.cookieStorage))
        XCTAssertNil(socket.authenticationConfigProvider())
        XCTAssertEqual(socket.reconnectCount, 2)
    }

    func testCachedOverviewGameDecodesWidgetSourceSnapshot() throws {
        let gameID = 845_001
        let detail = try makeFinishedGameDetail(gameID: gameID)
        let gameJSON = try XCTUnwrap(
            detail.rawData["gamedata"] as? [String: Any]
        )
        let service = makeService(
            environment: .production,
            httpClient: makeHTTPClient(responseUsername: "overview-cache"),
            label: "overview-cache"
        )
        service.preferences[.latestOGSOverview] = try JSONSerialization.data(
            withJSONObject: [
                "active_games": [["json": gameJSON]],
            ]
        )

        let game = try XCTUnwrap(
            service.cachedOverviewGame(gameID: gameID)
        )
        XCTAssertEqual(game.ogsID, gameID)
        XCTAssertTrue(game.ogs === service)
        XCTAssertNil(service.cachedOverviewGame(gameID: gameID + 1))
    }

    func testCachedOverviewGameRejectsMalformedOrNonpositiveRequests() {
        let service = makeService(
            environment: .production,
            httpClient: makeHTTPClient(responseUsername: "bad-overview-cache"),
            label: "bad-overview-cache"
        )
        service.preferences[.latestOGSOverview] = Data("not-json".utf8)

        XCTAssertNil(service.cachedOverviewGame(gameID: 1))
        XCTAssertNil(service.cachedOverviewGame(gameID: 0))
        XCTAssertNil(service.cachedOverviewGame(gameID: -1))
    }

    private func makeHTTPClient(responseUsername: String) -> AlamofireOGSHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        let storage = configuration.httpCookieStorage!
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = ["X-Surround-Test-Username": responseUsername]
        StubURLProtocol.lock.lock()
        StubURLProtocol.cookieStorageByUsername[responseUsername] = storage
        StubURLProtocol.lock.unlock()
        return AlamofireOGSHTTPClient(
            session: Session(configuration: configuration),
            cookieStorage: storage
        )
    }

    private func makeHistoryResult(
        id: Int,
        blackID: Int,
        whiteID: Int
    ) -> [String: Any] {
        [
            "id": id,
            "width": 9,
            "height": 9,
            "players": [
                "black": ["id": blackID, "username": "black-\(blackID)"],
                "white": ["id": whiteID, "username": "white-\(whiteID)"],
            ],
        ]
    }

    private func makeHistoryGame(id: Int) -> Game {
        Game(
            width: 9,
            height: 9,
            blackName: "black-\(id)",
            whiteName: "white-\(id)",
            gameId: .OGS(id)
        )
    }

    private func installGameDetailResponse(gameID: Int) throws -> OGSGame {
        let detail = try makeFinishedGameDetail(gameID: gameID)
        let responseBody = try JSONSerialization.data(withJSONObject: detail.rawData)

        StubURLProtocol.lock.lock()
        StubURLProtocol.gameDetailBody = responseBody
        StubURLProtocol.lock.unlock()

        return detail.ogsGame
    }

    private func makeFinishedGameDetail(
        gameID: Int,
        modifyingGameData: (inout [String: Any]) -> Void = { _ in }
    ) throws -> FinishedGameDetail {
        let bundle = Bundle(for: Self.self)
        let fixtureURL = try XCTUnwrap(
            bundle.url(forResource: "game-25076729", withExtension: "json")
        )
        var gameData = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        gameData["game_id"] = gameID
        modifyingGameData(&gameData)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try decoder.decode(
            OGSGame.self,
            from: JSONSerialization.data(withJSONObject: gameData)
        )
        return FinishedGameDetail(
            ogsGame: ogsGame,
            rawData: ["gamedata": gameData]
        )
    }

    private func makeUser(
        id: Int,
        username: String,
        ranking: Double
    ) throws -> OGSUser {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "username": username,
            "ranking": ranking,
        ])
        return try JSONDecoder().decode(OGSUser.self, from: data)
    }

    /// `ui/config` for `userID`. The role options add OGS's role fields to its
    /// user: `is_superuser`, `ui_class` and `is_moderator`.
    private func makeUIConfig(
        jwt: String, userID: Int, isSuperuser: Bool? = nil, uiClass: String? = nil, isModerator: Bool? = nil
    ) throws -> OGSUIConfig {
        var user: [String: Any] = [
            "username": "player-\(userID)",
            "id": userID,
            "anonymous": false,
        ]
        if let isSuperuser { user["is_superuser"] = isSuperuser }
        if let uiClass { user["ui_class"] = uiClass }
        if let isModerator { user["is_moderator"] = isModerator }
        let data = try JSONSerialization.data(withJSONObject: [
            "csrf_token": "test-csrf",
            "user_jwt": jwt,
            "user": user,
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSUIConfig.self, from: data)
    }

    private func signInForPrivateMessageTest(
        _ service: OGSService, userID: Int,
        isSuperuser: Bool? = nil, uiClass: String? = nil, isModerator: Bool? = nil
    ) throws {
        service.preferences[.ogsSessionId] = "test-session-\(userID)"
        service.ogsUIConfig = try makeUIConfig(
            jwt: "test-jwt-\(userID)", userID: userID,
            isSuperuser: isSuperuser, uiClass: uiClass, isModerator: isModerator
        )
        XCTAssertEqual(service.user?.id, userID)
    }

    private func privateMessage(
        from senderID: Int, to recipientID: Int, id: String, timestamp: Double
    ) -> OGSPrivateMessage {
        OGSPrivateMessage(
            from: OGSUser(username: "player-\(senderID)", id: senderID),
            to: OGSUser(username: "player-\(recipientID)", id: recipientID),
            content: OGSPrivateMessageContent(id: id, message: id, timestamp: timestamp)
        )
    }

    private func privateMessagePayload(from senderID: Int, to recipientID: Int, id: String) -> [String: Any] {
        [
            "from": ["id": senderID, "username": "player-\(senderID)"],
            "to": ["id": recipientID, "username": "player-\(recipientID)"],
            "message": ["i": id, "m": id, "t": 100.0],
        ]
    }

    // MARK: Superchat helpers

    private let superchatPlayer = 101
    private let otherPlayer = 202
    private let moderator = 301
    private let secondModerator = 302
    /// A `net/pong` the service accepts as a clock sample: on a superchat
    /// window's clock, OGS's agrees with the device's.
    private let pong: [String: Any] = ["client": 1_000_000 as NSNumber, "server": 1_000_000 as NSNumber]

    /// A superchat store of the test's own, on a manual scheduler and a
    /// clock, by default a fixed one that superchat windows share.
    private func makeSuperchatStore(
        preferences: UserDefaults? = nil, now: @escaping () -> TimeInterval = { 1_000 }
    ) -> (SuperchatStore, ManualScheduler) {
        let scheduler = ManualScheduler()
        return (SuperchatStore(preferences: preferences, scheduler: scheduler, now: now), scheduler)
    }

    /// A throwaway suite for what a superchat store saves.
    private func makeSuperchatPreferences(label: String) -> UserDefaults {
        let suite = "com.honganhkhoa.Surround.IsolationTests.\(label).\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    /// One window of the app, signed in as `userID` on a socket that
    /// authenticated as it, or signed out without one, and reporting to
    /// `store`. Its clock reads 1_000 s by default, as the store's does. A
    /// window made `sharing` another uses its preferences, so the two share
    /// the stored sign-in, as the app's windows do.
    private func makeSuperchatWindow(
        userID: Int?, store: SuperchatStore, sharing other: OGSService? = nil,
        isSuperuser: Bool? = nil, uiClass: String? = nil, isModerator: Bool? = nil,
        label: String = "superchat-window", currentTime clock: @escaping () -> TimeInterval = { 1_000 }
    ) throws -> (OGSService, StubWebsocket) {
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        let httpClient = makeHTTPClient(responseUsername: label)
        let socket = StubWebsocket()
        let service: OGSService
        if let other {
            service = OGSService(
                environment: environment,
                httpClient: httpClient,
                preferences: other.preferences,
                ogsWebsocket: socket,
                connectsAutomatically: false,
                usesSurroundOverviewService: false,
                enablesAppSideEffects: false,
                startsTimers: false,
                installsObservers: false,
                currentTime: clock
            )
        } else {
            service = makeService(
                environment: environment, httpClient: httpClient, socket: socket, label: label, currentTime: clock
            )
        }
        if let userID {
            try signInForPrivateMessageTest(
                service, userID: userID, isSuperuser: isSuperuser, uiClass: uiClass, isModerator: isModerator
            )
        }
        socket.authenticatedUserID = userID
        service.superchatStore = store
        return (service, socket)
    }

    /// OGS's `private-superchat` (Goban ServerToClient.ts:348-365). A nil
    /// `player` leaves out `player_id`.
    private func superchat(
        _ moderatorID: Int, enable: Bool = true, player: Int?, username: String = "moderator"
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "moderator_id": moderatorID, "moderator_username": username, "enable": enable,
        ]
        if let player {
            payload["player_id"] = player
            payload["player_username"] = "player-\(player)"
        }
        return payload
    }

    /// Lets the main queue run what is already on it, such as another
    /// window's account-change broadcast.
    private func drainMainQueue() {
        let drained = expectation(description: "the main queue ran its earlier work")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private func makeService(
        environment: OGSEnvironment,
        httpClient: AlamofireOGSHTTPClient,
        socket: OGSWebsocketProtocol = StubWebsocket(),
        label: String,
        currentTime: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) -> OGSService {
        let suite = "com.honganhkhoa.Surround.IsolationTests.\(label).\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: environment,
            httpClient: httpClient,
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false,
            currentTime: currentTime
        )
    }

    private func cookie(named name: String, in storage: HTTPCookieStorage?) -> String? {
        storage?.cookies?.first { $0.name == name }?.value
    }
}
