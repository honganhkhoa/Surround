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
