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
        private(set) var reconnectCount = 0
        private(set) var emittedCommands = [String]()
        var nextCallbackError: [String: String]?
        var defersPrivateMessageAcknowledgements = false
        private(set) var privateMessageCallbacks = [OGSWebsocketResultCallback]()

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() { reconnectCount += 1 }

        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            emittedCommands.append(command)
            if command == "chat/pm", defersPrivateMessageAcknowledgements, let resultCallback {
                privateMessageCallbacks.append(resultCallback)
                return
            }
            resultCallback?(nil, nextCallbackError)
            nextCallbackError = nil
        }

        func resetEmittedCommands() {
            emittedCommands.removeAll()
        }

        func acknowledgeNextPrivateMessage(with data: [String: Any]) {
            let callback = privateMessageCallbacks.removeFirst()
            callback(data, nil)
        }
    }

    private final class StubURLProtocol: URLProtocol {
        static let lock = NSLock()
        static var requests = [URLRequest]()
        static var cookieStorageByUsername = [String: HTTPCookieStorage]()
        static var rejectedUsernames = Set<String>()
        static var gameDetailBody: Data?
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
                body = Self.gameDetailBody ?? Data("{}".utf8)
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
        XCTAssertEqual(game.whitePlayer?.username, listedWhite.username)
        XCTAssertEqual(game.whitePlayer?.ranking, listedWhite.ranking)
        XCTAssertEqual(game.gameData?.gameId, 731)
        XCTAssertEqual(
            game.currentPosition.lastMoveNumber,
            detail.ogsGame.moves.count
        )
        XCTAssertNotNil(game.ogsRawData)
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

    private func makeFinishedGameDetail(gameID: Int) throws -> FinishedGameDetail {
        let bundle = Bundle(for: Self.self)
        let fixtureURL = try XCTUnwrap(
            bundle.url(forResource: "game-25076729", withExtension: "json")
        )
        var gameData = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        gameData["game_id"] = gameID
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

    private func signInForPrivateMessageTest(_ service: OGSService, userID: Int) throws {
        service.preferences[.ogsSessionId] = "test-session-\(userID)"
        service.ogsUIConfig = try makeUIConfig(jwt: "test-jwt-\(userID)", userID: userID)
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

    private func makeService(
        environment: OGSEnvironment,
        httpClient: AlamofireOGSHTTPClient,
        socket: OGSWebsocketProtocol = StubWebsocket(),
        label: String
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
            installsObservers: false
        )
    }

    private func cookie(named name: String, in storage: HTTPCookieStorage?) -> String? {
        storage?.cookies?.first { $0.name == name }?.value
    }
}
