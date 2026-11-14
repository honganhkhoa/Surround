//
//  AppRouteTests.swift
//  SurroundTests
//

import Combine
import SwiftUI
import XCTest

final class AppRouteTests: XCTestCase {
    private enum ResolverError: Error {
        case failed
    }

    func testProductionAndBetaRoundTrips() throws {
        for scheme in AppURLScheme.allCases {
            let home = try XCTUnwrap(
                AppRoute(rootView: .home, ogsGameID: 42)
            )
            let homeURL = try XCTUnwrap(home.url(scheme: scheme))
            XCTAssertEqual(
                AppRoute(url: homeURL, expectedScheme: scheme),
                home
            )

            let publicGame = try XCTUnwrap(
                AppRoute(rootView: .publicGames, ogsGameID: 7)
            )
            let publicURL = try XCTUnwrap(publicGame.url(scheme: scheme))
            XCTAssertEqual(
                AppRoute(url: publicURL, expectedScheme: scheme),
                publicGame
            )
        }
    }

    func testHomeRouteWithoutGameRoundTrips() throws {
        let route = try XCTUnwrap(AppRoute(rootView: .home))
        let url = try XCTUnwrap(route.url(scheme: .production))
        XCTAssertEqual(url.absoluteString, "surround://home")
        XCTAssertEqual(
            AppRoute(url: url, expectedScheme: .production),
            route
        )
    }

    func testRejectsInvalidGameDestinations() {
        XCTAssertNil(AppRoute(rootView: .home, ogsGameID: 0))
        XCTAssertNil(AppRoute(rootView: .home, ogsGameID: -1))
        XCTAssertNil(AppRoute(rootView: .settings, ogsGameID: 1))
    }

    func testRejectsMalformedURLs() {
        let invalidURLs = [
            "https://home/1",
            "surround://unknown/1",
            "surround://home/0",
            "surround://home/-1",
            "surround://home/1/2",
            "surround://settings/1",
            "surround://user:password@home/1",
            "surround://home:123/1",
            "surround://home/1?source=widget",
            "surround://home/1#fragment",
        ]

        for string in invalidURLs {
            XCTAssertNil(
                AppRoute(
                    url: URL(string: string)!,
                    expectedScheme: .production
                ),
                string
            )
        }
    }

    func testWrongEnvironmentSchemeIsRejected() throws {
        let betaURL = try XCTUnwrap(
            AppRoute(rootView: .home, ogsGameID: 1)?.url(scheme: .beta)
        )
        XCTAssertNil(
            AppRoute(url: betaURL, expectedScheme: .production)
        )
    }

    @MainActor
    func testFoundGameRouteDismissesTrackedSheetsAndRemainsPending() throws {
        let navigation = NavigationService()
        let currentHomeGame = Game(
            width: 19,
            height: 19,
            blackName: "Current Black",
            whiteName: "Current White",
            gameId: .OGS(41)
        )
        navigation.home.activeGame = currentHomeGame
        navigation.home.activeGameShowsCarousel = false
        navigation.publicGames.activeGame = Game(
            width: 13,
            height: 13,
            blackName: "Public Black",
            whiteName: "Public White",
            gameId: .OGS(40)
        )
        navigation.main.activity = ActivityRequest(source: .homeSearching, style: .sheet)
        navigation.home.showingNewGameView = true
        navigation.home.showingPreferredSettings = true
        navigation.home.showingGameHistory = true
        navigation.home.showingSettings = true

        navigation.handle(
            route: try XCTUnwrap(
                AppRoute(rootView: .home, ogsGameID: 42)
            )
        )

        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertNil(navigation.main.activity, "A link closes the Activity list.")
        XCTAssertFalse(navigation.home.showingNewGameView)
        XCTAssertFalse(navigation.home.showingPreferredSettings)
        XCTAssertFalse(navigation.home.showingGameHistory)
        XCTAssertFalse(navigation.home.showingSettings)
        XCTAssertTrue(navigation.home.activeGame === currentHomeGame)
        XCTAssertFalse(navigation.home.activeGameShowsCarousel)
        XCTAssertNil(navigation.publicGames.activeGame)
        XCTAssertEqual(navigation.pendingGameOpen?.rootView, .home)
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 42)
    }

    @MainActor
    func testHomeRouteWithoutGameClearsCurrentDetail() throws {
        let navigation = NavigationService()
        navigation.home.activeGame = Game(
            width: 19,
            height: 19,
            blackName: "Black",
            whiteName: "White",
            gameId: .OGS(41)
        )
        navigation.home.activeGameShowsCarousel = false

        navigation.handle(
            route: try XCTUnwrap(AppRoute(rootView: .home))
        )

        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertNil(navigation.home.activeGame)
        XCTAssertTrue(navigation.home.activeGameShowsCarousel)
        XCTAssertNil(navigation.pendingGameOpen)
    }

    @MainActor
    func testActiveGameTapReplacesHomeDetailWithoutPoppingAndSupersedesPendingRoute() throws {
        let navigation = NavigationService()
        let currentGame = Game(
            width: 19,
            height: 19,
            blackName: "Current Black",
            whiteName: "Current White",
            gameId: .OGS(41)
        )
        let liveGame = Game(
            width: 9,
            height: 9,
            blackName: "Live Black",
            whiteName: "Live White",
            gameId: .OGS(42)
        )
        navigation.home.activeGame = currentGame
        navigation.home.activeGameShowsCarousel = false
        navigation.requestGameOpen(
            try XCTUnwrap(AppRoute(rootView: .home, ogsGameID: 99))
        )
        XCTAssertNotNil(navigation.pendingGameOpen)

        // The current Home destination must remain presented throughout the
        // replacement; publishing nil would start a competing back navigation.
        var publishedHomeGameIDs = [Int?]()
        let observation = navigation.$home.sink {
            publishedHomeGameIDs.append($0.activeGame?.ogsID)
        }
        defer { observation.cancel() }

        navigation.goToActiveGame(game: liveGame)

        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertTrue(navigation.home.activeGame === liveGame)
        XCTAssertTrue(navigation.home.activeGameShowsCarousel)
        XCTAssertNil(navigation.pendingGameOpen)
        XCTAssertFalse(publishedHomeGameIDs.contains { $0 == nil })
        XCTAssertEqual(publishedHomeGameIDs.last ?? nil, liveGame.ogsID)
    }

    @MainActor
    func testActiveGameTapReturnsHomeFromEveryOtherSection() throws {
        let liveGame = Game(
            width: 9,
            height: 9,
            blackName: "Live Black",
            whiteName: "Live White",
            gameId: .OGS(42)
        )

        for section in RootView.allCases where section != .home {
            let navigation = NavigationService()
            navigation.publicGames.activeGame = Game(
                width: 19,
                height: 19,
                blackName: "Public Black",
                whiteName: "Public White",
                gameId: .OGS(40)
            )
            navigation.requestGameOpen(
                try XCTUnwrap(AppRoute(rootView: .publicGames, ogsGameID: 99))
            )
            navigation.main.rootView = section

            navigation.goToActiveGame(game: liveGame)

            XCTAssertEqual(navigation.main.rootView, .home, section.rawValue)
            XCTAssertTrue(navigation.home.activeGame === liveGame, section.rawValue)
            XCTAssertTrue(navigation.home.activeGameShowsCarousel, section.rawValue)
            XCTAssertNil(navigation.publicGames.activeGame, section.rawValue)
            XCTAssertNil(navigation.pendingGameOpen, section.rawValue)
        }
    }

    @MainActor
    func testActiveGameTapDismissesTrackedSheetsAndGameHistory() {
        let navigation = NavigationService()
        let liveGame = Game(
            width: 9,
            height: 9,
            blackName: "Live Black",
            whiteName: "Live White",
            gameId: .OGS(42)
        )
        navigation.home.showingGameHistory = true
        navigation.gameHistory.activeGame = Game(
            width: 19,
            height: 19,
            blackName: "History Black",
            whiteName: "History White",
            gameId: .OGS(40)
        )
        navigation.home.activeGameShowsCarousel = false
        navigation.openActivity(source: .waitingPill, anchor: CGRect(x: 100, y: 60, width: 120, height: 44),
                                horizontalSizeClass: .regular)
        navigation.home.showingNewGameView = true
        navigation.home.showingPreferredSettings = true
        navigation.home.showingSettings = true
        XCTAssertNotNil(navigation.main.activity)

        navigation.goToActiveGame(game: liveGame)

        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertTrue(navigation.home.activeGame === liveGame)
        XCTAssertTrue(navigation.home.activeGameShowsCarousel)
        XCTAssertFalse(navigation.home.showingGameHistory)
        XCTAssertNil(navigation.gameHistory.activeGame)
        XCTAssertNil(navigation.main.activity, "Opening a game closes the Activity list.")
        XCTAssertFalse(navigation.home.showingNewGameView)
        XCTAssertFalse(navigation.home.showingPreferredSettings)
        XCTAssertFalse(navigation.home.showingSettings)
    }

    // MARK: - Opening the Activity list

    @MainActor
    func testActivityOpensAsASheetOrAPopoverByWidthAndPlace() {
        let navigation = NavigationService()
        let card = CGRect(x: 16, y: 120, width: 360, height: 52)

        navigation.openActivity(source: .homeSearching, anchor: card, horizontalSizeClass: .compact)
        let sheet = navigation.main.activity
        XCTAssertEqual(sheet?.style, .sheet, "A compact root screen gets the sheet.")
        XCTAssertEqual(sheet?.source, .homeSearching)
        XCTAssertEqual(sheet?.place, .root(isMessagesTab: false))

        navigation.openActivity(source: .homeSearching, anchor: card, horizontalSizeClass: .regular)
        XCTAssertEqual(navigation.main.activity?.style, .popover, "A regular width gets a popover.")
        XCTAssertEqual(navigation.main.activity?.anchor, card, "It is anchored where its opener was tapped.")
        XCTAssertNotEqual(navigation.main.activity?.sessionID, sheet?.sessionID, "Each request is a new session.")

        let game = ActivityModel.Place.game(id: 42, isOwnGame: true, isLive: true, isOver: false)
        navigation.activityPlaces.set(.init(place: game, root: .home, isOnTop: true), for: UUID())
        let settled = expectation(description: "The place settles a main-queue turn later.")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        navigation.openActivity(source: .waitingPill, horizontalSizeClass: .compact)
        XCTAssertEqual(navigation.main.activity?.style, .popover, "A game gets a popover at any width.")
        XCTAssertEqual(navigation.main.activity?.place, game)
    }

    @MainActor
    func testAnActivityPopoverFollowsOnlyItsOwnOpener() {
        let navigation = NavigationService()
        let pill = CGRect(x: 120, y: 60, width: 140, height: 44)
        let moved = pill.offsetBy(dx: 200, dy: 0)
        navigation.openActivity(source: .waitingPill, anchor: pill, horizontalSizeClass: .regular)
        let session = navigation.main.activity?.sessionID

        navigation.moveActivityAnchor(to: moved, from: .challengePill)
        XCTAssertEqual(navigation.main.activity?.anchor, pill, "Another opener moves nothing.")
        navigation.moveActivityAnchor(to: moved, from: .waitingPill)
        XCTAssertEqual(navigation.main.activity?.anchor, moved, "The popover follows its opener, as on rotation.")
        XCTAssertEqual(navigation.main.activity?.sessionID, session, "It is the same list.")

        navigation.openActivity(source: .homeSearching, anchor: pill, horizontalSizeClass: .compact)
        navigation.moveActivityAnchor(to: moved, from: .homeSearching)
        XCTAssertEqual(navigation.main.activity?.anchor, pill, "A sheet has nothing to follow.")
    }

    // MARK: - Game detail display reset

    func testCrossingTheSpeedBoundaryRestoresDisplayDefaults() {
        // The live-game banner and resolved routes are the only ways to jump
        // between speed classes, and both start again from the full game view.
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(
                from: .correspondence,
                to: .live
            )
        )
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(
                from: .correspondence,
                to: .blitz
            )
        )
        // The mirror case: a route into a correspondence game must not leave
        // Zen mode or Analyze on from the live game that was open.
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(
                from: .live,
                to: .correspondence
            )
        )
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(
                from: .blitz,
                to: .correspondence
            )
        )
    }

    func testSwitchingInsideOneSpeedClassKeepsDisplayChoices() {
        // These are the carousel and Next game, which never leave their speed
        // class. A browsing session there keeps what the player chose.
        XCTAssertFalse(
            GameDetailDisplayReset.restoresDisplayDefaults(
                from: .correspondence,
                to: .correspondence
            )
        )
        for from in [TimeControlSpeed.blitz, .rapid, .live] {
            for to in [TimeControlSpeed.blitz, .rapid, .live] {
                XCTAssertFalse(
                    GameDetailDisplayReset.restoresDisplayDefaults(
                        from: from,
                        to: to
                    ),
                    "\(from.rawValue) to \(to.rawValue)"
                )
            }
        }
    }

    func testUnknownSpeedIsTreatedAsACrossingOnlyAgainstAKnownOne() {
        // A game whose detail has not arrived yet is an external jump, not a
        // carousel move, so it restores the defaults…
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(from: .correspondence, to: nil)
        )
        XCTAssertTrue(
            GameDetailDisplayReset.restoresDisplayDefaults(from: nil, to: .live)
        )
        // …while two unknowns say nothing, and must not disturb the view.
        XCTAssertFalse(
            GameDetailDisplayReset.restoresDisplayDefaults(from: nil, to: nil)
        )
    }

    @MainActor
    func testPublicGameRoutePreservesCurrentPublicDetail() throws {
        let navigation = NavigationService()
        let currentPublicGame = Game(
            width: 19,
            height: 19,
            blackName: "Black",
            whiteName: "White",
            gameId: .OGS(41)
        )
        navigation.publicGames.activeGame = currentPublicGame

        navigation.handle(
            route: try XCTUnwrap(
                AppRoute(rootView: .publicGames, ogsGameID: 42)
            )
        )

        XCTAssertEqual(navigation.main.rootView, .publicGames)
        XCTAssertTrue(
            navigation.publicGames.activeGame === currentPublicGame
        )
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 42)
    }

    @MainActor
    func testInternalGameRequestDoesNotDismissCallerOwnedNavigation() throws {
        let navigation = NavigationService()
        let currentGame = Game(
            width: 19,
            height: 19,
            blackName: "Black",
            whiteName: "White",
            gameId: .OGS(41)
        )
        navigation.home.activeGame = currentGame
        navigation.home.showingNewGameView = true
        navigation.home.showingSettings = true

        navigation.requestGameOpen(
            try XCTUnwrap(
                AppRoute(rootView: .home, ogsGameID: 42)
            )
        )

        XCTAssertTrue(navigation.home.activeGame === currentGame)
        XCTAssertTrue(navigation.home.showingNewGameView)
        XCTAssertTrue(navigation.home.showingSettings)
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 42)
    }

    @MainActor
    func testRepeatedGameRouteCreatesUniqueRetryToken() throws {
        let navigation = NavigationService()
        let route = try XCTUnwrap(
            AppRoute(rootView: .home, ogsGameID: 42)
        )

        navigation.handle(route: route)
        let firstID = try XCTUnwrap(navigation.pendingGameOpen?.id)
        navigation.handle(route: route)
        let secondID = try XCTUnwrap(navigation.pendingGameOpen?.id)

        XCTAssertNotEqual(firstID, secondID)
    }

    @MainActor
    func testGameResolverPrefersActiveThenSharedOverview() async throws {
        var requestedREST = false
        var restRequired = false
        let activeResolver = GameOpenResolver<String>(
            activeGame: { _ in "active" },
            sharedOverviewGame: { _ in "overview" },
            restGame: { _ in
                requestedREST = true
                return "rest"
            }
        )
        let active = try await activeResolver.resolve(
            gameID: 1,
            onRESTRequired: { restRequired = true }
        )
        XCTAssertEqual(active.game, "active")
        XCTAssertEqual(active.source, .activeGame)
        XCTAssertFalse(requestedREST)
        XCTAssertFalse(restRequired)

        let overviewResolver = GameOpenResolver<String>(
            activeGame: { _ in nil },
            sharedOverviewGame: { _ in "overview" },
            restGame: { _ in
                requestedREST = true
                return "rest"
            }
        )
        let overview = try await overviewResolver.resolve(gameID: 1)
        XCTAssertEqual(overview.game, "overview")
        XCTAssertEqual(overview.source, .sharedOverview)
        XCTAssertFalse(requestedREST)
    }

    @MainActor
    func testGameResolverUsesRESTAndAllowsFinishedValue() async throws {
        var restRequired = false
        let resolver = GameOpenResolver<String>(
            activeGame: { _ in nil },
            sharedOverviewGame: { _ in nil },
            restGame: { gameID in "finished-\(gameID)" }
        )

        let resolution = try await resolver.resolve(
            gameID: 42,
            onRESTRequired: { restRequired = true }
        )

        XCTAssertTrue(restRequired)
        XCTAssertEqual(resolution.game, "finished-42")
        XCTAssertEqual(resolution.source, .rest)
    }

    @MainActor
    func testGameResolverPropagatesRESTFailure() async {
        let resolver = GameOpenResolver<String>(
            activeGame: { _ in nil },
            sharedOverviewGame: { _ in nil },
            restGame: { _ in throw ResolverError.failed }
        )

        do {
            _ = try await resolver.resolve(gameID: 42)
            XCTFail("Expected REST failure")
        } catch {
            XCTAssertTrue(error is ResolverError)
        }
    }

    @MainActor
    func testGameResolverHonorsCancellation() async {
        let resolver = GameOpenResolver<String>(
            activeGame: { _ in nil },
            sharedOverviewGame: { _ in nil },
            restGame: { _ in
                try await Task.sleep(for: .seconds(5))
                return "late"
            }
        )
        let task = Task { try await resolver.resolve(gameID: 42) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testGameResolverCallbacksStayOnMainActor() async throws {
        var didRequireREST = false
        let resolver = GameOpenResolver<String>(
            activeGame: { _ in
                XCTAssertTrue(Thread.isMainThread)
                return nil
            },
            sharedOverviewGame: { _ in
                XCTAssertTrue(Thread.isMainThread)
                return nil
            },
            restGame: { _ in
                XCTAssertTrue(Thread.isMainThread)
                return "rest"
            }
        )

        let resolution = try await resolver.resolve(
            gameID: 42,
            onRESTRequired: {
                XCTAssertTrue(Thread.isMainThread)
                didRequireREST = true
            }
        )

        XCTAssertTrue(didRequireREST)
        XCTAssertEqual(resolution.game, "rest")
    }

    // MARK: - Held navigation under a moderator superchat cover

    /// One window's cover, which the test raises and lowers.
    private final class Cover {
        var isRaised: Bool
        init(isRaised: Bool = true) { self.isRaised = isRaised }
    }

    /// Counts what a publisher sends from now on.
    private final class Count {
        private(set) var value = 0
        private var observation: AnyCancellable?

        init<Sent: Publisher>(_ publisher: Sent) where Sent.Failure == Never {
            observation = publisher.sink { [unowned self] _ in self.value += 1 }
        }
    }

    /// A window whose navigation waits while its cover is raised, as the
    /// window's root sets it up. Windows of one store share its tap tickets.
    private func window(store: SuperchatStore, cover: Cover) -> NavigationService {
        let navigation = NavigationService()
        navigation.navigationHold = NavigationHold(store: store, isCovered: { cover.isRaised })
        return navigation
    }

    /// Each `handle(route:)` or `goToActiveGame` that runs resets tracked
    /// navigation once; `requestGameOpen` on its own resets nothing.
    private func countResets(of navigation: NavigationService) -> Count {
        Count(navigation.$navigationResetID.dropFirst())
    }

    private func route(_ rootView: RootView, game: Int? = nil) throws -> AppRoute {
        try XCTUnwrap(AppRoute(rootView: rootView, ogsGameID: game))
    }

    private func link(_ rootView: RootView, game: Int? = nil) throws -> URL {
        try XCTUnwrap(route(rootView, game: game).url())
    }

    private func makeGame(_ id: Int) -> Game {
        Game(width: 9, height: 9, blackName: "Black", whiteName: "White", gameId: .OGS(id))
    }

    @MainActor
    func testRoutesWaitWhileCovered() throws {
        let cover = Cover(isRaised: false)
        let navigation = window(store: SuperchatStore(preferences: nil), cover: cover)
        // What the window shows when the cover rises: an open in flight,
        // a Home game and tracked sheets.
        navigation.requestGameOpen(try route(.publicGames, game: 40))
        let pending = try XCTUnwrap(navigation.pendingGameOpen)
        let homeGame = makeGame(41)
        navigation.home.activeGame = homeGame
        navigation.home.showingNewGameView = true
        navigation.home.showingSettings = true
        let activity = ActivityRequest(source: .challengePill, style: .popover,
                                       anchor: CGRect(x: 10, y: 20, width: 44, height: 44))
        navigation.main.activity = activity
        navigation.main.accountSheet = .profile
        let resetID = navigation.navigationResetID
        cover.isRaised = true
        let publishes = Count(navigation.objectWillChange)

        XCTAssertTrue(navigation.handle(appURL: try link(.home, game: 42)), "A held link is still handled.")
        XCTAssertTrue(navigation.handle(appURL: try link(.settings)))
        XCTAssertFalse(navigation.handle(appURL: URL(string: "surround://home/0")!))
        navigation.handle(route: try route(.home, game: 43))
        navigation.requestGameOpen(try route(.home, game: 44), closesNewGame: true)
        navigation.goToActiveGame(game: makeGame(45))

        XCTAssertEqual(navigation.main.rootView, .publicGames)
        XCTAssertEqual(navigation.pendingGameOpen, pending)
        XCTAssertTrue(navigation.home.activeGame === homeGame)
        XCTAssertTrue(navigation.home.showingNewGameView)
        XCTAssertTrue(navigation.home.showingSettings)
        XCTAssertEqual(navigation.main.activity, activity, "The Activity list stays as it was.")
        XCTAssertEqual(navigation.main.accountSheet, .profile)
        XCTAssertEqual(navigation.navigationResetID, resetID)
        XCTAssertEqual(publishes.value, 0, "Holding publishes nothing, so nothing redraws.")
        XCTAssertEqual(navigation.heldTap?.route, try route(.settings), "The window keeps its latest valid tap.")
        guard case .activeGame(let held)? = navigation.heldInternalNavigation else {
            return XCTFail("The window keeps its latest internal open.")
        }
        XCTAssertEqual(held.ogsID, 45)
    }

    @MainActor
    func testOnlyTheAppsLatestHeldTapRuns() throws {
        let store = SuperchatStore(preferences: nil)
        let coverA = Cover(), coverB = Cover()
        let windowA = window(store: store, cover: coverA)
        let windowB = window(store: store, cover: coverB)
        windowA.main.rootView = .about
        let resetsA = countResets(of: windowA), resetsB = countResets(of: windowB)

        XCTAssertTrue(windowA.handle(appURL: try link(.home, game: 51)))
        XCTAssertTrue(windowB.handle(appURL: try link(.publicGames, game: 52)))
        XCTAssertEqual(resetsA.value + resetsB.value, 0)

        // Done lowers the cover in every window of the account.
        coverA.isRaised = false
        coverB.isRaised = false
        windowA.replayHeldNavigation()
        windowB.replayHeldNavigation()

        XCTAssertEqual(resetsA.value, 0, "Another window's later tap replaced this one.")
        XCTAssertEqual(windowA.main.rootView, .about)
        XCTAssertNil(windowA.pendingGameOpen)
        XCTAssertEqual(resetsB.value, 1)
        XCTAssertEqual(windowB.main.rootView, .publicGames)
        XCTAssertEqual(windowB.pendingGameOpen?.ogsGameID, 52)

        windowA.replayHeldNavigation()
        windowB.replayHeldNavigation()
        XCTAssertEqual(resetsA.value, 0, "A dropped tap never comes back.")
        XCTAssertEqual(resetsB.value, 1, "A replayed tap runs once.")

        // Each window replays from its own cover's lowering, in either order:
        // the earlier window replaying last still drops its tap.
        coverA.isRaised = true
        coverB.isRaised = true
        XCTAssertTrue(windowA.handle(appURL: try link(.home, game: 53)))
        XCTAssertTrue(windowB.handle(appURL: try link(.publicGames, game: 54)))
        coverA.isRaised = false
        coverB.isRaised = false
        windowB.replayHeldNavigation()
        windowA.replayHeldNavigation()
        XCTAssertEqual(resetsA.value, 0, "The latest tap's replay leaves the earlier one dropped.")
        XCTAssertEqual(windowA.main.rootView, .about)
        XCTAssertNil(windowA.pendingGameOpen)
        XCTAssertEqual(resetsB.value, 2)
        XCTAssertEqual(windowB.pendingGameOpen?.ogsGameID, 54)
    }

    @MainActor
    func testATapBeatsALaterInternalOpen() throws {
        let cover = Cover()
        let navigation = window(store: SuperchatStore(preferences: nil), cover: cover)
        let resets = countResets(of: navigation)
        XCTAssertTrue(navigation.handle(appURL: try link(.publicGames, game: 61)))
        // Home's automatch start, after the tap.
        navigation.handle(route: try route(.home, game: 62))

        cover.isRaised = false
        navigation.replayHeldNavigation()

        XCTAssertEqual(resets.value, 1, "Only the tap ran.")
        XCTAssertEqual(navigation.main.rootView, .publicGames)
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 61)
        navigation.replayHeldNavigation()
        XCTAssertEqual(resets.value, 1, "The internal open was dropped, not kept for later.")

        // A tap that another window's later tap replaced gives way to its
        // own window's internal open.
        let store = SuperchatStore(preferences: nil)
        let coverA = Cover(), coverB = Cover()
        let windowA = window(store: store, cover: coverA)
        let windowB = window(store: store, cover: coverB)
        windowA.main.rootView = .about
        XCTAssertTrue(windowA.handle(appURL: try link(.publicGames, game: 63)))
        windowA.handle(route: try route(.home, game: 64))
        XCTAssertTrue(windowB.handle(appURL: try link(.publicGames, game: 65)))
        coverA.isRaised = false
        coverB.isRaised = false
        windowA.replayHeldNavigation()
        XCTAssertEqual(windowA.main.rootView, .home)
        XCTAssertEqual(windowA.pendingGameOpen?.ogsGameID, 64)
    }

    @MainActor
    func testInternalOpensReplayWithoutATap() throws {
        let cover = Cover()
        let navigation = window(store: SuperchatStore(preferences: nil), cover: cover)
        let resets = countResets(of: navigation)
        navigation.main.rootView = .publicGames
        navigation.home.showingNewGameView = true

        // An open challenge's accept, still in flight when the cover rose.
        navigation.requestGameOpen(try route(.home, game: 71), closesNewGame: true)
        XCTAssertTrue(navigation.home.showingNewGameView, "New game stays open under the cover.")
        XCTAssertEqual(navigation.main.rootView, .publicGames)
        XCTAssertNil(navigation.pendingGameOpen)

        cover.isRaised = false
        navigation.replayHeldNavigation()
        XCTAssertFalse(navigation.home.showingNewGameView)
        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 71)
        XCTAssertEqual(resets.value, 0, "As when unheld, the accept resets nothing else.")

        // The live-game pill, after another internal open: only the
        // window's latest one runs.
        let game = makeGame(72)
        navigation.main.rootView = .settings
        cover.isRaised = true
        navigation.handle(route: try route(.publicGames, game: 73))
        navigation.goToActiveGame(game: game)
        XCTAssertNil(navigation.home.activeGame)
        XCTAssertEqual(navigation.main.rootView, .settings)

        cover.isRaised = false
        navigation.replayHeldNavigation()
        XCTAssertTrue(navigation.home.activeGame === game)
        XCTAssertEqual(navigation.main.rootView, .home)
        XCTAssertNil(navigation.pendingGameOpen)
        XCTAssertEqual(resets.value, 1, "Only the window's latest internal open ran.")
    }

    @MainActor
    func testAReplayWhileCoveredAgainKeepsTheHolds() throws {
        let cover = Cover()
        let navigation = window(store: SuperchatStore(preferences: nil), cover: cover)
        let resets = countResets(of: navigation)
        let tap = try route(.publicGames, game: 81)
        XCTAssertTrue(navigation.handle(appURL: try XCTUnwrap(tap.url())))
        navigation.handle(route: try route(.home, game: 82))

        // The cover rose again before the lowering's next main turn.
        navigation.replayHeldNavigation()
        XCTAssertEqual(resets.value, 0)
        XCTAssertNil(navigation.pendingGameOpen)
        XCTAssertEqual(navigation.heldTap?.route, tap)
        guard case .route(let internalOpen)? = navigation.heldInternalNavigation else {
            return XCTFail("The internal open stays held.")
        }
        XCTAssertEqual(internalOpen.ogsGameID, 82)

        cover.isRaised = false
        navigation.replayHeldNavigation()
        XCTAssertEqual(resets.value, 1)
        XCTAssertEqual(navigation.pendingGameOpen?.ogsGameID, 81, "The kept tap still wins.")
        XCTAssertNil(navigation.heldTap)
        XCTAssertNil(navigation.heldInternalNavigation)
    }

    @MainActor
    func testAClosedWindowDropsItsHolds() throws {
        let store = SuperchatStore(preferences: nil)
        let coverA = Cover(), coverB = Cover()
        let windowA = window(store: store, cover: coverA)
        let windowB = window(store: store, cover: coverB)
        windowA.main.rootView = .about
        windowB.main.rootView = .settings
        let resetsA = countResets(of: windowA), resetsB = countResets(of: windowB)
        XCTAssertTrue(windowA.handle(appURL: try link(.home, game: 101)))
        // Window B holds the app's latest tap and an automatch-style open.
        XCTAssertTrue(windowB.handle(appURL: try link(.publicGames, game: 102)))
        windowB.handle(route: try route(.home, game: 103))

        // B's views go while it is covered: the window closed, or the system
        // disconnected its scene.
        let publishes = Count(windowB.objectWillChange)
        windowB.dropHeldNavigation()
        XCTAssertNil(windowB.heldTap)
        XCTAssertNil(windowB.heldInternalNavigation)
        XCTAssertEqual(publishes.value, 0)

        // Done in A. B held the app's latest tap, so nothing replays it, and
        // A's earlier tap stays dropped.
        coverA.isRaised = false
        windowA.replayHeldNavigation()
        XCTAssertEqual(resetsA.value, 0)
        XCTAssertEqual(windowA.main.rootView, .about)
        XCTAssertNil(windowA.pendingGameOpen)

        // B comes back, and its cover's next lowering replays nothing.
        coverB.isRaised = false
        windowB.replayHeldNavigation()
        XCTAssertEqual(resetsB.value, 0)
        XCTAssertEqual(windowB.main.rootView, .settings)
        XCTAssertNil(windowB.pendingGameOpen)
    }

    @MainActor
    func testReplayWithoutAHoldDoesNothing() throws {
        // Without a hold every route runs at once, and a replay finds nothing.
        let unheld = NavigationService()
        let unheldResets = countResets(of: unheld)
        XCTAssertTrue(unheld.handle(appURL: try link(.home, game: 91)))
        XCTAssertEqual(unheldResets.value, 1)
        let pending = try XCTUnwrap(unheld.pendingGameOpen)
        XCTAssertEqual(pending.ogsGameID, 91)
        let unheldPublishes = Count(unheld.objectWillChange)
        unheld.replayHeldNavigation()
        XCTAssertEqual(unheldPublishes.value, 0)
        XCTAssertEqual(unheld.pendingGameOpen, pending)
        XCTAssertEqual(unheldResets.value, 1)

        // Nor does a hold whose cover is down hold anything.
        let navigation = window(store: SuperchatStore(preferences: nil), cover: Cover(isRaised: false))
        let resets = countResets(of: navigation)
        XCTAssertTrue(navigation.handle(appURL: try link(.publicGames, game: 92)))
        navigation.goToActiveGame(game: makeGame(93))
        XCTAssertEqual(resets.value, 2)
        XCTAssertNil(navigation.heldTap)
        XCTAssertNil(navigation.heldInternalNavigation)
        let publishes = Count(navigation.objectWillChange)
        navigation.replayHeldNavigation()
        XCTAssertEqual(publishes.value, 0)
        XCTAssertEqual(resets.value, 2)
    }
}
