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
    var nonDuplicatingMoveCoordinatesByLabel: [Int: [Int]]
    
    private init(position: BoardPosition, basePosition: BoardPosition, moves: [Move]) {
        self.position = position
        self.basePosition = basePosition
        self.moves = moves
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
        while !currentPosition.hasTheSamePosition(with: basePosition) {
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
    
    init(basePosition: BoardPosition, moves: [Move]) {
        var position = basePosition
        for move in moves {
            position = try! position.makeMove(move: move)
        }
        self.init(position: position, basePosition: basePosition, moves: moves)
    }
}
