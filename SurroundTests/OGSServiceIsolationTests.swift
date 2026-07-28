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

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() { reconnectCount += 1 }

        func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
            emittedCommands.append(command)
            resultCallback?(nil, nil)
        }

        func resetEmittedCommands() {
            emittedCommands.removeAll()
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
        static var gameHistoryBody: Data?

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
                let gate = Self.gameDetailGate
                let started = Self.gameDetailStarted
                Self.lock.unlock()
                started?()
                gate?.wait()
            default:
                body = Data("{}".utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
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

    func testTwoLoginsKeepCookiesPreferencesAndUsersIsolated() throws {
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

        wait(for: [firstLogin, secondLogin], timeout: 5)
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

        StubURLProtocol.lock.lock()
        let loginRequests = StubURLProtocol.requests.filter { $0.url?.path == "/api/v0/login" }
        StubURLProtocol.lock.unlock()
        XCTAssertEqual(loginRequests.count, 2)
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
            startsTimers: false
        )
    }

    private func cookie(named name: String, in storage: HTTPCookieStorage?) -> String? {
        storage?.cookies?.first { $0.name == name }?.value
    }
}
