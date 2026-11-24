//
//  ActivityBarStateTests.swift
//  SurroundTests
//
//  One window's Activity bar state over a real OGSService in an Activity
//  state, the window's own stores and a connection source, each driven by
//  hand: its first value at once on attaching; each source of change read a
//  main-queue turn later; a result's 4 s end and a started game's 30 s end;
//  nothing published while the stable value stays the same; hidden ids
//  forgotten once the service drops the item; and what it says as a lead
//  first leads on a root screen.
//

#if DEBUG
import Combine
import XCTest

final class ActivityBarStateTests: XCTestCase {
    private typealias Model = ActivityModel
    private typealias Fixtures = ActivityFixtures
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias ID = SurroundUITestContract.ActivityFixtureID

    /// Runs work only when the test says so: `turn()` runs what `async`
    /// queued, as the main queue's next turn would, and `advance()` runs every
    /// deadline scheduled before it.
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
        private var turns = [() -> Void]()

        var pendingDelays: [TimeInterval] { work.keys.sorted().compactMap { work[$0]?.delay } }
        var pendingTurns: Int { turns.count }

        func async(_ block: @escaping () -> Void) { turns.append(block) }

        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            nextID += 1
            let id = nextID
            work[id] = (delay, block)
            return Cancellation { [weak self] in self?.work.removeValue(forKey: id) }
        }

        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            preconditionFailure("Nothing here repeats.")
        }

        func turn() {
            let due = turns
            turns = []
            due.forEach { $0() }
        }

        func advance() {
            for id in work.keys.sorted() {
                guard let due = work.removeValue(forKey: id) else { continue }
                due.block()
            }
        }
    }

    private final class Clock {
        var now: TimeInterval
        init(_ now: TimeInterval) { self.now = now }
    }

    private final class SilentNavigator: ActivityNavigating {
        func openGame(_ gameID: Int, closesNewGame: Bool) {}
        func announce(_ announcement: AppAnnouncement) {}
    }

    /// Answers each reject or withdraw when the test completes its reply.
    private final class FakeClient {
        private(set) var replies = [PassthroughSubject<Void, Error>]()

        var client: ActivityResults.Client {
            ActivityResults.Client(
                accept: { _ in Empty(completeImmediately: false).eraseToAnyPublisher() },
                withdrawOrDecline: { [unowned self] _ in
                    let reply = PassthroughSubject<Void, Error>()
                    self.replies.append(reply)
                    return reply.eraseToAnyPublisher()
                },
                cancelAutomatch: { _ in true },
                leaveRengo: { _ in Empty(completeImmediately: false).eraseToAnyPublisher() },
                startRengo: { _ in Empty(completeImmediately: false).eraseToAnyPublisher() },
                hasActiveGame: { _ in false },
                automatchLifecycleEvents: Empty(completeImmediately: false).eraseToAnyPublisher()
            )
        }

        func succeedLast() {
            replies.last?.send(())
            replies.last?.send(completion: .finished)
        }
    }

    /// 9 Nov 2026, 10:42 UTC: every Activity state's times count from here.
    private static let reference: TimeInterval = 1_794_220_920
    /// Seconds since 1970, the window's input's clock.
    private let wall = Clock(ActivityBarStateTests.reference)
    /// The results store's and the connection source's clock.
    private let uptime = Clock(1_000)
    private let barScheduler = ManualScheduler()
    private let storeScheduler = ManualScheduler()
    private let sourceScheduler = ManualScheduler()
    private let client = FakeClient()
    private let navigator = SilentNavigator()
    private let socket = CurrentValueSubject<Bool, Never>(true)

    private var ogs: OGSService!
    private var nav: NavigationService!
    private var source: ConnectionStatusSource!
    private var bar: ActivityBarState!
    /// The window's live games, as its started-games recorder hears them.
    private var live: CurrentValueSubject<Set<Int>, Never>!
    private var spoken = [ActivityBarAnnouncement]()
    private var suites = [String]()
    private var subscriptions = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        ActivitySession.reset()
    }

    override func tearDown() {
        subscriptions.removeAll()
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        ActivitySession.reset()
        super.tearDown()
    }

    // MARK: Building a window

    /// The plain offline journey's start: game 26268404, the user as White.
    private func journeyState() throws -> OGSService.BootstrapState {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.players.black.username = "OrbitFox"
        data.players.white.username = "PuzzleHeron"
        let game = Game(ogsGame: data)
        game.ogsRawData = [:]
        var state = OGSService.BootstrapState()
        state.user = try XCTUnwrap(game.whitePlayer)
        state.isLoggedIn = true
        state.socketStatus = .connected
        state.isLoadingOverview = false
        state.activeGames[SurroundUITestContract.fixtureGameID] = game
        state.finishedGamesSnapshot = []
        return state
    }

    private func service(_ state: OGSService.BootstrapState) -> OGSService {
        let suite = "com.honganhkhoa.Surround.ActivityBarStateTests.\(UUID().uuidString)"
        suites.append(suite)
        return OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
    }

    /// The window's service in `selected`, with its stores attached as
    /// MainView attaches them, but not yet its bar state.
    private func prepare(_ selected: State) throws {
        var state = try journeyState()
        Fixtures.apply(selected, to: &state, clock: Fixtures.Clock(reference: Self.reference))
        let ogs = service(state)
        Fixtures.finish(selected, service: ogs)
        prepareWindow(ogs)
    }

    /// A signed-in window whose service holds only what `build` gives it.
    private func prepareSignedIn(_ build: (inout OGSService.BootstrapState) -> Void) {
        var state = OGSService.BootstrapState()
        state.user = OGSUser(username: "current", id: 1, rank: 25)
        state.isLoggedIn = true
        build(&state)
        prepareWindow(service(state))
    }

    private func prepareWindow(_ ogs: OGSService) {
        self.ogs = ogs
        let nav = NavigationService()
        self.nav = nav
        let uptime = uptime, wall = wall
        nav.activityResults.attach(client: client.client, navigator: navigator, scheduler: storeScheduler,
                                   now: { uptime.now })
        nav.activityLastKnown.attach(ogs: ogs)
        // Seeded at once with the games the service lists now, but for a
        // started game, which appears when the test says.
        let listed = Set(ogs.liveGames.compactMap(\.ogsID)).subtracting([ID.startedGameID])
        live = CurrentValueSubject(listed)
        nav.startedGamesRecorder.attach(StartedGamesRecorder.Feed(
            accountID: Just(ogs.user?.id).eraseToAnyPublisher(),
            isLoadingOverview: Just(false).eraseToAnyPublisher(),
            appliedOverviews: Just(1).eraseToAnyPublisher(),
            liveGameIDs: live.eraseToAnyPublisher(),
            openedGameIDs: StartedGamesRecorder.openedGameIDs(in: nav)
        ), now: { wall.now })
        source = ConnectionStatusSource(socketIsConnected: socket.eraseToAnyPublisher(),
                                        path: ConstantNetworkPath.satisfied, reconnect: {},
                                        scheduler: sourceScheduler, now: { uptime.now })
        source.setVisible(true)
        bar = ActivityBarState(scheduler: barScheduler, now: { wall.now })
    }

    private func attach() {
        bar.attach(ogs: ogs, nav: nav, connection: source, announce: { [unowned self] in self.spoken.append($0) })
    }

    /// The started game appears among the window's live games, `secondsAgo`.
    private func startGame(secondsAgo: TimeInterval) {
        let now = wall.now
        wall.now = now - secondsAgo
        live.send(Set(ogs.liveGames.compactMap(\.ogsID)))
        wall.now = now
    }

    /// Waits for the main queue's next turn, on which the registry settles.
    private func settleRegistry() {
        let settled = expectation(description: "the registry's turn")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    private func register(_ place: Model.Place, in root: RootView = .home, owner: UUID) {
        nav.activityPlaces.set(.init(place: place, root: root, isOnTop: true), for: owner)
        settleRegistry()
    }

    /// How many times the bar state published from now on.
    private func countPublishes() -> () -> Int {
        var count = 0
        bar.objectWillChange.sink { count += 1 }.store(in: &subscriptions)
        return { count }
    }

    private func rejectReceivedChallenge() throws {
        let challenge = try XCTUnwrap(ogs.challengesReceived.first { $0.id == ID.usualChallengeID })
        nav.activityResults.reject(challenge: challenge, session: UUID(), itemID: "challenge-\(challenge.id)",
                                   display: ActivityRowDisplay(title: "CedarWave", detail: "19×19"),
                                   section: .challengesReceived, after: nil)
        client.succeedLast()
    }

    private var usualChallenge: ActivityBarLead {
        .challenge(Model.Challenge(id: ID.usualChallengeID, isLive: true))
    }

    private let fixtureGame = ActivityBarLead.liveGame(gameID: SurroundUITestContract.fixtureGameID)

    // MARK: The first value

    func testAttachingComputesTheFirstValueAtOnce() throws {
        try prepare(.challengeReceived)
        XCTAssertEqual(bar.activity, ActivityBarActivity(), "An unattached state publishes nothing.")
        attach()
        XCTAssertEqual(barScheduler.pendingTurns, 0)
        XCTAssertEqual(bar.activity.lead, usualChallenge, "The hosts' first pass already has it.")
        XCTAssertEqual(bar.activity.counted, [])
        XCTAssertEqual(bar.activity.countedLead, .challenge(Model.Challenge(id: ID.usualChallengeID, isLive: true)))
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge, fixtureGame])
        XCTAssertNil(bar.nowSection.statusRow)
        XCTAssertEqual(bar.connection, ActivityBarConnection(words: nil, hasConnected: true))
    }

    func testWithoutTheWindowsSourceNothingIsSaid() throws {
        try prepare(.challengeReceived)
        bar.attach(ogs: ogs, nav: nav, connection: nil)
        XCTAssertEqual(bar.connection, ActivityBarConnection())
        XCTAssertEqual(bar.activity.lead, usualChallenge)
    }

    // MARK: Each source of change

    func testTheServiceChangingRecomputesATurnLater() throws {
        try prepare(.challengeReceived)
        attach()
        ogs.processOverview(overview: ["challenges": []])
        XCTAssertEqual(bar.activity.lead, usualChallenge, "Never inside the change itself.")
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertEqual(bar.activity.lead, fixtureGame)
    }

    func testTheResultsStoresHiddenIDsRecompute() throws {
        try prepare(.challengeReceived)
        attach()
        try rejectReceivedChallenge()
        XCTAssertEqual(nav.activityResults.hiddenIDs, ["challenge-\(ID.usualChallengeID)"])
        barScheduler.turn()
        XCTAssertTrue(ogs.challengesReceived.contains { $0.id == ID.usualChallengeID }, "The service still lists it.")
        XCTAssertEqual(bar.activity.lead, fixtureGame, "What OGS confirmed gone never leads.")
        XCTAssertEqual(bar.activity.counted, [])
        XCTAssertEqual(bar.nowSection.rows, [fixtureGame], "Nor does it show as a Now row.")
    }

    func testTheChromesResultsRecompute() throws {
        try prepare(.challengeReceived)
        attach()
        let results = nav.activityResults
        results.withdraw(challenge: OGSChallengeSampleData.sampleOpenChallenge, session: results.chromeSession,
                         itemID: "waiting-open-7", display: ActivityRowDisplay(title: "Open challenge", detail: ""),
                         section: .waiting, after: nil)
        XCTAssertNil(bar.activity.result)
        barScheduler.turn()
        XCTAssertEqual(bar.activity.result, results.chromeResults.last)
        XCTAssertEqual(bar.activity.result?.state, .pending(since: 1_000))
        XCTAssertEqual(bar.activity.lead, usualChallenge, "The lead stays under the result.")
    }

    func testTheLastKnownCopyRecomputes() {
        var open = OGSChallengeSampleData.sampleOpenChallenge
        open.id = 4
        prepareSignedIn { $0.openChallengeSentById = [4: open] }
        attach()
        XCTAssertEqual(bar.activity.lead?.itemID, "waiting-open-4", "While the socket is down the copy stands in.")
        nav.activityLastKnown.reset()
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertEqual(bar.activity, ActivityBarActivity())
    }

    func testTheRegistryRecomputes() throws {
        try prepare(.challengeReceived)
        attach()
        register(.game(id: SurroundUITestContract.fixtureGameID, isOwnGame: true, isLive: true, isOver: false),
                 owner: UUID())
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertNil(bar.activity.lead, "No lead over a game.")
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge], "The Now section leaves the game on screen out.")
    }

    func testTheSelectedTabRecomputes() throws {
        try prepare(.nothingLeads)
        attach()
        XCTAssertEqual(bar.activity.lead, .nothingLeads(count: 3))
        nav.main.rootView = .privateMessages
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertEqual(bar.activity.lead, .nothingLeads(count: 1), "Unread conversations don't count on Messages.")
    }

    func testTheConnectionSourceRecomputes() throws {
        try prepare(.challengeReceived)
        attach()
        socket.send(false)
        uptime.now += ConnectionStatusModel.revealDelay
        sourceScheduler.advance()
        XCTAssertEqual(source.status, .reconnecting)
        XCTAssertEqual(bar.connection.words, nil)
        barScheduler.turn()
        XCTAssertEqual(bar.connection, ActivityBarConnection(words: .reconnecting, hasConnected: true))
        XCTAssertEqual(bar.nowSection.statusRow, NowStatusRow(.reconnecting, place: .root(isMessagesTab: false)))
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge], "The status row takes the first row's place.")
        XCTAssertEqual(bar.nowSection.counted, [], "Their move never counts.")
    }

    func testOpeningAStartedGameRecomputes() throws {
        try prepare(.gameStarted)
        startGame(secondsAgo: 5)
        attach()
        XCTAssertEqual(bar.activity.lead, .gameStarted(gameID: ID.startedGameID))
        let started = try XCTUnwrap(ogs.activeGames[ID.startedGameID])
        nav.showHomeGame(started)
        XCTAssertEqual(barScheduler.pendingTurns, 1, "The recorder publishes nothing; the window's open does.")
        barScheduler.turn()
        XCTAssertEqual(bar.activity.lead, fixtureGame)
    }

    func testChangesWithinOneTurnRecomputeOnce() throws {
        try prepare(.challengeReceived)
        attach()
        var leads = [ActivityBarLead?]()
        bar.$activity.dropFirst().sink { leads.append($0.lead) }.store(in: &subscriptions)
        try rejectReceivedChallenge()
        ogs.processOverview(overview: ["challenges": []])
        nav.main.rootView = .publicGames
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertEqual(leads, [fixtureGame])
    }

    // MARK: Deadlines

    func testAResultsFourSecondEndRemovesTheBarWithNothingElseChanging() throws {
        try prepare(.nothingWaiting)
        attach()
        XCTAssertEqual(bar.activity, ActivityBarActivity(), "Nothing waits.")
        let results = nav.activityResults
        results.withdraw(challenge: OGSChallengeSampleData.sampleOpenChallenge, session: results.chromeSession,
                         itemID: "waiting-open-7", display: ActivityRowDisplay(title: "Open challenge", detail: ""),
                         section: .waiting, after: nil)
        client.succeedLast()
        barScheduler.turn()
        XCTAssertEqual(bar.activity.result?.state, .succeeded(.withdrawn), "While its result shows, the bar stays.")
        // The service never listed it, so the state forgot its hidden id,
        // which the store publishes too.
        barScheduler.turn()
        XCTAssertEqual(barScheduler.pendingTurns, 0)

        uptime.now += ActivityResults.chromeResultDuration
        storeScheduler.advance()
        XCTAssertEqual(barScheduler.pendingTurns, 1, "The store publishes the result's end.")
        barScheduler.turn()
        XCTAssertEqual(bar.activity, ActivityBarActivity(), "No bar.")
        XCTAssertTrue(results.hiddenIDs.isEmpty)
    }

    func testAStartedGamesThirtySecondEndReordersWithoutAnotherChange() throws {
        try prepare(.gameStarted)
        startGame(secondsAgo: 5)
        attach()
        XCTAssertEqual(bar.activity.lead, .gameStarted(gameID: ID.startedGameID))
        XCTAssertEqual(barScheduler.pendingDelays, [25], "Its 30 s end, since the recorder publishes nothing.")
        wall.now += 25
        barScheduler.advance()
        XCTAssertEqual(bar.activity.lead, fixtureGame, "Now it is ordered as a live game.")
        XCTAssertEqual(bar.nowSection.rows, [fixtureGame, .liveGame(gameID: ID.startedGameID)])
        XCTAssertTrue(barScheduler.pendingDelays.isEmpty)
    }

    func testTwoGamesOnYourMoveAreReorderedEachSecond() throws {
        try prepare(.liveYourMove)
        attach()
        let harborMist = ActivityBarLead.liveGame(gameID: ID.harborMistGameID)
        XCTAssertEqual(bar.activity.lead, harborMist)
        XCTAssertTrue(barScheduler.pendingDelays.isEmpty, "One game on your move keeps its place.")

        // OrbitFox moves in 26268404, so both games are on your move.
        let user = try XCTUnwrap(ogs.user)
        let base = try XCTUnwrap(ogs.activeGames[SurroundUITestContract.fixtureGameID])
        base.clock?.currentPlayerColor = .white
        base.clock?.currentPlayerId = user.id
        ogs.objectWillChange.send()
        barScheduler.turn()
        XCTAssertEqual(bar.activity.lead, harborMist, "Least time first.")
        XCTAssertEqual(barScheduler.pendingDelays, [1])

        // HarborMist's time grows past 26268404's, which no service change says.
        let game = try XCTUnwrap(ogs.activeGames[ID.harborMistGameID])
        game.clock?.whiteTime.thinkingTimeLeft = 900
        XCTAssertEqual(barScheduler.pendingTurns, 0)
        barScheduler.advance()
        XCTAssertEqual(bar.activity.lead, fixtureGame)
        XCTAssertEqual(barScheduler.pendingDelays, [1])
    }

    func testTheNextDeadline() {
        func game(_ id: Int, yourMove: Bool, running: Bool = true) -> Model.LiveGame {
            Model.LiveGame(id: id, isYourMove: yourMove, isClockRunning: running, timeUntilTimeout: 100)
        }
        var input = Model.Input()
        input.now = 1_000
        XCTAssertNil(ActivityBarState.nextDeadline(input, startedLeads: false), "Nothing waits for time.")
        input.liveGames = [game(1, yourMove: true), game(2, yourMove: true)]
        XCTAssertEqual(ActivityBarState.nextDeadline(input, startedLeads: false), 1)
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertNil(ActivityBarState.nextDeadline(input, startedLeads: false), "The game on screen has no place to lose.")

        input.place = .root(isMessagesTab: false)
        input.liveGames = [game(1, yourMove: true), game(3, yourMove: false)]
        input.startedGames = [3: 990]
        XCTAssertEqual(ActivityBarState.nextDeadline(input, startedLeads: true), 1,
                       "Low time on a game on your move would end the started game's lead.")
        XCTAssertEqual(ActivityBarState.nextDeadline(input, startedLeads: false), 20,
                       "Otherwise the started game's 30 s end.")
        input.liveGames = [game(1, yourMove: true, running: false), game(3, yourMove: false)]
        XCTAssertEqual(ActivityBarState.nextDeadline(input, startedLeads: true), 20, "A paused clock never runs low.")
        input.startedGames = [3: 960]
        XCTAssertNil(ActivityBarState.nextDeadline(input, startedLeads: false), "Its 30 s are over.")
    }

    // MARK: Publishing

    func testNothingPublishesWhenTheStableValueStaysTheSame() throws {
        try prepare(.liveYourMove)
        attach()
        let publishes = countPublishes()
        ogs.objectWillChange.send()
        nav.main.rootView = .publicGames
        barScheduler.turn()
        // A clock's tick changes only the game itself.
        let game = try XCTUnwrap(ogs.activeGames[ID.harborMistGameID])
        game.clock?.whiteTime.thinkingTimeLeft = 41
        ogs.objectWillChange.send()
        barScheduler.turn()
        XCTAssertEqual(publishes(), 0)
        XCTAssertEqual(bar.activity.lead, .liveGame(gameID: ID.harborMistGameID))
    }

    // MARK: Hidden ids

    func testAHiddenIDIsForgottenOnceTheServiceDropsTheItem() throws {
        try prepare(.challengeReceived)
        attach()
        try rejectReceivedChallenge()
        barScheduler.turn()
        XCTAssertEqual(nav.activityResults.hiddenIDs, ["challenge-\(ID.usualChallengeID)"],
                       "Kept while the service still lists it.")
        ogs.processOverview(overview: ["challenges": []])
        barScheduler.turn()
        XCTAssertEqual(nav.activityResults.hiddenIDs, [])
        XCTAssertEqual(bar.activity.lead, fixtureGame)
    }

    // MARK: First leads

    func testAFirstLeadIsSaidOncePerClaim() throws {
        try prepare(.challengeReceived)
        bar.postsFirstLeads = true
        attach()
        XCTAssertEqual(spoken, [.challenge(challengeID: ID.usualChallengeID)])
        ogs.objectWillChange.send()
        barScheduler.turn()
        nav.main.rootView = .publicGames
        barScheduler.turn()
        XCTAssertEqual(spoken, [.challenge(challengeID: ID.usualChallengeID)], "Said once.")
    }

    func testAStartedGameIsClaimedThroughTheWindowsRecorder() throws {
        try prepare(.gameStarted)
        startGame(secondsAgo: 5)
        bar.postsFirstLeads = true
        attach()
        XCTAssertEqual(spoken, [.gameStarted(gameID: ID.startedGameID)])
        XCTAssertFalse(nav.startedGamesRecorder.claimAnnouncement(for: ID.startedGameID),
                       "The in-game control won't say it again.")
    }

    func testAFirstLeadWaitsBehindAGameOrAConversation() throws {
        try prepare(.challengeReceived)
        bar.postsFirstLeads = true
        let game = UUID()
        register(.game(id: SurroundUITestContract.fixtureGameID, isOwnGame: true, isLive: true, isOver: false),
                 owner: game)
        attach()
        XCTAssertEqual(spoken, [], "Held while a game is on top.")
        let conversation = UUID()
        register(.conversation, owner: conversation)
        nav.activityPlaces.remove(game)
        settleRegistry()
        barScheduler.turn()
        XCTAssertEqual(spoken, [], "And while a conversation is.")
        nav.activityPlaces.remove(conversation)
        settleRegistry()
        barScheduler.turn()
        XCTAssertEqual(spoken, [.challenge(challengeID: ID.usualChallengeID)], "Said as the root shows again.")
    }

    func testAFirstLeadIsSaidUnderASheet() throws {
        try prepare(.challengeReceived)
        bar.postsFirstLeads = true
        nav.main.activity = ActivityRequest(source: .debug, style: .sheet)
        attach()
        XCTAssertEqual(spoken, [.challenge(challengeID: ID.usualChallengeID)], "The bar waits under the sheet.")
    }

    func testWhilePostingIsOffNothingIsSaidOrClaimed() throws {
        try prepare(.gameStarted)
        startGame(secondsAgo: 5)
        attach()
        XCTAssertFalse(bar.postsFirstLeads)
        XCTAssertEqual(bar.activity.lead, .gameStarted(gameID: ID.startedGameID))
        XCTAssertEqual(spoken, [])
        XCTAssertTrue(nav.startedGamesRecorder.claimAnnouncement(for: ID.startedGameID),
                      "The in-game control can still say it.")
    }
}
extension ActivityBarStateTests {
    /// The iPad container gives the Now section one row in a short window,
    /// a main-queue turn later, as every input.
    func testAShortWindowListsOneNowRow() throws {
        try prepare(.challengeReceived)
        attach()
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge, fixtureGame])
        let publishes = countPublishes()
        bar.setNowSectionRows(1)
        XCTAssertEqual(barScheduler.pendingTurns, 1)
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge])
        XCTAssertEqual(bar.nowSection.counted, [], "Their move never counts.")
        XCTAssertEqual(publishes(), 1)
        bar.setNowSectionRows(1)
        XCTAssertEqual(barScheduler.pendingTurns, 0, "The same room asks for nothing.")
    }

    /// A window too short for even one row lists nothing, not even the
    /// window's status, so the section shows nothing; one row of room comes
    /// back with the status row in it.
    func testAWindowTooShortForOneRowListsNothing() throws {
        try prepare(.challengeReceived)
        attach()
        socket.send(false)
        uptime.now += ConnectionStatusModel.revealDelay
        sourceScheduler.advance()
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection.statusRow, NowStatusRow(.reconnecting, place: .root(isMessagesTab: false)))
        bar.setNowSectionRows(0)
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection, ActivityBarNowSection(), "No row, no status row and no +N.")
        bar.setNowSectionRows(1)
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection.statusRow, NowStatusRow(.reconnecting, place: .root(isMessagesTab: false)))
        XCTAssertEqual(bar.nowSection.rows, [], "One row of room is the status row's.")
    }

    /// Signed out, or with nothing waiting, the Now section is the status
    /// row alone during an outage: no All activity. With something waiting
    /// and room for one row, the status row takes it and All activity stays.
    func testWithNothingWaitingTheNowSectionIsTheStatusRowAlone() throws {
        prepareWindow(service(OGSService.BootstrapState()))
        attach()
        XCTAssertNil(ogs.user, "Signed out")
        socket.send(false)
        uptime.now += ConnectionStatusModel.revealDelay
        sourceScheduler.advance()
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection, ActivityBarNowSection(
            statusRow: NowStatusRow(.reconnecting, place: .root(isMessagesTab: false))),
                       "The status row, no rows, no +N and no All activity.")

        try prepare(.challengeReceived)
        attach()
        XCTAssertTrue(bar.nowSection.hasActivity)
        bar.setNowSectionRows(1)
        barScheduler.turn()
        socket.send(false)
        uptime.now += ConnectionStatusModel.revealDelay
        sourceScheduler.advance()
        barScheduler.turn()
        XCTAssertNotNil(bar.nowSection.statusRow)
        XCTAssertEqual(bar.nowSection.rows, [], "The one row of room is the status row's.")
        XCTAssertTrue(bar.nowSection.hasActivity, "All activity still opens what waits.")
    }

    /// What MainView's sink posts: the started game's opponent and the
    /// challenger by name, from the window's service; nothing once the
    /// service no longer lists them.
    func testTheFirstLeadsAreSaidWithTheNamesTheServiceHolds() throws {
        try prepare(.challengeReceived)
        XCTAssertEqual(ActivityBarState.appAnnouncement(.challenge(challengeID: ID.usualChallengeID), in: ogs),
                       AppAnnouncement(.challengeReceived(ID.usualChallengeID), audience: .frontmostWindow,
                                       speech: "Challenge from CedarWave"))
        XCTAssertNil(ActivityBarState.appAnnouncement(.challenge(challengeID: 1), in: ogs))
        try prepare(.gameStarted)
        XCTAssertEqual(ActivityBarState.appAnnouncement(.gameStarted(gameID: ID.startedGameID), in: ogs),
                       AppAnnouncement(.gameStarted(ID.startedGameID), audience: .frontmostWindow,
                                       speech: "Game started with CedarWave"))
        XCTAssertNil(ActivityBarState.appAnnouncement(.gameStarted(gameID: 1), in: ogs))
    }

    /// While the window's bar says no status, the Now section's rows stay
    /// Activity's during an outage.
    func testTheNowSectionCanLeaveTheWindowsStatusOut() throws {
        try prepare(.challengeReceived)
        bar.nowSectionSaysStatus = false
        attach()
        socket.send(false)
        uptime.now += ConnectionStatusModel.revealDelay
        sourceScheduler.advance()
        barScheduler.turn()
        XCTAssertEqual(bar.connection.words, .reconnecting)
        XCTAssertNil(bar.nowSection.statusRow)
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge, fixtureGame], "Both rows stay Activity's.")
        bar.nowSectionSaysStatus = true
        barScheduler.turn()
        XCTAssertEqual(bar.nowSection.statusRow, NowStatusRow(.reconnecting, place: .root(isMessagesTab: false)))
        XCTAssertEqual(bar.nowSection.rows, [usualChallenge])
    }
}
#endif
