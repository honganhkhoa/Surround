//
//  GameControlSwitchTests.swift
//  SurroundTests
//
//  How a Game Detail switches to another game: in place only on Home's route
//  with the picker allowed, and through Home everywhere else. And when the
//  in-game control's popover is open, with the window's request it made,
//  and when the native item that presents it may be made again.
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

/// The control's popover: each item presents only at the placement it
/// opened from, and the window's request goes with the popover.
final class GameControlPopoverTests: XCTestCase {
    private let place = ActivityModel.Place.game(id: 41, isOwnGame: true, isLive: false, isOver: false)

    @MainActor
    func testOpeningMakesTheWindowsRequestForThisGame() throws {
        let navigation = NavigationService()
        var popover = GameControlPopover()
        XCTAssertFalse(popover.isOpen)
        popover.open(at: .bottomBar, place: place, navigation: navigation)
        let request = try XCTUnwrap(navigation.main.activity)
        XCTAssertEqual(request.source, .gameControl)
        XCTAssertEqual(request.style, .popover)
        XCTAssertEqual(request.place, place, "The list reads the game's own place.")
        XCTAssertEqual(popover.sessionID, request.sessionID)
        XCTAssertEqual(popover.listSessionID, request.sessionID, "The list's session is the request's.")
        XCTAssertTrue(popover.isPresented(at: .bottomBar))
        XCTAssertFalse(popover.isPresented(at: .topBarBeforeModes))
    }

    /// A turn moves the slot from the bottom bar to the top bar. The old
    /// item's popover goes without SwiftUI saying so, so Game Detail closes
    /// it and clears its request. The new item starts closed, and the next
    /// hold or VoiceOver action opens the popover there.
    @MainActor
    func testMovingToAnotherBarClosesThePopoverAndClearsItsRequest() throws {
        let navigation = NavigationService()
        var popover = GameControlPopover()
        popover.open(at: .bottomBar, place: place, navigation: navigation)
        popover.close(navigation: navigation)
        XCTAssertNil(navigation.main.activity, "The request goes with the popover.")
        XCTAssertFalse(popover.isOpen)
        XCTAssertFalse(popover.isPresented(at: .topBarBeforeModes), "The new item starts closed.")

        popover.open(at: .topBarBeforeModes, place: place, navigation: navigation)
        XCTAssertTrue(popover.isPresented(at: .topBarBeforeModes), "It opens again from the new item.")
        let reopened = try XCTUnwrap(navigation.main.activity?.sessionID)
        popover.itemClosed(at: .bottomBar, navigation: navigation)
        XCTAssertTrue(popover.isPresented(at: .topBarBeforeModes), "A late report from the old item closes nothing.")
        XCTAssertEqual(navigation.main.activity?.sessionID, reopened)

        popover.itemClosed(at: .topBarBeforeModes, navigation: navigation)
        XCTAssertFalse(popover.isOpen, "A tap outside closes it.")
        XCTAssertNil(navigation.main.activity)
        XCTAssertEqual(popover.listSessionID, reopened, "The list keeps its session while the popover goes.")
    }

    /// Closing clears only this popover's request, and a request that goes or
    /// changes closes the popover.
    @MainActor
    func testOnlyItsOwnRequestIsCleared() {
        let navigation = NavigationService()
        var popover = GameControlPopover()
        popover.open(at: .topBarAfterModes, place: place, navigation: navigation)
        // Another Game Detail's control, as the iPad Profile sheet's over a tab's game.
        let other = ActivityRequest(source: .gameControl, style: .popover, place: place)
        navigation.main.activity = other
        popover.windowRequestChanged(to: other.sessionID)
        XCTAssertFalse(popover.isOpen, "One list per window: the other replaces this one.")
        popover.close(navigation: navigation)
        XCTAssertEqual(navigation.main.activity?.sessionID, other.sessionID, "The other's request stays.")

        popover.open(at: .rail, place: place, navigation: navigation)
        popover.windowRequestChanged(to: popover.sessionID)
        XCTAssertTrue(popover.isOpen, "Its own request changes nothing.")
        // The window's navigation resets, or the list's own action closes it.
        navigation.main.activity = nil
        popover.windowRequestChanged(to: nil)
        XCTAssertFalse(popover.isOpen)
        XCTAssertNil(popover.sessionID)
    }

    /// The rail's and the Mac's native item is made again when its badge
    /// changes while its popover is closed, so iOS 27 can't keep a stale
    /// badge. The item that presented the popover stays until the popover
    /// has left the screen, even when a live Accept or a switch closes it in
    /// the same pass that changes the badge.
    func testTheNativeItemStaysUntilItsPopoverHasLeftTheScreen() {
        typealias Badge = GameControlNativeItem.Badge
        let noBadge = Badge.none
        var identity = GameControlNativeIdentity()
        identity.follow(.count(1), isPopoverOpen: false)
        XCTAssertEqual(identity.id(showing: .count(1), isPopoverOpen: false), .count(1))
        XCTAssertEqual(identity.id(showing: .count(2), isPopoverOpen: false), .count(2),
                       "Closed, a new badge makes the item again.")
        identity.follow(.count(2), isPopoverOpen: false)

        XCTAssertEqual(identity.id(showing: .count(2), isPopoverOpen: true), .count(2), "Opening keeps the item.")
        identity.popoverAppeared()
        identity.follow(.count(3), isPopoverOpen: true)
        XCTAssertEqual(identity.id(showing: .count(3), isPopoverOpen: true), .count(2),
                       "While it is open the badge changes, the item doesn't.")

        // A live Accept closes the popover in code, and its card goes.
        identity.follow(noBadge, isPopoverOpen: false)
        XCTAssertTrue(identity.holds(isPopoverOpen: false))
        XCTAssertEqual(identity.id(showing: noBadge, isPopoverOpen: false), .count(2),
                       "Closed in code but still on screen: the item that can dismiss it stays.")

        identity.popoverDisappeared()
        XCTAssertFalse(identity.holds(isPopoverOpen: false))
        XCTAssertEqual(identity.id(showing: noBadge, isPopoverOpen: false), noBadge,
                       "Once the popover has gone, the item takes the badge it shows.")
        identity.follow(noBadge, isPopoverOpen: false)
        XCTAssertEqual(identity.badge, noBadge)

        // A tap outside: the binding turns false first, the content disappears after.
        identity.popoverAppeared()
        identity.follow(.dot, isPopoverOpen: false)
        XCTAssertEqual(identity.id(showing: .dot, isPopoverOpen: false), noBadge)
        identity.popoverDisappeared()
        XCTAssertEqual(identity.id(showing: .dot, isPopoverOpen: false), .dot)
        XCTAssertNil(identity.id(showing: nil, isPopoverOpen: false), "No item: the slot hides.")
    }
}
