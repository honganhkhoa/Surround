//
//  ActivityResultsTests.swift
//  SurroundTests
//
//  The per-window store behind Activity's actions: each request it sends,
//  what each reply leaves in the row, the ids it hides, Quick Match withdraws
//  settled by OGS's lifecycle events or a deadline, the lists' sessions, and
//  who speaks a result. A fake client answers through subjects the test
//  completes, a fake navigator records what the window was asked to do, and
//  a manual scheduler stands in for the main queue and the deadline.
//

import Alamofire
import Combine
import SwiftUI
import UIKit
import XCTest

final class ActivityResultsTests: XCTestCase {
    /// Runs work only when the test says so: `turn()` runs what `async`
    /// queued, as the main queue's next turn would, and `advance()` runs the
    /// deadlines that are due.
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

        /// The delays of the deadlines still to come.
        var pendingDelays: [TimeInterval] { work.values.map { $0.delay } }
        var pendingTurns: Int { turns.count }

        func async(_ block: @escaping () -> Void) { turns.append(block) }

        func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            nextID += 1
            let id = nextID
            work[id] = (delay, block)
            return Cancellation { [weak self] in self?.work.removeValue(forKey: id) }
        }

        func scheduleRepeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
            preconditionFailure("The store schedules one deadline at a time.")
        }

        /// Runs what was queued before this turn.
        func turn() {
            let due = turns
            turns = []
            due.forEach { $0() }
        }

        /// Runs every pending deadline. Work that an earlier one cancels
        /// doesn't run.
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

    /// Records each request and answers it when the test completes its reply.
    private final class FakeClient {
        private(set) var accepted = [Int]()
        private(set) var withdrawnOrDeclined = [Int]()
        private(set) var cancelledSearches = [String]()
        private(set) var left = [Int]()
        private(set) var started = [Int]()
        private(set) var acceptReplies = [PassthroughSubject<Int, Error>]()
        private(set) var withdrawReplies = [PassthroughSubject<Void, Error>]()
        private(set) var leaveReplies = [PassthroughSubject<Void, Error>]()
        private(set) var startReplies = [PassthroughSubject<Int, Error>]()
        /// What the socket's cancel answers.
        var socketSends = true
        let lifecycle = PassthroughSubject<OGSAutomatchLifecycleEvent, Never>()

        var client: ActivityResults.Client {
            ActivityResults.Client(
                accept: { [unowned self] challenge in
                    self.accepted.append(challenge.id)
                    return Self.reply(in: &self.acceptReplies)
                },
                withdrawOrDecline: { [unowned self] challenge in
                    self.withdrawnOrDeclined.append(challenge.id)
                    return Self.reply(in: &self.withdrawReplies)
                },
                cancelAutomatch: { [unowned self] entry in
                    self.cancelledSearches.append(entry.uuid)
                    return self.socketSends
                },
                leaveRengo: { [unowned self] challenge in
                    self.left.append(challenge.id)
                    return Self.reply(in: &self.leaveReplies)
                },
                startRengo: { [unowned self] challenge in
                    self.started.append(challenge.id)
                    return Self.reply(in: &self.startReplies)
                },
                automatchLifecycleEvents: lifecycle.eraseToAnyPublisher()
            )
        }

        private static func reply<Value>(
            in replies: inout [PassthroughSubject<Value, Error>]
        ) -> AnyPublisher<Value, Error> {
            let reply = PassthroughSubject<Value, Error>()
            replies.append(reply)
            return reply.eraseToAnyPublisher()
        }
    }

    private final class FakeNavigator: ActivityNavigating {
        enum Event: Equatable {
            case close
            case open(Int, closesNewGame: Bool)
            case announce(AppAnnouncement)
        }

        private(set) var events = [Event]()

        var announcements: [AppAnnouncement] {
            events.compactMap { event in
                if case .announce(let announcement) = event { return announcement }
                return nil
            }
        }

        var spoken: [String] { announcements.compactMap(\.speech) }

        func closeActivity() { events.append(.close) }
        func openGame(_ gameID: Int, closesNewGame: Bool) { events.append(.open(gameID, closesNewGame: closesNewGame)) }
        func announce(_ announcement: AppAnnouncement) { events.append(.announce(announcement)) }
    }

    private let clock = Clock()
    private let client = FakeClient()
    private let navigator = FakeNavigator()
    private let scheduler = ManualScheduler()
    private let session = UUID()
    private var store: ActivityResults!

    override func setUp() {
        super.setUp()
        store = makeStore()
        store.begin(session: session)
    }

    // MARK: Builders

    private func makeStore() -> ActivityResults {
        let clock = clock
        let store = ActivityResults(now: { clock.now })
        store.attach(client: client.client, navigator: navigator, scheduler: scheduler)
        return store
    }

    private func received(_ id: Int) -> OGSDirectChallenge {
        var challenge = OGSChallengeSampleData.sampleChallenge
        challenge.id = id
        return challenge
    }

    private func openChallenge(_ id: Int) -> OGSSeekgraphChallenge {
        var challenge = OGSChallengeSampleData.sampleOpenChallenge
        challenge.id = id
        return challenge
    }

    private func rengo(_ id: Int) -> OGSSeekgraphChallenge {
        var challenge = OGSChallengeSampleData.sampleRengoChallenge
        challenge.id = id
        return challenge
    }

    private func display(_ title: String) -> ActivityRowDisplay {
        ActivityRowDisplay(title: title, detail: "19×19 · Live", initial: "C")
    }

    private func accept(_ id: Int, live: Bool, in session: UUID? = nil) {
        store.accept(challenge: received(id), isLive: live, session: session ?? self.session,
                     itemID: "challenge-\(id)", display: display("CedarWave"), section: .challengesReceived, after: nil)
    }

    private func reject(_ id: Int) {
        store.reject(challenge: received(id), session: session, itemID: "challenge-\(id)",
                     display: display("CedarWave"), section: .challengesReceived, after: nil)
    }

    private func withdraw(_ id: Int, after: String? = nil, in session: UUID? = nil) {
        store.withdraw(challenge: openChallenge(id), session: session ?? self.session,
                       itemID: "waiting-open-\(id)", display: display("Open challenge"), section: .waiting,
                       after: after)
    }

    private func withdrawSearch(_ uuid: String) {
        store.withdraw(automatch: OGSAutomatchEntry(sizeSpeedOptions: [], uuid: uuid), session: session,
                       itemID: "waiting-quick-match-\(uuid)", display: display("Quick match"), section: .waiting,
                       after: nil)
    }

    private func leave(_ id: Int) {
        store.leave(rengo: rengo(id), session: session, itemID: "waiting-rengo-\(id)",
                    display: display("Rengo · Host"), section: .waiting, after: nil)
    }

    private func start(_ id: Int, live: Bool) {
        store.start(rengo: rengo(id), isLive: live, session: session, itemID: "waiting-rengo-\(id)",
                    display: display("Rengo · Host"), section: .waiting, after: nil)
    }

    private func succeed<Value>(_ reply: PassthroughSubject<Value, Error>?, with value: Value) {
        reply?.send(value)
        reply?.send(completion: .finished)
    }

    private func fail<Value>(_ reply: PassthroughSubject<Value, Error>?, _ error: Error = URLError(.notConnectedToInternet)) {
        reply?.send(completion: .failure(error))
    }

    private let notFound = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 404))

    private func lifecycle(_ kind: OGSAutomatchLifecycleEvent.Kind) {
        client.lifecycle.send(OGSAutomatchLifecycleEvent(kind: kind))
    }

    private func state(_ itemID: String) -> ActivityActionState? {
        store.entries[itemID]?.state
    }

    private func result(
        _ itemID: String, _ action: ActivityAction, _ speech: String
    ) -> AppAnnouncement {
        AppAnnouncement(.activityResult(itemID: itemID, action: action), audience: .anyWindow, speech: speech)
    }

    private func failure(
        _ itemID: String, _ action: ActivityAction, _ speech: String
    ) -> AppAnnouncement {
        AppAnnouncement(.activityFailure(itemID: itemID, action: action), audience: .anyWindow, speech: speech)
    }

    // MARK: Accept

    func testALiveAcceptClosesTheListThenOpensTheGame() {
        accept(7, live: true)
        XCTAssertEqual(client.accepted, [7])
        XCTAssertEqual(store.entries["challenge-7"], ActivityResults.Entry(
            action: .accept, state: .pending(since: 1_000), display: display("CedarWave"),
            section: .challengesReceived, after: nil
        ))

        succeed(client.acceptReplies.last, with: 901)
        XCTAssertEqual(navigator.events, [.close, .open(901, closesNewGame: true)])
        XCTAssertEqual(state("challenge-7"), .succeeded(.gameStarted(gameID: 901)))
        scheduler.turn()
        XCTAssertEqual(navigator.events, [.close, .open(901, closesNewGame: true)], "The game opening says it all.")
        XCTAssertEqual(store.hiddenIDs, ["challenge-7"], "No list offers the accepted challenge again.")
    }

    func testACorrespondenceAcceptStaysWithGameStarted() {
        accept(8, live: false)
        succeed(client.acceptReplies.last, with: 902)
        XCTAssertEqual(state("challenge-8"), .succeeded(.gameStarted(gameID: 902)))
        XCTAssertTrue(navigator.events.isEmpty, "The list stays, and the result waits a turn to speak.")
        scheduler.turn()
        XCTAssertEqual(navigator.events, [.announce(result("challenge-8", .accept, "Game started"))])
        XCTAssertEqual(store.hiddenIDs, ["challenge-8"],
                       "The list that accepted keeps the result row; a later list never offers it again.")
    }

    func testAFailedAcceptSaysSoAndRetryRepeatsIt() {
        accept(9, live: false)
        fail(client.acceptReplies.last)
        XCTAssertEqual(state("challenge-9"), .failed)
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [failure("challenge-9", .accept, "Couldn’t accept")])

        clock.now = 1_010
        store.retry(itemID: "challenge-9")
        XCTAssertEqual(client.accepted, [9, 9])
        XCTAssertEqual(state("challenge-9"), .pending(since: 1_010))
        fail(client.acceptReplies.last, notFound)
        XCTAssertEqual(state("challenge-9"), .failed, "A missing challenge has no game to open.")

        store.retry(itemID: "challenge-9")
        succeed(client.acceptReplies.last, with: 903)
        XCTAssertEqual(state("challenge-9"), .succeeded(.gameStarted(gameID: 903)))
        XCTAssertEqual(client.accepted, [9, 9, 9])
    }

    func testRetryOnlyRepeatsAFailure() {
        accept(10, live: false)
        store.retry(itemID: "challenge-10")
        store.retry(itemID: "challenge-11")
        XCTAssertEqual(client.accepted, [10], "Nothing to retry while pending, or for a row that never acted.")
        succeed(client.acceptReplies.last, with: 904)
        store.retry(itemID: "challenge-10")
        XCTAssertEqual(client.accepted, [10])
    }

    // MARK: Reject, withdraw and leave

    func testARejectHidesTheChallengeUntilTheSourceDropsIt() {
        reject(12)
        XCTAssertEqual(client.withdrawnOrDeclined, [12])
        succeed(client.withdrawReplies.last, with: ())
        XCTAssertEqual(state("challenge-12"), .succeeded(.rejected))
        XCTAssertEqual(store.hiddenIDs, ["challenge-12"])
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [result("challenge-12", .reject, "Rejected")])

        store.forget(hidden: "challenge-12")
        XCTAssertTrue(store.hiddenIDs.isEmpty)
        XCTAssertEqual(state("challenge-12"), .succeeded(.rejected), "The row keeps its result.")
    }

    func testANotFoundOnARejectRetryCountsAsSuccess() {
        reject(13)
        fail(client.withdrawReplies.last)
        XCTAssertEqual(state("challenge-13"), .failed)
        XCTAssertTrue(store.hiddenIDs.isEmpty)
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t reject"])

        store.retry(itemID: "challenge-13")
        fail(client.withdrawReplies.last, notFound)
        XCTAssertEqual(state("challenge-13"), .succeeded(.rejected), "The first try went through.")
        XCTAssertEqual(store.hiddenIDs, ["challenge-13"])
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t reject", "Rejected"])
    }

    func testAWithdrawnChallengeIsConfirmedByItsReplyAlone() {
        withdraw(14, after: "waiting-quick-match-a")
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "An HTTP withdraw has no 8 s limit.")
        XCTAssertEqual(store.entries["waiting-open-14"]?.after, "waiting-quick-match-a")
        succeed(client.withdrawReplies.last, with: ())
        XCTAssertEqual(state("waiting-open-14"), .succeeded(.withdrawn))
        XCTAssertEqual(store.hiddenIDs, ["waiting-open-14"])
        XCTAssertEqual(store.resolvedRows, [ActivityResolvedRow(
            id: "waiting-open-14", section: .waiting, after: "waiting-quick-match-a", display: display("Open challenge")
        )])
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [result("waiting-open-14", .withdraw, "Withdrawn")])
    }

    func testANotFoundIsAFailureUntilARetry() {
        withdraw(15)
        fail(client.withdrawReplies.last, notFound)
        XCTAssertEqual(state("waiting-open-15"), .failed, "On the first try, a missing challenge may have been accepted.")
        store.retry(itemID: "waiting-open-15")
        XCTAssertEqual(client.withdrawnOrDeclined, [15, 15])
        fail(client.withdrawReplies.last)
        XCTAssertEqual(state("waiting-open-15"), .failed)
        store.retry(itemID: "waiting-open-15")
        fail(client.withdrawReplies.last, notFound)
        XCTAssertEqual(state("waiting-open-15"), .succeeded(.withdrawn))
        XCTAssertEqual(store.hiddenIDs, ["waiting-open-15"])
    }

    func testLeavingRengoSaysLeftOrCouldntLeave() {
        leave(16)
        fail(client.leaveReplies.last)
        XCTAssertEqual(state("waiting-rengo-16"), .failed)
        scheduler.turn()
        store.retry(itemID: "waiting-rengo-16")
        XCTAssertEqual(client.left, [16, 16])
        succeed(client.leaveReplies.last, with: ())
        XCTAssertEqual(state("waiting-rengo-16"), .succeeded(.left))
        XCTAssertEqual(store.hiddenIDs, ["waiting-rengo-16"])
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [
            failure("waiting-rengo-16", .leave, "Couldn’t leave"),
            result("waiting-rengo-16", .leave, "Left"),
        ])
    }

    // MARK: Rengo Start

    func testStartingRengoFollowsTheAcceptRule() {
        start(17, live: true)
        succeed(client.startReplies.last, with: 917)
        XCTAssertEqual(navigator.events, [.close, .open(917, closesNewGame: true)])

        start(18, live: false)
        succeed(client.startReplies.last, with: 918)
        XCTAssertEqual(state("waiting-rengo-18"), .succeeded(.gameStarted(gameID: 918)))
        XCTAssertEqual(store.hiddenIDs, ["waiting-rengo-17", "waiting-rengo-18"],
                       "A started Rengo never shows its Start again.")

        start(19, live: false)
        fail(client.startReplies.last)
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Game started", "Couldn’t start"])
        store.retry(itemID: "waiting-rengo-19")
        succeed(client.startReplies.last, with: 919)
        XCTAssertEqual(state("waiting-rengo-19"), .succeeded(.gameStarted(gameID: 919)))
        XCTAssertEqual(client.started, [17, 18, 19, 19])
    }

    // MARK: Quick Match

    func testAQuickMatchWithdrawTheSocketCannotSendFailsAtOnce() {
        client.socketSends = false
        withdrawSearch("a")
        XCTAssertEqual(client.cancelledSearches, ["a"])
        XCTAssertEqual(state("waiting-quick-match-a"), .failed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [failure("waiting-quick-match-a", .withdraw, "Couldn’t withdraw")])
    }

    func testOGSCancellingTheSearchConfirmsTheWithdraw() {
        withdrawSearch("b")
        XCTAssertEqual(state("waiting-quick-match-b"), .pending(since: 1_000))
        XCTAssertEqual(scheduler.pendingDelays, [8])
        lifecycle(.cancelled(uuid: "other", removedCount: 1))
        lifecycle(.entry(uuid: "b"))
        XCTAssertEqual(state("waiting-quick-match-b"), .pending(since: 1_000))
        lifecycle(.cancelled(uuid: "b", removedCount: 1))
        XCTAssertEqual(state("waiting-quick-match-b"), .succeeded(.withdrawn))
        XCTAssertTrue(scheduler.pendingDelays.isEmpty, "The deadline goes with the last pending withdraw.")
        XCTAssertTrue(store.hiddenIDs.isEmpty, "The service drops the search itself.")
        scheduler.turn()
        XCTAssertEqual(navigator.announcements, [result("waiting-quick-match-b", .withdraw, "Withdrawn")])
    }

    func testAGameStartingFromTheSearchLeavesNoWithdrawResult() {
        withdrawSearch("c")
        lifecycle(.started(uuid: "c", gameID: 77, requestedLocally: false))
        XCTAssertNil(store.entries["waiting-quick-match-c"], "The game lists or opens instead.")
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.turn()
        XCTAssertTrue(navigator.events.isEmpty)
    }

    func testASearchOGSDidNotConfirmAfterAReconnectCouldntBeWithdrawn() {
        withdrawSearch("d")
        lifecycle(.notFoundAfterReconciliation(uuid: "d"))
        XCTAssertEqual(state("waiting-quick-match-d"), .failed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t withdraw"])
    }

    func testAnUnconfirmedQuickMatchWithdrawFailsAfterEightSeconds() {
        withdrawSearch("e")
        clock.now = 1_008
        scheduler.advance()
        XCTAssertEqual(state("waiting-quick-match-e"), .failed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t withdraw"])

        lifecycle(.cancelled(uuid: "e", removedCount: 1))
        XCTAssertEqual(state("waiting-quick-match-e"), .succeeded(.withdrawn), "A late cancel still confirms it.")
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t withdraw", "Withdrawn"])
    }

    func testRetryingAQuickMatchWithdrawWaitsAgain() {
        withdrawSearch("f")
        clock.now = 1_008
        scheduler.advance()
        clock.now = 1_020
        store.retry(itemID: "waiting-quick-match-f")
        XCTAssertEqual(client.cancelledSearches, ["f", "f"])
        XCTAssertEqual(state("waiting-quick-match-f"), .pending(since: 1_020))
        XCTAssertEqual(scheduler.pendingDelays, [8])
        clock.now = 1_027
        scheduler.advance()
        XCTAssertEqual(state("waiting-quick-match-f"), .pending(since: 1_020), "A wake-up before the deadline waits on.")
        XCTAssertEqual(scheduler.pendingDelays.map { ($0 * 10).rounded() / 10 }, [1])
        lifecycle(.cancelled(uuid: nil, removedCount: 1))
        XCTAssertEqual(state("waiting-quick-match-f"), .succeeded(.withdrawn), "OGS ended every search.")
    }

    // MARK: Sessions

    func testEachSessionKeepsItsOwnEntries() {
        withdraw(20)
        let popover = UUID()
        store.begin(session: popover)
        XCTAssertTrue(store.entries.isEmpty, "Only the live session's entries publish.")
        withdraw(21, in: popover)
        XCTAssertEqual(Set(store.entries.keys), ["waiting-open-21"])

        succeed(client.withdrawReplies.first, with: ())
        XCTAssertEqual(Set(store.entries.keys), ["waiting-open-21"])
        store.end(session: popover)
        XCTAssertEqual(store.entries["waiting-open-20"]?.state, .succeeded(.withdrawn),
                       "The earlier list is live again, with what came of its request meanwhile.")
        XCTAssertNil(store.entries["waiting-open-21"])

        store.end(session: session)
        XCTAssertTrue(store.entries.isEmpty)
        store.begin(session: session)
        XCTAssertTrue(store.entries.isEmpty, "Ending a session clears its entries.")
    }

    func testTheLiveSessionIsTheLatestBegunList() {
        XCTAssertEqual(store.liveSession, session)
        let popover = UUID()
        store.begin(session: popover)
        XCTAssertEqual(store.liveSession, popover, "A card pushed from the list on screen acts for it.")
        store.begin(session: session)
        XCTAssertEqual(store.liveSession, session, "Beginning again brings a list back to the top.")
        store.end(session: session)
        XCTAssertEqual(store.liveSession, popover)
        store.end(session: popover)
        XCTAssertNil(store.liveSession)
    }

    func testACompletionAfterItsSessionEndsRecordsNothingButStillSpeaks() {
        withdraw(22)
        store.end(session: session)
        succeed(client.withdrawReplies.last, with: ())
        store.begin(session: session)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.hiddenIDs, ["waiting-open-22"], "OGS confirmed it gone, so no list shows it again.")
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Withdrawn"])
    }

    func testALiveAcceptAfterTheListClosedStillOpensTheGame() {
        accept(23, live: true)
        store.end(session: session)
        succeed(client.acceptReplies.last, with: 923)
        XCTAssertEqual(navigator.events, [.close, .open(923, closesNewGame: true)], "It is the user's own action.")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testAQuickMatchWithdrawThatFailsAfterItsListClosedIsForgotten() {
        withdrawSearch("g")
        store.end(session: session)
        XCTAssertEqual(scheduler.pendingDelays, [8], "The withdraw still waits for OGS.")
        clock.now = 1_008
        scheduler.advance()
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t withdraw"])
        lifecycle(.cancelled(uuid: "g", removedCount: 1))
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Couldn’t withdraw"], "No row is left to correct.")
    }

    func testRequestsWithoutAClientFail() {
        let store = ActivityResults()
        store.begin(session: session)
        store.withdraw(challenge: openChallenge(24), session: session, itemID: "waiting-open-24",
                       display: display("Open challenge"), section: .waiting, after: nil)
        XCTAssertEqual(store.entries["waiting-open-24"]?.state, .failed)
    }

    func testResetForgetsEverything() {
        accept(25, live: true)
        reject(26)
        succeed(client.withdrawReplies.last, with: ())
        withdrawSearch("h")
        store.reset()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.hiddenIDs.isEmpty)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        succeed(client.acceptReplies.last, with: 925)
        lifecycle(.cancelled(uuid: "h", removedCount: 1))
        scheduler.turn()
        XCTAssertTrue(navigator.events.isEmpty, "Nothing from before the account change lands.")
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: Who speaks

    func testARowThatClaimsItsResultSilencesTheAnnouncement() {
        store.claim(itemID: "waiting-open-27")
        withdraw(27)
        succeed(client.withdrawReplies.last, with: ())
        XCTAssertEqual(scheduler.pendingTurns, 1, "The store decides a turn after the reply.")
        store.claim(itemID: "waiting-open-27")
        scheduler.turn()
        XCTAssertTrue(navigator.events.isEmpty, "The row moved VoiceOver focus to its result.")

        withdraw(28)
        succeed(client.withdrawReplies.last, with: ())
        scheduler.turn()
        store.claim(itemID: "waiting-open-28")
        XCTAssertEqual(navigator.spoken, ["Withdrawn"], "Unclaimed after a turn, the store speaks.")

        store.claim(itemID: "waiting-open-29")
        withdraw(29)
        succeed(client.withdrawReplies.last, with: ())
        scheduler.turn()
        XCTAssertEqual(navigator.spoken, ["Withdrawn", "Withdrawn"], "A claim before the result doesn't count.")
    }

    /// A row claims from its `entries` subscription, inside the publish that
    /// delivers its result, as the list and the pushed card do; never from its
    /// redraw, which can come after the store's turn.
    func testAClaimMadeAsTheResultPublishesSilencesTheStore() {
        var claimed = [String]()
        let store = store!
        let subscription = store.$entries.sink { next in
            // `entries` still holds the value before `next`, as in the views.
            for (itemID, entry) in next
            where !entry.state.isPending && store.entries[itemID]?.state != entry.state {
                claimed.append(itemID)
                store.claim(itemID: itemID)
            }
        }
        defer { subscription.cancel() }
        withdraw(30)
        reject(31)
        succeed(client.withdrawReplies.first, with: ())
        fail(client.withdrawReplies.last)
        XCTAssertEqual(claimed, ["waiting-open-30", "challenge-31"])
        XCTAssertEqual(scheduler.pendingTurns, 2, "The store decides a turn after each reply.")
        scheduler.turn()
        XCTAssertTrue(navigator.events.isEmpty, "Both rows moved VoiceOver focus to what came of them.")
    }

    /// The rows rely on SwiftUI running `onReceive` inside the publish that
    /// delivers a result, before any main-queue block queued then, such as
    /// the store's decision.
    @MainActor
    func testOnReceiveRunsInsideThePublishBeforeTheNextMainQueueTurn() throws {
        final class Events {
            var list = [String]()
        }
        let subject = PassthroughSubject<Int, Never>()
        let events = Events()
        // SwiftUI subscribes only a view in a window, and the test host has no
        // scene, so the view gets a window of its own. UIKit deprecates such a
        // window from iOS 26, which the Mac build already targets, so there the
        // test needs the app's scene.
        #if targetEnvironment(macCatalyst)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("The test host has no scene to show a window in.")
        }
        let window = UIWindow(windowScene: scene)
        #else
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #endif
        window.rootViewController = UIHostingController(
            rootView: Color.clear.frame(width: 10, height: 10)
                .onReceive(subject) { events.list.append("received \($0)") }
        )
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while !events.list.contains("received 0"), Date() < deadline {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            subject.send(0)
        }
        XCTAssertTrue(events.list.contains("received 0"), "SwiftUI subscribed the view.")
        events.list.removeAll()

        let decided = expectation(description: "the next main-queue turn")
        DispatchQueue.main.async {
            events.list.append("next turn")
            decided.fulfill()
        }
        subject.send(1)
        events.list.append("after the publish")
        wait(for: [decided], timeout: 5)
        XCTAssertEqual(events.list, ["received 1", "after the publish", "next turn"])
    }
}
