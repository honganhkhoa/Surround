import Combine
import XCTest

final class GameControlStateTests: XCTestCase {
    private final class ScoringSocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks: [() -> Void] = []
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = true
        var opened = true
        var status = OGSWebsocketStatus.connected
        var drift = 0.0
        var latency = 0.0
        var commands: [String] = []
        var removedStonePayloads: [[String: Any]] = []

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() {}
        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            commands.append(command)
            if command == "game/removed_stones/set", let data = data as? [String: Any] {
                removedStonePayloads.append(data)
            }
        }
    }

    /// Keeps each `game/move` and its callback, so a test can answer it.
    private final class MoveSocket: OGSWebsocketProtocol {
        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks: [() -> Void] = []
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = true
        var opened = true
        var status = OGSWebsocketStatus.connected
        var drift = 0.0
        var latency = 0.0
        var moves: [Any?] = []
        var moveCallbacks: [OGSWebsocketResultCallback] = []

        func connect() {}
        func close() {}
        func reconnectIfNeeded() {}
        func closeThenReconnect() {}
        func emit(command: String, data: Any?, resultCallback: OGSWebsocketResultCallback?) {
            guard command == "game/move" else { return }
            moves.append(data)
            if let resultCallback { moveCallbacks.append(resultCallback) }
        }

        func deliver(_ name: String, _ data: Any?) {
            serverEventCallback?(name, data)
        }
    }

    private final class HapticsRecorder: MoveCommitHaptics {
        var events: [String] = []

        func prepare() { events.append("prepare") }
        func playCommit() { events.append("commit") }
        func playRefusal() { events.append("refusal") }
    }

    private final class SpeechRecorder: CountdownSpeaking {
        var spoken: [String] = []

        func prepare() {}
        func speak(_ text: String) { spoken.append(text) }
        func stop() {}
    }

    /// Counts what a board's stone sounds would play.
    private final class SoundCounter {
        var plays = 0
        var schedules = 0

        func makePlayer(_ name: String) -> StoneSoundPlaying? { CountedVoice(counter: self) }
    }

    private final class CountedVoice: StoneSoundPlaying {
        private let counter: SoundCounter
        var currentTime: TimeInterval = 0
        let deviceCurrentTime: TimeInterval = 0
        let duration: TimeInterval = 0.2

        init(counter: SoundCounter) { self.counter = counter }

        func prepareToPlay() -> Bool { true }
        func play() -> Bool {
            counter.plays += 1
            return true
        }
        func play(atTime time: TimeInterval) -> Bool {
            counter.schedules += 1
            return true
        }
        func stop() {}
    }

    private enum Failure: Error {
        case rejected
    }

    private let firstGame = GameID.OGS(1)
    private let secondGame = GameID.OGS(2)
    private let accountID = 100

    @MainActor
    func testDelayedEstimateCannotReturnAfterAMoveAndUndoToTheSamePosition() throws {
        let game = Game(width: 9, height: 9, blackName: "black", whiteName: "white", gameId: firstGame)
        game.gamePhase = .play
        let position = game.currentPosition
        let positionRevision = position.scoringRevision
        let state = GameControlState()
        let service = OGSService(previewState: .init())
        state.updateContext(gameID: game.ID, accountID: service.user?.id)
        let finished = expectation(description: "Delayed estimate finishes")
        let observation = state.$isBusy.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in finished.fulfill() }
        defer { observation.cancel() }

        // Use the existing per-game worker queue to delay the real estimator.
        let queue = game.computeQueue
        queue.suspend()
        var suspended = true
        defer { if suspended { queue.resume() } }
        state.estimateTerritory(game: game, using: service)
        XCTAssertTrue(state.isBusy)
        try game.makeMove(move: .placeStone(2, 2))
        game.undoLastMoves(count: 1)
        XCTAssertTrue(game.currentPosition === position)
        XCTAssertEqual(position.scoringRevision, positionRevision,
                       "Position identity and its own revision cannot detect the intervening move")

        queue.resume()
        suspended = false
        // The real estimator runs here, and a busy CI runner can take tens of
        // seconds; the test is about the result, not its speed.
        wait(for: [finished], timeout: 60)
        XCTAssertFalse(state.isBusy)
        XCTAssertNil(position.estimatedScores, "Undo must not revive an estimate requested before the move")
    }

    @MainActor
    func testDelayedRequestKeepsBusyStateAndPreventsAnotherCommand() {
        let state = GameControlState()
        let response = PassthroughSubject<Int, Failure>()
        var commandCount = 0
        var receivedValues: [Int] = []
        let received = expectation(description: "Authoritative response")

        XCTAssertTrue(state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: {
                commandCount += 1
                return response
            },
            receiveValue: {
                receivedValues.append($0)
                received.fulfill()
            }
        ))
        // A replacement control row reuses this owner and the same context.
        state.updateContext(gameID: firstGame, accountID: accountID)
        XCTAssertTrue(state.isBusy)
        XCTAssertFalse(state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: {
                commandCount += 1
                return response
            },
            receiveValue: { _ in XCTFail("Duplicate command completed") }
        ))
        XCTAssertEqual(commandCount, 1)

        response.send(42)
        wait(for: [received], timeout: 1)
        XCTAssertEqual(receivedValues, [42])
        XCTAssertFalse(state.isBusy)
    }

    @MainActor
    func testQueuedOldResponseCannotClearTheNextGamesRequest() {
        let state = GameControlState()
        let firstResponse = PassthroughSubject<Int, Failure>()
        let secondResponse = PassthroughSubject<Int, Failure>()
        var cancelledObservations = 0
        var oldCallbacks = 0
        state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: { firstResponse },
            receiveValue: { _ in oldCallbacks += 1 },
            receiveFailure: { _ in oldCallbacks += 1 },
            onCancel: { cancelledObservations += 1 }
        )
        // The response is queued for the main thread when the game changes.
        firstResponse.send(10)
        state.updateContext(gameID: secondGame, accountID: accountID)
        let received = expectation(description: "New game's response")
        state.performRequest(
            gameID: secondGame,
            accountID: accountID,
            publisher: { secondResponse },
            receiveValue: { _ in received.fulfill() }
        )
        drainMainQueue()

        XCTAssertEqual(cancelledObservations, 1)
        XCTAssertEqual(oldCallbacks, 0)
        XCTAssertTrue(state.isBusy)
        secondResponse.send(20)
        wait(for: [received], timeout: 1)
        XCTAssertFalse(state.isBusy)
    }

    @MainActor
    func testFailureReleasesBusyStateAndAllowsRetry() {
        let state = GameControlState()
        let response = PassthroughSubject<Int, Failure>()
        let failed = expectation(description: "Rejected request")
        state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: { response },
            receiveValue: { _ in XCTFail("Failed request produced a value") },
            receiveFailure: { _ in failed.fulfill() }
        )
        response.send(completion: .failure(.rejected))
        wait(for: [failed], timeout: 1)
        XCTAssertFalse(state.isBusy)

        let retry = PassthroughSubject<Int, Failure>()
        XCTAssertTrue(state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: { retry },
            receiveValue: { _ in }
        ))
        XCTAssertTrue(state.isBusy)
    }

    @MainActor
    func testSameGameRetainsPresentationButGameOrAccountChangesDismissIt() {
        let state = GameControlState()
        state.presentRematch(
            OGSChallengeSampleData.sampleChallengeTemplate,
            gameID: firstGame,
            accountID: accountID
        )
        let rematchID = state.rematchPresentation?.id
        state.updateContext(gameID: firstGame, accountID: accountID)
        XCTAssertEqual(state.rematchPresentation?.id, rematchID)
        XCTAssertNotNil(state.rematchPresentation)

        state.updateContext(gameID: secondGame, accountID: accountID)
        XCTAssertNil(state.rematchPresentation)
        state.confirm(.pass, gameID: secondGame, accountID: accountID)
        let confirmationID = state.confirmation?.id
        state.updateContext(gameID: secondGame, accountID: accountID)
        XCTAssertEqual(state.confirmation?.id, confirmationID)
        XCTAssertNotNil(state.confirmation)

        state.updateContext(gameID: secondGame, accountID: accountID + 1)
        XCTAssertNil(state.confirmation)
        XCTAssertFalse(state.matches(gameID: secondGame, accountID: accountID))
    }

    @MainActor
    func testAccountChangeCancelsObservationWithoutAcceptingItsResponse() {
        let state = GameControlState()
        let response = PassthroughSubject<Int, Failure>()
        var cancellations = 0
        var received = 0
        state.performRequest(
            gameID: firstGame,
            accountID: accountID,
            publisher: { response },
            receiveValue: { _ in received += 1 },
            onCancel: { cancellations += 1 }
        )
        state.updateContext(gameID: firstGame, accountID: nil)
        response.send(42)
        drainMainQueue()

        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(received, 0)
    }

    @MainActor
    func testScoringTimeoutIsUnconfirmedAndDoesNotResendOrClearSelection() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let snapshot = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        var commandCount = 0
        var selectedPoints: Set<[Int]> = [[1, 2]]
        func submit() -> Bool {
            state.performScoringRequest(
                gameID: firstGame, accountID: accountID,
                confirmation: echo.eraseToAnyPublisher(),
                connection: connection.eraseToAnyPublisher(),
                snapshot: { snapshot.eraseToAnyPublisher() },
                send: { commandCount += 1 }, refresh: {},
                onConfirmed: { selectedPoints.removeAll() }
            )
        }
        XCTAssertTrue(submit())
        XCTAssertFalse(submit())
        deadline.send(())
        drainMainQueue()

        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.requiresScoringRefresh)
        XCTAssertTrue(state.blocksGameActions)
        XCTAssertEqual(state.scoringNotice, .unconfirmed)
        XCTAssertEqual(selectedPoints, [[1, 2]])
        XCTAssertFalse(submit(), "A timeout does not make a toggle safe to retry.")
        XCTAssertEqual(commandCount, 1)
        echo.send(())
        drainMainQueue()
        XCTAssertTrue(state.requiresScoringRefresh, "A late command echo is not a new snapshot.")
        XCTAssertEqual(selectedPoints, [[1, 2]])
    }

    @MainActor
    func testAuthoritativeSnapshotAndDeadlineCannotLeaveRecoveryLockedInEitherOrder() {
        for snapshotFirst in [true, false] {
            let deadline = PassthroughSubject<Void, Never>()
            let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
            let echo = PassthroughSubject<Void, Error>()
            let snapshot = PassthroughSubject<Void, Error>()
            let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
            var commands = 0
            var confirmations = 0
            state.performScoringRequest(
                gameID: firstGame, accountID: accountID,
                confirmation: echo.eraseToAnyPublisher(),
                connection: connection.eraseToAnyPublisher(),
                snapshot: { snapshot.eraseToAnyPublisher() },
                send: { commands += 1 },
                refresh: { XCTFail("An unsolicited snapshot needs no manual refresh.") },
                onConfirmed: { confirmations += 1 }
            )
            // Both events arrive before their queued main-thread handling.
            // In particular, gamedata can replace the original BoardPosition
            // before its old removed-stones waiter reaches the deadline.
            if snapshotFirst {
                snapshot.send(())
                deadline.send(())
            } else {
                deadline.send(())
                snapshot.send(())
            }
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions)
            XCTAssertEqual(state.scoringNotice, .refreshed)
            XCTAssertEqual(commands, 1)
            XCTAssertEqual(confirmations, 0)
            deadline.send(())
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions, "A settled recovery cannot be relocked by a late timeout.")
        }
    }

    @MainActor
    func testQueuedPassiveSnapshotCannotUnlockNewEpisodeAfterReturningToSameContext() {
        for switchesAccount in [false, true] {
            let deadline = PassthroughSubject<Void, Never>()
            let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
            let oldEcho = PassthroughSubject<Void, Error>()
            let oldSnapshot = PassthroughSubject<Void, Error>()
            let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
            state.performScoringRequest(
                gameID: firstGame, accountID: accountID,
                confirmation: oldEcho.eraseToAnyPublisher(),
                connection: connection.eraseToAnyPublisher(),
                snapshot: { oldSnapshot.eraseToAnyPublisher() }, send: {}, refresh: {}
            )
            deadline.send(())
            drainMainQueue()
            oldSnapshot.send(())
            state.updateContext(
                gameID: switchesAccount ? firstGame : secondGame,
                accountID: switchesAccount ? accountID + 1 : accountID
            )
            let newEcho = PassthroughSubject<Void, Error>()
            let newSnapshot = PassthroughSubject<Void, Error>()
            state.performScoringRequest(
                gameID: firstGame, accountID: accountID,
                confirmation: newEcho.eraseToAnyPublisher(),
                connection: connection.eraseToAnyPublisher(),
                snapshot: { newSnapshot.eraseToAnyPublisher() }, send: {}, refresh: {}
            )
            drainMainQueue()
            XCTAssertTrue(state.isBusy)
            XCTAssertNil(state.scoringNotice)
            oldSnapshot.send(())
            drainMainQueue()
            XCTAssertTrue(state.isBusy)
            newEcho.send(())
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions)
        }
    }

    @MainActor
    func testScoringRefreshSubscribesBeforeRequestAndUnlocksWithoutResending() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let snapshot = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        var commandCount = 0
        var refreshCount = 0
        var confirmedCommands = 0
        state.performScoringRequest(
            gameID: firstGame, accountID: accountID,
            confirmation: echo.eraseToAnyPublisher(),
            connection: connection.eraseToAnyPublisher(),
            snapshot: { snapshot.eraseToAnyPublisher() },
            send: { commandCount += 1 },
            refresh: {
                refreshCount += 1
                snapshot.send(())
            },
            onConfirmed: { confirmedCommands += 1 }
        )
        deadline.send(())
        drainMainQueue()
        state.refreshScoringState()
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(state.blocksGameActions)
        state.refreshScoringState()
        drainMainQueue()

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(commandCount, 1)
        XCTAssertEqual(confirmedCommands, 0, "Refreshing does not claim the old command succeeded.")
        XCTAssertFalse(state.blocksGameActions)
        XCTAssertEqual(state.scoringNotice, .refreshed)
        state.dismissScoringNotice()
        XCTAssertNil(state.scoringNotice)
    }

    @MainActor
    func testScoringDisconnectAndRefreshTimeoutKeepRecoveryAvailable() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let snapshot = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        var refreshCount = 0
        state.performScoringRequest(
            gameID: firstGame, accountID: accountID,
            confirmation: echo.eraseToAnyPublisher(),
            connection: connection.eraseToAnyPublisher(),
            snapshot: { snapshot.eraseToAnyPublisher() }, send: {},
            refresh: { refreshCount += 1 }
        )
        connection.send(.reconnecting)
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(state.scoringNotice, .unconfirmed)
        state.dismissScoringNotice()
        XCTAssertEqual(state.scoringNotice, .unconfirmed)

        connection.send(.connected)
        state.refreshScoringState()
        XCTAssertTrue(state.isBusy)
        XCTAssertEqual(state.scoringNotice, .refreshing)
        deadline.send(())
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.requiresScoringRefresh)
        XCTAssertEqual(state.scoringNotice, .unconfirmed)
        state.refreshScoringState()
        XCTAssertEqual(refreshCount, 2)
        snapshot.send(())
        drainMainQueue()
        XCTAssertFalse(state.blocksGameActions)
    }

    @MainActor
    func testScoringRefreshFailureRemainsUnconfirmedAndRetryable() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let snapshot = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        state.performScoringRequest(
            gameID: firstGame, accountID: accountID,
            confirmation: echo.eraseToAnyPublisher(),
            connection: connection.eraseToAnyPublisher(),
            snapshot: { snapshot.eraseToAnyPublisher() }, send: {}, refresh: {}
        )
        echo.send(completion: .failure(Failure.rejected))
        drainMainQueue()
        state.refreshScoringState()
        snapshot.send(completion: .failure(Failure.rejected))
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.blocksGameActions)
        XCTAssertEqual(state.scoringNotice, .unconfirmed)
    }

    @MainActor
    func testQueuedScoringRefreshCannotUnlockAnotherGamesRequest() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let snapshot = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        state.performScoringRequest(
            gameID: firstGame, accountID: accountID,
            confirmation: echo.eraseToAnyPublisher(),
            connection: connection.eraseToAnyPublisher(),
            snapshot: { snapshot.eraseToAnyPublisher() }, send: {}, refresh: {}
        )
        deadline.send(())
        drainMainQueue()
        state.refreshScoringState()
        snapshot.send(())
        state.updateContext(gameID: secondGame, accountID: accountID)
        let nextResponse = PassthroughSubject<Void, Error>()
        state.performRequest(
            gameID: secondGame, accountID: accountID,
            publisher: { nextResponse }, receiveValue: { _ in }
        )
        drainMainQueue()
        XCTAssertTrue(state.isBusy)
        XCTAssertFalse(state.requiresScoringRefresh)
        XCTAssertNil(state.scoringNotice)
        nextResponse.send(())
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
    }

    @MainActor
    func testSynchronousScoringEchoIsObservedBeforeDeadline() {
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: {
            deadline.eraseToAnyPublisher()
        })
        let echo = PassthroughSubject<Void, Error>()
        let connection = CurrentValueSubject<OGSWebsocketStatus, Never>(.connected)
        var confirmations = 0
        state.performScoringRequest(
            gameID: firstGame, accountID: accountID,
            confirmation: echo.eraseToAnyPublisher(),
            connection: connection.eraseToAnyPublisher(),
            snapshot: { Empty().eraseToAnyPublisher() },
            send: { echo.send(()) }, refresh: {},
            onConfirmed: { confirmations += 1 }
        )
        drainMainQueue()
        XCTAssertEqual(confirmations, 1)
        XCTAssertFalse(state.blocksGameActions)
        deadline.send(())
        drainMainQueue()
        XCTAssertNil(state.scoringNotice)
    }

    @MainActor
    func testToggleWaitsForRequestedStonesAndSettlesWhenScoringEnds() throws {
        let (game, service, socket, _) = try scoringFixture()
        game.currentPosition.removedStones = []
        let state = GameControlState()
        var confirmations = 0
        let points: Set<[Int]> = [[1, 2]]
        state.toggleRemovedStones(points, game: game, using: service) {
            confirmations += 1
        }
        XCTAssertEqual(socket.commands.filter { $0 == "game/removed_stones/set" }.count, 1)
        socket.serverEventCallback?("game/27053412/removed_stones", [
            "all_removed": BoardPosition.positionString(fromPoints: [[2, 2]])
        ])
        drainMainQueue()
        XCTAssertTrue(state.isBusy, "An unrelated removed-stone update is not this toggle's confirmation.")
        socket.serverEventCallback?("game/27053412/removed_stones", [
            "all_removed": BoardPosition.positionString(fromPoints: points.union([[2, 2]]))
        ])
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(confirmations, 1)

        state.toggleRemovedStones(points, game: game, using: service) {
            confirmations += 1
        }
        socket.serverEventCallback?("game/27053412/phase", "finished")
        drainMainQueue()
        XCTAssertFalse(state.blocksGameActions)
        XCTAssertNil(state.scoringNotice)
    }

    @MainActor
    func testMixedStoneToggleWaitsForEveryRequestedMembershipButIgnoresOtherGroups() throws {
        let (game, service, socket, _) = try scoringFixture()
        let alreadyRemoved = [1, 2]
        let newlyRemoved = [2, 2]
        let unrelated = [3, 3]
        game.currentPosition.removedStones = [alreadyRemoved]
        let state = GameControlState()
        var confirmations = 0
        state.toggleRemovedStones([alreadyRemoved, newlyRemoved], game: game, using: service) {
            confirmations += 1
        }
        XCTAssertEqual(socket.removedStonePayloads.count, 2)
        // The add has arrived but the requested removal has not.
        socket.serverEventCallback?("game/27053412/removed_stones", [
            "all_removed": BoardPosition.positionString(fromPoints: [alreadyRemoved, newlyRemoved, unrelated])
        ])
        drainMainQueue()
        XCTAssertTrue(state.isBusy)
        // Both requested memberships now match; the other player's group is
        // unrelated to this command and must not delay confirmation.
        socket.serverEventCallback?("game/27053412/removed_stones", [
            "all_removed": BoardPosition.positionString(fromPoints: [newlyRemoved, unrelated])
        ])
        drainMainQueue()
        XCTAssertFalse(state.blocksGameActions)
        XCTAssertEqual(confirmations, 1)
        XCTAssertNil(state.scoringNotice)
    }

    @MainActor
    func testPhaseExitClearsTimedOutToggleAcceptanceAndResumeWithoutRefresh() throws {
        for action in ["toggle", "accept", "resume"] {
            for phase in ["play", "finished"] {
                let (game, service, socket, _) = try scoringFixture()
                let deadline = PassthroughSubject<Void, Never>()
                let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
                game.currentPosition.removedStones = []
                game.removedStonesAccepted = [:]
                var confirmations = 0
                switch action {
                case "toggle":
                    state.toggleRemovedStones([[1, 2]], game: game, using: service) {
                        confirmations += 1
                    }
                case "accept": state.acceptRemovedStones(game: game, using: service)
                default: state.resumeGameFromStoneRemoval(game: game, using: service)
                }
                deadline.send(())
                drainMainQueue()
                XCTAssertTrue(state.requiresScoringRefresh, action)
                let commands = socket.commands
                socket.serverEventCallback?("game/27053412/phase", phase)
                drainMainQueue()
                XCTAssertFalse(state.blocksGameActions, "\(action), \(phase)")
                XCTAssertNil(state.scoringNotice)
                XCTAssertEqual(confirmations, 0, "A phase exit settles uncertainty without acknowledging the old command.")
                XCTAssertEqual(socket.commands, commands)
                deadline.send(())
                drainMainQueue()
                XCTAssertFalse(state.blocksGameActions)
            }
        }
    }

    @MainActor
    func testPhaseExitDuringRefreshCannotBeRelockedByRefreshTimeout() throws {
        for phaseFirst in [true, false] {
            let (game, service, socket, _) = try scoringFixture()
            let deadline = PassthroughSubject<Void, Never>()
            let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
            state.resumeGameFromStoneRemoval(game: game, using: service)
            deadline.send(())
            drainMainQueue()
            state.refreshScoringState()
            XCTAssertTrue(state.isBusy)
            if phaseFirst {
                socket.serverEventCallback?("game/27053412/phase", "play")
                deadline.send(())
            } else {
                deadline.send(())
                socket.serverEventCallback?("game/27053412/phase", "play")
            }
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions)
            XCTAssertNil(state.scoringNotice)
        }
    }

    @MainActor
    func testReconnectSnapshotClearsScoringRecoveryWithoutManualRefresh() throws {
        let (game, service, socket, rawData) = try scoringFixture()
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
        game.currentPosition.removedStones = []
        var confirmations = 0
        state.toggleRemovedStones([[1, 2]], game: game, using: service) {
            confirmations += 1
        }
        deadline.send(())
        drainMainQueue()
        XCTAssertTrue(state.requiresScoringRefresh)
        let commandCount = socket.removedStonePayloads.count
        service.processOverview(overview: ["active_games": [[
            "id": 27_053_412, "json": rawData
        ]]])
        drainMainQueue()
        XCTAssertTrue(state.requiresScoringRefresh, "Cached overview data is not recovery evidence.")
        socket.status = .reconnecting
        socket.onStatusChanged?()
        socket.status = .connected
        socket.onStatusChanged?()
        socket.serverEventCallback?("game/27053412/gamedata", rawData)
        drainMainQueue()
        XCTAssertFalse(state.blocksGameActions)
        XCTAssertEqual(state.scoringNotice, .refreshed)
        XCTAssertEqual(confirmations, 0)
        XCTAssertEqual(socket.removedStonePayloads.count, commandCount)
    }

    @MainActor
    func testCachedPhaseChangeCannotSettleScoringWaitOrRecovery() throws {
        for stage in ["pending", "timed-out", "refreshing"] {
            let (game, service, socket, rawData) = try scoringFixture()
            let deadline = PassthroughSubject<Void, Never>()
            let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
            state.resumeGameFromStoneRemoval(game: game, using: service)
            if stage != "pending" {
                deadline.send(())
                drainMainQueue()
            }
            if stage == "refreshing" { state.refreshScoringState() }
            var cached = rawData
            cached["phase"] = "play"
            service.processOverview(overview: ["active_games": [[
                "id": 27_053_412, "json": cached
            ]]])
            drainMainQueue()
            XCTAssertEqual(game.gamePhase, .play)
            XCTAssertTrue(state.blocksGameActions, "Cached phase change while \(stage) is not an authoritative reply.")
            // The live event must settle even though the displayed phase now
            // has the same value as the stale overview assignment.
            socket.serverEventCallback?("game/27053412/phase", "play")
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions, stage)
            XCTAssertNil(state.scoringNotice)
        }
    }

    @MainActor
    func testAcceptanceWaitsForThisPlayersEchoAndResumeHandlesDisconnect() throws {
        let (game, service, socket, _) = try scoringFixture()
        let state = GameControlState()
        let points: Set<[Int]> = [[1, 2]]
        game.currentPosition.removedStones = points
        game.removedStonesAccepted = [:]
        let stones = BoardPosition.positionString(fromPoints: points)
        state.acceptRemovedStones(game: game, using: service)
        XCTAssertEqual(socket.commands.last, "game/removed_stones/accept")
        socket.serverEventCallback?("game/27053412/removed_stones_accepted", [
            "player_id": game.whitePlayer!.id, "stones": stones
        ])
        drainMainQueue()
        XCTAssertTrue(state.isBusy)
        socket.serverEventCallback?("game/27053412/removed_stones_accepted", [
            "player_id": game.blackPlayer!.id, "stones": stones
        ])
        drainMainQueue()
        XCTAssertFalse(state.isBusy)

        state.resumeGameFromStoneRemoval(game: game, using: service)
        XCTAssertEqual(socket.commands.last, "game/removed_stones/reject")
        let interrupted = expectation(description: "Disconnected scoring wait releases busy")
        let observer = state.$isBusy.first { !$0 }.sink { _ in interrupted.fulfill() }
        socket.status = .reconnecting
        socket.onStatusChanged?()
        wait(for: [interrupted], timeout: 1)
        observer.cancel()
        XCTAssertEqual(state.scoringNotice, .unconfirmed)
        XCTAssertTrue(state.requiresScoringRefresh)
    }

    @MainActor
    func testRefreshRequiresMatchingAuthoritativeSnapshotAfterModelApplication() throws {
        let (game, service, socket, rawData) = try scoringFixture()
        let deadline = PassthroughSubject<Void, Never>()
        let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
        game.currentPosition.removedStones = []
        var selected: Set<[Int]> = [[1, 2]]
        state.toggleRemovedStones(selected, game: game, using: service) {
            selected.removeAll()
        }
        deadline.send(())
        drainMainQueue()
        state.refreshScoringState()
        XCTAssertTrue(state.isBusy)
        XCTAssertEqual(Array(socket.commands.suffix(2)), ["game/disconnect", "game/connect"])

        var cachedData = rawData
        cachedData["removed"] = ""
        service.processOverview(overview: ["active_games": [[
            "id": 27_053_412, "json": cachedData
        ]]])
        drainMainQueue()
        XCTAssertEqual(game.currentPosition.removedStones, [])
        XCTAssertTrue(state.isBusy, "Cached overview assignment must not settle a fresh-snapshot wait.")
        XCTAssertTrue(state.requiresScoringRefresh)

        var otherData = try XCTUnwrap(game.gameData)
        otherData.gameId = 27_053_413
        let otherGame = Game(ogsGame: otherData)
        service.connect(to: otherGame, owner: .explicit(UUID()))
        var otherRawData = rawData
        otherRawData["game_id"] = otherData.gameId
        socket.serverEventCallback?("game/27053413/gamedata", otherRawData)
        drainMainQueue()
        XCTAssertTrue(state.isBusy, "Another game's authoritative snapshot must not unlock this game.")

        let expected = selected
        var refreshedData = rawData
        refreshedData["removed"] = BoardPosition.positionString(fromPoints: expected)
        var observedAfterApplication = false
        let applied = service.scoringSnapshots(game: game).sink(
            receiveCompletion: { _ in }, receiveValue: {
                observedAfterApplication = game.currentPosition.removedStones == expected
            }
        )
        socket.serverEventCallback?("game/27053412/gamedata", refreshedData)
        drainMainQueue()
        applied.cancel()
        XCTAssertTrue(observedAfterApplication)
        XCTAssertFalse(state.blocksGameActions)
        XCTAssertEqual(state.scoringNotice, .refreshed)
        XCTAssertEqual(selected, expected, "Recovery does not auto-clear or repeat the uncertain toggle.")
        XCTAssertEqual(socket.commands.filter { $0 == "game/removed_stones/set" }.count, 1)
    }

    @MainActor
    func testSameGroupCanBeExplicitlyResubmittedUsingRefreshedStoneState() throws {
        for firstCommandWasApplied in [false, true] {
            let (game, service, socket, rawData) = try scoringFixture()
            let deadline = PassthroughSubject<Void, Never>()
            let state = GameControlState(scoringDeadline: { deadline.eraseToAnyPublisher() })
            let points: Set<[Int]> = [[1, 2]]
            var selected = points
            game.currentPosition.removedStones = []
            state.toggleRemovedStones(selected, game: game, using: service) {
                selected.removeAll()
            }
            deadline.send(())
            drainMainQueue()
            state.refreshScoringState()
            var snapshot = rawData
            snapshot["removed"] = firstCommandWasApplied
                ? BoardPosition.positionString(fromPoints: points) : ""
            socket.serverEventCallback?("game/27053412/gamedata", snapshot)
            drainMainQueue()
            XCTAssertEqual(selected, points)
            XCTAssertEqual(socket.removedStonePayloads.count, 1)

            // This explicit board action uses the same retained selection.
            // It must run even though no Set value changed, and must derive
            // its new intent from the refreshed server state rather than replay
            // the first command's old add/remove decision.
            state.toggleRemovedStones(selected, game: game, using: service) {
                selected.removeAll()
            }
            XCTAssertEqual(socket.removedStonePayloads.count, 2)
            XCTAssertEqual(
                socket.removedStonePayloads.last?["removed"] as? Int,
                firstCommandWasApplied ? 0 : 1
            )
            XCTAssertTrue(state.isBusy)
            let expected: Set<[Int]> = firstCommandWasApplied ? [] : points
            socket.serverEventCallback?("game/27053412/removed_stones", [
                "all_removed": BoardPosition.positionString(fromPoints: expected)
            ])
            drainMainQueue()
            XCTAssertFalse(state.blocksGameActions)
            XCTAssertEqual(game.currentPosition.removedStones, expected)
            XCTAssertTrue(selected.isEmpty)
        }
    }

    @MainActor
    func testSubmittedStoneSoundsAtCommitAndItsEchoPlaysNothing() throws {
        let (game, service, socket) = try liveMoveFixture()
        let sounds = SoundCounter()
        let observation = observeStoneSounds(of: game, counter: sounds)
        defer { observation.forEach { $0.cancel() } }
        let haptics = HapticsRecorder()
        let state = GameControlState(haptics: haptics)

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        XCTAssertEqual(socket.moves.count, 1)
        XCTAssertEqual(sounds.plays, 1, "The stone sounds as it is sent, not a round trip later")
        XCTAssertEqual(haptics.events, ["commit"], "One impact with the click")

        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(1, 2))
        XCTAssertEqual(sounds.plays, 1, "OGS's echo plays nothing again")
        XCTAssertEqual(sounds.schedules, 0)
        XCTAssertEqual(haptics.events, ["commit"], "Nor does it play a haptic")
    }

    @MainActor
    func testRefusedStoneIsWithdrawnSoNothingStaleSilencesTheNextMove() throws {
        let (game, service, socket) = try liveMoveFixture()
        let sounds = SoundCounter()
        var events = [String]()
        let observation = observeStoneSounds(of: game, counter: sounds) + [
            game.moveCommits.sink { commit in
                switch commit {
                case .committed: events.append("committed")
                case .committedElsewhere: events.append("elsewhere")
                case .withdrawn: events.append("withdrawn")
                }
            },
        ]
        defer { observation.forEach { $0.cancel() } }
        let haptics = HapticsRecorder()
        let state = GameControlState(haptics: haptics)

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["error": "refused"])
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(events, ["committed", "withdrawn"])
        XCTAssertEqual(haptics.events, ["commit", "refusal"], "The impact already played, so an error follows")

        // Even the same stone, arriving later as a move, sounds again.
        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        XCTAssertEqual(sounds.plays, 2)
    }

    @MainActor
    func testPassesAndMovesSentWhileOfflineCommitNothing() throws {
        let (game, service, socket) = try liveMoveFixture()
        var commits = 0
        let observation = game.moveCommits.sink { _ in commits += 1 }
        defer { observation.cancel() }
        let haptics = HapticsRecorder()
        let state = GameControlState(haptics: haptics)

        XCTAssertTrue(state.submitMove(.pass, game: game, using: service, reviewCoordinator: nil) {})
        XCTAssertEqual(commits, 0, "A pass stays silent")
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["error": "refused"])
        drainMainQueue()
        XCTAssertEqual(commits, 0, "Nothing was committed, so nothing is withdrawn")

        socket.status = .reconnecting
        socket.onStatusChanged?()
        drainMainQueue()
        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        XCTAssertEqual(commits, 0, "A socket that is down fails the move with not_sent")
        XCTAssertTrue(haptics.events.isEmpty, "No impact without a commit, and no error after one")

        socket.status = .connected
        socket.onStatusChanged?()
        drainMainQueue()
        let emptyGame = Game(width: 9, height: 9, blackName: "black", whiteName: "white", gameId: .OGS(3))
        var emptyGameCommits = 0
        let emptyObservation = emptyGame.moveCommits.sink { _ in emptyGameCommits += 1 }
        defer { emptyObservation.cancel() }
        let emptyGameState = GameControlState(haptics: haptics)
        XCTAssertTrue(emptyGameState.submitMove(.placeStone(1, 2), game: emptyGame, using: service, reviewCoordinator: nil) {})
        drainMainQueue()
        XCTAssertEqual(emptyGameCommits, 0, "A game without data fails before anything is sent")
        XCTAssertTrue(emptyGame.sentMoves.isEmpty)
        XCTAssertTrue(haptics.events.isEmpty)
    }

    @MainActor
    func testAnswerLostAfterTheEchoIsNoRefusal() throws {
        let (game, service, socket) = try liveMoveFixture()
        let sounds = SoundCounter()
        var withdrawals = 0
        let observation = observeStoneSounds(of: game, counter: sounds) + [
            game.moveCommits.sink { if case .withdrawn = $0 { withdrawals += 1 } },
        ]
        defer { observation.forEach { $0.cancel() } }
        let haptics = HapticsRecorder()
        let state = GameControlState(haptics: haptics)

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        // OGS takes the move and echoes it, then the socket drops before its answer.
        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["connection": "WebSocket connection closed"])
        drainMainQueue()
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(withdrawals, 0)
        XCTAssertEqual(haptics.events, ["commit"], "No error for a stone on the board")
        XCTAssertEqual(sounds.plays, 1)
    }

    @MainActor
    func testUnansweredMoveKeepsItsCommitForALateEcho() throws {
        let (game, service, socket) = try liveMoveFixture()
        let sounds = SoundCounter()
        var withdrawals = 0
        let observation = observeStoneSounds(of: game, counter: sounds) + [
            game.moveCommits.sink { if case .withdrawn = $0 { withdrawals += 1 } },
        ]
        defer { observation.forEach { $0.cancel() } }
        let haptics = HapticsRecorder()
        let state = GameControlState(haptics: haptics)

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["timeout": "No WebSocket response received within 30 seconds"])
        drainMainQueue()
        XCTAssertFalse(state.isBusy, "The controls are free again")
        XCTAssertEqual(withdrawals, 0, "OGS may have taken the move")
        XCTAssertEqual(haptics.events, ["commit"])

        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        XCTAssertEqual(sounds.plays, 1, "The late echo does not click again")
    }

    @MainActor
    func testCommitInOneWindowReachesTheOtherWindowsModel() throws {
        let payload = try liveGamePayload()
        let (game, service, socket) = try openWindow(on: payload)
        // Each scene keeps its own service, as OGSService.instances does.
        let (otherGame, otherService, otherSocket) = try openWindow(on: payload)
        defer { withExtendedLifetime(otherService) {} }
        XCTAssertFalse(game === otherGame, "Each window has its own model")
        let sounds = SoundCounter()
        let otherSounds = SoundCounter()
        var otherEvents = [String]()
        let observation = observeStoneSounds(of: game, counter: sounds)
            + observeStoneSounds(of: otherGame, counter: otherSounds) + [
                otherGame.moveCommits.sink { commit in
                    switch commit {
                    case .committed: otherEvents.append("committed")
                    case .committedElsewhere: otherEvents.append("elsewhere")
                    case .withdrawn: otherEvents.append("withdrawn")
                    }
                },
            ]
        defer { observation.forEach { $0.cancel() } }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        XCTAssertEqual(otherEvents, ["elsewhere"])
        XCTAssertEqual(otherGame.sentMoves.count, 1, "Its countdown holds too")
        let gameID = try XCTUnwrap(game.ogsID)
        let echo = ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any]
        socket.deliver("game/\(gameID)/move", echo)
        otherSocket.deliver("game/\(gameID)/move", echo)
        XCTAssertEqual(sounds.plays, 1, "The window that sent the stone plays it")
        XCTAssertEqual(otherSounds.plays, 0, "And the other window's echo stays silent")
    }

    @MainActor
    func testRefusalReachesTheOtherWindowsModel() throws {
        let payload = try liveGamePayload()
        let (game, service, socket) = try openWindow(on: payload)
        let (otherGame, otherService, _) = try openWindow(on: payload)
        defer { withExtendedLifetime(otherService) {} }
        var otherEvents = [String]()
        let observation = otherGame.moveCommits.sink { commit in
            if case .withdrawn = commit { otherEvents.append("withdrawn") }
        }
        defer { observation.cancel() }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["move": "illegal move"])
        drainMainQueue()
        XCTAssertEqual(otherEvents, ["withdrawn"])
        XCTAssertTrue(otherGame.sentMoves.isEmpty)
    }

    func testLiveGamesTableStaysBoundedAsGamesComeAndGo() {
        // As the public games list cycles, models come and go.
        for index in 0..<300 {
            Game(width: 9, height: 9, blackName: "black", whiteName: "white", gameId: .OGS(980_000 + index))
                .joinLiveGames()
        }
        let kept = Game(width: 9, height: 9, blackName: "black", whiteName: "white", gameId: .OGS(987_002))
        kept.joinLiveGames()
        XCTAssertTrue(Game.liveGameIDs.contains(kept.ID))
        XCTAssertFalse(Game.liveGameIDs.contains(.OGS(980_000)), "Games whose models have gone are swept")
        XCTAssertLessThan(Game.liveGameIDs.count, 40)
    }

    @MainActor
    func testRefusalAfterTheSendingScreenMovesOnStillReachesTheOtherWindow() throws {
        let payload = try liveGamePayload()
        let (game, service, socket) = try openWindow(on: payload)
        let (otherGame, otherService, _) = try openWindow(on: payload)
        defer { withExtendedLifetime(otherService) {} }
        var otherEvents = [String]()
        let observation = otherGame.moveCommits.sink { commit in
            if case .withdrawn = commit { otherEvents.append("withdrawn") }
        }
        defer { observation.cancel() }
        let state = GameControlState()

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        // The sending window turns to another game before OGS answers.
        state.updateContext(gameID: .OGS(999), accountID: service.user?.id)
        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["move": "illegal move"])
        drainMainQueue()
        XCTAssertEqual(otherEvents, ["withdrawn"], "The other window does not keep waiting for an echo")
    }

    @MainActor
    func testLeavingTheGameKeepsTheCommitForItsEcho() throws {
        let (game, service, socket) = try liveMoveFixture()
        let sounds = SoundCounter()
        var events = [String]()
        let observation = observeStoneSounds(of: game, counter: sounds) + [
            game.moveCommits.sink { commit in
                switch commit {
                case .committed: events.append("committed")
                case .committedElsewhere: events.append("elsewhere")
                case .withdrawn: events.append("withdrawn")
                }
            },
        ]
        defer { observation.forEach { $0.cancel() } }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        let sentMoves = game.sentMoves
        // This window turns to another game. Its move has still gone to OGS.
        state.updateContext(gameID: .OGS(999), accountID: service.user?.id)
        drainMainQueue()
        XCTAssertEqual(events, ["committed"], "Another window on the game still expects the echo")
        XCTAssertEqual(game.sentMoves, sentMoves)
        XCTAssertEqual(sentMoves.count, 1)

        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        XCTAssertEqual(sounds.plays, 1, "So it plays nothing again there")
    }

    func testPendingStoneOnlyReadiesTheCommitImpact() {
        let haptics = HapticsRecorder()
        let touch = BoardTouchHaptics(haptics: haptics)
        touch.touchBegan()
        touch.touchEnded(placingPendingStone: true)
        XCTAssertEqual(haptics.events, ["prepare", "prepare"], "A pending stone is a preview, not a success")
        touch.touchBegan()
        touch.touchEnded(placingPendingStone: false)
        XCTAssertEqual(haptics.events, ["prepare", "prepare", "prepare"])
    }

    @MainActor
    func testVoiceCountdownSaysOnlyTheUsersOwnLastSeconds() throws {
        let (game, service, _) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        // As the game screen listens: the game still holds the old clock.
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 3)
        XCTAssertEqual(speech.spoken, ["3"])
        // The clock that ends Black's turn still shows Black's main time.
        // (A fresh overtime period is also a period's top, skipped anyway.)
        game.clock = try byoYomiClock(for: game, toMove: .white, mainLeft: 8, lastMove: 2_000)
        XCTAssertEqual(speech.spoken, ["3"], "The user's time left after their move is not said")
        game.clock = try byoYomiClock(for: game, toMove: .white, mainLeft: 7, lastMove: 2_000)
        XCTAssertEqual(speech.spoken, ["3"])
    }

    @MainActor
    func testVoiceCountdownHoldsAfterACommitAndResumesAfterARefusal() throws {
        let (game, service, socket) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        var now = Date()
        let announcer = VoiceCountdownAnnouncer(speaker: speech, now: { now })
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        let committedAt = try XCTUnwrap(game.sentMoves.last?.date)
        // Black's clock still ticks until OGS's turn-ending clock arrives.
        for (offset, left) in [(0.2, 3.0), (0.6, 2.0)] as [(TimeInterval, Double)] {
            now = committedAt.addingTimeInterval(offset)
            game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: left)
        }
        XCTAssertEqual(speech.spoken, [], "Nothing is said right after a commit")

        try XCTUnwrap(socket.moveCallbacks.first)(nil, ["error": "refused"])
        drainMainQueue()
        XCTAssertTrue(game.sentMoves.isEmpty)
        now = committedAt.addingTimeInterval(0.8)
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 2)
        XCTAssertEqual(speech.spoken, ["2"], "A refused move's turn goes on, and so does its count")
    }

    @MainActor
    func testRefusalOfOneWindowsMoveKeepsTheOthersCountdownHeld() throws {
        let payload = try liveGamePayload(byoYomiPeriod: 5)
        let (game, service, _) = try openWindow(on: payload)
        let (otherGame, otherService, otherSocket) = try openWindow(on: payload)
        defer { withExtendedLifetime(otherService) {} }
        let speech = SpeechRecorder()
        var now = Date()
        let announcer = VoiceCountdownAnnouncer(speaker: speech, now: { now })
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }
        let state = GameControlState(haptics: HapticsRecorder())
        let otherState = GameControlState(haptics: HapticsRecorder())

        // Two windows send different stones for the turn, 50 ms apart, and
        // OGS refuses the later one.
        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        let sentAt = try XCTUnwrap(game.sentMoves.first?.date)
        XCTAssertTrue(otherState.submitMove(.placeStone(3, 3), game: otherGame, using: otherService,
                                            reviewCoordinator: nil) {})
        try XCTUnwrap(otherSocket.moveCallbacks.first)(nil, ["move": "illegal move"])
        drainMainQueue()
        XCTAssertEqual(game.sentMoves.count, 1, "This window's move is still on its way")

        now = sentAt.addingTimeInterval(0.2)
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 3)
        XCTAssertEqual(speech.spoken, [], "So its countdown holds")
    }

    @MainActor
    func testVoiceCountdownResumesAfterTheHoldButNotOnceTheMoveIsApplied() throws {
        let (game, service, socket) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        var now = Date()
        let announcer = VoiceCountdownAnnouncer(speaker: speech, now: { now })
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        let committedAt = try XCTUnwrap(game.sentMoves.last?.date)
        now = committedAt.addingTimeInterval(1.5)
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 3)
        XCTAssertEqual(speech.spoken, ["3"], "OGS is slow and Black's clock is still running")

        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        now = committedAt.addingTimeInterval(1.8)
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 2)
        XCTAssertEqual(speech.spoken, ["3"], "The move is applied, so this clock is out of date")
    }

    @MainActor
    func testVoiceCountdownHoldEndsOnceTheBoardMovesOn() throws {
        let (game, service, socket) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        var now = Date()
        let announcer = VoiceCountdownAnnouncer(speaker: speech, now: { now })
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }
        let state = GameControlState(haptics: HapticsRecorder())

        XCTAssertTrue(state.submitMove(.placeStone(1, 2), game: game, using: service, reviewCoordinator: nil) {})
        let committedAt = try XCTUnwrap(game.sentMoves.last?.date)
        // OGS echoes the move and an instant bot replies at once.
        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/move", ["move_number": 1, "move": [2, 1, 1_000]] as [String: Any])
        socket.deliver("game/\(gameID)/move", ["move_number": 2, "move": [4, 4, 1_100]] as [String: Any])
        now = committedAt.addingTimeInterval(0.3)
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 3, lastMove: 3_000)
        XCTAssertEqual(speech.spoken, ["3"], "The next turn counts at once, within a second of the last move")
    }

    @MainActor
    func testVoiceCountdownStaysQuietBeforeTheClockStartsAndAfterTheGameEnds() throws {
        let (game, service, _) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        // Waiting for the first move, the time left stays as it is.
        for _ in 0..<2 {
            game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 5, started: false)
        }
        XCTAssertEqual(speech.spoken, [])
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 4)
        XCTAssertEqual(speech.spoken, ["4"])

        // A finishing snapshot stores its clock before its phase.
        game.gameData?.outcome = "Timeout"
        game.clock = try byoYomiClock(for: game, toMove: .black, mainLeft: 3)
        XCTAssertEqual(speech.spoken, ["4"])
    }

    @MainActor
    func testVoiceCountdownCountsASnapshotsClockFromNow() throws {
        var payload = try liveGamePayload(byoYomiPeriod: 5)
        let (game, service, socket) = try openWindow(on: payload)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        // On reconnecting, the snapshot's clock shows Black's 8 s as of the
        // last move, 5 s ago.
        var clock = try XCTUnwrap(payload["clock"] as? [String: Any])
        let time = ["thinking_time": 8, "periods": 5, "period_time": 5] as [String: Any]
        clock["black_time"] = time
        clock["white_time"] = time
        clock["last_move"] = Date().timeIntervalSince1970 * 1_000 - 5_000
        clock.removeValue(forKey: "expiration")
        payload["clock"] = clock
        let gameID = try XCTUnwrap(game.ogsID)
        socket.deliver("game/\(gameID)/gamedata", payload)
        XCTAssertEqual(speech.spoken, ["3"], "Not 8, the time left when the turn began")
    }

    @MainActor
    func testVoiceCountdownCountsAnOverviewsClockFromNow() throws {
        var payload = try liveGamePayload(byoYomiPeriod: 5)
        let (game, service, _) = try openWindow(on: payload)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        // Back in the foreground, the overview's game data shows Black's 8 s
        // as of the last move, 5 s ago.
        var clock = try XCTUnwrap(payload["clock"] as? [String: Any])
        let time = ["thinking_time": 8, "periods": 5, "period_time": 5] as [String: Any]
        clock["black_time"] = time
        clock["white_time"] = time
        clock["last_move"] = Date().timeIntervalSince1970 * 1_000 - 5_000
        clock.removeValue(forKey: "expiration")
        payload["clock"] = clock
        let gameID = try XCTUnwrap(game.ogsID)
        service.processOverview(overview: ["active_games": [["id": gameID, "json": payload] as [String: Any]]])
        XCTAssertEqual(speech.spoken, ["3"], "Not 8, the time left when the turn began")
    }

    @MainActor
    func testVoiceCountdownSaysEachLostOneSecondPeriod() throws {
        let (game, service, _) = try liveMoveFixture(byoYomiPeriod: 1)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        // Every overtime tick reads 1, the period's top. Each lost period is
        // said all the same, and the turn's start is not.
        for periodsLeft in [5, 4, 3, 2, 1] {
            game.clock = try byoYomiClock(for: game, toMove: .black, periodLeft: 1,
                                          periodsLeft: periodsLeft, periodTime: 1)
        }
        game.clock = try byoYomiClock(for: game, toMove: .black, periodLeft: 0, periodsLeft: 0, periodTime: 1)
        XCTAssertEqual(speech.spoken, ["1", "1", "1", "1", "0"])
    }

    @MainActor
    func testVoiceCountdownSkipsAByoYomiPeriodsTopAtTurnStart() throws {
        let (game, service, _) = try liveMoveFixture(byoYomiPeriod: 5)
        let speech = SpeechRecorder()
        let announcer = VoiceCountdownAnnouncer(speaker: speech)
        let userID = service.user?.id
        let observation = game.$clock.dropFirst().sink {
            announcer.clockChanged(to: $0, in: game, userID: userID)
        }
        defer { observation.cancel() }

        // In overtime each turn starts at the full period, as OGS sends it.
        for left in [5.0, 5.0, 4.0, 3.0] {
            game.clock = try byoYomiClock(for: game, toMove: .black, periodLeft: left)
        }
        XCTAssertEqual(speech.spoken, ["4", "3"])
        // A period running out mid-turn starts again from its top, said.
        for left in [2.0, 1.0, 5.0, 4.0] {
            game.clock = try byoYomiClock(for: game, toMove: .black, periodLeft: left)
        }
        XCTAssertEqual(speech.spoken, ["4", "3", "2", "1", "5", "4"])
        // The next turn starts at the top again.
        game.clock = try byoYomiClock(for: game, toMove: .white, periodLeft: 5, lastMove: 9_000)
        for left in [5.0, 4.0] {
            game.clock = try byoYomiClock(for: game, toMove: .black, periodLeft: left, lastMove: 12_000)
        }
        XCTAssertEqual(speech.spoken, ["4", "3", "2", "1", "5", "4", "4"])
    }

    /// The fixture's byo-yomi clock, with 5 s periods: the player to move
    /// has `mainLeft` seconds of main time, or in overtime `periodLeft`.
    private func byoYomiClock(
        for game: Game, toMove color: StoneColor, mainLeft: Double = 0,
        periodLeft: Double = 5, periodsLeft: Int = 5, periodTime: Double = 5,
        lastMove: Double = 1_000, started: Bool = true
    ) throws -> OGSClock {
        let black = try XCTUnwrap(game.blackPlayer?.id)
        let white = try XCTUnwrap(game.whitePlayer?.id)
        let time = ThinkingTime(
            thinkingTime: mainLeft, thinkingTimeLeft: mainLeft, periods: 5,
            periodsLeft: periodsLeft, periodTime: periodTime, periodTimeLeft: periodLeft
        )
        return OGSClock(
            blackTime: time, whiteTime: time, currentPlayerColor: color,
            lastMoveTime: lastMove, started: started, currentPlayerId: color == .black ? black : white,
            blackPlayerId: black, whitePlayerId: white
        )
    }

    /// A board's wiring of its stone sounds, as in SingleGameView.
    private func observeStoneSounds(of game: Game, counter: SoundCounter) -> [AnyCancellable] {
        let player = StonePlacementSoundPlayer(makePlayer: counter.makePlayer)
        return [
            game.moveApplied.sink { player.play(move: $0, theme: .standard, enabled: true) },
            game.moveCommits.sink { player.play(commit: $0, theme: .standard, enabled: true) },
        ]
    }

    /// An empty live 9x9 game with Black, the signed-in user, to move. With
    /// a period, its clock is byo-yomi with 30 s of main time and 5 periods.
    @MainActor
    private func liveMoveFixture(byoYomiPeriod: Int? = nil) throws -> (Game, OGSService, MoveSocket) {
        try openWindow(on: try liveGamePayload(byoYomiPeriod: byoYomiPeriod))
    }

    /// The fixture's game data: an empty live 9x9 game with Black to move.
    private func liveGamePayload(byoYomiPeriod: Int? = nil) throws -> [String: Any] {
        let bundle = Bundle(for: GameControlStateTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-25076729", withExtension: "json"))
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        payload["moves"] = [Any]()
        payload["phase"] = "play"
        payload["outcome"] = NSNull()
        payload["winner"] = NSNull()
        var clock = try XCTUnwrap(payload["clock"] as? [String: Any])
        clock["current_player"] = clock["black_player_id"]
        payload["clock"] = clock
        if let byoYomiPeriod {
            payload["time_control"] = [
                "system": "byoyomi", "time_control": "byoyomi", "speed": "blitz",
                "main_time": 30, "periods": 5, "period_time": byoYomiPeriod,
            ] as [String: Any]
        }
        return payload
    }

    /// One window on the game: its own service and socket, as each scene
    /// has, signed in as Black, with its own model of the game.
    @MainActor
    private func openWindow(on payload: [String: Any]) throws -> (Game, OGSService, MoveSocket) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let game = Game(ogsGame: try decoder.decode(
            OGSGame.self, from: JSONSerialization.data(withJSONObject: payload)
        ))
        let socket = MoveSocket()
        let suite = "com.honganhkhoa.Surround.MoveCommitTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            socket.serverEventCallback = nil
            socket.onStatusChanged = nil
        }
        var initial = OGSService.BootstrapState()
        initial.user = game.blackPlayer
        initial.isLoggedIn = true
        initial.socketStatus = .connected
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: preferences,
            ogsWebsocket: socket, connectsAutomatically: false,
            installsObservers: false, initialState: initial
        )
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))
        XCTAssertTrue(game.isUserTurn)
        return (game, service, socket)
    }

    @MainActor
    private func scoringFixture() throws -> (Game, OGSService, ScoringSocket, [String: Any]) {
        let bundle = Bundle(for: GameControlStateTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-27053412", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let game = Game(ogsGame: try decoder.decode(OGSGame.self, from: data))
        let socket = ScoringSocket()
        let suite = "com.honganhkhoa.Surround.ScoringTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            preferences.removePersistentDomain(forName: suite)
            socket.serverEventCallback = nil
            socket.onStatusChanged = nil
        }
        var initial = OGSService.BootstrapState()
        initial.user = game.blackPlayer
        initial.isLoggedIn = true
        initial.socketStatus = .connected
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: preferences,
            ogsWebsocket: socket, connectsAutomatically: false,
            installsObservers: false, initialState: initial
        )
        game.ogs = service
        service.connect(to: game, owner: .explicit(UUID()))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (game, service, socket, raw)
    }

    @MainActor
    private func drainMainQueue() {
        let drained = expectation(description: "Queued callbacks delivered")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
