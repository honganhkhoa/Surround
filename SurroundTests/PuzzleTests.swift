//
//  PuzzleTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 29/05/2021.
//

import XCTest

class PuzzleTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParsingPuzzle() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let fileURL = Bundle(for: PuzzleTests.self).url(forResource: "puzzle-2630", withExtension: "json")!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let puzzleInfo = try decoder.decode(OGSPuzzleInfo.self, from: Data(contentsOf: fileURL))
        let puzzle = puzzleInfo.puzzle
        XCTAssertEqual(puzzle.initialPlayer, .black)
        XCTAssertEqual(puzzle.moveTree.move, .pass)
    }
}
