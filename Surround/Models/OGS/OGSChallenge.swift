//
//  OGSChallenge.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/2/20.
//

import Foundation

protocol OGSChallenge: Decodable, Hashable {
    associatedtype GameDetail: OGSChallengeGameDetail
    
    var challenger: OGSUser? { get set }
    var challenged: OGSUser? { get set }
    var challengerColor: StoneColor? { get set }
    var game: GameDetail { get set }

//    enum CodingKeys: String, CodingKey {
//        case id
//        case challenger
//        case challenged
//        case challengerColor
//        case game
//        
//        // Encode only
//        case maxRanking
//        case minRanking
//        case initialized
//        case agaRanked
//    }
//    
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        
//        if container.contains(.challenged) {
//            // Direct challenge
//            id = try container.decode(Int.self, forKey: .id)
//            challenger = try container.decode(OGSUser.self, forKey: .challenger)
//            challenged = try container.decode(OGSUser.self, forKey: .challenged)
//            challengerColor = StoneColor(rawValue: try container.decode(String.self, forKey: .challengerColor))
//            game = try container.decode(OGSChallengeGameDetail.self, forKey: .game)
//        } else {
//            // Custom game
//            let singleKeyContainer = try decoder.singleValueContainer()
//            do {
//                game = try singleKeyContainer.decode(OGSChallengeGameDetail.self)
//            } catch {
//                game = try container.decode(OGSChallengeGameDetail.self, forKey: .game)
//            }
//            id = game.challengeId ?? 0
//            if let username = game.username, let userId = game.userId, let userRank = game.userRank {
//                challenger = OGSUser(
//                    username: username,
//                    id: userId,
//                    rank: userRank
//                )
//            }
//            if id == 0 {
//                id = self.hashValue
//            }
//        }
//    }
//    
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(challengerColor?.rawValue ?? "automatic", forKey: .challengerColor)
//        if let maxRank = game.maxRank, let minRank = game.minRank {
//            try container.encode(maxRank, forKey: .maxRanking)
//            try container.encode(minRank, forKey: .minRanking)
//        } else {
//            try container.encode(1000, forKey: .maxRanking)
//            try container.encode(-1000, forKey: .minRanking)
//        }
//        try container.encode(false, forKey: .initialized)
//        try container.encode(game, forKey: .game)
//        try container.encode(false, forKey: .agaRanked)
//
//        // This is used when creating challenges, so be careful when adding stuff...
//
//    }
//       
//    init(id: Int, challenger: OGSUser? = nil, challenged: OGSUser? = nil, challengerColor: StoneColor? = nil, game: OGSChallengeGameDetail) {
//        self.id = id
//        self.challenger = challenger
//        self.challenged = challenged
//        self.challengerColor = challengerColor
//        self.game = game
//    }

}

extension OGSChallenge {
    var hasHandicap: Bool { game.handicap > 0 }
    var useCustomKomi: Bool {
        if let game = game as? OGSChallengeTemplate.GameDetail {
            if game.komiAuto == "automatic" {
                return false
            }
        }
        return (game.komi != nil && game.komi != game.rules.defaultKomi)
    }
    var unusualBoardSize: Bool { game.width != game.height || ![9, 13, 19].contains(game.width) }
    var isUnusual: Bool { hasHandicap || useCustomKomi || game.timeControl.system.isUnusual || unusualBoardSize }
    
    var rengo: Bool {
        return game.rengo ?? false
    }
    
    func isUserEligible(user: OGSUser) -> Bool {
        if user.id == self.challenger?.id {
            return false
        }
        
        if rengo, let participants = game.rengoParticipants, participants.firstIndex(of: user.id) != nil {
            return false
        }

        let userRank = user.rank()
        if let minRank = game.minRank, let maxRank = game.maxRank {
            if userRank < Double(minRank) || userRank > Double(maxRank) {
                return false
            }
        }
        if let challengerRank = challenger?.rank {
            if game.ranked == true && abs(challengerRank - Double(userRank)) > 9 {
                return false
            }
        }
        
        return true
    }
}

protocol OGSChallengeGameDetail: Decodable, Hashable {
//    init(width: Int, height: Int, ranked: Bool, isPrivate: Bool = false, komi: Double? = nil, handicap: Int, disableAnalysis: Bool, name: String, rules: OGSRule, timeControl: TimeControl, challengerColor: StoneColor? = nil, challengeId: Int? = nil, userId: Int? = nil, username: String? = nil, userRank: Double? = nil, minRank: Int? = nil, maxRank: Int? = nil, rengo: Bool? = nil) {
//        self.width = width
//        self.height = height
//        self.ranked = ranked
//        self.isPrivate = isPrivate
//        self.komi = komi
//        self.handicap = handicap
//        self.disableAnalysis = disableAnalysis
//        self.name = name
//        self.rules = rules
//        self.timeControl = timeControl
//        self.challengerColor = challengerColor
//        self.challengeId = challengeId
//        self.userId = userId
//        self.username = username
//        self.userRank = userRank
//        self.minRank = minRank
//        self.maxRank = maxRank
//    }
    
    var width: Int { get set }
    var height: Int { get set }
    
    var ranked: Bool { get set }
    var isPrivate: Bool { get set } // = false
    var komi: Double? { get set }
    var handicap: Int { get set }
    var disableAnalysis: Bool { get set }
    var name: String { get set }
    var rules: OGSRule { get set }
    var timeControl: TimeControl { get set }

//    // Encode only
//    var challengerColor: StoneColor?
//    
//    // Custom game
//    var challengeId: Int?
//    var userId: Int?
//    var username: String?
//    var userRank: Double?
    var minRank: Int? { get set }
    var maxRank: Int? { get set }
    
    // Rengo
    var rengo: Bool? { get set }
    var rengoCasualMode: Bool? { get set }
    var rengoAutoStart: Int? { get set }
    var rengoBlackTeam: [Int]? { get set }
    var rengoWhiteTeam: [Int]? { get set }
    var rengoNominees: [Int]? { get set }
    var rengoParticipants: [Int]? { get set }
    
//    var id: Int?
    
//    enum CodingKeys: String, CodingKey {
//        case width
//        case height
//        case ranked
//        case komi
//        case handicap
//        case disableAnalysis
//        case name
//        case rules
//        case timeControlParameters
//        
//        // Encode only
//        case initialState
//        case komiAuto
//        case challengerColor
//        case isPrivate = "private"
//        case timeControl
//        case pauseOnWeekends
//        
//        // Custom games
//        case gameId
//        case userId
//        case username
//        case maxRank
//        case minRank
//        case challengeId
//        case rank
//        
//        // Rengo
//        case rengo
//        case rengoCasualMode
//        case rengoAutoStart
//        case rengoBlackTeam
//        case rengoWhiteTeam
//        case rengoNominees
//        case rengoParticipants
//    }
//    
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        
//        width = try container.decode(Int.self, forKey: .width)
//        height = try container.decode(Int.self, forKey: .height)
//        ranked = try container.decode(Bool.self, forKey: .ranked)
//        isPrivate = (try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? false
//        if let komiString = try? container.decodeIfPresent(String.self, forKey: .komi) {
//            komi = Double(komiString)!
//        } else {
//            komi = try container.decodeIfPresent(Double.self, forKey: .komi)
//        }
//        if let handicapString = try? container.decode(String.self, forKey: .handicap) {
//            handicap = Int(handicapString) ?? 0
//        } else {
//            handicap = try container.decode(Int.self, forKey: .handicap)
//        }
//        disableAnalysis = try container.decode(Bool.self, forKey: .disableAnalysis)
//        name = try container.decode(String.self, forKey: .name)
//        rules = OGSRule(rawValue: try container.decode(String.self, forKey: .rules))!
//        if let timeControlParameters = try? container.decodeIfPresent(String.self, forKey: .timeControlParameters) {
//            let jsonDecoder = JSONDecoder()
//            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
//            timeControl = try jsonDecoder.decode(TimeControl.self, from: timeControlParameters.data(using: String.Encoding.utf8)!)
//        } else {
//            timeControl = try container.decode(TimeControl.self, forKey: .timeControlParameters)
//        }
//        
//        // Custom game
//        challengeId = try container.decodeIfPresent(Int.self, forKey: .challengeId)
//        id = try container.decodeIfPresent(Int.self, forKey: .gameId)
//        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
//        username = try container.decodeIfPresent(String.self, forKey: .username)
//        userRank = try container.decodeIfPresent(Double.self, forKey: .rank)
//        minRank = try container.decodeIfPresent(Int.self, forKey: .minRank)
//        maxRank = try container.decodeIfPresent(Int.self, forKey: .maxRank)
//        
//        // Rengo
//        rengo = try container.decodeIfPresent(Bool.self, forKey: .rengo)
//        rengoCasualMode = try container.decodeIfPresent(Bool.self, forKey: .rengoCasualMode)
//        rengoAutoStart = try container.decodeIfPresent(Int.self, forKey: .rengoAutoStart)
//        rengoBlackTeam = try container.decodeIfPresent([Int].self, forKey: .rengoBlackTeam)
//        rengoWhiteTeam = try container.decodeIfPresent([Int].self, forKey: .rengoWhiteTeam)
//        rengoNominees = try container.decodeIfPresent([Int].self, forKey: .rengoNominees)
//        rengoParticipants = try container.decodeIfPresent([Int].self, forKey: .rengoParticipants)
//    }
//    
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(challengerColor?.rawValue ?? "automatic", forKey: .challengerColor)
//        try container.encode(disableAnalysis, forKey: .disableAnalysis)
//        try container.encode(handicap, forKey: .handicap)
//        try container.encode(height, forKey: .height)
//        try container.encode(width, forKey: .width)
//        try container.encodeNil(forKey: .initialState)
//        if komi == rules.defaultKomi || komi == nil {
//            try container.encodeNil(forKey: .komi)
//            try container.encode("automatic", forKey: .komiAuto)
//        } else if let komi = komi {
//            try container.encode(komi, forKey: .komi)
//            try container.encode("custom", forKey: .komiAuto)
//        }
//        try container.encode(name, forKey: .name)
//        try container.encode(isPrivate, forKey: .isPrivate)
//        try container.encode(ranked, forKey: .ranked)
//        try container.encode(rules, forKey: .rules)
//        try container.encode(timeControl.timeControl, forKey: .timeControl)
//        try container.encode(timeControl.pauseOnWeekends ?? true, forKey: .pauseOnWeekends)
//        try container.encode(timeControl, forKey: .timeControlParameters)
//        try container.encode(rengo ?? false, forKey: .rengo)
//        try container.encode(rengoCasualMode ?? false, forKey: .rengoCasualMode)
//        
//        // This is used when creating challenges, so be careful when adding stuff...
//        
//    }
}

extension OGSChallengeGameDetail {
    var rengoReadyToStart: Bool {
        guard rengo == true, let blackTeam = rengoBlackTeam, let whiteTeam = rengoWhiteTeam else {
            return false
        }
        return blackTeam.count > 0 && whiteTeam.count > 0 && blackTeam.count + whiteTeam.count > 2
    }
}

protocol OGSSubmittedChallenge: OGSChallenge, Identifiable {
    var id: Int { get set }
}

struct OGSDirectChallenge: OGSSubmittedChallenge, Identifiable {
    struct GameDetail: OGSChallengeGameDetail {
        var id: Int
        var width: Int
        var height: Int
        var ranked: Bool
        var isPrivate: Bool = false
        var komi: Double?
        var handicap: Int
        var disableAnalysis: Bool
        var name: String
        var rules: OGSRule
        var timeControl: TimeControl
        var minRank: Int?
        var maxRank: Int?
        var rengo: Bool?
        var rengoCasualMode: Bool?
        var rengoAutoStart: Int?
        var rengoBlackTeam: [Int]?
        var rengoWhiteTeam: [Int]?
        var rengoNominees: [Int]?
        var rengoParticipants: [Int]?
        
        enum CodingKeys: String, CodingKey {
            case id
            case width
            case height
            case ranked
            case isPrivate = "private"
            case komi
            case handicap
            case disableAnalysis
            case name
            case rules
            case timeControlParameters
            
            case rengo
            case rengoCasualMode
            case rengoAutoStart
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            id = try container.decode(Int.self, forKey: .id)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
            ranked = try container.decode(Bool.self, forKey: .ranked)
            isPrivate = (try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? false
            if let komiString = try? container.decodeIfPresent(String.self, forKey: .komi) {
                komi = Double(komiString)!
            } else {
                komi = try container.decodeIfPresent(Double.self, forKey: .komi)
            }
            handicap = try container.decode(Int.self, forKey: .handicap)
            disableAnalysis = try container.decode(Bool.self, forKey: .disableAnalysis)
            name = try container.decode(String.self, forKey: .name)
            rules = OGSRule(rawValue: try container.decode(String.self, forKey: .rules))!

            let timeControlParameters = try container.decode(String.self, forKey: .timeControlParameters)
            let jsonDecoder = JSONDecoder()
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
            timeControl = try jsonDecoder.decode(TimeControl.self, from: timeControlParameters.data(using: .utf8)!)
        }
    }

    var id: Int
    var challenger: OGSUser?
    var challenged: OGSUser?
    var challengerColor: StoneColor?
    var game: OGSDirectChallenge.GameDetail
    
    enum CodingKeys: String, CodingKey {
        case id
        case challenger
        case challenged
        case challengerColor
        case game
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.challenger = try container.decodeIfPresent(OGSUser.self, forKey: .challenger)
        self.challenged = try container.decodeIfPresent(OGSUser.self, forKey: .challenged)
        self.challengerColor = StoneColor(rawValue: try container.decode(String.self, forKey: .challengerColor))
        self.game = try container.decode(OGSDirectChallenge.GameDetail.self, forKey: .game)
    }
}

struct OGSSeekgraphChallenge: OGSSubmittedChallenge, Identifiable {
    struct GameDetail: OGSChallengeGameDetail {
        var id: Int
        var width: Int
        var height: Int
        var ranked: Bool
        var isPrivate: Bool = false
        var komi: Double?
        var handicap: Int
        var disableAnalysis: Bool
        var name: String
        var rules: OGSRule
        var timeControl: TimeControl
        var minRank: Int?
        var maxRank: Int?
        var rengo: Bool?
        var rengoCasualMode: Bool?
        var rengoAutoStart: Int?
        var rengoBlackTeam: [Int]?
        var rengoWhiteTeam: [Int]?
        var rengoNominees: [Int]?
        var rengoParticipants: [Int]?
    }

    var id: Int
    var challenger: OGSUser?
    var challenged: OGSUser?
    var challengerColor: StoneColor?
    var game: OGSSeekgraphChallenge.GameDetail
    
    enum CodingKeys: String, CodingKey {
        case challengeId
        case userId
        case username
        case rank
        case minRank
        case maxRank
        case gameId
        case name
        case ranked
        case handicap
        case komi
        case rules
        case width
        case height
        case challengerColor
        case disableAnalysis
        case timeControlParameters
        
        case rengo
        case rengoNominees
        case rengoBlackTeam
        case rengoWhiteTeam
        case rengoParticipants
        case rengoCasualMode
        case rengoAutoStart
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int.self, forKey: .challengeId)
        let userid = try container.decode(Int.self, forKey: .userId)
        let username = try container.decode(String.self, forKey: .username)
        let userrank = try container.decode(Double.self, forKey: .rank)
        challenger = OGSUser(username: username, id: userid, rank: userrank)
        challengerColor = StoneColor(rawValue: try container.decode(String.self, forKey: .challengerColor))

        var komi: Double?
        if let komiString = try? container.decodeIfPresent(String.self, forKey: .komi) {
            komi = Double(komiString)!
        } else {
            komi = try container.decodeIfPresent(Double.self, forKey: .komi)
        }

        game = OGSSeekgraphChallenge.GameDetail(
            id: try container.decode(Int.self, forKey: .gameId),
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            ranked: try container.decode(Bool.self, forKey: .ranked),
            komi: komi,
            handicap: try container.decode(Int.self, forKey: .handicap),
            disableAnalysis: try container.decode(Bool.self, forKey: .disableAnalysis),
            name: try container.decode(String.self, forKey: .name),
            rules: OGSRule(rawValue: try container.decode(String.self, forKey: .rules))!,
            timeControl: try container.decode(TimeControl.self, forKey: .timeControlParameters),
            minRank: try container.decodeIfPresent(Int.self, forKey: .minRank),
            maxRank: try container.decodeIfPresent(Int.self, forKey: .maxRank),
            rengo: try container.decodeIfPresent(Bool.self, forKey: .rengo),
            rengoCasualMode: try container.decodeIfPresent(Bool.self, forKey: .rengoCasualMode),
            rengoAutoStart: try container.decodeIfPresent(Int.self, forKey: .rengoAutoStart),
            rengoBlackTeam: try container.decodeIfPresent([Int].self, forKey: .rengoBlackTeam),
            rengoWhiteTeam: try container.decodeIfPresent([Int].self, forKey: .rengoWhiteTeam),
            rengoNominees: try container.decodeIfPresent([Int].self, forKey: .rengoNominees),
            rengoParticipants: try container.decodeIfPresent([Int].self, forKey: .rengoParticipants)
        )
    }
}

struct OGSChallengeTemplate: OGSChallenge, Encodable {
    struct GameDetail: OGSChallengeGameDetail, Encodable {
        internal init(width: Int, height: Int, ranked: Bool, isPrivate: Bool = false, komi: Double? = nil, komiAuto: String? = nil, handicap: Int, disableAnalysis: Bool, name: String, rules: OGSRule, timeControl: TimeControl, minRank: Int? = nil, maxRank: Int? = nil, initialState: OGSGame.InitialState? = nil, rengo: Bool? = nil, rengoCasualMode: Bool? = nil, rengoAutoStart: Int? = nil, rengoBlackTeam: [Int]? = nil, rengoWhiteTeam: [Int]? = nil, rengoNominees: [Int]? = nil, rengoParticipants: [Int]? = nil) {
            self.width = width
            self.height = height
            self.ranked = ranked
            self.isPrivate = isPrivate
            self.komi = komi
            self.komiAuto = komiAuto
            self.handicap = handicap
            self.disableAnalysis = disableAnalysis
            self.name = name
            self.rules = rules
            self.timeControl = timeControl
            self.minRank = minRank
            self.maxRank = maxRank
            self.initialState = initialState
            self.rengo = rengo
            self.rengoCasualMode = rengoCasualMode
            self.rengoAutoStart = rengoAutoStart
            self.rengoBlackTeam = rengoBlackTeam
            self.rengoWhiteTeam = rengoWhiteTeam
            self.rengoNominees = rengoNominees
            self.rengoParticipants = rengoParticipants
        }
        
        var width: Int
        var height: Int
        var ranked: Bool
        var isPrivate: Bool = false
        var komi: Double?
        var komiAuto: String?
        var handicap: Int
        var disableAnalysis: Bool
        var name: String
        var rules: OGSRule
        var timeControl: TimeControl
        var minRank: Int?
        var maxRank: Int?
        var initialState: OGSGame.InitialState?
        var rengo: Bool?
        var rengoCasualMode: Bool?
        var rengoAutoStart: Int?
        var rengoBlackTeam: [Int]?
        var rengoWhiteTeam: [Int]?
        var rengoNominees: [Int]?
        var rengoParticipants: [Int]?
        
        enum CodingKeys: String, CodingKey {
            case width
            case height
            case ranked
            case isPrivate = "private"
            case komi
            case komiAuto
            case handicap
            case disableAnalysis
            case name
            case rules
            case timeControlParameters
            
            case rengo
            case rengoCasualMode
            case rengoAutoStart
            
            // Encode only
            case initialState
            case pauseOnWeekends
            case timeControl
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
            ranked = try container.decode(Bool.self, forKey: .ranked)
            isPrivate = (try? container.decodeIfPresent(Bool.self, forKey: .isPrivate)) ?? false
            komi = try? container.decode(Double.self, forKey: .komi)
            komiAuto = try? container.decode(String.self, forKey: .komiAuto)
            disableAnalysis = try container.decode(Bool.self, forKey: .disableAnalysis)
            handicap = try container.decode(Int.self, forKey: .handicap)
            name = try container.decode(String.self, forKey: .name)
            rules = OGSRule(rawValue: try container.decode(String.self, forKey: .rules))!
            timeControl = try container.decode(TimeControl.self, forKey: .timeControlParameters)
            
            rengo = try? container.decodeIfPresent(Bool.self, forKey: .rengo) ?? false
            rengoCasualMode = try? container.decodeIfPresent(Bool.self, forKey: .rengoCasualMode) ?? false
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(name, forKey: .name)
            try container.encode(rules, forKey: .rules)
            try container.encode(ranked, forKey: .ranked)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(handicap, forKey: .handicap)
            if komiAuto == "automatic" {
                try container.encode(komi, forKey: .komi)
                try container.encode(komiAuto, forKey: .komiAuto)
            } else {
                if komi == rules.defaultKomi || komi == nil {
                    try container.encodeNil(forKey: .komi)
                    try container.encode("automatic", forKey: .komiAuto)
                } else {
                    try container.encode(komi, forKey: .komi)
                    try container.encode("custom", forKey: .komiAuto)
                }
            }
            
            try container.encode(disableAnalysis, forKey: .disableAnalysis)
            try container.encode(initialState, forKey: .initialState)
            try container.encode(isPrivate, forKey: .isPrivate)
            try container.encode(rengo ?? false, forKey: .rengo)
            try container.encode(rengoCasualMode ?? true, forKey: .rengoCasualMode)
            try container.encode(timeControl.timeControl, forKey: .timeControl)
            try container.encode(timeControl, forKey: .timeControlParameters)
            try container.encode(timeControl.pauseOnWeekends ?? true, forKey: .pauseOnWeekends)
        }
    }

    var challenger: OGSUser?
    var challenged: OGSUser?
    var challengerColor: StoneColor?
    var randomColor: Bool = false
    var game: OGSChallengeTemplate.GameDetail
    
    var initialized: Bool? = false
    var minRanking: Int? = nil
    var maxRanking: Int? = nil
    var agaRanked: Bool = false
    var rengoAutoStart: Int? = 0
    
    enum CodingKeys: String, CodingKey {
        case initialized
        case minRanking
        case maxRanking
        case challengerColor
        case game
        case rengoAutoStart
        case agaRanked
    }
    
    init(game: OGSChallengeTemplate.GameDetail) {
        self.game = game
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        initialized = try? container.decodeIfPresent(Bool.self, forKey: .initialized)
        minRanking = try? container.decodeIfPresent(Int.self, forKey: .minRanking)
        maxRanking = try? container.decodeIfPresent(Int.self, forKey: .maxRanking)
        rengoAutoStart = try? container.decodeIfPresent(Int.self, forKey: .rengoAutoStart)
        let challengerColorString = try container.decode(String.self, forKey: .challengerColor)
        if challengerColorString == "random" {
            randomColor = true
        }
        challengerColor = StoneColor(rawValue: challengerColorString)
        game = try container.decode(OGSChallengeTemplate.GameDetail.self, forKey: .game)
        game.minRank = minRanking
        game.maxRank = maxRanking
        game.rengoAutoStart = rengoAutoStart
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if randomColor {
            try container.encode("random", forKey: .challengerColor)
        } else {
            try container.encode(challengerColor?.rawValue ?? "automatic", forKey: .challengerColor)
        }
        if let maxRank = game.maxRank, let minRank = game.minRank {
            try container.encode(maxRank, forKey: .maxRanking)
            try container.encode(minRank, forKey: .minRanking)
        } else {
            try container.encode(1000, forKey: .maxRanking)
            try container.encode(-1000, forKey: .minRanking)
        }
        try container.encode(false, forKey: .initialized)
        try container.encode(game, forKey: .game)
        try container.encode(false, forKey: .agaRanked)
        try container.encode(rengoAutoStart ?? 0, forKey: .rengoAutoStart)
    }
}




class OGSChallengeSampleData {
    static var sampleChallenge: OGSDirectChallenge {
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
                "private": true,
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
        return try! decoder.decode(OGSDirectChallenge.self, from: data.data(using: .utf8)!)
    }
    static var sampleOpenChallenge: OGSSeekgraphChallenge {
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
        return try! decoder.decode(OGSSeekgraphChallenge.self, from: data.data(using: .utf8)!)
    }
    static var sampleRengoChallenge: OGSSeekgraphChallenge {
        let data = #"""
            {
              "challenge_id": 3366,
              "user_id": 1769,
              "username": "hakhoa4",
              "rank": 24.303382182144386,
              "pro": 0,
              "min_rank": -1000,
              "max_rank": 1000,
              "game_id": 11454,
              "name": "Rengo test",
              "ranked": false,
              "handicap": 0,
              "komi": null,
              "rules": "japanese",
              "width": 19,
              "height": 19,
              "challenger_color": "automatic",
              "disable_analysis": false,
              "time_control": "fischer",
              "time_control_parameters": {
                "system": "simple",
                "speed": "correspondence",
                "per_move": 172800,
                "pause_on_weekends": true,
                "time_control": "simple"
              },
              "time_per_move": 172800,
              "rengo": true,
              "rengo_auto_start": 4,
              "rengo_casual_mode": true,
              "rengo_nominees": [
                1526
              ],
              "rengo_black_team": [],
              "rengo_white_team": [
                1769
              ],
              "rengo_participants": [
                1526,
                1769
              ]
            }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(OGSSeekgraphChallenge.self, from: data.data(using: .utf8)!)
    }
    
    static var sampleChallengeTemplate: OGSChallengeTemplate {
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
        return try! decoder.decode(OGSChallengeTemplate.self, from: challengeTemplate.data(using: .utf8)!)
    }
}
