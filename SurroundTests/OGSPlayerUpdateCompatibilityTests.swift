import DictionaryCoding
import XCTest

final class OGSPlayerUpdateCompatibilityTests: XCTestCase {
    func testPlayerOnlyUpdatesAcceptMissingOrEmptyMembershipWithBothDecoders() throws {
        for suppliesEmptyTeams in [false, true] {
            var payload = playerUpdatePayload()
            if suppliesEmptyTeams { payload["rengo_teams"] = [String: Any]() }
            for (decoder, update) in try decodeBoth(payload, as: OGSPlayerUpdate.self) {
                XCTAssertEqual(update.players?.black, 1, decoder)
                XCTAssertEqual(update.players?.white, 2, decoder)
                XCTAssertNil(update.rengoTeams, decoder)
            }
        }
    }

    func testMoveExtrasRetainPlayedByAndPlayerIDsWithBothDecoders() throws {
        for suppliesEmptyTeams in [false, true] {
            var update = playerUpdatePayload()
            if suppliesEmptyTeams { update["rengo_teams"] = [String: Any]() }
            let payload: [String: Any] = ["played_by": 1, "player_update": update]
            for (decoder, extra) in try decodeBoth(payload, as: OGSMoveExtra.self) {
                XCTAssertEqual(extra.playedBy, 1, decoder)
                XCTAssertEqual(extra.playerUpdate?.players?.black, 1, decoder)
                XCTAssertEqual(extra.playerUpdate?.players?.white, 2, decoder)
                XCTAssertNil(extra.playerUpdate?.rengoTeams, decoder)
            }
        }
    }

    func testSuppliedTeamArraysRemainDistinctFromNoMembershipWithBothDecoders() throws {
        for teams in [["black": [1, 3], "white": [2, 4]], ["black": [], "white": []]] {
            var payload = playerUpdatePayload()
            payload["rengo_teams"] = teams
            for (decoder, update) in try decodeBoth(payload, as: OGSPlayerUpdate.self) {
                XCTAssertEqual(update.rengoTeams?.black, teams["black"], decoder)
                XCTAssertEqual(update.rengoTeams?.white, teams["white"], decoder)
                XCTAssertNotNil(update.rengoTeams, decoder)
            }
        }
    }

    func testNullMalformedAndPartialMembershipIsRejectedByBothDecoders() throws {
        let malformedTeams: [Any] = [
            NSNull(), true, 1, "teams", [] as [Any],
            ["black": [1]], ["white": [2]], ["unexpected": [] as [Int]],
            ["black": NSNull(), "white": [2]],
            ["black": 1, "white": [2]],
            ["black": ["1"], "white": [2]],
            ["black": [true], "white": [2]],
            ["black": [1.5], "white": [2]],
            ["black": [1, NSNull()] as [Any], "white": [2]],
        ]
        for teams in malformedTeams {
            var payload = playerUpdatePayload()
            payload["rengo_teams"] = teams
            try assertBothDecodersReject(payload, as: OGSPlayerUpdate.self)
        }
    }

    func testGenuineRengoRejectsMissingOrEmptyMoveMembershipWithBothDecoders() throws {
        for suppliesEmptyTeams in [false, true] {
            var update = playerUpdatePayload()
            if suppliesEmptyTeams { update["rengo_teams"] = [String: Any]() }
            var payload = gamePayload()
            payload["rengo"] = true
            payload["rengo_teams"] = fullGameTeams()
            payload["moves"] = [[0, 0, 1, false, ["player_update": update]] as [Any]]
            try assertBothDecodersReject(payload, as: OGSGame.self)
        }
    }

    func testGenuineRengoAcceptsCompleteMoveMembershipWithBothDecoders() throws {
        var update = playerUpdatePayload()
        update["rengo_teams"] = ["black": [1], "white": [2]]
        var payload = gamePayload()
        payload["rengo"] = true
        payload["rengo_teams"] = fullGameTeams()
        payload["moves"] = [[0, 0, 1, false, ["played_by": 1, "player_update": update]] as [Any]]
        for (decoder, game) in try decodeBoth(payload, as: OGSGame.self) {
            XCTAssertEqual(game.rengo, true, decoder)
            XCTAssertEqual(game.moves[0].extra?.playerUpdate?.rengoTeams?.black, [1], decoder)
            XCTAssertEqual(game.moves[0].extra?.playerUpdate?.rengoTeams?.white, [2], decoder)
        }
    }

    func testOrdinaryPublicGameRetainsAllMovesAndPlayerOnlyUpdateWithBothDecoders() throws {
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.ordinaryPlayerUpdateGameJSON.utf8)) as? [String: Any]
        )
        for suppliesEmptyTeams in [true, false] {
            var variant = payload
            if !suppliesEmptyTeams {
                var moves = try XCTUnwrap(variant["moves"] as? [[Any]])
                var extra = try XCTUnwrap(moves[14][4] as? [String: Any])
                var update = try XCTUnwrap(extra["player_update"] as? [String: Any])
                update.removeValue(forKey: "rengo_teams")
                extra["player_update"] = update
                moves[14][4] = extra
                variant["moves"] = moves
            }
            for (decoder, game) in try decodeBoth(variant, as: OGSGame.self) {
                XCTAssertEqual(game.gameId, 37718759, decoder)
                XCTAssertNil(game.rengo, decoder)
                XCTAssertEqual(game.phase, .finished, decoder)
                XCTAssertEqual(game.moves.count, 184, decoder)
                XCTAssertEqual(game.outcome, "87.5 points", decoder)
                XCTAssertTrue(game.scoreHandicap, decoder)
                XCTAssertEqual(game.moves[14].extra?.playedBy, 1, decoder)
                XCTAssertEqual(game.moves[14].extra?.playerUpdate?.players?.black, 1, decoder)
                XCTAssertEqual(game.moves[14].extra?.playerUpdate?.players?.white, 449941, decoder)
                XCTAssertNil(game.moves[14].extra?.playerUpdate?.rengoTeams, decoder)
            }
        }
    }

    private func playerUpdatePayload() -> [String: Any] {
        ["players": ["black": 1, "white": 2]]
    }

    private func fullGameTeams() -> [String: Any] {
        [
            "black": [["id": 1, "username": "Black"]],
            "white": [["id": 2, "username": "White"]],
        ]
    }

    private func gamePayload() -> [String: Any] {
        [
            "game_id": 1001, "black_player_id": 1, "white_player_id": 2,
            "width": 19, "height": 19, "game_name": "Player update fixture",
            "handicap": 0, "ranked": false, "rules": "japanese", "phase": "finished",
            "initial_player": "black", "initial_state": ["black": "", "white": ""],
            "komi": 6.5, "moves": [] as [Any],
            "players": [
                "black": ["id": 1, "username": "Black"],
                "white": ["id": 2, "username": "White"],
            ],
            "time_control": ["time_control": "none"],
            "clock": [
                "black_player_id": 1, "white_player_id": 2, "current_player": 1,
                "last_move": 0, "black_time": 0, "white_time": 0,
            ],
        ]
    }

    private func decodeBoth<T: Decodable>(_ payload: [String: Any], as type: T.Type) throws -> [(String, T)] {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return [
            ("JSONDecoder", try jsonDecoder.decode(type, from: JSONSerialization.data(withJSONObject: payload))),
            ("DictionaryDecoder", try dictionaryDecoder.decode(type, from: payload)),
        ]
    }

    private func assertBothDecodersReject<T: Decodable>(
        _ payload: [String: Any], as type: T.Type, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try jsonDecoder.decode(type, from: data), "JSONDecoder", file: file, line: line)
        XCTAssertThrowsError(try dictionaryDecoder.decode(type, from: payload), "DictionaryDecoder", file: file, line: line)
    }
}

private extension OGSPlayerUpdateCompatibilityTests {
    // Public OGS game 37718759. Player labels and the title are anonymized;
    // all 184 move records and the empty team object retain their wire types.
    static let ordinaryPlayerUpdateGameJSON = #"""
    {
        "aga_handicap_scoring": false,
        "allow_ko": false,
        "allow_self_capture": false,
        "allow_superko": false,
        "auto_scoring_done": true,
        "automatic_stone_removal": false,
        "black_player_id": 1,
        "clock": {
            "black_player_id": 1,
            "black_time": {
                "skip_bonus": false,
                "thinking_time": 2419200
            },
            "current_player": 1,
            "expiration": 1664220816257,
            "expiration_delta": 2419200000,
            "game_id": 37718759,
            "last_move": 1661801616257,
            "now": 1649462342118,
            "pause_delta": 0,
            "paused_since": 1661801616257,
            "stone_removal_expiration": 1661888024841,
            "stone_removal_mode": true,
            "title": "Ordinary player update compatibility fixture",
            "white_player_id": 449941,
            "white_time": {
                "skip_bonus": false,
                "thinking_time": 2419200
            }
        },
        "disable_analysis": false,
        "free_handicap_placement": true,
        "game_id": 37718759,
        "game_name": "Ordinary player update compatibility fixture",
        "handicap": 0,
        "height": 19,
        "initial_player": "black",
        "initial_state": {
            "black": "",
            "white": ""
        },
        "komi": 7.5,
        "moves": [
            [15, 3, 202826781, null, null],
            [3, 15, 476064723, null, null],
            [15, 15, 20288072, null, null],
            [3, 2, 65138555, null, null],
            [2, 3, 104895445, null, null],
            [5, 3, 45434540],
            [4, 4, 58298149, null, null],
            [2, 9, 2434727668, null, null],
            [15, 9, 154241508, null, null],
            [13, 2, 188586095, null, null],
            [14, 1, 1448576093, null, null],
            [13, 1, 576773125, null, null],
            [14, 2, 982160846, null, null],
            [13, 4, 258185816],
            [9, 15, 610141136, null, {"played_by": 1, "player_update": {"players": {"black": 1, "white": 449941}, "rengo_teams": {}}}],
            [5, 16, 408346485],
            [7, 16, 32866081],
            [2, 6, 1255059496],
            [2, 2, 107807577],
            [2, 1, 10361309],
            [1, 1, 1110885460],
            [3, 0, 287011690],
            [2, 5, 138943542],
            [3, 6, 419439665],
            [15, 5, 272607140],
            [16, 7, 117758151],
            [16, 8, 62708374],
            [14, 7, 441667885],
            [15, 12, 1368270496],
            [13, 16, 407495212],
            [14, 17, 1240720389],
            [13, 17, 52421908],
            [14, 16, 26174534],
            [10, 17, 1171927],
            [2, 13, 394419646],
            [2, 14, 12993399],
            [2, 11, 112819863],
            [1, 10, 56322018],
            [1, 11, 119567275],
            [1, 13, 585904955],
            [5, 17, 533647195],
            [4, 17, 403397188],
            [6, 17, 27283453],
            [8, 17, 750880422],
            [4, 6, 200912595.49999988],
            [4, 7, 230984011],
            [5, 6, 203569803.00000012],
            [5, 7, 398592848.5, null, null],
            [6, 7, 28967520.49999988],
            [6, 8, 59397105.5, null, null],
            [7, 7, 133282432],
            [7, 8, 7798728, null, null],
            [8, 8, 411342131.5, null, null],
            [8, 9, 142787123.50000006, null, null],
            [9, 8, 622121405, null, null],
            [9, 9, 67519957, null, null],
            [11, 8, 1322598622, null, null],
            [13, 6, 14324023, null, null],
            [11, 6, 9443629, null, null],
            [12, 5, 97661783.00000012, null, null],
            [11, 5, 134253677.5, null, null],
            [11, 4, 146089.5, null, null],
            [10, 4, 97952998.5, null, null],
            [10, 3, 51672514.5, null, null],
            [9, 4, 21554757.49999988, null, null],
            [9, 3, 58783940.5, null, null],
            [8, 3, 35894918.5, null, null],
            [8, 2, 19843338.5, null, null],
            [7, 3, 432015958.4999999, null, null],
            [7, 2, 31678004, null, null],
            [6, 3, 27662656, null, null],
            [6, 2, 66015978, null, null],
            [10, 9, 70133947, null, null],
            [6, 14, 10380856.5, null, null],
            [7, 14, 25601889, null, null],
            [6, 13, 384779, null, null],
            [7, 13, 1900479, null, null],
            [7, 12, 1433242, null, null],
            [8, 12, 5968652, null, null],
            [8, 11, 3654451, null, null],
            [7, 11, 263563216, null, null],
            [6, 12, 15944716, null, null],
            [9, 11, 3, null, null],
            [8, 10, 3815, null, null],
            [9, 13, 4, null, null],
            [17, 7, 17495, null, null],
            [17, 8, 159561515.5, null, null],
            [18, 4, 44773127.5, null, null],
            [17, 4, 471501498.49999976, null, null],
            [17, 5, 46551641.5, null, null],
            [18, 3, 25968386, null, null],
            [18, 5, 22037998, null, null],
            [17, 3, 61111504.50000048],
            [16, 5, 1200307.5, null, null],
            [16, 4, 85489994.5, null, null],
            [1, 5, 14613077.5, null, null],
            [1, 4, 1944533.5, null, null],
            [3, 5, 15567688, null, null],
            [3, 4, 1113238520, null, null],
            [13, 14, 55042403.5],
            [14, 14, 318981542.99999976, null, null],
            [13, 13, 11297767, null, null],
            [14, 13, 20900666.000000477, null, null],
            [10, 16, 61774004.5, null, null],
            [10, 15, 24686789.5, null, null],
            [11, 15, 17699457, null, null],
            [5, 4, 67710306, null, null],
            [4, 3, 74998593.5, null, null],
            [14, 8, 17862547, null, null],
            [13, 11, 32695565.5, null, null],
            [13, 10, 335435751.5],
            [12, 11, 58328763, null, null],
            [12, 10, 99256773],
            [10, 12, 19871517, null, null],
            [10, 11, 62492979.5, null, null],
            [11, 11, 59114294, null, null],
            [11, 10, 14691077, null, null],
            [9, 12, 7265675, null, null],
            [8, 13, 232048, null, null],
            [10, 10, 5, null, null],
            [6, 15, 1216200, null, null],
            [5, 15, 2313576, null, null],
            [10, 13, 454700631.5, null, null],
            [11, 12, 38700313.5, null, null],
            [8, 16, 46284866.5, null, null],
            [9, 16, 44703465.5, null, null],
            [8, 14, 12795126, null, null],
            [10, 14, 5400468, null, null],
            [12, 15, 168450133.5, null, null],
            [11, 14, 349494, null, null],
            [13, 15, 330123.5, null, null],
            [12, 16, 109756.5, null, null],
            [13, 18, 35192.5],
            [12, 18, 6111.5, null, null],
            [14, 18, 218905],
            [11, 17, 584082.5, null, null],
            [14, 11, 495230.5],
            [11, 13, 1199537, null, null],
            [12, 7, 1173844.5, null, null],
            [13, 7, 1382670.5, null, null],
            [13, 8, 1431164],
            [1, 6, 1506869.5, null, null],
            [2, 4, 3334334.5, null, null],
            [1, 0, 3018337, null, null],
            [0, 1, 698313.5, null, null],
            [18, 8, 260351],
            [18, 9, 12954484.5],
            [18, 7, 59.5, null, null],
            [17, 10, 6655.5, null, null],
            [14, 0, 64.5, null, null],
            [15, 0, 12926.5, null, null],
            [13, 0, 75.5, null, null],
            [16, 1, 7045.5, null, null],
            [3, 3, 52.5, null, null],
            [15, 7, 144390.5],
            [15, 6, 108219, null, null],
            [15, 8, 270.5, null, null],
            [14, 5, 36327.5, null, null],
            [15, 4, 89.5, null, null],
            [12, 14, 21977.5, null, null],
            [14, 15, 204806, null, null],
            [4, 5, 48.5, null, null],
            [5, 5, 4104.5, null, null],
            [0, 4, 53.5, null, null],
            [0, 3, 6531.5, null, null],
            [0, 5, 57.5, null, null],
            [1, 2, 8778.5, null, null],
            [14, 3, 18161, null, null],
            [14, 4, 46842],
            [13, 3, 14252, null, null],
            [12, 6, 35560],
            [2, 0, 52463.5, null, null],
            [11, 3, 53377],
            [12, 4, 3823.5, null, null],
            [11, 2, 114.5, null, null],
            [10, 1, 10630.5, null, null],
            [11, 1, 30281],
            [11, 0, 2979.5, null, null],
            [13, 12, 46644, null, null],
            [12, 12, 4039.5, null, null],
            [14, 12, 128.5, null, null],
            [4, 1, 32789, null, null],
            [-1, -1, 17647],
            [-1, -1, 4639, null, null]
        ],
        "outcome": "87.5 points",
        "pause_control": {
            "stone-removal": true
        },
        "phase": "finished",
        "player_pool": {
            "1": {
                "accepted_stones": "lblcldblclhljlklimcnhninjnknhoiogpjpkphqiqfrgr",
                "accepted_strict_seki_mode": false,
                "id": 1,
                "professional": false,
                "rank": 21.684411812485017,
                "username": "Player 1"
            },
            "449941": {
                "accepted_stones": "lblcldblclhljlklimcnhninjnknhoiogpjpkphqiqfrgr",
                "accepted_strict_seki_mode": false,
                "id": 449941,
                "professional": false,
                "rank": 22.19064231848925,
                "username": "Player 449941"
            }
        },
        "players": {
            "black": {
                "accepted_stones": "lblcldblclhljlklimcnhninjnknhoiogpjpkphqiqfrgr",
                "accepted_strict_seki_mode": false,
                "id": 1,
                "professional": false,
                "rank": 21.684411812485017,
                "username": "Player 1"
            },
            "white": {
                "accepted_stones": "lblcldblclhljlklimcnhninjnknhoiogpjpkphqiqfrgr",
                "accepted_strict_seki_mode": false,
                "id": 449941,
                "professional": false,
                "rank": 22.19064231848925,
                "username": "Player 449941"
            }
        },
        "private": false,
        "ranked": true,
        "removed": "lblcldblclhljlklimcnhninjnknhoiogpjpkphqiqfrgr",
        "rules": "chinese",
        "score": {
            "black": {
                "handicap": 0,
                "komi": 0,
                "prisoners": 0,
                "scoring_positions": "qarasapbrbsbpcqcrcscqdacbdgeheiegfhfifjfkfgghgigjgkgihjhkhlhkimiljmjnjojqjrjokpkqkskplqlrlslqmrmsmpnqnrnsnpoqorosoqprpsppqqqrqsqprqrrrsrpsqsrssspaabbbobqbbcccocadcdgdhdidpdrdsdbecedeeefejekeoepeqerecffflfpfegfglgmgghhhmhphiijilinioipiqirikjpjsjlkmknkrkolnmompmonoompnpopppoqornsos",
                "stones": 68,
                "territory": 72,
                "total": 140
            },
            "white": {
                "handicap": 0,
                "komi": 7.5,
                "prisoners": 0,
                "scoring_positions": "eafagahaiajakamafbgbhbibjblbmbecfcjckclcmcldmddbnfagahbhchdhaibicidieifiajbjdjejfjgjhjakckdkekfkgkhkalblcldlelflglhlambmcmdmemfmimancndnenfnhninjnknaobodoeofohoiojoapbpcpepgphpipjpkpaqbqcqdqeqgqhqiqarbrcrdrfrgrhrjrasbscsdsesfsgshsisjskslsogqgrgsgjkjlklmnlqmrbacadalanaoacbebkbnbdcgchcicncddedfdjdkdndodaelemeneseafbfdfefmfofqfrfsfbgcgdgngpgehfhnhohqhrhshgihisicjijjjbkikkkilllmlnlgmhmjmkmlmmmbngnlnnncogokolomonodpfplpfqjqkqmqnqerirkrlrnrms",
                "stones": 91,
                "territory": 129,
                "total": 227.5
            }
        },
        "score_handicap": true,
        "score_passes": true,
        "score_prisoners": false,
        "score_stones": true,
        "score_territory": true,
        "score_territory_in_seki": true,
        "strict_seki_mode": false,
        "time_control": {
            "initial_time": 604800,
            "max_time": 2419200,
            "pause_on_weekends": true,
            "speed": "correspondence",
            "system": "fischer",
            "time_control": "fischer",
            "time_increment": 172800
        },
        "white_must_pass_last": false,
        "white_player_id": 449941,
        "width": 19,
        "winner": 449941
    }
    """#
}
