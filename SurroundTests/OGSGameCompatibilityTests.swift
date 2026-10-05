import DictionaryCoding
import XCTest

final class OGSGameCompatibilityTests: XCTestCase {
    private let phases: [OGSGamePhase] = [.play, .stoneRemoval, .finished]
    private let flagKeys = [
        "allow_ko", "allow_self_capture", "allow_superko", "automatic_stone_removal",
        "white_must_pass_last", "disable_analysis", "free_handicap_placement",
        "score_handicap", "score_passes", "score_prisoners", "score_stones",
        "score_territory", "score_territory_in_seki", "strict_seki_mode", "aga_handicap_scoring",
    ]

    func testMissingFlagsMatchGobanForEveryRuleAndPhaseWithBothDecoders() throws {
        for rules in OGSRule.allCases {
            for phase in phases {
                let payload = basePayload(rules: rules, phase: phase)
                let expected = expectedFlags(rules: rules, phase: phase)
                for (decoder, game) in try decodedGames(payload) {
                    XCTAssertEqual(flags(game), expected, "\(decoder): \(rules.rawValue), \(phase.rawValue)")
                    XCTAssertEqual(game.gameId, 1001)
                    XCTAssertEqual(game.rules, rules)
                    XCTAssertEqual(game.phase, phase)
                }
            }
        }
    }

    func testSuppliedFlagsOverrideDefaultsForEveryRuleAndPhaseWithBothDecoders() throws {
        for rules in OGSRule.allCases {
            for phase in phases {
                for suppliedValue in [false, true] {
                    var payload = basePayload(rules: rules, phase: phase)
                    for key in flagKeys { payload[key] = suppliedValue }
                    let expected = Dictionary(uniqueKeysWithValues: flagKeys.map { ($0, suppliedValue) })
                    for (decoder, game) in try decodedGames(payload) {
                        XCTAssertEqual(flags(game), expected,
                                       "\(decoder): \(rules.rawValue), \(phase.rawValue), supplied \(suppliedValue)")
                    }
                }
            }
        }
    }

    func testDefaultingOneMissingFlagPreservesOtherSuppliedFlagsWithBothDecoders() throws {
        let defaults = expectedFlags(rules: .japanese, phase: .finished)
        for missingKey in flagKeys {
            var payload = basePayload(rules: .japanese, phase: .finished)
            var expected = defaults.mapValues { !$0 }
            for (key, value) in expected { payload[key] = value }
            payload.removeValue(forKey: missingKey)
            expected[missingKey] = defaults[missingKey]
            for (decoder, game) in try decodedGames(payload) {
                XCTAssertEqual(flags(game), expected, "\(decoder): omitted \(missingKey)")
            }
        }
    }

    func testExplicitNullAndMalformedFlagsAreRejectedByBothDecoders() throws {
        for key in flagKeys {
            for value in [NSNull(), "true", [true], ["value": true]] as [Any] {
                var payload = basePayload()
                payload[key] = value
                try assertBothDecodersReject(payload, context: "Malformed \(key): \(value)")
            }
        }
    }

    func testSuppliedNumericFlagsRetainEachDecodersExistingBehavior() throws {
        // DictionaryCoding has always accepted numeric flags; JSONDecoder has
        // always required booleans. Missing-field compatibility changes neither.
        for suppliedValue in [0, 1] {
            var payload = basePayload()
            for key in flagKeys { payload[key] = suppliedValue }
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let game = try decoder.decode(OGSGame.self, from: payload)
            XCTAssertEqual(flags(game), Dictionary(uniqueKeysWithValues:
                flagKeys.map { ($0, suppliedValue != 0) }))
            let jsonDecoder = JSONDecoder()
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
            XCTAssertThrowsError(try jsonDecoder.decode(OGSGame.self,
                from: JSONSerialization.data(withJSONObject: payload)))
        }
    }

    func testChineseImportPresenceDefaultsOnlyMissingFreeHandicapPlacement() throws {
        // Goban checks the presence of ogs_import, including false and null.
        for marker in [false, true, NSNull(), ["source": "sgf"]] as [Any] {
            var payload = basePayload(rules: .chinese)
            payload["ogs_import"] = marker
            for (decoder, game) in try decodedGames(payload) {
                XCTAssertFalse(game.freeHandicapPlacement, decoder)
                XCTAssertTrue(game.scoreHandicap, decoder)
            }
            payload["free_handicap_placement"] = true
            for (decoder, game) in try decodedGames(payload) {
                XCTAssertTrue(game.freeHandicapPlacement, "\(decoder): explicit imported-game setting")
            }
        }

        for rules in OGSRule.allCases where rules != .chinese {
            var payload = basePayload(rules: rules)
            payload["ogs_import"] = true
            for (decoder, game) in try decodedGames(payload) {
                XCTAssertEqual(flags(game), expectedFlags(rules: rules, phase: .play), decoder)
            }
        }
    }

    func testRequiredGameFieldsRemainRequiredAndTypedWithBothDecoders() throws {
        let requiredKeys = [
            "game_id", "black_player_id", "white_player_id", "width", "height",
            "game_name", "handicap", "ranked", "rules", "phase", "initial_player",
            "initial_state", "komi", "moves", "players", "time_control", "clock",
        ]
        for key in requiredKeys {
            for value in [nil, NSNull(), ["invalid": true]] as [Any?] {
                var payload = basePayload()
                payload[key] = value
                try assertBothDecodersReject(payload, context: "Required \(key): \(String(describing: value))")
            }
        }

        let malformedStructure: [(String, Any)] = [
            ("phase", "unknown-phase"),
            ("rules", "unknown-rules"),
            ("game_id", "1001"),
            ("black_player_id", true),
            ("initial_player", "unknown-color"),
            ("initial_state", ["black": ""]),
            ("players", ["black": ["id": 1, "username": "Black"] as [String: Any]]),
            ("moves", [[0, "invalid-row"] as [Any]]),
            ("time_control", ["time_control": "fischer", "system": "fischer"]),
            ("clock", ["white_player_id": 2, "current_player": 1, "last_move": 0]),
        ]
        for (key, value) in malformedStructure {
            var payload = basePayload()
            payload[key] = value
            try assertBothDecodersReject(payload, context: "Malformed \(key)")
        }
    }

    func testModernGameRetainsExplicitFlagsAndCoreDataWithBothDecoders() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-25076729", withExtension: "json"))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var expected: [String: Bool] = [:]
        for key in flagKeys { expected[key] = try XCTUnwrap(payload[key] as? Bool, key) }
        let expectedMoveCount = try XCTUnwrap((payload["moves"] as? [Any])?.count)
        let expectedPhase = try XCTUnwrap(payload["phase"] as? String)

        for (decoder, game) in try decodedGames(payload) {
            XCTAssertEqual(flags(game), expected, decoder)
            XCTAssertEqual(game.gameId, 25076729, decoder)
            XCTAssertEqual(game.moves.count, expectedMoveCount, decoder)
            XCTAssertEqual(game.phase.rawValue, expectedPhase, decoder)
            XCTAssertEqual(game.outcome, payload["outcome"] as? String, decoder)
        }
    }

    func testLegacyArchivedGameDecodesWithoutScoreHandicapWithBothDecoders() throws {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.legacyGameJSON.utf8)) as? [String: Any])
        XCTAssertNil(payload["score_handicap"])
        for (decoder, game) in try decodedGames(payload) {
            XCTAssertEqual(game.gameId, 5756546, decoder)
            XCTAssertEqual(game.rules, .japanese, decoder)
            XCTAssertEqual(game.phase, .finished, decoder)
            XCTAssertEqual(game.moves.count, 152, decoder)
            XCTAssertEqual(game.outcome, "Resignation", decoder)
            XCTAssertFalse(game.scoreHandicap, decoder)
            for key in flagKeys where key != "score_handicap" {
                XCTAssertEqual(flags(game)[key], try XCTUnwrap(payload[key] as? Bool, key), "\(decoder): \(key)")
            }
        }
    }

    private func basePayload(rules: OGSRule = .japanese, phase: OGSGamePhase = .play) -> [String: Any] {
        [
            "game_id": 1001, "black_player_id": 1, "white_player_id": 2,
            "width": 19, "height": 19, "game_name": "Compatibility fixture",
            "handicap": 0, "ranked": false, "rules": rules.rawValue, "phase": phase.rawValue,
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

    private func expectedFlags(rules: OGSRule, phase: OGSGamePhase) -> [String: Bool] {
        // Independent expectations from GobanEngine.fillDefaults, not the native helper.
        let trueFlagsByRule: [OGSRule: Set<String>] = [
            .chinese: ["free_handicap_placement", "score_handicap", "score_passes", "score_stones",
                       "score_territory", "score_territory_in_seki"],
            .aga: ["white_must_pass_last", "aga_handicap_scoring", "score_handicap", "score_passes",
                   "score_stones", "score_territory", "score_territory_in_seki"],
            .japanese: ["allow_superko", "score_passes", "score_prisoners", "score_territory"],
            .korean: ["allow_superko", "score_passes", "score_prisoners", "score_territory"],
            .ing: ["allow_self_capture", "free_handicap_placement", "score_handicap", "score_passes",
                   "score_stones", "score_territory", "score_territory_in_seki"],
            .nz: ["allow_self_capture", "free_handicap_placement", "score_passes", "score_stones",
                  "score_territory", "score_territory_in_seki"],
        ]
        var trueFlags = trueFlagsByRule[rules]!
        if phase == .finished { trueFlags.insert("strict_seki_mode") }
        return Dictionary(uniqueKeysWithValues: flagKeys.map { ($0, trueFlags.contains($0)) })
    }

    private func flags(_ game: OGSGame) -> [String: Bool] {
        [
            "allow_ko": game.allowKo, "allow_self_capture": game.allowSelfCapture,
            "allow_superko": game.allowSuperko, "automatic_stone_removal": game.automaticStoneRemoval,
            "white_must_pass_last": game.whiteMustPassLast, "disable_analysis": game.disableAnalysis,
            "free_handicap_placement": game.freeHandicapPlacement, "score_handicap": game.scoreHandicap,
            "score_passes": game.scorePasses, "score_prisoners": game.scorePrisoners,
            "score_stones": game.scoreStones, "score_territory": game.scoreTerritory,
            "score_territory_in_seki": game.scoreTerritoryInSeki, "strict_seki_mode": game.strictSekiMode,
            "aga_handicap_scoring": game.agaHandicapScoring,
        ]
    }

    private func decodedGames(_ payload: [String: Any]) throws -> [(String, OGSGame)] {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return [
            ("JSONDecoder", try jsonDecoder.decode(OGSGame.self, from: JSONSerialization.data(withJSONObject: payload))),
            ("DictionaryDecoder", try dictionaryDecoder.decode(OGSGame.self, from: payload)),
        ]
    }

    private func assertBothDecodersReject(_ payload: [String: Any], context: String,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try jsonDecoder.decode(OGSGame.self, from: data),
                             "JSONDecoder: \(context)", file: file, line: line)
        XCTAssertThrowsError(try dictionaryDecoder.decode(OGSGame.self, from: payload),
                             "DictionaryDecoder: \(context)", file: file, line: line)
    }
}

private extension OGSGameCompatibilityTests {
    // Public archived OGS gamedata from 2016. Player labels and the game title
    // are anonymized; IDs, all 152 moves and wire field types are retained.
    static let legacyGameJSON = #"""
    {
        "aga_handicap_scoring": false,
        "allow_ko": false,
        "allow_self_capture": false,
        "allow_superko": true,
        "automatic_stone_removal": false,
        "black_player_id": 103791,
        "clock": {
            "current_player": 103791,
            "title": "Archived compatibility fixture",
            "black_player_id": 103791,
            "last_move": 1467887968962,
            "white_player_id": 314459,
            "expiration": 1467888268962,
            "game_id": 5756546,
            "black_time": {
                "thinking_time": 0,
                "period_time": 60,
                "periods": 5
            },
            "white_time": {
                "thinking_time": 0,
                "period_time": 60,
                "periods": 5
            }
        },
        "disable_analysis": false,
        "end_time": 1467887973,
        "free_handicap_placement": false,
        "game_id": 5756546,
        "game_name": "Archived compatibility fixture",
        "handicap": 0,
        "height": 19,
        "initial_player": "black",
        "initial_state": {
            "white": "",
            "black": ""
        },
        "komi": 6.5,
        "moves": [
            [15, 3, 3636],
            [15, 15, 5039],
            [3, 3, 6833],
            [3, 15, 3432],
            [9, 3, 33857],
            [2, 5, 9003],
            [2, 7, 197737],
            [2, 2, 7062],
            [3, 2, 37681],
            [2, 3, 10136],
            [3, 4, 4741],
            [1, 5, 2851],
            [3, 5, 3157],
            [3, 6, 15800],
            [4, 6, 16849],
            [3, 7, 4300],
            [15, 9, 5453],
            [9, 16, 42841],
            [2, 13, 46831],
            [2, 14, 7658],
            [3, 13, 1728],
            [5, 15, 3422],
            [2, 9, 11952],
            [2, 8, 32016],
            [3, 8, 1346],
            [1, 8, 7142],
            [4, 8, 8842],
            [2, 6, 16236],
            [3, 10, 16814],
            [4, 7, 9888],
            [1, 9, 1639],
            [1, 7, 32316],
            [5, 6, 3772],
            [5, 7, 2831],
            [16, 4, 13915],
            [6, 6, 11323],
            [6, 5, 16059],
            [7, 6, 29875],
            [7, 5, 9772],
            [16, 11, 52982],
            [15, 13, 10614],
            [14, 11, 4780],
            [16, 15, 3648],
            [16, 16, 15797],
            [16, 14, 18694],
            [14, 15, 16085],
            [13, 13, 3549],
            [12, 11, 6148],
            [13, 12, 14236],
            [13, 11, 4100],
            [12, 15, 4187],
            [12, 16, 26785],
            [11, 15, 4721],
            [11, 16, 4644],
            [9, 15, 9429],
            [10, 15, 2637],
            [10, 14, 1508],
            [10, 16, 1630],
            [11, 13, 7477],
            [13, 15, 16951],
            [13, 14, 5734],
            [9, 14, 11296],
            [9, 13, 2051],
            [8, 15, 6299],
            [7, 8, 2841],
            [6, 7, 18263],
            [8, 6, 2156],
            [10, 12, 33633],
            [10, 13, 5502],
            [9, 11, 33558],
            [9, 12, 20234],
            [10, 11, 8631],
            [11, 8, 26560],
            [13, 2, 15049],
            [15, 2, 3489],
            [13, 8, 17121],
            [12, 6, 9028],
            [15, 7, 8804],
            [13, 9, 3371],
            [14, 9, 18090],
            [14, 10, 3051],
            [14, 8, 2626],
            [15, 10, 1231],
            [12, 9, 5202],
            [13, 10, 5575],
            [12, 10, 24057],
            [15, 11, 3264],
            [15, 12, 10926],
            [16, 12, 1280],
            [14, 12, 4482],
            [16, 10, 17280],
            [17, 11, 4461],
            [17, 10, 3637],
            [17, 12, 7649],
            [16, 13, 1582],
            [17, 13, 15066],
            [16, 7, 28780],
            [12, 8, 15628],
            [16, 8, 10712],
            [17, 15, 8860],
            [15, 14, 10155],
            [17, 16, 14600],
            [8, 14, 1665],
            [7, 14, 4967],
            [9, 15, 2857],
            [7, 12, 5626],
            [7, 15, 8141],
            [8, 16, 2639],
            [7, 13, 3360],
            [6, 14, 2933],
            [6, 13, 1090],
            [5, 13, 14275],
            [6, 12, 1775],
            [7, 11, 18595],
            [5, 12, 13448],
            [5, 8, 21233],
            [5, 9, 1883],
            [4, 9, 14420],
            [5, 10, 28154],
            [11, 7, 36771],
            [10, 8, 13693],
            [10, 7, 7119],
            [9, 7, 2687],
            [9, 8, 4002],
            [9, 9, 1308],
            [8, 8, 3823],
            [8, 9, 3057],
            [9, 6, 12738],
            [8, 7, 1811],
            [13, 5, 47683],
            [11, 5, 4919],
            [12, 7, 10194],
            [11, 2, 17795],
            [12, 5, 52375],
            [11, 6, 13266],
            [13, 6, 4950],
            [10, 4, 4732],
            [16, 6, 7948],
            [15, 6, 6702],
            [15, 5, 7802],
            [14, 6, 14914],
            [14, 7, 23048],
            [14, 5, 2192],
            [14, 4, 2818],
            [14, 6, 53224],
            [17, 7, 48653],
            [17, 6, 3824],
            [17, 5, 3503],
            [16, 5, 1308],
            [18, 6, 3976],
            [15, 4, 5802],
            [17, 8, 44063]
        ],
        "opponent_plays_first_after_resume": true,
        "outcome": "Resignation",
        "pause_on_weekends": false,
        "phase": "finished",
        "players": {
            "white": {
                "username": "White fixture",
                "professional": false,
                "rank": 19,
                "id": 314459
            },
            "black": {
                "username": "Black fixture",
                "professional": false,
                "rank": 17,
                "id": 103791
            }
        },
        "private": false,
        "ranked": true,
        "rules": "japanese",
        "score_passes": true,
        "score_prisoners": true,
        "score_stones": false,
        "score_territory": true,
        "score_territory_in_seki": false,
        "start_time": 1467885971,
        "strict_seki_mode": false,
        "superko_algorithm": "ssk",
        "time_control": {
            "time_control": "byoyomi",
            "period_time": 60,
            "main_time": 600,
            "periods": 5,
            "system": "byoyomi",
            "speed": "live"
        },
        "white_must_pass_last": false,
        "white_player_id": 314459,
        "width": 19,
        "winner": 314459
    }
    """#
}
