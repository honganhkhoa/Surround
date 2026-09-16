//
//  GameDetailConnectionCoordinator.swift
//  Surround
//

import Foundation
import Combine

/// Owns the realtime game subscription for one `GameDetailView` identity.
///
/// SwiftUI retains this owner in `@State` while a pushed destination covers the
/// game. Destroying the host route releases its claim even when the game does
/// not appear again. The service remains the source of truth for the game.
final class GameDetailConnectionCoordinator {
    let ownerID: UUID
    private(set) var connectedGameID: Int?
    private weak var connectedService: OGSService?
    private weak var requestedService: OGSService?
    private var requestedGame: Game?
    private var isOwnerActive = true
    private var isRoutePresent = true
    private weak var observedRouter: StackRouter?
    private var owningRoute: StackRoute?
    private var lifetimeObservation: AnyCancellable?
    private var onCanonicalGame: ((Game) -> Void)?

    init(ownerID: UUID = UUID()) {
        self.ownerID = ownerID
    }

    deinit {
        releaseOwnedConnection()
    }

    /// Observe the stack directly: a covered SwiftUI view need not appear again
    /// for a tab switch to suspend or resume its connection.
    func observeLifetime(
        in router: StackRouter,
        route: StackRoute?,
        onCanonicalGame: @escaping (Game) -> Void
    ) {
        guard route.map({ router.path.contains($0) }) ?? true else {
            release()
            return
        }
        isRoutePresent = true
        self.onCanonicalGame = onCanonicalGame
        guard observedRouter !== router || owningRoute != route else { return }
        lifetimeObservation?.cancel()
        observedRouter = router
        owningRoute = route
        lifetimeObservation = Publishers.CombineLatest(router.$isActive, router.$path)
            .sink { [weak self] isActive, path in
                guard let self else { return }
                if let route, !path.contains(route) {
                    self.release()
                    return
                }
                self.isOwnerActive = isActive
                self.updateConnection()
            }
    }

    /// Acquires the requested game and returns the service's canonical model.
    ///
    /// Switching games releases the previous claim first. Reacquiring the same
    /// id is intentionally idempotent because it uses the same owner token.
    @discardableResult
    func connect(to requestedGame: Game, using ogs: OGSService) -> Game {
        guard isRoutePresent else { return requestedGame }
        guard let requestedGameID = requestedGame.ogsID else {
            release()
            return requestedGame
        }

        if connectedGameID != requestedGameID || connectedService !== ogs {
            releaseOwnedConnection()
        }

        self.requestedGame = requestedGame
        requestedService = ogs
        return updateConnection() ?? requestedGame
    }

    /// End this route's intent. Activity changes cannot reacquire it afterward.
    func release() {
        isRoutePresent = false
        isOwnerActive = false
        lifetimeObservation?.cancel()
        lifetimeObservation = nil
        observedRouter = nil
        owningRoute = nil
        requestedGame = nil
        requestedService = nil
        onCanonicalGame = nil
        releaseOwnedConnection()
    }

    @discardableResult
    private func updateConnection() -> Game? {
        guard isOwnerActive, let requestedGame, let ogs = requestedService else {
            releaseOwnedConnection()
            return self.requestedGame
        }

        let canonicalGame = ogs.connect(
            to: requestedGame,
            withChat: true,
            owner: .detail(ownerID)
        )
        connectedService = ogs
        connectedGameID = canonicalGame.ogsID
        self.requestedGame = canonicalGame
        onCanonicalGame?(canonicalGame)
        return canonicalGame
    }

    private func releaseOwnedConnection() {
        guard let connectedGameID else {
            return
        }

        let service = connectedService
        self.connectedGameID = nil
        connectedService = nil
        service?.releaseConnection(
            gameID: connectedGameID,
            owner: .detail(ownerID)
        )
    }
}
