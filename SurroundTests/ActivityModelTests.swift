//
//  ActivityModelTests.swift
//  SurroundTests
//
//  The Activity rules from the in-app notices design: what leads the bar,
//  what +N counts, the list's order, low time, the Now section, the in-game
//  control, a conversation's control, and one window's input with what OGS
//  confirmed gone left out.
//

import Combine
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

    // MARK: The in-game control's context

    private typealias Context = Model.GameControlContext

    func testTheOneArgumentFormIsHomesRouteOutsideZen() {
        XCTAssertEqual(Context.home, Context(allowsPicker: true, isZen: false, cardChallengeID: nil))
        let places: [Model.Place] = [
            .game(id: 3, isOwnGame: true, isLive: true, isOver: false),
            .game(id: 90, isOwnGame: true, isLive: false, isOver: false),
            .game(id: 3, isOwnGame: true, isLive: true, isOver: true),
            .game(id: 500, isOwnGame: false, isLive: true, isOver: false),
        ]
        for liveGames in [[yourMove(3)], [yourMove(1), yourMove(3)]] {
            for place in places {
                var input = Model.Input()
                input.liveGames = liveGames
                input.challengesReceived = [Model.Challenge(id: 9, isLive: false)]
                input.place = place
                XCTAssertEqual(Model.gameControl(input), Model.gameControl(input, context: .home), "\(place)")
            }
        }
    }

    func testWithoutThePickerYourGameShowsTheInbox() {
        let noPicker = Context(allowsPicker: false)
        var input = Model.Input()
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .base(plusN: 0))
        XCTAssertNil(Model.gameControl(input, context: noPicker), "The inbox hides at 0.")

        input.challengesReceived = [Model.Challenge(id: 9, isLive: false)]
        input.conversations = [unread(30)]
        XCTAssertEqual(Model.gameControl(input, context: noPicker), .inbox(count: 2))
        input.place = .game(id: 90, isOwnGame: true, isLive: true, isOver: true)
        XCTAssertEqual(Model.gameControl(input, context: noPicker), .inbox(count: 2), "Your finished game too.")

        input.place = .game(id: 90, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input, context: noPicker), .dot, "While you play live, what waits is a dot.")
        input.challengesReceived = []
        input.conversations = []
        XCTAssertNil(Model.gameControl(input, context: noPicker), "No base form without the picker.")
    }

    func testTheChipOutranksTheInboxAndTheCard() {
        var input = Model.Input()
        input.liveGames = [yourMove(1)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input, context: Context(allowsPicker: false)),
                       .chip(yourMove(1), plusN: 1, hasDot: false), "The most urgent thing shows on any route.")

        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: true)
        XCTAssertEqual(Model.gameControl(input, context: Context(cardChallengeID: 9)),
                       .chip(yourMove(1), plusN: 1, hasDot: false), "The card's challenge counts in +N meanwhile.")
    }

    func testZenShowsOnlyAnotherLiveGameOnYourMove() {
        let zen = Context(isZen: true)
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 200), yourMove(2, left: 100), theirMove(7), yourMove(3)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        input.conversations = [unread(30)]
        input.startedGames = [7: 1_000]
        input.now = 1_005
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input, context: zen), .chip(yourMove(2, left: 100), plusN: 0, hasDot: false),
                       "Least time first, with no +N and no dot, ahead of the game that started.")

        input.liveGames = [theirMove(7), yourMove(3)]
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 0, hasDot: true))
        XCTAssertNil(Model.gameControl(input, context: zen), "No started game, dot, base or inbox in Zen.")

        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: true)
        input.liveGames = [yourMove(1)]
        XCTAssertEqual(Model.gameControl(input, context: Context(isZen: true, cardChallengeID: 9)),
                       .chip(yourMove(1), plusN: 0, hasDot: false))
        input.liveGames = []
        XCTAssertNil(Model.gameControl(input, context: Context(isZen: true, cardChallengeID: 9)), "Zen hides the card.")
    }

    func testAStartedGameOutsideLivePlayCountsEverythingThatWaits() {
        var input = Model.Input()
        input.liveGames = [theirMove(7)]
        input.startedGames = [7: 1_000]
        input.now = 1_010
        input.challengesReceived = [Model.Challenge(id: 9, isLive: false)]
        input.conversations = [unread(30)]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 2, hasDot: false))
        input.place = .game(id: 500, isOwnGame: false, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 2, hasDot: false),
                       "In a game you watch too.")
    }

    func testPlusNBeyondAStartedGameCountsYourOtherLiveGamesOnYourMove() {
        var input = Model.Input()
        input.liveGames = [theirMove(7), yourMove(1), yourMove(2)]
        input.startedGames = [7: 1_000]
        input.now = 1_010
        input.conversations = [unread(30)]
        input.place = .game(id: 90, isOwnGame: true, isLive: false, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 3, hasDot: false),
                       "Both games on your move and the conversation.")

        input.place = .game(id: 2, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .gameStarted(theirMove(7), plusN: 1, hasDot: true),
                       "While you play live, the other game on your move still counts; the conversation is a dot.")
    }

    func testTheChipShowsInGamesYouOnlyWatch() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2, left: 100)]
        input.conversations = [unread(30)]
        input.place = .game(id: 500, isOwnGame: false, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input), .chip(yourMove(2, left: 100), plusN: 2, hasDot: false),
                       "Watching isn't playing: the other game and the conversation count.")
        XCTAssertEqual(Model.gameControl(input, context: Context(allowsPicker: false)),
                       .chip(yourMove(2, left: 100), plusN: 2, hasDot: false), "On a route without the picker too.")
    }

    func testYourFinishedGameLeadsWithTheCardWhileItsChallengeWaits() {
        let card = Context(cardChallengeID: 9)
        var input = Model.Input()
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        input.conversations = [unread(30)]
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: true)
        XCTAssertEqual(Model.gameControl(input, context: card), .gameOverCard(challengeID: 9, plusN: 2),
                       "+N counts the other challenge and the conversation.")
        XCTAssertEqual(Model.gameControl(input, context: Context(allowsPicker: false, cardChallengeID: 9)),
                       .gameOverCard(challengeID: 9, plusN: 2), "The card needs no picker.")
        XCTAssertEqual(Model.gameControl(input), .base(plusN: 3), "Without a card, game over releases what waited.")

        input.challengesReceived.removeFirst()
        XCTAssertEqual(Model.gameControl(input, context: card), .base(plusN: 2), "Its challenge has gone.")

        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        input.place = .game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.gameControl(input, context: card), .dot, "Only a finished game has the card.")
        input.place = .game(id: 3, isOwnGame: false, isLive: true, isOver: true)
        XCTAssertEqual(Model.gameControl(input, context: card), .inbox(count: 2), "Nor does a game you watched.")
    }

    // MARK: What +N counted

    func testWhatAddsToPlusN() {
        XCTAssertTrue(Model.counts(.liveGame(yourMove(1)), onMessagesTab: false))
        XCTAssertFalse(Model.counts(.liveGame(theirMove(2)), onMessagesTab: false))
        XCTAssertTrue(Model.counts(.challenge(Model.Challenge(id: 7, isLive: false)), onMessagesTab: true),
                      "Every challenge counts, a correspondence one too.")
        XCTAssertTrue(Model.counts(.conversation(unread(30)), onMessagesTab: false))
        XCTAssertFalse(Model.counts(.conversation(unread(30)), onMessagesTab: true))
        XCTAssertFalse(Model.counts(.conversation(read(31, at: 50)), onMessagesTab: false))
        XCTAssertFalse(Model.counts(.waiting(waiting("search")), onMessagesTab: false))
        XCTAssertFalse(Model.counts(.correspondenceGames(count: 2, mostUrgentID: 90), onMessagesTab: false))
    }

    func testCountedNamesWhatPlusNCountsBesideALead() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2, left: 100), theirMove(3)]
        input.challengesReceived = [Model.Challenge(id: 7, isLive: false)]
        input.conversations = [unread(30), read(31, at: 50)]
        input.waiting = [waiting("search")]
        input.correspondenceGamesOnYourMove = [Model.CorrespondenceGame(id: 90, timeUntilTimeout: 3_600)]
        let snapshot = Model.snapshot(input)
        XCTAssertEqual(snapshot.lead, .item(.liveGame(yourMove(2, left: 100))))
        XCTAssertEqual(snapshot.counted.map(\.id), ["game-1", "challenge-7", "conversation-30"],
                       "The lead never counts itself, and neither do their move, your search, a read conversation "
                           + "or a correspondence game.")
        XCTAssertEqual(snapshot.counted.count, snapshot.plusN)

        input.startedGames = [3: 1_000]
        input.now = 1_010
        XCTAssertEqual(Model.snapshot(input).lead, .gameStarted(theirMove(3)))
        XCTAssertEqual(Model.snapshot(input).counted.map(\.id), ["game-2", "game-1", "challenge-7", "conversation-30"],
                       "A started game on their move counts nothing.")
    }

    func testCountedIsWhatNWaitingCounts() {
        var input = Model.Input()
        input.challengesReceived = [Model.Challenge(id: 7, isLive: false)]
        input.conversations = [unread(30), unread(31)]
        input.waiting = [waiting("correspondence search", live: false)]
        let snapshot = Model.snapshot(input)
        XCTAssertEqual(snapshot.lead, .waiting(count: 3))
        XCTAssertEqual(snapshot.counted.map(\.id), ["challenge-7", "conversation-30", "conversation-31"])
        XCTAssertEqual(snapshot.plusN, 0, "N waiting counts them itself.")
    }

    func testTheMessagesTabLeavesConversationsOutOfCounted() {
        var input = Model.Input()
        input.liveGames = [yourMove(1)]
        input.conversations = [unread(30)]
        input.place = .root(isMessagesTab: true)
        XCTAssertEqual(Model.snapshot(input).counted, [])
        input.place = .root(isMessagesTab: false)
        XCTAssertEqual(Model.snapshot(input).counted.map(\.id), ["conversation-30"])
        input.isMessagesTabSelected = true
        XCTAssertEqual(Model.snapshot(input).counted, [], "The window's selected tab says it too.")
    }

    func testNothingIsCountedWithoutALeadOrAwayFromARoot() {
        XCTAssertEqual(Model.snapshot(Model.Input()).counted, [])
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2)]
        input.conversations = [unread(30)]
        for place: Model.Place in [.conversation, .game(id: 1, isOwnGame: true, isLive: true, isOver: false)] {
            input.place = place
            XCTAssertEqual(Model.snapshot(input).counted, [], "\(place)")
        }
    }

    // MARK: The Now section

    func testTheNowSectionListsTwoRowsInTheLeadOrder() {
        var input = Model.Input()
        input.liveGames = [theirMove(3), yourMove(1, left: 200), yourMove(2, left: 100)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        input.waiting = [waiting("search")]
        input.conversations = [unread(30)]
        let section = Model.nowSection(input, rows: Model.nowSectionRows)
        XCTAssertEqual(Model.nowSectionRows, 2)
        XCTAssertEqual(section.rows, [.item(.liveGame(yourMove(2, left: 100))), .item(.liveGame(yourMove(1, left: 200)))])
        XCTAssertEqual(section.rows.first, Model.snapshot(input).lead, "The first row is the bar's lead.")
        XCTAssertEqual(section.counted.map(\.id), ["challenge-8", "challenge-9", "conversation-30"])
        XCTAssertEqual(section.plusN, 3, "All activity counts what the rows don't show.")
    }

    func testTheNowSectionFollowsTheLeadOrderAcrossKinds() {
        var input = Model.Input()
        input.liveGames = [theirMove(3), yourMove(1), theirMove(7)]
        input.startedGames = [7: 1_000]
        input.now = 1_010
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        input.waiting = [waiting("correspondence search", live: false), waiting("live search", since: 5)]
        XCTAssertEqual(Model.nowSection(input, rows: 10).rows, [
            .gameStarted(theirMove(7)), .item(.liveGame(yourMove(1))),
            .item(.challenge(Model.Challenge(id: 9, isLive: true))), .item(.liveGame(theirMove(3))),
            .item(.waiting(waiting("live search", since: 5))),
        ], "A started game, your move, a live challenge, their move, then your live searches, each once. "
            + "Correspondence never leads.")
    }

    func testTheNowSectionLeavesTheGameOnScreenOut() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 100), yourMove(2, left: 200)]
        input.conversations = [unread(30)]
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        let section = Model.nowSection(input, rows: 2)
        XCTAssertEqual(section.rows, [.item(.liveGame(yourMove(2, left: 200)))])
        XCTAssertEqual(section.counted.map(\.id), ["conversation-30"])
        XCTAssertNil(Model.snapshot(input).lead, "The bar has no lead over a game, but the Now section answers.")
    }

    func testTheGameOnScreenCountsForLowTimeButNeverAsOneThatStarted() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 10), theirMove(7)]
        input.startedGames = [7: 1_000]
        input.now = 1_005
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.nowSection(input, rows: 2).rows, [.item(.liveGame(theirMove(7)))],
                       "Low time in the game on screen keeps the started game from leading, as in the game's control.")
        input.liveGames = [yourMove(1), theirMove(7)]
        input.place = .game(id: 7, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(Model.nowSection(input, rows: 2).rows, [.item(.liveGame(yourMove(1)))])
    }

    func testTheNowSectionAnswersInAConversationWithTheMessagesTabFromTheSelectedTab() {
        var input = Model.Input()
        input.liveGames = [yourMove(1)]
        input.conversations = [unread(30), unread(31)]
        input.place = .conversation
        let section = Model.nowSection(input, rows: 2)
        XCTAssertEqual(section.rows, [.item(.liveGame(yourMove(1)))])
        XCTAssertEqual(section.plusN, 2)
        input.isMessagesTabSelected = true
        XCTAssertEqual(Model.nowSection(input, rows: 2).plusN, 0,
                       "A conversation in Messages' pane reads as a conversation; the selected tab leaves them out.")
    }

    func testTheNowSectionShowsNWaitingWhenNothingThatCanLeadWaits() {
        var input = Model.Input()
        input.challengesReceived = [Model.Challenge(id: 7, isLive: false)]
        input.conversations = [unread(30), unread(31)]
        let section = Model.nowSection(input, rows: 2)
        XCTAssertEqual(section.rows, [.waiting(count: 3)])
        XCTAssertEqual(section.rows.first, Model.snapshot(input).lead)
        XCTAssertEqual(section.plusN, 0, "The row stands for what it counts.")
        XCTAssertEqual(section.counted.map(\.id), ["challenge-7", "conversation-30", "conversation-31"])
        XCTAssertEqual(Model.nowSection(input, rows: 0),
                       Model.NowSection(rows: [], plusN: 3, counted: section.counted), "No room for the row.")
    }

    func testTheNowSectionIsEmptyWhenNothingWaits() {
        XCTAssertEqual(Model.nowSection(Model.Input(), rows: 2), Model.NowSection(rows: [], plusN: 0, counted: []))
        var input = Model.Input()
        input.waiting = [waiting("correspondence search", live: false)]
        input.correspondenceGamesOnYourMove = [Model.CorrespondenceGame(id: 90, timeUntilTimeout: 3_600)]
        XCTAssertEqual(Model.nowSection(input, rows: 2), Model.NowSection(rows: [], plusN: 0, counted: []),
                       "What neither leads nor counts stays in Activity.")
    }

    func testOneRowLeavesTheNextItemToAllActivity() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 100), yourMove(2, left: 200)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        let two = Model.nowSection(input, rows: 2)
        let one = Model.nowSection(input, rows: 1)
        XCTAssertEqual(one.rows, [.item(.liveGame(yourMove(1, left: 100)))])
        XCTAssertEqual(one.plusN, two.plusN + 1, "All activity's +N takes the item the status row displaced.")
        XCTAssertEqual(Model.nowSection(input, rows: 0).plusN, 3)
    }

    // MARK: A conversation's control

    func testAConversationShowsYourLiveGameWithTheLeastTime() {
        var input = Model.Input()
        input.liveGames = [yourMove(1, left: 200), yourMove(2, left: 100), theirMove(3)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        input.conversations = [unread(30)]
        input.place = .conversation
        XCTAssertEqual(Model.conversationControl(input), .chip(yourMove(2, left: 100), plusN: 0, hasDot: false),
                       "Least time first, never +N or a dot.")
    }

    func testAConversationShowsAGameThatStartedElsewhereFirst() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), theirMove(7)]
        input.startedGames = [7: 1_000]
        input.now = 1_010
        input.place = .conversation
        XCTAssertEqual(Model.conversationControl(input), .gameStarted(theirMove(7), plusN: 0, hasDot: false))
        input.now = 1_030
        XCTAssertEqual(Model.conversationControl(input), .chip(yourMove(1), plusN: 0, hasDot: false),
                       "Its 30 s are over.")
        input.now = 1_010
        input.liveGames = [yourMove(1, left: 10), theirMove(7)]
        XCTAssertEqual(Model.conversationControl(input), .chip(yourMove(1, left: 10), plusN: 0, hasDot: false),
                       "A game on your move low on time keeps the started game out.")
    }

    func testAConversationShowsNothingWithoutAGameOnYourMove() {
        var input = Model.Input()
        input.liveGames = [theirMove(3)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true)]
        input.conversations = [unread(30)]
        input.waiting = [waiting("search")]
        input.place = .conversation
        XCTAssertNil(Model.conversationControl(input), "Nothing but a game that needs you shows.")
        input.liveGames = [yourMove(1)]
        for place: Model.Place in [.root(isMessagesTab: true), .game(id: 5, isOwnGame: true, isLive: true, isOver: false)] {
            input.place = place
            XCTAssertNil(Model.conversationControl(input), "Only a conversation has this control: \(place)")
        }
    }

    // MARK: Leaving out what OGS confirmed gone

    func testAHiddenItemNeverLeadsCountsOrShows() {
        var input = Model.Input()
        input.liveGames = [theirMove(3)]
        input.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        input.waiting = [waiting("open-4", kind: .openChallenge)]
        input.conversations = [unread(30)]
        XCTAssertEqual(Model.snapshot(input).lead, .item(.challenge(Model.Challenge(id: 9, isLive: true))))

        let hidden = input.hiding(["challenge-9", "challenge-8", "waiting-open-4", "challenge-404"])
        XCTAssertEqual(hidden.hiddenListedIDs, ["challenge-9", "challenge-8", "waiting-open-4"],
                       "Only what the service still lists is left out.")
        let snapshot = Model.snapshot(hidden)
        XCTAssertEqual(snapshot.lead, .item(.liveGame(theirMove(3))))
        XCTAssertEqual(snapshot.counted.map(\.id), ["conversation-30"])
        XCTAssertEqual(snapshot.list.map(\.id), ["game-3", "conversation-30"])
        XCTAssertEqual(Model.nowSection(hidden, rows: 2).rows, [.item(.liveGame(theirMove(3)))])
        XCTAssertEqual(input.hiding([]), input)
    }

    /// Answers every request at once, as OGS's 2xx does.
    private func confirmingClient() -> ActivityResults.Client {
        ActivityResults.Client(
            accept: { _ in Just(1).setFailureType(to: Error.self).eraseToAnyPublisher() },
            withdrawOrDecline: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
            cancelAutomatch: { _ in true },
            leaveRengo: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
            startRengo: { _ in Just(1).setFailureType(to: Error.self).eraseToAnyPublisher() },
            hasActiveGame: { _ in false },
            automatchLifecycleEvents: Empty().eraseToAnyPublisher()
        )
    }

    private final class SilentNavigator: ActivityNavigating {
        func openGame(_ gameID: Int, closesNewGame: Bool) {}
        func announce(_ announcement: AppAnnouncement) {}
    }

    /// Holds every block, so nothing the store schedules runs.
    private final class HeldScheduler: OGSWebsocketScheduling {
        func async(_ block: @escaping () -> Void) {}
        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable { AnyCancellable {} }
        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            AnyCancellable {}
        }
    }

    private let navigator = SilentNavigator()

    /// A window whose results store hides the challenges `rejected`, as after
    /// OGS confirmed their reject.
    private func navigation(rejecting rejected: [Int] = []) -> NavigationService {
        let nav = NavigationService()
        nav.activityResults.attach(client: confirmingClient(), navigator: navigator, scheduler: HeldScheduler())
        for id in rejected {
            var challenge = OGSChallengeSampleData.sampleChallenge
            challenge.id = id
            nav.activityResults.reject(challenge: challenge, session: UUID(), itemID: "challenge-\(id)",
                                       display: ActivityRowDisplay(title: "Challenger", detail: "9×9"),
                                       section: .challengesReceived, after: nil)
        }
        return nav
    }

    /// The services a test made, kept until it ends, since a window's stores
    /// hold theirs weakly.
    private var services = [OGSService]()

    /// A signed-in service on a socket that never opens.
    private func signedInService(_ build: (inout OGSService.BootstrapState) -> Void = { _ in }) -> OGSService {
        var state = OGSService.BootstrapState()
        state.user = OGSUser(username: "current", id: 1, rank: 25)
        state.isLoggedIn = true
        build(&state)
        let suite = "com.honganhkhoa.Surround.ActivityModelTests.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state
        )
        services.append(service)
        return service
    }

    private func received(_ id: Int) -> OGSDirectChallenge {
        var challenge = OGSChallengeSampleData.sampleChallenge
        challenge.id = id
        return challenge
    }

    func testTheWindowsInputReadsEachOfTheWindowsStores() {
        ActivitySession.reset()
        defer { ActivitySession.reset() }
        let nav = navigation()

        // The window's live games that started elsewhere.
        let account = CurrentValueSubject<Int?, Never>(1)
        let loading = CurrentValueSubject<Bool, Never>(false)
        let applied = CurrentValueSubject<Int, Never>(1)
        let live = CurrentValueSubject<Set<Int>, Never>([1])
        let opened = CurrentValueSubject<Set<Int>, Never>([])
        nav.startedGamesRecorder.attach(StartedGamesRecorder.Feed(
            accountID: account.eraseToAnyPublisher(), isLoadingOverview: loading.eraseToAnyPublisher(),
            appliedOverviews: applied.eraseToAnyPublisher(), liveGameIDs: live.eraseToAnyPublisher(),
            openedGameIDs: opened.eraseToAnyPublisher()
        ), now: { 1_000 })
        live.send([1, 7])

        // The app's first sightings of items without a creation time.
        ActivitySession.record([Model.WaitingID.sentChallenge(5)], at: 900)

        // The window's last-known open challenges, from while its socket was up.
        var open = OGSChallengeSampleData.sampleOpenChallenge
        open.id = 4
        nav.activityLastKnown.attach(ogs: signedInService { $0.openChallengeSentById = [4: open] })

        nav.main.rootView = .privateMessages
        let ogs = signedInService { $0.challengesSent = [self.received(5)] }
        let input = Model.Input.window(ogs: ogs, nav: nav, place: .root(isMessagesTab: true), now: 1_010, fixture: nil)
        XCTAssertEqual(input.startedGames, [7: 1_000])
        XCTAssertEqual(input.waiting.first { $0.id == "sent-5" }?.since, 900)
        XCTAssertNotNil(input.waiting.first { $0.id == "open-4" },
                        "While the socket is down the last-known copy stands in for the service's own rows.")
        XCTAssertTrue(input.isMessagesTabSelected)
        XCTAssertEqual(input.now, 1_010)
        XCTAssertEqual(input.sessionStart, 0, "Every read conversation counts as a recent one.")
        XCTAssertEqual(input.hiddenListedIDs, [])
    }

    func testTheWindowsInputLeavesOutWhatOGSConfirmedGone() {
        let ogs = signedInService { $0.challengesReceived = [self.received(9), self.received(8)] }
        XCTAssertEqual(Model.Input.window(ogs: ogs, nav: navigation(), place: .root(isMessagesTab: false), now: 0,
                                          fixture: nil).challengesReceived.map(\.id), [9, 8])

        let nav = navigation(rejecting: [9])
        XCTAssertEqual(nav.activityResults.hiddenIDs, ["challenge-9"])
        let input = Model.Input.window(ogs: ogs, nav: nav, place: .root(isMessagesTab: false), now: 0, fixture: nil)
        XCTAssertEqual(input.challengesReceived.map(\.id), [8])
        XCTAssertEqual(input.hiddenListedIDs, ["challenge-9"])
        XCTAssertEqual(Model.snapshot(input).counted.map(\.id), ["challenge-8"], "A hidden challenge never counts.")

        let updated = signedInService { $0.challengesReceived = [self.received(8)] }
        XCTAssertEqual(Model.Input.window(ogs: updated, nav: nav, place: .root(isMessagesTab: false), now: 0,
                                          fixture: nil).hiddenListedIDs, [],
                       "Once the service drops it, nothing is left out, and the store can forget it.")
    }

    func testADebugStatesInputStandsInForTheServicesLessWhatOGSConfirmedGone() {
        let nav = navigation(rejecting: [9])
        nav.main.rootView = .privateMessages
        var fixture = Model.Input()
        fixture.liveGames = [yourMove(1)]
        fixture.challengesReceived = [Model.Challenge(id: 9, isLive: true), Model.Challenge(id: 8, isLive: false)]
        fixture.now = 42
        let ogs = signedInService { $0.challengesReceived = [self.received(7)] }
        var expected = fixture
        expected.challengesReceived = [Model.Challenge(id: 8, isLive: false)]
        expected.isMessagesTabSelected = true
        expected.hiddenListedIDs = ["challenge-9"]
        XCTAssertEqual(Model.Input.window(ogs: ogs, nav: nav, place: .conversation, now: 1_000, fixture: fixture),
                       expected, "The state's input passes through on its own clock.")
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
