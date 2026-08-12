//
//  MoveTree.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/07/2021.
//

import Foundation

class MoveTree: ObservableObject {
    enum BranchDirection {
        case previous
        case next
    }

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
        levelByBoardPosition.removeValue(forKey: identifier)
        if let nextPositions = nextPositionsByPosition[identifier] {
            for nextPosition in nextPositions {
                self.removeData(forPosition: nextPosition)
            }
        }
        nextPositionsByPosition.removeValue(forKey: identifier)
        if let index = indexByBoardPosition[identifier] {
            positionsByLastMoveNumber[position.lastMoveNumber]?.remove(at: index)
            if let positions = positionsByLastMoveNumber[position.lastMoveNumber] {
                if positions.count == 0 {
                    positionsByLastMoveNumber.removeValue(forKey: position.lastMoveNumber)
                } else {
                    for (index, position) in positions.enumerated() {
                        if let position = position {
                            indexByBoardPosition[ObjectIdentifier(position)] = index
                        }
                    }
                }
            }
        }
        indexByBoardPosition.removeValue(forKey: identifier)
    }

    /// Returns the nearest ancestor with at least two distinct, currently
    /// registered direct children.
    func nearestParentWithMultipleChildren(
        for position: BoardPosition
    ) -> BoardPosition? {
        guard indexByBoardPosition[ObjectIdentifier(position)] != nil else {
            return nil
        }

        var ancestor = position.previousPosition
        while let currentAncestor = ancestor {
            let ancestorIdentifier = ObjectIdentifier(currentAncestor)
            guard indexByBoardPosition[ancestorIdentifier] != nil else {
                return nil
            }

            var childIdentifiers = Set<ObjectIdentifier>()
            for child in nextPositionsByPosition[ancestorIdentifier] ?? [] {
                let childIdentifier = ObjectIdentifier(child)
                guard child.previousPosition === currentAncestor,
                      indexByBoardPosition[childIdentifier] != nil else {
                    continue
                }
                childIdentifiers.insert(childIdentifier)
            }
            if childIdentifiers.count > 1 {
                return currentAncestor
            }
            ancestor = currentAncestor.previousPosition
        }
        return nil
    }

    func adjacentBranch(
        from position: BoardPosition,
        direction: BranchDirection
    ) -> BoardPosition? {
        let positionIdentifier = ObjectIdentifier(position)
        guard indexByBoardPosition[positionIdentifier] != nil,
              let currentLevel = levelByBoardPosition[positionIdentifier],
              let positions = positionsByLastMoveNumber[position.lastMoveNumber] else {
            return nil
        }

        let candidates = positions.compactMap { candidate -> (position: BoardPosition, level: Int)? in
            guard let candidate, candidate !== position,
                  let level = levelByBoardPosition[ObjectIdentifier(candidate)] else {
                return nil
            }
            return (candidate, level)
        }

        switch direction {
        case .previous:
            return candidates
                .filter { $0.level < currentLevel }
                .max { $0.level < $1.level }?
                .position
        case .next:
            return candidates
                .filter { $0.level > currentLevel }
                .min { $0.level < $1.level }?
                .position
        }
    }

    func canRemoveBranch(startingAt position: BoardPosition) -> Bool {
        position !== initialPosition
            && (indexByBoardPosition[ObjectIdentifier(position)] ?? 0) > 0
            && position.previousPosition.map {
                indexByBoardPosition[ObjectIdentifier($0)] != nil
            } == true
    }

    @discardableResult
    func removeBranch(startingAt position: BoardPosition) -> BoardPosition? {
        guard canRemoveBranch(startingAt: position),
              let parentPosition = position.previousPosition,
              indexByBoardPosition[ObjectIdentifier(parentPosition)] != nil else {
            return nil
        }

        var subtreePositions = [BoardPosition]()
        var positionsToVisit = [position]
        var subtreeIdentifiers = Set<ObjectIdentifier>()
        while let currentPosition = positionsToVisit.popLast() {
            let currentIdentifier = ObjectIdentifier(currentPosition)
            guard subtreeIdentifiers.insert(currentIdentifier).inserted else {
                continue
            }
            subtreePositions.append(currentPosition)
            positionsToVisit.append(contentsOf: nextPositionsByPosition[currentIdentifier] ?? [])
        }

        guard subtreePositions.allSatisfy({
            guard let index = indexByBoardPosition[ObjectIdentifier($0)] else {
                return false
            }
            return index > 0
        }) else {
            return nil
        }

        objectWillChange.send()

        for identifier in Array(nextPositionsByPosition.keys) {
            guard var nextPositions = nextPositionsByPosition[identifier] else {
                continue
            }
            nextPositions.removeAll { subtreeIdentifiers.contains(ObjectIdentifier($0)) }
            if nextPositions.isEmpty {
                nextPositionsByPosition.removeValue(forKey: identifier)
            } else {
                nextPositionsByPosition[identifier] = nextPositions
            }
        }

        for identifier in subtreeIdentifiers {
            nextPositionsByPosition.removeValue(forKey: identifier)
            levelByBoardPosition.removeValue(forKey: identifier)
            indexByBoardPosition.removeValue(forKey: identifier)
        }

        let affectedMoveNumbers = Set(subtreePositions.map(\.lastMoveNumber))
        for moveNumber in affectedMoveNumbers {
            guard let existingPositions = positionsByLastMoveNumber[moveNumber] else {
                continue
            }
            let remainingPositions = existingPositions.filter { candidate in
                guard let candidate else {
                    return true
                }
                return !subtreeIdentifiers.contains(ObjectIdentifier(candidate))
            }
            if remainingPositions.compactMap({ $0 }).isEmpty {
                positionsByLastMoveNumber.removeValue(forKey: moveNumber)
            } else {
                positionsByLastMoveNumber[moveNumber] = remainingPositions
                for (index, remainingPosition) in remainingPositions.enumerated() {
                    if let remainingPosition {
                        indexByBoardPosition[ObjectIdentifier(remainingPosition)] = index
                    }
                }
            }
        }

        largestLastMoveNumber = positionsByLastMoveNumber
            .filter { $0.value.contains(where: { $0 != nil }) }
            .keys
            .max()
            ?? initialPosition.lastMoveNumber
        calculateLevels()
        return parentPosition
    }

    /// Converts an authoritative continuation into an analysis variation.
    ///
    /// The positions and their parent/child relationships stay intact so the
    /// undone line remains available in analysis. Inserting an empty main slot
    /// at every affected move number lets a later official continuation occupy
    /// index zero without deleting the preserved line.
    func demoteMainBranch(startingAt position: BoardPosition) {
        guard position !== initialPosition,
              indexByBoardPosition[ObjectIdentifier(position)] == 0 else {
            return
        }

        var mainBranchPositions = [BoardPosition]()
        var branchPosition: BoardPosition? = position
        while let currentPosition = branchPosition,
              indexByBoardPosition[ObjectIdentifier(currentPosition)] == 0 {
            mainBranchPositions.append(currentPosition)

            let nextPosition = positionsByLastMoveNumber[currentPosition.lastMoveNumber + 1]?
                .first ?? nil
            if nextPosition?.previousPosition === currentPosition {
                branchPosition = nextPosition
            } else {
                branchPosition = nil
            }
        }

        for mainBranchPosition in mainBranchPositions {
            let moveNumber = mainBranchPosition.lastMoveNumber
            guard var positions = positionsByLastMoveNumber[moveNumber],
                  let firstPosition = positions.first ?? nil,
                  firstPosition === mainBranchPosition else {
                continue
            }
            positions.insert(nil, at: 0)
            positionsByLastMoveNumber[moveNumber] = positions
            for (index, position) in positions.enumerated() {
                if let position {
                    indexByBoardPosition[ObjectIdentifier(position)] = index
                }
            }
        }

        calculateLevels()
    }
    
    func register(newPosition: BoardPosition, fromPosition: BoardPosition, mainBranch: Bool) -> BoardPosition {
        if let fromIndex = indexByBoardPosition[ObjectIdentifier(fromPosition)] {
            if let existingPositions = positionsByLastMoveNumber[newPosition.lastMoveNumber] {
                if mainBranch {
                    if let existingPosition = existingPositions.first ?? nil {
                        if existingPosition.hasTheSamePosition(with: newPosition) {
                            return existingPosition
                        } else {
                            self.removeData(forPosition: existingPosition)
                        }
                    } else {
                        var updatedPositions = existingPositions
                        if let promotedIndex = updatedPositions.firstIndex(where: {
                            $0?.previousPosition === fromPosition
                                && $0?.lastMove == newPosition.lastMove
                                && ($0?.hasTheSamePosition(with: newPosition) ?? false)
                        }), let promotedPosition = updatedPositions[promotedIndex] {
                            updatedPositions.remove(at: promotedIndex)
                            updatedPositions[0] = promotedPosition
                            positionsByLastMoveNumber[newPosition.lastMoveNumber] = updatedPositions
                            for (index, position) in updatedPositions.enumerated() {
                                if let position {
                                    indexByBoardPosition[ObjectIdentifier(position)] = index
                                }
                            }
                            let fromPositionIdentifier = ObjectIdentifier(fromPosition)
                            if var nextPositions = nextPositionsByPosition[fromPositionIdentifier] {
                                nextPositions.removeAll { $0 === promotedPosition }
                                nextPositions.insert(promotedPosition, at: 0)
                                nextPositionsByPosition[fromPositionIdentifier] = nextPositions
                            } else {
                                nextPositionsByPosition[fromPositionIdentifier] = [promotedPosition]
                            }
                            calculateLevels()
                            return promotedPosition
                        }

                        updatedPositions[0] = newPosition
                        positionsByLastMoveNumber[newPosition.lastMoveNumber] = updatedPositions
                        indexByBoardPosition[ObjectIdentifier(newPosition)] = 0
                        let fromPositionIdentifier = ObjectIdentifier(fromPosition)
                        if nextPositionsByPosition[fromPositionIdentifier] == nil {
                            nextPositionsByPosition[fromPositionIdentifier] = [newPosition]
                        } else {
                            nextPositionsByPosition[fromPositionIdentifier]?.insert(newPosition, at: 0)
                        }
                        calculateLevels()
                        return newPosition
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
        levelByBoardPosition.removeAll(keepingCapacity: true)
        for positions in positionsByLastMoveNumber.values {
            for (index, position) in positions.enumerated() {
                guard let position else {
                    continue
                }
                levelByBoardPosition[ObjectIdentifier(position)] = index
                maxLevel = max(maxLevel, index)
            }
        }
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
