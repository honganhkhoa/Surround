//
//  OGSPlayerProfileTests.swift
//  SurroundTests
//

import Alamofire
import Combine
import XCTest

final class OGSPlayerProfileTests: XCTestCase {
    private final class ProfileURLProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var handler: ((ProfileURLProtocol) -> Void)?
        private static var stopped: (() -> Void)?
        private static var requests: [URLRequest] = []

        static func configure(
            handler: ((ProfileURLProtocol) -> Void)?,
            stopped: (() -> Void)? = nil
        ) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
            self.stopped = stopped
            requests = []
        }

        static var recordedRequests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            let handler = Self.handler
            Self.lock.unlock()
            if let handler {
                handler(self)
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            }
        }

        override func stopLoading() {
            Self.lock.lock()
            let stopped = Self.stopped
            Self.lock.unlock()
            stopped?()
        }

        func respond(_ body: String, statusCode: Int = 200) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var preferenceSuites: [String] = []

    override func setUp() {
        super.setUp()
        ProfileURLProtocol.configure(handler: nil)
    }

    override func tearDown() {
        cancellables.removeAll()
        ProfileURLProtocol.configure(handler: nil)
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    func testSparseProfileDoesNotInventOptionalIdentityDetails() throws {
        for json in [
            #"{"user":{"id":42,"username":"player"}}"#,
            #"{"user":{"id":42,"username":"player","about":null,"country":null,"registration_date":null}}"#,
        ] {
            let profile = try decode(json)
            XCTAssertEqual(profile.id, 42)
            XCTAssertEqual(profile.user.username, "player")
            XCTAssertNil(profile.user.country)
            XCTAssertNil(profile.about)
            XCTAssertNil(profile.registrationDate)
        }
    }

    func testProfileDecodesNestedSnakeCaseFieldsAndBothTimestampPrecisions() throws {
        for dateString in ["2019-03-01T12:30:00Z", "2019-03-01T12:30:00.000Z"] {
            let profile = try decode("""
                {"user": {
                    "id": 42, "username": "player", "country": "tw",
                    "icon": "https://example.invalid/avatar.png",
                    "ui_class": "supporter", "supporter": true,
                    "about": "A **Go** player.\\nSecond paragraph.",
                    "registration_date": "\(dateString)"
                }, "active_games": [], "vs": {"wins": 4}}
                """)
            XCTAssertEqual(profile.user.country, "tw")
            XCTAssertEqual(profile.user.icon, "https://example.invalid/avatar.png")
            XCTAssertTrue(profile.user.isOGSSupporter)
            XCTAssertEqual(profile.about, "A **Go** player.\nSecond paragraph.")
            XCTAssertEqual(
                profile.registrationDate,
                ISO8601DateFormatter().date(from: "2019-03-01T12:30:00Z")
            )
        }
    }

    func testSupporterProfileUsesRoleFlagWhenUIClassIsAbsent() throws {
        let profile = try decode("""
            {"user":{"id":42,"username":"supporter","supporter":true,
             "professional":false,"is_moderator":false,"is_superuser":false}}
            """)
        XCTAssertNil(profile.user.uiClass)
        XCTAssertTrue(profile.user.isOGSSupporter)
        XCTAssertFalse(profile.user.isOGSModerator)
        XCTAssertFalse(profile.user.isOGSAdmin)
        XCTAssertEqual(profile.user.uiColor, .orange)
    }

    func testProfileRejectsMissingOrMalformedIdentity() {
        for json in [
            #"{}"#,
            #"{"user":null}"#,
            #"{"user":{"id":42}}"#,
            #"{"user":{"username":"player"}}"#,
            #"{"user":{"id":0,"username":"system"}}"#,
            #"{"user":{"id":42,"username":"  "}}"#,
            #"{"user":{"id":"42","username":"player"}}"#,
        ] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testProfileIgnoresMalformedOptionalRegistrationDate() throws {
        for dateValue in [#""not-a-date""#, #""""#, "42", "true", "{}", "[]"] {
            let profile = try decode("""
                {"user":{"id":42,"username":"player","about":"A Go player.","registration_date":\(dateValue)}}
                """)
            XCTAssertEqual(profile.id, 42, dateValue)
            XCTAssertEqual(profile.user.username, "player", dateValue)
            XCTAssertEqual(profile.about, "A Go player.", dateValue)
            XCTAssertNil(profile.registrationDate, dateValue)
        }
    }

    func testFetchIsLazyAndUsesTheRequestedEnvironmentAndPlayer() throws {
        ProfileURLProtocol.configure(handler: { request in
            request.respond(#"{"user":{"id":42,"username":"player"}}"#)
        })
        let service = makeService()
        let publisher = service.fetchPlayerProfile(playerId: 42)
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)

        let result = waitForResult(publisher)
        XCTAssertEqual(try result.get().id, 42)
        let request = try XCTUnwrap(ProfileURLProtocol.recordedRequests.first)
        XCTAssertEqual(ProfileURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://profile.ogs.test/api/v1/players/42/full")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(service.user)
        XCTAssertTrue(service.cachedUsersById.isEmpty)
    }

    func testFetchPreservesValidProfileWithMalformedOptionalDate() throws {
        ProfileURLProtocol.configure(handler: {
            $0.respond(#"{"user":{"id":42,"username":"player","registration_date":"not-a-date"}}"#)
        })
        let profile = try waitForResult(makeService().fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(profile.user.username, "player")
        XCTAssertNil(profile.registrationDate)
    }

    func testFetchRejectsAnotherPlayersResponseAndMalformedPayloads() {
        let service = makeService()
        for body in [
            #"{"user":{"id":99,"username":"other-player"}}"#,
            #"{"user":{"id":42}}"#,
            #"{"id":42,"username":"player"}"#,
            "not JSON",
        ] {
            ProfileURLProtocol.configure(handler: { $0.respond(body) })
            let result = waitForResult(service.fetchPlayerProfile(playerId: 42))
            guard case .failure(let error) = result,
                  case OGSServiceError.invalidJSON = error else {
                XCTFail("Expected an invalid profile response: \(body)")
                continue
            }
        }
    }

    func testFetchPreservesHTTPFailureInsteadOfReportingAnEmptyProfile() {
        ProfileURLProtocol.configure(handler: {
            $0.respond(#"{"user":{"id":42,"username":"player"}}"#, statusCode: 404)
        })
        let result = waitForResult(makeService().fetchPlayerProfile(playerId: 42))
        guard case .failure(let error) = result,
              let error = error as? AFError else {
            return XCTFail("Expected HTTP validation failure")
        }
        XCTAssertEqual(error.responseCode, 404)
    }

    func testFetchPreservesTransportFailure() {
        ProfileURLProtocol.configure(handler: {
            $0.client?.urlProtocol($0, didFailWithError: URLError(.notConnectedToInternet))
        })
        let result = waitForResult(makeService().fetchPlayerProfile(playerId: 42))
        guard case .failure(let error) = result,
              let error = error as? AFError,
              let underlying = error.underlyingError as? URLError else {
            return XCTFail("Expected the transport failure")
        }
        XCTAssertEqual(underlying.code, .notConnectedToInternet)
    }

    func testInvalidRequestedPlayerDoesNotStartHTTP() {
        for playerID in [0, -1] {
            let result = waitForResult(makeService().fetchPlayerProfile(playerId: playerID))
            guard case .failure(let error) = result,
                  case OGSServiceError.invalidJSON = error else {
                return XCTFail("Expected invalid player identity")
            }
        }
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testBootstrapProfilesResolveAndFailWithoutHTTPFallback() throws {
        let profile = OGSPlayerProfile(
            user: OGSUser(username: "fixture-player", id: 42),
            about: "Offline biography"
        )
        let service = makeService(initialState: .init(playerProfilesById: [42: profile]))
        let loaded = try waitForResult(service.fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(loaded.user, profile.user)
        XCTAssertEqual(loaded.about, profile.about)

        let result = waitForResult(service.fetchPlayerProfile(playerId: 99))
        guard case .failure(let error) = result,
              case OGSServiceError.invalidJSON = error else {
            return XCTFail("A missing fixture must fail without requesting live data")
        }
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testCancellingProfileLoadCancelsItsHTTPRequest() {
        let started = expectation(description: "profile request started")
        let stopped = expectation(description: "profile request cancelled")
        ProfileURLProtocol.configure(
            handler: { _ in started.fulfill() },
            stopped: { stopped.fulfill() }
        )
        let service = makeService()
        let cancellable = service.fetchPlayerProfile(playerId: 42).sink(
            receiveCompletion: { _ in XCTFail("Cancelled request must not deliver completion") },
            receiveValue: { _ in XCTFail("Cancelled request must not deliver a profile") }
        )
        wait(for: [started], timeout: 5)
        cancellable.cancel()
        wait(for: [stopped], timeout: 5)
    }

    func testBootstrapPlayerSearchFiltersWithoutHTTP() {
        let service = makeService(initialState: .init(playerProfilesById: [
            42: OGSPlayerProfile(user: OGSUser(username: "Rin", id: 42)),
            43: OGSPlayerProfile(user: OGSUser(username: "RinGo", id: 43)),
            44: OGSPlayerProfile(user: OGSUser(username: "Other", id: 44)),
        ]))
        var users: [OGSUser] = []
        service.searchByUsername(keyword: "RIN").sink(
            receiveCompletion: {
                if case .failure = $0 { XCTFail("Fixture search must succeed") }
            },
            receiveValue: { users = $0 }
        ).store(in: &cancellables)
        XCTAssertEqual(users.map(\.id), [42, 43])
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testProfileFromPreviousAuthenticationContextIsDiscarded() throws {
        let started = expectation(description: "old-account profile request started")
        var heldRequest: ProfileURLProtocol?
        ProfileURLProtocol.configure(handler: {
            heldRequest = $0
            started.fulfill()
        })
        let service = makeService()
        let completed = expectation(description: "old-account profile discarded")
        var receivedError: Error?
        service.fetchPlayerProfile(playerId: 42).sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            },
            receiveValue: { _ in XCTFail("A response from the old account must not be delivered") }
        ).store(in: &cancellables)

        wait(for: [started], timeout: 5)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        service.ogsUIConfig = try decoder.decode(
            OGSUIConfig.self,
            from: Data(#"{"user":{"id":7,"username":"new-account","anonymous":false}}"#.utf8)
        )
        heldRequest?.respond(#"{"user":{"id":42,"username":"player"}}"#)
        wait(for: [completed], timeout: 5)
        guard let receivedError,
              case OGSServiceError.staleAuthenticationContext = receivedError else {
            return XCTFail("Expected the old authentication context to be rejected")
        }
    }

    func testOptionalSectionsDistinguishUnavailableFromEmpty() throws {
        let sparse = try decode(#"{"user":{"id":42,"username":"player"}}"#)
        XCTAssertNil(sparse.activeGames)
        XCTAssertNil(sparse.versus)

        let empty = try decode("""
            {"user":{"id":42,"username":"player"},"active_games":[],
             "vs":{"wins":0,"losses":0,"draws":0,"history":[]}}
            """)
        XCTAssertEqual(empty.activeGames?.count, 0)
        XCTAssertEqual(empty.versus?.totalGames, 0)

        for section in ["null", "false", "42", #""invalid""#] {
            let profile = try decode("""
                {"user":{"id":42,"username":"player"},
                 "active_games":\(section),"vs":\(section)}
                """)
            XCTAssertEqual(profile.id, 42)
            XCTAssertNil(profile.activeGames, section)
            XCTAssertNil(profile.versus, section)
        }
    }

    func testEmptyVersusObjectMeansNoGamesWhileMalformedSectionsRemainUnavailable() throws {
        let profile = try decode("""
            {"user":{"id":42,"username":"player"},"active_games":{},"vs":{}}
            """)
        let versus = try XCTUnwrap(profile.versus)
        XCTAssertEqual(versus.wins, 0)
        XCTAssertEqual(versus.losses, 0)
        XCTAssertEqual(versus.draws, 0)
        XCTAssertEqual(versus.totalGames, 0)
        XCTAssertTrue(versus.history.isEmpty)
        XCTAssertNil(profile.activeGames)

        for value in [
            #"{"history":[]}"#,
            #"{"wins":0}"#,
            #"{"wins":0,"losses":0}"#,
            #"{"wins":null,"losses":0,"draws":0}"#,
            #"{"unknown":0}"#,
            "[]",
        ] {
            let malformed = try decode("""
                {"user":{"id":42,"username":"player"},"vs":\(value)}
                """)
            XCTAssertEqual(malformed.id, 42)
            XCTAssertNil(malformed.versus, value)
        }
    }

    func testFetchTreatsEmptyVersusObjectAsAnEmptyRecord() throws {
        ProfileURLProtocol.configure(handler: {
            $0.respond(#"{"user":{"id":42,"username":"player"},"vs":{}}"#)
        })
        let profile = try waitForResult(makeService().fetchPlayerProfile(playerId: 42)).get()
        XCTAssertEqual(profile.versus, OGSProfileVersus(wins: 0, losses: 0, draws: 0))
    }

    func testMalformedBiographyDoesNotDiscardIdentityOrValidSections() throws {
        let profile = try decode("""
            {"user":{"id":42,"username":"player","about":{}},
             "active_games":[],"vs":{"wins":1,"losses":2,"draws":3}}
            """)
        XCTAssertNil(profile.about)
        XCTAssertEqual(profile.activeGames?.count, 0)
        XCTAssertEqual(profile.versus?.totalGames, 6)
    }

    func testVersusRetainsViewerRelativeTotalsAndToleratesDamagedHistory() throws {
        let profile = try decode("""
            {"user":{"id":42,"username":"player"},"vs":{
                "wins":2,"losses":3,"draws":1,"history":[
                    {"game":20,"state":"W","date":"2026-01-01T01:02:03.000Z"},
                    {"game":19,"state":"L","date":"2026-01-01T01:02:03Z"},
                    {"game":18,"state":"D","date":"invalid"},
                    {"game":17,"state":"future-state"},
                    {"game":0,"state":"W"},null
                ]}}
            """)
        let versus = try XCTUnwrap(profile.versus)
        XCTAssertEqual(versus.wins, 2)
        XCTAssertEqual(versus.losses, 3)
        XCTAssertEqual(versus.draws, 1)
        XCTAssertEqual(versus.totalGames, 6)
        XCTAssertEqual(versus.history.map(\.gameID), [20, 19, 18, 17])
        XCTAssertEqual(versus.history.map(\.result), [.win, .loss, .draw, .unknown])
        XCTAssertEqual(versus.history[0].date, versus.history[1].date)
        XCTAssertNotNil(versus.history[0].date)
        XCTAssertNil(versus.history[2].date)
    }

    func testVersusRejectsIncompleteNegativeAndOverflowingTotals() throws {
        for totals in [
            #"{"wins":2}"#,
            #"{"wins":-1,"losses":2,"draws":0}"#,
            #"{"wins":"2","losses":2,"draws":0}"#,
            #"{"wins":9223372036854775807,"losses":1,"draws":0}"#,
        ] {
            let profile = try decode("""
                {"user":{"id":42,"username":"player"},"vs":\(totals)}
                """)
            XCTAssertEqual(profile.id, 42)
            XCTAssertNil(profile.versus)
        }
    }

    func testActiveGamesDecodeFullBoardAndRejectMismatchedWrappersWithoutLosingIdentity() throws {
        let gameData = try fixtureGameJSON(id: 700)
        let profileData: [String: Any] = [
            "user": ["id": 42, "username": "player"],
            "active_games": [["id": 700, "json": gameData]],
        ]
        let profile = try decodeObject(profileData)
        XCTAssertEqual(profile.activeGames?.first?.id, 700)
        XCTAssertEqual(profile.activeGames?.first?.gameData.gameId, 700)
        XCTAssertEqual(profile.activeGames?.first?.gameData.phase, .play)
        XCTAssertFalse(profile.activeGames?.first?.gameData.moves.isEmpty ?? true)

        let invalidEntries: [[[String: Any]]] = [
            [["id": 701, "json": gameData]],
            [["id": 700]],
            [["id": 700, "json": gameData], ["id": 0]],
        ]
        for entries in invalidEntries {
            var invalidProfile = profileData
            invalidProfile["active_games"] = entries
            let decoded = try decodeObject(invalidProfile)
            XCTAssertEqual(decoded.id, 42)
            XCTAssertNil(decoded.activeGames)
        }
    }

    func testActiveGamesReuseCanonicalModelsAndExcludeFinishedAndDroppedRengo() throws {
        let playing = try fixtureGame(id: 700)
        var finished = try fixtureGame(id: 701)
        finished.phase = .finished
        var dropped = try fixtureGame(id: 702)
        dropped.rengo = true
        dropped.rengoTeams = OGSGame.RengoTeams(
            black: [OGSUser(username: "replacement", id: 99)],
            white: [dropped.players.white]
        )
        var retainedRengo = try fixtureGame(id: 703)
        retainedRengo.rengo = true
        retainedRengo.rengoTeams = OGSGame.RengoTeams(
            black: [retainedRengo.players.black],
            white: [retainedRengo.players.white]
        )
        let canonical = Game(ogsGame: playing)
        canonical.gameName = "Fresher connected title"
        let service = makeService(initialState: .init(activeGames: [700: canonical]))
        let profile = OGSPlayerProfile(
            user: playing.players.black,
            activeGames: [playing, finished, dropped, retainedRengo, playing].map {
                OGSProfileActiveGame(gameData: $0)
            }
        )

        let store = try XCTUnwrap(service.profileActiveGames(from: profile))
        XCTAssertEqual(store.entries.map(\.id), [700, 703])
        XCTAssertTrue(store.resolvedGames.isEmpty)
        let games = store.entries.map { store.game(for: $0) }
        XCTAssertTrue(games.first === canonical)
        XCTAssertEqual(games.first?.gameName, "Fresher connected title")
        XCTAssertTrue(games.last?.ogs === service)
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
        XCTAssertNil(service.profileActiveGames(from: .init(user: profile.user)))
        XCTAssertEqual(service.profileActiveGames(from: .init(user: profile.user, activeGames: []))?.entries.count, 0)

        canonical.gamePhase = .finished
        var changedRengo = retainedRengo
        changedRengo.rengoTeams?.black = [OGSUser(username: "replacement", id: 99)]
        games.last?.gameData = changedRengo
        store.refreshMembership()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.resolvedGames.isEmpty)
    }

    func testActiveGameStoreReplaysOnlyRequestedRowsAndReusesThem() throws {
        let template = try fixtureGame(id: 800)
        let entries = (800..<1_000).map { id in
            var data = template
            data.gameId = id
            return OGSProfileActiveGame(gameData: data)
        }
        let service = makeService()
        let profile = OGSPlayerProfile(user: template.players.black, activeGames: entries)
        let store = try XCTUnwrap(service.profileActiveGames(from: profile))
        XCTAssertEqual(store.entries.count, 200)
        XCTAssertTrue(store.resolvedGames.isEmpty, "Counting the full list must not replay boards")

        let visibleGames = store.entries.prefix(3).map { store.game(for: $0) }
        XCTAssertEqual(store.resolvedGames.count, 3)
        XCTAssertEqual(visibleGames.compactMap(\.ogsID), [800, 801, 802])
        for (entry, game) in zip(store.entries.prefix(3), visibleGames) {
            XCTAssertEqual(game.currentPosition.lastMoveNumber, template.moves.count)
            XCTAssertTrue(store.game(for: entry) === game)
        }
        store.refreshMembership()
        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(store.resolvedGames.count, 3)
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testHistoryFiltersAreSentToTheOfficialEndpointAndPreserveAnnulment() throws {
        ProfileURLProtocol.configure(handler: { request in
            request.respond("""
                {"results":[{"id":700,"width":19,"height":19,"annulled":true,
                 "players":{"black":{"id":42,"username":"player"},
                 "white":{"id":7,"username":"opponent"}}}],"next":null}
                """)
        })
        let service = makeService()
        let publisher = service.fetchFinishedGames(
            playerId: 42, page: 2, pageSize: 5, opponentId: 7, botGames: true
        )
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
        let result = try waitForResult(publisher).get()
        XCTAssertEqual(result.games.first?.historyAnnulled, true)
        XCTAssertNil(result.games.first?.ogsRawData, "Listing metadata must not masquerade as full detail")
        XCTAssertFalse(result.hasNextPage)
        let url = try XCTUnwrap(ProfileURLProtocol.recordedRequests.first?.url)
        let query = Dictionary(uniqueKeysWithValues:
            URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(url.path, "/api/v1/players/42/game_history")
        XCTAssertEqual(query["opponent"], "7")
        XCTAssertEqual(query["bot_game"], "true")
        XCTAssertEqual(query["ordering"], "-ended")
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["page_size"], "5")
    }

    func testFixtureHistoryFiltersBeforePaginationAndSupportsIndependentProfileFeeds() throws {
        let shared1 = Game(ogsGame: try fixtureGame(id: 700))
        let shared2 = Game(ogsGame: try fixtureGame(id: 699))
        let differentOpponent = Game(ogsGame: try fixtureGame(id: 698, whiteID: 8))
        var botData = try fixtureGame(id: 697, whiteID: 9)
        botData.players.white.isBot = true
        let botGame = Game(ogsGame: botData)
        let unrelated = Game(ogsGame: try fixtureGame(id: 696, blackID: 50, whiteID: 51))
        let homeOnly = Game(ogsGame: try fixtureGame(id: 695))
        let service = makeService(initialState: .init(
            finishedGamesSnapshot: [homeOnly],
            finishedGamesByPlayerId: [42: [shared1, unrelated, differentOpponent, shared2, botGame]]
        ))
        let firstPage = try waitForResult(service.fetchFinishedGames(
            playerId: 42, page: 1, pageSize: 1, opponentId: 7
        )).get()
        XCTAssertEqual(firstPage.games.compactMap(\.ogsID), [700])
        XCTAssertTrue(firstPage.hasNextPage)
        let secondPage = try waitForResult(service.fetchFinishedGames(
            playerId: 42, page: 2, pageSize: 1, opponentId: 7
        )).get()
        XCTAssertEqual(secondPage.games.compactMap(\.ogsID), [699])
        XCTAssertFalse(secondPage.hasNextPage)
        let bots = try waitForResult(service.fetchFinishedGames(
            playerId: 42, page: 1, botGames: true
        )).get()
        XCTAssertEqual(bots.games.compactMap(\.ogsID), [697])
        let home = try waitForResult(service.fetchFinishedGames(playerId: 7, page: 1)).get()
        XCTAssertEqual(home.games.compactMap(\.ogsID), [695])
        XCTAssertTrue(ProfileURLProtocol.recordedRequests.isEmpty)
    }

    func testCancellingHistoryLoadCancelsItsHTTPRequest() {
        let started = expectation(description: "history request started")
        let stopped = expectation(description: "history request cancelled")
        ProfileURLProtocol.configure(
            handler: { _ in started.fulfill() },
            stopped: { stopped.fulfill() }
        )
        let service = makeService()
        let cancellable = service.fetchFinishedGames(playerId: 42, page: 1).sink(
            receiveCompletion: { _ in XCTFail("Cancelled request must not deliver completion") },
            receiveValue: { _ in XCTFail("Cancelled request must not deliver games") }
        )
        wait(for: [started], timeout: 5)
        cancellable.cancel()
        wait(for: [stopped], timeout: 5)
    }

    func testHistoryFromPreviousAuthenticationContextIsDiscarded() throws {
        let started = expectation(description: "old-account history request started")
        var heldRequest: ProfileURLProtocol?
        ProfileURLProtocol.configure(handler: {
            heldRequest = $0
            started.fulfill()
        })
        let service = makeService()
        let completed = expectation(description: "old-account history discarded")
        var receivedError: Error?
        service.fetchFinishedGames(playerId: 42, page: 1).sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            },
            receiveValue: { _ in XCTFail("A response from the old account must not be delivered") }
        ).store(in: &cancellables)
        wait(for: [started], timeout: 5)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        service.ogsUIConfig = try decoder.decode(
            OGSUIConfig.self,
            from: Data(#"{"user":{"id":7,"username":"new-account","anonymous":false}}"#.utf8)
        )
        heldRequest?.respond(#"{"results":[],"next":null}"#)
        wait(for: [completed], timeout: 5)
        guard let receivedError,
              case OGSServiceError.staleAuthenticationContext = receivedError else {
            return XCTFail("Expected the old authentication context to be rejected")
        }
    }

    private func fixtureGameJSON(id: Int, blackID: Int = 42, whiteID: Int = 7) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-25076729", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["game_id"] = id
        json["phase"] = "play"
        json.removeValue(forKey: "outcome")
        json.removeValue(forKey: "winner")
        json["black_player_id"] = blackID
        json["white_player_id"] = whiteID
        json["players"] = [
            "black": ["id": blackID, "username": "player-\(blackID)"],
            "white": ["id": whiteID, "username": "player-\(whiteID)"],
        ]
        return json
    }

    private func fixtureGame(id: Int, blackID: Int = 42, whiteID: Int = 7) throws -> OGSGame {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: JSONSerialization.data(withJSONObject:
            fixtureGameJSON(id: id, blackID: blackID, whiteID: whiteID)
        ))
    }

    private func decodeObject(_ json: [String: Any]) throws -> OGSPlayerProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPlayerProfile.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func decode(_ json: String) throws -> OGSPlayerProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPlayerProfile.self, from: Data(json.utf8))
    }

    private func waitForResult<Value>(
        _ publisher: AnyPublisher<Value, Error>
    ) -> Result<Value, Error> {
        let completed = expectation(description: "request completed")
        var result: Result<Value, Error>?
        publisher.sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { result = .failure(error) }
                completed.fulfill()
            },
            receiveValue: { result = .success($0) }
        ).store(in: &cancellables)
        wait(for: [completed], timeout: 5)
        guard let result else {
            XCTFail("Profile request completed without a value or error")
            return .failure(OGSServiceError.invalidJSON)
        }
        return result
    }

    private func makeService(initialState: OGSService.BootstrapState? = nil) -> OGSService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        configuration.httpCookieStorage = nil
        let suite = "com.honganhkhoa.Surround.ProfileTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://profile.ogs.test")!),
            httpClient: AlamofireOGSHTTPClient(
                session: Session(configuration: configuration),
                cookieStorage: nil
            ),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(status: .disconnected),
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false,
            initialState: initialState
        )
    }
}
