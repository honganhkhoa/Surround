//
//  Variation.swift
//  Surround
//
//  Created by Anh Khoa Hong on 31/12/2020.
//

import Foundation

struct Variation {
    var basePosition: BoardPosition
    var position: BoardPosition
    var moves: [Move]
    var markups: BoardMarkups
    var nonDuplicatingMoveCoordinatesByLabel: [Int: [Int]]
    
    init(
        position: BoardPosition,
        basePosition: BoardPosition,
        moves: [Move],
        markups: BoardMarkups = [:]
    ) {
        self.position = position
        self.basePosition = basePosition
        self.moves = moves
        self.markups = markups
        self.nonDuplicatingMoveCoordinatesByLabel = [Int: [Int]]()
        var positions = Set<[Int]>()
        for (index, move) in moves.enumerated() {
            if case .placeStone(let row, let column) = move {
                if !positions.contains([row, column]) {
                    positions.insert([row, column])
                    self.nonDuplicatingMoveCoordinatesByLabel[index + 1] = [row, column]
                }
            }
        }
    }
    
    init(position: BoardPosition, basePosition: BoardPosition) {
        var moves = [Move]()
        var currentPosition = position
        // Board equality is not path identity. In particular, pass moves (and
        // legal self-captures) can leave the stones unchanged, so stopping on
        // equal board contents would truncate the variation.
        while currentPosition !== basePosition {
            if let lastMove = currentPosition.lastMove {
                moves.insert(lastMove, at: 0)
                if currentPosition.previousPosition != nil {
                    currentPosition = currentPosition.previousPosition!
                } else {
                    break
                }
            } else {
                break
            }
        }
        self.init(position: position, basePosition: basePosition, moves: moves)
    }
    
    init(
        basePosition: BoardPosition,
        moves: [Move],
        allowsSelfCapture: Bool = false
    ) throws {
        var position = basePosition
        for move in moves {
            position = try position.makeMove(
                move: move,
                allowsSelfCapture: allowsSelfCapture
            )
        }
        self.init(position: position, basePosition: basePosition, moves: moves)
    }
}

enum BoardStoneIndicatorMode: Equatable {
    case positionIndicators
    case variationNumberings

    init(variation: Variation?) {
        self = variation?.moves.isEmpty == false
            ? .variationNumberings
            : .positionIndicators
    }
}

/// Explicit annotations replace automatic point labels, while a pending move
/// keeps its confirmation marker visible until the player submits it.
struct BoardPointIndicatorPolicy: Equatable {
    var markups: BoardMarkups

    func showsLastMove(at point: BoardPoint, pending: Bool) -> Bool {
        pending || !hasVisibleMarkup(at: point)
    }

    func showsVariationNumber(at point: BoardPoint) -> Bool {
        !hasVisibleMarkup(at: point)
    }

    /// Status points must come from the indicators actually drawn by the
    /// board. An annotation returns unchanged when that transient status ends.
    func showsMarkup(
        at point: BoardPoint,
        pendingMove: BoardPoint? = nil,
        undoPoints: Set<BoardPoint> = []
    ) -> Bool {
        point != pendingMove && !undoPoints.contains(point)
    }

    private func hasVisibleMarkup(at point: BoardPoint) -> Bool {
        markups[point]?.isVisible == true
    }
}

/// The automatic indicators a board draws, worked out once so the stones and
/// the annotation overlay agree on every point: undo glyphs, the last move's
/// ring or the pending move's cross, and the annotations they leave visible.
struct BoardIndicatorPlan: Equatable {
    struct LastMove: Equatable {
        var point: BoardPoint
        var pending: Bool
    }

    /// Explicit annotations, which replace automatic labels at their points.
    let policy: BoardPointIndicatorPolicy
    /// Undo requests on stones. Each glyph takes the place of the point's
    /// score square, last-move ring and annotation.
    let undoPoints: [BoardPoint]
    /// The ring or pending cross actually drawn, if any.
    let lastMove: LastMove?
    /// Annotations left visible; a status point's returns when it ends.
    let visibleMarkups: BoardMarkups

    init(
        position: BoardPosition,
        variation: Variation?,
        markups: BoardMarkups,
        undoRequestCoordinates: [[Int]] = [],
        isLastMovePending: Bool = false,
        showsLastMove: Bool = true
    ) {
        let policy = BoardPointIndicatorPolicy(markups: markups)
        self.policy = policy
        // A variation numbers its own moves; status indicators do not apply.
        guard BoardStoneIndicatorMode(variation: variation) == .positionIndicators else {
            undoPoints = []
            lastMove = nil
            visibleMarkups = markups
            return
        }
        let undoPoints = undoRequestCoordinates.compactMap { coordinate -> BoardPoint? in
            guard coordinate.count == 2,
                  coordinate[0] >= 0, coordinate[0] < position.height,
                  coordinate[1] >= 0, coordinate[1] < position.width,
                  case .hasStone = position[coordinate[0], coordinate[1]] else { return nil }
            return BoardPoint(row: coordinate[0], column: coordinate[1])
        }
        self.undoPoints = undoPoints
        var lastMove: LastMove?
        // The ring yields to an ownership square, an undo glyph or an
        // annotation on its point; a pending cross yields to none but squares.
        if showsLastMove, case .placeStone(let row, let column) = position.lastMove,
           case .hasStone = position[row, column],
           !position.hasOwnershipMark(atRow: row, column: column) {
            let point = BoardPoint(row: row, column: column)
            if !undoPoints.contains(point), policy.showsLastMove(at: point, pending: isLastMovePending) {
                lastMove = LastMove(point: point, pending: isLastMovePending)
            }
        }
        self.lastMove = lastMove
        let pendingPoint = lastMove?.pending == true ? lastMove?.point : nil
        let undoSet = Set(undoPoints)
        visibleMarkups = markups.filter {
            policy.showsMarkup(at: $0.key, pendingMove: pendingPoint, undoPoints: undoSet)
        }
    }
}
