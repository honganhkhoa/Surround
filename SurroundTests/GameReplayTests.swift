//
//  GameReplayTests.swift
//  SurroundTests
//

import XCTest

final class GameReplayTests: XCTestCase {
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

    func testLiveMovesCaptureAndUndoRemovesTheDiscardedMainBranch() throws {
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

        game.undoMove(numbered: 6)

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 5)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(4, 3))
        XCTAssertNil(game.positionByLastMoveNumber[6])
        XCTAssertNil(game.positionByLastMoveNumber[8])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[6])
        XCTAssertNil(game.moveTree.positionsByLastMoveNumber[8])

        try game.makeMove(move: .placeStone(2, 2))
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 6)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(2, 2))
        XCTAssertEqual(game.positionByLastMoveNumber.count, 7)
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

    private func loadGameFixture(id: Int) throws -> OGSGame {
        let bundle = Bundle(for: GameReplayTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-\(id)", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: data)
    }
}
