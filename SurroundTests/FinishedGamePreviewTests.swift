import Alamofire
import Combine
import XCTest

final class FinishedGamePreviewTests: XCTestCase {
    private var preferenceSuites: [String] = []
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        for suite in preferenceSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        preferenceSuites.removeAll()
        PreviewURLProtocol.configure(nil)
        super.tearDown()
    }

    func testSummaryLossFlagsResolveBothPlayersWithoutGameDetail() {
        for blackLost in [false, true] {
            let summary = makeSummary(outcome: "Resignation", blackLost: blackLost, whiteLost: !blackLost)
            XCTAssertEqual(summary.result(for: 1), blackLost ? .loss : .win)
            XCTAssertEqual(summary.result(for: 2), blackLost ? .win : .loss)
            XCTAssertEqual(summary.result(for: 99), .unknown)
            XCTAssertEqual(summary.winnerColor, blackLost ? .white : .black)
            XCTAssertFalse(summary.isDraw)
        }
    }

    func testSummaryDrawRequiresMatchingLossFlagsAndAnExplicitDrawOutcome() {
        for outcome in ["0 points", "0.0 points", "0 point", "draw", " Jigo ", "TIE"] {
            let summary = makeSummary(outcome: outcome, blackLost: false, whiteLost: false)
            XCTAssertTrue(summary.isDraw, outcome)
            XCTAssertNil(summary.winnerColor, outcome)
            XCTAssertEqual(summary.result(for: 1), .draw, outcome)
            XCTAssertEqual(summary.result(for: 2), .draw, outcome)
        }
        for flags in [(nil, nil), (false, nil), (nil, false), (true, true)] as [(Bool?, Bool?)] {
            let summary = makeSummary(outcome: "0 points", blackLost: flags.0, whiteLost: flags.1)
            XCTAssertFalse(summary.isDraw)
            XCTAssertEqual(summary.result(for: 1), .unknown)
        }
    }

    func testSummaryCancellationAndUnknownOutcomesDoNotInventAResult() {
        for outcome in ["Cancellation", " Cancelled ", "CANCELED", "Void", "", "Server decision 42", "5.5 points"] {
            let summary = makeSummary(outcome: outcome, blackLost: false, whiteLost: false)
            XCTAssertFalse(summary.isDraw, outcome)
            XCTAssertNil(summary.winnerColor, outcome)
            XCTAssertEqual(summary.result(for: 1), .unknown, outcome)
            XCTAssertEqual(summary.result(for: 2), .unknown, outcome)
        }
        for outcome in ["B+R", "W+3.5", "Resignation"] {
            let summary = makeSummary(outcome: outcome)
            XCTAssertNil(summary.winnerColor, outcome)
            XCTAssertEqual(summary.result(for: 1), .unknown, outcome)
        }
        let cancelledWithLossFlag = makeSummary(outcome: "Cancellation", blackLost: true, whiteLost: false)
        XCTAssertNil(cancelledWithLossFlag.winnerColor)
        XCTAssertEqual(cancelledWithLossFlag.result(for: 1), .unknown)
    }

    func testSummaryAnnulmentOverridesWinLossAndDraw() {
        for flags in [(false, true), (true, false), (false, false)] {
            let summary = makeSummary(outcome: "0 points", blackLost: flags.0, whiteLost: flags.1, annulled: true)
            XCTAssertEqual(summary.result(for: 1), .annulled)
            XCTAssertEqual(summary.result(for: 2), .annulled)
            XCTAssertNil(summary.winnerColor)
            XCTAssertFalse(summary.isDraw)
        }
    }

    func testRengoSummaryResolvesNonleaderPerspectivesWithoutPlayerRoster() {
        let summary = FinishedGameSummary(
            gameID: 101, blackPlayerID: 1, whitePlayerID: 2, width: 9, height: 9,
            outcome: "Resignation", blackLost: false, whiteLost: true, rengo: true,
            rengoBlackTeamIDs: [1, 3], rengoWhiteTeamIDs: [2, 4]
        )
        XCTAssertEqual(summary.stoneColor(ofPlayerWithID: 3), .black)
        XCTAssertEqual(summary.stoneColor(ofPlayerWithID: 4), .white)
        XCTAssertEqual(summary.result(for: 3), .win)
        XCTAssertEqual(summary.result(for: 4), .loss)
        XCTAssertEqual(summary.result(for: 99), .unknown)

        let missingTeams = FinishedGameSummary(
            gameID: 101, blackPlayerID: 1, whitePlayerID: 2, width: 9, height: 9,
            outcome: "Resignation", blackLost: false, whiteLost: true, rengo: true
        )
        XCTAssertEqual(missingTeams.result(for: 1), .win)
        XCTAssertEqual(missingTeams.result(for: 3), .unknown)

        let contradictoryTeams = FinishedGameSummary(
            gameID: 101, blackPlayerID: 1, whitePlayerID: 2, width: 9, height: 9,
            outcome: "Resignation", blackLost: false, whiteLost: true, rengo: true,
            rengoBlackTeamIDs: [1, 3], rengoWhiteTeamIDs: [2, 3]
        )
        XCTAssertNil(contradictoryTeams.stoneColor(ofPlayerWithID: 3))
        XCTAssertEqual(contradictoryTeams.result(for: 3), .unknown)
    }

    func testSummaryDecodesOfficialListingShapeAndOptionalMetadata() throws {
        var payload = summaryPayload()
        payload["name"] = "Listed game"
        payload["ended"] = "2016-07-07T10:39:33.000Z"
        payload["handicap"] = 2
        payload["komi"] = "0.5"
        payload["rules"] = "japanese"
        payload["rengo"] = true
        payload["rengo_black_team"] = [1, 3]
        payload["rengo_white_team"] = [2, 4]
        let summary = try decodeSummary(payload)
        XCTAssertEqual(summary.gameID, 101)
        XCTAssertEqual(summary.blackPlayerID, 1)
        XCTAssertEqual(summary.whitePlayerID, 2)
        XCTAssertEqual(summary.name, "Listed game")
        XCTAssertNotNil(summary.ended)
        XCTAssertEqual(summary.handicap, 2)
        XCTAssertEqual(summary.komi, 0.5)
        XCTAssertEqual(summary.rules, .japanese)
        XCTAssertEqual(summary.result(for: 3), .win)
        XCTAssertEqual(summary.result(for: 4), .loss)
    }

    func testSummaryRejectsMalformedRequiredIdentityButKeepsUnknownOptionalResults() throws {
        for key in ["id", "width", "height", "players"] {
            var payload = summaryPayload()
            payload.removeValue(forKey: key)
            XCTAssertThrowsError(try decodeSummary(payload), key)
        }
        for key in ["id", "width", "height"] {
            var payload = summaryPayload()
            payload[key] = 0
            XCTAssertThrowsError(try decodeSummary(payload), key)
        }
        var invalidPlayer = summaryPayload()
        invalidPlayer["players"] = [
            "black": ["id": 1, "username": " "], "white": ["id": 2, "username": "White"],
        ]
        XCTAssertThrowsError(try decodeSummary(invalidPlayer))

        var optionalDamage = summaryPayload()
        optionalDamage["black_lost"] = "false"
        optionalDamage["white_lost"] = NSNull()
        optionalDamage["rengo"] = true
        optionalDamage["rengo_black_team"] = [1, -3]
        optionalDamage["rengo_white_team"] = [2, 2]
        let summary = try decodeSummary(optionalDamage)
        XCTAssertEqual(summary.result(for: 1), .unknown)
        XCTAssertNil(summary.rengoBlackTeamIDs)
        XCTAssertNil(summary.rengoWhiteTeamIDs)
    }

    func testPreviewSuccessAndFailureAreIndependentBoundedAndKeepListingOrder() throws {
        let service = makeService()
        let games = [901, 902, 903, 904].map(makeHistoryGame(id:))
        let originalIDs = games.map(\.ID)
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 2, loadPreview: requests.load)
        loader.load(games: games, using: service)
        XCTAssertEqual(requests.requestedIDs, [901, 902])
        XCTAssertEqual(games.map(\.historyDetailState), [.loading, .loading, .notRequested, .notRequested])

        let thirdStarted = expectation(description: "third preview starts after the second finishes")
        requests.didStart = { if $0 == 903 { thirdStarted.fulfill() } }
        try requests.succeed(gameID: 902, detail: makeFinishedGameDetail(gameID: 902))
        wait(for: [thirdStarted], timeout: 3)
        XCTAssertEqual(games[1].historyDetailState, .ready)
        XCTAssertNotNil(games[1].finishedHistoryPosition)
        XCTAssertEqual(games[0].historyDetailState, .loading)

        let fourthStarted = expectation(description: "fourth preview starts after a failure")
        requests.didStart = { if $0 == 904 { fourthStarted.fulfill() } }
        requests.fail(gameID: 903)
        wait(for: [fourthStarted], timeout: 3)
        XCTAssertEqual(games[2].historyDetailState, .unavailable)
        XCTAssertNil(games[2].gameData)
        waitForState(.ready, of: games[3]) {
            try requests.succeed(gameID: 904, detail: makeFinishedGameDetail(gameID: 904))
        }
        XCTAssertEqual(games[0].historyDetailState, .loading)
        waitForState(.ready, of: games[0]) {
            try requests.succeed(gameID: 901, detail: makeFinishedGameDetail(gameID: 901))
        }
        XCTAssertEqual(requests.peakActiveCount, 2)
        XCTAssertEqual(requests.requestedIDs, [901, 902, 903, 904])
        XCTAssertEqual(games.map(\.ID), originalIDs)
        XCTAssertEqual(games.map { $0.historySummary?.gameID }, [901, 902, 903, 904])
        XCTAssertEqual(games.map(\.historyDetailState), [.ready, .ready, .unavailable, .ready])
    }

    func testPreviewConcurrencyIsClampedToOneThroughFour() {
        for (requestedLimit, expectedLimit) in [(-2, 1), (0, 1), (8, 4)] {
            let service = makeService()
            let requests = ControlledPreviewRequests()
            let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: requestedLimit, loadPreview: requests.load)
            loader.load(games: [911, 912, 913, 914, 915].map(makeHistoryGame(id:)), using: service)
            XCTAssertEqual(requests.requestedIDs.count, expectedLimit)
            XCTAssertEqual(requests.peakActiveCount, expectedLimit)
            loader.cancel()
            XCTAssertEqual(requests.activeCount, 0)
        }
    }

    func testPreviewLoadReusesReadyGamesDeduplicatesAndRetriesOnlyFailedRow() throws {
        let service = makeService()
        let ready = makeHistoryGame(id: 921)
        OGSService.applyFinishedGameDetail(try makeFinishedGameDetail(gameID: 921), to: ready)
        let pending = makeHistoryGame(id: 922)
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(loadPreview: requests.load)
        loader.load(games: [ready, pending, pending], using: service)
        loader.load(games: [ready, pending], using: service)
        XCTAssertEqual(ready.historyDetailState, .ready)
        XCTAssertEqual(requests.requestedIDs, [922])
        waitForState(.unavailable, of: pending) { requests.fail(gameID: 922) }
        loader.load(games: [ready, pending], using: service)
        XCTAssertEqual(requests.requestedIDs, [922])
        loader.retry(game: pending, using: service)
        XCTAssertEqual(requests.requestedIDs, [922, 922])
        XCTAssertEqual(pending.historyDetailState, .loading)
        waitForState(.ready, of: pending) {
            try requests.succeed(gameID: 922, detail: makeFinishedGameDetail(gameID: 922))
        }
        loader.retry(game: ready, using: service)
        loader.load(games: [ready, pending], using: service)
        XCTAssertEqual(requests.requestedIDs, [922, 922])
    }

    func testSuccessfulPublisherWithoutFinalBoardDoesNotMarkPreviewReady() {
        let service = makeService()
        let game = makeHistoryGame(id: 931)
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(loadPreview: requests.load)
        loader.load(games: [game], using: service)
        waitForState(.unavailable, of: game) { requests.finishWithoutDetail(gameID: 931) }
        XCTAssertFalse(game.hasCompleteFinishedGameDetail)
        XCTAssertNil(game.finishedHistoryPosition)
    }

    func testCancelDiscardsQueueAndLateNoncooperativePublisherEvents() {
        let service = makeService()
        let games = [941, 942, 943].map(makeHistoryGame(id:))
        let latePublisher = LatePreviewPublisher()
        var requestedIDs = [Int]()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1) { game, _ in
            requestedIDs.append(game.ogsID!)
            return latePublisher.eraseToAnyPublisher()
        }
        loader.load(games: games, using: service)
        loader.cancel()
        XCTAssertEqual(games.map(\.historyDetailState), [.notRequested, .notRequested, .notRequested])
        XCTAssertTrue(latePublisher.wasCancelled)
        latePublisher.sendAfterCancellation()
        drainMainQueue()
        XCTAssertEqual(requestedIDs, [941])
        XCTAssertTrue(games.allSatisfy { $0.gameData == nil && $0.ogsRawData == nil })
        XCTAssertTrue(games.allSatisfy { $0.historyDetailRequestID == nil })
        XCTAssertEqual(games.map(\.historyDetailState), [.notRequested, .notRequested, .notRequested])
    }

    func testCancellingOneLoaderDoesNotResetAnotherLoadersOwnedRow() throws {
        let service = makeService()
        let game = makeHistoryGame(id: 951)
        let firstRequests = ControlledPreviewRequests()
        let secondRequests = ControlledPreviewRequests()
        let first = FinishedGamePreviewLoader(loadPreview: firstRequests.load)
        let second = FinishedGamePreviewLoader(loadPreview: secondRequests.load)
        first.load(games: [game], using: service)
        let firstID = game.historyDetailRequestID
        second.load(games: [game], using: service)
        XCTAssertNotEqual(game.historyDetailRequestID, firstID)
        first.cancel()
        XCTAssertEqual(game.historyDetailState, .loading)
        XCTAssertNotNil(game.historyDetailRequestID)
        waitForState(.ready, of: game) {
            try secondRequests.succeed(gameID: 951, detail: makeFinishedGameDetail(gameID: 951))
        }
        XCTAssertNil(game.historyDetailRequestID)
    }

    func testAuthenticationChangeDiscardsOutstandingAndQueuedPreviews() throws {
        let service = makeService()
        let games = [961, 962].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: requests.load)
        loader.load(games: games, using: service)
        let oldGeneration = service.finishedGamePreviewAuthenticationGeneration
        try setAccount(7, on: service)
        XCTAssertNotEqual(service.finishedGamePreviewAuthenticationGeneration, oldGeneration)
        waitForState(.notRequested, of: games[0]) { requests.finishWithoutDetail(gameID: 961) }
        XCTAssertEqual(requests.requestedIDs, [961])
        XCTAssertEqual(games[1].historyDetailState, .notRequested)
        XCTAssertTrue(games.allSatisfy { $0.gameData == nil })

        loader.load(games: games, using: service)
        XCTAssertEqual(requests.requestedIDs, [961, 961])
        XCTAssertEqual(games[0].historyDetailState, .loading)
        loader.cancel()
    }

    func testViewerAndServiceChangesCancelPreviousPreviewContext() {
        let service = makeService()
        let game = makeHistoryGame(id: 971)
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(loadPreview: requests.load)
        loader.load(games: [game], using: service)
        service.user = OGSUser(username: "Other account", id: 8)
        loader.load(games: [game], using: service)
        XCTAssertEqual(requests.requestedIDs, [971, 971])
        XCTAssertEqual(requests.cancelCount, 1)
        let otherService = makeService()
        loader.load(games: [game], using: otherService)
        XCTAssertEqual(requests.requestedIDs, [971, 971, 971])
        XCTAssertEqual(requests.cancelCount, 2)
        loader.cancel()
    }

    func testStaleAuthenticationFailureCancelsOtherRowsWithoutMarkingThemUnavailable() {
        let service = makeService()
        let games = [981, 982, 983].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 2, loadPreview: requests.load)
        loader.load(games: games, using: service)
        waitForState(.notRequested, of: games[0]) {
            requests.fail(gameID: 981, error: OGSServiceError.staleAuthenticationContext)
        }
        XCTAssertEqual(requests.requestedIDs, [981, 982])
        XCTAssertEqual(games.map(\.historyDetailState), [.notRequested, .notRequested, .notRequested])
        XCTAssertEqual(requests.activeCount, 0)
    }

    func testDefaultPreviewServiceRejectsLateResponseFromPreviousAccountBeforeApplyingDetail() throws {
        let service = makeService()
        let gameID = Int.random(in: 1_500_000_000...2_000_000_000)
        let game = makeHistoryGame(id: gameID)
        let started = expectation(description: "old account detail request started")
        var heldRequest: PreviewURLProtocol?
        PreviewURLProtocol.configure { request in
            DispatchQueue.main.async {
                heldRequest = request
                started.fulfill()
            }
        }
        let completed = expectation(description: "stale preview rejected")
        var receivedError: Error?
        var receivedValue = false
        service.loadFinishedGamePreview(for: game).sink(receiveCompletion: {
            if case .failure(let error) = $0 { receivedError = error }
            completed.fulfill()
        }, receiveValue: { receivedValue = true }).store(in: &cancellables)
        wait(for: [started], timeout: 3)
        try setAccount(9, on: service)
        try XCTUnwrap(heldRequest).respond(makeFinishedGameDetail(gameID: gameID).rawData)
        wait(for: [completed], timeout: 3)
        guard let error = receivedError as? OGSServiceError,
              case .staleAuthenticationContext = error else {
            XCTFail("Expected the account fence to reject the old response")
            return
        }
        XCTAssertFalse(receivedValue)
        XCTAssertNil(game.gameData)
        XCTAssertNil(game.ogsRawData)
        XCTAssertFalse(game.hasCompleteFinishedGameDetail)
        XCTAssertNil(FinishedGameCache.shared.data(forGameID: gameID))
    }

    func testDefaultPreviewLoaderCancellationPreventsLateResponseApplyingToRow() throws {
        let service = makeService()
        let gameID = Int.random(in: 1_500_000_000...2_000_000_000)
        let game = makeHistoryGame(id: gameID)
        let started = expectation(description: "cancellable preview request started")
        var heldRequest: PreviewURLProtocol?
        PreviewURLProtocol.configure { request in
            DispatchQueue.main.async {
                heldRequest = request
                started.fulfill()
            }
        }
        let loader = FinishedGamePreviewLoader()
        loader.load(games: [game], using: service)
        wait(for: [started], timeout: 3)
        loader.cancel()
        let applied = expectation(description: "cancelled detail must never apply")
        applied.isInverted = true
        game.$gameData.dropFirst().sink { _ in applied.fulfill() }.store(in: &cancellables)
        try XCTUnwrap(heldRequest).respond(makeFinishedGameDetail(gameID: gameID).rawData)
        wait(for: [applied], timeout: 0.5)
        XCTAssertEqual(game.historyDetailState, .notRequested)
        XCTAssertNil(game.gameData)
        XCTAssertNil(game.ogsRawData)
        XCTAssertNil(game.historyDetailRequestID)
    }

    func testResultlessFinishedGameStillLoadsItsActualFinalBoardWithoutInventingResult() throws {
        let service = makeService()
        let game = makeHistoryGame(id: 991)
        game.historySummary = FinishedGameSummary(gameID: 991, blackPlayerID: 1, whitePlayerID: 2,
                                                   width: 9, height: 9)
        let originalDetail = try makeFinishedGameDetail(gameID: 991)
        var data = originalDetail.ogsGame
        data.outcome = nil
        data.winner = nil
        var rawData = originalDetail.rawData
        var rawGameData = try XCTUnwrap(rawData["gamedata"] as? [String: Any])
        rawGameData.removeValue(forKey: "outcome")
        rawGameData.removeValue(forKey: "winner")
        rawData["gamedata"] = rawGameData
        let detail = FinishedGameDetail(ogsGame: data, rawData: rawData)
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(loadPreview: requests.load)
        loader.load(games: [game], using: service)
        waitForState(.ready, of: game) { try requests.succeed(gameID: 991, detail: detail) }
        XCTAssertTrue(game.hasCompleteFinishedGameDetail)
        XCTAssertEqual(game.finishedHistoryPosition?.lastMoveNumber, 3)
        XCTAssertNil(game.gameData?.winner)
        XCTAssertNil(game.gameData?.outcome)
        XCTAssertEqual(game.historySummary?.result(for: 1), .unknown)
        XCTAssertEqual(game.historySummary?.result(for: 2), .unknown)
    }

    func testDefaultPreviewServicePreservesSharedSelectedPositionAndAnalysisBranch() throws {
        let service = makeService()
        let gameID = Int.random(in: 1_500_000_000...2_000_000_000)
        let detail = try makeFinishedGameDetail(gameID: gameID)
        var oldData = detail.ogsGame
        let selectedBlack = OGSUser(username: "Selected black", id: 1, ranking: 31)
        let selectedWhite = OGSUser(username: "Selected white", id: 2, ranking: 22)
        let selectedBlackTeammate = OGSUser(username: "Selected black teammate", id: 3, ranking: 25)
        let selectedWhiteTeammate = OGSUser(username: "Selected white teammate", id: 4, ranking: 26)
        oldData.players = .init(black: selectedBlack, white: selectedWhite)
        oldData.playerPool = [
            1: selectedBlack, 2: selectedWhite,
            3: selectedBlackTeammate, 4: selectedWhiteTeammate,
        ]
        oldData.rengo = true
        oldData.rengoTeams = .init(
            black: [selectedBlack, selectedBlackTeammate],
            white: [selectedWhite, selectedWhiteTeammate]
        )
        oldData.phase = .play
        oldData.moves = Array(oldData.moves.prefix(1))
        oldData.winner = nil
        oldData.outcome = nil
        let game = Game(ogsGame: oldData)
        let selectedPosition = game.initialPosition
        game.currentPosition = selectedPosition
        let analysisBranch = try game.makeMove(move: .placeStone(4, 4), fromAnalyticsPosition: selectedPosition)
        let originalTree = game.moveTree
        let originalBlack = game.blackPlayer
        let originalWhite = game.whitePlayer
        let originalPlayerPool = game.playerByOGSId
        let originalRengoTeams = game.orderedRengoTeam
        let originalPlayerUpdate = game.latestPlayerUpdate
        let originalBlackToMove = game.currentPlayer(with: .black)
        let originalWhiteToMove = game.currentPlayer(with: .white)
        let originalGameDataPool = game.gameData?.playerPool
        let originalGameDataBlackTeam = game.gameData?.rengoTeams?.black
        let originalGameDataWhiteTeam = game.gameData?.rengoTeams?.white
        XCTAssertFalse(game.hasCompleteFinishedGameDetail)

        var incomingData = try XCTUnwrap(detail.rawData["gamedata"] as? [String: Any])
        let incomingBlack: [String: Any] = ["id": 1, "username": "Incoming black", "ranking": 11]
        let incomingWhite: [String: Any] = ["id": 2, "username": "Incoming white", "ranking": 12]
        let incomingBlackCaptain: [String: Any] = ["id": 3, "username": "Incoming black captain", "ranking": 34]
        let incomingWhiteCaptain: [String: Any] = ["id": 4, "username": "Incoming white captain", "ranking": 35]
        incomingData["players"] = ["black": incomingBlack, "white": incomingWhite]
        incomingData["player_pool"] = [
            "1": incomingBlack, "2": incomingWhite,
            "3": incomingBlackCaptain, "4": incomingWhiteCaptain,
        ]
        incomingData["rengo"] = true
        incomingData["rengo_teams"] = [
            "black": [incomingBlack, incomingBlackCaptain],
            "white": [incomingWhite, incomingWhiteCaptain],
        ]
        let captainUpdate: [String: Any] = [
            "players": ["black": 3, "white": 4],
            "rengo_teams": ["black": [3, 1], "white": [4, 2]],
        ]
        let moveExtra: [String: Any] = ["played_by": 3, "player_update": captainUpdate]
        incomingData["moves"] = [
            [0, 0] as [Any], [1, 0] as [Any],
            [0, 1, 1, false, moveExtra] as [Any],
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let incomingGameData = try decoder.decode(
            OGSGame.self, from: JSONSerialization.data(withJSONObject: incomingData)
        )
        let incomingReplay = Game(ogsGame: incomingGameData)
        XCTAssertEqual(incomingReplay.currentPosition.lastMoveNumber, 3)
        XCTAssertEqual(incomingReplay.blackPlayer?.id, 3)
        XCTAssertEqual(incomingReplay.whitePlayer?.id, 4)
        XCTAssertEqual(incomingReplay.orderedRengoTeam[.black]?.map(\.id), [3, 1])
        XCTAssertEqual(incomingReplay.orderedRengoTeam[.white]?.map(\.id), [4, 2])
        XCTAssertNotEqual(incomingReplay.blackPlayer, originalBlack)
        XCTAssertNotEqual(incomingReplay.whitePlayer, originalWhite)
        XCTAssertNotEqual(incomingReplay.playerByOGSId, originalPlayerPool)
        let response: [String: Any] = ["gamedata": incomingData]
        PreviewURLProtocol.configure { request in
            do { try request.respond(response) }
            catch { request.client?.urlProtocol(request, didFailWithError: error) }
        }
        let completed = expectation(description: "shared game preview loaded separately")
        var receivedError: Error?
        service.loadFinishedGamePreview(for: game).sink(receiveCompletion: {
            if case .failure(let error) = $0 { receivedError = error }
            completed.fulfill()
        }, receiveValue: { _ in }).store(in: &cancellables)
        wait(for: [completed], timeout: 3)
        XCTAssertNil(receivedError)
        XCTAssertEqual(game.historyDetailState, .ready)
        XCTAssertEqual(game.historyPreviewPosition?.lastMoveNumber, 3)
        XCTAssertTrue(game.currentPosition === selectedPosition)
        XCTAssertTrue(game.moveTree === originalTree)
        XCTAssertTrue(game.moveTree.contains(analysisBranch))
        XCTAssertEqual(game.blackPlayer, originalBlack)
        XCTAssertEqual(game.whitePlayer, originalWhite)
        XCTAssertEqual(game.blackId, originalBlack?.id)
        XCTAssertEqual(game.whiteId, originalWhite?.id)
        XCTAssertEqual(game.playerByOGSId, originalPlayerPool)
        XCTAssertEqual(game.orderedRengoTeam, originalRengoTeams)
        XCTAssertEqual(game.latestPlayerUpdate, originalPlayerUpdate)
        XCTAssertEqual(game.currentPlayer(with: .black), originalBlackToMove)
        XCTAssertEqual(game.currentPlayer(with: .white), originalWhiteToMove)
        XCTAssertEqual(game.gameData?.playerPool, originalGameDataPool)
        XCTAssertEqual(game.gameData?.rengoTeams?.black, originalGameDataBlackTeam)
        XCTAssertEqual(game.gameData?.rengoTeams?.white, originalGameDataWhiteTeam)
        XCTAssertEqual(game.gameData?.phase, .play)
        XCTAssertEqual(game.gameData?.moves.count, 1)
        XCTAssertNil(game.ogsRawData)
    }

    func testPreviewCooldownUsesOneMinuteFallbackForMissingOrMalformedHeaders() {
        let now = Date(timeIntervalSince1970: 1_000)
        for header in [nil, "", "nonsense", "0", "-5", "0.5", "1e2", "+5", "NaN", "infinity",
                       "Thu, 01 Jan 1970 00:00:00 GMT"] as [String?] {
            let cooldown = FinishedGamePreviewCooldown(now: { now })
            XCTAssertEqual(cooldown.record(retryAfter: header), now.addingTimeInterval(60),
                           "Header: \(String(describing: header))")
            XCTAssertEqual(cooldown.retryNotBefore, now.addingTimeInterval(60))
        }
    }

    func testPreviewCooldownAcceptsDeltaSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_445_412_400)
        let delta = FinishedGamePreviewCooldown(now: { now })
        XCTAssertEqual(delta.record(retryAfter: "120"), now.addingTimeInterval(120))
        for header in ["Wed, 21 Oct 2015 07:28:00 GMT",
                       "Wednesday, 21-Oct-15 07:28:00 GMT",
                       "Wed Oct 21 07:28:00 2015"] {
            let date = FinishedGamePreviewCooldown(now: { now })
            XCTAssertEqual(date.record(retryAfter: header), Date(timeIntervalSince1970: 1_445_412_480),
                           "Header: \(header)")
        }
    }

    func testPreviewCooldownKeepsLatestDeadlineAndPublishesExpiry() {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        var changes: [Date?] = []
        cooldown.changes.sink { changes.append($0) }.store(in: &cancellables)
        XCTAssertEqual(cooldown.record(retryAfter: "120"), clock.now.addingTimeInterval(120))
        clock.advance(by: 10)
        XCTAssertEqual(cooldown.record(retryAfter: "5"), Date(timeIntervalSince1970: 1_120))
        XCTAssertEqual(cooldown.record(retryNotBefore: Date(timeIntervalSince1970: 1_080)),
                       Date(timeIntervalSince1970: 1_120))
        XCTAssertEqual(cooldown.record(retryAfter: "240"), Date(timeIntervalSince1970: 1_250))
        clock.advance(by: 239)
        XCTAssertEqual(cooldown.refresh(), Date(timeIntervalSince1970: 1_250))
        clock.advance(by: 1)
        XCTAssertNil(cooldown.refresh())
        XCTAssertNil(cooldown.retryNotBefore)
        XCTAssertFalse(changes.isEmpty)
        XCTAssertNil(changes.last!)
    }

    func testOffscreenQueuedPreviewsArePrunedAndReentryRequestsOnlyThatRow() throws {
        let service = makeService()
        let games = [1_001, 1_002, 1_003, 1_004].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: requests.load)
        loader.load(games: games, using: service)
        loader.removeDemand(for: games[1])
        loader.removeDemand(for: games[2])
        loader.removeDemand(for: games[0])
        XCTAssertEqual(requests.requestedIDs, [1_001])
        XCTAssertEqual(requests.activeCount, 1, "Begun requests may finish after scrolling offscreen")

        let lastStarted = expectation(description: "remaining visible row starts")
        requests.didStart = { if $0 == 1_004 { lastStarted.fulfill() } }
        try requests.succeed(gameID: 1_001, detail: makeFinishedGameDetail(gameID: 1_001))
        wait(for: [lastStarted], timeout: 3)
        XCTAssertEqual(games[0].historyDetailState, .ready)
        waitForState(.ready, of: games[3]) {
            try requests.succeed(gameID: 1_004, detail: makeFinishedGameDetail(gameID: 1_004))
        }
        XCTAssertEqual(requests.requestedIDs, [1_001, 1_004])
        XCTAssertEqual(games[1].historyDetailState, .notRequested)
        XCTAssertEqual(games[2].historyDetailState, .notRequested)

        loader.load(games: [games[1], games[1]], using: service)
        XCTAssertEqual(requests.requestedIDs, [1_001, 1_004, 1_002])
        XCTAssertEqual(requests.peakActiveCount, 1)
        loader.cancel()
    }

    func testFastScrollingDoesNotAccumulateOffscreenRequestsAndKeepsFourRequestCap() throws {
        let service = makeService()
        let active = [1_011, 1_012, 1_013, 1_014].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 4, loadPreview: requests.load)
        loader.load(games: active, using: service)
        for page in 0..<10 {
            let transient = (0..<10).map { makeHistoryGame(id: 2_000 + page * 10 + $0) }
            loader.load(games: transient, using: service)
            transient.forEach { loader.removeDemand(for: $0) }
        }
        let visible = makeHistoryGame(id: 1_015)
        loader.load(games: [visible], using: service)
        XCTAssertEqual(requests.requestedIDs, [1_011, 1_012, 1_013, 1_014])

        let visibleStarted = expectation(description: "current visible demand gets the next slot")
        requests.didStart = { if $0 == 1_015 { visibleStarted.fulfill() } }
        try requests.succeed(gameID: 1_011, detail: makeFinishedGameDetail(gameID: 1_011))
        wait(for: [visibleStarted], timeout: 3)
        XCTAssertEqual(requests.requestedIDs, [1_011, 1_012, 1_013, 1_014, 1_015])
        XCTAssertEqual(requests.peakActiveCount, 4)
        loader.cancel()
        XCTAssertEqual(requests.activeCount, 0)
    }

    func testOneRateLimitedLoaderPausesOtherLoaderAndManualRetryUntilSharedExpiry() {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let failed = makeHistoryGame(id: 1_021)
        let firstPending = makeHistoryGame(id: 1_022)
        let secondPending = makeHistoryGame(id: 1_023)
        let firstRequests = ControlledPreviewRequests()
        let secondRequests = ControlledPreviewRequests()
        let first = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: firstRequests.load)
        let second = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: secondRequests.load)
        first.load(games: [failed, firstPending], using: service)
        waitForState(.unavailable, of: failed) {
            firstRequests.fail(gameID: 1_021,
                               error: FinishedGamePreviewRateLimitError(retryNotBefore: clock.now.addingTimeInterval(60)))
        }
        second.load(games: [secondPending], using: service)
        first.retry(game: failed, using: service)
        drainMainQueue()
        XCTAssertEqual(cooldown.retryNotBefore, clock.now.addingTimeInterval(60))
        XCTAssertEqual(firstRequests.requestedIDs, [1_021])
        XCTAssertTrue(secondRequests.requestedIDs.isEmpty)
        XCTAssertEqual(failed.historyDetailState, .unavailable)
        XCTAssertEqual(firstPending.historyDetailState, .notRequested)
        XCTAssertEqual(secondPending.historyDetailState, .notRequested)

        let firstResumed = expectation(description: "first loader's pending visible row resumes")
        let secondResumed = expectation(description: "second loader's pending visible row resumes")
        firstRequests.didStart = { if $0 == 1_022 { firstResumed.fulfill() } }
        secondRequests.didStart = { if $0 == 1_023 { secondResumed.fulfill() } }
        clock.advance(by: 60)
        cooldown.refresh()
        wait(for: [firstResumed, secondResumed], timeout: 3)
        XCTAssertEqual(firstRequests.requestedIDs, [1_021, 1_022])
        XCTAssertEqual(secondRequests.requestedIDs, [1_023])
        XCTAssertEqual(failed.historyDetailState, .unavailable, "Expiry must not bulk retry failed rows")
        first.cancel()
        second.cancel()
    }

    func testCooldownExpiryResumesOnlyVisiblePendingRowsAndDoesNotRetryFailedRows() throws {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let games = [1_031, 1_032, 1_033].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: requests.load)
        loader.load(games: games, using: service)
        waitForState(.unavailable, of: games[0]) {
            requests.fail(gameID: 1_031,
                          error: FinishedGamePreviewRateLimitError(retryNotBefore: clock.now.addingTimeInterval(60)))
        }
        loader.removeDemand(for: games[1])
        let visibleStarted = expectation(description: "only still-visible pending row starts")
        requests.didStart = { if $0 == 1_033 { visibleStarted.fulfill() } }
        clock.advance(by: 60)
        cooldown.refresh()
        wait(for: [visibleStarted], timeout: 3)
        waitForState(.ready, of: games[2]) {
            try requests.succeed(gameID: 1_033, detail: makeFinishedGameDetail(gameID: 1_033))
        }
        XCTAssertEqual(requests.requestedIDs, [1_031, 1_033])
        XCTAssertEqual(games[0].historyDetailState, .unavailable)
        XCTAssertEqual(games[1].historyDetailState, .notRequested)
        loader.load(games: [games[1]], using: service)
        XCTAssertEqual(requests.requestedIDs, [1_031, 1_033, 1_032])
        loader.cancel()
    }

    func testCancelDuringCooldownCannotResumeDiscardedVisibleDemand() {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let games = [1_041, 1_042].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: requests.load)
        loader.load(games: games, using: service)
        waitForState(.unavailable, of: games[0]) {
            requests.fail(gameID: 1_041,
                          error: FinishedGamePreviewRateLimitError(retryNotBefore: clock.now.addingTimeInterval(60)))
        }
        loader.cancel()
        clock.advance(by: 60)
        cooldown.refresh()
        drainMainQueue()
        XCTAssertEqual(requests.requestedIDs, [1_041])
        XCTAssertEqual(games[1].historyDetailState, .notRequested)
        XCTAssertNil(games[1].historyDetailRequestID)
        XCTAssertEqual(requests.activeCount, 0)
    }

    func testAuthenticationChangeDuringCooldownDoesNotResumeOldQueue() throws {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let games = [1_051, 1_052].map(makeHistoryGame(id:))
        let requests = ControlledPreviewRequests()
        let loader = FinishedGamePreviewLoader(maximumConcurrentRequests: 1, loadPreview: requests.load)
        loader.load(games: games, using: service)
        waitForState(.unavailable, of: games[0]) {
            requests.fail(gameID: 1_051,
                          error: FinishedGamePreviewRateLimitError(retryNotBefore: clock.now.addingTimeInterval(60)))
        }
        try setAccount(17, on: service)
        clock.advance(by: 60)
        cooldown.refresh()
        drainMainQueue()
        XCTAssertEqual(requests.requestedIDs, [1_051])
        XCTAssertEqual(games[1].historyDetailState, .notRequested)
        XCTAssertNil(games[1].historyDetailRequestID)
        let fresh = makeHistoryGame(id: 1_053)
        loader.load(games: [fresh], using: service)
        XCTAssertEqual(requests.requestedIDs, [1_051, 1_053])
        loader.cancel()
    }

    func testHTTP429RecordsRetryAfterBlocksNetworkButAllowsCachedPreviews() throws {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let gameID = Int.random(in: 1_500_000_000...1_900_000_000)
        let failed = makeHistoryGame(id: gameID)
        let counter = PreviewRequestCounter()
        PreviewURLProtocol.configure { request in
            counter.increment()
            do {
                try request.respond(["detail": "Fixture rate limit"], statusCode: 429,
                                    headers: ["Retry-After": "120"])
            } catch { request.client?.urlProtocol(request, didFailWithError: error) }
        }
        let failedRequest = expectation(description: "HTTP 429 becomes typed preview failure")
        var receivedError: Error?
        var receivedValue = false
        service.loadFinishedGamePreview(for: failed).sink(receiveCompletion: {
            if case .failure(let error) = $0 { receivedError = error }
            failedRequest.fulfill()
        }, receiveValue: { receivedValue = true }).store(in: &cancellables)
        wait(for: [failedRequest], timeout: 3)
        XCTAssertEqual((receivedError as? FinishedGamePreviewRateLimitError)?.retryNotBefore,
                       clock.now.addingTimeInterval(120))
        XCTAssertEqual(cooldown.retryNotBefore, clock.now.addingTimeInterval(120))
        XCTAssertFalse(receivedValue)
        XCTAssertEqual(counter.count, 1)
        XCTAssertNil(FinishedGameCache.shared.data(forGameID: gameID))

        let blocked = makeHistoryGame(id: gameID + 1)
        let blockedRequest = expectation(description: "uncached preview is rejected without another HTTP request")
        var blockedError: Error?
        service.loadFinishedGamePreview(for: blocked).sink(receiveCompletion: {
            if case .failure(let error) = $0 { blockedError = error }
            blockedRequest.fulfill()
        }, receiveValue: { _ in XCTFail("Blocked preview must not emit a value") }).store(in: &cancellables)
        wait(for: [blockedRequest], timeout: 3)
        XCTAssertEqual((blockedError as? FinishedGamePreviewRateLimitError)?.retryNotBefore,
                       clock.now.addingTimeInterval(120))
        XCTAssertEqual(counter.count, 1)

        let cached = makeHistoryGame(id: gameID + 2)
        let detail = try makeFinishedGameDetail(gameID: gameID + 2)
        FinishedGameCache.shared.store(try JSONSerialization.data(withJSONObject: detail.rawData),
                                       forGameID: gameID + 2,
                                       ifGeneration: FinishedGameCache.shared.currentGeneration)
        let loader = FinishedGamePreviewLoader()
        waitForState(.ready, of: cached) {
            loader.load(games: [blocked, cached], using: service)
        }
        XCTAssertEqual(cached.finishedHistoryPosition?.lastMoveNumber, 3)
        XCTAssertEqual(blocked.historyDetailState, .notRequested)
        XCTAssertEqual(counter.count, 1, "A cache hit behind blocked network demand must stay usable")
        loader.cancel()

        let corruptID = gameID + 3
        FinishedGameCache.shared.store(Data("invalid cached JSON".utf8), forGameID: corruptID,
                                       ifGeneration: FinishedGameCache.shared.currentGeneration)
        let corruptRequest = expectation(description: "corrupt cache cannot bypass network cooldown")
        var corruptError: Error?
        service.loadFinishedGamePreview(for: makeHistoryGame(id: corruptID)).sink(receiveCompletion: {
            if case .failure(let error) = $0 { corruptError = error }
            corruptRequest.fulfill()
        }, receiveValue: { _ in XCTFail("Corrupt cache must not emit detail") }).store(in: &cancellables)
        wait(for: [corruptRequest], timeout: 3)
        XCTAssertNotNil(corruptError as? FinishedGamePreviewRateLimitError)
        XCTAssertEqual(counter.count, 1)
    }

    func testCancelledHTTP429ResponseCannotStartSharedCooldown() throws {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let game = makeHistoryGame(id: Int.random(in: 1_500_000_000...1_900_000_000))
        let started = expectation(description: "request starts before cancellation")
        var heldRequest: PreviewURLProtocol?
        PreviewURLProtocol.configure { request in
            DispatchQueue.main.async {
                heldRequest = request
                started.fulfill()
            }
        }
        let loader = FinishedGamePreviewLoader()
        loader.load(games: [game], using: service)
        wait(for: [started], timeout: 3)
        loader.cancel()
        let unexpectedCooldown = expectation(description: "cancelled response cannot set a cooldown")
        unexpectedCooldown.isInverted = true
        cooldown.changes.filter { $0 != nil }.prefix(1)
            .sink { _ in unexpectedCooldown.fulfill() }.store(in: &cancellables)
        try XCTUnwrap(heldRequest).respond(["detail": "Cancelled fixture rate limit"], statusCode: 429,
                                         headers: ["Retry-After": "120"])
        wait(for: [unexpectedCooldown], timeout: 0.5)
        XCTAssertNil(cooldown.retryNotBefore)
        XCTAssertEqual(game.historyDetailState, .notRequested)
        XCTAssertNil(game.historyDetailRequestID)
    }

    func testPreviousAccountHTTP429ResponseCannotStartSharedCooldown() throws {
        let clock = PreviewClock()
        let cooldown = FinishedGamePreviewCooldown(now: { clock.now })
        let service = makeService(cooldown: cooldown)
        let game = makeHistoryGame(id: Int.random(in: 1_500_000_000...1_900_000_000))
        let started = expectation(description: "old account request starts")
        var heldRequest: PreviewURLProtocol?
        PreviewURLProtocol.configure { request in
            DispatchQueue.main.async {
                heldRequest = request
                started.fulfill()
            }
        }
        let completed = expectation(description: "old account HTTP 429 is rejected as stale")
        var receivedError: Error?
        service.loadFinishedGamePreview(for: game).sink(receiveCompletion: {
            if case .failure(let error) = $0 { receivedError = error }
            completed.fulfill()
        }, receiveValue: { _ in XCTFail("Old account response must not emit detail") }).store(in: &cancellables)
        wait(for: [started], timeout: 3)
        try setAccount(18, on: service)
        try XCTUnwrap(heldRequest).respond(["detail": "Old account fixture rate limit"], statusCode: 429,
                                         headers: ["Retry-After": "120"])
        wait(for: [completed], timeout: 3)
        guard let error = receivedError as? OGSServiceError,
              case .staleAuthenticationContext = error else {
            XCTFail("Expected account generation to reject HTTP 429 before recording cooldown")
            return
        }
        XCTAssertNil(cooldown.retryNotBefore)
        XCTAssertNil(game.gameData)
    }

    private func makeHistoryGame(id: Int) -> Game {
        let game = Game(width: 9, height: 9, blackName: "Black", whiteName: "White", gameId: .OGS(id))
        game.historySummary = FinishedGameSummary(
            gameID: id, blackPlayerID: 1, whitePlayerID: 2, width: 9, height: 9,
            outcome: "Resignation", blackLost: false, whiteLost: true
        )
        return game
    }

    private func makeFinishedGameDetail(gameID: Int) throws -> FinishedGameDetail {
        let gameData: [String: Any] = [
            "game_id": gameID, "black_player_id": 1, "white_player_id": 2,
            "width": 9, "height": 9, "game_name": "Preview fixture",
            "handicap": 0, "ranked": false, "rules": "japanese", "phase": "finished",
            "initial_player": "black", "initial_state": ["black": "", "white": ""],
            "komi": 6.5, "moves": [[0, 0], [1, 0], [0, 1]],
            "outcome": "Resignation", "winner": 1,
            "players": ["black": ["id": 1, "username": "Black"],
                        "white": ["id": 2, "username": "White"]],
            "time_control": ["time_control": "none"],
            "clock": ["black_player_id": 1, "white_player_id": 2, "current_player": 2,
                      "last_move": 0, "black_time": 0, "white_time": 0],
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try decoder.decode(OGSGame.self, from: JSONSerialization.data(withJSONObject: gameData))
        return FinishedGameDetail(ogsGame: ogsGame, rawData: ["gamedata": gameData])
    }

    private func makeService(cooldown: FinishedGamePreviewCooldown = FinishedGamePreviewCooldown()) -> OGSService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewURLProtocol.self]
        configuration.httpCookieStorage = nil
        let suite = "com.honganhkhoa.Surround.PreviewTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://preview.ogs.test")!),
            httpClient: AlamofireOGSHTTPClient(session: Session(configuration: configuration), cookieStorage: nil),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(status: .disconnected),
            connectsAutomatically: false, usesSurroundOverviewService: false, enablesAppSideEffects: false,
            startsTimers: false, installsObservers: false,
            finishedGamePreviewCooldown: cooldown
        )
    }

    private func setAccount(_ id: Int, on service: OGSService) throws {
        let payload: [String: Any] = ["user": ["id": id, "username": "Fixture account", "anonymous": false]]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        service.ogsUIConfig = try decoder.decode(OGSUIConfig.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func waitForState(_ state: FinishedGameDetailState, of game: Game,
                              action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let reachedState = expectation(description: "preview \(game.ogsID ?? 0) becomes \(state)")
        game.$historyDetailState.filter { $0 == state }.prefix(1)
            .sink { _ in reachedState.fulfill() }.store(in: &cancellables)
        do { try action() }
        catch { XCTFail("Preview fixture failed: \(error)", file: file, line: line) }
        wait(for: [reachedState], timeout: 3)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "scheduled publisher events drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
    }

    private final class PreviewRequestCounter {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    private final class PreviewClock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(by interval: TimeInterval) { now.addTimeInterval(interval) }
    }

    private final class ControlledPreviewRequests {
        private struct Request {
            let game: Game
            let subject: PassthroughSubject<Void, Error>
        }
        private var requests: [Int: Request] = [:]
        private(set) var requestedIDs: [Int] = []
        private(set) var activeCount = 0
        private(set) var peakActiveCount = 0
        private(set) var cancelCount = 0
        var didStart: ((Int) -> Void)?

        func load(_ game: Game, _ service: OGSService) -> AnyPublisher<Void, Error> {
            let id = game.ogsID!
            let subject = PassthroughSubject<Void, Error>()
            requests[id] = Request(game: game, subject: subject)
            requestedIDs.append(id)
            activeCount += 1
            peakActiveCount = max(peakActiveCount, activeCount)
            didStart?(id)
            var terminated = false
            let terminate: (Bool) -> Void = { [weak self] cancelled in
                guard !terminated else { return }
                terminated = true
                self?.activeCount -= 1
                if cancelled { self?.cancelCount += 1 }
            }
            return subject.handleEvents(receiveCompletion: { _ in terminate(false) },
                                        receiveCancel: { terminate(true) }).eraseToAnyPublisher()
        }

        func succeed(gameID: Int, detail: FinishedGameDetail) throws {
            let request = try XCTUnwrap(requests[gameID])
            OGSService.applyFinishedGameDetail(detail, to: request.game)
            request.subject.send(())
            request.subject.send(completion: .finished)
        }

        func finishWithoutDetail(gameID: Int) {
            requests[gameID]?.subject.send(())
            requests[gameID]?.subject.send(completion: .finished)
        }

        func fail(gameID: Int, error: Error = URLError(.badServerResponse)) {
            requests[gameID]?.subject.send(completion: .failure(error))
        }
    }

    /// Deliberately violates the publisher contract so late callbacks exercise
    /// the loader's request ownership and cancellation fences as well.
    private final class LatePreviewPublisher: Publisher {
        typealias Output = Void
        typealias Failure = Error
        private var subscriber: AnySubscriber<Void, Error>?
        private(set) var wasCancelled = false

        func receive<S: Subscriber>(subscriber: S) where S.Input == Void, S.Failure == Error {
            self.subscriber = AnySubscriber(subscriber)
            subscriber.receive(subscription: LateSubscription { [weak self] in self?.wasCancelled = true })
        }

        func sendAfterCancellation() {
            _ = subscriber?.receive(())
            subscriber?.receive(completion: .finished)
        }

        private final class LateSubscription: Subscription {
            let onCancel: () -> Void
            init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
            func request(_ demand: Subscribers.Demand) {}
            func cancel() { onCancel() }
        }
    }

    private func makeSummary(outcome: String? = nil, blackLost: Bool? = nil,
                             whiteLost: Bool? = nil, annulled: Bool? = nil) -> FinishedGameSummary {
        FinishedGameSummary(gameID: 101, blackPlayerID: 1, whitePlayerID: 2, width: 9, height: 9,
                            outcome: outcome, blackLost: blackLost, whiteLost: whiteLost, annulled: annulled)
    }

    private func summaryPayload() -> [String: Any] {
        [
            "id": 101, "width": 9, "height": 9, "outcome": "Resignation",
            "black_lost": false, "white_lost": true, "annulled": false,
            "players": ["black": ["id": 1, "username": "Black"],
                        "white": ["id": 2, "username": "White"]],
        ]
    }

    private func decodeSummary(_ payload: [String: Any]) throws -> FinishedGameSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FinishedGameSummary.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private final class PreviewURLProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var handler: ((PreviewURLProtocol) -> Void)?

        static func configure(_ handler: ((PreviewURLProtocol) -> Void)?) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lock.lock()
            let handler = Self.handler
            Self.lock.unlock()
            if let handler { handler(self) }
            else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
        }
        override func stopLoading() {}

        func respond(_ payload: [String: Any], statusCode: Int = 200,
                     headers: [String: String] = [:]) throws {
            var responseHeaders = headers
            responseHeaders["Content-Type"] = "application/json"
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                                           headerFields: responseHeaders)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

final class FinishedGameCacheTests: XCTestCase {
    private let fileManager = FileManager.default
    private var scratchDirectories: [URL] = []

    override func tearDownWithError() throws {
        defer { scratchDirectories.removeAll() }
        for directory in scratchDirectories {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
        try super.tearDownWithError()
    }

    func testExactByteBudgetAndExactLimitPayloadRemainCacheable() throws {
        let (cache, directory) = try makeCache(maximumBytes: 10)
        store(Data(repeating: 1, count: 3), gameID: 1, in: cache)
        try setModificationDate(100, gameID: 1, in: directory)
        store(Data(repeating: 2, count: 7), gameID: 2, in: cache)

        XCTAssertEqual(cache.data(forGameID: 1), Data(repeating: 1, count: 3))
        XCTAssertEqual(cache.data(forGameID: 2), Data(repeating: 2, count: 7))
        XCTAssertEqual(try totalFileBytes(in: directory), 10)

        store(Data([3]), gameID: 3, in: cache)
        XCTAssertNil(cache.data(forGameID: 1))
        XCTAssertEqual(cache.data(forGameID: 2), Data(repeating: 2, count: 7))
        XCTAssertEqual(cache.data(forGameID: 3), Data([3]))
        XCTAssertEqual(try totalFileBytes(in: directory), 8)

        let exactLimit = Data(repeating: 4, count: 10)
        store(exactLimit, gameID: 4, in: cache)
        XCTAssertEqual(try fileNames(in: directory), ["4.json"])
        XCTAssertEqual(cache.data(forGameID: 4), exactLimit)
        XCTAssertEqual(try totalFileBytes(in: directory), 10)
    }

    func testOverwriteUsesReplacementSizeAndProtectsTheReplacement() throws {
        let (cache, directory) = try makeCache(maximumBytes: 12)
        try seed(Data(repeating: 1, count: 4), gameID: 1, modified: 300, in: directory)
        try seed(Data(repeating: 2, count: 4), gameID: 2, modified: 100, in: directory)
        try seed(Data(repeating: 3, count: 4), gameID: 3, modified: 200, in: directory)

        let replacement = Data(repeating: 9, count: 6)
        store(replacement, gameID: 1, in: cache)
        XCTAssertEqual(try fileNames(in: directory), ["1.json", "3.json"])
        XCTAssertEqual(cache.data(forGameID: 1), replacement)
        XCTAssertEqual(cache.data(forGameID: 3), Data(repeating: 3, count: 4))
        XCTAssertEqual(try totalFileBytes(in: directory), 10)

        store(Data([8, 8]), gameID: 1, in: cache)
        XCTAssertEqual(try fileNames(in: directory), ["1.json", "3.json"])
        XCTAssertEqual(cache.data(forGameID: 1), Data([8, 8]))
        XCTAssertEqual(try totalFileBytes(in: directory), 6)
    }

    func testOversizedReplacementPreservesExistingEntryWithoutPruning() throws {
        let (cache, directory) = try makeCache(maximumBytes: 8)
        let existing = Data(repeating: 1, count: 4)
        let other = Data(repeating: 2, count: 6)
        try seed(existing, gameID: 1, modified: 100, in: directory)
        try seed(other, gameID: 2, modified: 200, in: directory)
        let originalDate = try modificationDate(gameID: 1, in: directory)

        store(Data(repeating: 9, count: 9), gameID: 1, in: cache)
        store(Data(repeating: 9, count: 9), gameID: 3, in: cache)

        XCTAssertEqual(try fileNames(in: directory), ["1.json", "2.json"])
        XCTAssertEqual(cache.data(forGameID: 1), existing)
        XCTAssertEqual(cache.data(forGameID: 2), other)
        XCTAssertNil(cache.data(forGameID: 3))
        XCTAssertEqual(try modificationDate(gameID: 1, in: directory), originalDate)
        XCTAssertEqual(try totalFileBytes(in: directory), 10)
    }

    func testOldestContentModificationDateWinsAcrossGameIDs() throws {
        let (cache, directory) = try makeCache(maximumBytes: 6)
        // The older file sorts after the newer file by name, so filename-only
        // eviction cannot satisfy this content-modification-date assertion.
        try seed(Data(repeating: 1, count: 3), gameID: 2, modified: 100, in: directory)
        try seed(Data(repeating: 2, count: 3), gameID: 10, modified: 200, in: directory)

        store(Data(repeating: 3, count: 3), gameID: 99, in: cache)

        XCTAssertEqual(try fileNames(in: directory), ["10.json", "99.json"])
        XCTAssertNil(cache.data(forGameID: 2))
        XCTAssertEqual(cache.data(forGameID: 10), Data(repeating: 2, count: 3))
        XCTAssertEqual(cache.data(forGameID: 99), Data(repeating: 3, count: 3))
        XCTAssertEqual(try totalFileBytes(in: directory), 6)
        XCTAssertEqual(try modificationDate(gameID: 10, in: directory), Date(timeIntervalSince1970: 200))
    }

    func testEqualModificationDatesUseDeterministicFilenameOrder() throws {
        let (cache, directory) = try makeCache(maximumBytes: 6)
        try seed(Data(repeating: 1, count: 3), gameID: 2, modified: 100, in: directory)
        try seed(Data(repeating: 2, count: 3), gameID: 10, modified: 100, in: directory)

        store(Data(repeating: 3, count: 3), gameID: 99, in: cache)

        XCTAssertEqual(try fileNames(in: directory), ["2.json", "99.json"])
        XCTAssertNil(cache.data(forGameID: 10))
        XCTAssertEqual(cache.data(forGameID: 2), Data(repeating: 1, count: 3))
        XCTAssertEqual(try totalFileBytes(in: directory), 6)
    }

    func testSuccessfulWriteIsProtectedEvenWhenExistingFileHasFutureModificationDate() throws {
        let (cache, directory) = try makeCache(maximumBytes: 6)
        try seed(Data(repeating: 1, count: 4), gameID: 1,
                 modified: Date().addingTimeInterval(86_400).timeIntervalSince1970, in: directory)
        let newlyWritten = Data(repeating: 2, count: 4)

        store(newlyWritten, gameID: 2, in: cache)

        XCTAssertEqual(try fileNames(in: directory), ["2.json"])
        XCTAssertEqual(cache.data(forGameID: 2), newlyWritten)
        XCTAssertNil(cache.data(forGameID: 1))
        XCTAssertEqual(try totalFileBytes(in: directory), 4)
    }

    func testCorruptRecognizedFileCountsTowardBudgetWithoutDecoding() throws {
        let (cache, directory) = try makeCache(maximumBytes: 4)
        try seed(Data("not JSON".utf8), gameID: 1, modified: 100, in: directory)
        try seed(Data([2, 2]), gameID: 2, modified: 200, in: directory)

        store(Data([3, 3]), gameID: 3, in: cache)

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL(gameID: 1, in: directory).path))
        XCTAssertEqual(cache.data(forGameID: 2), Data([2, 2]))
        XCTAssertEqual(cache.data(forGameID: 3), Data([3, 3]))
        XCTAssertEqual(try totalFileBytes(in: directory), 4)
    }

    func testUnknownFilesDirectoriesAndSymlinksAreUntouched() throws {
        let (cache, directory) = try makeCache(maximumBytes: 8)
        try seed(Data(repeating: 1, count: 4), gameID: 1, modified: 100, in: directory)
        let unknownData = Data(repeating: 7, count: 128)
        let unknownNames = ["01.json", "+1.json", "4.JSON", "4.json.tmp", "notes.json", "9223372036854775808.json"]
        for name in unknownNames {
            try unknownData.write(to: directory.appendingPathComponent(name))
        }
        let nestedDirectory = directory.appendingPathComponent("7.json", isDirectory: true)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: false)
        let nestedFile = nestedDirectory.appendingPathComponent("keep")
        try unknownData.write(to: nestedFile)
        let externalFile = directory.deletingLastPathComponent().appendingPathComponent("link-target")
        try unknownData.write(to: externalFile)
        let link = directory.appendingPathComponent("3.json")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: externalFile)

        store(Data(repeating: 2, count: 4), gameID: 2, in: cache)

        // Both recognized entries fit exactly. Counting any large unknown item
        // would incorrectly evict the older recognized entry.
        XCTAssertEqual(cache.data(forGameID: 1), Data(repeating: 1, count: 4))
        XCTAssertEqual(cache.data(forGameID: 2), Data(repeating: 2, count: 4))
        XCTAssertEqual(try modificationDate(gameID: 1, in: directory), Date(timeIntervalSince1970: 100))
        for name in unknownNames {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), unknownData, name)
        }
        XCTAssertEqual(try Data(contentsOf: nestedFile), unknownData)
        XCTAssertEqual(try Data(contentsOf: externalFile), unknownData)
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: link.path), externalFile.path)
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType,
                       .typeSymbolicLink)
    }

    func testReadHitHasNoTTLAndDoesNotPruneOrRefreshContentModificationDate() throws {
        let (cache, directory) = try makeCache(maximumBytes: 3)
        let oldest = Data([1, 1, 1])
        let newest = Data([2, 2, 2])
        try seed(oldest, gameID: 1, modified: 100, in: directory)
        try seed(newest, gameID: 2, modified: 200, in: directory)
        let oldDate = try modificationDate(gameID: 1, in: directory)
        let newDate = try modificationDate(gameID: 2, in: directory)

        XCTAssertTrue(cache.contains(gameID: 1))
        XCTAssertEqual(cache.data(forGameID: 1), oldest)
        XCTAssertEqual(cache.data(forGameID: 1), oldest)

        XCTAssertEqual(try fileNames(in: directory), ["1.json", "2.json"])
        XCTAssertEqual(try totalFileBytes(in: directory), 6)
        XCTAssertEqual(try modificationDate(gameID: 1, in: directory), oldDate)
        XCTAssertEqual(try modificationDate(gameID: 2, in: directory), newDate)
        XCTAssertEqual(cache.data(forGameID: 2), newest)
    }

    func testFailedAtomicWriteDoesNotPruneAnExistingOverBudgetCache() throws {
        let (cache, directory) = try makeCache(maximumBytes: 4)
        let existing = Data(repeating: 1, count: 6)
        try seed(existing, gameID: 1, modified: 100, in: directory)
        let blockedDestination = fileURL(gameID: 2, in: directory)
        try fileManager.createDirectory(at: blockedDestination, withIntermediateDirectories: false)
        let sentinel = blockedDestination.appendingPathComponent("keep")
        try Data([9]).write(to: sentinel)

        store(Data([2, 2]), gameID: 2, in: cache)

        XCTAssertEqual(cache.data(forGameID: 1), existing)
        XCTAssertEqual(try modificationDate(gameID: 1, in: directory), Date(timeIntervalSince1970: 100))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([9]))
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: blockedDestination.path)[.type] as? FileAttributeType,
                       .typeDirectory)
    }

    func testConcurrentAtomicWritesKeepCompletePayloadsWithinTheByteBudget() throws {
        let (cache, directory) = try makeCache(maximumBytes: 160)
        let writes = (0..<48).map { index in
            (gameID: index % 8 + 1,
             data: Data(("revision:\(index):" + String(repeating: String(index % 10), count: 32 + index % 9)).utf8))
        }
        let expectedPayloads = Dictionary(grouping: writes, by: { $0.gameID }).mapValues { $0.map { $0.data } }
        let generation = cache.currentGeneration
        let observationLock = NSLock()
        var observations: [(gameID: Int, data: Data)] = []

        DispatchQueue.concurrentPerform(iterations: writes.count) { index in
            let write = writes[index]
            cache.store(write.data, forGameID: write.gameID, ifGeneration: generation)
            if let observed = try? Data(contentsOf: fileURL(gameID: write.gameID, in: directory)) {
                observationLock.lock()
                observations.append((write.gameID, observed))
                observationLock.unlock()
            }
        }

        for observation in observations {
            XCTAssertTrue(expectedPayloads[observation.gameID]?.contains(observation.data) == true)
        }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        var totalBytes = 0
        for file in files {
            let gameID = try XCTUnwrap(Int(file.deletingPathExtension().lastPathComponent))
            XCTAssertEqual(file.lastPathComponent, "\(gameID).json")
            let payload = try Data(contentsOf: file)
            XCTAssertTrue(expectedPayloads[gameID]?.contains(payload) == true)
            totalBytes += payload.count
        }
        XCTAssertLessThanOrEqual(totalBytes, 160)
    }

    func testClearAdvancesGenerationAndRejectsLateWritesWithoutRecreatingTheDirectory() throws {
        let (cache, directory) = try makeCache(maximumBytes: 4)
        let oldGeneration = cache.currentGeneration
        cache.store(Data([1, 1]), forGameID: 1, ifGeneration: oldGeneration)

        cache.clear()

        XCTAssertEqual(cache.currentGeneration, oldGeneration + 1)
        XCTAssertNil(cache.data(forGameID: 1)) // Flush the asynchronously queued directory removal.
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        cache.store(Data([9, 9]), forGameID: 1, ifGeneration: oldGeneration)
        XCTAssertNil(cache.data(forGameID: 1))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))

        let newGeneration = cache.currentGeneration
        cache.store(Data(repeating: 2, count: 4), forGameID: 2, ifGeneration: newGeneration)
        cache.store(Data([9, 9]), forGameID: 3, ifGeneration: oldGeneration)
        XCTAssertEqual(try fileNames(in: directory), ["2.json"])
        XCTAssertEqual(cache.data(forGameID: 2), Data(repeating: 2, count: 4))

        cache.clear()
        XCTAssertEqual(cache.currentGeneration, newGeneration + 1)
        XCTAssertNil(cache.data(forGameID: 2))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        store(Data([4]), gameID: 4, in: cache)
        XCTAssertEqual(try fileNames(in: directory), ["4.json"])
        XCTAssertEqual(cache.data(forGameID: 4), Data([4]))
    }

    private func makeCache(maximumBytes: Int) throws -> (FinishedGameCache, URL) {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("FinishedGameCacheTests-\(UUID().uuidString)",
                                                                           isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: false)
        scratchDirectories.append(scratch)
        let directory = scratch.appendingPathComponent("FinishedGames", isDirectory: true)
        return (FinishedGameCache(directoryURL: directory, maximumBytes: maximumBytes), directory)
    }

    private func store(_ data: Data, gameID: Int, in cache: FinishedGameCache) {
        cache.store(data, forGameID: gameID, ifGeneration: cache.currentGeneration)
    }

    private func seed(_ data: Data, gameID: Int, modified: TimeInterval, in directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(gameID: gameID, in: directory), options: .atomic)
        try setModificationDate(modified, gameID: gameID, in: directory)
    }

    private func fileURL(gameID: Int, in directory: URL) -> URL {
        directory.appendingPathComponent("\(gameID).json")
    }

    private func setModificationDate(_ timestamp: TimeInterval, gameID: Int, in directory: URL) throws {
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: timestamp)],
                                      ofItemAtPath: fileURL(gameID: gameID, in: directory).path)
    }

    private func modificationDate(gameID: Int, in directory: URL) throws -> Date {
        try XCTUnwrap(fileManager.attributesOfItem(atPath: fileURL(gameID: gameID, in: directory).path)[.modificationDate] as? Date)
    }

    private func fileNames(in directory: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func totalFileBytes(in directory: URL) throws -> Int {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .reduce(0) { total, file in total + (try Data(contentsOf: file)).count }
    }
}
