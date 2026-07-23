//
//  OGSPauseControlTests.swift
//  SurroundTests
//

import XCTest

final class OGSPauseControlTests: XCTestCase {
    func testDecodesAllPauseSourcesIncludingDynamicVacationKeys() throws {
        let control = try makePauseControl(#"""
        {
            "paused": {"pauses_left": 3, "pausing_player_id": 11},
            "moderator_paused": {"moderator_id": 99},
            "weekend": true,
            "system": false,
            "stone-removal": true,
            "vacation-123": true,
            "vacation-456": true,
            "unrelated-key": true
        }
        """#)

        XCTAssertEqual(control.userPauseDetail?.pausesLeft, 3)
        XCTAssertEqual(control.userPauseDetail?.pausingPlayerId, 11)
        XCTAssertEqual(control.moderatorPauseDetail?.moderatorId, 99)
        XCTAssertEqual(control.weekend, true)
        XCTAssertEqual(control.system, false)
        XCTAssertEqual(control.stoneRemoval, true)
        XCTAssertEqual(control.vacationPlayerIds.sorted(), [123, 456])
        XCTAssertTrue(control.isPaused())
    }

    func testIsPausedRequiresAtLeastOneActiveSource() throws {
        let empty = try makePauseControl("{}")
        XCTAssertFalse(empty.isPaused())
        XCTAssertEqual(empty.pauseReason(playerId: 11), "")

        XCTAssertFalse(try makePauseControl(#"{"weekend": false, "system": false}"#).isPaused())
        XCTAssertTrue(try makePauseControl(#"{"system": true}"#).isPaused())
        XCTAssertTrue(try makePauseControl(#"{"stone-removal": true}"#).isPaused())
        XCTAssertTrue(try makePauseControl(#"{"vacation-9": true}"#).isPaused())
    }

    /// A moderator- or server-only pause must still freeze the clock; goban maps
    /// the legacy "server" key onto the same state as "system".
    func testModeratorAndServerPausesCountAsPaused() throws {
        let moderator = try makePauseControl(#"{"moderator_paused": {"moderator_id": 7}}"#)
        XCTAssertTrue(moderator.isPaused())
        XCTAssertEqual(moderator.pauseReason(playerId: 11), String(localized: "Moderator"))

        let server = try makePauseControl(#"{"server": true}"#)
        XCTAssertTrue(server.isPaused())
        XCTAssertEqual(server.system, true)
        XCTAssertEqual(server.pauseReason(playerId: 11), String(localized: "System"))
    }

    func testPauseReasonDependsOnWhoIsAsking() throws {
        let userPause = try makePauseControl(#"{"paused": {"pauses_left": 3, "pausing_player_id": 11}}"#)
        XCTAssertEqual(userPause.pauseReason(playerId: 11), String(localized: "Paused, \(3) left"))
        XCTAssertEqual(userPause.pauseReason(playerId: 22), String(localized: "Paused"))
        XCTAssertEqual(userPause.pauseReason(playerId: nil), String(localized: "Paused"))

        let vacation = try makePauseControl(#"{"vacation-11": true, "weekend": true}"#)
        XCTAssertEqual(vacation.pauseReason(playerId: 11), String(localized: "Vacation"))
        // A player who is not on vacation falls through to the next reason.
        XCTAssertEqual(vacation.pauseReason(playerId: 22), String(localized: "Weekend"))

        XCTAssertEqual(try makePauseControl(#"{"weekend": true}"#).pauseReason(playerId: 11), String(localized: "Weekend"))
        XCTAssertEqual(try makePauseControl(#"{"system": true}"#).pauseReason(playerId: 11), String(localized: "System"))
        XCTAssertEqual(try makePauseControl(#"{"stone-removal": true}"#).pauseReason(playerId: 11), String(localized: "Stone removal"))
    }

    private func makePauseControl(_ json: String) throws -> OGSPauseControl {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPauseControl.self, from: Data(json.utf8))
    }
}
