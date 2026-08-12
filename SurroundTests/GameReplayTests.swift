//
//  GameReplayTests.swift
//  SurroundTests
//

import Combine
import XCTest

final class GameReplayTests: XCTestCase {
    func testEstimatedScoreStatusDistinguishesLeadsAndEvenScore() {
        let game = Game(width: 2, height: 1, blackName: "black", whiteName: "white", gameId: .OGS(1))

        game.currentPosition.estimatedScores = [[.hasStone(.black), .hasStone(.black)]]
        XCTAssertEqual(game.status, String(localized: "Black by \(2.0, specifier: "%.1f")"))

        game.currentPosition.estimatedScores = [[.hasStone(.white), .hasStone(.white)]]
        XCTAssertEqual(game.status, String(localized: "White by \(2.0, specifier: "%.1f")"))

        game.currentPosition.estimatedScores = [[.hasStone(.black), .hasStone(.white)]]
        XCTAssertEqual(
            game.status,
            String(
                localized: "Even",
                comment: "Estimated score is tied; the game has not necessarily ended"
            )
        )
    }

    func testFinishedGameFixtureReplaysMovesPassesAndScoringState() throws {
        let gameData = try loadGameFixture(id: 18_759_438)
        let game = Game(ogsGame: gameData)

        XCTAssertEqual(gameData.moves.count, 257)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, gameData.moves.count)
        XCTAssertEqual(game.currentPosition.lastMove, .pass)
        XCTAssertEqual(game.currentPosition.previousPosition?.lastMove, .pass)
        XCTAssertEqual(game.currentPosition.nextToMove, .white)
        XCTAssertEqual(game.gamePhase, .finished)
        XCTAssertEqual(game.positionByLastMoveNumber.count, gameData.moves.count + 1)

        for moveNumber in 0...gameData.moves.count {
            XCTAssertEqual(game.positionByLastMoveNumber[moveNumber]?.lastMoveNumber, moveNumber)
        }

        let removed = try XCTUnwrap(gameData.removed)
        XCTAssertEqual(game.currentPosition.removedStones, BoardPosition.points(fromPositionString: removed))
        XCTAssertEqual(game.currentPosition.gameScores?.black.total, 70)
        XCTAssertEqual(game.currentPosition.gameScores?.white.total, 126.5)
        XCTAssertEqual(game.removedStonesAccepted[.black], BoardPosition.points(fromPositionString: removed))
        XCTAssertEqual(game.removedStonesAccepted[.white], BoardPosition.points(fromPositionString: removed))
    }

    func testRefreshingIdenticalGameDataReusesTheExistingMainBranch() throws {
        let gameData = try loadGameFixture(id: 25_076_729)
        let game = Game(ogsGame: gameData)
        let originalPositions = game.positionByLastMoveNumber
        let originalFinalPosition = game.currentPosition

        game.gameData = gameData

        XCTAssertTrue(game.currentPosition === originalFinalPosition)
        XCTAssertEqual(game.positionByLastMoveNumber.count, originalPositions.count)
        for (moveNumber, position) in originalPositions {
            XCTAssertTrue(game.positionByLastMoveNumber[moveNumber] === position)
        }
        XCTAssertEqual(game.moveTree.positionsByLastMoveNumber.count, gameData.moves.count + 1)
    }

    func testLiveMovesCaptureAndUndoPreservesTheDiscardedLineAsVariation() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(1))
        let moves: [Move] = [
            .placeStone(1, 1),
            .placeStone(0, 1),
            .placeStone(4, 4),
            .placeStone(1, 0),
            .placeStone(4, 3),
            .placeStone(1, 2),
            .placeStone(3, 4),
            .placeStone(2, 1)
        ]

        for move in moves {
            try game.makeMove(move: move)
        }

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 8)
        XCTAssertEqual(game.currentPosition[1, 1], .empty)
        XCTAssertEqual(game.currentPosition.captures[.white], 1)
        XCTAssertEqual(game.positionByLastMoveNumber.count, 9)

        let discardedBranchRoot = try XCTUnwrap(game.positionByLastMoveNumber[6])
        let discardedFinalPosition = game.currentPosition
        game.undoMove(numbered: 6)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 5)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(4, 3))
        XCTAssertNil(game.positionByLastMoveNumber[6])
        XCTAssertNil(game.positionByLastMoveNumber[8])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[6]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[6]?[1] === discardedBranchRoot)
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[8]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[8]?[1] === discardedFinalPosition)
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(game.currentPosition)]?
                .contains { $0 === discardedBranchRoot } == true
        )
        let discardedVariation = try XCTUnwrap(game.moveTree.variation(to: discardedFinalPosition))
        XCTAssertTrue(discardedVariation.basePosition === game.currentPosition)
        XCTAssertEqual(game.moveTree.largestLastMoveNumber, 8)
        XCTAssertEqual(game.moveTree.moveNumberRange, 0..<9)
        XCTAssertEqual(game.moveTree.maxLevel, 1)

        let replacementPosition = try game.makeMove(move: .placeStone(2, 2))
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 6)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(2, 2))
        XCTAssertEqual(game.positionByLastMoveNumber.count, 7)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[6]?[0] === replacementPosition)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[6]?[1] === discardedBranchRoot)
        XCTAssertTrue(game.moveTree.variation(to: discardedFinalPosition)?.position === discardedFinalPosition)
    }

    func testAnalysisVariationDoesNotReplaceTheLiveMainBranch() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(2))
        let firstMainPosition = try game.makeMove(move: .placeStone(0, 0))
        try game.makeMove(move: .placeStone(1, 1))
        let finalMainPosition = try game.makeMove(move: .placeStone(0, 2))

        let firstVariationPosition = try game.makeMove(
            move: .placeStone(2, 2),
            fromAnalyticsPosition: firstMainPosition
        )
        let finalVariationPosition = try game.makeMove(
            move: .placeStone(2, 1),
            fromAnalyticsPosition: firstVariationPosition
        )

        XCTAssertTrue(game.currentPosition === finalMainPosition)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 3)
        XCTAssertEqual(game.moveTree.positionsByLastMoveNumber[2]?.compactMap { $0 }.count, 2)
        XCTAssertEqual(game.moveTree.positionsByLastMoveNumber[3]?.compactMap { $0 }.count, 2)

        let variation = try XCTUnwrap(game.moveTree.variation(to: finalVariationPosition))
        XCTAssertTrue(variation.basePosition === firstMainPosition)
        XCTAssertTrue(variation.position === finalVariationPosition)
        XCTAssertEqual(variation.moves, [.placeStone(2, 2), .placeStone(2, 1)])
        XCTAssertEqual(variation.nonDuplicatingMoveCoordinatesByLabel[1], [2, 2])
        XCTAssertEqual(variation.nonDuplicatingMoveCoordinatesByLabel[2], [2, 1])
    }

    func testMoveTreeNavigationUsesNearestForkAndDisplayedLevels() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(7))
        let mainPosition1 = try game.makeMove(move: .placeStone(0, 0))
        let mainPosition2 = try game.makeMove(move: .placeStone(0, 1))
        let mainPosition3 = try game.makeMove(move: .placeStone(0, 2))

        let unaryBranch = try game.makeMove(
            move: .placeStone(4, 4),
            fromAnalyticsPosition: mainPosition3
        )
        let unaryBranchContinuation = try game.makeMove(
            move: .placeStone(4, 3),
            fromAnalyticsPosition: unaryBranch
        )
        let staleChild = BoardPosition(
            fromPreviousPosition: mainPosition3,
            lastMove: .pass
        )
        game.moveTree.nextPositionsByPosition[
            ObjectIdentifier(mainPosition3),
            default: []
        ].append(contentsOf: [unaryBranch, staleChild])
        XCTAssertNil(
            game.moveTree.nearestParentWithMultipleChildren(for: staleChild)
        )
        XCTAssertNil(
            game.moveTree.nearestParentWithMultipleChildren(
                for: unaryBranchContinuation
            )
        )
        XCTAssertTrue(game.moveTree.canRemoveBranch(startingAt: unaryBranch))
        XCTAssertFalse(game.moveTree.canRemoveBranch(startingAt: mainPosition2))

        let firstBranch = try game.makeMove(
            move: .placeStone(2, 2),
            fromAnalyticsPosition: mainPosition1
        )
        let firstBranchContinuation = try game.makeMove(
            move: .placeStone(2, 3),
            fromAnalyticsPosition: firstBranch
        )
        let secondBranch = try game.makeMove(
            move: .placeStone(3, 2),
            fromAnalyticsPosition: mainPosition1
        )

        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: firstBranchContinuation
            ) === mainPosition1
        )
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: mainPosition2
            ) === mainPosition1
        )

        XCTAssertNil(game.moveTree.adjacentBranch(from: mainPosition2, direction: .previous))
        XCTAssertTrue(
            game.moveTree.adjacentBranch(from: mainPosition2, direction: .next) === firstBranch
        )
        XCTAssertTrue(
            game.moveTree.adjacentBranch(from: firstBranch, direction: .previous) === mainPosition2
        )
        XCTAssertTrue(
            game.moveTree.adjacentBranch(from: firstBranch, direction: .next) === secondBranch
        )
        XCTAssertTrue(
            game.moveTree.adjacentBranch(from: secondBranch, direction: .previous) === firstBranch
        )
        XCTAssertNil(game.moveTree.adjacentBranch(from: secondBranch, direction: .next))

        let nestedSibling = try game.makeMove(
            move: .placeStone(3, 3),
            fromAnalyticsPosition: firstBranch
        )
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: firstBranchContinuation
            ) === firstBranch
        )
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: firstBranch
            ) === mainPosition1
        )
        XCTAssertTrue(
            game.moveTree.removeBranch(startingAt: nestedSibling) === firstBranch
        )
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: firstBranchContinuation
            ) === mainPosition1
        )

        let passBranch = try game.makeMove(move: .pass, fromAnalyticsPosition: mainPosition1)
        let passContinuation = try game.makeMove(move: .pass, fromAnalyticsPosition: passBranch)
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: passContinuation
            ) === mainPosition1
        )

        let rootBranch = try game.makeMove(
            move: .placeStone(4, 0),
            fromAnalyticsPosition: game.initialPosition
        )
        XCTAssertTrue(
            game.moveTree.nearestParentWithMultipleChildren(
                for: rootBranch
            ) === game.initialPosition
        )
    }

    func testRemoveBranchDeletesSubtreeAndPreservesMainAndSiblingBranches() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(8))
        let mainPosition1 = try game.makeMove(move: .placeStone(0, 0))
        let mainPosition2 = try game.makeMove(move: .placeStone(0, 1))
        let mainPosition3 = try game.makeMove(move: .placeStone(0, 2))

        let removedPosition2 = try game.makeMove(
            move: .placeStone(2, 2),
            fromAnalyticsPosition: mainPosition1
        )
        let removedPosition3 = try game.makeMove(
            move: .placeStone(2, 3),
            fromAnalyticsPosition: removedPosition2
        )
        let removedPosition4 = try game.makeMove(
            move: .placeStone(3, 3),
            fromAnalyticsPosition: removedPosition3
        )
        let removedPosition5 = try game.makeMove(
            move: .placeStone(4, 4),
            fromAnalyticsPosition: removedPosition4
        )
        let siblingPosition2 = try game.makeMove(
            move: .placeStone(3, 2),
            fromAnalyticsPosition: mainPosition1
        )
        let siblingPosition3 = try game.makeMove(
            move: .placeStone(3, 3),
            fromAnalyticsPosition: siblingPosition2
        )
        let siblingPosition4 = try game.makeMove(
            move: .placeStone(4, 3),
            fromAnalyticsPosition: siblingPosition3
        )

        var publicationCount = 0
        let observation = game.moveTree.objectWillChange.sink {
            publicationCount += 1
        }

        XCTAssertNil(game.moveTree.removeBranch(startingAt: game.initialPosition))
        XCTAssertNil(game.moveTree.removeBranch(startingAt: mainPosition2))
        XCTAssertEqual(publicationCount, 0)

        let parentPosition = game.moveTree.removeBranch(startingAt: removedPosition2)

        XCTAssertTrue(parentPosition === mainPosition1)
        XCTAssertEqual(publicationCount, 1)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[2]?[0] === mainPosition2)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[2]?[1] === siblingPosition2)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[0] === mainPosition3)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[1] === siblingPosition3)
        XCTAssertNil(game.moveTree.indexByBoardPosition[ObjectIdentifier(removedPosition2)])
        XCTAssertNil(game.moveTree.indexByBoardPosition[ObjectIdentifier(removedPosition3)])
        XCTAssertNil(game.moveTree.indexByBoardPosition[ObjectIdentifier(removedPosition4)])
        XCTAssertNil(game.moveTree.indexByBoardPosition[ObjectIdentifier(removedPosition5)])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[5])
        XCTAssertEqual(game.moveTree.indexByBoardPosition[ObjectIdentifier(siblingPosition2)], 1)
        XCTAssertEqual(game.moveTree.levelByBoardPosition[ObjectIdentifier(siblingPosition2)], 1)
        XCTAssertEqual(game.moveTree.largestLastMoveNumber, 4)
        XCTAssertEqual(game.moveTree.moveNumberRange, 0..<5)
        XCTAssertEqual(game.moveTree.maxLevel, 1)

        let mainChildren = try XCTUnwrap(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(mainPosition1)]
        )
        XCTAssertTrue(mainChildren.contains { $0 === mainPosition2 })
        XCTAssertTrue(mainChildren.contains { $0 === siblingPosition2 })
        XCTAssertFalse(mainChildren.contains { $0 === removedPosition2 })
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(siblingPosition2)]?.first
                === siblingPosition3
        )
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(siblingPosition3)]?.first
                === siblingPosition4
        )
        withExtendedLifetime(observation) {}
    }

    func testUndoLastMovesDemotesTwoMovesClampsAtRootAndClearsRequest() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(3))
        for move in [
            Move.placeStone(0, 0),
            .placeStone(1, 1),
            .placeStone(0, 1),
            .placeStone(1, 2),
        ] {
            try game.makeMove(move: move)
        }

        let retainedPosition = try XCTUnwrap(game.positionByLastMoveNumber[2])
        let discardedBranchRoot = try XCTUnwrap(game.positionByLastMoveNumber[3])
        let discardedFinalPosition = game.currentPosition
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(retainedPosition)]?
                .contains { $0 === discardedBranchRoot } == true
        )

        game.undoRequest = OGSUndoRequest(moveNumber: 4, requestedBy: 1, moveCount: 2)
        game.undoLastMoves(count: 2)

        XCTAssertTrue(game.currentPosition === retainedPosition)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 2)
        XCTAssertNil(game.undoRequest)
        XCTAssertNil(game.positionByLastMoveNumber[3])
        XCTAssertNil(game.positionByLastMoveNumber[4])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[3]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[1] === discardedBranchRoot)
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[4]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[4]?[1] === discardedFinalPosition)
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(retainedPosition)]?
                .contains { $0 === discardedBranchRoot } == true
        )
        let discardedVariation = try XCTUnwrap(game.moveTree.variation(to: discardedFinalPosition))
        XCTAssertTrue(discardedVariation.basePosition === retainedPosition)
        XCTAssertEqual(game.moveTree.largestLastMoveNumber, 4)
        XCTAssertEqual(game.moveTree.moveNumberRange, 0..<5)
        XCTAssertEqual(game.moveTree.maxLevel, 1)

        let replacementPosition = try game.makeMove(move: .placeStone(3, 3))
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[0] === replacementPosition)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[1] === discardedBranchRoot)
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(retainedPosition)]?
                .contains { $0 === replacementPosition } == true
        )
        XCTAssertTrue(game.moveTree.variation(to: discardedFinalPosition)?.position === discardedFinalPosition)

        game.undoRequest = OGSUndoRequest(moveNumber: 3, moveCount: 99)
        game.undoLastMoves(count: 99)

        XCTAssertTrue(game.currentPosition === game.initialPosition)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.undoRequest)
        XCTAssertEqual(Set(game.positionByLastMoveNumber.keys), [0])
        XCTAssertEqual(Set(game.moveTree.positionsByLastMoveNumber.keys), [0, 1, 2, 3, 4])
        XCTAssertEqual(game.moveTree.largestLastMoveNumber, 4)
        XCTAssertEqual(game.moveTree.moveNumberRange, 0..<5)
        XCTAssertTrue(game.moveTree.variation(to: discardedFinalPosition)?.basePosition === game.initialPosition)
    }

    func testUndoDemotionPreservesSiblingAnalysisVariation() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(6))
        try game.makeMove(move: .placeStone(0, 0))
        let retainedPosition = try game.makeMove(move: .placeStone(1, 1))
        let discardedBranchRoot = try game.makeMove(move: .placeStone(0, 1))
        let discardedFinalPosition = try game.makeMove(move: .placeStone(1, 2))
        let siblingBranchRoot = try game.makeMove(
            move: .placeStone(3, 3),
            fromAnalyticsPosition: retainedPosition
        )
        let siblingFinalPosition = try game.makeMove(
            move: .placeStone(4, 4),
            fromAnalyticsPosition: siblingBranchRoot
        )

        game.undoLastMoves(count: 2)

        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[3]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[1] === discardedBranchRoot)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[2] === siblingBranchRoot)
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[4]?[0])
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[4]?[1] === discardedFinalPosition)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[4]?[2] === siblingFinalPosition)
        XCTAssertTrue(game.moveTree.variation(to: discardedFinalPosition)?.basePosition === retainedPosition)
        XCTAssertTrue(game.moveTree.variation(to: siblingFinalPosition)?.basePosition === retainedPosition)

        let replacementPosition = try game.makeMove(move: .placeStone(2, 2))
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[0] === replacementPosition)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[1] === discardedBranchRoot)
        XCTAssertTrue(game.moveTree.positionsByLastMoveNumber[3]?[2] === siblingBranchRoot)
        let retainedChildren = try XCTUnwrap(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(retainedPosition)]
        )
        XCTAssertTrue(retainedChildren.first === replacementPosition)
    }

    func testShorterAuthoritativeGameDataDemotesMissedUndoTail() throws {
        let fullGameData = try loadGameFixture(id: 25_076_729)
        var shortenedGameData = fullGameData
        let game = Game(ogsGame: fullGameData)
        let originalFinalPosition = game.currentPosition
        let retainedMoveNumber = fullGameData.moves.count - 2
        let retainedPosition = try XCTUnwrap(game.positionByLastMoveNumber[retainedMoveNumber])
        let staleBranchRoot = try XCTUnwrap(game.positionByLastMoveNumber[retainedMoveNumber + 1])

        shortenedGameData.moves = Array(fullGameData.moves.prefix(retainedMoveNumber))
        game.gameData = shortenedGameData

        XCTAssertTrue(game.currentPosition === retainedPosition)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, retainedMoveNumber)
        XCTAssertNil(game.positionByLastMoveNumber[retainedMoveNumber + 1])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[retainedMoveNumber + 1]?[0])
        XCTAssertTrue(
            game.moveTree.positionsByLastMoveNumber[retainedMoveNumber + 1]?[1] === staleBranchRoot
        )
        XCTAssertTrue(
            game.moveTree.nextPositionsByPosition[ObjectIdentifier(retainedPosition)]?
                .contains { $0 === staleBranchRoot } == true
        )
        let staleFinalPosition = try XCTUnwrap(
            game.moveTree.positionsByLastMoveNumber[shortenedGameData.moves.count + 2]?[1]
        )
        XCTAssertTrue(game.moveTree.variation(to: staleFinalPosition)?.basePosition === retainedPosition)
        XCTAssertEqual(game.moveTree.largestLastMoveNumber, retainedMoveNumber + 2)
        XCTAssertEqual(game.moveTree.moveNumberRange, 0..<(retainedMoveNumber + 3))

        game.gameData = fullGameData

        XCTAssertTrue(game.currentPosition === originalFinalPosition)
        XCTAssertTrue(
            game.moveTree.positionsByLastMoveNumber[retainedMoveNumber + 1]?[0] === staleBranchRoot
        )
        XCTAssertEqual(
            game.moveTree.positionsByLastMoveNumber[retainedMoveNumber + 1]?.compactMap { $0 }.count,
            1
        )
    }

    func testUndoRequestCoordinatesCountPassesAndExcludeCapturedStones() throws {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(4))
        let moves: [Move] = [
            .placeStone(1, 1),
            .placeStone(0, 1),
            .pass,
            .placeStone(1, 0),
            .placeStone(4, 4),
            .placeStone(1, 2),
            .pass,
            .placeStone(2, 1),
        ]
        for move in moves {
            try game.makeMove(move: move)
        }

        XCTAssertEqual(game.currentPosition[1, 1], .empty)

        game.undoRequest = OGSUndoRequest(moveNumber: 8, moveCount: 2)
        XCTAssertEqual(game.undoRequestCoordinates, [[2, 1]])

        game.undoRequest = OGSUndoRequest(moveNumber: 8, moveCount: 8)
        XCTAssertEqual(
            game.undoRequestCoordinates,
            [[2, 1], [1, 2], [4, 4], [1, 0], [0, 1]]
        )
        XCTAssertFalse(game.undoRequestCoordinates.contains([1, 1]))
    }

    func testUndoRequestStatusRolesAvailabilityAndMoveClearing() throws {
        let black = OGSUser(username: "Black player", id: 1)
        let white = OGSUser(username: "White player", id: 2)
        let service = OGSService(previewState: .init(user: black, isLoggedIn: true))
        let game = Game(width: 5, height: 5, blackName: black.username, whiteName: white.username, gameId: .OGS(5))
        game.blackPlayer = black
        game.whitePlayer = white
        game.ogs = service
        game.gamePhase = .play
        game.clock = OGSClock(
            blackTime: ThinkingTime(),
            whiteTime: ThinkingTime(),
            currentPlayerColor: .black,
            lastMoveTime: 0,
            currentPlayerId: black.id,
            blackPlayerId: black.id,
            whitePlayerId: white.id
        )
        try game.makeMove(move: .placeStone(0, 0))

        XCTAssertTrue(game.undoable)

        game.undoRequest = OGSUndoRequest(moveNumber: 1, requestedBy: white.id)
        XCTAssertTrue(game.hasCurrentUndoRequest)
        XCTAssertTrue(game.canAcceptUndo)
        XCTAssertFalse(game.canCancelUndo)
        XCTAssertEqual(game.status, "Undo requested")
        XCTAssertFalse(game.undoable)

        game.undoRequest = OGSUndoRequest(moveNumber: 1, requestedBy: black.id)
        XCTAssertFalse(game.canAcceptUndo)
        XCTAssertTrue(game.canCancelUndo)
        XCTAssertEqual(game.status, "Undo requested")

        game.undoRequest = OGSUndoRequest(moveNumber: 1, requestedBy: 999)
        XCTAssertTrue(game.canAcceptUndo)
        XCTAssertFalse(game.canCancelUndo)
        XCTAssertEqual(game.status, "Undo requested")

        game.undoRequest = OGSUndoRequest(moveNumber: 0, requestedBy: white.id)
        XCTAssertFalse(game.hasCurrentUndoRequest)
        XCTAssertFalse(game.canAcceptUndo)
        XCTAssertFalse(game.canCancelUndo)
        XCTAssertTrue(game.undoRequestCoordinates.isEmpty)
        XCTAssertNotEqual(game.status, "Undo requested")

        game.undoRequest = OGSUndoRequest(moveNumber: 1)
        XCTAssertTrue(game.canAcceptUndo)
        XCTAssertFalse(game.canCancelUndo)

        try game.makeMove(move: .placeStone(1, 1))
        XCTAssertNil(game.undoRequest)
    }

    private func loadGameFixture(id: Int) throws -> OGSGame {
        let bundle = Bundle(for: GameReplayTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-\(id)", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: data)
    }
}
