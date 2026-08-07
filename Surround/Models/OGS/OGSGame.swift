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

enum OGSRule: String, Codable, CaseIterable, Hashable {
    case chinese
    case aga
    case japanese
    case korean
    case ing
    case nz
    
    var fullName: String {
        switch self {
        case .chinese:
            return String(localized: "Chinese", comment: "rules name")
        case .aga:
            return String(localized: "AGA", comment: "rules name")
        case .japanese:
            return String(localized: "Japanese", comment: "rules name")
        case .korean:
            return String(localized: "Korean", comment: "rules name")
        case .ing:
            return String(localized: "Ing SST", comment: "rules name")
        case .nz:
            return String(localized: "New Zealand", comment: "rules name")
        }
    }
    
    var defaultKomi: Double {
        switch self {
        case .chinese:
            return 7.5
        case .aga:
            return 7.5
        case .japanese:
            return 6.5
        case .korean:
            return 6.5
        case .ing:
            return 7.5
        case .nz:
            return 7
        }
    }
}

struct OGSPlayerUpdate: Codable, Equatable {
    struct Players: Codable, Equatable {
        var black: Int
        var white: Int
    }
    struct RengoTeams: Codable, Equatable {
        var black: [Int]
        var white: [Int]

        subscript(color: StoneColor) -> [Int] {
            switch color {
            case .black:
                return self.black
            case .white:
                return self.white
            }
        }
    }
    
    var players: Players?
    var rengoTeams: RengoTeams
}

struct OGSMoveExtra: Codable {
    var playedBy: Int?
    var playerUpdate: OGSPlayerUpdate?
}

struct OGSMove: Decodable {
    var column: Int
    var row: Int
    var timedelta: Double?
    var edited: Bool?
    var extra: OGSMoveExtra?
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.column = try container.decode(Int.self)
        self.row = try container.decode(Int.self)
        if !container.isAtEnd {
            self.timedelta = try container.decodeIfPresent(Double.self)
        }
        if !container.isAtEnd {
            self.edited = try container.decodeIfPresent(Bool.self)
        }
        if !container.isAtEnd {
            self.extra = try container.decodeIfPresent(OGSMoveExtra.self)
        }
    }
    
    var move: Move {
        if column == -1 {
            return .pass
        } else {
            return .placeStone(row, column)
        }
    }
}

struct OGSUndoRequest: Decodable, Equatable {
    let moveNumber: Int
    let requestedBy: Int?
    let moveCount: Int

    init(moveNumber: Int, requestedBy: Int? = nil, moveCount: Int = 1) {
        self.moveNumber = moveNumber
        self.requestedBy = requestedBy
        self.moveCount = max(1, moveCount)
    }

    init?(payload: Any) {
        if let moveNumber = Self.integer(from: payload) {
            self.init(moveNumber: moveNumber)
            return
        }

        guard let payload = payload as? [String: Any],
              let moveNumberValue = payload["move_number"],
              let moveNumber = Self.integer(from: moveNumberValue) else {
            return nil
        }

        self.init(
            moveNumber: moveNumber,
            requestedBy: Self.strictInteger(from: payload["requested_by"]),
            moveCount: Self.strictInteger(from: payload["undo_move_count"]) ?? 1
        )
    }

    static func positiveMoveCount(from payload: Any?) -> Int? {
        guard let payload = payload as? [String: Any],
              let moveCount = strictInteger(from: payload["undo_move_count"]),
              moveCount > 0 else {
            return nil
        }
        return moveCount
    }

    private struct FlexibleCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let moveNumber = try? singleValueContainer.decode(Int.self) {
            self.init(moveNumber: moveNumber)
            return
        }
        if let string = try? singleValueContainer.decode(String.self),
           let moveNumber = Self.integer(from: string) {
            self.init(moveNumber: moveNumber)
            return
        }

        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        guard let moveNumber = Self.decodeInteger(
            from: container,
            keys: ["moveNumber", "move_number"],
            allowsNumericPrefix: true
        ) else {
            throw DecodingError.dataCorruptedError(
                in: singleValueContainer,
                debugDescription: "Undo request has no valid move number"
            )
        }

        let requestedBy = Self.decodeInteger(
            from: container,
            keys: ["requestedBy", "requested_by"]
        )
        let moveCount = Self.decodeInteger(
            from: container,
            keys: ["undoMoveCount", "undo_move_count"]
        ) ?? 1
        self.init(moveNumber: moveNumber, requestedBy: requestedBy, moveCount: moveCount)
    }

    private static func decodeInteger(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String],
        allowsNumericPrefix: Bool = false
    ) -> Int? {
        for keyName in keys {
            let key = FlexibleCodingKey(keyName)
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }
            if allowsNumericPrefix,
               let string = try? container.decode(String.self, forKey: key),
               let value = integer(from: string) {
                return value
            }
        }
        return nil
    }

    private static func strictInteger(from value: Any?) -> Int? {
        guard let value else {
            return nil
        }
        // JSON booleans bridge through NSNumber and otherwise cast to Int as 0/1.
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        return value as? Int
    }

    private static func integer(from value: Any) -> Int? {
        if let value = strictInteger(from: value) {
            return value
        }
        guard let value = value as? String else {
            return nil
        }

        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        var parsedValue = 0
        return scanner.scanInt(&parsedValue) ? parsedValue : nil
    }
}

struct OGSGame: Decodable {
    struct InitialState: Codable, Hashable {
        var black: String
        var white: String
    }
    
    struct Players: Codable {
        var black: OGSUser
        var white: OGSUser
    }
    
    struct RengoTeams: Codable {
        var black: [OGSUser]
        var white: [OGSUser]
        
        subscript(color: StoneColor) -> [OGSUser] {
            switch color {
            case .black:
                return self.black
            case .white:
                return self.white
            }
        }
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
    // The REST payload declares this required, but the Goban engine config
    // marks it optional, so game payloads may omit it. Every official client
    // read treats absence as public.
    var `private`: Bool?
    var rules: OGSRule
    var initialPlayer: StoneColor
    var initialState: InitialState
    var komi: Double

    var moves: [OGSMove]
    var players: Players
    var playerPool: [Int: OGSUser]?
    
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
    
    var undoRequested: OGSUndoRequest?
    var phase: OGSGamePhase
    
    var tournamentId: Int?
    var ladderId: Int?
    
    var rengo: Bool?
    var rengoTeams: RengoTeams?
    var rengoCasualMode: Bool?
}
