//
//  StartedGamesRecorderTests.swift
//  SurroundTests
//
//  The live games a window records as started. The games of its first
//  overview load, and of the first load after an account change, were
//  already running; a load that failed applied no overview and doesn't
//  count. A game that appears after them counts from then until the window
//  shows or opens it, or for 30 s, and its "Game started" is said once.
//

import Combine
import XCTest

final class StartedGamesRecorderTests: XCTestCase {
    private final class Clock {
        var now: TimeInterval = 1_794_220_920
    }

    /// A window as the recorder follows it, with each value set by hand.
    private final class Window {
        let account = CurrentValueSubject<Int?, Never>(592_684)
        let isLoading: CurrentValueSubject<Bool, Never>
        let applied: CurrentValueSubject<Int, Never>
        let live: CurrentValueSubject<Set<Int>, Never>
        let opened = CurrentValueSubject<Set<Int>, Never>([])
        let clock = Clock()
        let recorder = StartedGamesRecorder()

        /// A service that isn't loading has applied an overview, unless
        /// `appliedOverviews` says otherwise.
        init(isLoading: Bool, live: Set<Int> = [], appliedOverviews: Int? = nil) {
            self.isLoading = CurrentValueSubject(isLoading)
            applied = CurrentValueSubject(appliedOverviews ?? (isLoading ? 0 : 1))
            self.live = CurrentValueSubject(live)
            let clock = clock
            recorder.attach(StartedGamesRecorder.Feed(
                accountID: account.eraseToAnyPublisher(),
                isLoadingOverview: self.isLoading.eraseToAnyPublisher(),
                appliedOverviews: applied.eraseToAnyPublisher(),
                liveGameIDs: self.live.eraseToAnyPublisher(),
                openedGameIDs: opened.eraseToAnyPublisher()
            ), now: { clock.now })
        }

        var started: Set<Int> { Set(recorder.startedGames.keys) }

        /// The service applies an overview that lists `games`.
        func apply(_ games: Set<Int>) {
            live.send(games)
            applied.send(applied.value + 1)
        }

        /// An overview load from start to end that lists `games`.
        func load(_ games: Set<Int>) {
            isLoading.send(true)
            apply(games)
            isLoading.send(false)
        }

        /// An overview load from start to end that fails, applying nothing.
        func failLoad() {
            isLoading.send(true)
            isLoading.send(false)
        }
    }

    // MARK: Seeding

    func testTheFirstLoadsGamesWereAlreadyRunning() {
        let window = Window(isLoading: true, live: [1])
        window.apply([1, 2])
        XCTAssertEqual(window.started, [], "Nothing counts before the window's first load ends.")
        window.isLoading.send(false)
        XCTAssertEqual(window.started, [], "The first load's games were running before the window heard of them.")

        window.clock.now += 3
        window.live.send([1, 2, 3])
        XCTAssertEqual(window.recorder.startedGames, [3: window.clock.now], "From when it appeared.")
        window.clock.now += 1
        window.load([1, 2, 3])
        XCTAssertEqual(window.recorder.startedGames, [3: window.clock.now - 1], "Every later load only lists it again.")
    }

    func testAWindowThatHasLoadedCountsFromWhenItAttaches() {
        let window = Window(isLoading: false, live: [1])
        XCTAssertEqual(window.started, [])
        window.live.send([1, 4])
        XCTAssertEqual(window.started, [4])
    }

    func testAFailedLoadSeedsNothing() {
        let window = Window(isLoading: true)
        window.isLoading.send(false)
        window.live.send([1, 2])
        XCTAssertEqual(window.started, [], "A first load that failed listed no games, so none can count.")
        window.failLoad()
        XCTAssertEqual(window.started, [], "Nor does a pull to refresh that fails.")
        window.load([1, 2, 3])
        XCTAssertEqual(window.started, [], "The first load that applies an overview seeds silently.")
        window.live.send([1, 2, 3, 4])
        XCTAssertEqual(window.started, [4])
    }

    func testAWindowWhoseServiceHasAppliedNoOverviewWaitsForOne() {
        let window = Window(isLoading: false, live: [1], appliedOverviews: 0)
        window.live.send([1, 2])
        XCTAssertEqual(window.started, [], "The last launch's games, or none, never seed.")
        window.load([1, 2, 3])
        XCTAssertEqual(window.started, [], "The first overview applied seeds silently.")
        window.live.send([1, 2, 3, 4])
        XCTAssertEqual(window.started, [4])

        window.account.send(915_100)
        window.failLoad()
        window.live.send([30, 31])
        XCTAssertEqual(window.started, [], "After an account change, a first load that fails seeds nothing either.")
        window.load([30, 31])
        XCTAssertEqual(window.started, [])
        window.live.send([30, 31, 32])
        XCTAssertEqual(window.started, [32])
    }

    func testAStartedGameCountsForThirtySeconds() {
        let window = Window(isLoading: false)
        let start = window.clock.now
        window.live.send([5])
        window.clock.now = start + ActivityModel.startedLeadDuration - 0.5
        XCTAssertEqual(window.recorder.startedGames, [5: start])
        window.clock.now = start + ActivityModel.startedLeadDuration
        XCTAssertEqual(window.started, [], "30 s after it appeared.")
        window.live.send([5, 6])
        XCTAssertEqual(window.started, [6], "A game that has had its 30 s never counts again.")
    }

    func testShowingOrOpeningAStartedGameStopsItCounting() {
        let window = Window(isLoading: false)
        window.live.send([7, 8, 9])
        window.opened.send([7])
        XCTAssertEqual(window.started, [8, 9], "A Game Detail in the window shows it, or the window opens it.")
        window.opened.send([])
        XCTAssertEqual(window.started, [8, 9], "Leaving it doesn't bring it back.")

        window.opened.send([10])
        window.live.send([7, 8, 9, 10])
        XCTAssertEqual(window.started, [8, 9], "A game the window was already opening never counts.")
    }

    func testAnAccountChangeWaitsForTheNewAccountsFirstLoad() {
        let window = Window(isLoading: false, live: [1])
        window.live.send([1, 2])
        XCTAssertEqual(window.started, [2])
        XCTAssertTrue(window.recorder.claimAnnouncement(for: 2))

        window.account.send(915_100)
        XCTAssertEqual(window.started, [], "Another account's games don't carry over.")
        window.isLoading.send(false)
        window.live.send([30, 31])
        XCTAssertEqual(window.started, [], "A load that was already running belongs to the old account.")
        window.load([30, 31, 32])
        XCTAssertEqual(window.started, [], "The new account's first load seeds silently.")
        window.live.send([30, 31, 32, 33])
        XCTAssertEqual(window.started, [33])
        XCTAssertTrue(window.recorder.claimAnnouncement(for: 2), "What was said goes with the old account.")

        window.account.send(915_100)
        XCTAssertEqual(window.started, [33], "The same account again changes nothing.")
        window.account.send(nil)
        XCTAssertEqual(window.started, [], "Signing out starts over too.")
    }

    func testEachStartedGameIsAnnouncedOnce() {
        let window = Window(isLoading: false)
        window.live.send([4, 5])
        XCTAssertTrue(window.recorder.claimAnnouncement(for: 4))
        XCTAssertFalse(window.recorder.claimAnnouncement(for: 4), "Said once, by the first to ask.")
        XCTAssertTrue(window.recorder.claimAnnouncement(for: 5))
        window.opened.send([4])
        XCTAssertFalse(window.recorder.claimAnnouncement(for: 4), "Still said, after it stops counting.")
    }

    // MARK: The window's navigation

    func testTheWindowsNavigationSaysWhatItShowsOrOpens() {
        let nav = NavigationService()
        var opened = Set<Int>()
        let observation = StartedGamesRecorder.openedGameIDs(in: nav).sink { opened = $0 }
        defer { observation.cancel() }
        XCTAssertEqual(opened, [])

        nav.gameDetailNotificationContexts[UUID()] = GameDetailNotificationContext(
            ownLiveGame: .OGS(11), showsLiveGameInPlay: true)
        nav.gameDetailNotificationContexts[UUID()] = GameDetailNotificationContext(showsLiveGameInPlay: true)
        XCTAssertEqual(opened, [11], "Your own live game on screen; a game you watch isn't yours.")
        XCTAssertEqual(nav.ownLiveGameIDsOnScreen, [11])

        nav.requestGameOpen(AppRoute(rootView: .home, ogsGameID: 12)!)
        XCTAssertEqual(opened, [11, 12], "A pending open.")
        nav.clearPendingGameOpen()
        nav.home.activeGame = Game(width: 19, height: 19, blackName: "", whiteName: "", gameId: .OGS(13))
        XCTAssertEqual(opened, [11, 13], "Home's game, about to show.")
        nav.gameDetailNotificationContexts.removeAll()
        nav.home.activeGame = nil
        XCTAssertEqual(opened, [])
        XCTAssertEqual(nav.ownLiveGameIDsOnScreen, [])
    }

    #if DEBUG
    // MARK: A window's service

    private let fixtureClock = ActivityFixtures.Clock(reference: 1_794_220_920)   // 9 Nov 2026, 10:42 UTC
    private var suites = [String]()

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        super.tearDown()
    }

    /// The plain offline journey in `challenge-received`, with Accept answered
    /// at once by a new live game, as `--surround-activity-actions succeed` does.
    /// - Parameter isLoading: The service starts with an overview load in
    ///   progress and none applied, as an app launch does.
    private func challengeReceivedService(isLoading: Bool = false) throws -> OGSService {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let game = Game(ogsGame: try decoder.decode(OGSGame.self, from: Data(contentsOf: url)))
        game.ogsRawData = [:]
        var state = OGSService.BootstrapState()
        state.user = try XCTUnwrap(game.whitePlayer)
        state.isLoggedIn = true
        state.socketStatus = .connected
        state.isLoadingOverview = isLoading
        state.activeGames[SurroundUITestContract.fixtureGameID] = game
        state.finishedGamesSnapshot = []
        ActivityFixtures.apply(.challengeReceived, to: &state, clock: fixtureClock)
        state.activityActions = ActivityFixtures.Actions(mode: .succeed, clock: fixtureClock, delay: 0)
        let suite = "com.honganhkhoa.Surround.StartedGamesRecorderTests.\(UUID().uuidString)"
        suites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
        ActivityFixtures.finish(.challengeReceived, service: service)
        return service
    }

    /// The accepted game's id, once the service answers.
    private func accept(_ challenge: OGSDirectChallenge, in ogs: OGSService) throws -> Int {
        let answered = expectation(description: "Accept answers")
        var gameID: Int?
        let subscription = ogs.acceptChallenge(challenge: challenge).sink(
            receiveCompletion: { _ in answered.fulfill() }, receiveValue: { gameID = $0 })
        wait(for: [answered], timeout: 5)
        subscription.cancel()
        return try XCTUnwrap(gameID)
    }

    func testTheWindowsServiceAndNavigationFeedIt() throws {
        let ogs = try challengeReceivedService()
        let nav = NavigationService()
        let clock = Clock()
        let recorder = StartedGamesRecorder()
        recorder.attach(ogs: ogs, navigation: nav, now: { clock.now })
        XCTAssertFalse(ogs.liveGames.isEmpty)
        XCTAssertEqual(ogs.appliedOverviewCount, 1, "A state that isn't loading stands for an applied overview.")
        XCTAssertEqual(recorder.startedGames, [:], "The window had loaded: its live games were running.")

        let challenge = try XCTUnwrap(ogs.challengesReceived.first)
        let gameID = try accept(challenge, in: ogs)
        XCTAssertTrue(ogs.liveGames.contains { $0.ogsID == gameID })
        XCTAssertEqual(recorder.startedGames, [gameID: clock.now], "Started elsewhere: nothing here opened it.")
        XCTAssertTrue(recorder.claimAnnouncement(for: gameID))

        nav.requestGameOpen(try XCTUnwrap(AppRoute(rootView: .home, ogsGameID: gameID)))
        XCTAssertEqual(recorder.startedGames, [:], "The window is opening it.")

        ogs.user = OGSUser(username: "tenuki_tom", id: 915_100)
        XCTAssertTrue(recorder.claimAnnouncement(for: gameID), "Another account starts over.")
    }

    func testAFailedLoadOfTheServiceSeedsNothing() throws {
        let ogs = try challengeReceivedService(isLoading: true)
        XCTAssertEqual(ogs.appliedOverviewCount, 0)
        let clock = Clock()
        let recorder = StartedGamesRecorder()
        recorder.attach(ogs: ogs, navigation: NavigationService(), now: { clock.now })

        let ended = expectation(description: "The load ends")
        let loading = ogs.$isLoadingOverview.dropFirst().filter { !$0 }.sink { _ in ended.fulfill() }
        ogs.loadOverview()
        wait(for: [ended], timeout: 5)
        loading.cancel()
        XCTAssertEqual(ogs.appliedOverviewCount, 0, "Offline, the load fails and applies nothing.")

        let gameID = try accept(try XCTUnwrap(ogs.challengesReceived.first), in: ogs)
        XCTAssertTrue(ogs.liveGames.contains { $0.ogsID == gameID })
        XCTAssertEqual(recorder.startedGames, [:], "The failed load seeded nothing, so nothing reads as started.")
    }
    #endif
}
