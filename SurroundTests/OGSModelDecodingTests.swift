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

    func testChatLineDecodesAllInboundChannels() throws {
        let channels: [OGSChatChannel] = [
            .main,
            .hidden,
            .malkovich,
            .personal,
            .shadowban,
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

    func testAnalysisChatBodyDecodesLegacyBranchMoveAndOptionalFields() throws {
        let legacy = try decodeChatLine(
            body: #"{"type":"analysis","branch_move":8,"moves":"aa","name":"Legacy line"}"#
        )
        XCTAssertEqual(legacy.body, "Legacy line")
        XCTAssertTrue(legacy.isAnalysis)
        XCTAssertEqual(legacy.variationData?.fromMoveNumber, 7)

        let unnamed = try decodeChatLine(
            body: #"{"type":"analysis","from":0,"moves":""}"#
        )
        XCTAssertEqual(unnamed.body, "")
        XCTAssertEqual(unnamed.variationData?.name, "")

        let nameOnly = try decodeChatLine(
            body: #"{"type":"analysis","name":"Name only","pen_marks":[],"engine_analysis":{"win_rate":0.5}}"#
        )
        XCTAssertEqual(nameOnly.body, "Name only")
        XCTAssertTrue(nameOnly.isAnalysis)
        XCTAssertNil(nameOnly.variationData)

        let malformedOptionalFields = try decodeChatLine(
            body: #"{"type":"analysis","branch_move":"invalid","from":5,"moves":"aa","name":42,"marks":["not-a-map"]}"#
        )
        XCTAssertEqual(malformedOptionalFields.body, "")
        XCTAssertTrue(malformedOptionalFields.isAnalysis)
        let recoveredVariation = try XCTUnwrap(
            malformedOptionalFields.variationData
        )
        XCTAssertEqual(recoveredVariation.fromMoveNumber, 5)
        XCTAssertEqual(recoveredVariation.moves, "aa")
        XCTAssertEqual(recoveredVariation.name, "")
        XCTAssertTrue(
            recoveredVariation.decodedMarkups(
                boardWidth: 19,
                boardHeight: 19
            ).isEmpty
        )

        let underflowingLegacyBranch = try decodeChatLine(
            body: #"{"type":"analysis","branch_move":\#(Int.min),"from":6,"moves":"aa","name":"Checked legacy branch"}"#
        )
        XCTAssertEqual(
            underflowingLegacyBranch.variationData?.fromMoveNumber,
            6
        )
    }

    func testOnlyPlainStringBodiesCarryPlainTextSemantics() throws {
        let plain = try decodeChatLine(body: #""/me waves""#)
        let translated = try decodeChatLine(
            body: #"{"type":"translated","en":"/me waves"}"#,
            preferredLanguages: ["en"]
        )
        let analysis = try decodeChatLine(
            body: #"{"type":"analysis","from":0,"moves":"aa","name":"/me variation"}"#
        )

        XCTAssertTrue(plain.isPlainTextBody)
        XCTAssertEqual(plain.body, "/me waves")
        XCTAssertFalse(translated.isPlainTextBody)
        XCTAssertEqual(translated.body, "/me waves")
        XCTAssertFalse(analysis.isPlainTextBody)
        XCTAssertEqual(analysis.body, "/me variation")
    }

    func testChatCoordinatesHandleNonBMPTextBeforeCoordinate() throws {
        var plain = try decodeChatLine(body: #""👍 c4 is good""#)
        var translated = try decodeChatLine(
            body: #"{"type":"translated","en":"👍 c4 is good"}"#,
            preferredLanguages: ["en"]
        )

        XCTAssertEqual(plain.coordinates, [[3, 2]])
        XCTAssertEqual(translated.coordinates, [[3, 2]])
    }

    func testTranslatedChatBodySelectsExactNormalizedAndBaseLanguages() throws {
        let exact = try decodeChatLine(
            body: #"{"type":"translated","fr-ca":"Allô","fr":"Bonjour","en":"Hello"}"#,
            preferredLanguages: ["FR_ca"]
        )
        XCTAssertEqual(exact.body, "Allô")

        let base = try decodeChatLine(
            body: #"{"type":"translated","pt":"Olá","en":"Hello"}"#,
            preferredLanguages: ["pt-BR"]
        )
        XCTAssertEqual(base.body, "Olá")

        let englishBeforeSecondaryPreference = try decodeChatLine(
            body: #"{"type":"translated","fr":"Bonjour","en":"Hello"}"#,
            preferredLanguages: ["de-DE", "fr-FR"]
        )
        XCTAssertEqual(englishBeforeSecondaryPreference.body, "Hello")
    }

    func testTranslatedChatBodyMapsAppleChineseLocalesToOGSKeys() throws {
        let traditional = try decodeChatLine(
            body: #"{"type":"translated","zh-tw":"對局開始","en":"Game started"}"#,
            preferredLanguages: ["zh-Hant-HK"]
        )
        XCTAssertEqual(traditional.body, "對局開始")

        let simplified = try decodeChatLine(
            body: #"{"type":"translated","zh-cn":"对局开始","en":"Game started"}"#,
            preferredLanguages: ["zh_Hans_SG"]
        )
        XCTAssertEqual(simplified.body, "对局开始")

        let scriptTakesPrecedenceOverRegion = try decodeChatLine(
            body: #"{"type":"translated","zh-tw":"繁體","zh-cn":"简体"}"#,
            preferredLanguages: ["zh-Hant-CN"]
        )
        XCTAssertEqual(scriptTakesPrecedenceOverRegion.body, "繁體")
    }

    func testTranslatedChatBodyUsesEnglishAvailableAndUnavailableFallbacks() throws {
        let english = try decodeChatLine(
            body: #"{"type":"translated","en":"Undo requested","fr":"Annulation demandée"}"#,
            preferredLanguages: ["de-DE"]
        )
        XCTAssertEqual(english.body, "Undo requested")

        let available = try decodeChatLine(
            body: #"{"type":"translated","fr":"Annulation demandée"}"#,
            preferredLanguages: ["de-DE"]
        )
        XCTAssertEqual(available.body, "Annulation demandée")

        let unavailable = try decodeChatLine(
            body: #"{"type":"translated","en":""}"#,
            preferredLanguages: ["en"]
        )
        XCTAssertEqual(
            unavailable.body,
            String(localized: "[Message unavailable in this language]")
        )
    }

    func testReviewAndUnknownStructuredChatBodiesRemainVisible() throws {
        let review = try decodeChatLine(
            body: #"{"type":"review","review_id":90212712}"#
        )
        XCTAssertEqual(review.reviewID, 90212712)
        XCTAssertEqual(review.body, "")
        XCTAssertFalse(review.isPlainTextBody)

        let unknownBodies = [
            #"{"type":"future-analysis","from":0,"moves":"aa","name":"Future line"}"#,
            #"{"type":"unknown","name":"Unknown line"}"#,
            #"{"type":"review"}"#,
            #"["unexpected", "shape"]"#,
        ]

        for body in unknownBodies {
            XCTAssertEqual(
                try decodeChatLine(body: body).body,
                String(localized: "[Unknown chat message]"),
                body
            )
        }
    }

    func testChatLineAllowsNullMoveNumberAndMissingOptionalUserMetadata() throws {
        let payload = #"""
        {
          "channel": "main",
          "line": {
            "body": {"type":"translated","en":"System message"},
            "chat_id": "system-chat",
            "date": 1700000000,
            "move_number": null,
            "player_id": "0"
          }
        }
        """#
        let line = try decoder.decode(
            OGSChatLine.self,
            from: Data(payload.utf8)
        )

        XCTAssertNil(line.moveNumber)
        XCTAssertEqual(line.body, "System message")
        XCTAssertEqual(line.user.id, 0)
        XCTAssertEqual(line.user.username, "")
        XCTAssertNil(line.user.ranking)
        XCTAssertNil(line.user.professional)
        XCTAssertNil(line.user.uiClass)
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

    private func decodeChatLine(
        body: String,
        preferredLanguages: [String]? = nil
    ) throws -> OGSChatLine {
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
        let chatDecoder = JSONDecoder()
        chatDecoder.keyDecodingStrategy = .convertFromSnakeCase
        if let preferredLanguages {
            chatDecoder.userInfo[.ogsChatPreferredLanguageIdentifiers] = preferredLanguages
        }
        return try chatDecoder.decode(OGSChatLine.self, from: Data(payload.utf8))
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

final class OGSQuickMatchContractTests: XCTestCase {
    private struct LegacyStoredAutomatchEntry: Decodable {
        let sizeOptions: Set<Int>
        let timeControlSpeed: TimeControlSpeed
        let uuid: String
    }

    func testOfficialPresetMatrixMatchesOGSReference() throws {
        struct ExpectedPreset {
            let size: Int
            let speed: TimeControlSpeed
            let system: OGSAutomatchClockSystem
            let timeControl: TimeControlSystem
            let duration: Int?
        }

        let expected = [
            ExpectedPreset(
                size: 9,
                speed: .blitz,
                system: .fischer,
                timeControl: .Fischer(initialTime: 30, timeIncrement: 5, maxTime: 300),
                duration: 300
            ),
            ExpectedPreset(
                size: 9,
                speed: .blitz,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 30, periods: 5, periodTime: 10),
                duration: 300
            ),
            ExpectedPreset(
                size: 9,
                speed: .rapid,
                system: .fischer,
                timeControl: .Fischer(initialTime: 120, timeIncrement: 7, maxTime: 1200),
                duration: 600
            ),
            ExpectedPreset(
                size: 9,
                speed: .rapid,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 120, periods: 5, periodTime: 30),
                duration: 600
            ),
            ExpectedPreset(
                size: 9,
                speed: .live,
                system: .fischer,
                timeControl: .Fischer(initialTime: 180, timeIncrement: 10, maxTime: 1800),
                duration: 900
            ),
            ExpectedPreset(
                size: 9,
                speed: .live,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 300, periods: 5, periodTime: 30),
                duration: 900
            ),
            ExpectedPreset(
                size: 9,
                speed: .correspondence,
                system: .fischer,
                timeControl: .Fischer(
                    initialTime: 3 * 86400,
                    timeIncrement: 86400,
                    maxTime: 7 * 86400
                ),
                duration: nil
            ),
            ExpectedPreset(
                size: 13,
                speed: .blitz,
                system: .fischer,
                timeControl: .Fischer(initialTime: 30, timeIncrement: 5, maxTime: 300),
                duration: 600
            ),
            ExpectedPreset(
                size: 13,
                speed: .blitz,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 30, periods: 5, periodTime: 10),
                duration: 600
            ),
            ExpectedPreset(
                size: 13,
                speed: .rapid,
                system: .fischer,
                timeControl: .Fischer(initialTime: 180, timeIncrement: 7, maxTime: 1800),
                duration: 1200
            ),
            ExpectedPreset(
                size: 13,
                speed: .rapid,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 180, periods: 5, periodTime: 30),
                duration: 1200
            ),
            ExpectedPreset(
                size: 13,
                speed: .live,
                system: .fischer,
                timeControl: .Fischer(initialTime: 300, timeIncrement: 10, maxTime: 1800),
                duration: 1800
            ),
            ExpectedPreset(
                size: 13,
                speed: .live,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 600, periods: 5, periodTime: 30),
                duration: 1800
            ),
            ExpectedPreset(
                size: 13,
                speed: .correspondence,
                system: .fischer,
                timeControl: .Fischer(
                    initialTime: 3 * 86400,
                    timeIncrement: 86400,
                    maxTime: 7 * 86400
                ),
                duration: nil
            ),
            ExpectedPreset(
                size: 19,
                speed: .blitz,
                system: .fischer,
                timeControl: .Fischer(initialTime: 30, timeIncrement: 5, maxTime: 300),
                duration: 900
            ),
            ExpectedPreset(
                size: 19,
                speed: .blitz,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 30, periods: 5, periodTime: 10),
                duration: 900
            ),
            ExpectedPreset(
                size: 19,
                speed: .rapid,
                system: .fischer,
                timeControl: .Fischer(initialTime: 300, timeIncrement: 7, maxTime: 3000),
                duration: 1500
            ),
            ExpectedPreset(
                size: 19,
                speed: .rapid,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 300, periods: 5, periodTime: 30),
                duration: 1500
            ),
            ExpectedPreset(
                size: 19,
                speed: .live,
                system: .fischer,
                timeControl: .Fischer(initialTime: 600, timeIncrement: 10, maxTime: 3600),
                duration: 2400
            ),
            ExpectedPreset(
                size: 19,
                speed: .live,
                system: .byoyomi,
                timeControl: .ByoYomi(mainTime: 1200, periods: 5, periodTime: 30),
                duration: 2400
            ),
            ExpectedPreset(
                size: 19,
                speed: .correspondence,
                system: .fischer,
                timeControl: .Fischer(
                    initialTime: 3 * 86400,
                    timeIncrement: 86400,
                    maxTime: 7 * 86400
                ),
                duration: nil
            ),
        ]

        XCTAssertEqual(expected.count, 21)
        XCTAssertEqual(
            OGSQuickMatchClockPreset.supportedBoardSizes.flatMap {
                OGSQuickMatchClockPreset.presets(for: $0)
            }.count,
            21
        )
        for item in expected {
            let preset = try XCTUnwrap(
                OGSQuickMatchClockPreset.preset(
                    boardSize: item.size,
                    speed: item.speed,
                    system: item.system
                )
            )
            XCTAssertEqual(preset.boardSize, item.size)
            XCTAssertEqual(preset.speed, item.speed)
            XCTAssertEqual(preset.system, item.system)
            XCTAssertEqual(preset.timeControl, item.timeControl)
            XCTAssertEqual(preset.estimatedGameDuration, item.duration)
        }
    }

    func testPresetRetainsDeclaredRapidSpeedInsteadOfHeuristicClassification() throws {
        let preset = try XCTUnwrap(
            OGSQuickMatchClockPreset.preset(
                boardSize: 9,
                speed: .rapid,
                system: .fischer
            )
        )

        XCTAssertEqual(preset.speed, .rapid)
        XCTAssertEqual(preset.timeControl.speed, .blitz)
        XCTAssertNil(
            OGSQuickMatchClockPreset.preset(
                boardSize: 9,
                speed: .correspondence,
                system: .byoyomi
            )
        )
    }

    func testDefaultDraftMatchesOGSQuickMatchDefaults() {
        let draft = OGSQuickMatchDraft.ogsDefault

        XCTAssertEqual(draft.schemaVersion, 1)
        XCTAssertEqual(draft.mode, .flexible)
        XCTAssertEqual(draft.boardSize, 9)
        XCTAssertEqual(draft.speed, .rapid)
        XCTAssertEqual(draft.system, .fischer)
        XCTAssertTrue(draft.multipleBoardSizes.isEmpty)
        XCTAssertTrue(draft.multipleClocks.isEmpty)
        XCTAssertEqual(draft.handicap, .standard)
        XCTAssertEqual(draft.lowerRankDifference, 3)
        XCTAssertEqual(draft.upperRankDifference, 3)
    }

    func testExactBuildsOneOrderedTupleAndClampsRankDifferences() {
        let draft = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .byoyomi,
            handicap: .required,
            lowerRankDifference: -2,
            upperRankDifference: 12
        )

        let entry = draft.makeAutomatchEntry(uuid: "EXACT-ID")

        XCTAssertEqual(entry.uuid, "exact-id")
        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 13,
                    speed: .rapid,
                    system: .byoyomi
                ),
            ]
        )
        XCTAssertEqual(entry.lowerRankDifference, 0)
        XCTAssertEqual(entry.upperRankDifference, 9)
        XCTAssertEqual(entry.rules, .quickMatchDefault)
        XCTAssertEqual(
            entry.handicap,
            OGSAutomatchHandicapPreference(
                condition: .required,
                value: .enabled
            )
        )
    }

    func testFlexibleBuildsPrimaryThenAlternateClockSystem() {
        let entry = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 19,
            speed: .live,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "flexible-id")

        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .live,
                    system: .byoyomi
                ),
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .live,
                    system: .fischer
                ),
            ]
        )
    }

    func testFlexibleCorrespondenceBuildsOnlyFischer() {
        let entry = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 9,
            speed: .correspondence,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "correspondence-id")

        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .correspondence,
                    system: .fischer
                ),
            ]
        )
    }

    func testWaitingRequestClassificationCoversEveryWireShape() throws {
        let exact = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .fischer,
            handicap: .required,
            lowerRankDifference: 2,
            upperRankDifference: 4
        ).makeAutomatchEntry(uuid: "exact-presentation")
        let flexible = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 19,
            speed: .live,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "flexible-presentation")
        let multiple = OGSQuickMatchDraft(
            mode: .multiple,
            multipleBoardSizes: [9, 19],
            multipleClocks: [
                OGSQuickMatchClockSelection(
                    speed: .blitz,
                    system: .fischer
                ),
                OGSQuickMatchClockSelection(
                    speed: .rapid,
                    system: .byoyomi
                ),
            ],
            handicap: .disabled
        ).makeAutomatchEntry(
            uuid: "multiple-presentation",
            multipleOptionsShuffler: { _ in }
        )
        let legacyWire = try XCTUnwrap(
            OGSAutomatchEntry([
                "uuid": "legacy-presentation",
                "size_speed_options": [
                    ["size": "9x9", "speed": "live"],
                    ["size": "13x13", "speed": "live"],
                ],
                "time_control": [
                    "condition": "no-preference",
                    "value": ["speed": "live", "system": "byoyomi"],
                ],
            ])
        )
        let correspondence = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 19,
            speed: .correspondence,
            system: .fischer
        ).makeAutomatchEntry(uuid: "correspondence-presentation")

        XCTAssertEqual(exact.sizeOptions, [13])
        XCTAssertEqual(exact.sizeSpeedOptions.count, 1)
        XCTAssertEqual(flexible.sizeOptions, [19])
        XCTAssertEqual(flexible.sizeSpeedOptions.count, 2)
        XCTAssertEqual(multiple.sizeOptions, [9, 19])
        XCTAssertEqual(multiple.sizeSpeedOptions.count, 4)
        XCTAssertEqual(legacyWire.sizeOptions, [9, 13])
        XCTAssertEqual(legacyWire.sizeSpeedOptions.map(\.system), [
            .byoyomi,
            .byoyomi,
        ])
        XCTAssertEqual(correspondence.sizeOptions, [19])
        XCTAssertFalse(exact.isCorrespondence)
        XCTAssertFalse(flexible.isCorrespondence)
        XCTAssertFalse(multiple.isCorrespondence)
        XCTAssertFalse(legacyWire.isCorrespondence)
        XCTAssertTrue(correspondence.isCorrespondence)
    }

    func testMultipleBuildsUniqueEighteenTupleCartesianProduct() {
        let draft = OGSQuickMatchDraft(
            mode: .multiple,
            multipleBoardSizes: [9, 13, 19],
            multipleClocks: Set(OGSQuickMatchClockSelection.allRealtime)
        )

        let entry = draft.makeAutomatchEntry(
            uuid: "multiple-id",
            multipleOptionsShuffler: { _ in }
        )
        let expected = Set(
            [9, 13, 19].flatMap { size in
                OGSQuickMatchClockSelection.allRealtime.map { clock in
                    OGSAutomatchSizeSpeedOption(
                        size: size,
                        speed: clock.speed,
                        system: clock.system
                    )
                }
            }
        )

        XCTAssertEqual(entry.sizeSpeedOptions.count, 18)
        XCTAssertEqual(Set(entry.sizeSpeedOptions).count, 18)
        XCTAssertEqual(Set(entry.sizeSpeedOptions), expected)
        XCTAssertFalse(entry.sizeSpeedOptions.contains { $0.speed == .correspondence })
    }

    func testMultipleUsesTheInjectedShuffleOperation() {
        let draft = OGSQuickMatchDraft(
            mode: .multiple,
            multipleBoardSizes: [9, 13],
            multipleClocks: [
                OGSQuickMatchClockSelection(speed: .blitz, system: .fischer),
                OGSQuickMatchClockSelection(speed: .rapid, system: .byoyomi),
            ]
        )
        let ordered = draft.makeAutomatchEntry(
            uuid: "ordered-id",
            multipleOptionsShuffler: { _ in }
        ).sizeSpeedOptions
        var invoked = false

        let shuffled = draft.makeAutomatchEntry(
            uuid: "shuffled-id",
            multipleOptionsShuffler: {
                invoked = true
                $0.reverse()
            }
        ).sizeSpeedOptions

        XCTAssertTrue(invoked)
        XCTAssertEqual(shuffled, Array(ordered.reversed()))
    }

    func testEmptyMultipleSelectionsUseThePreviousSingleSelections() {
        let entry = OGSQuickMatchDraft(
            mode: .multiple,
            boardSize: 13,
            speed: .correspondence,
            system: .byoyomi
        ).makeAutomatchEntry(
            uuid: "seeded-id",
            multipleOptionsShuffler: { _ in }
        )

        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 13,
                    speed: .rapid,
                    system: .byoyomi
                ),
            ]
        )
    }

    func testPayloadMatchesOfficialShape() throws {
        let payload = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .fischer,
            handicap: .standard,
            lowerRankDifference: 2,
            upperRankDifference: 5
        ).makeAutomatchEntry(uuid: "PAYLOAD-ID").jsonObject

        XCTAssertEqual(
            Set(payload.keys),
            Set([
                "uuid",
                "size_speed_options",
                "lower_rank_diff",
                "upper_rank_diff",
                "rules",
                "handicap",
            ])
        )
        XCTAssertNil(payload["time_control"])
        XCTAssertEqual(payload["uuid"] as? String, "payload-id")
        XCTAssertEqual(payload["lower_rank_diff"] as? Int, 2)
        XCTAssertEqual(payload["upper_rank_diff"] as? Int, 5)

        let options = try XCTUnwrap(
            payload["size_speed_options"] as? [[String: Any]]
        )
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0]["size"] as? String, "13x13")
        XCTAssertEqual(options[0]["speed"] as? String, "rapid")
        XCTAssertEqual(options[0]["system"] as? String, "fischer")

        let rules = try XCTUnwrap(payload["rules"] as? [String: Any])
        XCTAssertEqual(rules["condition"] as? String, "required")
        XCTAssertEqual(rules["value"] as? String, "japanese")
        let handicap = try XCTUnwrap(payload["handicap"] as? [String: Any])
        XCTAssertEqual(handicap["condition"] as? String, "preferred")
        XCTAssertEqual(handicap["value"] as? String, "enabled")
    }

    func testHandicapPayloadMappings() {
        let expected: [
            OGSQuickMatchHandicapPreference: OGSAutomatchHandicapPreference
        ] = [
            .required: OGSAutomatchHandicapPreference(
                condition: .required,
                value: .enabled
            ),
            .standard: OGSAutomatchHandicapPreference(
                condition: .preferred,
                value: .enabled
            ),
            .disabled: OGSAutomatchHandicapPreference(
                condition: .required,
                value: .disabled
            ),
        ]

        for (selection, preference) in expected {
            let entry = OGSQuickMatchDraft(
                mode: .exact,
                handicap: selection
            ).makeAutomatchEntry(uuid: "handicap-id")
            XCTAssertEqual(entry.handicap, preference)
        }
    }

    func testInboundEntryRetainsAllModernPreferences() throws {
        let payload: [String: Any] = [
            "uuid": "incoming-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
                ["size": "19x19", "speed": "live", "system": "byoyomi"],
            ],
            "lower_rank_diff": 1,
            "upper_rank_diff": 8,
            "rules": ["condition": "required", "value": "japanese"],
            "handicap": ["condition": "required", "value": "disabled"],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.sizeSpeedOptions.count, 2)
        XCTAssertEqual(entry.sizeOptions, [9, 19])
        XCTAssertEqual(entry.lowerRankDifference, 1)
        XCTAssertEqual(entry.upperRankDifference, 8)
        XCTAssertEqual(entry.rules.condition, .required)
        XCTAssertEqual(entry.handicap.condition, .required)
        XCTAssertEqual(entry.handicap.value, .disabled)
    }

    func testInboundJSONRankDifferencesDistinguishNumbersFromBooleans() throws {
        for difference in 0...2 {
            let data = Data(
                """
                {
                  "uuid": "rank-\(difference)",
                  "size_speed_options": [
                    {"size": "9x9", "speed": "rapid", "system": "fischer"}
                  ],
                  "lower_rank_diff": \(difference),
                  "upper_rank_diff": \(difference),
                  "rules": {"condition": "required", "value": "japanese"},
                  "handicap": {"condition": "preferred", "value": "enabled"}
                }
                """.utf8
            )
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

            XCTAssertEqual(entry.lowerRankDifference, difference)
            XCTAssertEqual(entry.upperRankDifference, difference)
            XCTAssertTrue(entry.quickMatchDisplayIsComplete)
            XCTAssertNotNil(OGSActiveQuickMatchPresentation(entry: entry))
        }

        for boolean in ["false", "true"] {
            let data = Data(
                """
                {
                  "uuid": "rank-\(boolean)",
                  "size_speed_options": [
                    {"size": "9x9", "speed": "rapid", "system": "fischer"}
                  ],
                  "lower_rank_diff": \(boolean),
                  "upper_rank_diff": \(boolean),
                  "rules": {"condition": "required", "value": "japanese"},
                  "handicap": {"condition": "preferred", "value": "enabled"}
                }
                """.utf8
            )
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

            XCTAssertEqual(entry.lowerRankDifference, 3)
            XCTAssertEqual(entry.upperRankDifference, 3)
            XCTAssertFalse(entry.quickMatchDisplayIsComplete)
            XCTAssertNil(OGSActiveQuickMatchPresentation(entry: entry))
        }
    }

    func testInboundJSONMarksMalformedPreferenceContainersAsDegraded() throws {
        let malformedValues = [#""future-shape""#, "[]", "null"]

        for malformedValue in malformedValues {
            for malformedKey in ["rules", "handicap"] {
                let rules = malformedKey == "rules"
                    ? malformedValue
                    : #"{"condition":"required","value":"japanese"}"#
                let handicap = malformedKey == "handicap"
                    ? malformedValue
                    : #"{"condition":"preferred","value":"enabled"}"#
                let data = Data(
                    """
                    {
                      "uuid": "malformed-\(malformedKey)",
                      "size_speed_options": [
                        {"size": "9x9", "speed": "rapid", "system": "fischer"}
                      ],
                      "lower_rank_diff": 3,
                      "upper_rank_diff": 3,
                      "rules": \(rules),
                      "handicap": \(handicap)
                    }
                    """.utf8
                )
                let payload = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

                XCTAssertFalse(
                    entry.quickMatchDisplayIsComplete,
                    "\(malformedKey) value \(malformedValue) must degrade display."
                )
            }
        }
    }

    func testInboundJSONMarksIncompletePreferenceContainersAsDegraded() throws {
        let incompleteRules = [
            "{}",
            #"{"condition":"required"}"#,
            #"{"value":"japanese"}"#,
        ]
        let incompleteHandicaps = [
            "{}",
            #"{"condition":"preferred"}"#,
            #"{"value":"enabled"}"#,
        ]

        for (incompleteKey, incompleteValues) in [
            ("rules", incompleteRules),
            ("handicap", incompleteHandicaps),
        ] {
            for incompleteValue in incompleteValues {
                let rules = incompleteKey == "rules"
                    ? incompleteValue
                    : #"{"condition":"required","value":"japanese"}"#
                let handicap = incompleteKey == "handicap"
                    ? incompleteValue
                    : #"{"condition":"preferred","value":"enabled"}"#
                let data = Data(
                    """
                    {
                      "uuid": "incomplete-\(incompleteKey)",
                      "size_speed_options": [
                        {"size": "9x9", "speed": "rapid", "system": "fischer"}
                      ],
                      "lower_rank_diff": 3,
                      "upper_rank_diff": 3,
                      "rules": \(rules),
                      "handicap": \(handicap)
                    }
                    """.utf8
                )
                let payload = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

                XCTAssertFalse(
                    entry.quickMatchDisplayIsComplete,
                    "\(incompleteKey) value \(incompleteValue) must degrade display."
                )
            }
        }
    }

    func testInboundJSONKeepsAbsentPreferenceContainersAsLegacyDefaults() throws {
        let data = Data(
            """
            {
              "uuid": "legacy-missing-preferences",
              "size_speed_options": [
                {"size": "9x9", "speed": "rapid", "system": "fischer"}
              ],
              "lower_rank_diff": 3,
              "upper_rank_diff": 3
            }
            """.utf8
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(
            entry.rules,
            OGSAutomatchRulesPreference(
                condition: .noPreference,
                value: .japanese
            )
        )
        XCTAssertEqual(
            entry.handicap,
            OGSAutomatchHandicapPreference(
                condition: .noPreference,
                value: .enabled
            )
        )
        XCTAssertTrue(entry.quickMatchDisplayIsComplete)
    }

    func testInboundAutomatchTimestampIsNormalizedAndOnlyPersistedLocally() throws {
        for wireTimestamp in ["1725312345.678", "1725312345678"] {
            let data = Data(
                """
                {
                  "uuid": "timestamped-entry",
                  "timestamp": \(wireTimestamp),
                  "size_speed_options": [
                    {"size": "9x9", "speed": "rapid", "system": "fischer"}
                  ],
                  "lower_rank_diff": 3,
                  "upper_rank_diff": 3,
                  "rules": {"condition": "required", "value": "japanese"},
                  "handicap": {"condition": "preferred", "value": "enabled"}
                }
                """.utf8
            )
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

            XCTAssertEqual(
                try XCTUnwrap(entry.creationTimestamp),
                1_725_312_345.678,
                accuracy: 0.000_001
            )
            XCTAssertNil(entry.jsonObject["timestamp"])
            XCTAssertNil(entry.jsonObject["creationTimestamp"])

            let persisted = try JSONEncoder().encode(entry)
            let restored = try JSONDecoder().decode(
                OGSAutomatchEntry.self,
                from: persisted
            )
            XCTAssertEqual(restored, entry)
            XCTAssertEqual(
                try XCTUnwrap(restored.creationTimestamp),
                1_725_312_345.678,
                accuracy: 0.000_001
            )
        }
    }

    func testLegacyWireEntryUsesTopLevelClockAsSystemFallback() throws {
        let payload: [String: Any] = [
            "uuid": "legacy-wire-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "live"],
                ["size": "13x13", "speed": "live"],
            ],
            "time_control": [
                "condition": "no-preference",
                "value": ["system": "byoyomi"],
            ],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.sizeSpeedOptions.map(\.system), [.byoyomi, .byoyomi])
        XCTAssertEqual(entry.rules.condition, .noPreference)
        XCTAssertEqual(entry.handicap.condition, .noPreference)
    }

    func testInboundEntrySkipsUnknownOptionsAndKeepsValidOnes() throws {
        let payload: [String: Any] = [
            "uuid": "partially-readable-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
                ["size": "9x9", "speed": "rapid", "system": "canadian"],
                ["size": "13x13", "speed": "hyper", "system": "fischer"],
                ["size": "19x13", "speed": "rapid", "system": "byoyomi"],
            ],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.uuid, "partially-readable-id")
        XCTAssertEqual(
            entry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .rapid,
                    system: .fischer
                ),
            ]
        )
    }

    func testInboundEntryRetainsUUIDWhenEveryOptionIsUnknown() throws {
        let payload: [String: Any] = [
            "uuid": "future-options-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "canadian"],
                ["size": "13x13", "speed": "hyper", "system": "fischer"],
            ],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.uuid, "future-options-id")
        XCTAssertTrue(entry.sizeSpeedOptions.isEmpty)
        XCTAssertEqual(entry.timeControlSpeed, .rapid)
        XCTAssertFalse(entry.isCorrespondence)
    }

    func testInboundUnknownClockSystemPreservesCorrespondenceClassification() throws {
        let payload: [String: Any] = [
            "uuid": "future-correspondence-id",
            "size_speed_options": [
                [
                    "size": "19x19",
                    "speed": "correspondence",
                    "system": "future-correspondence-clock",
                ],
            ],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertTrue(entry.sizeSpeedOptions.isEmpty)
        XCTAssertEqual(entry.timeControlSpeed, .correspondence)
        XCTAssertTrue(entry.isCorrespondence)

        let persisted = try JSONEncoder().encode(entry)
        let restored = try JSONDecoder().decode(
            OGSAutomatchEntry.self,
            from: persisted
        )
        XCTAssertEqual(restored.timeControlSpeed, .correspondence)
        XCTAssertTrue(restored.isCorrespondence)
    }

    func testInboundEntryStillRequiresANonblankUUID() {
        let options: [[String: Any]] = [
            ["size": "9x9", "speed": "rapid", "system": "fischer"],
        ]

        XCTAssertNil(OGSAutomatchEntry(["size_speed_options": options]))
        XCTAssertNil(OGSAutomatchEntry([
            "uuid": " \n\t ",
            "size_speed_options": options,
        ]))
    }

    func testInboundEntryDefaultsUnknownPreferenceFieldsIndependently() throws {
        let payload: [String: Any] = [
            "uuid": "future-preferences-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "rules": ["condition": "optional", "value": "chinese"],
            "handicap": ["condition": "required", "value": "automatic"],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.rules.condition, .noPreference)
        XCTAssertEqual(entry.rules.value, .chinese)
        XCTAssertEqual(entry.handicap.condition, .required)
        XCTAssertEqual(entry.handicap.value, .enabled)
    }

    func testInboundEntryDefaultsMalformedPreferenceObjectsIndependently() throws {
        let malformedRulesPayload: [String: Any] = [
            "uuid": "malformed-rules-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "rules": "future-rules-shape",
            "handicap": ["condition": "required", "value": "disabled"],
        ]
        let malformedRulesEntry = try XCTUnwrap(
            OGSAutomatchEntry(malformedRulesPayload)
        )

        XCTAssertEqual(malformedRulesEntry.rules.condition, .noPreference)
        XCTAssertEqual(malformedRulesEntry.rules.value, .japanese)
        XCTAssertEqual(malformedRulesEntry.handicap.condition, .required)
        XCTAssertEqual(malformedRulesEntry.handicap.value, .disabled)

        let malformedHandicapPayload: [String: Any] = [
            "uuid": "malformed-handicap-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "rules": ["condition": "required", "value": "aga"],
            "handicap": ["condition": 42, "value": ["future": true]],
        ]
        let malformedHandicapEntry = try XCTUnwrap(
            OGSAutomatchEntry(malformedHandicapPayload)
        )

        XCTAssertEqual(malformedHandicapEntry.rules.condition, .required)
        XCTAssertEqual(malformedHandicapEntry.rules.value, .aga)
        XCTAssertEqual(malformedHandicapEntry.handicap.condition, .noPreference)
        XCTAssertEqual(malformedHandicapEntry.handicap.value, .enabled)
    }

    func testInboundEntryIgnoresInvalidLegacyTimeControlMetadata() throws {
        let payload: [String: Any] = [
            "uuid": "invalid-legacy-time-control-id",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid"],
                ["size": "13x13", "speed": "correspondence"],
            ],
            "time_control": [
                "condition": "no-preference",
                "value": ["system": "canadian"],
            ],
        ]

        let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

        XCTAssertEqual(entry.uuid, "invalid-legacy-time-control-id")
        XCTAssertEqual(entry.sizeSpeedOptions.map(\.system), [.byoyomi, .fischer])
    }

    func testCurrentUICompatibilityAdapterPreservesLegacyPreferences() {
        let liveEntry = OGSAutomatchEntry(
            sizeOptions: [9, 19],
            timeControlSpeed: .live,
            optionsShuffler: { _ in }
        )
        XCTAssertEqual(
            liveEntry.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .live,
                    system: .fischer
                ),
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .live,
                    system: .byoyomi
                ),
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .live,
                    system: .fischer
                ),
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .live,
                    system: .byoyomi
                ),
            ]
        )
        XCTAssertEqual(liveEntry.rules.condition, .noPreference)
        XCTAssertEqual(liveEntry.handicap.condition, .noPreference)
        XCTAssertEqual(liveEntry.handicap.value, .enabled)
        XCTAssertNil(liveEntry.jsonObject["time_control"])

        var invoked = false
        _ = OGSAutomatchEntry(
            sizeOptions: [9, 19],
            timeControlSpeed: .live,
            optionsShuffler: {
                invoked = true
                $0.reverse()
            }
        )
        XCTAssertTrue(invoked)

        let blitzEntry = OGSAutomatchEntry(
            sizeOptions: [9],
            timeControlSpeed: .blitz
        )
        XCTAssertEqual(blitzEntry.handicap.condition, .noPreference)
        XCTAssertEqual(blitzEntry.handicap.value, .disabled)

        let correspondenceEntry = OGSAutomatchEntry(
            sizeOptions: [13],
            timeControlSpeed: .correspondence
        )
        XCTAssertEqual(correspondenceEntry.sizeSpeedOptions.count, 1)
        XCTAssertEqual(correspondenceEntry.sizeSpeedOptions.first?.system, .fischer)
    }

    func testModernEntryEncodingRemainsReadableByTheLegacyDecoder() throws {
        let entry = OGSAutomatchEntry(
            sizeOptions: [9, 19],
            timeControlSpeed: .live
        )

        let data = try JSONEncoder().encode(entry)
        let legacyEntry = try JSONDecoder().decode(
            LegacyStoredAutomatchEntry.self,
            from: data
        )

        XCTAssertEqual(legacyEntry.sizeOptions, [9, 19])
        XCTAssertEqual(legacyEntry.timeControlSpeed, .live)
        XCTAssertEqual(legacyEntry.uuid, entry.uuid)
    }

    func testEntryPersistenceRoundTripPreservesModernContract() throws {
        let entry = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 19,
            speed: .rapid,
            system: .byoyomi,
            handicap: .required,
            lowerRankDifference: 0,
            upperRankDifference: 9
        ).makeAutomatchEntry(uuid: "round-trip-id")

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(OGSAutomatchEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    func testActivePresentationKeepsExactServerCriteriaWithoutBroadening() throws {
        let entry = OGSQuickMatchDraft(
            mode: .exact,
            boardSize: 13,
            speed: .rapid,
            system: .fischer,
            handicap: .required,
            lowerRankDifference: 2,
            upperRankDifference: 4
        ).makeAutomatchEntry(uuid: "restored-exact")

        let presentation = try XCTUnwrap(
            OGSActiveQuickMatchPresentation(entry: entry)
        )

        XCTAssertEqual(presentation.draft.mode, .exact)
        XCTAssertEqual(presentation.draft.boardSize, 13)
        XCTAssertEqual(presentation.draft.speed, .rapid)
        XCTAssertEqual(presentation.draft.system, .fischer)
        XCTAssertEqual(presentation.draft.handicap, .required)
        XCTAssertEqual(presentation.draft.lowerRankDifference, 2)
        XCTAssertEqual(presentation.draft.upperRankDifference, 4)
    }

    func testActivePresentationReconstructsFlexibleAndMultipleEntries() throws {
        let flexibleEntry = OGSQuickMatchDraft(
            mode: .flexible,
            boardSize: 19,
            speed: .live,
            system: .byoyomi
        ).makeAutomatchEntry(uuid: "restored-flexible")
        let flexible = try XCTUnwrap(
            OGSActiveQuickMatchPresentation(entry: flexibleEntry)
        )
        XCTAssertEqual(flexible.draft.mode, .flexible)
        XCTAssertEqual(flexible.draft.boardSize, 19)
        XCTAssertEqual(flexible.draft.speed, .live)
        XCTAssertEqual(flexible.draft.system, .byoyomi)

        let multipleEntry = OGSQuickMatchDraft(
            mode: .multiple,
            multipleBoardSizes: [9, 19],
            multipleClocks: [
                OGSQuickMatchClockSelection(
                    speed: .blitz,
                    system: .fischer
                ),
                OGSQuickMatchClockSelection(
                    speed: .rapid,
                    system: .byoyomi
                ),
            ]
        ).makeAutomatchEntry(
            uuid: "restored-multiple",
            multipleOptionsShuffler: { _ in }
        )
        let multiple = try XCTUnwrap(
            OGSActiveQuickMatchPresentation(entry: multipleEntry)
        )
        XCTAssertEqual(multiple.draft.mode, .multiple)
        XCTAssertEqual(multiple.draft.multipleBoardSizes, [9, 19])
        XCTAssertEqual(
            multiple.draft.multipleClocks,
            Set([
                OGSQuickMatchClockSelection(
                    speed: .blitz,
                    system: .fischer
                ),
                OGSQuickMatchClockSelection(
                    speed: .rapid,
                    system: .byoyomi
                ),
            ])
        )
    }

    func testActivePresentationRejectsUnrepresentableSettings() {
        let degraded = OGSAutomatchEntry(
            sizeSpeedOptions: [],
            uuid: "degraded-entry"
        )

        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: degraded))
    }

    func testActivePresentationRejectsNonCartesianMultipleCriteria() {
        let entry = OGSAutomatchEntry(
            sizeSpeedOptions: [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .blitz,
                    system: .fischer
                ),
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .rapid,
                    system: .byoyomi
                ),
            ],
            uuid: "non-cartesian-entry"
        )

        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: entry))
    }

    func testActivePresentationRejectsCriteriaTheEditorCannotRepresent() {
        let legacyHandicap = OGSAutomatchEntry(
            sizeSpeedOptions: [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .rapid,
                    system: .fischer
                ),
            ],
            handicap: OGSAutomatchHandicapPreference(
                condition: .noPreference,
                value: .enabled
            ),
            uuid: "legacy-handicap-entry"
        )
        let broadRankRange = OGSAutomatchEntry(
            sizeSpeedOptions: legacyHandicap.sizeSpeedOptions,
            lowerRankDifference: 10,
            handicap: .quickMatchDefault,
            uuid: "broad-rank-entry"
        )
        let legacyRules = OGSAutomatchEntry(
            sizeSpeedOptions: legacyHandicap.sizeSpeedOptions,
            rules: OGSAutomatchRulesPreference(
                condition: .noPreference,
                value: .japanese
            ),
            uuid: "legacy-rules-entry"
        )

        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: legacyHandicap))
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: broadRankRange))
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: legacyRules))
    }

    func testActivePresentationRejectsPartiallyDegradedInboundOptions() throws {
        let entry = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "partially-degraded-entry",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
                ["size": "9x9", "speed": "rapid", "system": "future-clock"],
            ],
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))

        XCTAssertEqual(entry.sizeSpeedOptions.count, 1)
        XCTAssertEqual(entry.rules, .quickMatchDefault)
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: entry))
    }

    func testActivePresentationRejectsDegradedInboundHandicap() throws {
        let entry = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "degraded-handicap-entry",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "handicap": ["condition": "required", "value": "automatic"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))

        XCTAssertEqual(entry.rules, .quickMatchDefault)
        XCTAssertEqual(
            entry.handicap,
            OGSAutomatchHandicapPreference(
                condition: .required,
                value: .enabled
            )
        )
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: entry))
    }

    func testActivePresentationRejectsDegradedInboundRankLimit() throws {
        let entry = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "degraded-rank-entry",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "lower_rank_diff": "future-rank-limit",
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))

        XCTAssertEqual(entry.lowerRankDifference, 3)
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: entry))
    }

    func testWaitingGamesSummaryEligibilityRejectsEveryDegradedInboundSetting() throws {
        let payloads: [[String: Any]] = [
            [
                "uuid": "waiting-future-clock",
                "size_speed_options": [
                    ["size": "9x9", "speed": "rapid", "system": "fischer"],
                    ["size": "9x9", "speed": "rapid", "system": "future-clock"],
                ],
                "lower_rank_diff": 3,
                "upper_rank_diff": 3,
                "handicap": ["condition": "preferred", "value": "enabled"],
                "rules": ["condition": "required", "value": "japanese"],
            ],
            [
                "uuid": "waiting-malformed-rank",
                "size_speed_options": [
                    ["size": "13x13", "speed": "rapid", "system": "byoyomi"],
                ],
                "lower_rank_diff": "future-rank-limit",
                "upper_rank_diff": 3,
                "handicap": ["condition": "preferred", "value": "enabled"],
                "rules": ["condition": "required", "value": "japanese"],
            ],
            [
                "uuid": "waiting-unknown-handicap",
                "size_speed_options": [
                    ["size": "19x19", "speed": "correspondence", "system": "fischer"],
                ],
                "lower_rank_diff": 3,
                "upper_rank_diff": 3,
                "handicap": ["condition": "required", "value": "automatic"],
                "rules": ["condition": "required", "value": "japanese"],
            ],
        ]

        for payload in payloads {
            let entry = try XCTUnwrap(OGSAutomatchEntry(payload))

            XCTAssertFalse(
                entry.quickMatchDisplayIsComplete,
                "Waiting Games must not summarize degraded entry \(entry.uuid)."
            )
        }
    }

    func testWaitingGamesSummaryEligibilityKeepsFullyDecodedRequestDisplayable() throws {
        let entry = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "waiting-valid-request",
            "size_speed_options": [
                ["size": "19x19", "speed": "correspondence", "system": "fischer"],
            ],
            "lower_rank_diff": 3,
            "upper_rank_diff": 3,
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))

        XCTAssertTrue(entry.quickMatchDisplayIsComplete)
    }

    func testWaitingGamesPresentationPreservesArbitrarySizeClockPairings() throws {
        let presentation = try XCTUnwrap(
            AutomatchEntryPresentation(
                entry: OGSAutomatchEntry.sampleEntry,
                userRank: nil,
                locale: Locale(identifier: "en_US")
            )
        )

        XCTAssertEqual(presentation.boardAndSpeed, "9×9 and 13×13 · Live")
        XCTAssertEqual(
            presentation.clockLines,
            [
                "9×9 · Fischer: 3m + 10s",
                "13×13 · Byo-Yomi: 10m + 5×30s",
            ]
        )
        XCTAssertEqual(
            presentation.handicap,
            "Standard: Use handicaps by default, but accept games with handicaps off."
        )
        XCTAssertNil(
            presentation.rules,
            "The standard required Japanese rules should keep the compact four-row card."
        )
    }

    func testWaitingGamesPresentationSupportsLegacyAndNonEditorPreferences() throws {
        let option = OGSAutomatchSizeSpeedOption(
            size: 9,
            speed: .rapid,
            system: .fischer
        )
        let locale = Locale(identifier: "en_US")

        let rulesCases: [
            (OGSAutomatchRulesPreference, String?)
        ] = [
            (.quickMatchDefault, nil),
            (
                OGSAutomatchRulesPreference(
                    condition: .required,
                    value: .chinese
                ),
                "Rules: Chinese"
            ),
            (
                OGSAutomatchRulesPreference(
                    condition: .preferred,
                    value: .aga
                ),
                "Preferred rules: AGA"
            ),
            (
                OGSAutomatchRulesPreference(
                    condition: .required,
                    value: .korean
                ),
                "Rules: Korean"
            ),
            (
                OGSAutomatchRulesPreference(
                    condition: .required,
                    value: .newZealand
                ),
                "Rules: New Zealand"
            ),
            (
                OGSAutomatchRulesPreference(
                    condition: .required,
                    value: .ing
                ),
                "Rules: Ing SST"
            ),
            (
                OGSAutomatchRulesPreference(
                    condition: .noPreference,
                    value: .japanese
                ),
                "No rules preference"
            ),
        ]
        for (rules, expected) in rulesCases {
            let entry = OGSAutomatchEntry(
                sizeSpeedOptions: [option],
                rules: rules,
                uuid: "waiting-rules"
            )
            let presentation = try XCTUnwrap(
                AutomatchEntryPresentation(
                    entry: entry,
                    userRank: nil,
                    locale: locale
                )
            )
            XCTAssertEqual(presentation.rules, expected)
        }

        let handicapCases: [
            (OGSAutomatchHandicapPreference, String)
        ] = [
            (
                OGSAutomatchHandicapPreference(
                    condition: .required,
                    value: .enabled
                ),
                "Required: Require handicaps between players of different ranks."
            ),
            (
                .quickMatchDefault,
                "Standard: Use handicaps by default, but accept games with handicaps off."
            ),
            (
                OGSAutomatchHandicapPreference(
                    condition: .required,
                    value: .disabled
                ),
                "Disabled: Never play with handicap stones."
            ),
            (
                OGSAutomatchHandicapPreference(
                    condition: .preferred,
                    value: .disabled
                ),
                "No handicap preferred: Accept games with or without handicap stones."
            ),
            (
                OGSAutomatchHandicapPreference(
                    condition: .noPreference,
                    value: .enabled
                ),
                "No preference: Accept any handicap setting."
            ),
            (
                OGSAutomatchHandicapPreference(
                    condition: .noPreference,
                    value: .disabled
                ),
                "No preference: Accept any handicap setting."
            ),
        ]
        for (handicap, expected) in handicapCases {
            let entry = OGSAutomatchEntry(
                sizeSpeedOptions: [option],
                handicap: handicap,
                uuid: "waiting-handicap"
            )
            let presentation = try XCTUnwrap(
                AutomatchEntryPresentation(
                    entry: entry,
                    userRank: nil,
                    locale: locale
                )
            )
            XCTAssertEqual(presentation.handicap, expected)
        }

        let expandedServerRankRange = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "waiting-expanded-rank-range",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "lower_rank_diff": 12,
            "upper_rank_diff": 15,
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))
        let broadRankPresentation = try XCTUnwrap(
            AutomatchEntryPresentation(
                entry: expandedServerRankRange,
                userRank: nil,
                locale: locale
            )
        )
        XCTAssertEqual(
            broadRankPresentation.rankRange,
            "12 ranks below to 15 ranks above"
        )
        XCTAssertEqual(
            AutomatchEntryPresentation(
                entry: expandedServerRankRange,
                userRank: 28,
                locale: locale
            )?.rankRange,
            "14 Kyu - 9 Dan",
            "A future OGS range wider than the current editor must still be displayed."
        )

        let veryLargeButSafeRankRange = OGSAutomatchEntry(
            sizeSpeedOptions: [option],
            lowerRankDifference: Int.max / 2,
            upperRankDifference: Int.max / 2,
            uuid: "waiting-safe-large-rank-range"
        )
        XCTAssertNotNil(
            AutomatchEntryPresentation(
                entry: veryLargeButSafeRankRange,
                userRank: 1_037,
                locale: locale
            ),
            "The display guard must leave ample room for future OGS ranges."
        )
    }

    func testWaitingGamesPresentationRejectsOnlyDegradedOrInvalidEntries() throws {
        let degraded = try XCTUnwrap(
            OGSAutomatchEntry([
                "uuid": "waiting-degraded",
                "size_speed_options": [
                    ["size": "9x9", "speed": "rapid", "system": "future-clock"],
                ],
                "rules": ["condition": "required", "value": "japanese"],
                "handicap": ["condition": "preferred", "value": "enabled"],
            ])
        )
        let empty = OGSAutomatchEntry(
            sizeSpeedOptions: [],
            uuid: "waiting-empty"
        )
        let unsupportedBoard = OGSAutomatchEntry(
            sizeSpeedOptions: [
                OGSAutomatchSizeSpeedOption(
                    size: 7,
                    speed: .rapid,
                    system: .fischer
                ),
            ],
            uuid: "waiting-unsupported-board"
        )
        let negativeRankDifference = OGSAutomatchEntry(
            sizeSpeedOptions: [
                OGSAutomatchSizeSpeedOption(
                    size: 9,
                    speed: .rapid,
                    system: .fischer
                ),
            ],
            lowerRankDifference: -1,
            uuid: "waiting-negative-rank"
        )
        let unsafeLowerRankDifference = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "waiting-unsafe-lower-rank",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "lower_rank_diff": Int.max / 2 + 1,
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))
        let unsafeUpperRankDifference = try XCTUnwrap(OGSAutomatchEntry([
            "uuid": "waiting-unsafe-upper-rank",
            "size_speed_options": [
                ["size": "9x9", "speed": "rapid", "system": "fischer"],
            ],
            "upper_rank_diff": Int.max,
            "handicap": ["condition": "preferred", "value": "enabled"],
            "rules": ["condition": "required", "value": "japanese"],
        ]))
        XCTAssertTrue(unsafeLowerRankDifference.quickMatchDisplayIsComplete)
        XCTAssertTrue(unsafeUpperRankDifference.quickMatchDisplayIsComplete)

        for entry in [
            degraded,
            empty,
            unsupportedBoard,
            negativeRankDifference,
            unsafeLowerRankDifference,
            unsafeUpperRankDifference,
        ] {
            XCTAssertNil(
                AutomatchEntryPresentation(
                    entry: entry,
                    // A legacy encoded professional rank exercises the
                    // Double-to-Int conversion path that made Int.max unsafe.
                    userRank: 1_037,
                    locale: Locale(identifier: "en_US")
                ),
                "Entry \(entry.uuid) should retain the unavailable-settings fallback."
            )
        }
    }

    func testQuickMatchCorrespondenceOnlyClassificationUsesSelectedClocks() {
        let exact = OGSQuickMatchDraft(
            mode: .exact,
            speed: .correspondence
        )
        let flexible = OGSQuickMatchDraft(
            mode: .flexible,
            speed: .correspondence
        )
        let rapid = OGSQuickMatchDraft(
            mode: .exact,
            speed: .rapid
        )
        let multiple = OGSQuickMatchDraft(
            mode: .multiple,
            multipleBoardSizes: [9],
            multipleClocks: [
                OGSQuickMatchClockSelection(
                    speed: .rapid,
                    system: .fischer
                ),
            ]
        )

        XCTAssertTrue(exact.quickMatchIsCorrespondenceOnly)
        XCTAssertTrue(flexible.quickMatchIsCorrespondenceOnly)
        XCTAssertFalse(rapid.quickMatchIsCorrespondenceOnly)
        XCTAssertFalse(multiple.quickMatchIsCorrespondenceOnly)
    }

    func testSharedActivePresentationOnlyAcceptsRepresentableSettings() {
        let options = [
            OGSAutomatchSizeSpeedOption(
                size: 19,
                speed: .correspondence,
                system: .fischer
            ),
        ]
        let japaneseEntry = OGSAutomatchEntry(
            sizeSpeedOptions: options,
            rules: .quickMatchDefault,
            uuid: "waiting-japanese"
        )
        let agaEntry = OGSAutomatchEntry(
            sizeSpeedOptions: options,
            rules: OGSAutomatchRulesPreference(
                condition: .required,
                value: .aga
            ),
            uuid: "waiting-aga"
        )
        let unsupportedHandicapEntry = OGSAutomatchEntry(
            sizeSpeedOptions: options,
            handicap: OGSAutomatchHandicapPreference(
                condition: .preferred,
                value: .disabled
            ),
            uuid: "waiting-unsupported-handicap"
        )

        XCTAssertNotNil(OGSActiveQuickMatchPresentation(entry: japaneseEntry))
        XCTAssertNil(OGSActiveQuickMatchPresentation(entry: agaEntry))
        XCTAssertNil(
            OGSActiveQuickMatchPresentation(entry: unsupportedHandicapEntry)
        )
    }

    func testLateCancellationTerminalClearsOnlyItsFailure() {
        let entry = OGSQuickMatchDraft.ogsDefault.makeAutomatchEntry(
            uuid: "cancelled-entry"
        )
        let timeout = QuickMatchRequestFailure(
            operation: .cancelTimedOut,
            entry: entry
        )
        let start = QuickMatchRequestFailure(operation: .start, entry: entry)

        XCTAssertNil(
            timeout.retainedAfterCancellationTerminal(uuid: entry.uuid)
        )
        XCTAssertNil(timeout.retainedAfterCancellationTerminal(uuid: nil))
        XCTAssertEqual(
            timeout.retainedAfterCancellationTerminal(uuid: "another-entry"),
            timeout
        )
        XCTAssertEqual(
            start.retainedAfterCancellationTerminal(uuid: entry.uuid),
            start
        )
        XCTAssertFalse(timeout.canRetryCancellation(activeEntryIDs: []))
        XCTAssertTrue(
            timeout.canRetryCancellation(activeEntryIDs: [entry.uuid])
        )
    }

    func testLegacyStoredEntryMigratesAndKeepsLegacyKey() throws {
        let suiteName = "com.honganhkhoa.Surround.QuickMatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyData = Data(
            #"{"sizeOptions":[9,19],"timeControlSpeed":"live","uuid":"legacy-id"}"#.utf8
        )
        defaults.set(legacyData, forKey: SettingKey<OGSAutomatchEntry>.lastAutomatchEntry.name)

        let draft = defaults.loadQuickMatchDraft()

        XCTAssertEqual(draft.mode, .multiple)
        XCTAssertEqual(draft.boardSize, 19)
        XCTAssertEqual(draft.speed, .live)
        XCTAssertEqual(draft.system, .byoyomi)
        XCTAssertEqual(draft.multipleBoardSizes, [9, 19])
        XCTAssertEqual(
            draft.multipleClocks,
            [
                OGSQuickMatchClockSelection(speed: .live, system: .fischer),
                OGSQuickMatchClockSelection(speed: .live, system: .byoyomi),
            ]
        )
        XCTAssertEqual(draft.handicap, .standard)
        XCTAssertEqual(draft.lowerRankDifference, 3)
        XCTAssertEqual(draft.upperRankDifference, 3)
        XCTAssertEqual(defaults.data(forKey: SettingKey<OGSAutomatchEntry>.lastAutomatchEntry.name), legacyData)
        XCTAssertNotNil(
            defaults[SettingKey<OGSQuickMatchDraft>.lastQuickMatchDraft]
        )
        XCTAssertEqual(defaults.loadQuickMatchDraft(), draft)
    }

    func testUnknownDraftSchemaIsPreservedWithoutLegacyOverwrite() throws {
        let suiteName = "com.honganhkhoa.Surround.QuickMatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let futureDraft = OGSQuickMatchDraft(
            schemaVersion: OGSQuickMatchDraft.currentSchemaVersion + 1,
            mode: .exact,
            boardSize: 19
        )
        let futureData = try JSONEncoder().encode(futureDraft)
        let draftKey = SettingKey<OGSQuickMatchDraft>.lastQuickMatchDraft
        defaults.set(futureData, forKey: draftKey.name)
        defaults.set(
            Data(
                #"{"sizeOptions":[9],"timeControlSpeed":"blitz","uuid":"legacy-id"}"#.utf8
            ),
            forKey: SettingKey<OGSAutomatchEntry>.lastAutomatchEntry.name
        )

        let loaded = defaults.loadQuickMatchDraft()

        XCTAssertEqual(loaded, .ogsDefault)
        XCTAssertEqual(defaults.data(forKey: draftKey.name), futureData)
    }

    func testLegacyMultiSizeCorrespondenceMigratesToFlexibleLargestSize() throws {
        let legacyData = Data(
            #"{"sizeOptions":[9,13,19],"timeControlSpeed":"correspondence","uuid":"legacy-correspondence"}"#.utf8
        )
        let legacyEntry = try JSONDecoder().decode(
            OGSAutomatchEntry.self,
            from: legacyData
        )

        let draft = OGSQuickMatchDraft(migrating: legacyEntry)
        let payload = draft.makeAutomatchEntry(uuid: "migrated-id")

        XCTAssertEqual(draft.mode, .flexible)
        XCTAssertEqual(draft.boardSize, 19)
        XCTAssertEqual(draft.multipleBoardSizes, [9, 13, 19])
        XCTAssertEqual(draft.speed, .correspondence)
        XCTAssertEqual(draft.system, .fischer)
        XCTAssertEqual(
            payload.sizeSpeedOptions,
            [
                OGSAutomatchSizeSpeedOption(
                    size: 19,
                    speed: .correspondence,
                    system: .fischer
                ),
            ]
        )
    }

    func testLegacyBlitzMigrationKeepsDisabledHandicap() throws {
        let legacyData = Data(
            #"{"sizeOptions":[9],"timeControlSpeed":"blitz","uuid":"legacy-blitz"}"#.utf8
        )
        let legacyEntry = try JSONDecoder().decode(
            OGSAutomatchEntry.self,
            from: legacyData
        )

        let draft = OGSQuickMatchDraft(migrating: legacyEntry)

        XCTAssertEqual(draft.mode, .flexible)
        XCTAssertEqual(draft.handicap, .disabled)
    }
}
