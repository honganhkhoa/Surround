//
//  SuperchatStoreTests.swift
//  SurroundTests
//
//  Moderator superchats once per app and per OGS account: what every
//  window's socket reports, what is saved for a relaunch, and the re-send
//  rule that lifts a cover whose end the app missed. A manual scheduler
//  stands in for the re-send deadline, a test clock for the times, and a
//  throwaway defaults suite for the saved state.
//

import Combine
import XCTest

final class SuperchatStoreTests: XCTestCase {
    /// Runs scheduled work only when the test advances it.
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

        /// The delays of the deadlines still to come.
        var pendingDelays: [TimeInterval] { work.values.map { $0.delay } }

        func async(_ block: @escaping () -> Void) { block() }

        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            nextID += 1
            let id = nextID
            work[id] = (delay, block)
            return Cancellation { [weak self] in self?.work.removeValue(forKey: id) }
        }

        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            preconditionFailure("The store schedules one deadline at a time.")
        }

        /// Runs every pending deadline, as if the re-send window passed.
        /// Work that an earlier one cancels doesn't run.
        func advance() {
            for id in work.keys.sorted() {
                guard let due = work.removeValue(forKey: id) else { continue }
                due.block()
            }
        }
    }

    private final class Clock {
        var now: TimeInterval = 1_000
    }

    private let player = 1
    private let otherPlayer = 2
    private let moderator = 101
    private let secondModerator = 102
    /// Two windows' sockets.
    private let connectionA = UUID()
    private let connectionB = UUID()

    private let clock = Clock()
    private let scheduler = ManualScheduler()
    private var observations = Set<AnyCancellable>()
    /// Every account whose cover went away without Done, from every store the test made.
    private var lifted = [Int]()

    override func tearDown() {
        observations.removeAll()
        super.tearDown()
    }

    // MARK: Builders

    private func makeStore(preferences: UserDefaults? = nil) -> SuperchatStore {
        let clock = clock
        let store = SuperchatStore(preferences: preferences, scheduler: scheduler, now: { clock.now })
        store.coverLiftedWithoutDone
            .sink { [weak self] accountID in self?.lifted.append(accountID) }
            .store(in: &observations)
        return store
    }

    private func makePreferences() -> UserDefaults {
        let suite = "com.honganhkhoa.Surround.SuperchatStoreTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// What a relaunch would find.
    private func saved(_ preferences: UserDefaults) -> [Int: [SuperchatModerator]] {
        preferences[.superchatModeratorsByOGSAccountID] ?? [:]
    }

    /// Counts the store's publishes from now on.
    private func countPublishes(of store: SuperchatStore) -> () -> Int {
        var count = 0
        store.objectWillChange.sink { count += 1 }.store(in: &observations)
        return { count }
    }

    /// `private-superchat` with `enable: true`, as a window passes it on.
    private func start(
        _ store: SuperchatStore, _ moderatorID: Int, username: String? = "moderator", account: Int? = nil
    ) {
        store.receive(enable: true, moderatorID: moderatorID, username: username, accountID: account ?? player)
    }

    /// The same event with `enable: false`.
    private func end(_ store: SuperchatStore, _ moderatorID: Int, account: Int? = nil) {
        store.receive(enable: false, moderatorID: moderatorID, username: nil, accountID: account ?? player)
    }

    // MARK: Starts, copies and ends

    func testAStartCoversOnlyItsAccount() {
        let store = makeStore()
        start(store, moderator, username: "  moderator\n")
        XCTAssertEqual(store.covers, [player: SuperchatCover(moderators: [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000),
        ])], "It starts now, under the event's name.")
        XCTAssertEqual(store.covers[player]?.isOn, true)
        XCTAssertEqual(store.covers[player]?.awaitsDone, false)
        XCTAssertTrue(store.endings.isEmpty)

        clock.now = 1_005
        start(store, moderator, account: otherPlayer)
        XCTAssertEqual(store.covers[otherPlayer]?.moderators.map(\.startedAt), [1_005],
                       "Another player's superchat is a cover of its own.")
        XCTAssertEqual(store.covers[player]?.moderators.map(\.startedAt), [1_000],
                       "It leaves this account's cover as it was.")
        XCTAssertEqual(store.covers.count, 2)
    }

    func testCopiesAndResendsChangeNothing() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        let started = store.covers
        let publishes = countPublishes(of: store)

        clock.now = 1_030
        start(store, moderator)
        start(store, moderator, username: nil)
        start(store, moderator, username: " ")
        XCTAssertEqual(publishes(), 0, "A copy from another window, or OGS's re-send, publishes nothing.")
        XCTAssertEqual(store.covers, started, "The first start's time and the name stay.")

        start(store, moderator, username: "renamed")
        XCTAssertEqual(publishes(), 1, "Only a new username changes the cover.")
        XCTAssertEqual(store.covers[player]?.moderators, [
            SuperchatModerator(id: moderator, username: "renamed", startedAt: 1_000),
        ])
        XCTAssertEqual(saved(preferences)[player]?.map(\.username), ["renamed"])
    }

    func testAnEndWaitsForDone() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        XCTAssertEqual(saved(preferences)[player]?.map(\.id), [moderator])

        clock.now = 1_060
        end(store, moderator)
        let cover = store.covers[player]
        XCTAssertEqual(cover?.moderators, [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000, endedAt: 1_060),
        ], "The cover stays, ended.")
        XCTAssertEqual(cover?.isOn, false)
        XCTAssertEqual(cover?.awaitsDone, true, "The end card and Done.")
        XCTAssertEqual(store.endings, [player: [moderator: SuperchatEnding(at: 1_060, wasMissed: false)]])
        XCTAssertTrue(saved(preferences).isEmpty, "Only superchats still on are saved.")
        XCTAssertTrue(lifted.isEmpty)
    }

    func testDoneClearsTheAccountOnlyOnceNothingIsOn() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        start(store, secondModerator, username: "second")
        start(store, moderator, account: otherPlayer)
        end(store, moderator)
        store.done(accountID: player)
        XCTAssertEqual(store.covers[player]?.isOn, true, "Done waits while a superchat is still on.")

        // A wait whose deadline runs, then the last live end.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertEqual(scheduler.pendingDelays.count, 1)
        end(store, secondModerator)
        XCTAssertEqual(store.covers[player]?.awaitsDone, true)

        store.done(accountID: player)
        XCTAssertNil(store.covers[player], "The account's cover goes, for every window.")
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "Done cancels the account's waits.")
        XCTAssertEqual(store.covers[otherPlayer]?.isOn, true, "Another account's cover stays.")
        XCTAssertEqual(store.endings[player]?.keys.sorted(), [moderator, secondModerator],
                       "Messages keeps the ended lines this session.")
        XCTAssertEqual(saved(preferences).keys.sorted(), [otherPlayer])
        XCTAssertTrue(lifted.isEmpty, "A cover that goes by Done isn't reported as lifted without it.")

        store.done(accountID: player)
        store.done(accountID: otherPlayer)
        XCTAssertNil(store.covers[player])
        XCTAssertEqual(store.covers[otherPlayer]?.isOn, true, "Done does nothing while that account's superchat is on.")
    }

    func testUnknownAndRepeatedEndsAreIgnored() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        let publishes = countPublishes(of: store)
        end(store, moderator)
        XCTAssertTrue(store.covers.isEmpty, "An end the app never saw start covers nothing.")
        XCTAssertTrue(store.endings.isEmpty)
        XCTAssertEqual(publishes(), 0)

        start(store, moderator)
        clock.now = 1_010
        end(store, moderator)
        let covers = store.covers
        let endings = store.endings
        let publishesAfterTheEnd = publishes()

        clock.now = 1_020
        end(store, moderator)
        end(store, secondModerator)
        end(store, moderator, account: otherPlayer)
        XCTAssertEqual(publishes(), publishesAfterTheEnd, "Copies of the end, and unknown ends, publish nothing.")
        XCTAssertEqual(store.covers, covers)
        XCTAssertEqual(store.endings, endings)
        XCTAssertEqual(store.endings[player]?[moderator]?.at, 1_010, "The first end's time stays.")
        XCTAssertTrue(saved(preferences).isEmpty)
    }

    func testANewStartAfterAnEndIsNewestAgain() {
        let store = makeStore()
        start(store, moderator)
        clock.now = 1_010
        start(store, secondModerator, username: "second")
        clock.now = 1_020
        end(store, moderator)
        XCTAssertEqual(store.endings[player]?[moderator], SuperchatEnding(at: 1_020, wasMissed: false))

        clock.now = 1_030
        start(store, moderator)
        XCTAssertEqual(store.covers[player]?.moderators, [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_030),
            SuperchatModerator(id: secondModerator, username: "second", startedAt: 1_010),
        ], "It is on again and first, in place of the ended one.")
        XCTAssertNil(store.endings[player]?[moderator], "Messages drops the earlier ended line.")
    }

    func testSeveralModeratorsNewestFirst() {
        let store = makeStore()
        start(store, moderator)
        clock.now = 1_010
        start(store, secondModerator, username: "second")
        XCTAssertEqual(store.covers[player]?.moderators.map(\.id), [secondModerator, moderator])

        clock.now = 1_020
        start(store, moderator)
        XCTAssertEqual(store.covers[player]?.moderators.map(\.id), [secondModerator, moderator],
                       "A re-send never reorders.")

        end(store, secondModerator)
        XCTAssertEqual(store.covers[player]?.isOn, true, "One ends, and the cover stays on.")
        XCTAssertEqual(store.covers[player]?.awaitsDone, false, "No Done while another is on.")
        XCTAssertEqual(store.covers[player]?.moderators.map(\.id), [secondModerator, moderator])
        XCTAssertEqual(store.covers[player]?.moderators.map(\.isOn), [false, true])

        end(store, moderator)
        XCTAssertEqual(store.covers[player]?.isOn, false)
        XCTAssertEqual(store.covers[player]?.awaitsDone, true, "Both ended: the end card and Done.")
        XCTAssertEqual(store.endings[player]?.keys.sorted(), [moderator, secondModerator])
    }

    // MARK: Saved per account

    func testSuperchatsStillOnAreSavedPerAccountAndRestored() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        clock.now = 1_010
        start(store, secondModerator, username: "second")
        start(store, moderator, account: otherPlayer)
        clock.now = 1_020
        end(store, secondModerator)
        end(store, moderator, account: otherPlayer)
        XCTAssertEqual(saved(preferences), [player: [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000),
        ]], "Only superchats still on are saved, per account.")

        // A relaunch: a new store on the same defaults.
        let relaunched = makeStore(preferences: preferences)
        XCTAssertEqual(relaunched.covers, [player: SuperchatCover(moderators: [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000),
        ])], "The ended cover that waited for Done isn't restored.")
        XCTAssertTrue(relaunched.endings.isEmpty, "Endings last for the session.")

        // Saved superchats come back on, newest first, and nothing else does.
        preferences[.superchatModeratorsByOGSAccountID] = [
            player: [
                SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000),
                SuperchatModerator(id: secondModerator, username: "second", startedAt: 1_010),
                SuperchatModerator(id: 103, username: "ended", startedAt: 1_020, endedAt: 1_030),
            ],
            0: [SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000)],
            otherPlayer: [],
        ]
        XCTAssertEqual(makeStore(preferences: preferences).covers, [player: SuperchatCover(moderators: [
            SuperchatModerator(id: secondModerator, username: "second", startedAt: 1_010),
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_000),
        ])])
    }

    // MARK: The re-send window

    func testAResendInTimeKeepsTheCover() {
        let store = makeStore()
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "The deadline waits for OGS's answer.")
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertEqual(SuperchatStore.resendWindow, 10)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])

        start(store, moderator)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "The re-send closes the wait.")
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.moderators.map(\.isOn), [true])
        XCTAssertTrue(store.endings.isEmpty)
        XCTAssertTrue(lifted.isEmpty)
    }

    func testNoResendLiftsWithoutDone() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])
        clock.now = 1_010
        scheduler.advance()
        XCTAssertNil(store.covers[player], "Every superchat ended unseen: no end card to dismiss.")
        XCTAssertEqual(lifted, [player])
        XCTAssertEqual(store.endings, [player: [moderator: SuperchatEnding(at: 1_010, wasMissed: true)]])
        XCTAssertTrue(saved(preferences).isEmpty)
        XCTAssertTrue(makeStore(preferences: preferences).covers.isEmpty, "A relaunch opens uncovered.")
    }

    func testAResendBeforeTheAnswerCounts() {
        let store = makeStore()
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        start(store, moderator)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "The re-send came first, so no deadline starts.")

        // Through the fallback too: the re-send comes before the timeout and the ping.
        store.connectionAuthenticating(connectionB, accountID: player)
        start(store, moderator)
        store.connectionAnswered(connectionB, accountID: player, .unanswered)
        store.connectionAnsweredPing(connectionB)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true)
        XCTAssertTrue(lifted.isEmpty)
    }

    func testAnUnansweredConnectionStartsAtItsPing() {
        let store = makeStore()
        start(store, moderator)

        // A ping before the callback timeout: the deadline starts at the timeout.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnsweredPing(connectionA)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "A ping alone starts nothing while OGS may still answer.")
        store.connectionAnswered(connectionA, accountID: player, .unanswered)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow])

        // No ping before the timeout: the first one after it starts the deadline.
        store.connectionAuthenticating(connectionB, accountID: player)
        store.connectionAnswered(connectionB, accountID: player, .unanswered)
        XCTAssertEqual(scheduler.pendingDelays.count, 1, "B waits for its ping.")
        store.connectionAnsweredPing(connectionB)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow, SuperchatStore.resendWindow],
                       "B's first ping starts its deadline.")
        store.connectionAnsweredPing(connectionB)
        XCTAssertEqual(scheduler.pendingDelays.count, 2, "Later pings start nothing more.")

        clock.now = 1_040
        scheduler.advance()
        XCTAssertNil(store.covers[player], "A missed end lifts without OGS's answer too.")
        XCTAssertEqual(lifted, [player])
        XCTAssertEqual(store.endings[player]?[moderator], SuperchatEnding(at: 1_040, wasMissed: true))
    }

    func testADeafConnectionNeverLifts() {
        let store = makeStore()
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .unanswered)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "No answer and no ping: no deadline.")
        clock.now = 2_000
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true, "A connection that answers no ping never lifts.")
        XCTAssertTrue(store.endings.isEmpty)
        XCTAssertTrue(lifted.isEmpty)
    }

    func testARejectedAnswerNeverLifts() {
        let store = makeStore()
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnsweredPing(connectionA)
        store.connectionAnswered(connectionA, accountID: player, .rejected)
        store.connectionAnsweredPing(connectionA)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "OGS isn't listening as this account: the wait closes.")
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true)
        XCTAssertTrue(lifted.isEmpty)

        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow],
                       "The connection's next authentication waits again.")
    }

    func testAClosedConnectionCancelsItsWait() {
        let store = makeStore()
        start(store, moderator)

        // Closed while its deadline runs.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertEqual(scheduler.pendingDelays.count, 1)
        store.connectionEnded(connectionA)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        // Closed before OGS answered: a late answer or ping starts nothing.
        store.connectionAuthenticating(connectionB, accountID: player)
        store.connectionEnded(connectionB)
        store.connectionAnswered(connectionB, accountID: player, .confirmed)
        store.connectionAnsweredPing(connectionB)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        // A new authentication replaces the connection's earlier wait.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        store.connectionAuthenticating(connectionA, accountID: player)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "The new wait waits for its own answer.")
        store.connectionEnded(connectionA)

        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true, "Offline, the cover stays.")
        XCTAssertTrue(lifted.isEmpty)
    }

    func testWaitsOutlastTheBackgroundAndStartAtAPingAfterTheReturn() {
        let store = makeStore()
        start(store, moderator)
        // A's deadline runs; OGS hasn't answered B yet.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        store.connectionAuthenticating(connectionB, accountID: player)
        XCTAssertEqual(scheduler.pendingDelays.count, 1)

        store.enterBackground()
        XCTAssertTrue(store.isInBackground)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "Every deadline is cancelled.")

        // In the background a socket can still reconnect, be answered and ping.
        let reconnected = UUID()
        store.connectionAuthenticating(reconnected, accountID: player)
        store.connectionAnswered(reconnected, accountID: player, .confirmed)
        for connection in [connectionA, connectionB, reconnected] {
            store.connectionAnsweredPing(connection)
        }
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "No deadline starts in the background.")
        clock.now = 1_060
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true, "Nothing lifts.")
        XCTAssertTrue(lifted.isEmpty)

        // Back in the foreground, sockets that survived don't authenticate
        // again: each answered wait starts at its first ping after the return.
        store.enterForeground()
        XCTAssertFalse(store.isInBackground)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "Nothing starts before a ping.")
        store.connectionAnsweredPing(connectionA)
        store.connectionAnsweredPing(reconnected)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow, SuperchatStore.resendWindow],
                       "A's wait from before the background, and the one opened in it, start.")
        store.connectionAnsweredPing(connectionB)
        XCTAssertEqual(scheduler.pendingDelays.count, 2, "B still waits for OGS's answer.")
        store.connectionAnswered(connectionB, accountID: player, .confirmed)
        XCTAssertEqual(scheduler.pendingDelays.count, 3)

        clock.now = 1_080
        scheduler.advance()
        XCTAssertNil(store.covers[player], "No re-send came: the cover lifts by itself.")
        XCTAssertEqual(lifted, [player])
        XCTAssertEqual(store.endings, [player: [moderator: SuperchatEnding(at: 1_080, wasMissed: true)]])
    }

    func testAResendAfterTheReturnBeforeThePingKeepsTheCover() {
        let store = makeStore()
        start(store, moderator)
        start(store, secondModerator, username: "second")
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        store.enterBackground()
        store.enterForeground()

        // The socket held the first moderator's re-send while the app was
        // suspended, so it comes before the socket's next pong.
        start(store, moderator)
        store.connectionAnsweredPing(connectionA)
        XCTAssertEqual(scheduler.pendingDelays, [SuperchatStore.resendWindow], "The second is still awaited.")

        clock.now = 1_020
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.isOn, true, "The re-sent superchat keeps the cover.")
        XCTAssertEqual(store.covers[player]?.moderators.map(\.id), [secondModerator, moderator])
        XCTAssertEqual(store.covers[player]?.moderators.map(\.isOn), [false, true])
        XCTAssertEqual(store.endings, [player: [secondModerator: SuperchatEnding(at: 1_020, wasMissed: true)]],
                       "Only the superchat OGS didn't re-send ended.")
        XCTAssertTrue(lifted.isEmpty)
    }

    func testOnlyTheMissedModeratorEnds() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        clock.now = 1_010
        start(store, secondModerator, username: "second")
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        start(store, secondModerator, username: "second")
        XCTAssertEqual(scheduler.pendingDelays.count, 1, "The first is still awaited.")

        clock.now = 1_020
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.moderators, [
            SuperchatModerator(id: secondModerator, username: "second", startedAt: 1_010),
            SuperchatModerator(
                id: moderator, username: "moderator", startedAt: 1_000, endedAt: 1_020, endWasMissed: true
            ),
        ], "Only the superchat OGS didn't re-send ends.")
        XCTAssertEqual(store.endings, [player: [moderator: SuperchatEnding(at: 1_020, wasMissed: true)]])
        XCTAssertTrue(lifted.isEmpty, "The other is still on, so the cover stays.")
        XCTAssertEqual(saved(preferences)[player]?.map(\.id), [secondModerator])

        // The other missed too: nothing waits for Done, so the cover lifts.
        store.connectionAuthenticating(connectionB, accountID: player)
        store.connectionAnswered(connectionB, accountID: player, .confirmed)
        clock.now = 1_040
        scheduler.advance()
        XCTAssertNil(store.covers[player])
        XCTAssertEqual(lifted, [player])
        XCTAssertEqual(store.endings[player]?[secondModerator], SuperchatEnding(at: 1_040, wasMissed: true))
    }

    func testAMissedEndBesideALiveEndKeepsTheEndCard() {
        let store = makeStore()
        start(store, moderator)
        start(store, secondModerator, username: "second")
        // The wait opens for both; the first then ends live before the deadline.
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        clock.now = 1_010
        end(store, moderator)
        clock.now = 1_020
        scheduler.advance()

        let cover = store.covers[player]
        XCTAssertEqual(cover?.isOn, false)
        XCTAssertEqual(cover?.awaitsDone, true, "The live end's card and Done stay.")
        XCTAssertEqual(store.endings, [player: [
            moderator: SuperchatEnding(at: 1_010, wasMissed: false),
            secondModerator: SuperchatEnding(at: 1_020, wasMissed: true),
        ]])
        XCTAssertTrue(lifted.isEmpty)
    }

    func testAResendOnAnyConnectionCountsForEveryWaitOfTheAccount() {
        let store = makeStore()
        start(store, moderator)
        start(store, secondModerator, username: "second")
        for connection in [connectionA, connectionB] {
            store.connectionAuthenticating(connection, accountID: player)
            store.connectionAnswered(connection, accountID: player, .confirmed)
        }
        XCTAssertEqual(scheduler.pendingDelays.count, 2)

        // One window's socket hears the first moderator again, another window's the second.
        start(store, moderator)
        XCTAssertEqual(scheduler.pendingDelays.count, 2, "Both waits still await the second.")
        start(store, secondModerator, username: "second")
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "Each re-send counted for both waits.")
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.moderators.map(\.isOn), [true, true])
        XCTAssertTrue(lifted.isEmpty)
    }

    func testAnotherAccountsConnectionCannotLiftACover() {
        let store = makeStore()
        start(store, moderator)

        // A window whose socket speaks for another account, which has no cover.
        store.connectionAuthenticating(connectionB, accountID: otherPlayer)
        store.connectionAnswered(connectionB, accountID: otherPlayer, .confirmed)
        store.connectionAnsweredPing(connectionB)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "It opens no wait for this account's cover.")

        // The same moderator superchats that account too: its wait is that account's alone.
        start(store, moderator, account: otherPlayer)
        store.connectionAuthenticating(connectionB, accountID: otherPlayer)
        store.connectionAnswered(connectionB, accountID: player, .confirmed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "An answer for another account starts nothing.")
        store.connectionAnswered(connectionB, accountID: otherPlayer, .confirmed)
        start(store, moderator)
        XCTAssertEqual(scheduler.pendingDelays.count, 1, "This account's copy doesn't count for another's wait.")

        clock.now = 1_010
        scheduler.advance()
        XCTAssertEqual(lifted, [otherPlayer])
        XCTAssertNil(store.covers[otherPlayer])
        XCTAssertEqual(store.covers[player]?.isOn, true, "This account's cover stays.")
        XCTAssertNil(store.endings[player])
    }

    func testNoWaitWithoutASuperchatOn() {
        let store = makeStore()
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "No cover: nothing to wait for.")

        // A superchat that starts after the authentication was heard live.
        start(store, moderator)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        store.connectionAnsweredPing(connectionA)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        // A cover whose superchat ended live, waiting for Done.
        end(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.advance()
        XCTAssertEqual(store.covers[player]?.awaitsDone, true, "Only Done takes the end card away.")
        XCTAssertTrue(lifted.isEmpty)
    }

    func testALateResendCoversAgain() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        start(store, moderator)
        store.connectionAuthenticating(connectionA, accountID: player)
        store.connectionAnswered(connectionA, accountID: player, .confirmed)
        clock.now = 1_010
        scheduler.advance()
        XCTAssertNil(store.covers[player])
        XCTAssertEqual(store.endings[player]?[moderator]?.wasMissed, true)

        clock.now = 1_015
        start(store, moderator)
        XCTAssertEqual(store.covers[player], SuperchatCover(moderators: [
            SuperchatModerator(id: moderator, username: "moderator", startedAt: 1_015),
        ]), "A re-send after the lift is a new start: the cover rises again.")
        XCTAssertNil(store.endings[player]?[moderator], "Messages drops the ended line it showed meanwhile.")
        XCTAssertEqual(saved(preferences)[player]?.map(\.id), [moderator])
        XCTAssertEqual(lifted, [player])
    }

    // MARK: Held navigation

    func testOnlyTheLatestHoldTicketIsLatest() {
        let store = makeStore()
        var windowACovered = true
        let windowA = NavigationHold(store: store, isCovered: { windowACovered })
        let windowB = NavigationHold(store: store, isCovered: { false })
        XCTAssertTrue(windowA.isCovered)
        XCTAssertFalse(windowB.isCovered)
        windowACovered = false
        XCTAssertFalse(windowA.isCovered, "It asks its window each time.")

        let first = windowA.nextTicket()
        XCTAssertTrue(windowA.isLatest(first))
        let second = windowB.nextTicket()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(windowA.isLatest(first), "A later tap in any window replaces it, app-wide.")
        XCTAssertTrue(windowA.isLatest(second))
        XCTAssertTrue(windowB.isLatest(second))
        XCTAssertTrue(store.isLatestHold(second))

        let third = store.nextHoldTicket()
        XCTAssertFalse(windowB.isLatest(second))
        XCTAssertTrue(windowB.isLatest(third))
    }

    // MARK: The store's own guard

    func testTheModeratorsOwnIDNeverCovers() {
        let preferences = makePreferences()
        let store = makeStore(preferences: preferences)
        let publishes = countPublishes(of: store)
        store.receive(enable: true, moderatorID: player, username: "player", accountID: player)
        store.receive(enable: true, moderatorID: 0, username: "moderator", accountID: player)
        store.receive(enable: true, moderatorID: -moderator, username: "moderator", accountID: player)
        store.receive(enable: true, moderatorID: moderator, username: "moderator", accountID: 0)
        store.receive(enable: true, moderatorID: moderator, username: "moderator", accountID: -player)
        XCTAssertTrue(store.covers.isEmpty, "The moderator's own echo, and ids that name nobody, cover nothing.")
        XCTAssertEqual(publishes(), 0)
        XCTAssertTrue(saved(preferences).isEmpty)

        start(store, moderator)
        store.receive(enable: false, moderatorID: player, username: nil, accountID: player)
        XCTAssertEqual(store.covers[player]?.isOn, true, "The echo of an end changes nothing either.")
        XCTAssertTrue(store.endings.isEmpty)
    }

    // MARK: What a window's cover shows

    func testPresentationShowsDoneInAStaleWindow() throws {
        let store = makeStore()
        start(store, moderator)
        let live = try XCTUnwrap(store.covers[player])
        // The window kept another account, while the stored sign-in is `player`.
        let staleWhileOn = try XCTUnwrap(SuperchatCoverPresentation(
            cover: live, selectedModeratorID: nil, windowUserID: otherPlayer, accountID: player))
        XCTAssertTrue(staleWhileOn.isStale)
        XCTAssertEqual(staleWhileOn.endCard, .none)
        XCTAssertFalse(staleWhileOn.showsReplyField, "A stale window has no field.")
        XCTAssertFalse(staleWhileOn.showsLiveGames, "Its games belong to the other account.")

        end(store, moderator)
        let ended = try XCTUnwrap(store.covers[player])
        let stale = try XCTUnwrap(SuperchatCoverPresentation(
            cover: ended, selectedModeratorID: nil, windowUserID: otherPlayer, accountID: player))
        XCTAssertEqual(stale.endCard, .done, "A live end heard by any window gives the stale one Done.")
        XCTAssertFalse(stale.showsReplyField)
        XCTAssertFalse(stale.showsLiveGames)
        XCTAssertEqual(stale.moderator.id, moderator)

        let unknown = try XCTUnwrap(SuperchatCoverPresentation(
            cover: ended, selectedModeratorID: nil, windowUserID: nil, accountID: player))
        XCTAssertTrue(unknown.isStale, "A window with no user of its own is stale too.")

        let fresh = try XCTUnwrap(SuperchatCoverPresentation(
            cover: ended, selectedModeratorID: nil, windowUserID: player, accountID: player))
        XCTAssertFalse(fresh.isStale)
        XCTAssertEqual(fresh.endCard, .done)
        XCTAssertTrue(fresh.showsReplyField, "The last reply can still be sent.")
        XCTAssertTrue(fresh.showsLiveGames)
    }

    func testPresentationEndCardStates() throws {
        let store = makeStore()
        func shown(selecting id: Int? = nil) throws -> SuperchatCoverPresentation {
            try XCTUnwrap(SuperchatCoverPresentation(
                cover: XCTUnwrap(store.covers[player]), selectedModeratorID: id,
                windowUserID: player, accountID: player))
        }
        start(store, moderator)
        XCTAssertEqual(try shown().endCard, .none)
        XCTAssertFalse(try shown().showsChips, "One moderator needs no chips.")
        XCTAssertEqual(try shown().moderator.id, moderator)

        clock.now = 1_010
        start(store, secondModerator, username: "second")
        XCTAssertTrue(try shown().showsChips)
        XCTAssertEqual(try shown().moderator.id, secondModerator, "The newest is selected.")
        XCTAssertEqual(try shown(selecting: moderator).moderator.id, moderator)
        XCTAssertEqual(try shown(selecting: 999).moderator.id, secondModerator,
                       "A choice that isn't on the cover falls back to the newest.")

        end(store, moderator)
        XCTAssertEqual(try shown(selecting: moderator).endCard, .endedLine,
                       "Its line alone while another is still on: no Done.")
        XCTAssertEqual(try shown().endCard, .none, "The one still on shows no card.")

        end(store, secondModerator)
        XCTAssertEqual(try shown().endCard, .done)
        XCTAssertEqual(try shown(selecting: moderator).endCard, .done, "Done once nothing is on, whichever is selected.")
        XCTAssertTrue(try shown().showsChips)

        XCTAssertNil(SuperchatCoverPresentation(
            cover: SuperchatCover(moderators: []), selectedModeratorID: nil, windowUserID: player, accountID: player),
            "The store never keeps an empty cover, and nothing shows one.")
    }

    func testOnlyRegularHeightFreshWindowsFocusTheReply() {
        XCTAssertTrue(SuperchatCoverPresentation.focusesReply(isCompactHeight: false, isStale: false))
        XCTAssertFalse(SuperchatCoverPresentation.focusesReply(isCompactHeight: true, isStale: false),
                       "In compact height the keyboard would leave no room.")
        XCTAssertFalse(SuperchatCoverPresentation.focusesReply(isCompactHeight: false, isStale: true),
                       "A stale window has no field.")
        XCTAssertFalse(SuperchatCoverPresentation.focusesReply(isCompactHeight: true, isStale: true))
    }
}
