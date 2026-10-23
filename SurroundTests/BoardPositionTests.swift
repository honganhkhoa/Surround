//
//  BoardPositionTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 25/05/2021.
//

import XCTest

class BoardPositionTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCapture() throws {
        let position = BoardPositionTests.position(fromVisualStrings: [
            "-bbbw",
            "bww--",
            "-bb--",
        ])
        BoardPositionTests.assertPositionEqual(position: try! position.makeMove(move: .placeStone(1, 4)), visualStrings: [
            "-bbb-",
            "bww-b",
            "-bb--"
        ])
        BoardPositionTests.assertPositionEqual(position: try! position.makeMove(move: .placeStone(1, 3)), visualStrings: [
            "-bbbw",
            "b--b-",
            "-bb--"
        ])
    }
    
    func testSimpleInvalidMoves() throws {
        let position = BoardPositionTests.position(fromVisualStrings: [
            "-w--",
            "w-w-",
            "-w--"
        ])
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(0, 0)))
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(0, 1)))
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(1, 1)))
        XCTAssertNoThrow(try position.makeMove(move: .placeStone(0, 2)))
    }
    
    func testSelfCapture() throws {
        let position = BoardPositionTests.position(fromVisualStrings: [
            "----w",
            "---wb",
            "--wb-"
        ])
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(2, 4)))
        BoardPositionTests.assertPositionEqual(position: try! position.makeMove(move: .placeStone(2, 4), allowsSelfCapture: true), visualStrings: [
            "----w",
            "---w-",
            "--w--"
        ])
    }
    
    func testKo() throws {
        var position = BoardPositionTests.position(fromVisualStrings: [
            "--wb-",
            "-w-wb",
            "--wb-"
        ])
        position = try! position.makeMove(move: .placeStone(1, 2))
        BoardPositionTests.assertPositionEqual(position: position, visualStrings: [
            "--wb-",
            "-wb-b",
            "--wb-"
        ])
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(1, 3)))
        position = try! position.makeMove(move: .placeStone(0, 0))
        position = try! position.makeMove(move: .pass)
        position = try! position.makeMove(move: .placeStone(1, 3))
        BoardPositionTests.assertPositionEqual(position: position, visualStrings: [
            "w-wb-",
            "-w-wb",
            "--wb-"
        ])
        XCTAssertThrowsError(try position.makeMove(move: .placeStone(1, 2)))
    }

    func testCoordinateStringRoundTrips() throws {
        let points: Set<[Int]> = [[0, 0], [2, 4], [18, 3]]
        let encoded = BoardPosition.positionString(fromPoints: points)
        XCTAssertEqual(encoded, "aaecds")
        XCTAssertEqual(BoardPosition.points(fromPositionString: encoded), points)
        XCTAssertEqual(BoardPosition.points(fromPositionString: ""), [])

        XCTAssertEqual(Move.placeStone(2, 4).toOGSString(), "ec")
        XCTAssertEqual(Move.pass.toOGSString(), "..")
        XCTAssertEqual(
            try Move.fromMoveString(
                moveString: "aaecds",
                boardWidth: 19,
                boardHeight: 19
            ),
            [.placeStone(0, 0), .placeStone(2, 4), .placeStone(18, 3)]
        )
        XCTAssertEqual(
            try Move.fromMoveString(
                moveString: "..AaBC",
                boardWidth: 3,
                boardHeight: 3
            ),
            [.pass, .placeStone(0, 0), .placeStone(2, 1)]
        )
        XCTAssertEqual(
            try Move.moveString(
                from: [.pass, .placeStone(0, 0), .placeStone(2, 1)],
                boardWidth: 3,
                boardHeight: 3
            ),
            "..aabc"
        )
    }

    func testMoveStringRejectsMalformedEditedAndOutOfBoardPaths() throws {
        XCTAssertThrowsError(
            try Move.fromMoveString(
                moveString: "a",
                boardWidth: 19,
                boardHeight: 19
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .oddLength)
        }
        XCTAssertThrowsError(
            try Move.fromMoveString(
                moveString: "!1aa",
                boardWidth: 19,
                boardHeight: 19
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .editedMoveUnsupported)
        }
        XCTAssertThrowsError(
            try Move.fromMoveString(
                moveString: ".a",
                boardWidth: 19,
                boardHeight: 19
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .invalidCoordinate)
        }
        XCTAssertThrowsError(
            try Move.fromMoveString(
                moveString: "af",
                boardWidth: 5,
                boardHeight: 5
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .outOfBounds)
        }
        XCTAssertThrowsError(
            try Move.fromMoveString(
                moveString: "💥",
                boardWidth: 19,
                boardHeight: 19
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .invalidCoordinate)
        }
        XCTAssertThrowsError(
            try Move.moveString(
                from: [.placeStone(5, 0)],
                boardWidth: 5,
                boardHeight: 5
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .outOfBounds)
        }
        XCTAssertThrowsError(
            try Move.moveString(
                from: [.placeStone(-1, 0)],
                boardWidth: 5,
                boardHeight: 5
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .outOfBounds)
        }
        XCTAssertThrowsError(
            try Move.moveString(
                from: [.placeStone(0, 26)],
                boardWidth: 27,
                boardHeight: 27
            )
        ) { error in
            XCTAssertEqual(error as? MoveStringError, .outOfBounds)
        }
    }

    func testVariationMarkupsAreValueScopedWhenZeroMovePositionsAlias() throws {
        let basePosition = BoardPosition(width: 5, height: 5)
        var markedVariation = try Variation(
            basePosition: basePosition,
            moves: []
        )
        let plainVariation = try Variation(
            basePosition: basePosition,
            moves: []
        )

        XCTAssertTrue(markedVariation.position === basePosition)
        XCTAssertTrue(plainVariation.position === basePosition)
        markedVariation.markups[BoardPoint(row: 0, column: 0)] = BoardMarkup(
            label: "A"
        )
        XCTAssertEqual(markedVariation.markups.count, 1)
        XCTAssertTrue(plainVariation.markups.isEmpty)
    }

    func testZeroMoveVariationUsesPositionIndicators() throws {
        let basePosition = BoardPosition(width: 5, height: 5)
        let zeroMoveVariation = try Variation(
            basePosition: basePosition,
            moves: []
        )
        let placedMoveVariation = try Variation(
            basePosition: basePosition,
            moves: [.placeStone(0, 0)]
        )
        let passVariation = try Variation(
            basePosition: basePosition,
            moves: [.pass]
        )

        XCTAssertEqual(
            BoardStoneIndicatorMode(variation: nil),
            .positionIndicators
        )
        XCTAssertEqual(
            BoardStoneIndicatorMode(variation: zeroMoveVariation),
            .positionIndicators
        )
        XCTAssertEqual(
            BoardStoneIndicatorMode(variation: placedMoveVariation),
            .variationNumberings
        )
        XCTAssertTrue(passVariation.nonDuplicatingMoveCoordinatesByLabel.isEmpty)
        XCTAssertEqual(
            BoardStoneIndicatorMode(variation: passVariation),
            .variationNumberings
        )
    }

    func testExplicitMarkupReplacesAutomaticIndicatorsOnlyAtItsPoint() {
        let markedPoint = BoardPoint(row: 1, column: 1)
        let otherPoint = BoardPoint(row: 1, column: 2)
        let annotations = [BoardMarkup(label: "A"), BoardMarkup(label: "100")]
            + BoardMarkShape.allCases.map { BoardMarkup(shapes: [$0]) }

        for markup in annotations {
            let policy = BoardPointIndicatorPolicy(markups: [markedPoint: markup])
            XCTAssertFalse(policy.showsLastMove(at: markedPoint, pending: false))
            XCTAssertFalse(policy.showsVariationNumber(at: markedPoint))
            XCTAssertTrue(policy.showsLastMove(at: otherPoint, pending: false))
            XCTAssertTrue(policy.showsVariationNumber(at: otherPoint))
        }
    }

    /// The last-move ring yields only to a square drawn on its own point:
    /// territory scoring leaves a finished game's last stone unmarked, area
    /// scoring and estimates cover it, and dame never draws a square.
    func testOwnershipMarksFollowTheSquaresScoringDraws() {
        let position = BoardPosition(width: 5, height: 5)
        position.putStone(row: 1, column: 1, color: .black)
        position.putStone(row: 3, column: 3, color: .white)
        func score(_ points: Set<[Int]>) -> PlayerScore {
            PlayerScore(handicap: 0, komi: 0, scoringPositions: points, stones: 0, territory: 0, prisoners: 0, total: 0)
        }
        position.removedStones = [[2, 2]]
        position.gameScores = GameScores(black: score([[0, 0], [2, 2]]), white: score([[4, 4]]))
        XCTAssertFalse(position.hasOwnershipMark(atRow: 1, column: 1), "Territory scoring leaves stones unmarked")
        XCTAssertFalse(position.hasOwnershipMark(atRow: 3, column: 3))
        XCTAssertTrue(position.hasOwnershipMark(atRow: 0, column: 0))
        XCTAssertTrue(position.hasOwnershipMark(atRow: 4, column: 4))
        XCTAssertFalse(position.hasOwnershipMark(atRow: 2, column: 2), "Dame is drawn as an outline, not a square")
        XCTAssertFalse(position.hasOwnershipMark(atRow: -1, column: 0))
        XCTAssertFalse(position.hasOwnershipMark(atRow: 0, column: 5))

        position.gameScores = GameScores(black: score([[1, 1]]), white: score([]))
        XCTAssertTrue(position.hasOwnershipMark(atRow: 1, column: 1), "Area scoring covers the stone")

        position.gameScores = nil
        var estimate = Array(repeating: Array(repeating: PointState.empty, count: 5), count: 5)
        estimate[3][3] = .hasStone(.white)
        position.estimatedScores = estimate
        XCTAssertTrue(position.hasOwnershipMark(atRow: 3, column: 3))
        XCTAssertFalse(position.hasOwnershipMark(atRow: 1, column: 1), "An unestimated stone keeps its ring")
    }

    /// One rule decides whether a markup draws anything, for the overlay and
    /// for automatic indicators alike.
    /// The stones and the annotation overlay share one plan, so each status
    /// point shows exactly one indicator: the ring, a pending cross, an undo
    /// glyph or the annotation.
    func testIndicatorPlanGivesEachStatusPointOneIndicator() throws {
        let base = BoardPosition(width: 5, height: 5)
        let played = try base.makeMove(move: .placeStone(2, 2))
        let lastPoint = BoardPoint(row: 2, column: 2)
        let other = BoardPoint(row: 0, column: 0)
        let marks: BoardMarkups = [lastPoint: BoardMarkup(label: "A"), other: BoardMarkup(shapes: [.circle])]

        // The ring alone, and an annotation in its place.
        var plan = BoardIndicatorPlan(position: played, variation: nil, markups: [:])
        XCTAssertEqual(plan.lastMove, BoardIndicatorPlan.LastMove(point: lastPoint, pending: false))
        plan = BoardIndicatorPlan(position: played, variation: nil, markups: marks)
        XCTAssertNil(plan.lastMove)
        XCTAssertEqual(plan.visibleMarkups, marks)

        // A pending cross takes the point; its annotation waits.
        plan = BoardIndicatorPlan(position: played, variation: nil, markups: marks, isLastMovePending: true)
        XCTAssertEqual(plan.lastMove, BoardIndicatorPlan.LastMove(point: lastPoint, pending: true))
        XCTAssertEqual(plan.visibleMarkups, [other: BoardMarkup(shapes: [.circle])])

        // An undo glyph replaces both the ring and the annotation.
        plan = BoardIndicatorPlan(position: played, variation: nil, markups: marks,
                                  undoRequestCoordinates: [[2, 2]])
        XCTAssertEqual(plan.undoPoints, [lastPoint])
        XCTAssertNil(plan.lastMove)
        XCTAssertEqual(plan.visibleMarkups, [other: BoardMarkup(shapes: [.circle])])

        // An ownership square covers the point; with no cross drawn, the
        // annotation stays.
        var estimate = Array(repeating: Array(repeating: PointState.empty, count: 5), count: 5)
        estimate[2][2] = .hasStone(.black)
        played.estimatedScores = estimate
        plan = BoardIndicatorPlan(position: played, variation: nil, markups: marks, isLastMovePending: true)
        XCTAssertNil(plan.lastMove)
        XCTAssertEqual(plan.visibleMarkups, marks)
        played.estimatedScores = nil

        // Stone removal draws no ring.
        plan = BoardIndicatorPlan(position: played, variation: nil, markups: [:], showsLastMove: false)
        XCTAssertNil(plan.lastMove)
    }

    func testIndicatorPlanKeepsOnlyUndoRequestsOnStones() throws {
        let position = try BoardPosition(width: 5, height: 5).makeMove(move: .placeStone(1, 1))
        let plan = BoardIndicatorPlan(position: position, variation: nil, markups: [:],
                                      undoRequestCoordinates: [[1, 1], [0, 0], [5, 0], [0, -1], [1]])
        XCTAssertEqual(plan.undoPoints, [BoardPoint(row: 1, column: 1)])
    }

    /// A variation numbers its own moves: no status indicators, every annotation.
    func testIndicatorPlanLeavesVariationsToTheirNumbers() throws {
        let base = BoardPosition(width: 5, height: 5)
        let variation = try Variation(basePosition: base, moves: [.placeStone(2, 2), .placeStone(2, 3)])
        let marks: BoardMarkups = [BoardPoint(row: 2, column: 3): BoardMarkup(label: "A")]
        let plan = BoardIndicatorPlan(position: variation.position, variation: variation, markups: marks,
                                      undoRequestCoordinates: [[2, 2]], isLastMovePending: true)
        XCTAssertNil(plan.lastMove)
        XCTAssertTrue(plan.undoPoints.isEmpty)
        XCTAssertEqual(plan.visibleMarkups, marks)
        XCTAssertFalse(plan.policy.showsVariationNumber(at: BoardPoint(row: 2, column: 3)))
        XCTAssertTrue(plan.policy.showsVariationNumber(at: BoardPoint(row: 2, column: 2)))
    }

    func testMarkupVisibilityIgnoresEmptyLabels() {
        XCTAssertFalse(BoardMarkup().isVisible)
        XCTAssertFalse(BoardMarkup(label: "").isVisible)
        XCTAssertTrue(BoardMarkup(label: "A").isVisible)
        XCTAssertTrue(BoardMarkup(shapes: [.circle]).isVisible)
        XCTAssertTrue(BoardMarkup(label: "", shapes: [.cross]).isVisible)
    }

    func testInvisibleMarkupKeepsAutomaticIndicatorsVisible() {
        let point = BoardPoint(row: 1, column: 1)
        let markups: [BoardMarkups] = [
            [:],
            [point: BoardMarkup()],
            [point: BoardMarkup(label: "")]
        ]

        for marks in markups {
            let policy = BoardPointIndicatorPolicy(markups: marks)
            XCTAssertTrue(policy.showsLastMove(at: point, pending: false))
            XCTAssertTrue(policy.showsVariationNumber(at: point))
        }
    }

    func testPendingMoveIndicatorRemainsVisibleOverExplicitMarkup() {
        let point = BoardPoint(row: 1, column: 1)
        let annotations = [
            BoardMarkup(label: "A"),
            BoardMarkup(shapes: [.cross]),
            BoardMarkup(label: "A", shapes: [.circle, .triangle])
        ]

        for markup in annotations {
            let policy = BoardPointIndicatorPolicy(markups: [point: markup])
            XCTAssertTrue(policy.showsLastMove(at: point, pending: true))
            XCTAssertFalse(policy.showsLastMove(at: point, pending: false))
        }
    }

    func testPendingMoveTemporarilyHidesOnlyItsAnnotation() {
        let pendingPoint = BoardPoint(row: 1, column: 1)
        let otherPoint = BoardPoint(row: 1, column: 2)
        let marks: BoardMarkups = [
            pendingPoint: BoardMarkup(label: "A", shapes: [.circle]),
            otherPoint: BoardMarkup(label: "B")
        ]
        let policy = BoardPointIndicatorPolicy(markups: marks)

        XCTAssertFalse(policy.showsMarkup(at: pendingPoint, pendingMove: pendingPoint))
        XCTAssertTrue(policy.showsMarkup(at: otherPoint, pendingMove: pendingPoint))
        XCTAssertTrue(policy.showsMarkup(at: pendingPoint))
        XCTAssertEqual(policy.markups, marks)
    }

    func testUndoIndicatorsTemporarilyHideOnlyTheirAnnotations() {
        let firstUndoPoint = BoardPoint(row: 1, column: 1)
        let secondUndoPoint = BoardPoint(row: 1, column: 2)
        let otherPoint = BoardPoint(row: 2, column: 2)
        let marks: BoardMarkups = [
            firstUndoPoint: BoardMarkup(label: "A"),
            secondUndoPoint: BoardMarkup(shapes: [.triangle]),
            otherPoint: BoardMarkup(label: "B")
        ]
        let policy = BoardPointIndicatorPolicy(markups: marks)
        let undoPoints: Set<BoardPoint> = [firstUndoPoint, secondUndoPoint]

        XCTAssertFalse(policy.showsMarkup(at: firstUndoPoint, undoPoints: undoPoints))
        XCTAssertFalse(policy.showsMarkup(at: secondUndoPoint, undoPoints: undoPoints))
        XCTAssertTrue(policy.showsMarkup(at: otherPoint, undoPoints: undoPoints))
        XCTAssertTrue(policy.showsMarkup(at: firstUndoPoint))
        XCTAssertTrue(policy.showsMarkup(at: secondUndoPoint))
        XCTAssertEqual(policy.markups, marks)
    }

    func testBoardMarkupSequencesUseTheCurrentNode() {
        var markups = BoardMarkups()
        XCTAssertEqual(markups.nextBoardLetter, "A")
        XCTAssertEqual(markups.nextBoardNumber, "1")

        markups[BoardPoint(row: 0, column: 0)] = BoardMarkup(label: "A")
        markups[BoardPoint(row: 0, column: 1)] = BoardMarkup(label: "C")
        markups[BoardPoint(row: 0, column: 2)] = BoardMarkup(label: "custom")
        markups[BoardPoint(row: 1, column: 0)] = BoardMarkup(label: "2")
        markups[BoardPoint(row: 1, column: 1)] = BoardMarkup(label: "10")
        XCTAssertEqual(markups.nextBoardLetter, "D")
        XCTAssertEqual(markups.nextBoardNumber, "11")

        markups[BoardPoint(row: 2, column: 0)] = BoardMarkup(label: "z")
        XCTAssertEqual(markups.nextBoardLetter, "A")
    }

    func testBoardMarkupToolsReplaceAndEraseExistingMarkup() {
        let point = BoardPoint(row: 1, column: 1)
        var markups = BoardMarkups()

        markups.paint(.letters, at: point)
        XCTAssertEqual(markups[point]?.label, "A")
        XCTAssertTrue(AnalyzeBoardTool.letters.matches(markups[point]))

        markups.paint(.triangle, at: point)
        XCTAssertNil(markups[point]?.label)
        XCTAssertEqual(markups[point]?.shapes, [.triangle])
        XCTAssertTrue(AnalyzeBoardTool.triangle.matches(markups[point]))

        markups.paint(.eraser, at: point)
        XCTAssertNil(markups[point])
    }

    func testBoardMarkupOGSCodecRoundTripsSupportedMarks() {
        let original: BoardMarkups = [
            BoardPoint(row: 2, column: 4): BoardMarkup(
                label: "A",
                shapes: [.circle]
            ),
            BoardPoint(row: 0, column: 0): BoardMarkup(shapes: [.triangle]),
            BoardPoint(row: 1, column: 2): BoardMarkup(shapes: [.triangle]),
        ]

        let encoded = original.ogsMarks(boardWidth: 5, boardHeight: 3)
        XCTAssertEqual(encoded["A"], "ec")
        XCTAssertEqual(encoded["circle"], "ec")
        XCTAssertEqual(encoded["triangle"], "aacb")
        XCTAssertEqual(
            BoardMarkupCodec.decode(encoded, boardWidth: 5, boardHeight: 3),
            original
        )
    }

    func testBoardMarkupDecoderSkipsMalformedUnsupportedAndOutOfBoundsData() {
        let decoded = BoardMarkupCodec.decode(
            [
                "A": "aaeczzq",
                "square": "ba",
                "triangle": "a",
                "black": "aa",
                "removal": "aa",
            ],
            boardWidth: 5,
            boardHeight: 3
        )

        XCTAssertEqual(decoded[BoardPoint(row: 0, column: 0)]?.label, "A")
        XCTAssertEqual(decoded[BoardPoint(row: 2, column: 4)]?.label, "A")
        XCTAssertEqual(
            decoded[BoardPoint(row: 0, column: 1)]?.shapes,
            [.square]
        )
        XCTAssertEqual(decoded.count, 3)
    }

    static func position(fromVisualStrings visualStrings: [String], nextToMove: StoneColor = .black) -> BoardPosition {
        let position = BoardPosition(width: visualStrings[0].count, height: visualStrings.count)
        for row in 0..<position.height {
            let positionRow = visualStrings[row]
            for column in 0..<position.width {
                let char = positionRow[positionRow.index(positionRow.startIndex, offsetBy: column)]
                switch char {
                case "w":
                    position[row, column] = .hasStone(.white)
                case "b":
                    position[row, column] = .hasStone(.black)
                default:
                    break
                }
            }
        }
        position.nextToMove = nextToMove
        return position
    }
    
    static func assertPositionEqual(position: BoardPosition, visualStrings: [String], file: StaticString = #file, line: UInt = #line) {
        let otherPosition = BoardPositionTests.position(fromVisualStrings: visualStrings)
        for row in 0..<position.height {
            for column in 0..<position.width {
                if position[row, column] != otherPosition[row, column] {
                    XCTFail("Row \(row) column \(column) is \(position[row, column]), expected \(otherPosition[row, column])", file: file, line: line)
                }
            }
        }
    }
}
