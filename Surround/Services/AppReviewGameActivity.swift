import Foundation

/// Converts authoritative game evidence into signals for the review policy.
enum AppReviewGameActivity {
    /// An acknowledgment alone is insufficient: an unrelated update or undo can
    /// also release the existing submission publisher. Follow the authoritative
    /// ancestry in case the opponent has already replied to this move.
    static func confirmsSubmittedMove(
        _ move: Move,
        moveNumber: Int,
        from submittedPosition: BoardPosition,
        in confirmedPosition: BoardPosition
    ) -> Bool {
        var position: BoardPosition? = confirmedPosition
        while let current = position, current.lastMoveNumber > moveNumber {
            position = current.previousPosition
        }
        guard let position,
              position.lastMoveNumber == moveNumber,
              position.lastMove == move,
              position.lastMoveColor == submittedPosition.nextToMove,
              let previousPosition = position.previousPosition,
              previousPosition.lastMoveNumber == moveNumber - 1 else {
            return false
        }
        return previousPosition.hasTheSamePosition(with: submittedPosition)
    }

    /// A bare phase event can precede the final game data. Wait for the outcome
    /// so a cancelled game never becomes a review opportunity. Nil keeps the
    /// coordinator's ongoing baseline while final game data is arriving.
    static func phase(
        _ phase: OGSGamePhase?,
        authoritativePhase: OGSGamePhase?,
        outcome: String?
    ) -> AppReviewGamePhase? {
        switch phase {
        case .play:
            return .playing
        case .stoneRemoval:
            return .scoring
        case .finished:
            guard authoritativePhase == .finished,
                  let outcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !outcome.isEmpty else {
                return nil
            }
            switch outcome.lowercased() {
            case "cancellation", "canceled", "cancelled":
                return .cancelled
            default:
                return .finished
            }
        case nil:
            return nil
        }
    }
}
