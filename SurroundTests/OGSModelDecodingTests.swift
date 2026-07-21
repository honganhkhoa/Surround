//
//  OGSModelDecodingTests.swift
//  SurroundTests
//

import XCTest

final class OGSModelDecodingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func testMoveDecodesMinimalPassAndFullPlayerUpdateShapes() throws {
        let minimal = try decoder.decode(OGSMove.self, from: Data("[3,4]".utf8))
        XCTAssertEqual(minimal.column, 3)
        XCTAssertEqual(minimal.row, 4)
        XCTAssertEqual(minimal.move, .placeStone(4, 3))
        XCTAssertNil(minimal.timedelta)
        XCTAssertNil(minimal.edited)
        XCTAssertNil(minimal.extra)

        let pass = try decoder.decode(OGSMove.self, from: Data("[-1,-1,1250,null,null]".utf8))
        XCTAssertEqual(pass.move, .pass)
        XCTAssertEqual(pass.timedelta, 1250)
        XCTAssertNil(pass.edited)
        XCTAssertNil(pass.extra)

        let fullPayload = #"[15,3,30480,false,{"played_by":1526,"player_update":{"players":{"black":1526,"white":1769},"rengo_teams":{"black":[1526,1767,1765],"white":[1769]}}}]"#
        let full = try decoder.decode(OGSMove.self, from: Data(fullPayload.utf8))

        XCTAssertEqual(full.move, .placeStone(3, 15))
        XCTAssertEqual(full.timedelta, 30480)
        XCTAssertEqual(full.edited, false)
        XCTAssertEqual(full.extra?.playedBy, 1526)
        XCTAssertEqual(full.extra?.playerUpdate?.players, .init(black: 1526, white: 1769))
        XCTAssertEqual(full.extra?.playerUpdate?.rengoTeams.black, [1526, 1767, 1765])
        XCTAssertEqual(full.extra?.playerUpdate?.rengoTeams.white, [1769])
    }

    func testMoveRejectsIncompleteCoordinates() {
        XCTAssertThrowsError(try decoder.decode(OGSMove.self, from: Data("[3]".utf8)))
    }

    func testPlayerScoreDecodesCompactScoringPositions() throws {
        let payload = #"{"handicap":0,"komi":6.5,"scoring_positions":"abbcca","stones":10,"territory":3,"prisoners":2,"total":21.5}"#

        let score = try decoder.decode(PlayerScore.self, from: Data(payload.utf8))

        XCTAssertEqual(score.handicap, 0)
        XCTAssertEqual(score.komi, 6.5)
        XCTAssertEqual(score.stones, 10)
        XCTAssertEqual(score.territory, 3)
        XCTAssertEqual(score.prisoners, 2)
        XCTAssertEqual(score.total, 21.5)
        XCTAssertEqual(score.scoringPositions, Set([[1, 0], [2, 1], [0, 2]]))
    }

    func testClockDecodesStructuredThinkingTimeAndStartMode() throws {
        let payload = #"""
        {
          "black_player_id": 11,
          "white_player_id": 22,
          "current_player": 11,
          "last_move": 1700000000000,
          "start_mode": true,
          "paused_since": 1700000001000,
          "black_time": {
            "thinking_time": 600,
            "periods": 5,
            "period_time": 30,
            "moves_left": 10,
            "block_time": 180
          },
          "white_time": {
            "thinking_time": 590,
            "periods": 4,
            "period_time": 30,
            "moves_left": 9,
            "block_time": 170
          }
        }
        """#

        let clock = try decoder.decode(OGSClock.self, from: Data(payload.utf8))

        XCTAssertEqual(clock.currentPlayerColor, .black)
        XCTAssertEqual(clock.currentPlayerId, 11)
        XCTAssertEqual(clock.nextPlayerId(with: .black), 11)
        XCTAssertEqual(clock.nextPlayerId(with: .white), 22)
        XCTAssertFalse(clock.started)
        XCTAssertEqual(clock.lastMoveTime, 1_700_000_000_000)
        XCTAssertEqual(clock.pausedTime, 1_700_000_001_000)

        XCTAssertEqual(clock.blackTime.thinkingTime, 600)
        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 600)
        XCTAssertEqual(clock.blackTime.periodsLeft, 5)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 30)
        XCTAssertEqual(clock.blackTime.movesLeft, 10)
        XCTAssertEqual(clock.blackTime.blockTimeLeft, 180)

        XCTAssertEqual(clock.whiteTime.thinkingTime, 590)
        XCTAssertEqual(clock.whiteTime.thinkingTimeLeft, 590)
        XCTAssertEqual(clock.whiteTime.periodsLeft, 4)
        XCTAssertEqual(clock.whiteTime.periodTimeLeft, 30)
        XCTAssertEqual(clock.whiteTime.movesLeft, 9)
        XCTAssertEqual(clock.whiteTime.blockTimeLeft, 170)
    }

    func testThinkingTimeUsesOvertimeWhenMainTimeIsExhausted() {
        XCTAssertEqual(ThinkingTime(thinkingTime: 60, thinkingTimeLeft: 42).timeLeft, 42)
        XCTAssertEqual(
            ThinkingTime(thinkingTime: 60, thinkingTimeLeft: 0, periods: 5, periodsLeft: 4, periodTime: 30, periodTimeLeft: 18).timeLeft,
            18
        )
        XCTAssertEqual(
            ThinkingTime(thinkingTime: 60, thinkingTimeLeft: 0, movesLeft: 7, blockTime: 180, blockTimeLeft: 95).timeLeft,
            95
        )
    }

    func testUserDecodesCategoryRatingsAndHyphenatedIconURL() throws {
        let payload = #"""
        {
          "id": 1765,
          "username": "hakhoa",
          "icon-url": "https://example.test/avatar?s=32",
          "accepted_stones": "aabb",
          "accepted_strict_seki_mode": false,
          "ratings": {
            "overall": {"rating": 1510, "deviation": 120, "volatility": 0.06},
            "9x9": {"rating": 1450, "deviation": 130, "volatility": 0.07},
            "live-19x19": {"rating": 1600, "deviation": 100, "volatility": 0.05}
          }
        }
        """#

        let user = try decoder.decode(OGSUser.self, from: Data(payload.utf8))

        XCTAssertEqual(user.id, 1765)
        XCTAssertEqual(user.username, "hakhoa")
        XCTAssertEqual(user.iconUrl, "https://example.test/avatar?s=32")
        XCTAssertEqual(user.acceptedStones, "aabb")
        XCTAssertEqual(user.acceptedStrictSekiMode, false)
        XCTAssertEqual(user.ratings?[.overall]?.rating, 1510)
        XCTAssertEqual(user.ratings?[.overall_9x9]?.deviation, 130)
        XCTAssertEqual(user.ratings?[.live_19x19]?.volatility, 0.05)
        XCTAssertNil(user.ratings?[.blitz_overall])
    }
}
