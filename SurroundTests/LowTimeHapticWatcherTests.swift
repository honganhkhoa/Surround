//
//  LowTimeHapticWatcherTests.swift
//  SurroundTests
//
//  The warning haptic for another live game's last 10 seconds. It plays
//  once per game, when the user's own clock falls through 10 s between two
//  reads on the timer while it runs on their move with the socket
//  connected. In byo-yomi only the last period counts: entering it with
//  10 s or less is a fall, and so is a turn that starts in it. It never
//  plays offline, under the moderator cover, for the game on screen, with
//  Settings › Haptics off or on the Mac.
//

import Combine
import XCTest

final class LowTimeHapticWatcherTests: XCTestCase {
    private typealias Model = ActivityModel
    private var suites = [String]()

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        super.tearDown()
    }

    /// Preferences of the test's own, removed after it.
    private func preferences() throws -> UserDefaults {
        let suite = "com.honganhkhoa.Surround.LowTimeHapticWatcherTests.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func yourMove(_ id: Int, left: TimeInterval?, running: Bool = true) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: true, isClockRunning: running, timeUntilTimeout: left)
    }

    /// What fell at each read of one game on the user's move, as one
    /// account with the socket connected.
    private func fallen(_ watcher: LowTimeHapticWatcher, reading timesLeft: [TimeInterval]) -> [[Int]] {
        timesLeft.map { watcher.record([yourMove(1, left: $0)], accountID: 5, isConnected: true) }
    }

    // MARK: What counts as a fall

    func testAFallThroughTenSecondsWhileTheClockRunsIsSeenOnce() {
        XCTAssertEqual(Model.lowTimeHapticThreshold, 10)
        let watcher = LowTimeHapticWatcher()
        XCTAssertEqual(fallen(watcher, reading: [12, 11, 10.5, 9.5, 8.5, 3, 0]), [[], [], [], [1], [], [], []])
        XCTAssertEqual(watcher.doneGameIDs, [1])
        XCTAssertEqual(fallen(LowTimeHapticWatcher(), reading: [11, 10]), [[], [1]], "Reaching 10 s is the fall.")
    }

    func testAWindowThatOpensWithTenSecondsOrLessNeverSeesAFall() {
        XCTAssertEqual(fallen(LowTimeHapticWatcher(), reading: [8, 7, 6, 3, 0]), [[], [], [], [], []])
        XCTAssertEqual(fallen(LowTimeHapticWatcher(), reading: [10, 9, 8]), [[], [], []])
    }

    func testOnlyTheUsersOwnRunningClockOnTheirMoveCounts() {
        let watcher = LowTimeHapticWatcher()
        func read(_ game: Model.LiveGame) -> [Int] { watcher.record([game], accountID: 5, isConnected: true) }
        XCTAssertEqual(read(yourMove(1, left: 12)), [])
        XCTAssertEqual(read(yourMove(1, left: 11, running: false)), [], "Paused, or in stone removal.")
        XCTAssertEqual(read(yourMove(1, left: 9)), [], "The fall happened while the clock didn't run.")

        let theirs = Model.LiveGame(id: 1, isYourMove: false, isClockRunning: true, timeUntilTimeout: 9)
        XCTAssertEqual(read(theirs), [])
        XCTAssertEqual(read(yourMove(1, left: 30)), [], "Back on your move after a period or an increment.")
        XCTAssertEqual(read(theirs), [], "Their clock running through 10 s is theirs.")
        XCTAssertEqual(read(yourMove(1, left: 12)), [])
        XCTAssertEqual(read(yourMove(1, left: nil)), [], "No known time to timeout.")
        XCTAssertEqual(read(yourMove(1, left: 9)), [])
        XCTAssertEqual(read(yourMove(1, left: 12)), [])
        XCTAssertEqual(read(yourMove(1, left: 9)), [1])
        XCTAssertEqual(read(yourMove(1, left: 30)), [])
        XCTAssertEqual(read(yourMove(1, left: 9)), [], "Once per game.")
    }

    func testOfflineNothingFalls() {
        let watcher = LowTimeHapticWatcher()
        func read(_ left: TimeInterval, connected: Bool) -> [Int] {
            watcher.record([yourMove(1, left: left)], accountID: 5, isConnected: connected)
        }
        XCTAssertEqual(read(12, connected: true), [])
        XCTAssertEqual(read(9, connected: false), [], "A socket that is down stops the clock's ticks.")
        XCTAssertEqual(read(8, connected: true), [], "A fall during the outage isn't seen once the socket is back.")
        XCTAssertEqual(read(30, connected: true), [])
        XCTAssertEqual(read(9, connected: true), [1])
        XCTAssertTrue(watcher.doneGameIDs.contains(1))
    }

    func testEachGameFallsOnceAndAnotherAccountStartsOver() {
        let watcher = LowTimeHapticWatcher()
        func read(_ first: TimeInterval, _ second: TimeInterval, account: Int = 5) -> [Int] {
            watcher.record([yourMove(1, left: first), yourMove(2, left: second)], accountID: account, isConnected: true)
        }
        XCTAssertEqual(read(12, 20), [])
        XCTAssertEqual(read(9, 15), [1])
        XCTAssertEqual(read(8, 11), [])
        XCTAssertEqual(read(7, 10), [2])
        XCTAssertEqual(watcher.doneGameIDs, [1, 2])

        XCTAssertEqual(read(12, 12, account: 6), [])
        XCTAssertEqual(watcher.doneGameIDs, [], "Another account starts over.")
        XCTAssertEqual(read(9, 9, account: 6), [1, 2])
    }

    // MARK: Byo-yomi

    /// One of the user's live games on byo-yomi, in which they play Black,
    /// on a clock the test sets and reads as the watcher reads it.
    private final class ByoyomiGame {
        let id: Int
        let userID: Int
        /// The user's main time and periods as the turn in play began.
        var main: TimeInterval
        var periods: Int
        private let opponentID: Int
        private let period: TimeInterval
        private let system: TimeControlSystem
        private let game: Game
        /// Gives the game its signed-in user.
        private let service: OGSService
        /// Second 0, in seconds since 1970.
        private let reference: TimeInterval = 1_794_220_920

        /// Black's turn from second 0, with all of `main` and every period.
        init(main: Int, periods: Int, period: Int, preferences: UserDefaults) throws {
            let system = TimeControlSystem.ByoYomi(mainTime: main, periods: periods, periodTime: period)
            let url = try XCTUnwrap(Bundle(for: LowTimeHapticWatcherTests.self)
                .url(forResource: "game-27053412", withExtension: "json"))
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
            let game = Game(ogsGame: data)
            let service = OGSService(
                environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
                httpClient: OGSOfflineRejectingHTTPClient(), preferences: preferences,
                ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
                usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
                installsObservers: false)
            id = try XCTUnwrap(game.ogsID)
            userID = data.players.black.id
            opponentID = data.players.white.id
            self.main = TimeInterval(main)
            self.periods = periods
            self.period = TimeInterval(period)
            self.system = system
            self.game = game
            self.service = service
            service.user = OGSUser(username: "black", id: data.players.black.id, rank: 25)
            game.ogs = service
            game.clock = data.clock
            turn(.black, from: 0)
        }

        /// `color`'s turn from `second`, as OGS sends the clock at a move:
        /// the user's time is `main` and `periods`.
        func turn(_ color: StoneColor, from second: TimeInterval) {
            let time = ThinkingTime(thinkingTime: main, thinkingTimeLeft: main, periods: periods,
                                    periodsLeft: periods, periodTime: period, periodTimeLeft: period)
            game.clock?.blackTime = time
            game.clock?.whiteTime = time
            game.clock?.currentPlayerColor = color
            game.clock?.currentPlayerId = color == .black ? userID : opponentID
            game.clock?.lastMoveTime = (reference + second) * 1_000
        }

        /// The game as the watcher reads it at `second`.
        func read(at second: TimeInterval) throws -> ActivityModel.LiveGame {
            game.clock?.calculateTimeLeft(with: system, pauseControl: nil, now: (reference + second) * 1_000)
            return try XCTUnwrap(ActivityModel.LiveGame(game: game, userID: userID))
        }
    }

    /// A fall: how many seconds into the user's turn, with the seconds then
    /// left to timeout.
    private struct Fall: Equatable {
        var second: Int
        var left: TimeInterval
    }

    /// The falls a watcher sees in one turn of the user's that runs from all
    /// of `main` to timeout, read once a second.
    private func falls(main: Int, periods: Int, period: Int) throws -> [Fall] {
        let game = try ByoyomiGame(main: main, periods: periods, period: period, preferences: preferences())
        let watcher = LowTimeHapticWatcher()
        var falls = [Fall]()
        for second in 0...(main + periods * period) {
            let live = try game.read(at: TimeInterval(second))
            if watcher.record([live], accountID: game.userID, isConnected: true) == [game.id] {
                falls.append(Fall(second: second, left: try XCTUnwrap(live.timeUntilTimeout)))
            }
        }
        return falls
    }

    func testInByoyomiOnlyTheLastPeriodCounts() throws {
        XCTAssertEqual(try falls(main: 30, periods: 5, period: 5), [Fall(second: 50, left: 5)],
                       "Entering the last 5 s period is the fall: at 45 s two periods left are 10 s in all.")
        XCTAssertEqual(try falls(main: 30, periods: 5, period: 10), [Fall(second: 70, left: 10)],
                       "Entering a last period of 10 s is the fall.")
        XCTAssertEqual(try falls(main: 60, periods: 3, period: 30), [Fall(second: 140, left: 10)],
                       "A last period of 30 s falls through 10 s.")
    }

    func testMainTimeIsNeverTheLastPeriod() throws {
        XCTAssertEqual(try falls(main: 30, periods: 1, period: 5), [Fall(second: 30, left: 5)],
                       "With one period, entering it is the fall: at 25 s main time and the period are 10 s in all.")
    }

    func testATurnThatStartsInTheLastPeriodIsAFall() throws {
        let game = try ByoyomiGame(main: 30, periods: 5, period: 5, preferences: preferences())
        game.main = 0
        game.periods = 1
        game.turn(.white, from: 0)
        let watcher = LowTimeHapticWatcher()
        func read(_ second: TimeInterval) throws -> [Int] {
            watcher.record([try game.read(at: second)], accountID: game.userID, isConnected: true)
        }
        XCTAssertEqual(try read(1), [], "The opponent's move reads as above 10 s.")
        game.turn(.black, from: 2)
        XCTAssertEqual(try read(2), [game.id], "The user's turn starts in the last period, with 5 s.")
        XCTAssertEqual(try read(3), [])

        let opened = LowTimeHapticWatcher()
        game.turn(.black, from: 10)
        XCTAssertEqual(opened.record([try game.read(at: 11)], accountID: game.userID, isConnected: true), [],
                       "A window that opens during the turn never sees its start.")

        let fischer = LowTimeHapticWatcher()
        let theirs = Model.LiveGame(id: 2, isYourMove: false, isClockRunning: false, timeUntilTimeout: 8)
        XCTAssertEqual(fischer.record([theirs], accountID: 5, isConnected: true), [])
        XCTAssertEqual(fischer.record([yourMove(2, left: 8)], accountID: 5, isConnected: true), [],
                       "Other clocks fall only while they run on the user's move.")
    }

    func testAfterTheSocketWasDownATurnsStartIsNotSeen() throws {
        let game = try ByoyomiGame(main: 30, periods: 5, period: 5, preferences: preferences())
        game.main = 0
        game.periods = 1
        game.turn(.white, from: 0)
        let watcher = LowTimeHapticWatcher()
        func read(_ second: TimeInterval, connected: Bool = true) throws -> [Int] {
            watcher.record([try game.read(at: second)], accountID: game.userID, isConnected: connected)
        }
        XCTAssertEqual(try read(1), [])
        XCTAssertEqual(try read(2, connected: false), [], "The socket goes down on the opponent's move.")
        game.turn(.black, from: 3)
        XCTAssertEqual(try read(3, connected: false), [])
        XCTAssertEqual(try read(4), [], "Back with the turn under way: its start wasn't seen.")
        XCTAssertEqual(try read(5), [])

        game.turn(.white, from: 6)
        XCTAssertEqual(try read(7), [], "Connected on the opponent's move again.")
        game.turn(.black, from: 8)
        XCTAssertEqual(try read(8), [game.id], "So the next turn's start is a fall.")
    }

    #if DEBUG
    // MARK: What plays

    private typealias ID = SurroundUITestContract.ActivityFixtureID
    /// `low-time` has HarborMist's game 22 s into the user's last 30 s
    /// period at this second: 0:08 left.
    private let fixtureClock = ActivityFixtures.Clock(reference: 1_794_220_920)

    /// One window: its service in `low-time`, and the timer, poster, cover,
    /// screen and Settings › Haptics the watcher reads.
    private final class Window {
        let ogs: OGSService
        let game: Game
        let preferences: UserDefaults
        let timer = PassthroughSubject<Date, Never>()
        let watcher = LowTimeHapticWatcher()
        var posted = [AppAnnouncement]()
        var isCovered = false
        var onScreen = Set<Int>()
        private let reference: TimeInterval

        init(ogs: OGSService, preferences: UserDefaults, reference: TimeInterval) throws {
            self.ogs = ogs
            game = try XCTUnwrap(ogs.activeGames[ID.harborMistGameID])
            self.preferences = preferences
            self.reference = reference
        }

        func attach(isMac: Bool = false) {
            watcher.attach(
                ogs: ogs,
                post: { [unowned self] in self.posted.append($0) },
                isCovered: { [unowned self] in self.isCovered },
                gamesOnScreen: { [unowned self] in self.onScreen },
                ticks: timer.eraseToAnyPublisher(),
                preferences: preferences,
                isMac: isMac
            )
        }

        /// The service's clocks move to the second where the user has `left`
        /// in the last period.
        func setTimeLeft(_ left: TimeInterval) {
            guard let system = game.gameData?.timeControl.system else { return }
            game.clock?.calculateTimeLeft(with: system, pauseControl: game.pauseControl,
                                          now: (reference + 8 - left) * 1_000)
        }

        /// The clocks move to `left`, then the timer ticks.
        func tick(_ left: TimeInterval) {
            setTimeLeft(left)
            timer.send(Date())
        }

        func ticks(_ timesLeft: TimeInterval...) {
            timesLeft.forEach(tick)
        }
    }

    private func window(socketStatus: OGSWebsocketStatus = .connected) throws -> Window {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let game = Game(ogsGame: try decoder.decode(OGSGame.self, from: Data(contentsOf: url)))
        game.ogsRawData = [:]
        var state = OGSService.BootstrapState()
        state.user = try XCTUnwrap(game.whitePlayer)
        state.isLoggedIn = true
        state.socketStatus = socketStatus
        state.isLoadingOverview = false
        state.activeGames[SurroundUITestContract.fixtureGameID] = game
        state.finishedGamesSnapshot = []
        ActivityFixtures.apply(.lowTime, to: &state, clock: fixtureClock)
        let preferences = try self.preferences()
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: preferences,
            ogsWebsocket: OGSOfflineNoOpWebsocket(status: socketStatus), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
        ActivityFixtures.finish(.lowTime, service: service)
        return try Window(ogs: service, preferences: preferences, reference: fixtureClock.reference)
    }

    func testAFallPlaysOneWarningHapticFromTheTimer() throws {
        let window = try window()
        window.attach()
        let left = window.game.timeUntilTimeout(for: .white)
        XCTAssertEqual(left, 8, "The user's own clock, in the last period.")
        window.ticks(12, 11)
        XCTAssertEqual(window.posted, [])
        window.tick(10)
        XCTAssertEqual(window.posted, [
            AppAnnouncement(.lowTime(ID.harborMistGameID), audience: .frontmostWindow, haptic: .warning),
        ], "A haptic with no speech, played once per app from the window the user is in.")
        window.ticks(9, 3)
        XCTAssertEqual(window.posted.count, 1, "Once per game.")

        let between = try self.window()
        between.attach()
        between.setTimeLeft(12)
        between.setTimeLeft(9)
        XCTAssertEqual(between.posted, [], "Nothing reads the clocks between the timer's ticks.")
        between.timer.send(Date())
        XCTAssertEqual(between.posted, [], "Its first read already had 9 s left.")
    }

    func testAWindowThatOpensUnderTenSecondsNeverPlaysIt() throws {
        let window = try window()
        window.attach()
        window.ticks(8, 7, 3, 1)
        XCTAssertEqual(window.posted, [])
        XCTAssertEqual(window.watcher.doneGameIDs, [])
    }

    func testOnlyAnotherGameThanTheOneOnScreenPlays() throws {
        let watching = try window()
        watching.onScreen = [ID.harborMistGameID]
        watching.attach()
        watching.ticks(12, 9)
        XCTAssertEqual(watching.posted, [], "Its own clock is in front of the user.")
        XCTAssertEqual(watching.watcher.doneGameIDs, [ID.harborMistGameID])
        watching.onScreen = []
        watching.ticks(8, 3)
        XCTAssertEqual(watching.posted, [], "Leaving it under 10 s plays nothing either.")

        let elsewhere = try window()
        elsewhere.onScreen = [SurroundUITestContract.fixtureGameID]
        elsewhere.attach()
        elsewhere.ticks(12, 9)
        XCTAssertEqual(elsewhere.posted.map(\.key), [.lowTime(ID.harborMistGameID)])
    }

    func testUnderTheCoverTheGameIsDoneWithoutPlaying() throws {
        let window = try window()
        window.isCovered = true
        window.attach()
        window.ticks(12, 9)
        XCTAssertEqual(window.posted, [])
        XCTAssertEqual(window.watcher.doneGameIDs, [ID.harborMistGameID])
        window.isCovered = false
        window.ticks(8, 3)
        XCTAssertEqual(window.posted, [], "The cover lowering doesn't play it late.")
    }

    func testSettingsHapticsOffSilencesIt() throws {
        let window = try window()
        window.preferences[.hapticsFeedback] = false
        window.attach()
        window.ticks(12, 9)
        XCTAssertEqual(window.posted, [])
        XCTAssertEqual(window.watcher.doneGameIDs, [ID.harborMistGameID])
        window.preferences[.hapticsFeedback] = true
        window.ticks(8, 3)
        XCTAssertEqual(window.posted, [], "Turning haptics on later doesn't play it late.")
    }

    func testOfflineNothingPlays() throws {
        let window = try window(socketStatus: .reconnecting)
        window.attach()
        window.ticks(12, 9, 3)
        XCTAssertEqual(window.posted, [])
        XCTAssertEqual(window.watcher.doneGameIDs, [])
    }

    func testTheMacPlaysNothing() throws {
        let window = try window()
        window.attach(isMac: true)
        window.ticks(12, 9, 3)
        XCTAssertEqual(window.posted, [])
        XCTAssertEqual(window.watcher.doneGameIDs, [], "Nothing is read on the Mac.")
    }
    #endif
}
