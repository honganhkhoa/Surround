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
    private let conditionalMovesDecoder = JSONDecoder()

    func testChatLineDecodesFourPrimaryInboundChannels() throws {
        let channels: [OGSChatChannel] = [
            .main,
            .malkovich,
            .personal,
            .spectator,
        ]

        for channel in channels {
            let payload = #"""
            {
              "channel": "\#(channel.rawValue)",
              "line": {
                "body": "message on \#(channel.rawValue)",
                "chat_id": "chat-\#(channel.rawValue)",
                "date": 1700000000,
                "move_number": 12,
                "player_id": 42,
                "professional": false,
                "ranking": 25,
                "ui_class": "",
                "username": "chat-tester"
              }
            }
            """#

            let line = try decoder.decode(
                OGSChatLine.self,
                from: Data(payload.utf8)
            )

            XCTAssertEqual(line.channel, channel)
            XCTAssertEqual(line.id, "chat-\(channel.rawValue)")
            XCTAssertEqual(line.body, "message on \(channel.rawValue)")
            XCTAssertEqual(line.moveNumber, 12)
            XCTAssertEqual(line.user.id, 42)
        }
    }

    func testSendChannelResolutionPreservesPlayerSelectionsAndUsesMainForNonPlayers() {
        let channels: [OGSChatSendChannel] = [
            .main,
            .malkovich,
            .personal,
        ]

        for selectedChannel in channels {
            XCTAssertEqual(
                selectedChannel.resolved(isUserPlaying: true),
                selectedChannel
            )
            XCTAssertEqual(
                selectedChannel.resolved(isUserPlaying: false),
                .main
            )
        }
    }

    func testAnalysisChatBodyDecodesPackedMovesPassesAndEmptyPaths() throws {
        let line = try decodeChatLine(
            body: #"{"type":"analysis","from":7,"moves":"aa..BC","name":"Corner line"}"#
        )

        XCTAssertEqual(line.body, "Corner line")
        let variation = try XCTUnwrap(line.variationData)
        XCTAssertEqual(variation.fromMoveNumber, 7)
        XCTAssertEqual(variation.moves, "aa..BC")
        XCTAssertEqual(
            try variation.decodedMoves(boardWidth: 3, boardHeight: 3),
            [.placeStone(0, 0), .pass, .placeStone(2, 1)]
        )

        let emptyLine = try decodeChatLine(
            body: #"{"type":"analysis","from":0,"moves":"","name":"Empty"}"#
        )
        XCTAssertEqual(
            try XCTUnwrap(emptyLine.variationData).decodedMoves(
                boardWidth: 19,
                boardHeight: 19
            ),
            []
        )
    }

    func testAnalysisChatBodyDecodesMarksWithoutInvalidatingVariation() throws {
        let line = try decodeChatLine(
            body: #"{"type":"analysis","from":7,"moves":"aa","name":"Marked","marks":{"A":"ii","triangle":"hj","black":"aa"}}"#
        )
        let variation = try XCTUnwrap(line.variationData)
        let markups = variation.decodedMarkups(boardWidth: 19, boardHeight: 19)
        XCTAssertEqual(
            markups[BoardPoint(row: 8, column: 8)]?.label,
            "A"
        )
        XCTAssertEqual(
            markups[BoardPoint(row: 9, column: 7)]?.shapes,
            [.triangle]
        )
        XCTAssertNil(markups[BoardPoint(row: 0, column: 0)])

        let malformedMarks = try decodeChatLine(
            body: #"{"type":"analysis","from":0,"moves":"aa","name":"Still valid","marks":["not-a-map"]}"#
        )
        let malformedVariation = try XCTUnwrap(malformedMarks.variationData)
        XCTAssertEqual(malformedVariation.name, "Still valid")
        XCTAssertTrue(
            malformedVariation.decodedMarkups(
                boardWidth: 19,
                boardHeight: 19
            ).isEmpty
        )
    }

    func testMalformedAnalysisRemainsANameOnlyChatLine() throws {
        let edited = try decodeChatLine(
            body: #"{"type":"analysis","from":0,"moves":"!1aa","name":"Edited line"}"#
        )
        XCTAssertEqual(edited.body, "Edited line")
        XCTAssertNil(edited.variation)
        XCTAssertThrowsError(
            try XCTUnwrap(edited.variationData).decodedMoves(
                boardWidth: 19,
                boardHeight: 19
            )
        )

        let missingBase = try decodeChatLine(
            body: #"{"type":"analysis","moves":"aa","name":"Incomplete line"}"#
        )
        XCTAssertEqual(missingBase.body, "Incomplete line")
        XCTAssertNil(missingBase.variationData)
        XCTAssertNil(missingBase.variation)
    }

    func testUnsupportedStructuredChatBodiesFailLineDecoding() {
        let unsupportedBodies = [
            #"{"type":"future-analysis","from":0,"moves":"aa","name":"Future line"}"#,
            #"{"type":"translated","en":"Undo requested"}"#,
            #"{"type":"review","review_id":123}"#,
            #"{"type":"unknown","name":"Unknown line"}"#,
        ]

        for body in unsupportedBodies {
            XCTAssertThrowsError(try decodeChatLine(body: body), body)
        }
    }

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

    private func decodeChatLine(body: String) throws -> OGSChatLine {
        let payload = #"""
        {
          "channel": "main",
          "line": {
            "body": \#(body),
            "chat_id": "analysis-chat",
            "date": 1700000000,
            "move_number": 12,
            "player_id": 42,
            "professional": false,
            "ranking": 25,
            "ui_class": "",
            "username": "chat-tester"
          }
        }
        """#
        return try decoder.decode(OGSChatLine.self, from: Data(payload.utf8))
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

    func testConditionalMovesDecodesRuntimeTreeAndProtocolAlias() throws {
        let runtimePayload = #"""
        {
          "game_id": 42,
          "player_id": 7,
          "move_number": 60,
          "moves": [null, {
            "..": ["ll", {}],
            "jj": ["kj", {
              "ji": ["ki", {}],
              "jk": ["kk", {}]
            }]
          }]
        }
        """#
        let update = try conditionalMovesDecoder.decode(
            OGSConditionalMovesUpdate.self,
            from: Data(runtimePayload.utf8)
        )

        XCTAssertEqual(update.gameID, 42)
        XCTAssertEqual(update.playerID, 7)
        XCTAssertEqual(update.rootMoveNumber, 60)
        XCTAssertNil(update.root?.response)
        XCTAssertEqual(update.root?.children[".."]?.response, "ll")
        XCTAssertEqual(update.root?.children["jj"]?.response, "kj")
        XCTAssertEqual(update.root?.children["jj"]?.children["ji"]?.response, "ki")
        XCTAssertEqual(update.root?.children["jj"]?.children["jk"]?.response, "kk")
        let encodedRoot = try JSONEncoder().encode(XCTUnwrap(update.root))
        XCTAssertEqual(
            try JSONDecoder().decode(
                OGSConditionalMoveWireNode.self,
                from: encodedRoot
            ),
            update.root
        )

        let aliasPayload = runtimePayload.replacingOccurrences(
            of: "\"moves\"",
            with: "\"conditional_moves\""
        )
        XCTAssertEqual(
            try conditionalMovesDecoder.decode(
                OGSConditionalMovesUpdate.self,
                from: Data(aliasPayload.utf8)
            ),
            update
        )
    }

    func testConditionalMovesPreservesOpponentOnlyTerminalLeaf() throws {
        let update = try conditionalMovesDecoder.decode(
            OGSConditionalMovesUpdate.self,
            from: Data(
                #"{"game_id":42,"player_id":7,"move_number":0,"moves":[null,{"aa":[null,{}]}]}"#.utf8
            )
        )
        let wireRoot = try XCTUnwrap(update.root)
        XCTAssertNil(wireRoot.children["aa"]?.response)
        XCTAssertTrue(wireRoot.children["aa"]?.children.isEmpty == true)

        let decodedRoot = try XCTUnwrap(
            ConditionalMoveNode.decodedRoot(
                wireNode: wireRoot
            )
        )
        let validatedPlan = try XCTUnwrap(
            ConditionalMovePlan(
                gameID: 42,
                ownerID: 7,
                rootMoveNumber: 0,
                root: decodedRoot
            ).validated(width: 9, height: 9)
        )

        XCTAssertEqual(
            validatedPlan.orderedPaths().map(\.moves),
            [[.placeStone(0, 0)]]
        )
    }

    func testConditionalMovesDistinguishesClearAndRejectsAmbiguousEnvelope() throws {
        let nullUpdate = try conditionalMovesDecoder.decode(
            OGSConditionalMovesUpdate.self,
            from: Data(#"{"move_number":12,"moves":null}"#.utf8)
        )
        XCTAssertNil(nullUpdate.root)

        let emptyUpdate = try conditionalMovesDecoder.decode(
            OGSConditionalMovesUpdate.self,
            from: Data(#"{"move_number":12,"conditional_moves":[null,{}]}"#.utf8)
        )
        XCTAssertNotNil(emptyUpdate.root)
        XCTAssertTrue(emptyUpdate.root?.children.isEmpty == true)

        XCTAssertThrowsError(
            try conditionalMovesDecoder.decode(
                OGSConditionalMovesUpdate.self,
                from: Data(#"{"move_number":12}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try conditionalMovesDecoder.decode(
                OGSConditionalMovesUpdate.self,
                from: Data(
                    #"{"move_number":12,"moves":[null,{}],"conditional_moves":[null,{"aa":["bb",{}]}]}"#.utf8
                )
            )
        )
        XCTAssertThrowsError(
            try conditionalMovesDecoder.decode(
                OGSConditionalMovesUpdate.self,
                from: Data(#"{"move_number":-1,"moves":[null,{}]}"#.utf8)
            )
        )
    }

    func testConditionalMovesDropsMalformedBranchesWithoutLosingValidSiblings() throws {
        let payload = #"""
        {
          "move_number": 0,
          "moves": [null, {
            "aa": ["bb", {}],
            "cc": ["DD", {}],
            "dd": [null, {"ee": ["ff"]}],
            "ee": ["ff", {"gg": ["hh"]}]
          }]
        }
        """#
        let update = try conditionalMovesDecoder.decode(
            OGSConditionalMovesUpdate.self,
            from: Data(payload.utf8)
        )
        let wireRoot = try XCTUnwrap(update.root)
        let decodedRoot = try XCTUnwrap(
            ConditionalMoveNode.decodedRoot(
                wireNode: wireRoot
            )
        )
        let root = try XCTUnwrap(
            ConditionalMovePlan(
                gameID: 1,
                ownerID: nil,
                rootMoveNumber: 0,
                root: decodedRoot
            ).validated(width: 9, height: 9)
        ).root

        XCTAssertNotNil(root.children[.placeStone(0, 0)])
        XCTAssertNil(root.children[.placeStone(2, 2)])
        XCTAssertNil(root.children[.placeStone(3, 3)])
        XCTAssertEqual(root.children[.placeStone(4, 4)]?.response, .placeStone(5, 5))
        XCTAssertTrue(root.children[.placeStone(4, 4)]?.children.isEmpty == true)

        XCTAssertThrowsError(
            try conditionalMovesDecoder.decode(
                OGSConditionalMovesUpdate.self,
                from: Data(
                    #"{"move_number":0,"moves":[null,{"aa":["bb"]}]}"#.utf8
                )
            )
        )
    }
}
