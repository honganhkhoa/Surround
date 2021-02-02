//
//  OGSChallenge.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/2/20.
//

import Foundation

struct OGSChallenge: Decodable, Identifiable {
    var id: Int
    var challenger: OGSUser?
    var challenged: OGSUser?
    var challengerColor: StoneColor?
    var game: OGSChallengeGameDetail?
    
    enum CodingKeys: String, CodingKey {
        case id
        case challenger
        case challenged
        case challengerColor
        case game
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if container.contains(.challenged) {
            // Direct challenge
            id = try container.decode(Int.self, forKey: .id)
            challenger = try container.decode(OGSUser.self, forKey: .challenger)
            challenged = try container.decode(OGSUser.self, forKey: .challenged)
            challengerColor = StoneColor(rawValue: try container.decode(String.self, forKey: .challengerColor))
            game = try container.decode(OGSChallengeGameDetail.self, forKey: .game)
        } else {
            // Custom game
            let singleKeyContainer = try decoder.singleValueContainer()
            game = try singleKeyContainer.decode(OGSChallengeGameDetail.self)
            id = game!.challengeId!
            challenger = OGSUser(
                username: game!.username!,
                id: game!.userId!,
                rank: game!.userRank!
            )
        }
    }
    
    func isUserEligible(user: OGSUser) -> Bool {
        if user.id == self.challenger?.id {
            return false
        }

        let userRank = user.rank()        
        if let minRank = game?.minRank, let maxRank = game?.maxRank {
            if userRank < Double(minRank) || userRank > Double(maxRank) {
                return false
            }
        }
        if let challengerRank = challenger?.rank {
            if game?.ranked == true && abs(challengerRank - Double(userRank)) > 9 {
                return false
            }
        }
        
        return true
    }
}

struct OGSChallengeGameDetail: Decodable {
    var width: Int
    var height: Int
    
    var ranked: Bool
    var komi: Double?
    var handicap: Int
    var disableAnalysis: Bool
    var name: String
    var rules: OGSRule
    var timeControl: TimeControl?
    
    // Custom game
    var challengeId: Int?
    var userId: Int?
    var username: String?
    var userRank: Double?
    var minRank: Int?
    var maxRank: Int?
    
    enum CodingKeys: String, CodingKey {
        case width
        case height
        case ranked
        case komi
        case handicap
        case disableAnalysis
        case name
        case rules
        case timeControlParameters
        
        // Custom games
        case gameId
        case userId
        case username
        case maxRank
        case minRank
        case challengeId
        case rank
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        ranked = try container.decode(Bool.self, forKey: .ranked)
        if let komiString = try? container.decodeIfPresent(String.self, forKey: .komi) {
            komi = Double(komiString)!
        } else {
            komi = try container.decodeIfPresent(Double.self, forKey: .komi)
        }
        handicap = try container.decode(Int.self, forKey: .handicap)
        disableAnalysis = try container.decode(Bool.self, forKey: .disableAnalysis)
        name = try container.decode(String.self, forKey: .name)
        rules = OGSRule(rawValue: try container.decode(String.self, forKey: .rules))!
        if let timeControlParameters = try? container.decodeIfPresent(String.self, forKey: .timeControlParameters) {
            let jsonDecoder = JSONDecoder()
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
            timeControl = try jsonDecoder.decode(TimeControl.self, from: timeControlParameters.data(using: String.Encoding.utf8)!)
        } else {
            timeControl = try container.decodeIfPresent(TimeControl.self, forKey: .timeControlParameters)
        }
        
        // Custom game
        challengeId = try container.decodeIfPresent(Int.self, forKey: .challengeId)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        userRank = try container.decodeIfPresent(Double.self, forKey: .rank)
        minRank = try container.decodeIfPresent(Int.self, forKey: .minRank)
        maxRank = try container.decodeIfPresent(Int.self, forKey: .maxRank)
    }
}


extension OGSChallenge {
    static var sampleChallenge: OGSChallenge {
        let data = #"""
            {
              "id": 8849956,
              "challenger": {
                "id": 765826,
                "username": "hakhoa",
                "country": "un",
                "icon": "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/f945af04d1b32aaf565900a166a39b06-32.png",
                "ratings": {
                  "overall": {
                    "rating": 1500,
                    "deviation": 350,
                    "volatility": 0.06,
                    "games_played": 0
                  }
                },
                "ranking": 0,
                "professional": false,
                "ui_class": "provisional"
              },
              "challenged": {
                "id": 314459,
                "username": "HongAnhKhoa",
                "country": "un",
                "icon": "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png",
                "ratings": {
                  "overall": {
                    "rating": 2059.277201217474,
                    "deviation": 97.33091835676129,
                    "volatility": 0.05894771456018793
                  }
                },
                "ranking": 27,
                "professional": false,
                "ui_class": "supporter"
              },
              "game": {
                "related": {
                  "detail": "/api/v1/games/27296949"
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
                "id": 27296949,
                "name": "Test game",
                "creator": 765826,
                "mode": "game",
                "source": "play",
                "black": null,
                "white": null,
                "width": 9,
                "height": 9,
                "rules": "nz",
                "ranked": false,
                "handicap": -1,
                "komi": "6.50",
                "time_control": "fischer",
                "black_player_rank": 0,
                "black_player_rating": "0.000",
                "white_player_rank": 0,
                "white_player_rating": "0.000",
                "time_per_move": 89280,
                "time_control_parameters": "{\"system\": \"fischer\", \"time_control\": \"fischer\", \"speed\": \"correspondence\", \"pause_on_weekends\": true, \"time_increment\": 86400, \"initial_time\": 259200, \"max_time\": 604800}",
                "disable_analysis": true,
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
                "historical_ratings": {}
              },
              "group": null,
              "challenger_color": "black",
              "aga_rated": false
            }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(OGSChallenge.self, from: data.data(using: .utf8)!)
    }
    static var sampleOpenChallenge: OGSChallenge {
        let data = #"""
            {
              "challenge_id": 16255024,
              "user_id": 442873,
              "username": "#albatros",
              "rank": 21.304892343947607,
              "pro": 0,
              "min_rank": 5,
              "max_rank": 36,
              "game_id": 30344070,
              "name": "Friendly Match",
              "ranked": true,
              "handicap": 0,
              "komi": null,
              "rules": "japanese",
              "width": 19,
              "height": 19,
              "challenger_color": "black",
              "disable_analysis": false,
              "time_control": "byoyomi",
              "time_control_parameters": {
                "system": "byoyomi",
                "speed": "live",
                "main_time": 900,
                "period_time": 15,
                "periods": 1,
                "pause_on_weekends": false,
                "time_control": "byoyomi"
              },
              "time_per_move": 25
            }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(OGSChallenge.self, from: data.data(using: .utf8)!)
    }
}
