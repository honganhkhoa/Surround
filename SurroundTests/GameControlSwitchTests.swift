//
//  GameControlSwitchTests.swift
//  SurroundTests
//
//  How a Game Detail switches to another game: in place only on Home's route
//  with the picker allowed, and through Home everywhere else.
//

import XCTest

final class GameControlSwitchTests: XCTestCase {
    private func game(_ id: Int) -> Game {
        Game(width: 19, height: 19, blackName: "Black \(id)", whiteName: "White \(id)", gameId: .OGS(id))
    }

    private func request() -> ActivityRequest {
        ActivityRequest(source: .gameControl, style: .popover,
                        place: .game(id: 41, isOwnGame: true, isLive: true, isOver: false))
    }

    func testOnlyHomesRouteWithThePickerSwitchesInPlace() {
        let cases: [(route: StackRoute?, allowsCarousel: Bool, expected: GameControlSwitch)] = [
            (.homeGame, true, .inPlace),
            (.homeGame, false, .throughHome),       // Home's finished games
            (nil, true, .inPlace),                  // a stack's root: compatibility scenes and previews
            (nil, false, .throughHome),
            (.publicGame, true, .throughHome),      // its flag keeps the default
            (.publicGame, false, .throughHome),
            (.historyGame, false, .throughHome),
            (.historyGame, true, .throughHome),
            (.game(41), false, .throughHome),       // a profile's game, the iPad Profile sheet's too
            (.game(41), true, .throughHome),
            (.gameHistory, true, .throughHome),
        ]
        for (route, allowsCarousel, expected) in cases {
            let rule = GameControlSwitch(route: route, allowsActiveGamesCarousel: allowsCarousel)
            let name = "\(route.map { "\($0)" } ?? "root") \(allowsCarousel)"
            XCTAssertEqual(rule, expected, name)
            XCTAssertEqual(rule.allowsPicker, expected == .inPlace, "The picker follows the same rule: \(name)")
        }
    }

    @MainActor
    func testInPlaceClearsTheRequestAndAPendingOpenAndResetsNoStack() throws {
        let navigation = NavigationService()
        let current = game(41), next = game(42), watched = game(40)
        navigation.home.activeGame = current
        navigation.publicGames.activeGame = watched
        navigation.requestGameOpen(try XCTUnwrap(AppRoute(rootView: .home, ogsGameID: 99)))
        navigation.main.activity = request()
        let reset = navigation.navigationResetID
        var shown = [Int?]()

        GameControlSwitch(route: .homeGame, allowsActiveGamesCarousel: true).perform(next, navigation: navigation) {
            shown.append($0.ogsID)
            navigation.home.activeGame = $0
        }

        XCTAssertEqual(shown, [42], "The route's own game changes, once.")
        XCTAssertTrue(navigation.home.activeGame === next)
        XCTAssertNil(navigation.main.activity, "A switch closes the window's Activity request.")
        XCTAssertNil(navigation.pendingGameOpen, "An older open can't replace the switch.")
        XCTAssertEqual(navigation.navigationResetID, reset, "No stack resets.")
        XCTAssertTrue(navigation.publicGames.activeGame === watched, "Other tabs keep their games.")
        XCTAssertEqual(navigation.main.rootView, .home)
    }

    /// Next (N) follows the rule too: on Public games or a history game it
    /// would otherwise file the user's own game under that route, and on a
    /// profile's game do nothing.
    @MainActor
    func testEveryOtherRouteOpensTheGameOnHomesRoute() throws {
        for route: StackRoute in [.publicGame, .historyGame, .game(41)] {
            let navigation = NavigationService()
            let next = game(42)
            navigation.main.rootView = .publicGames
            navigation.publicGames.activeGame = game(41)
            navigation.main.accountSheet = .profile
            navigation.main.activity = request()
            let reset = navigation.navigationResetID
            var shown = 0

            GameControlSwitch(route: route, allowsActiveGamesCarousel: true).perform(next, navigation: navigation) { _ in
                shown += 1
            }

            XCTAssertEqual(shown, 0, "The route's own game stays: \(route)")
            XCTAssertEqual(navigation.main.rootView, .home, "\(route)")
            XCTAssertTrue(navigation.home.activeGame === next, "\(route)")
            XCTAssertTrue(navigation.home.activeGameShowsCarousel, "Home's route has the picker: \(route)")
            XCTAssertNil(navigation.publicGames.activeGame, "Nothing is filed under Public games: \(route)")
            XCTAssertNil(navigation.main.accountSheet, "The account sheet closes: \(route)")
            XCTAssertNil(navigation.main.activity, "\(route)")
            XCTAssertNotEqual(navigation.navigationResetID, reset, "Every stack resets: \(route)")
        }
    }
}
