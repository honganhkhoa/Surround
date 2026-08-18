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

    enum ConditionalVariationReplacementResult {
        case applied([ConditionalVariationID: BoardPosition])
        case rejected
    }

    private enum PositionSource: Hashable {
        case main
        case analysis
        case conditional(ConditionalVariationID)
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

    private var sourcesByBoardPosition =
        [ObjectIdentifier: Set<PositionSource>]()
    private var positionsByConditionalVariation =
        [ConditionalVariationID: [BoardPosition]]()
    
    init(position: BoardPosition) {
        initialPosition = position
        largestLastMoveNumber = initialPosition.lastMoveNumber
        positionsByLastMoveNumber[initialPosition.lastMoveNumber] = [initialPosition]
        levelByBoardPosition[ObjectIdentifier(initialPosition)] = 0
        indexByBoardPosition[ObjectIdentifier(initialPosition)] = 0
        sourcesByBoardPosition[ObjectIdentifier(initialPosition)] = [.main]
    }

    func contains(_ position: BoardPosition) -> Bool {
        indexByBoardPosition[ObjectIdentifier(position)] != nil
    }

    func isConditionalMovePosition(_ position: BoardPosition) -> Bool {
        !conditionalVariationIDs(for: position).isEmpty
    }

    /// Returns whether this position is the endpoint represented by a
    /// conditional-variation preview. Intermediate path positions retain
    /// conditional provenance, but are not themselves variation endpoints.
    func isConditionalVariationPosition(_ position: BoardPosition) -> Bool {
        conditionalVariationIDs(for: position).contains { variationID in
            positionsByConditionalVariation[variationID]?.last === position
        }
    }

    func conditionalVariationIDs(
        for position: BoardPosition
    ) -> Set<ConditionalVariationID> {
        Set((sourcesByBoardPosition[ObjectIdentifier(position)] ?? []).compactMap {
            guard case .conditional(let variationID) = $0 else {
                return nil
            }
            return variationID
        })
    }

    /// Returns every conditional variation whose projected path enters the
    /// registered subtree rooted at `position`.
    func conditionalVariationIDs(
        inSubtreeStartingAt position: BoardPosition
    ) -> Set<ConditionalVariationID> {
        Set(subtreePositions(startingAt: position).flatMap {
            conditionalVariationIDs(for: $0)
        })
    }
    
    private func subtreePositions(startingAt position: BoardPosition) -> [BoardPosition] {
        var result = [BoardPosition]()
        var positionsToVisit = [position]
        var visited = Set<ObjectIdentifier>()
        while let currentPosition = positionsToVisit.popLast() {
            let identifier = ObjectIdentifier(currentPosition)
            guard visited.insert(identifier).inserted,
                  indexByBoardPosition[identifier] != nil else {
                continue
            }
            result.append(currentPosition)
            positionsToVisit.append(
                contentsOf: nextPositionsByPosition[identifier] ?? []
            )
        }
        return result
    }

    private func removeRegisteredPositions(
        _ positions: [BoardPosition],
        recalculatesLevels: Bool = true
    ) {
        let positionsByIdentifier = Dictionary(
            uniqueKeysWithValues: positions.map {
                (ObjectIdentifier($0), $0)
            }
        )
        let identifiers = Set(positionsByIdentifier.keys)
        guard !identifiers.isEmpty else {
            return
        }

        // A structural removal invalidates any active conditional projection
        // that used one of the removed nodes. Clear that variation's source
        // from its retained prefix as well; the next projection refresh can
        // then install the authoritative path again if it is still valid.
        let affectedVariationIDs = positionsByConditionalVariation.compactMap {
            variationID, projectedPositions in
            projectedPositions.contains {
                identifiers.contains(ObjectIdentifier($0))
            } ? variationID : nil
        }
        for variationID in affectedVariationIDs {
            for projectedPosition in
                positionsByConditionalVariation[variationID] ?? [] {
                let identifier = ObjectIdentifier(projectedPosition)
                sourcesByBoardPosition[identifier]?.remove(
                    .conditional(variationID)
                )
                if sourcesByBoardPosition[identifier]?.isEmpty == true {
                    sourcesByBoardPosition.removeValue(forKey: identifier)
                }
            }
            positionsByConditionalVariation.removeValue(forKey: variationID)
        }

        for identifier in Array(nextPositionsByPosition.keys) {
            guard var nextPositions = nextPositionsByPosition[identifier] else {
                continue
            }
            nextPositions.removeAll {
                identifiers.contains(ObjectIdentifier($0))
            }
            if nextPositions.isEmpty {
                nextPositionsByPosition.removeValue(forKey: identifier)
            } else {
                nextPositionsByPosition[identifier] = nextPositions
            }
        }

        for identifier in identifiers {
            nextPositionsByPosition.removeValue(forKey: identifier)
            levelByBoardPosition.removeValue(forKey: identifier)
            indexByBoardPosition.removeValue(forKey: identifier)
            sourcesByBoardPosition.removeValue(forKey: identifier)
        }

        let affectedMoveNumbers = Set(positions.map(\.lastMoveNumber))
        for moveNumber in affectedMoveNumbers {
            guard let existingPositions = positionsByLastMoveNumber[moveNumber] else {
                continue
            }
            let removedMainPosition = existingPositions.first.flatMap { $0 }.map {
                identifiers.contains(ObjectIdentifier($0))
            } == true
            var remainingPositions = existingPositions.filter { candidate in
                guard let candidate else {
                    return true
                }
                return !identifiers.contains(ObjectIdentifier(candidate))
            }
            if removedMainPosition,
               remainingPositions.contains(where: { $0 != nil }),
               remainingPositions.first.flatMap({ $0 }) != nil {
                remainingPositions.insert(nil, at: 0)
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
        if recalculatesLevels {
            calculateLevels()
        }
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

    /// Structural branch-deletion eligibility without considering conditional
    /// provenance. Callers coordinating a server-side conditional update use
    /// this before asking `removeBranch` to perform the final local deletion.
    func canStructurallyRemoveBranch(
        startingAt position: BoardPosition
    ) -> Bool {
        position !== initialPosition
            && (indexByBoardPosition[ObjectIdentifier(position)] ?? 0) > 0
            && position.previousPosition.map {
                indexByBoardPosition[ObjectIdentifier($0)] != nil
            } == true
    }

    func canRemoveBranch(startingAt position: BoardPosition) -> Bool {
        canStructurallyRemoveBranch(startingAt: position)
            && conditionalVariationIDs(
                inSubtreeStartingAt: position
            ).isEmpty
    }

    @discardableResult
    func removeBranch(startingAt position: BoardPosition) -> BoardPosition? {
        guard canRemoveBranch(startingAt: position),
              let parentPosition = position.previousPosition,
              indexByBoardPosition[ObjectIdentifier(parentPosition)] != nil else {
            return nil
        }

        let subtreePositions = subtreePositions(startingAt: position)

        guard subtreePositions.allSatisfy({
            guard let index = indexByBoardPosition[ObjectIdentifier($0)] else {
                return false
            }
            return index > 0 && !isConditionalMovePosition($0)
        }) else {
            return nil
        }

        objectWillChange.send()
        removeRegisteredPositions(subtreePositions)
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
            let identifier = ObjectIdentifier(mainBranchPosition)
            sourcesByBoardPosition[identifier]?.remove(.main)
            sourcesByBoardPosition[identifier, default: []].insert(.analysis)
            for (index, position) in positions.enumerated() {
                if let position {
                    indexByBoardPosition[ObjectIdentifier(position)] = index
                }
            }
        }

        calculateLevels()
    }
    
    private func matches(
        _ existingPosition: BoardPosition,
        newPosition: BoardPosition,
        fromPosition: BoardPosition
    ) -> Bool {
        existingPosition.previousPosition === fromPosition
            && existingPosition.lastMove == newPosition.lastMove
            && existingPosition.hasTheSamePosition(with: newPosition)
    }

    private func addSource(
        _ source: PositionSource,
        to position: BoardPosition
    ) {
        let identifier = ObjectIdentifier(position)
        sourcesByBoardPosition[identifier, default: []].insert(source)
        if case .conditional = source {
            // Conditional projections are also durable analysis lines. Removing
            // their conditional provenance should only remove the highlight;
            // the projected branch remains available in Analyze mode.
            sourcesByBoardPosition[identifier, default: []].insert(.analysis)
        }
    }

    private func retainAnalysisLineage(from position: BoardPosition) {
        var retainedPosition: BoardPosition? = position
        while let currentPosition = retainedPosition,
              currentPosition !== initialPosition {
            let identifier = ObjectIdentifier(currentPosition)
            guard let index = indexByBoardPosition[identifier], index > 0 else {
                break
            }
            sourcesByBoardPosition[identifier, default: []].insert(.analysis)
            retainedPosition = currentPosition.previousPosition
        }
    }

    private func updateChildOrder(
        _ position: BoardPosition,
        from fromPosition: BoardPosition,
        mainBranch: Bool
    ) {
        let fromIdentifier = ObjectIdentifier(fromPosition)
        var nextPositions = nextPositionsByPosition[fromIdentifier] ?? []
        nextPositions.removeAll { $0 === position }
        if mainBranch {
            nextPositions.insert(position, at: 0)
        } else {
            nextPositions.append(position)
        }
        nextPositionsByPosition[fromIdentifier] = nextPositions
    }

    private func reindexPositions(at moveNumber: Int) {
        for (index, position) in
            (positionsByLastMoveNumber[moveNumber] ?? []).enumerated() {
            if let position {
                indexByBoardPosition[ObjectIdentifier(position)] = index
            }
        }
    }

    private func register(
        newPosition: BoardPosition,
        fromPosition: BoardPosition,
        source: PositionSource,
        mainBranch: Bool,
        recalculatesLevels: Bool
    ) -> BoardPosition {
        let fromIdentifier = ObjectIdentifier(fromPosition)
        guard let fromIndex = indexByBoardPosition[fromIdentifier] else {
            return newPosition
        }

        if case .analysis = source {
            retainAnalysisLineage(from: fromPosition)
        }

        let moveNumber = newPosition.lastMoveNumber
        if mainBranch {
            if let existingMainPosition =
                positionsByLastMoveNumber[moveNumber]?.first ?? nil {
                if matches(
                    existingMainPosition,
                    newPosition: newPosition,
                    fromPosition: fromPosition
                ) {
                    addSource(source, to: existingMainPosition)
                    return existingMainPosition
                }
                removeRegisteredPositions(
                    subtreePositions(startingAt: existingMainPosition),
                    recalculatesLevels: false
                )
            }

            var positions = positionsByLastMoveNumber[moveNumber] ?? []
            if let promotedIndex = positions.firstIndex(where: {
                guard let position = $0 else { return false }
                return matches(
                    position,
                    newPosition: newPosition,
                    fromPosition: fromPosition
                )
            }), let promotedPosition = positions[promotedIndex] {
                positions.remove(at: promotedIndex)
                if positions.isEmpty {
                    positions = [promotedPosition]
                } else if positions[0] == nil {
                    positions[0] = promotedPosition
                } else {
                    positions.insert(promotedPosition, at: 0)
                }
                positionsByLastMoveNumber[moveNumber] = positions
                reindexPositions(at: moveNumber)
                updateChildOrder(
                    promotedPosition,
                    from: fromPosition,
                    mainBranch: true
                )
                addSource(source, to: promotedPosition)
                if recalculatesLevels {
                    calculateLevels()
                }
                return promotedPosition
            }

            if positions.isEmpty {
                positions = [newPosition]
            } else if positions[0] == nil {
                positions[0] = newPosition
            } else {
                positions.insert(newPosition, at: 0)
            }
            positionsByLastMoveNumber[moveNumber] = positions
            reindexPositions(at: moveNumber)
            updateChildOrder(
                newPosition,
                from: fromPosition,
                mainBranch: true
            )
            addSource(source, to: newPosition)
        } else {
            var positions = positionsByLastMoveNumber[moveNumber]
                ?? [nil]
            if let existingPosition = positions.compactMap({ $0 }).first(where: {
                matches(
                    $0,
                    newPosition: newPosition,
                    fromPosition: fromPosition
                )
            }) {
                addSource(source, to: existingPosition)
                return existingPosition
            }

            var insertionIndex = 0
            while insertionIndex < positions.count {
                if let existingPosition = positions[insertionIndex],
                   let previousPosition = existingPosition.previousPosition,
                   let previousIndex = indexByBoardPosition[
                    ObjectIdentifier(previousPosition)
                   ], previousIndex > fromIndex {
                    break
                }
                insertionIndex += 1
            }
            positions.insert(newPosition, at: insertionIndex)
            positionsByLastMoveNumber[moveNumber] = positions
            reindexPositions(at: moveNumber)
            updateChildOrder(
                newPosition,
                from: fromPosition,
                mainBranch: false
            )
            addSource(source, to: newPosition)
        }

        largestLastMoveNumber = max(largestLastMoveNumber, moveNumber)
        if recalculatesLevels {
            calculateLevels()
        }
        return newPosition
    }

    func register(
        newPosition: BoardPosition,
        fromPosition: BoardPosition,
        mainBranch: Bool
    ) -> BoardPosition {
        register(
            newPosition: newPosition,
            fromPosition: fromPosition,
            source: mainBranch ? .main : .analysis,
            mainBranch: mainBranch,
            recalculatesLevels: true
        )
    }

    /// Reconciles conditional paths into canonical move-tree nodes.
    ///
    /// Existing identical projections are reused without replay. Each changed
    /// path is replayed exactly once before its detached legal positions are
    /// registered, preserving object identity for retained paths and shared
    /// prefixes. Paths that fail Go-rule validation are omitted when a legal
    /// sibling remains; if every nonempty path fails, the replacement is
    /// rejected before the existing projection is mutated.
    @discardableResult
    func replaceConditionalVariations(
        from basePosition: BoardPosition,
        paths: [ConditionalMovePath],
        allowsSelfCapture: Bool
    ) -> ConditionalVariationReplacementResult {
        guard contains(basePosition) else {
            return .rejected
        }

        var desiredPaths = [ConditionalMovePath]()
        var seenPathIDs = Set<ConditionalVariationID>()
        for path in paths.sorted(by: { $0.id < $1.id }) {
            guard path.rootMoveNumber == basePosition.lastMoveNumber,
                  !path.moves.isEmpty,
                  seenPathIDs.insert(path.variationID).inserted else {
                continue
            }
            desiredPaths.append(path)
        }
        guard paths.isEmpty || !desiredPaths.isEmpty else {
            return .rejected
        }

        func isIntactProjection(
            _ positions: [BoardPosition],
            for path: ConditionalMovePath
        ) -> Bool {
            guard positions.count == path.moves.count else {
                return false
            }
            var previousPosition = basePosition
            for (index, position) in positions.enumerated() {
                guard contains(position),
                      position.previousPosition === previousPosition,
                      position.lastMove == path.moves[index],
                      conditionalVariationIDs(for: position).contains(
                        path.variationID
                      ) else {
                    return false
                }
                previousPosition = position
            }
            return true
        }

        let previousProjection = positionsByConditionalVariation
        var replacementProjection =
            [ConditionalVariationID: [BoardPosition]]()
        var pathsToReplay = [ConditionalMovePath]()
        for path in desiredPaths {
            if let positions = previousProjection[path.variationID],
               isIntactProjection(positions, for: path) {
                replacementProjection[path.variationID] = positions
            } else {
                pathsToReplay.append(path)
            }
        }

        if pathsToReplay.isEmpty,
           Set(replacementProjection.keys) == Set(previousProjection.keys) {
            return .applied(Dictionary(
                uniqueKeysWithValues: replacementProjection.compactMap {
                    variationID, positions in
                    positions.last.map { (variationID, $0) }
                }
            ))
        }

        var replayedPaths = [(
            path: ConditionalMovePath,
            positions: [BoardPosition]
        )]()
        for path in pathsToReplay {
            var replayedPosition = basePosition
            var replayedPositions = [BoardPosition]()
            for move in path.moves {
                guard let nextPosition = try? replayedPosition.makeMove(
                    move: move,
                    allowsSelfCapture: allowsSelfCapture
                ) else {
                    replayedPositions = []
                    break
                }
                replayedPositions.append(nextPosition)
                replayedPosition = nextPosition
            }
            guard replayedPositions.count == path.moves.count else {
                continue
            }
            replayedPaths.append((path: path, positions: replayedPositions))
        }

        // A nonempty authoritative plan is not a clear operation. If none of
        // its structurally valid paths can be played, leave the previous
        // projection untouched so the caller can also retain its known-good
        // plan. Mixed updates still proceed with their legal siblings.
        guard desiredPaths.isEmpty
                || !replacementProjection.isEmpty
                || !replayedPaths.isEmpty else {
            return .rejected
        }

        objectWillChange.send()

        for replayedPath in replayedPaths {
            var previousPosition = basePosition
            var registeredPositions = [BoardPosition]()
            for candidatePosition in replayedPath.positions {
                // Reattach the detached replay to the canonical prefix before
                // registration. If an equivalent node already exists,
                // `register` returns that canonical instance instead.
                candidatePosition.previousPosition = previousPosition
                let registeredPosition = register(
                    newPosition: candidatePosition,
                    fromPosition: previousPosition,
                    source: .conditional(replayedPath.path.variationID),
                    mainBranch: false,
                    recalculatesLevels: false
                )
                registeredPositions.append(registeredPosition)
                previousPosition = registeredPosition
            }
            replacementProjection[replayedPath.path.variationID] =
                registeredPositions
        }

        for (variationID, previousPositions) in previousProjection {
            let replacementIdentifiers = Set(
                (replacementProjection[variationID] ?? []).map {
                    ObjectIdentifier($0)
                }
            )
            for position in previousPositions where
                !replacementIdentifiers.contains(ObjectIdentifier(position)) {
                let identifier = ObjectIdentifier(position)
                sourcesByBoardPosition[identifier]?.remove(
                    .conditional(variationID)
                )
                if sourcesByBoardPosition[identifier]?.isEmpty == true {
                    sourcesByBoardPosition.removeValue(forKey: identifier)
                }
            }
        }
        positionsByConditionalVariation = replacementProjection

        calculateLevels()
        return .applied(Dictionary(
            uniqueKeysWithValues: replacementProjection.compactMap {
                variationID, positions in
                positions.last.map { (variationID, $0) }
            }
        ))
    }

    func clearConditionalVariations() {
        guard !positionsByConditionalVariation.isEmpty else {
            return
        }
        _ = replaceConditionalVariations(
            from: initialPosition,
            paths: [],
            allowsSelfCapture: false
        )
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
