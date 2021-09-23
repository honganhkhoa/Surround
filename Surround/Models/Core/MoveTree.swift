//
//  MoveTree.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/07/2021.
//

import Foundation

class MoveTree: ObservableObject {
    var initialPosition: BoardPosition
    var largestLastMoveNumber: Int
    var positionsByLastMoveNumber: [Int: [BoardPosition?]] = [:]
    var moveNumberRange: Range<Int> {
        return initialPosition.lastMoveNumber..<largestLastMoveNumber + 1
    }
    var levelByBoardPosition: [ObjectIdentifier: Int] = [:]
    var indexByBoardPosition: [ObjectIdentifier: Int] = [:]
    var nextPositionsByPosition: [ObjectIdentifier: [BoardPosition]] = [:]
    var maxLevel = 0
    
    init(position: BoardPosition) {
        initialPosition = position
        largestLastMoveNumber = initialPosition.lastMoveNumber
        positionsByLastMoveNumber[initialPosition.lastMoveNumber] = [initialPosition]
        levelByBoardPosition[ObjectIdentifier(initialPosition)] = 0
        indexByBoardPosition[ObjectIdentifier(initialPosition)] = 0
    }
    
    func removeData(forPosition position: BoardPosition) {
        let identifier = ObjectIdentifier(position)
        indexByBoardPosition.removeValue(forKey: identifier)
        levelByBoardPosition.removeValue(forKey: identifier)
        if let nextPositions = nextPositionsByPosition[identifier] {
            for nextPosition in nextPositions {
                self.removeData(forPosition: nextPosition)
            }
        }
        nextPositionsByPosition.removeValue(forKey: identifier)
    }
    
    func register(newPosition: BoardPosition, fromPosition: BoardPosition, mainBranch: Bool) -> BoardPosition {
        if let fromIndex = indexByBoardPosition[ObjectIdentifier(fromPosition)] {
            if let existingPositions = positionsByLastMoveNumber[newPosition.lastMoveNumber] {
                if mainBranch {
                    if let existingPosition = existingPositions[0] {
                        if existingPosition.hasTheSamePosition(with: newPosition) {
                            return existingPosition
                        } else {
                            self.removeData(forPosition: existingPosition)
                        }
                    }
                    positionsByLastMoveNumber[newPosition.lastMoveNumber]?[0] = newPosition
                    indexByBoardPosition[ObjectIdentifier(newPosition)] = 0
                    levelByBoardPosition[ObjectIdentifier(newPosition)] = 0
                    return newPosition
                } else {
                    for existingPosition in existingPositions {
                        if existingPosition?.hasTheSamePosition(with: newPosition) ?? false {
                            if existingPosition?.previousPosition === fromPosition {
                                return existingPosition!
                            }
                        }
                    }
                    var index = 0
                    while index < existingPositions.count {
                        if let existingPosition = existingPositions[index] {
                            if let previousPosition = existingPosition.previousPosition {
                                if let previousIndex = indexByBoardPosition[ObjectIdentifier(previousPosition)] {
                                    if previousIndex > fromIndex {
                                        break
                                    }
                                }
                            }
                        }
                        index += 1
                    }
                    positionsByLastMoveNumber[newPosition.lastMoveNumber]?.insert(newPosition, at: index)
                    indexByBoardPosition[ObjectIdentifier(newPosition)] = index
                    if let positions = positionsByLastMoveNumber[newPosition.lastMoveNumber] {
                        for newIndex in (index+1)..<positions.count {
                            indexByBoardPosition[ObjectIdentifier(positions[newIndex]!)] = newIndex
                        }
                    }
                }
            } else {
                if mainBranch {
                    positionsByLastMoveNumber[newPosition.lastMoveNumber] = [newPosition]
                    indexByBoardPosition[ObjectIdentifier(newPosition)] = 0
                    levelByBoardPosition[ObjectIdentifier(newPosition)] = 0
                } else {
                    positionsByLastMoveNumber[newPosition.lastMoveNumber] = [nil, newPosition]
                    indexByBoardPosition[ObjectIdentifier(newPosition)] = 1
                    levelByBoardPosition[ObjectIdentifier(newPosition)] = 1
                    maxLevel = max(maxLevel, 1)
                }
                largestLastMoveNumber = max(largestLastMoveNumber, newPosition.lastMoveNumber)
            }
            let fromPositionIdentifier = ObjectIdentifier(fromPosition)
            if nextPositionsByPosition[fromPositionIdentifier] == nil {
                nextPositionsByPosition[fromPositionIdentifier] = [newPosition]
            } else {
                nextPositionsByPosition[fromPositionIdentifier]?.append(newPosition)
            }
            self.calculateLevels()
        }
        return newPosition
    }
    
    func calculateLevelsFromPosition(_ position: BoardPosition) {
        let positionIdentifier = ObjectIdentifier(position)
        guard let positions = positionsByLastMoveNumber[position.lastMoveNumber], let index = indexByBoardPosition[positionIdentifier], index > 0 else {
            return
        }
        
        let previousIndexPosition = positions[index - 1]
        
        guard let previousIndexLevel = previousIndexPosition == nil ? Optional(0) : levelByBoardPosition[ObjectIdentifier(previousIndexPosition!)] else {
            return
        }
        
        guard let previousPosition = position.previousPosition, let previousPositionLevel = levelByBoardPosition[ObjectIdentifier(previousPosition)] else {
            return
        }
        
        var newLevel = levelByBoardPosition[positionIdentifier] ?? index
        newLevel = max(newLevel, previousIndexLevel + 1)
        newLevel = max(newLevel, previousPositionLevel)
        
        if previousIndexPosition != nil, let highestNephew = nextPositionsByPosition[ObjectIdentifier(previousIndexPosition!)]?.last {
            if let highestNephewLevel = levelByBoardPosition[ObjectIdentifier(highestNephew)] {
                newLevel = max(newLevel, highestNephewLevel)
            }
        }
        
        levelByBoardPosition[positionIdentifier] = newLevel

        if let nextPositions = nextPositionsByPosition[positionIdentifier] {
            for nextPosition in nextPositions {
                self.calculateLevelsFromPosition(nextPosition)
            }
        }
        
        maxLevel = max(maxLevel, newLevel)
    }
    
    func calculateLevels() {
        maxLevel = 0
        for lastMoveNumber in moveNumberRange.reversed() {
            if let position = positionsByLastMoveNumber[lastMoveNumber]?[0] {
                if let nextPositions = nextPositionsByPosition[ObjectIdentifier(position)], nextPositions.count > 0 {
                    for nextPosition in nextPositions {
                        self.calculateLevelsFromPosition(nextPosition)
                    }
                }
            }
        }
    }
    
    func variation(to position: BoardPosition) -> Variation? {
        guard indexByBoardPosition[ObjectIdentifier(position)] ?? 0 != 0 else {
            return nil
        }
        var basePosition = Optional(position)
        while basePosition != nil {
            if let basePosition = basePosition, let index = indexByBoardPosition[ObjectIdentifier(basePosition)], index == 0 {
                return Variation(position: position, basePosition: basePosition)
            }
            basePosition = basePosition?.previousPosition
        }
        return nil
    }
}
