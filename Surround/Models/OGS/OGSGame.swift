//
//  OGSGame.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/30/20.
//

import Foundation

struct PlayerScore: Decodable {
    internal init(handicap: Int, komi: Double, scoringPositions: Set<[Int]>, stones: Int, territory: Int, prisoners: Int, total: Double) {
        self.handicap = handicap
        self.komi = komi
        self.scoringPositions = scoringPositions
        self.stones = stones
        self.territory = territory
        self.prisoners = prisoners
        self.total = total
    }
    
    var handicap: Int
    var komi: Double
    var scoringPositions: Set<[Int]>
    var stones: Int
    var territory: Int
    var prisoners: Int
    var total: Double
    
    enum CodingKeys: String, CodingKey {
        case handicap, komi, scoringPositions, stones, territory, prisoners, total
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handicap = try container.decode(Int.self, forKey: .handicap)
        komi = try container.decode(Double.self, forKey: .komi)
        stones = try container.decode(Int.self, forKey: .stones)
        territory = try container.decode(Int.self, forKey: .territory)
        prisoners = try container.decode(Int.self, forKey: .prisoners)
        total = try container.decode(Double.self, forKey: .total)
        scoringPositions = try BoardPosition.points(fromPositionString: container.decode(String.self, forKey: .scoringPositions))
    }
}

struct GameScores: Decodable {
    var black: PlayerScore
    var white: PlayerScore
}

enum OGSGamePhase: String, Decodable {
    case play
    case stoneRemoval = "stone removal"
    case finished
}

enum OGSRule: String, Decodable {
    case chinese
    case aga
    case japanese
    case korean
    case ing
    case nz
}

struct OGSGame: Decodable {
    struct InitialState: Codable {
        var black: String
        var white: String
    }
    
    struct Players: Codable {
        var black: OGSUser
        var white: OGSUser
    }
    
    var allowKo: Bool
    var allowSelfCapture: Bool
    var allowSuperko: Bool
    var automaticStoneRemoval: Bool
    var whiteMustPassLast: Bool
    
    var blackPlayerId: Int
    var whitePlayerId: Int
    var disableAnalysis: Bool
    var freeHandicapPlacement: Bool

    var width: Int
    var height: Int
    var gameId: Int
    var gameName: String
    var handicap: Int
    var ranked: Bool
    var rules: OGSRule
    var initialPlayer: StoneColor
    var initialState: InitialState
    var komi: Double

    var moves: [[Int]]
    var players: Players
    
    var timeControl: TimeControl
    var clock: OGSClock
    var pauseControl: OGSPauseControl?
    
    var outcome: String?
    var winner: Int?
    
    var removed: String?
    var score: GameScores?
    var scoreHandicap: Bool
    var scorePasses: Bool
    var scorePrisoners: Bool
    var scoreStones: Bool
    var scoreTerritory: Bool
    var scoreTerritoryInSeki: Bool
    var strictSekiMode: Bool
    var agaHandicapScoring: Bool
    var autoScoringDone: Bool?
    
    var undoRequested: Int?
    var phase: OGSGamePhase
}
