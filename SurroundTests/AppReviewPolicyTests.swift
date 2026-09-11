import Foundation
import XCTest

@MainActor
final class AppReviewPolicyTests: XCTestCase {
    private static let day: TimeInterval = 86_400
    private let observationOwnerID = UUID()

    private final class Clock {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var offset: TimeInterval = 0
        var date: Date { start.addingTimeInterval(offset) }
    }

    // Nested types do not inherit the test case's @MainActor. Without it,
    // Swift 5 mode runs wait() and waitUntilStarted() on the global executor
    // concurrently, and waitUntilStarted() can append its continuation after
    // wait() has already drained the list, hanging the test forever.
    @MainActor
    private final class DelayGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var startWaiters = [CheckedContinuation<Void, Never>]()
        private var started = false

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started = true
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        }

        func waitUntilStarted() async {
            guard !started else { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func preferences() -> UserDefaults {
        let name = "AppReviewPolicyTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }

    private func history(
        _ preferences: UserDefaults,
        version: String = "1.0"
    ) -> AppReviewHistoryStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return AppReviewHistoryStore(
            preferences: preferences, calendar: calendar,
            marketingVersion: version
        )
    }

    private func matureHistory(
        _ clock: Clock,
        preferences: UserDefaults? = nil
    ) -> AppReviewHistoryStore {
        let result = history(preferences ?? self.preferences())
        for day in 0..<5 {
            result.recordForegroundUse(
                at: clock.start.addingTimeInterval(Double(day) * Self.day),
                signedIn: true
            )
        }
        clock.offset = 8 * Self.day
        return result
    }

    private func context(
        home: Bool = false,
        turns: Bool = false,
        blocked: Bool = false,
        active: Bool = true,
        background: Bool = false,
        userID: Int? = 42
    ) -> AppReviewContext {
        AppReviewContext(
            isActive: active, isBackground: background, userID: userID,
            isHome: home, hasCorrespondenceTurns: turns, isBlocked: blocked
        )
    }

    private func completeCorrespondenceMove(_ coordinator: AppReviewCoordinator) {
        coordinator.updateContext(context())
        let submission = coordinator.beginMove(gameID: 100, correspondence: true)!
        coordinator.finishMove(submission, succeeded: true)
        coordinator.updateContext(context(home: true))
    }

    func testEligibilityRequiresSevenElapsedDaysAndFiveDistinctSignedInDays() {
        let clock = Clock()
        let store = history(preferences())
        store.recordForegroundUse(at: clock.start, signedIn: false)
        for _ in 0..<10 {
            store.recordForegroundUse(at: clock.start, signedIn: true)
        }
        for day in 1..<4 {
            store.recordForegroundUse(
                at: clock.start.addingTimeInterval(Double(day) * Self.day),
                signedIn: true
            )
        }
        XCTAssertFalse(store.isEligible(at: clock.start.addingTimeInterval(8 * Self.day)))
        store.recordForegroundUse(
            at: clock.start.addingTimeInterval(4 * Self.day), signedIn: true
        )
        XCTAssertFalse(store.isEligible(at: clock.start.addingTimeInterval(7 * Self.day - 1)))
        XCTAssertTrue(store.isEligible(at: clock.start.addingTimeInterval(7 * Self.day)))
    }

    func testAttemptPersistsAndRequiresNewVersionAnd120ElapsedDays() {
        let clock = Clock()
        let preferences = preferences()
        let store = matureHistory(clock, preferences: preferences)
        XCTAssertTrue(store.reserveAttempt(at: clock.date))
        XCTAssertFalse(history(preferences).isEligible(at: clock.date.addingTimeInterval(400 * Self.day)))
        let nextVersion = history(preferences, version: "1.1")
        XCTAssertFalse(nextVersion.isEligible(at: clock.date.addingTimeInterval(120 * Self.day - 1)))
        XCTAssertTrue(nextVersion.reserveAttempt(at: clock.date.addingTimeInterval(120 * Self.day)))
        XCTAssertFalse(nextVersion.reserveAttempt(at: clock.date.addingTimeInterval(240 * Self.day)))
    }

    func testMissingVersionDoesNotReserveAnAttempt() {
        let clock = Clock()
        let preferences = preferences()
        _ = matureHistory(clock, preferences: preferences)
        XCTAssertFalse(history(preferences, version: "").reserveAttempt(at: clock.date))
        XCTAssertTrue(history(preferences).isEligible(at: clock.date))
    }

    func testInitialHomeAndPassiveTurnUpdatesDoNotCreateOpportunity() {
        let clock = Clock()
        let store = matureHistory(clock)
        let coordinator = AppReviewCoordinator(history: store, now: { clock.date }, delay: {})
        coordinator.updateContext(context(home: true, turns: true))
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
        coordinator.updateContext(context())
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
    }

    func testCorrespondenceRequiresSuccessReturnHomeAndNoRemainingTurns() async {
        let clock = Clock()
        let store = matureHistory(clock)
        let coordinator = AppReviewCoordinator(history: store, now: { clock.date }, delay: {})
        coordinator.updateContext(context(turns: true))
        let token = coordinator.beginMove(gameID: 100, correspondence: true)!
        coordinator.finishMove(token, succeeded: true)
        XCTAssertNil(coordinator.requestID)
        coordinator.updateContext(context(home: true, turns: true))
        XCTAssertNil(coordinator.requestID)
        coordinator.updateContext(context(home: true))
        XCTAssertNotNil(coordinator.requestID)
        var presentations = 0
        await coordinator.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
        XCTAssertEqual(presentations, 1)
        XCTAssertFalse(store.isEligible(at: clock.date))
        XCTAssertNil(coordinator.requestID)
    }

    func testAcknowledgmentAfterReturningHomeStillQualifies() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        coordinator.updateContext(context())
        let token = coordinator.beginMove(gameID: 100, correspondence: true)!
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
        coordinator.finishMove(token, succeeded: true)
        XCTAssertNotNil(coordinator.requestID)
        coordinator.finishMove(token, succeeded: false)
        XCTAssertNotNil(coordinator.requestID, "Duplicate cancellation after success must be ignored")
    }

    func testPendingMoveAndFailureSuppressEarlierSuccess() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        coordinator.updateContext(context())
        let first = coordinator.beginMove(gameID: 100, correspondence: true)!
        coordinator.finishMove(first, succeeded: true)
        let second = coordinator.beginMove(gameID: 101, correspondence: true)!
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
        coordinator.finishMove(second, succeeded: false)
        XCTAssertNil(coordinator.requestID)
        coordinator.updateContext(context())
        let third = coordinator.beginMove(gameID: 102, correspondence: true)!
        coordinator.finishMove(third, succeeded: true)
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
    }

    func testLiveMoveWithoutFinishedGameDoesNotQualify() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        coordinator.updateContext(context())
        let token = coordinator.beginMove(gameID: 100, correspondence: false)!
        coordinator.finishMove(token, succeeded: true)
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
    }

    func testLiveCompletionRequiresObservedParticipantAndExcludesHistoryAndCancellation() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        coordinator.updateContext(context())
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .finished)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 2, isParticipant: false, phase: .playing)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 2, isParticipant: false, phase: .finished)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 3, isParticipant: true, phase: .playing)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 3, isParticipant: true, phase: .cancelled)
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
        coordinator.updateContext(context())
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 4, isParticipant: true, phase: .playing)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 4, isParticipant: true, phase: .scoring)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 4, isParticipant: true, phase: .finished)
        coordinator.stopObservingLiveGame(ownerID: observationOwnerID, gameID: 4)
        coordinator.updateContext(context(home: true, turns: true))
        XCTAssertNotNil(coordinator.requestID, "A completed live game does not require catching up correspondence")
    }

    func testStoppedLiveObservationAndBackgroundEventsCannotQualify() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        coordinator.updateContext(context())
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .playing)
        coordinator.stopObservingLiveGame(ownerID: observationOwnerID, gameID: 1)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .finished)
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 2, isParticipant: true, phase: .playing)
        coordinator.updateContext(context(active: false, background: true))
        coordinator.observeLiveGame(ownerID: observationOwnerID, gameID: 2, isParticipant: true, phase: .finished)
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)
    }

    func testOutgoingLayoutCannotClearIncomingViewsLiveBaseline() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        let outgoingOwner = UUID()
        let incomingOwner = UUID()
        coordinator.updateContext(context())
        coordinator.observeLiveGame(
            ownerID: outgoingOwner, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.observeLiveGame(
            ownerID: incomingOwner, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.stopObservingLiveGame(ownerID: outgoingOwner, gameID: 1)
        coordinator.observeLiveGame(
            ownerID: incomingOwner, gameID: 1, isParticipant: true, phase: .finished
        )
        coordinator.stopObservingLiveGame(ownerID: incomingOwner, gameID: 1)
        coordinator.updateContext(context(home: true))

        XCTAssertNotNil(coordinator.requestID)
    }

    func testFullyLeavingGameThenOpeningFinishedHistoryCannotQualify() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        let firstOwner = UUID()
        let historyOwner = UUID()
        coordinator.updateContext(context())
        coordinator.observeLiveGame(
            ownerID: firstOwner, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.stopObservingLiveGame(ownerID: firstOwner, gameID: 1)
        coordinator.updateContext(context(home: true))
        XCTAssertNil(coordinator.requestID)

        coordinator.updateContext(context())
        coordinator.observeLiveGame(
            ownerID: historyOwner, gameID: 1, isParticipant: true, phase: .finished
        )
        coordinator.stopObservingLiveGame(ownerID: historyOwner, gameID: 1)
        coordinator.updateContext(context(home: true))

        XCTAssertNil(coordinator.requestID)
    }

    func testNewViewCannotBorrowOngoingBaselineFromAnotherOwner() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        let outgoingOwner = UUID()
        let incomingOwner = UUID()
        coordinator.updateContext(context())
        coordinator.observeLiveGame(
            ownerID: outgoingOwner, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.observeLiveGame(
            ownerID: incomingOwner, gameID: 1, isParticipant: true, phase: .finished
        )
        coordinator.stopObservingLiveGame(ownerID: outgoingOwner, gameID: 1)
        coordinator.updateContext(context(home: true))

        XCTAssertNil(coordinator.requestID)
    }

    func testSceneReadinessChangesObservationIdentityAndAllowsBaselineRetry() {
        let clock = Clock()
        let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
        let initialIdentity = coordinator.gameObservationContextID
        // The child may appear before its parent installs the scene context.
        coordinator.observeLiveGame(
            ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.updateContext(context(home: true))
        let homeIdentity = coordinator.gameObservationContextID
        XCTAssertNotEqual(homeIdentity, initialIdentity)
        coordinator.updateContext(context())
        let readyIdentity = coordinator.gameObservationContextID
        XCTAssertNotEqual(readyIdentity, homeIdentity)

        // The changed identity restarts the visible child's observation task.
        coordinator.observeLiveGame(
            ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .playing
        )
        coordinator.updateContext(context(turns: true, blocked: true))
        XCTAssertEqual(coordinator.gameObservationContextID, readyIdentity)
        coordinator.observeLiveGame(
            ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .finished
        )
        coordinator.updateContext(context(home: true))

        XCTAssertNotNil(coordinator.requestID)
    }

    func testHomeOrInactiveContextClearsBaselineBeforeViewDisappears() {
        for interruption in [context(home: true), context(active: false)] {
            let clock = Clock()
            let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
            coordinator.updateContext(context())
            coordinator.observeLiveGame(
                ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .playing
            )
            let activeIdentity = coordinator.gameObservationContextID
            coordinator.updateContext(interruption)
            XCTAssertNotEqual(coordinator.gameObservationContextID, activeIdentity)
            let interruptedIdentity = coordinator.gameObservationContextID
            coordinator.updateContext(context())
            XCTAssertNotEqual(coordinator.gameObservationContextID, interruptedIdentity)
            coordinator.observeLiveGame(
                ownerID: observationOwnerID, gameID: 1, isParticipant: true, phase: .finished
            )
            coordinator.updateContext(context(home: true))

            XCTAssertNil(coordinator.requestID)
        }
    }

    func testBackgroundAndAccountChangesInvalidatePendingAcknowledgments() {
        for changesAccount in [false, true] {
            let clock = Clock()
            let coordinator = AppReviewCoordinator(history: matureHistory(clock), now: { clock.date }, delay: {})
            coordinator.updateContext(context())
            let token = coordinator.beginMove(gameID: 100, correspondence: true)!
            if changesAccount {
                coordinator.updateContext(context(userID: 43))
            } else {
                coordinator.updateContext(context(active: false, background: true))
            }
            coordinator.updateContext(context(home: true, userID: changesAccount ? 43 : 42))
            coordinator.finishMove(token, succeeded: true)
            XCTAssertNil(coordinator.requestID)
        }
    }

    func testInactiveCancelsDelayButPreservesSessionForSafeReturn() async {
        let clock = Clock()
        let store = matureHistory(clock)
        let gate = DelayGate()
        let coordinator = AppReviewCoordinator(history: store, now: { clock.date }, delay: { await gate.wait() })
        completeCorrespondenceMove(coordinator)
        let originalRequest = coordinator.requestID
        var presentations = 0
        let task = Task {
            await coordinator.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
        }
        await gate.waitUntilStarted()
        coordinator.updateContext(context(home: true, active: false))
        XCTAssertNil(coordinator.requestID)
        gate.release()
        await task.value
        XCTAssertEqual(presentations, 0)
        XCTAssertTrue(store.isEligible(at: clock.date))
        coordinator.updateContext(context(home: true))
        XCTAssertNotNil(coordinator.requestID)
        XCTAssertNotEqual(originalRequest, coordinator.requestID)
    }

    func testBlockedOrNavigatedAwayDuringDelayDoesNotReserveAttempt() async {
        for navigatesAway in [false, true] {
            let clock = Clock()
            let store = matureHistory(clock)
            let gate = DelayGate()
            let coordinator = AppReviewCoordinator(history: store, now: { clock.date }, delay: { await gate.wait() })
            completeCorrespondenceMove(coordinator)
            var presentations = 0
            let task = Task {
                await coordinator.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
            }
            await gate.waitUntilStarted()
            coordinator.updateContext(context(home: !navigatesAway, blocked: !navigatesAway))
            gate.release()
            await task.value
            XCTAssertEqual(presentations, 0)
            XCTAssertTrue(store.isEligible(at: clock.date))
        }
    }

    func testTaskCancellationAndFinalSceneRecheckDoNotConsumeQuota() async {
        let clock = Clock()
        let store = matureHistory(clock)
        let gate = DelayGate()
        let coordinator = AppReviewCoordinator(history: store, now: { clock.date }, delay: { await gate.wait() })
        completeCorrespondenceMove(coordinator)
        var presentations = 0
        let task = Task {
            await coordinator.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
        }
        await gate.waitUntilStarted()
        task.cancel()
        gate.release()
        await task.value
        XCTAssertEqual(presentations, 0)
        XCTAssertTrue(store.isEligible(at: clock.date))

        let next = AppReviewCoordinator(history: store, now: { clock.date }, delay: {})
        completeCorrespondenceMove(next)
        await next.requestIfEligible(present: { presentations += 1 }, finalCheck: { false })
        XCTAssertEqual(presentations, 0)
        XCTAssertTrue(store.isEligible(at: clock.date))
    }

    func testTwoWindowsReserveOnlyOneAttemptEvenWithSeparateHistoryInstances() async {
        let clock = Clock()
        let preferences = preferences()
        let store = matureHistory(clock, preferences: preferences)
        let first = AppReviewCoordinator(history: store, now: { clock.date }, delay: {})
        let second = AppReviewCoordinator(history: history(preferences), now: { clock.date }, delay: {})
        completeCorrespondenceMove(first)
        completeCorrespondenceMove(second)
        XCTAssertNotNil(first.requestID)
        XCTAssertNotNil(second.requestID)
        var presentations = 0
        await first.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
        await second.requestIfEligible(present: { presentations += 1 }, finalCheck: { true })
        XCTAssertEqual(presentations, 1)
        XCTAssertNil(second.requestID)
    }
}
