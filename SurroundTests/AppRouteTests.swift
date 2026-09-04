//
//  AppRouteTests.swift
//  SurroundTests
//

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
        navigation.main.modalLiveGame = Game(
            width: 9,
            height: 9,
            blackName: "Black",
            whiteName: "White",
            gameId: .OGS(99)
        )
        navigation.main.showWaitingGames = true
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
        XCTAssertNil(navigation.main.modalLiveGame)
        XCTAssertFalse(navigation.main.showWaitingGames)
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
}
