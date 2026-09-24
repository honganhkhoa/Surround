//
//  SurroundTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 6/30/20.
//

import XCTest

class SurroundTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

final class ChatLogSnapshotTests: XCTestCase {
    func testCapturedRowsSurviveChatClearingAndReplacement() throws {
        let game = Game(
            width: 5, height: 5,
            blackName: "black", whiteName: "white", gameId: .OGS(42)
        )
        game.chatLog = [
            try chatLine(id: "first", moveNumber: 1),
            try chatLine(id: "second", moveNumber: 1),
            try chatLine(id: "third", moveNumber: 2),
        ]
        let rows = ChatLogRow.snapshot(of: game.chatLog)

        game.chatLog.removeAll()
        XCTAssertTrue(ChatLogRow.snapshot(of: game.chatLog).isEmpty)
        XCTAssertEqual(rows.map(\.chatLine.id), ["first", "second", "third"])
        XCTAssertEqual(rows.map(\.moveDividerNumber), [1, nil, 2])
        XCTAssertEqual(rows.map(\.shouldMerge), [false, true, false])

        game.chatLog = [try chatLine(id: "replacement", moveNumber: 99)]
        let replacementRows = ChatLogRow.snapshot(of: game.chatLog)
        XCTAssertEqual(replacementRows.map(\.chatLine.id), ["replacement"])
        XCTAssertEqual(replacementRows.map(\.moveDividerNumber), [99])
        XCTAssertEqual(replacementRows.map(\.shouldMerge), [false])
        // A deferred lazy-row evaluation must still use its captured content
        // and metadata, even when the new log is shorter than the old log.
        XCTAssertEqual(rows.map(\.chatLine.body), ["first", "second", "third"])
        XCTAssertEqual(rows.map(\.moveDividerNumber), [1, nil, 2])
        XCTAssertEqual(rows.map(\.shouldMerge), [false, true, false])
    }

    func testMergeAndMoveDividersRespectChatBoundaries() throws {
        let lines = [
            try chatLine(id: "first", moveNumber: 1),
            try chatLine(id: "same-author", moveNumber: 1),
            try chatLine(id: "new-author", moveNumber: 1, playerID: 2),
            try chatLine(id: "new-channel", moveNumber: 1, playerID: 2, channel: "malkovich"),
            try chatLine(id: "new-move", moveNumber: 2, playerID: 2, channel: "malkovich"),
            try chatLine(id: "no-move", moveNumber: nil, playerID: 2, channel: "malkovich"),
            try chatLine(id: "same-no-move", moveNumber: nil, playerID: 2, channel: "malkovich"),
            try chatLine(id: "resume-move", moveNumber: 2, playerID: 2, channel: "malkovich"),
            try chatLine(id: "earlier-move", moveNumber: 1, playerID: 2, channel: "malkovich"),
        ]
        let rows = ChatLogRow.snapshot(of: lines)

        XCTAssertEqual(rows.map(\.chatLine.id), lines.map(\.id))
        XCTAssertEqual(
            rows.map(\.shouldMerge),
            [false, true, false, false, false, false, true, false, false]
        )
        XCTAssertEqual(
            rows.map(\.moveDividerNumber),
            [1, nil, nil, nil, 2, nil, nil, nil, 1]
        )
    }

    private func chatLine(
        id: String,
        moveNumber: Int?,
        playerID: Int = 1,
        channel: String = "main"
    ) throws -> OGSChatLine {
        var line: [String: Any] = [
            "chat_id": id, "date": 1, "player_id": playerID,
            "username": "player", "body": id,
        ]
        line["move_number"] = moveNumber
        let data = try JSONSerialization.data(withJSONObject: [
            "channel": channel, "line": line,
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSChatLine.self, from: data)
    }
}
