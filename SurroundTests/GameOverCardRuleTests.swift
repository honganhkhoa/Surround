//
//  GameOverCardRuleTests.swift
//  SurroundTests
//
//  Which challenge leads a finished game's popover: one from the opponent,
//  made after the game, with its board, rules, rankedness and clock.
//

import XCTest

final class GameOverCardRuleTests: XCTestCase {
    private var preferenceSuites = [String]()
    /// A game holds its service weakly; these keep each test's alive.
    private var services = [OGSService]()

    override func tearDown() {
        services.removeAll()
        preferenceSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    // MARK: Builders

    private func makeService(user: OGSUser?) -> OGSService {
        let suite = "com.honganhkhoa.Surround.GameOverCardRuleTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(),
            preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(),
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false,
            installsObservers: false
        )
        service.user = user
        services.append(service)
        return service
    }

    /// Game 26268404, which the user played as White: 19×19, Chinese rules,
    /// unranked, a 30 min Fischer clock and a handicap of 5. White won by
    /// resignation unless `over` is false.
    private func ownGame(over: Bool = true) throws -> Game {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        if over {
            data.phase = .finished
            data.outcome = "Resignation"
            data.winner = data.players.white.id
        }
        let game = Game(ogsGame: data)
        game.ogs = makeService(user: try XCTUnwrap(game.whitePlayer))
        return game
    }

    /// The opponent's challenge with the game's settings, without its
    /// handicap, made after the game.
    private func challenge(_ id: Int, gameID: Int = 26_268_500, after game: Game) throws -> OGSDirectChallenge {
        let settings = try XCTUnwrap(game.gameData)
        var challenge = OGSChallengeSampleData.sampleChallenge
        challenge.id = id
        challenge.challenger = game.blackPlayer
        challenge.challenged = game.whitePlayer
        challenge.game.id = gameID
        challenge.game.width = settings.width
        challenge.game.height = settings.height
        challenge.game.rules = settings.rules
        challenge.game.ranked = settings.ranked
        challenge.game.timeControl = settings.timeControl
        challenge.game.handicap = 0
        challenge.game.komi = nil
        return challenge
    }

    // MARK: The rule

    func testTheOpponentsChallengeWithTheGamesSettingsLeads() throws {
        let game = try ownGame()
        let offered = try challenge(95_004, after: game)
        XCTAssertFalse(offered.isUnusual)
        XCTAssertEqual(GameOverCardRule.challengeID(for: game, among: [offered]), 95_004)
        XCTAssertNil(GameOverCardRule.challengeID(for: game, among: []))
    }

    func testEverySettingMustMatch() throws {
        let game = try ownGame()
        let gameID = try XCTUnwrap(game.ogsID)
        let changes: [(String, (inout OGSDirectChallenge) -> Void)] = [
            ("from someone else", { $0.challenger = OGSUser(username: "CedarWave", id: 851_001, rank: 25) }),
            ("with no challenger", { $0.challenger = nil }),
            ("made before the game", { $0.game.id = gameID - 1 }),
            ("for this game", { $0.game.id = gameID }),
            ("on another width", { $0.game.width = 13 }),
            ("on another height", { $0.game.height = 13 }),
            ("under other rules", { $0.game.rules = .japanese }),
            ("ranked", { $0.game.ranked = true }),
            ("with other clock values", {
                $0.game.timeControl = TimeControlSystem.Fischer(initialTime: 600, timeIncrement: 30,
                                                                maxTime: 600).timeControlObject
            }),
            ("on another clock", {
                $0.game.timeControl = TimeControlSystem.ByoYomi(mainTime: 1_800, periods: 5,
                                                                periodTime: 30).timeControlObject
            }),
        ]
        for (change, apply) in changes {
            var offered = try challenge(95_004, after: game)
            apply(&offered)
            XCTAssertNil(GameOverCardRule.challengeID(for: game, among: [offered]), "A challenge \(change)")
        }
    }

    func testOnlyTheUsersOwnFinishedGameOutsideRengoHasACard() throws {
        let game = try ownGame()
        let offered = [try challenge(95_004, after: game)]
        XCTAssertEqual(GameOverCardRule.challengeID(for: game, among: offered), 95_004)

        game.gameData?.rengo = true
        XCTAssertNil(GameOverCardRule.challengeID(for: game, among: offered), "Rengo")
        game.gameData?.rengo = false

        let player = game.ogs
        game.ogs = makeService(user: OGSUser(username: "Watcher", id: 999_999_001, rank: 25))
        XCTAssertNil(GameOverCardRule.challengeID(for: game, among: offered), "A game the user watched")
        game.ogs = player

        let playing = try ownGame(over: false)
        XCTAssertNil(GameOverCardRule.challengeID(for: playing, among: [try challenge(95_004, after: playing)]),
                     "A game still in play")
    }

    func testTheHighestChallengeIDWins() throws {
        let game = try ownGame()
        let first = try challenge(95_004, gameID: 26_268_500, after: game)
        let second = try challenge(95_010, gameID: 26_268_480, after: game)
        var stranger = try challenge(95_020, after: game)
        stranger.challenger = OGSUser(username: "CedarWave", id: 851_001, rank: 25)
        XCTAssertEqual(GameOverCardRule.challengeID(for: game, among: [second, stranger, first]), 95_010,
                       "The highest id among those that qualify.")
    }

    func testAnUnusualCardStillLeadsAndOffersView() throws {
        let game = try ownGame()
        var copied = try challenge(95_004, after: game)
        copied.game.handicap = try XCTUnwrap(game.gameData?.handicap)   // as the game's Rematch copies it
        XCTAssertTrue(copied.isUnusual)
        XCTAssertEqual(GameOverCardRule.challengeID(for: game, among: [copied]), 95_004,
                       "The rule decides what leads, never the action.")

        func inline(_ challenge: OGSDirectChallenge) -> Bool {
            ActivityRowActionState(isUnusual: challenge.isUnusual, isInGamePopover: true, isGameOverCard: true,
                                   isOffline: false, state: nil).showsInlineAcceptAndReject
        }
        XCTAssertFalse(inline(copied), "An unusual card offers View.")
        XCTAssertTrue(inline(try challenge(95_005, after: game)), "A usual one offers Reject and Accept.")
    }
}
