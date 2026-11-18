//
//  GameControlModelTests.swift
//  SurroundTests
//
//  The value Game Detail's Active games slot shows, computed from one input
//  with no state from before it: a pure value, and a window's first read of
//  each Activity state. Also the window's width class and shape, which the
//  control's frames follow.
//

import XCTest

final class GameControlModelTests: XCTestCase {
    private typealias Model = ActivityModel
    private typealias Context = ActivityModel.GameControlContext

    private func yourMove(_ id: Int, left: TimeInterval = 300) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: true, isClockRunning: true, timeUntilTimeout: left)
    }

    // MARK: The value

    func testTheSlotKeepsTheStateButNotTheClock() {
        let game = yourMove(7, left: 42)
        XCTAssertEqual(GameControlSlot(.chip(game, plusN: 3, hasDot: true)), .chip(gameID: 7, plusN: 3, hasDot: true))
        XCTAssertEqual(GameControlSlot(.gameStarted(game, plusN: 0, hasDot: false)),
                       .gameStarted(gameID: 7, plusN: 0, hasDot: false))
        XCTAssertEqual(GameControlSlot(.gameOverCard(challengeID: 95, plusN: 2)),
                       .gameOverCard(challengeID: 95, plusN: 2))
        XCTAssertEqual(GameControlSlot(.base(plusN: 4)), .base(plusN: 4))
        XCTAssertEqual(GameControlSlot(.dot), .dot)
        XCTAssertEqual(GameControlSlot(.inbox(count: 1)), .inbox(count: 1))

        var ticked = game
        ticked.timeUntilTimeout = 41
        ticked.isInLastByoyomiPeriod = true
        XCTAssertNotEqual(ticked, game)
        XCTAssertEqual(GameControlSlot(.chip(ticked, plusN: 3, hasDot: true)),
                       GameControlSlot(.chip(game, plusN: 3, hasDot: true)),
                       "The clock ticks inside the control, never through the slot.")
    }

    func testTheSlotNeedsOneInputAndNothingFromBefore() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2, left: 100)]
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        let first = GameControlSlot(input, context: .home)
        XCTAssertEqual(first, .chip(gameID: 2, plusN: 0, hasDot: false))

        var switched = input
        switched.place = .game(id: 2, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(GameControlSlot(switched, context: .home), .chip(gameID: 1, plusN: 0, hasDot: false),
                       "After an in-place switch the next read has the new game's slot.")
        XCTAssertEqual(GameControlSlot(input, context: .home), first, "Nothing carries over between reads.")
        XCTAssertEqual(GameControlSlot(input, context: Context(isZen: true)), first, "Zen keeps only the chip.")
        XCTAssertNil(GameControlSlot(Model.Input(), context: .home), "A root screen has no slot.")
    }

    // MARK: The window

    private typealias WindowClass = GameControlWindowClass
    private typealias WidthClass = GameControlWindowClass.WidthClass

    func testTheWidthClassChangesAt390Points() {
        XCTAssertEqual(WidthClass(width: 320), .narrow)
        XCTAssertEqual(WidthClass(width: 375), .narrow, "The iPhone SE and the narrowest iPad window")
        XCTAssertEqual(WidthClass(width: 389.5), .narrow, "Below 390 pt")
        XCTAssertEqual(WidthClass(width: 390), .standard, "390 pt itself, as the iPhone 16e")
        XCTAssertEqual(WidthClass(width: 402), .standard)
        XCTAssertEqual(WidthClass(width: 1366), .standard)
        XCTAssertLessThan(WidthClass.narrow, .standard, "The classes go from narrowest to widest.")
    }

    func testEachClassRunsFromItsMinimumToTheNextOne() {
        let classes = WidthClass.allCases
        let minimums = classes.map(\.minimumWidth)
        XCTAssertEqual(minimums.first, 0, "Every width has a class.")
        XCTAssertEqual(minimums, minimums.sorted(), "Declared narrowest first.")
        XCTAssertEqual(Set(minimums).count, minimums.count, "No two classes start at one width.")
        for widthClass in classes {
            XCTAssertEqual(WidthClass(width: widthClass.minimumWidth), widthClass, "\(widthClass) starts at its minimum.")
        }
        for (narrower, wider) in zip(classes, classes.dropFirst()) {
            XCTAssertEqual(WidthClass(width: wider.minimumWidth - 0.5), narrower,
                           "Just under \(wider)'s minimum is still \(narrower).")
        }
    }

    func testTheShapeIsLandscapeOnlyWhenTheWindowIsWiderThanTall() {
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 402, height: 874)),
                       WindowClass(widthClass: .standard, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 874, height: 402)),
                       WindowClass(widthClass: .standard, shape: .landscape))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 320, height: 568)),
                       WindowClass(widthClass: .narrow, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 568, height: 320)),
                       WindowClass(widthClass: .standard, shape: .landscape), "Turned, the same window is wide enough.")
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 375, height: 548)),
                       WindowClass(widthClass: .narrow, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 600, height: 600)).shape, .portrait,
                       "A square window isn't landscape-shaped.")
    }

    func testAResizeWithinAClassAndShapeKeepsTheValue() {
        let phones = [CGSize(width: 390, height: 844), CGSize(width: 393, height: 852),
                      CGSize(width: 402, height: 874), CGSize(width: 440, height: 956)]
        let values = phones.map { WindowClass(windowSize: $0) }
        XCTAssertTrue(values.allSatisfy { $0 == WindowClass(widthClass: .standard, shape: .portrait) },
                      "Only a resize across a boundary, or a turn, gives the root a new value to publish.")
        let turned = phones.map { WindowClass(windowSize: CGSize(width: $0.height, height: $0.width)) }
        XCTAssertTrue(turned.allSatisfy { $0 == WindowClass(widthClass: .standard, shape: .landscape) })
    }

    #if DEBUG
    // MARK: A window's first read

    private typealias Fixtures = ActivityFixtures
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias ID = SurroundUITestContract.ActivityFixtureID
    private let clock = ActivityFixtures.Clock(reference: 1_794_220_920)   // 9 Nov 2026, 10:42 UTC
    private var suites = [String]()

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        super.tearDown()
    }

    /// The plain offline journey's start, as `OGSService.offlineUITestInstance()` builds it.
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

    /// A window's service as `selected` starts it, before anything publishes,
    /// with Game Detail's game, 26268404.
    private func openWindow(_ selected: State) throws -> (ogs: OGSService, game: Game, seed: Fixtures.Seed) {
        var state = try journeyState()
        let seed = Fixtures.apply(selected, to: &state, clock: clock)
        let suite = "com.honganhkhoa.Surround.GameControlModelTests.\(UUID().uuidString)"
        suites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
        Fixtures.finish(selected, service: service)
        let game = try XCTUnwrap(service.activeGames[SurroundUITestContract.fixtureGameID], "\(selected)")
        return (service, game, seed)
    }

    private func firstSlot(_ selected: State, _ context: Context = .home) throws -> GameControlSlot? {
        let window = try openWindow(selected)
        return GameControlSlot(ogs: window.ogs, showing: window.game, context: context,
                               startedGames: window.seed.startedGames, now: clock.now)
    }

    func testAWindowsFirstReadGivesEachSlot() throws {
        let harborMist = ID.harborMistGameID
        XCTAssertEqual(try firstSlot(.liveYourMove), .chip(gameID: harborMist, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.several), .chip(gameID: harborMist, plusN: 0, hasDot: true))
        XCTAssertEqual(try firstSlot(.several, Context(isZen: true)), .chip(gameID: harborMist, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.gameStarted), .gameStarted(gameID: ID.startedGameID, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.challengeReceived), .dot)
        XCTAssertEqual(try firstSlot(.nothingLeads), .base(plusN: 3))
        XCTAssertEqual(try firstSlot(.nothingLeads, Context(allowsPicker: false)), .inbox(count: 3))
        XCTAssertEqual(try firstSlot(.nothingWaiting), .base(plusN: 0))
        XCTAssertNil(try firstSlot(.nothingWaiting, Context(allowsPicker: false)))
        XCTAssertEqual(try firstSlot(.rematchOffered), .base(plusN: 1))
        XCTAssertEqual(try firstSlot(.rematchOffered, Context(cardChallengeID: ID.rematchChallengeID)),
                       .gameOverCard(challengeID: ID.rematchChallengeID, plusN: 0))
    }

    func testTheWindowsStartedGamesAndTimeAreInputs() throws {
        let window = try openWindow(.gameStarted)
        let started = window.seed.startedGames
        XCTAssertEqual(GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                                       startedGames: [:], now: clock.now),
                       .base(plusN: 0), "Without the window's started games it is a live game on their move.")
        XCTAssertEqual(GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                                       startedGames: started, now: clock.now + Model.startedLeadDuration),
                       .base(plusN: 0), "It leads for 30 s.")
    }

    func testTheGameOnScreenCountsAsOverTheMomentItEnds() throws {
        let window = try openWindow(.challengeReceived)
        func slot() -> GameControlSlot? {
            GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                            startedGames: window.seed.startedGames, now: clock.now)
        }
        XCTAssertEqual(slot(), .dot)
        window.game.gamePhase = .finished
        XCTAssertTrue(window.ogs.liveGames.contains { $0 === window.game }, "The service still lists it as live.")
        XCTAssertEqual(slot(), .base(plusN: 1), "Game over releases what waited, read from the game itself.")
    }

    func testSignedOutThereIsNoSlot() throws {
        let window = try openWindow(.several)
        window.ogs.user = nil
        for context in [Context.home, Context(isZen: true), Context(allowsPicker: false)] {
            XCTAssertNil(GameControlSlot(ogs: window.ogs, showing: window.game, context: context,
                                         startedGames: window.seed.startedGames, now: clock.now), "\(context)")
        }
    }
    #endif
}
