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

    private enum Failure: Error {
        case rejected
    }

    private let firstGame = GameID.OGS(1)
    private let secondGame = GameID.OGS(2)
    private let accountID = 100

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
