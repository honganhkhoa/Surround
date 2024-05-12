//
//  ChallengeTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 2024/3/18.
//

import XCTest

final class ChallengeTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParsingSeekgraphChallenge() throws {
        let seekgraphChallenge = #"""
            {
                "challenge_id": 28448023,
                "user_id": 655163,
                "username": "Spidermonkey",
                "rank": 25.223410705952766,
                "pro": 0,
                "min_rank": 23,
                "max_rank": 27,
                "game_id": 62661221,
                "name": "Friendly Match",
                "ranked": true,
                "handicap": 0,
                "komi": null,
                "rules": "japanese",
                "width": 9,
                "height": 9,
                "challenger_color": "white",
                "disable_analysis": false,
                "time_control": "simple",
                "time_control_parameters": {
                    "per_move": 20,
                    "pause_on_weekends": false,
                    "speed": "live",
                    "system": "simple",
                    "time_control": "simple"
                },
                "time_per_move": 20,
                "rengo": false,
                "rengo_nominees": [],
                "rengo_black_team": [],
                "rengo_white_team": [],
                "rengo_participants": [],
                "rengo_casual_mode": false,
                "rengo_auto_start": 0,
                "invite_only": false,
                "uuid": "3tiGdpJSds8kbo3ZBCbqv6",
                "created": "2024-03-21T02:58:09"
            }
            """#

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSSeekgraphChallenge.self, from: seekgraphChallenge.data(using: .utf8)!)
        
        XCTAssertEqual(challenge.id, 28448023)
        XCTAssertEqual(challenge.challenger?.id, 655163)
        XCTAssertEqual(challenge.challenger?.username, "Spidermonkey")
        XCTAssertEqual(challenge.game.minRank, 23)
        XCTAssertEqual(challenge.game.maxRank, 27)
        XCTAssertEqual(challenge.game.id, 62661221)
        XCTAssertEqual(challenge.game.name, "Friendly Match")
        XCTAssertEqual(challenge.game.ranked, true)
        XCTAssertEqual(challenge.game.handicap, 0)
        XCTAssertEqual(challenge.game.komi, nil)
        XCTAssertEqual(challenge.game.rules, .japanese)
        XCTAssertEqual(challenge.game.width, 9)
        XCTAssertEqual(challenge.game.height, 9)
        XCTAssertEqual(challenge.challengerColor, .white)
        XCTAssertEqual(challenge.game.disableAnalysis, false)
        XCTAssertEqual(challenge.game.timeControl.system, TimeControlSystem.Simple(perMove: 20))
        XCTAssertEqual(challenge.rengo, false)
    }
    
    func testParsingSeekgraphRengoChallenge() throws {
        let seekgraphRengoChallenge = #"""
            {
                "challenge_id": 28445989,
                "user_id": 1523852,
                "username": "zzbaebae",
                "rank": 27.878894400082505,
                "pro": 0,
                "min_rank": -1000,
                "max_rank": 1000,
                "game_id": 62656196,
                "name": "친선 대국",
                "ranked": false,
                "handicap": 0,
                "komi": null,
                "rules": "korean",
                "width": 19,
                "height": 19,
                "challenger_color": "automatic",
                "disable_analysis": false,
                "time_control": "simple",
                "time_control_parameters": {
                    "per_move": 72000,
                    "pause_on_weekends": false,
                    "speed": "correspondence",
                    "system": "simple",
                    "time_control": "simple"
                },
                "time_per_move": 72000,
                "rengo": true,
                "rengo_nominees": [],
                "rengo_black_team": [
                    1523852
                ],
                "rengo_white_team": [],
                "rengo_participants": [
                    1523852
                ],
                "rengo_casual_mode": true,
                "rengo_auto_start": 6,
                "invite_only": false,
                "uuid": "34kAuPtdo3yVCws573W3u3",
                "created": "2024-03-20T22:26:56"
            }
            """#
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSSeekgraphChallenge.self, from: seekgraphRengoChallenge.data(using: .utf8)!)
        
        XCTAssertEqual(challenge.id, 28445989)
        XCTAssertEqual(challenge.challenger?.id, 1523852)
        XCTAssertEqual(challenge.challenger?.username, "zzbaebae")
        XCTAssertEqual(challenge.game.minRank, -1000)
        XCTAssertEqual(challenge.game.maxRank, 1000)
        XCTAssertEqual(challenge.game.id, 62656196)
        XCTAssertEqual(challenge.game.name, "친선 대국")
        XCTAssertEqual(challenge.game.ranked, false)
        XCTAssertEqual(challenge.game.handicap, 0)
        XCTAssertEqual(challenge.game.komi, nil)
        XCTAssertEqual(challenge.game.rules, .korean)
        XCTAssertEqual(challenge.game.width, 19)
        XCTAssertEqual(challenge.game.height, 19)
        XCTAssertEqual(challenge.challengerColor, nil)
        XCTAssertEqual(challenge.game.disableAnalysis, false)
        XCTAssertEqual(challenge.game.timeControl.system, .Simple(perMove: 72000))
        XCTAssertEqual(challenge.game.timeControl.pauseOnWeekends, false)
        XCTAssertEqual(challenge.rengo, true)
        XCTAssertEqual(challenge.game.rengoCasualMode, true)
        XCTAssertEqual(challenge.game.rengoAutoStart, 6)
        XCTAssertEqual(challenge.game.rengoBlackTeam?.count, 1)
        XCTAssertEqual(challenge.game.rengoParticipants?.count, 1)
    }
    
    func testParskingSeekgraphChallenge2() throws {
        let seekgraphChallenge = #"""
            {
                "challenge_id": 28497213,
                "user_id": 1494583,
                "username": "janeeyree23",
                "rank": 24.303382182144386,
                "pro": 0,
                "min_rank": -1000,
                "max_rank": 1000,
                "game_id": 62789185,
                "name": "ryo",
                "ranked": false,
                "handicap": 0,
                "komi": 7.5,
                "rules": "chinese",
                "width": 9,
                "height": 9,
                "challenger_color": "black",
                "disable_analysis": false,
                "time_control": "byoyomi",
                "time_control_parameters": {
                    "main_time": 604800,
                    "period_time": 86400,
                    "periods": 5,
                    "periods_min": 1,
                    "periods_max": 300,
                    "pause_on_weekends": true,
                    "speed": "correspondence",
                    "system": "byoyomi",
                    "time_control": "byoyomi"
                },
                "time_per_move": 107733,
                "rengo": false,
                "rengo_nominees": [],
                "rengo_black_team": [],
                "rengo_white_team": [],
                "rengo_participants": [],
                "rengo_casual_mode": false,
                "rengo_auto_start": 0,
                "invite_only": false,
                "uuid": "3GTMb7PkW2tVYR2s9rXv2t",
                "created": "2024-03-25T08:35:02"
            }
            """#
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSSeekgraphChallenge.self, from: seekgraphChallenge.data(using: .utf8)!)

        XCTAssertEqual(challenge.game.komi, 7.5)
    }

    func testParsingDirectChallenge() throws {
        let directChallenge = #"""
            {
              "id": 10813,
              "challenger": {
                "id": 1768,
                "username": "hakhoa3",
                "country": "un",
                "icon": "https://secure.gravatar.com/avatar/db29450c3f5e97f97846693611f98c15?s=64&d=retro",
                "ratings": {
                  "version": 5,
                  "overall": {
                    "rating": 1003.5976036531721,
                    "deviation": 350,
                    "volatility": 0.06
                  }
                },
                "ranking": 15,
                "professional": false,
                "ui_class": "provisional"
              },
              "challenged": {
                "id": 1765,
                "username": "hakhoa",
                "country": "un",
                "icon": "https://secure.gravatar.com/avatar/8698ff92115213ab187d31d4ee5da8ea?s=64&d=retro",
                "ratings": {
                  "version": 5,
                  "overall": {
                    "rating": 1510.3007606332371,
                    "deviation": 243.59651454189097,
                    "volatility": 0.060002852579482076
                  }
                },
                "ranking": 24.46181388604712,
                "professional": false,
                "ui_class": "provisional"
              },
              "game": {
                "related": {
                  "detail": "/api/v1/games/16896"
                },
                "players": {
                  "black": {
                    "username": null,
                    "ranking": 0,
                    "professional": false
                  },
                  "white": {
                    "username": null,
                    "ranking": 0,
                    "professional": false
                  }
                },
                "id": 16896,
                "name": "Friendly Match",
                "creator": 1768,
                "mode": "game",
                "source": "play",
                "black": null,
                "white": null,
                "width": 19,
                "height": 19,
                "rules": "japanese",
                "ranked": true,
                "handicap_rank_difference": null,
                "handicap": -1,
                "komi": null,
                "time_control": "byoyomi",
                "black_player_rank": 0,
                "black_player_rating": "0.000",
                "white_player_rank": 0,
                "white_player_rating": "0.000",
                "time_per_move": 91187,
                "time_control_parameters": "{\"system\": \"byoyomi\", \"time_control\": \"byoyomi\", \"speed\": \"correspondence\", \"pause_on_weekends\": true, \"main_time\": 604800, \"period_time\": 86400, \"periods\": 5}",
                "disable_analysis": false,
                "tournament": null,
                "tournament_round": 0,
                "ladder": null,
                "pause_on_weekends": true,
                "outcome": "",
                "black_lost": true,
                "white_lost": true,
                "annulled": false,
                "started": null,
                "ended": null,
                "sgf_filename": null,
                "historical_ratings": {},
                "rengo": false,
                "rengo_black_team": null,
                "rengo_white_team": null,
                "rengo_casual_mode": true,
                "flags": null,
                "bot_detection_results": null
              },
              "group": null,
              "challenger_color": "white",
              "aga_rated": false
            }
            """#
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSDirectChallenge.self, from: directChallenge.data(using: .utf8)!)
        
        XCTAssertEqual(challenge.challenger?.username, "hakhoa3")
        XCTAssertEqual(challenge.challenged?.username, "hakhoa")
        XCTAssertEqual(challenge.game.rules, .japanese)
        XCTAssertEqual(challenge.game.handicap, -1)
        XCTAssertEqual(challenge.challengerColor, .white)
        XCTAssertEqual(challenge.game.timeControl.system, .ByoYomi(mainTime: 604800, periods: 5, periodTime: 86400))
    }
    
    func testParsingChallengeTemplate() {
        let challengeTemplate = #"""
            {
              "initialized": false,
              "min_ranking": 10,
              "max_ranking": 33,
              "challenger_color": "white",
              "game": {
                "name": "Test",
                "rules": "ing",
                "ranked": true,
                "width": 19,
                "height": 19,
                "handicap": 0,
                "komi_auto": "automatic",
                "komi": 5.5,
                "disable_analysis": true,
                "initial_state": null,
                "private": false,
                "rengo": false,
                "time_control": "absolute",
                "time_control_parameters": {
                  "system": "absolute",
                  "speed": "correspondence",
                  "total_time": 2419200,
                  "pause_on_weekends": true,
                  "time_control": "absolute"
                },
                "pause_on_weekends": true
              },
              "rengo_auto_start": 0,
              "aga_ranked": false
            }
            """#
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSChallengeTemplate.self, from: challengeTemplate.data(using: .utf8)!)
        
        XCTAssertNil(challenge.challenger)
        XCTAssertNil(challenge.challenged)
        XCTAssertEqual(challenge.challengerColor, .white)
        XCTAssertEqual(challenge.game.rules, .ing)
        XCTAssertEqual(challenge.game.minRank, 10)
        XCTAssertEqual(challenge.game.maxRank, 33)
        XCTAssertEqual(challenge.game.timeControl.system, .Absolute(totalTime: 2419200))
        XCTAssertEqual(challenge.game.timeControl.pauseOnWeekends, true)
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedChallenge = try! encoder.encode(challenge)
        
        var redecodedChallenge = try! decoder.decode(OGSChallengeTemplate.self, from: encodedChallenge)
        
        // Surround overrides komiAuto and komi when decoding, which is a different behavior than OGS, so no need to check these
//        redecodedChallenge.game.komi = challenge.game.komi
//        redecodedChallenge.game.komiAuto = challenge.game.komiAuto
        XCTAssertEqual(redecodedChallenge, challenge)
    }
    
    func testParsingChallengeTemplateRandomColor() {
        let challengeTemplate = #"""
            {
              "initialized": false,
              "min_ranking": 10,
              "max_ranking": 33,
              "challenger_color": "random",
              "game": {
                "name": "Test",
                "rules": "ing",
                "ranked": true,
                "width": 19,
                "height": 19,
                "handicap": 0,
                "komi_auto": "automatic",
                "komi": 5.5,
                "disable_analysis": true,
                "initial_state": null,
                "private": false,
                "rengo": false,
                "time_control": "absolute",
                "time_control_parameters": {
                  "system": "absolute",
                  "speed": "correspondence",
                  "total_time": 2419200,
                  "pause_on_weekends": true,
                  "time_control": "absolute"
                },
                "pause_on_weekends": true
              },
              "rengo_auto_start": 0,
              "aga_ranked": false
            }
            """#
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let challenge = try! decoder.decode(OGSChallengeTemplate.self, from: challengeTemplate.data(using: .utf8)!)
        
        XCTAssertEqual(challenge.challengerColor, nil)
        XCTAssertEqual(challenge.randomColor, true)
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedChallenge = try! encoder.encode(challenge)
        
        let redecodedChallenge = try! JSONSerialization.jsonObject(with: encodedChallenge) as! [String: Any]
        XCTAssertEqual(redecodedChallenge["challenger_color"] as? String, "random")
    }
}
