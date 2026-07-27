//
//  GameDetailConnectionCoordinator.swift
//  Surround
//

import Foundation

/// Owns the realtime game subscription for one `GameDetailView` identity.
///
/// This is value state rather than an observable view model: SwiftUI keeps the
/// value (and therefore its owner token) stable in `@State`, while the shared
/// `OGSService` remains the source of truth for the canonical `Game`.
struct GameDetailConnectionCoordinator {
    let ownerID: UUID
    private(set) var connectedGameID: Int?

    init(ownerID: UUID = UUID()) {
        self.ownerID = ownerID
    }

    /// Acquires the requested game and returns the service's canonical model.
    ///
    /// Switching games releases the previous claim first. Reacquiring the same
    /// id is intentionally idempotent because it uses the same owner token.
    @discardableResult
    mutating func connect(to requestedGame: Game, using ogs: OGSService) -> Game {
        guard let requestedGameID = requestedGame.ogsID else {
            release(using: ogs)
            return requestedGame
        }

        if connectedGameID != requestedGameID {
            release(using: ogs)
        }

        let canonicalGame = ogs.connect(
            to: requestedGame,
            withChat: true,
            owner: .detail(ownerID)
        )
        connectedGameID = requestedGameID
        return canonicalGame
    }

    /// Releases this detail view's current claim. Repeated calls are no-ops.
    mutating func release(using ogs: OGSService) {
        guard let connectedGameID else {
            return
        }

        self.connectedGameID = nil
        ogs.releaseConnection(
            gameID: connectedGameID,
            owner: .detail(ownerID)
        )
    }
}
