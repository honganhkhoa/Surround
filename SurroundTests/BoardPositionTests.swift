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
