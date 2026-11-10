//
//  ActivityPlaceRegistryTests.swift
//  SurroundTests
//
//  The window-level signal that hides Activity's bar on Game Detail and in
//  conversations, pushed or in Messages' side pane.
//

import Combine
import XCTest

final class ActivityPlaceRegistryTests: XCTestCase {
    private typealias Registry = ActivityPlaceRegistry
    private typealias Registration = ActivityPlaceRegistry.Registration
    private typealias Place = ActivityModel.Place

    /// The main-queue turns the registry asked for, run by hand.
    private final class Turns {
        private(set) var pending: [() -> Void] = []
        func schedule(_ work: @escaping () -> Void) { pending.append(work) }
        func run() {
            let due = pending
            pending.removeAll()
            due.forEach { $0() }
        }
    }

    private let turns = Turns()
    private lazy var registry = Registry(schedule: turns.schedule)
    private var subscriptions = Set<AnyCancellable>()

    private let ownGame = Place.game(id: 26_268_404, isOwnGame: true, isLive: true, isOver: false)

    private func screen(_ place: Place, in root: RootView?, onTop: Bool = true) -> Registration {
        Registration(place: place, root: root, isOnTop: onTop)
    }

    func testAGameDetailHidesItsOwnTabFromTheNextTurn() {
        registry.set(screen(ownGame, in: .home), for: UUID())
        XCTAssertFalse(registry.hidesActivity(in: .home),
                       "Never synchronously: onAppear can run inside setTabBarHidden's layout.")
        XCTAssertEqual(turns.pending.count, 1)

        turns.run()
        XCTAssertTrue(registry.hidesActivity(in: .home))
        XCTAssertEqual(registry.place(in: .home), ownGame)
        XCTAssertFalse(registry.hidesActivity(in: .publicGames))
        XCTAssertEqual(registry.place(in: .publicGames), .root(isMessagesTab: false))
        XCTAssertEqual(registry.place(in: .privateMessages), .root(isMessagesTab: true))
    }

    func testChangesWithinOneTurnSettleOnceAndOnlyWhenTheStateChanges() {
        var willChange = 0
        var sent = [Registry.State]()
        registry.objectWillChange.sink { _ in willChange += 1 }.store(in: &subscriptions)
        registry.stateDidChange.sink { sent.append($0) }.store(in: &subscriptions)

        let game = UUID()
        registry.set(screen(ownGame, in: .home), for: game)
        registry.remove(game)
        registry.set(screen(.conversation, in: .privateMessages), for: UUID())
        XCTAssertEqual(turns.pending.count, 1)
        turns.run()
        XCTAssertEqual(willChange, 1)
        XCTAssertEqual(sent, [Registry.State(places: [.privateMessages: .conversation])])

        let passing = UUID()
        registry.set(screen(ownGame, in: .home), for: passing)
        registry.remove(passing)
        turns.run()
        XCTAssertEqual(willChange, 1, "A screen that comes and goes within a turn settles nothing.")
        XCTAssertEqual(sent.count, 1)
    }

    func testRefreshingAnUnchangedScreenSchedulesNothing() {
        let owner = UUID()
        registry.set(screen(ownGame, in: .home), for: owner)
        turns.run()

        registry.set(screen(ownGame, in: .home), for: owner)
        XCTAssertTrue(turns.pending.isEmpty,
                      "Every onAppear and onDisappear refresh does this, so tab switches and re-parenting can't flicker.")
        XCTAssertTrue(registry.hidesActivity(in: .home))
    }

    func testACoveredScreenStopsHidingUntilItIsOnTopAgain() {
        let owner = UUID()
        registry.set(screen(ownGame, in: .home), for: owner)
        turns.run()

        registry.set(screen(ownGame, in: .home, onTop: false), for: owner)
        turns.run()
        XCTAssertFalse(registry.hidesActivity(in: .home), "Profile pushed over Game Detail.")

        registry.set(screen(ownGame, in: .home), for: owner)
        turns.run()
        XCTAssertTrue(registry.hidesActivity(in: .home), "Back from Profile.")
    }

    func testAPresentedStackNeverHidesATab() {
        registry.set(screen(ownGame, in: nil), for: UUID())
        registry.set(screen(.conversation, in: nil), for: UUID())
        turns.run()
        XCTAssertEqual(registry.state, Registry.State(),
                       "A sheet or popover covers the bar; hiding it would move a popover's anchor.")
        for root in RootView.allCases {
            XCTAssertFalse(registry.hidesActivity(in: root), "\(root)")
        }
    }

    func testAConversationInMessagesSidePaneHidesTheBarBesideTheTabBar() {
        let pane = UUID()
        registry.set(screen(.conversation, in: .privateMessages), for: pane)
        turns.run()
        XCTAssertTrue(registry.hidesActivity(in: .privateMessages))
        XCTAssertFalse(registry.hidesActivity(in: .home))

        registry.set(screen(.conversation, in: .privateMessages, onTop: false), for: pane)
        turns.run()
        XCTAssertFalse(registry.hidesActivity(in: .privateMessages), "Profile opened from the pane's header.")

        registry.set(screen(.conversation, in: .privateMessages), for: pane)
        turns.run()
        XCTAssertTrue(registry.hidesActivity(in: .privateMessages), "Back from Profile.")

        registry.remove(pane)
        turns.run()
        XCTAssertEqual(registry.place(in: .privateMessages), .root(isMessagesTab: true),
                       "The pane back to its placeholder.")
    }

    func testStackedGameDetailsReportTheOneOnTop() {
        let first = UUID()
        let second = UUID()
        let other = Place.game(id: 27_053_412, isOwnGame: false, isLive: true, isOver: false)
        registry.set(screen(ownGame, in: .home), for: first)
        turns.run()
        registry.set(screen(ownGame, in: .home, onTop: false), for: first)
        registry.set(screen(other, in: .home), for: second)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), other, "A → Profile → B: B is on top.")

        var sent = [Registry.State]()
        registry.stateDidChange.sink { sent.append($0) }.store(in: &subscriptions)
        // Back to A through the Back menu: the path covers B as its slide-out
        // begins and puts A on top again. B stays registered until its
        // lifetime release.
        registry.set(screen(other, in: .home, onTop: false), for: second)
        registry.set(screen(ownGame, in: .home), for: first)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), ownGame,
                       "Popping B reveals A: a later screen that is covered never wins.")

        registry.remove(second)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), ownGame, "B's release changes nothing.")
        XCTAssertEqual(sent, [Registry.State(places: [.home: ownGame])],
                       "No flash while B waits for its release.")
    }

    func testTwoScreensOnTopResolveToTheLaterAndAnUpdateKeepsItsOrder() {
        let earlier = UUID()
        let later = UUID()
        let laterGame = Place.game(id: 2, isOwnGame: true, isLive: false, isOver: false)
        registry.set(screen(ownGame, in: .home), for: earlier)
        registry.set(screen(laterGame, in: .home), for: later)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), laterGame)

        let switched = Place.game(id: 3, isOwnGame: true, isLive: true, isOver: false)
        registry.set(screen(switched, in: .home), for: earlier)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), laterGame, "An in-place game switch keeps the screen's order.")

        registry.remove(later)
        turns.run()
        XCTAssertEqual(registry.place(in: .home), switched)
    }

    func testARootPlaceOrAnUnknownOwnerChangesNothing() {
        registry.set(screen(.root(isMessagesTab: false), in: .home), for: UUID())
        registry.remove(UUID())
        XCTAssertTrue(turns.pending.isEmpty)

        let owner = UUID()
        registry.set(screen(ownGame, in: .home), for: owner)
        turns.run()
        registry.set(screen(.root(isMessagesTab: false), in: .home), for: owner)
        XCTAssertEqual(turns.pending.count, 1)
        turns.run()
        XCTAssertFalse(registry.hidesActivity(in: .home), "A .root place removes the registration.")

        registry.remove(owner)
        XCTAssertTrue(turns.pending.isEmpty, "A lifetime release after a removal schedules nothing.")
    }

    func testObserversSeeTheStoredStateAndTheirChangesWaitForTheNextTurn() {
        var stored = [Bool]()
        var reacted = false
        let pane = screen(.conversation, in: .privateMessages)
        registry.stateDidChange.sink { [registry] state in
            stored.append(registry.state == state)
            guard !reacted else { return }
            reacted = true
            registry.set(pane, for: UUID())
        }
        .store(in: &subscriptions)

        registry.set(screen(ownGame, in: .home), for: UUID())
        turns.run()
        XCTAssertEqual(stored, [true], "Unlike a @Published publisher, the state is stored before observers run.")
        XCTAssertFalse(registry.hidesActivity(in: .privateMessages), "An observer's change never settles re-entrantly.")
        XCTAssertEqual(turns.pending.count, 1)

        turns.run()
        XCTAssertTrue(registry.hidesActivity(in: .privateMessages))
        XCTAssertEqual(stored, [true, true])
    }

    func testReleasingAScreensLifetimeRemovesItsRegistration() {
        // A scene the system disconnects drops its views without onDisappear;
        // its NavigationService, and this registry, return with the window.
        let owner = UUID()
        registry.set(screen(ownGame, in: .home), for: owner)
        turns.run()
        var lifetime: ViewLifetime? = ViewLifetime()
        lifetime?.release = { [registry] in registry.remove(owner) }
        lifetime = nil

        let released = expectation(description: "The release ran on the main queue")
        DispatchQueue.main.async { released.fulfill() }
        wait(for: [released], timeout: 1)
        XCTAssertEqual(turns.pending.count, 1)
        turns.run()
        XCTAssertFalse(registry.hidesActivity(in: .home))
    }

    func testEachWindowKeepsItsOwnRegistry() {
        // Not instance(forSceneWithID:), which writes a static dictionary.
        XCTAssertTrue(NavigationService().activityPlaces !== NavigationService().activityPlaces)
    }

    func testAWindowHostTakesItsPlaceFromTheRegistry() {
        var input = ActivityModel.Input()
        input.liveGames = [ActivityModel.LiveGame(id: 1, isYourMove: true, isClockRunning: true, timeUntilTimeout: 300)]
        input.place = registry.place(in: .home)
        XCTAssertNotNil(ActivityModel.snapshot(input).lead, "Nothing registered: Home shows the bar.")

        registry.set(screen(ownGame, in: .home), for: UUID())
        turns.run()
        input.place = registry.place(in: .home)
        let snapshot = ActivityModel.snapshot(input)
        XCTAssertNil(snapshot.lead, "The host turns the accessory off.")
        XCTAssertEqual(snapshot.list.map(\.id), ["game-1"], "A Now section still lists what waits.")
    }
}
