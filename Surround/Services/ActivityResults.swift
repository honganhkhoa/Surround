//
//  ActivityResults.swift
//  Surround
//
//  What the user does in a window's Activity list, and what came of it. The
//  store sends every request the list and its pushed cards start, so a
//  request outlives the row, the push and the list that started it. Results
//  are kept by the list's session and the row's item id, so a row shows its
//  result until its list closes. One per window, held by NavigationService.
//  Main thread by convention, like its owner; it is not actor-isolated,
//  because NavigationService makes it in a property initializer.
//

import Alamofire
import Combine
import Foundation

/// What the results store asks of its window.
protocol ActivityNavigating: AnyObject {
    /// Closes the window's Activity list.
    func closeActivity()
    /// Opens a game. `closesNewGame` closes New game with it.
    func openGame(_ gameID: Int, closesNewGame: Bool)
    /// Speaks once per app, on behalf of this window.
    func announce(_ announcement: AppAnnouncement)
}

final class ActivityResults: ObservableObject {
    /// The requests, over one window's OGSService. Tests pass fakes.
    struct Client {
        var accept: (any OGSSubmittedChallenge) -> AnyPublisher<Int, Error>
        var withdrawOrDecline: (any OGSSubmittedChallenge) -> AnyPublisher<Void, Error>
        /// False when the socket couldn't send the cancel.
        var cancelAutomatch: (OGSAutomatchEntry) -> Bool
        var leaveRengo: (OGSSeekgraphChallenge) -> AnyPublisher<Void, Error>
        var startRengo: (OGSSeekgraphChallenge) -> AnyPublisher<Int, Error>
        var automatchLifecycleEvents: AnyPublisher<OGSAutomatchLifecycleEvent, Never>

        static func live(_ ogs: OGSService) -> Client {
            Client(
                accept: { ogs.acceptChallenge(challenge: $0) },
                withdrawOrDecline: { ogs.withdrawOrDeclineChallenge(challenge: $0) },
                cancelAutomatch: { ogs.cancelAutomatch(entry: $0) },
                leaveRengo: { ogs.leaveRengoChallenge(challenge: $0) },
                startRengo: { ogs.startRengoGame(challenge: $0) },
                automatchLifecycleEvents: ogs.automatchLifecycleEvents.eraseToAnyPublisher()
            )
        }
    }

    /// A row's latest action in the live session.
    struct Entry: Equatable {
        var action: ActivityAction
        var state: ActivityActionState
        /// The row as it was when the action started.
        var display: ActivityRowDisplay
        var section: ActivitySection
        /// The id before it in its section when the action started.
        var after: String?
    }

    /// The live session's entries, by item id.
    @Published private(set) var entries: [String: Entry] = [:]
    /// Items OGS confirmed gone that the service may still list until its
    /// next overview or seek graph update. The list leaves them out, and
    /// calls `forget(hidden:)` once its source has dropped them.
    @Published private(set) var hiddenIDs: Set<String> = []

    /// The latest begun session, whose entries publish: the list on screen,
    /// which a card it pushed acts for.
    var liveSession: UUID? { sessionOrder.last }

    /// The live session's entries as rows to merge into the list, by id.
    var resolvedRows: [ActivityResolvedRow] {
        entries
            .map { ActivityResolvedRow(id: $0.key, section: $0.value.section, after: $0.value.after, display: $0.value.display) }
            .sorted { $0.id < $1.id }
    }

    private enum Request {
        case accept(any OGSSubmittedChallenge, isLive: Bool)
        case reject(any OGSSubmittedChallenge)
        case withdraw(any OGSSubmittedChallenge)
        case withdrawAutomatch(OGSAutomatchEntry)
        case leave(OGSSeekgraphChallenge)
        case start(OGSSeekgraphChallenge, isLive: Bool)

        var action: ActivityAction {
            switch self {
            case .accept: .accept
            case .reject: .reject
            case .withdraw, .withdrawAutomatch: .withdraw
            case .leave: .leave
            case .start: .start
            }
        }

        /// OGS's 2xx reply confirms the item is gone, but the service lists
        /// it until its next update. An accepted challenge or a started Rengo
        /// is gone too: the list that acted keeps its result row, and a list
        /// opened before the update never offers it again. A Quick Match
        /// search leaves the service with OGS's cancel.
        var hidesOnSuccess: Bool {
            switch self {
            case .accept, .reject, .withdraw, .leave, .start: true
            case .withdrawAutomatch: false
            }
        }
    }

    /// One try at a request.
    private struct Attempt {
        let id: Int
        let session: UUID
        let itemID: String
        let request: Request
        let isRetry: Bool
    }

    /// A row's latest attempt in one session.
    private struct Record {
        var entry: Entry
        var request: Request
        var attemptID: Int
    }

    /// A Quick Match withdraw that OGS hasn't confirmed.
    private struct QuickMatchWithdraw {
        let attempt: Attempt
        var withdrawal: ActivityQuickMatchWithdrawal.Entry
    }

    private enum Resolution {
        case succeeded(ActivityOutcome)
        /// A live game: the list closes and the game opens.
        case opensGame(Int)
        case failed
        /// A game started from the search being withdrawn: no outcome.
        case removed
    }

    /// The request never answered.
    private struct NoReply: Error {}

    private let now: () -> TimeInterval
    private var client: Client?
    private weak var navigator: ActivityNavigating?
    private var scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared
    private var lifecycleSubscription: AnyCancellable?

    /// The begun sessions, oldest first. The last is live.
    private var sessionOrder: [UUID] = []
    private var records: [UUID: [String: Record]] = [:]
    private var lastAttemptID = 0
    private var replies: [Int: AnyCancellable] = [:]
    /// By attempt. A failed one stays while its session lives, for a late
    /// cancel from OGS.
    private var quickMatchWithdraws: [Int: QuickMatchWithdraw] = [:]
    private var deadline: Cancellable?
    /// Items whose announcement waits for the next turn, and how many wait.
    private var awaitingAnnouncement: [String: Int] = [:]
    private var claimedIDs: Set<String> = []
    /// Moves on with `reset()`, so nothing from before it lands.
    private var generation = 0

    /// - Parameter now: Seconds on the scheduler's clock. The default stops
    ///   while the device sleeps, as `DispatchTime` does.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    deinit {
        deadline?.cancel()
    }

    /// Connects the store to its window: the window's requests, its
    /// navigation and the queue its deadlines and announcements run on.
    func attach(
        client: Client,
        navigator: ActivityNavigating,
        scheduler: OGSWebsocketScheduling = OGSMainQueueWebsocketScheduler.shared
    ) {
        self.client = client
        self.navigator = navigator
        self.scheduler = scheduler
        lifecycleSubscription = client.automatchLifecycleEvents
            .sink { [weak self] event in self?.receive(event.kind) }
    }

    // MARK: Sessions

    /// A list appeared. The latest begun session is the live one, whose
    /// entries publish; an earlier one keeps its entries until it ends.
    func begin(session: UUID) {
        sessionOrder.removeAll { $0 == session }
        sessionOrder.append(session)
        if records[session] == nil {
            records[session] = [:]
        }
        publishLiveSession()
    }

    /// A list closed or went away: its entries go. Its requests still
    /// finish, record nothing and still speak, and a live game still opens.
    func end(session: UUID) {
        sessionOrder.removeAll { $0 == session }
        records[session] = nil
        // Its failed Quick Match withdraws have no row left to correct.
        quickMatchWithdraws = quickMatchWithdraws.filter {
            $0.value.attempt.session != session || $0.value.withdrawal.state.isPending
        }
        publishLiveSession()
    }

    /// Forgets every entry, hidden id and request, for an account change.
    /// Replies to the old account's requests change nothing.
    func reset() {
        generation += 1
        replies.values.forEach { $0.cancel() }
        replies = [:]
        quickMatchWithdraws = [:]
        deadline?.cancel()
        deadline = nil
        records = records.mapValues { _ in [:] }
        awaitingAnnouncement = [:]
        claimedIDs = []
        if !hiddenIDs.isEmpty {
            hiddenIDs = []
        }
        publishLiveSession()
    }

    // MARK: Requests

    /// Accepts a challenge sent to the user. A live game closes the list and
    /// opens; a correspondence game stays as the row's result.
    func accept(
        challenge: any OGSSubmittedChallenge, isLive: Bool, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.accept(challenge, isLive: isLive), session: session, itemID: itemID,
             display: display, section: section, after: after)
    }

    func reject(
        challenge: any OGSSubmittedChallenge, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.reject(challenge), session: session, itemID: itemID, display: display, section: section, after: after)
    }

    /// Withdraws the user's own open or sent challenge, or cancels a Rengo
    /// challenge the user hosts.
    func withdraw(
        challenge: any OGSSubmittedChallenge, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.withdraw(challenge), session: session, itemID: itemID, display: display, section: section, after: after)
    }

    /// Withdraws a Quick Match search. OGS confirms it over the socket
    /// within `ActivityQuickMatchWithdrawal.confirmationLimit`, or it fails.
    func withdraw(
        automatch entry: OGSAutomatchEntry, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.withdrawAutomatch(entry), session: session, itemID: itemID,
             display: display, section: section, after: after)
    }

    /// Leaves a Rengo challenge the user joined.
    func leave(
        rengo challenge: OGSSeekgraphChallenge, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.leave(challenge), session: session, itemID: itemID, display: display, section: section, after: after)
    }

    /// Starts a Rengo game the user hosts, by the same rule as Accept.
    func start(
        rengo challenge: OGSSeekgraphChallenge, isLive: Bool, session: UUID, itemID: String,
        display: ActivityRowDisplay, section: ActivitySection, after: String?
    ) {
        send(.start(challenge, isLive: isLive), session: session, itemID: itemID,
             display: display, section: section, after: after)
    }

    /// Repeats the live session's failed action on `itemID`.
    func retry(itemID: String) {
        guard let session = sessionOrder.last, let record = records[session]?[itemID],
              record.entry.state == .failed else {
            return
        }
        let entry = record.entry
        send(record.request, session: session, itemID: itemID, display: entry.display,
             section: entry.section, after: entry.after, isRetry: true)
    }

    /// The list's source no longer lists `id`, so it needs no hiding.
    func forget(hidden id: String) {
        guard hiddenIDs.contains(id) else { return }
        hiddenIDs.remove(id)
    }

    /// The row moved VoiceOver focus to its result, so the store doesn't
    /// announce it too. It counts from the moment the result publishes in
    /// `entries` until the store decides, a main-queue turn later; a row
    /// claims from its `entries` subscription, in the publish itself.
    func claim(itemID: String) {
        guard awaitingAnnouncement[itemID] != nil else { return }
        claimedIDs.insert(itemID)
    }

    // MARK: Sending

    private func send(
        _ request: Request, session: UUID, itemID: String, display: ActivityRowDisplay,
        section: ActivitySection, after: String?, isRetry: Bool = false
    ) {
        lastAttemptID += 1
        let attempt = Attempt(id: lastAttemptID, session: session, itemID: itemID, request: request, isRetry: isRetry)
        let time = now()
        if records[session] != nil {
            records[session]?[itemID] = Record(
                entry: Entry(action: request.action, state: .pending(since: time), display: display,
                             section: section, after: after),
                request: request,
                attemptID: attempt.id
            )
            // A Retry takes over from the failed withdraw it repeats.
            quickMatchWithdraws = quickMatchWithdraws.filter {
                $0.value.attempt.session != session || $0.value.attempt.itemID != itemID
            }
            publish(session)
        }
        guard let client else {
            resolve(attempt, .failed)
            return
        }
        switch request {
        case .accept(let challenge, let isLive):
            subscribe(to: client.accept(challenge), for: attempt) { [weak self] result in
                self?.resolve(attempt, Self.resolution(result, isLive: isLive))
            }
        case .reject(let challenge):
            subscribe(to: client.withdrawOrDecline(challenge), for: attempt) { [weak self] result in
                self?.resolve(attempt, Self.resolution(result, outcome: .rejected, isRetry: isRetry))
            }
        case .withdraw(let challenge):
            subscribe(to: client.withdrawOrDecline(challenge), for: attempt) { [weak self] result in
                self?.resolve(attempt, Self.resolution(result, outcome: .withdrawn, isRetry: isRetry))
            }
        case .withdrawAutomatch(let entry):
            let withdrawal = ActivityQuickMatchWithdrawal.start(
                uuid: entry.uuid, sent: client.cancelAutomatch(entry), at: time)
            guard withdrawal.state.isPending else {
                resolve(attempt, .failed)
                return
            }
            quickMatchWithdraws[attempt.id] = QuickMatchWithdraw(attempt: attempt, withdrawal: withdrawal)
            scheduleDeadline()
        case .leave(let challenge):
            subscribe(to: client.leaveRengo(challenge), for: attempt) { [weak self] result in
                self?.resolve(attempt, Self.resolution(result, outcome: .left, isRetry: isRetry))
            }
        case .start(let challenge, let isLive):
            subscribe(to: client.startRengo(challenge), for: attempt) { [weak self] result in
                self?.resolve(attempt, Self.resolution(result, isLive: isLive))
            }
        }
    }

    /// Keeps the reply's subscription until it finishes. A reply that is
    /// already there finishes at once.
    private func subscribe<Value>(
        to reply: AnyPublisher<Value, Error>,
        for attempt: Attempt,
        _ completion: @escaping (Result<Value, Error>) -> Void
    ) {
        var value: Value?
        var finished = false
        let subscription = reply.sink(
            receiveCompletion: { [weak self] end in
                finished = true
                self?.replies[attempt.id] = nil
                switch end {
                case .finished:
                    completion(value.map { .success($0) } ?? .failure(NoReply()))
                case .failure(let error):
                    completion(.failure(error))
                }
            },
            receiveValue: { value = $0 }
        )
        if !finished {
            replies[attempt.id] = subscription
        }
    }

    private static func resolution(_ result: Result<Int, Error>, isLive: Bool) -> Resolution {
        guard case .success(let gameID) = result else { return .failed }
        switch ActivityAcceptRule(isLive: isLive, gameID: gameID) {
        case .closeAndOpen(let gameID): return .opensGame(gameID)
        case .stay(let outcome): return .succeeded(outcome)
        }
    }

    private static func resolution(_ result: Result<Void, Error>, outcome: ActivityOutcome, isRetry: Bool) -> Resolution {
        switch result {
        case .success:
            return .succeeded(outcome)
        case .failure(let error):
            // On a Retry, "not found" means an earlier try went through.
            return isRetry && isNotFound(error) ? .succeeded(outcome) : .failed
        }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        (error as? AFError)?.responseCode == 404
    }

    // MARK: Quick Match

    private func receive(_ event: OGSAutomatchLifecycleEvent.Kind) {
        guard !quickMatchWithdraws.isEmpty else { return }
        settle(ActivityQuickMatchWithdrawal.apply(event, to: quickMatchWithdraws.mapValues(\.withdrawal)))
    }

    private func deadlinePassed() {
        deadline = nil
        settle(ActivityQuickMatchWithdrawal.expire(quickMatchWithdraws.mapValues(\.withdrawal), at: now()))
    }

    /// Resolves each withdraw a transition changed.
    private func settle(_ next: [Int: ActivityQuickMatchWithdrawal.Entry]) {
        for (id, withdraw) in quickMatchWithdraws.sorted(by: { $0.key < $1.key }) {
            let attempt = withdraw.attempt
            guard let updated = next[id] else {
                quickMatchWithdraws[id] = nil
                resolve(attempt, .removed)
                continue
            }
            guard updated.state != withdraw.withdrawal.state else { continue }
            switch updated.state {
            case .succeeded(let outcome):
                quickMatchWithdraws[id] = nil
                resolve(attempt, .succeeded(outcome))
            case .failed:
                if records[attempt.session] != nil {
                    quickMatchWithdraws[id]?.withdrawal = updated
                } else {
                    quickMatchWithdraws[id] = nil
                }
                resolve(attempt, .failed)
            case .pending:
                quickMatchWithdraws[id]?.withdrawal = updated
            }
        }
        scheduleDeadline()
    }

    /// Wakes the store at the next Quick Match deadline, if any is pending.
    private func scheduleDeadline() {
        deadline?.cancel()
        deadline = nil
        guard let next = ActivityQuickMatchWithdrawal.nextDeadline(
            entries: quickMatchWithdraws.mapValues(\.withdrawal)
        ) else {
            return
        }
        deadline = scheduler.schedule(after: max(0, next - now())) { [weak self] in
            self?.deadlinePassed()
        }
    }

    // MARK: Results

    private func resolve(_ attempt: Attempt, _ resolution: Resolution) {
        let action = attempt.request.action
        let itemID = attempt.itemID
        switch resolution {
        case .opensGame(let gameID):
            record(.succeeded(.gameStarted(gameID: gameID)), for: attempt)
            if attempt.request.hidesOnSuccess, !hiddenIDs.contains(itemID) {
                hiddenIDs.insert(itemID)
            }
            // The user's own action, so the game opens even after the list
            // closed; the open itself says what happened.
            navigator?.closeActivity()
            navigator?.openGame(gameID, closesNewGame: true)
        case .succeeded(let outcome):
            // The announcement waits before the result publishes, so a row
            // that takes VoiceOver focus as it publishes can claim it.
            announceNextTurn(
                AppAnnouncement(.activityResult(itemID: itemID, action: action), audience: .anyWindow,
                                speech: outcome.text),
                about: itemID
            )
            record(.succeeded(outcome), for: attempt)
            if attempt.request.hidesOnSuccess, !hiddenIDs.contains(itemID) {
                hiddenIDs.insert(itemID)
            }
        case .failed:
            announceNextTurn(
                AppAnnouncement(.activityFailure(itemID: itemID, action: action), audience: .anyWindow,
                                speech: action.failureText),
                about: itemID
            )
            record(.failed, for: attempt)
        case .removed:
            guard records[attempt.session]?[itemID]?.attemptID == attempt.id else { return }
            records[attempt.session]?[itemID] = nil
            publish(attempt.session)
        }
    }

    /// Records a state for the attempt, unless its session ended or a later
    /// attempt took over.
    private func record(_ state: ActivityActionState, for attempt: Attempt) {
        guard records[attempt.session]?[attempt.itemID]?.attemptID == attempt.id else { return }
        records[attempt.session]?[attempt.itemID]?.entry.state = state
        publish(attempt.session)
    }

    /// Speaks one turn later, unless the row claimed the result by then. A
    /// SwiftUI state change can apply after a block queued now runs, so the
    /// row's claim never waits for its own redraw.
    private func announceNextTurn(_ announcement: AppAnnouncement, about itemID: String) {
        awaitingAnnouncement[itemID, default: 0] += 1
        let generation = generation
        scheduler.async { [weak self] in
            guard let self, generation == self.generation else { return }
            let stillWaiting = (awaitingAnnouncement[itemID] ?? 1) - 1
            awaitingAnnouncement[itemID] = stillWaiting > 0 ? stillWaiting : nil
            if claimedIDs.remove(itemID) != nil {
                return
            }
            navigator?.announce(announcement)
        }
    }

    private func publish(_ session: UUID) {
        guard session == sessionOrder.last else { return }
        publishLiveSession()
    }

    private func publishLiveSession() {
        let live = sessionOrder.last.flatMap { records[$0] }?.mapValues(\.entry) ?? [:]
        if entries != live {
            entries = live
        }
    }
}
