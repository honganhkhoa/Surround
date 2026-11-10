//
//  ActivityModelTests.swift
//  SurroundTests
//
//  The Activity rules from the in-app notices design: what leads the bar,
//  what +N counts, the list's order, low time and the in-game control.
//

import XCTest

final class ActivityModelTests: XCTestCase {
    private typealias Model = ActivityModel

    private var preferenceSuites = [String]()

    override func tearDown() {
        preferenceSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        preferenceSuites.removeAll()
        super.tearDown()
    }

    // MARK: Builders

    private func yourMove(_ id: Int, left: TimeInterval? = 300, running: Bool = true) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: true, isClockRunning: running, timeUntilTimeout: left)
    }

    private func theirMove(_ id: Int) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: false)
    }

    private func unread(_ peer: Int, at time: TimeInterval = 100) -> Model.Conversation {
        Model.Conversation(peerID: peer, isUnread: true, lastMessageTime: time)
    }

    private func read(_ peer: Int, at time: TimeInterval) -> Model.Conversation {
        Model.Conversation(peerID: peer, isUnread: false, lastMessageTime: time)
    }

    private func waiting(
        _ id: String,
        kind: Model.Waiting.Kind = .quickMatch,
        live: Bool = true,
        since: TimeInterval = 0
    ) -> Model.Waiting {
        Model.Waiting(id: id, kind: kind, isLive: live, since: since)
    }

    // MARK: The bar on root screens

    func testNothingWaitingMeansNoBar() {
        let snapshot = Model.snapshot(Model.Input())
        XCTAssertNil(snapshot.lead)
        XCTAssertEqual(snapshot.plusN, 0)
        XCTAssertTrue(snapshot.list.isEmpty)
    }

    func testAGameOnYourMoveLeadsAndPlusNCountsWhatElseWaitsForYou() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), theirMove(2)]
        input.challengesReceived = [Model.Challenge(id: 7, isLive: false)]
        input.conversations = [unread(30), unread(31)]
        input.waiting = [waiting("search")]
        let snapshot = Model.snapshot(input)
        XCTAssertEqual(snapshot.lead, .item(.liveGame(yourMove(1))))
        XCTAssertEqual(
            snapshot.plusN,
            3,
            "The challenge and the two conversations. A game on their move and your own search don't count."
        )
    }

    func testWhenNothingLiveLeadsTheBarShowsTheCount() {
        var input = Model.Input()
        input.challengesReceived = [Model.Challenge(id: 7, isLive: false)]
        input.conversations = [unread(30), unread(31)]
        input.waiting = [waiting("correspondence search", live: false)]
        input.correspondenceGamesOnYourMove = [Model.CorrespondenceGame(id: 90, timeUntilTimeout: 3_600)]
        let snapshot = Model.snapshot(input)
        XCTAssertEqual(snapshot.lead, .waiting(count: 3))
        XCTAssertEqual(snapshot.plusN, 0)
    }

    func testItemsThatNeitherLeadNorCountShowNoBar() {
        var input = Model.Input()
        input.waiting = [waiting("correspondence search", live: false)]
        input.correspondenceGamesOnYourMove = [Model.CorrespondenceGame(id: 90, timeUntilTimeout: 3_600)]
        XCTAssertNil(Model.snapshot(input).lead)
        XCTAssertEqual(Model.snapshot(input).list.count, 2, "Activity still lists them.")
    }

    func testTheMessagesTabDoesNotCountUnreadConversations() {
        var input = Model.Input()
        input.conversations = [unread(30)]
        input.place = .root(isMessagesTab: true)
        XCTAssertNil(Model.snapshot(input).lead)
        input.place = .root(isMessagesTab: false)
        XCTAssertEqual(Model.snapshot(input).lead, .waiting(count: 1))
    }

    func testWhatLeadsTheBar() {
        var input = Model.Input()
        input.waiting = [waiting("correspondence", live: false, since: -1), waiting("live")]
        XCTAssertEqual(Model.snapshot(input).lead, .item(.waiting(waiting("live"))))

        input.liveGames = [theirMove(2)]
        XCTAssertEqual(Model.snapshot(input).lead, .item(.liveGame(theirMove(2))))

        input.challengesReceived = [Model.Challenge(id: 8, isLive: false), Model.Challenge(id: 9, isLive: true)]
        XCTAssertEqual(
            Model.snapshot(input).lead,
            .item(.challenge(Model.Challenge(id: 9, isLive: true))),
            "A correspondence challenge never leads."
        )

        input.liveGames.append(yourMove(1))
        XCTAssertEqual(Model.snapshot(input).lead, .item(.liveGame(yourMove(1))))
    }

    func testGamesOnYourMoveGoByLeastTimeThenGamesWithNoRunningClock() {
        let games = [
            yourMove(4, left: nil, running: false),
            theirMove(1),
            yourMove(3, left: 120),
            yourMove(2, left: 40),
            yourMove(6, left: 10, running: false),
            yourMove(5, left: 40),
        ]
        XCTAssertEqual(Model.sortedLiveGames(games).map(\.id), [2, 5, 3, 4, 6, 1])
    }

    func testLowTime() {
        XCTAssertTrue(Model.isLowOnTime(yourMove(1, left: 29)))
        XCTAssertFalse(Model.isLowOnTime(yourMove(1, left: 30)))
        XCTAssertFalse(Model.isLowOnTime(yourMove(1, left: 10, running: false)), "Only a running clock is low.")

        var byoyomi = yourMove(1, left: 20)
        byoyomi.usesByoyomi = true
        XCTAssertFalse(Model.isLowOnTime(byoyomi), "Byo-yomi is low only in its last period.")
        byoyomi.isInLastByoyomiPeriod = true
        byoyomi.timeUntilTimeout = 25
        XCTAssertTrue(Model.isLowOnTime(byoyomi))

        var theirs = theirMove(2)
        theirs.isClockRunning = true
        theirs.timeUntilTimeout = 5
        XCTAssertFalse(Model.isLowOnTime(theirs))

        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 10), yourMove(2, left: 300)]
        XCTAssertEqual(Model.snapshot(input).lowTimeGameIDs, [1])
    }

    func testAGameThatStartedElsewhereLeadsForThirtySeconds() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), theirMove(2)]
        input.startedGames = [2: 1_000]
        input.now = 1_010
        XCTAssertEqual(Model.snapshot(input).lead, .gameStarted(theirMove(2)))
        XCTAssertEqual(Model.snapshot(input).plusN, 1, "The game on your move still counts.")

        input.now = 1_030
        XCTAssertEqual(Model.snapshot(input).lead, .item(.liveGame(yourMove(1))))
    }

    func testLowTimeKeepsAGameThatStartedElsewhereFromLeading() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 10), theirMove(2)]
        input.startedGames = [2: 1_000]
        input.now = 1_005
        XCTAssertEqual(Model.snapshot(input).lead, .item(.liveGame(yourMove(1, left: 10))))
    }

    // MARK: Activity's list

    func testTheListOrder() {
        var input = Model.Input()
        input.liveGames = [theirMove(2), yourMove(1)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        input.waiting = [
            waiting("rengo-1", kind: .rengo),
            waiting("sent-5", kind: .sentChallenge, since: 5),
            waiting("quick", since: 10),
            waiting("open-4", kind: .openChallenge, since: 4),
        ]
        input.correspondenceGamesOnYourMove = [
            Model.CorrespondenceGame(id: 91, timeUntilTimeout: 7_200),
            Model.CorrespondenceGame(id: 90, timeUntilTimeout: 3_600),
        ]
        input.conversations = [read(40, at: 50), unread(41, at: 10)]

        let list = Model.snapshot(input).list
        XCTAssertEqual(list.map(\.id), [
            "game-1", "game-2",
            "challenge-8", "challenge-9",
            "waiting-rengo-1", "waiting-open-4", "waiting-sent-5", "waiting-quick",
            "correspondence-games",
            "conversation-41", "conversation-40",
        ])
        XCTAssertTrue(list.contains(.correspondenceGames(count: 2, mostUrgentID: 90)))
    }

    func testTheGameOnScreenIsLeftOutOfTheList() {
        var input = Model.Input()
        input.liveGames = [yourMove(1)]
        input.correspondenceGamesOnYourMove = [
            Model.CorrespondenceGame(id: 90, timeUntilTimeout: 60),
            Model.CorrespondenceGame(id: 91, timeUntilTimeout: 7_200),
        ]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(
            Model.snapshot(input).list,
            [.liveGame(yourMove(1)), .correspondenceGames(count: 1, mostUrgentID: 91)]
        )
    }

    func testConversationsAreUnreadFirstThenAtMostThreeRecentOnes() {
        let conversations = [
            read(1, at: 10), read(2, at: 50), unread(3, at: 5), read(4, at: 40),
            read(5, at: 30), unread(6, at: 20), read(7, at: 0),
        ]
        XCTAssertEqual(Model.orderedConversations(conversations).map(\.peerID), [6, 3, 2, 4, 5])
        XCTAssertEqual(
            Model.orderedConversations(conversations, sessionStart: 35).map(\.peerID),
            [6, 3, 2, 4],
            "Read conversations from before this session drop out; unread ones never do."
        )
    }

    func testTheListCanEmptyWhenOnlyOldConversationsRemain() {
        var input = Model.Input()
        input.conversations = [read(1, at: 10)]
        input.sessionStart = 20
        XCTAssertTrue(Model.snapshot(input).list.isEmpty)
    }

    func testTheCorrespondenceRowOpensARunningClockFirst() {
        var input = Model.Input()
        input.correspondenceGamesOnYourMove = [
            Model.CorrespondenceGame(id: 1, isClockRunning: false, timeUntilTimeout: 7_200),
            Model.CorrespondenceGame(id: 2, timeUntilTimeout: 72_000),
        ]
        XCTAssertEqual(
            Model.snapshot(input).list,
            [.correspondenceGames(count: 2, mostUrgentID: 2)],
            "A paused game or a stone removal follows running clocks."
        )
    }

    func testTheBarNeverShowsOnGameDetailOrInAConversation() {
        var input = Model.Input()
        input.liveGames = [yourMove(1)]
        input.conversations = [unread(30)]
        for place: Model.Place in [.conversation, .game(id: 5, isOwnGame: true, isLive: false, isOver: false)] {
            input.place = place
            let snapshot = Model.snapshot(input)
            XCTAssertNil(snapshot.lead)
            XCTAssertEqual(snapshot.plusN, 0)
            XCTAssertEqual(snapshot.list.count, 2, "Activity still lists what waits.")
        }
    }

    // MARK: The in-game control

    func testAnotherLiveGameOnYourMoveShowsTheChip() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 200), yourMove(2, left: 100), yourMove(3, left: 50)]
        input.conversations = [unread(30)]
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(
            Model.gameControl(input),
            .chip(yourMove(2, left: 100), plusN: 1, hasDot: true),
            "While you play live only game 1 counts; the conversation is a dot."
        )
    }

    func testOutsideLivePlayTheChipCountsEverythingThatWaits() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2)]
        input.conversations = [unread(30)]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .chip(yourMove(1), plusN: 2, hasDot: false))
    }

    func testAGameThatStartedElsewhereShowsInTheInGameControl() {
        var input = Model.Input()
        input.liveGames = [theirMove(7), yourMove(3)]
        input.startedGames = [7: 1_000]
        input.now = 1_005
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 0, hasDot: false))

        input.liveGames = [theirMove(7), yourMove(3, left: 10)]
        XCTAssertEqual(
            Model.gameControl(input),
            .base(plusN: 0),
            "Low time in the game on screen keeps the started game out."
        )
    }

    func testPlayingLiveTurnsWhatWaitsIntoADot() {
        var input = Model.Input()
        input.liveGames = [yourMove(3)]
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .base(plusN: 0))

        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        XCTAssertEqual(Model.gameControl(input), .dot)

        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: true)
        XCTAssertEqual(Model.gameControl(input), .base(plusN: 1), "Game over releases what waited.")
    }

    func testYourOwnCorrespondenceGameShowsTheCount() {
        var input = Model.Input()
        input.challengesReceived = [Model.Challenge(id: 9, isLive: false)]
        input.conversations = [unread(30), unread(31)]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .base(plusN: 3))
    }

    func testAGameYouDoNotPlayShowsTheInboxCount() {
        var input = Model.Input()
        input.place = .game(id: 500, isOwnGame: false, isLive: true, isOver: false)
        XCTAssertNil(Model.gameControl(input), "Hidden at 0.")

        input.conversations = [unread(30)]
        XCTAssertEqual(Model.gameControl(input), .inbox(count: 1))

        input.place = .root(isMessagesTab: false)
        XCTAssertNil(Model.gameControl(input))
    }

    // MARK: Reading a game

    private func game(_ system: TimeControlSystem) throws -> Game {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-27053412", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.phase = .play
        data.outcome = nil
        data.winner = nil
        data.moves = []
        data.pauseControl = nil
        data.timeControl = system.timeControlObject
        data.clock.started = true
        data.clock.expiration = nil
        data.clock.timeUntilExpiration = nil
        data.clock.currentPlayerColor = .black
        data.clock.currentPlayerId = data.players.black.id
        data.clock.lastMoveTime = Date().timeIntervalSince1970 * 1_000
        data.clock.blackTime = ThinkingTime(thinkingTime: 272, thinkingTimeLeft: 272,
            periods: 3, periodsLeft: 3, periodTime: 30, periodTimeLeft: 30)
        data.clock.whiteTime = data.clock.blackTime
        let game = Game(ogsGame: data)
        game.clock = data.clock
        return game
    }

    private func makeService(user: OGSUser) -> OGSService {
        let suite = "com.honganhkhoa.Surround.ActivityModelTests.\(UUID().uuidString)"
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
        return service
    }

    func testTimeUntilTimeoutCountsByoyomiPeriodsAndTheCanadianBlock() throws {
        let byoyomi = try game(.ByoYomi(mainTime: 600, periods: 3, periodTime: 30))
        XCTAssertEqual(byoyomi.timeUntilTimeout(for: .black), 362, "272 s of main time and three 30 s periods.")
        byoyomi.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0, periods: 3, periodsLeft: 2,
            periodTime: 30, periodTimeLeft: 12)
        XCTAssertEqual(byoyomi.timeUntilTimeout(for: .black), 42)

        let canadian = try game(.Canadian(mainTime: 600, periodTime: 120, stonesPerPeriod: 10))
        canadian.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 50)
        XCTAssertEqual(canadian.timeUntilTimeout(for: .black), 170)
        canadian.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0, movesLeft: 7, blockTimeLeft: 102)
        XCTAssertEqual(canadian.timeUntilTimeout(for: .black), 102)

        let fischer = try game(.Fischer(initialTime: 300, timeIncrement: 10, maxTime: 600))
        fischer.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 25)
        XCTAssertEqual(fischer.timeUntilTimeout(for: .black), 25)

        XCTAssertNil(try game(.None).timeUntilTimeout(for: .black))
        fischer.clock?.started = false
        XCTAssertNil(fischer.timeUntilTimeout(for: .black), "Nothing before the clock starts.")
    }

    func testALiveGameIsReadFromTheUsersSide() throws {
        let game = try game(.Fischer(initialTime: 300, timeIncrement: 10, maxTime: 600))
        let blackID = try XCTUnwrap(game.gameData?.players.black.id)
        let service = makeService(user: OGSUser(username: "black", id: blackID, rank: 25))
        game.ogs = service
        game.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 25)

        let live = try XCTUnwrap(Model.LiveGame(game: game, userID: blackID))
        XCTAssertEqual(live.id, game.ogsID)
        XCTAssertTrue(live.isYourMove)
        XCTAssertTrue(live.isClockRunning)
        XCTAssertEqual(live.timeUntilTimeout, 25)
        XCTAssertFalse(live.usesByoyomi)
        XCTAssertTrue(Model.isLowOnTime(live))

        game.gamePhase = .finished
        XCTAssertNil(Model.LiveGame(game: game, userID: blackID))
    }

    func testGameDetailsPlaceFollowsTheGameAndTheAccount() throws {
        let game = try game(.Fischer(initialTime: 300, timeIncrement: 10, maxTime: 600))
        let blackID = try XCTUnwrap(game.gameData?.players.black.id)
        let service = makeService(user: OGSUser(username: "black", id: blackID, rank: 25))
        game.ogs = service
        let id = try XCTUnwrap(game.ogsID)

        let place = Model.Place(showing: game)
        XCTAssertEqual(place, .game(id: id, isOwnGame: true, isLive: true, isOver: false))
        XCTAssertTrue(place.hidesBar)

        service.user = OGSUser(username: "watcher", id: 999_999_001, rank: 25)
        XCTAssertEqual(Model.Place(showing: game), .game(id: id, isOwnGame: false, isLive: true, isOver: false),
                       "Whether the user plays it follows the signed-in account.")

        game.gamePhase = .finished
        XCTAssertEqual(Model.Place(showing: game), .game(id: id, isOwnGame: false, isLive: true, isOver: true))

        let correspondence = try self.game(.Fischer(initialTime: 259_200, timeIncrement: 86_400, maxTime: 604_800))
        correspondence.ogs = service
        XCTAssertEqual(Model.Place(showing: correspondence),
                       .game(id: id, isOwnGame: false, isLive: false, isOver: false))

        XCTAssertFalse(Model.Place.root(isMessagesTab: true).hidesBar)
    }

    func testAChallengeWithoutASpeedTagIsClassifiedFromItsClock() throws {
        func timeControl(_ json: String) throws -> TimeControl {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(TimeControl.self, from: Data(json.utf8))
        }
        let correspondence = try timeControl(
            #"{"system":"fischer","time_control":"fischer","initial_time":259200,"time_increment":86400,"max_time":604800}"#
        )
        XCTAssertNil(correspondence.speed)
        XCTAssertFalse(Model.isRealtime(correspondence, width: 19, height: 19))

        let live = try timeControl(
            #"{"system":"fischer","time_control":"fischer","initial_time":600,"time_increment":30,"max_time":1200}"#
        )
        XCTAssertTrue(Model.isRealtime(live, width: 19, height: 19))

        let unknown = try timeControl(#"{"system":"future-clock","time_control":"future-clock"}"#)
        XCTAssertFalse(Model.isRealtime(unknown, width: 19, height: 19), "An unknown clock never leads.")
    }

    func testTheInputLeavesEverythingOutWithoutAnAccount() {
        let service = makeService(user: OGSUser(username: "black", id: 1, rank: 25))
        service.user = nil
        XCTAssertEqual(
            Model.Input(ogs: service, place: .root(isMessagesTab: false), now: 5),
            Model.Input(now: 5)
        )
    }
}
