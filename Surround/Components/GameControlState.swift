//
//  GameControlState.swift
//  Surround
//

import Foundation
import Combine

struct GameControlConfirmation: Identifiable {
    enum Kind {
        case pass
        case resume
        case resign
        case cancel
    }

    let id = UUID()
    let kind: Kind
    let gameID: GameID
    let accountID: Int?
}

struct GameRematchPresentation: Identifiable {
    let gameID: GameID
    let challenge: OGSChallengeTemplate

    var id: GameID { gameID }
}

/// Retained by the game screen, independently of its adaptive control rows.
/// Resetting this owner stops local observation; it cannot retract a command
/// that has already been sent to OGS.
@MainActor
final class GameControlState: ObservableObject {
    enum ScoringNotice: Equatable {
        case unconfirmed
        case refreshing
        case refreshed
    }

    private enum ScoringWaitResult {
        case confirmed
        case unconfirmed
    }

    private struct ScoringRecovery {
        let id = UUID()
        let context: Context
        let snapshot: () -> AnyPublisher<Void, Error>
        let phaseExit: AnyPublisher<Void, Never>
        let connection: AnyPublisher<OGSWebsocketStatus, Never>
        let refresh: () -> Void
    }

    private enum ScoringRecoverySignal: Equatable {
        case snapshot
        case phaseExit
    }

    private struct Context: Equatable {
        let gameID: GameID
        let accountID: Int?
    }

    private struct Request {
        let id: UUID
        let onCancel: () -> Void
        var cancellable: AnyCancellable?
    }

    @Published private(set) var isBusy = false
    @Published var confirmation: GameControlConfirmation?
    @Published var rematchPresentation: GameRematchPresentation?
    @Published private(set) var requiresScoringRefresh = false
    @Published private(set) var scoringNotice: ScoringNotice?

    var blocksGameActions: Bool { isBusy || requiresScoringRefresh }

    private var context: Context?
    private var request: Request?
    private var scoringRecovery: ScoringRecovery?
    private var scoringRecoveryObservation: AnyCancellable?
    private let scoringDeadline: () -> AnyPublisher<Void, Never>

    init(scoringDeadline: @escaping () -> AnyPublisher<Void, Never> = {
        Just(())
            .delay(for: .seconds(15), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }) {
        self.scoringDeadline = scoringDeadline
    }

    deinit {
        request?.cancellable?.cancel()
        let onCancel = request?.onCancel
        Task { @MainActor in onCancel?() }
    }

    func updateContext(gameID: GameID, accountID: Int?) {
        let newContext = Context(gameID: gameID, accountID: accountID)
        guard context != newContext else { return }
        context = newContext
        confirmation = nil
        rematchPresentation = nil
        clearScoringRecovery()
        requiresScoringRefresh = false
        scoringNotice = nil
        let previousRequest = request
        request = nil
        isBusy = false
        previousRequest?.cancellable?.cancel()
        previousRequest?.onCancel()
    }

    func matches(gameID: GameID, accountID: Int?) -> Bool {
        context == Context(gameID: gameID, accountID: accountID)
    }

    func confirm(
        _ kind: GameControlConfirmation.Kind,
        gameID: GameID,
        accountID: Int?
    ) {
        updateContext(gameID: gameID, accountID: accountID)
        guard !blocksGameActions else { return }
        confirmation = GameControlConfirmation(
            kind: kind, gameID: gameID, accountID: accountID
        )
    }

    func presentRematch(
        _ challenge: OGSChallengeTemplate,
        gameID: GameID,
        accountID: Int?
    ) {
        updateContext(gameID: gameID, accountID: accountID)
        guard !blocksGameActions else { return }
        rematchPresentation = GameRematchPresentation(
            gameID: gameID, challenge: challenge
        )
    }

    /// The publisher is created only after reserving the request, so a second
    /// control row cannot send the same action while the first one is pending.
    @discardableResult
    func performRequest<P: Publisher>(
        gameID: GameID,
        accountID: Int?,
        publisher: () -> P,
        receiveValue: @escaping (P.Output) -> Void,
        receiveFailure: @escaping (P.Failure) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        allowsScoringRecovery: Bool = false
    ) -> Bool {
        updateContext(gameID: gameID, accountID: accountID)
        guard !isBusy,
              !requiresScoringRefresh || allowsScoringRecovery else { return false }
        let requestID = UUID()
        request = Request(id: requestID, onCancel: onCancel)
        isBusy = true

        let cancellable = publisher()
            .prefix(1)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self, self.request?.id == requestID else { return }
                if case .failure(let error) = completion {
                    receiveFailure(error)
                }
                self.finishRequest(requestID)
            } receiveValue: { [weak self] value in
                guard let self, self.request?.id == requestID else { return }
                receiveValue(value)
                self.finishRequest(requestID)
            }
        if request?.id == requestID {
            request?.cancellable = cancellable
        } else {
            cancellable.cancel()
        }
        return true
    }

    private func finishRequest(_ requestID: UUID) {
        guard request?.id == requestID else { return }
        let completedRequest = request
        request = nil
        isBusy = false
        completedRequest?.cancellable?.cancel()
    }

    func submitMove(
        _ move: Move,
        game: Game,
        using ogs: OGSService,
        reviewCoordinator: AppReviewCoordinator?,
        onConfirmed: @escaping () -> Void
    ) {
        let userID = ogs.user?.id
        let submittedPosition = game.currentPosition
        let expectedMoveNumber = submittedPosition.lastMoveNumber + 1
        var reviewSubmission: AppReviewSubmission?

        performRequest(
            gameID: game.ID,
            accountID: userID,
            publisher: {
                if let gameID = game.ogsID,
                   gameID > 0, userID != nil,
                   game.gameData?.gameId == gameID,
                   game.isUserPlaying, game.isUserTurn {
                    reviewSubmission = reviewCoordinator?.beginMove(
                        gameID: gameID,
                        correspondence: game.gameData?.timeControl.speed
                            == .correspondence
                    )
                }
                return ogs.submitMove(move: move, forGame: game)
                    .zip(game.$currentPosition.filter {
                        $0.lastMoveNumber != submittedPosition.lastMoveNumber
                    }.setFailureType(to: Error.self))
            },
            receiveValue: { _, confirmedPosition in
                if let reviewSubmission {
                    let confirmed = ogs.user?.id == userID
                        && game.isUserPlaying
                        && AppReviewGameActivity.confirmsSubmittedMove(
                            move, moveNumber: expectedMoveNumber,
                            from: submittedPosition, in: confirmedPosition
                        )
                    reviewCoordinator?.finishMove(
                        reviewSubmission, succeeded: confirmed
                    )
                }
                onConfirmed()
            },
            receiveFailure: { _ in
                if let reviewSubmission {
                    reviewCoordinator?.finishMove(
                        reviewSubmission, succeeded: false
                    )
                }
            },
            onCancel: {
                if let reviewSubmission {
                    reviewCoordinator?.abandonMove(reviewSubmission)
                }
            }
        )
    }

    func toggleRemovedStones(
        _ stones: Set<[Int]>,
        game: Game,
        using ogs: OGSService,
        onConfirmed: @escaping () -> Void
    ) {
        guard !stones.isEmpty, game.gamePhase == .stoneRemoval else { return }
        let position = game.currentPosition
        let expected = stones.subtracting(position.removedStones ?? [])
        let phaseExit = ogs.scoringPhaseExits(game: game)
        let confirmation = position.$removedStones
            // Other players may change different groups in the same update.
            // Only the requested intersections acknowledge this toggle.
            .filter { ($0 ?? []).intersection(stones) == expected }
            .map { _ in () }
            .merge(with: phaseExit)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        performScoringRequest(
            gameID: game.ID,
            accountID: ogs.user?.id,
            confirmation: confirmation,
            connection: ogs.$socketStatus.eraseToAnyPublisher(),
            snapshot: { ogs.scoringSnapshots(game: game) },
            phaseExit: phaseExit,
            send: {
                // The service emits immediately. The retained waiter owns
                // confirmation; this local Future does not acknowledge OGS.
                _ = ogs.toggleRemovedStones(stones: stones, forGame: game)
            },
            refresh: { ogs.refreshScoringState(game: game) },
            onConfirmed: onConfirmed
        )
    }

    func acceptRemovedStones(game: Game, using ogs: OGSService) {
        guard game.gamePhase == .stoneRemoval,
              let color = game.userStoneColor else { return }
        let stones = game.currentPosition.removedStones ?? []
        guard game.removedStonesAccepted[color] != stones else { return }
        let acceptance = game.$removedStonesAccepted
            .filter { $0[color] == stones }
            .map { _ in () }
        let phaseExit = ogs.scoringPhaseExits(game: game)
        performScoringRequest(
            gameID: game.ID,
            accountID: ogs.user?.id,
            confirmation: acceptance.merge(with: phaseExit)
                .setFailureType(to: Error.self).eraseToAnyPublisher(),
            connection: ogs.$socketStatus.eraseToAnyPublisher(),
            snapshot: { ogs.scoringSnapshots(game: game) },
            phaseExit: phaseExit,
            send: { ogs.acceptRemovedStone(game: game) },
            refresh: { ogs.refreshScoringState(game: game) }
        )
    }

    func resumeGameFromStoneRemoval(game: Game, using ogs: OGSService) {
        guard game.gamePhase == .stoneRemoval else { return }
        let phaseExit = ogs.scoringPhaseExits(game: game)
        performScoringRequest(
            gameID: game.ID,
            accountID: ogs.user?.id,
            confirmation: phaseExit.setFailureType(to: Error.self)
                .eraseToAnyPublisher(),
            connection: ogs.$socketStatus.eraseToAnyPublisher(),
            snapshot: { ogs.scoringSnapshots(game: game) },
            phaseExit: phaseExit,
            send: { ogs.resumeGameFromStoneRemoval(game: game) },
            refresh: { ogs.refreshScoringState(game: game) }
        )
    }

    /// Subscribe before sending, so even an immediate response is observed.
    /// This seam also lets tests drive silence, disconnects, and fresh snapshots
    /// without sending an OGS command or waiting for a wall-clock timeout.
    @discardableResult
    func performScoringRequest(
        gameID: GameID,
        accountID: Int?,
        confirmation: AnyPublisher<Void, Error>,
        connection: AnyPublisher<OGSWebsocketStatus, Never>,
        snapshot: @escaping () -> AnyPublisher<Void, Error>,
        phaseExit: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
        send: () -> Void,
        refresh: @escaping () -> Void,
        onConfirmed: @escaping () -> Void = {}
    ) -> Bool {
        updateContext(gameID: gameID, accountID: accountID)
        guard !blocksGameActions else { return false }
        let recovery = ScoringRecovery(
            context: Context(gameID: gameID, accountID: accountID),
            snapshot: snapshot, phaseExit: phaseExit,
            connection: connection, refresh: refresh
        )
        scoringRecovery = recovery
        scoringNotice = nil
        // Observe before sending and keep observing after the bounded wait.
        // Reconnects can supply gamedata without a manual Refresh action.
        observeScoringRecovery(recovery)
        let started = performRequest(
            gameID: gameID, accountID: accountID,
            publisher: { scoringWait(confirmation, connection: connection) },
            receiveValue: { [weak self] result in
                guard let self else { return }
                switch result {
                case .confirmed:
                    self.clearScoringRecovery()
                    onConfirmed()
                case .unconfirmed:
                    self.requiresScoringRefresh = true
                    self.scoringNotice = .unconfirmed
                }
            }
        )
        if started { send() }
        return started
    }

    private func observeScoringRecovery(_ recovery: ScoringRecovery) {
        scoringRecoveryObservation?.cancel()
        let recoveryID = recovery.id
        let recoveryContext = recovery.context
        let snapshots = recovery.snapshot()
            .map { ScoringRecoverySignal.snapshot }
            .catch { _ in Empty<ScoringRecoverySignal, Never>() }
        scoringRecoveryObservation = snapshots
            .merge(with: recovery.phaseExit.map { ScoringRecoverySignal.phaseExit })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard let self,
                      self.scoringRecovery?.id == recoveryID,
                      self.context == recoveryContext else { return }
                // During the original wait a phase exit is already a normal
                // confirmation. After uncertainty it instead ends recovery.
                if case .phaseExit = signal, !self.requiresScoringRefresh { return }

                // A fresh snapshot settles the current state, not whether the
                // old command succeeded. Never replay it or call onConfirmed.
                // Cancelling also invalidates any queued timeout/refresh result.
                if let requestID = self.request?.id {
                    self.finishRequest(requestID)
                }
                self.requiresScoringRefresh = false
                self.scoringNotice = signal == .snapshot ? .refreshed : nil
                self.clearScoringRecovery()
            }
    }

    private func clearScoringRecovery() {
        scoringRecovery = nil
        scoringRecoveryObservation?.cancel()
        scoringRecoveryObservation = nil
    }

    private func scoringWait(
        _ confirmation: AnyPublisher<Void, Error>,
        connection: AnyPublisher<OGSWebsocketStatus, Never>
    ) -> AnyPublisher<ScoringWaitResult, Never> {
        let confirmed = confirmation
            .map { ScoringWaitResult.confirmed }
            .catch { _ in Just(ScoringWaitResult.unconfirmed) }
        let disconnected = connection.filter { $0 != .connected }
            .map { _ in ScoringWaitResult.unconfirmed }
        let expired = scoringDeadline().map { ScoringWaitResult.unconfirmed }
        return confirmed.merge(with: disconnected, expired)
            .prefix(1).eraseToAnyPublisher()
    }

    func refreshScoringState() {
        guard requiresScoringRefresh, !isBusy,
              let recovery = scoringRecovery,
              recovery.context == context else { return }
        scoringNotice = .refreshing
        observeScoringRecovery(recovery)
        let started = performRequest(
            gameID: recovery.context.gameID,
            accountID: recovery.context.accountID,
            publisher: {
                scoringWait(recovery.snapshot(), connection: recovery.connection)
            },
            receiveValue: { [weak self] result in
                guard let self else { return }
                switch result {
                case .confirmed:
                    self.requiresScoringRefresh = false
                    self.scoringNotice = .refreshed
                    self.clearScoringRecovery()
                case .unconfirmed:
                    self.scoringNotice = .unconfirmed
                }
            },
            allowsScoringRecovery: true
        )
        if started { recovery.refresh() }
    }

    func dismissScoringNotice() {
        guard !requiresScoringRefresh else { return }
        scoringNotice = nil
    }

    func estimateTerritory(game: Game, using ogs: OGSService) {
        let position = game.currentPosition
        let revision = position.scoringRevision
        let phase = game.gamePhase
        performRequest(
            gameID: game.ID,
            accountID: ogs.user?.id,
            publisher: { position.estimateTerritory(on: game.computeQueue) },
            receiveValue: { estimatedTerritory in
                guard game.currentPosition === position,
                      position.scoringRevision == revision,
                      game.gamePhase == phase else { return }
                position.estimatedScores = estimatedTerritory
            }
        )
    }
}
