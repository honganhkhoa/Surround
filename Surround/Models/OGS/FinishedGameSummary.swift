import Foundation

/// Listing metadata remains useful even when a game's replay is unavailable.
struct FinishedGameSummary: Decodable, Equatable {
    enum Result: Equatable {
        case win, loss, draw, annulled, unknown
    }

    let gameID: Int
    let blackPlayerID: Int
    let whitePlayerID: Int
    let width: Int
    let height: Int
    let outcome: String?
    let blackLost: Bool?
    let whiteLost: Bool?
    let annulled: Bool?
    let name: String?
    let ended: Date?
    let handicap: Int?
    let komi: Double?
    let rules: OGSRule?
    let rengo: Bool?
    let rengoBlackTeamIDs: [Int]?
    let rengoWhiteTeamIDs: [Int]?
    let ranked: Bool?

    init(
        gameID: Int, blackPlayerID: Int, whitePlayerID: Int, width: Int, height: Int,
        outcome: String? = nil, blackLost: Bool? = nil, whiteLost: Bool? = nil,
        annulled: Bool? = nil, name: String? = nil, ended: Date? = nil,
        handicap: Int? = nil, komi: Double? = nil, rules: OGSRule? = nil,
        rengo: Bool? = nil, rengoBlackTeamIDs: [Int]? = nil,
        rengoWhiteTeamIDs: [Int]? = nil, ranked: Bool? = nil
    ) {
        self.gameID = gameID
        self.blackPlayerID = blackPlayerID
        self.whitePlayerID = whitePlayerID
        self.width = width
        self.height = height
        self.outcome = outcome
        self.blackLost = blackLost
        self.whiteLost = whiteLost
        self.annulled = annulled
        self.name = name
        self.ended = ended
        self.handicap = handicap
        self.komi = komi
        self.rules = rules
        self.rengo = rengo
        self.rengoBlackTeamIDs = rengoBlackTeamIDs
        self.rengoWhiteTeamIDs = rengoWhiteTeamIDs
        self.ranked = ranked
    }

    private enum CodingKeys: String, CodingKey {
        case id, players, width, height, outcome, blackLost, whiteLost, annulled
        case name, ended, handicap, komi, rules, rengo, rengoBlackTeam, rengoWhiteTeam, ranked
    }

    private enum PlayerKeys: String, CodingKey {
        case black, white
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(Int.self, forKey: .id)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        let players = try container.nestedContainer(keyedBy: PlayerKeys.self, forKey: .players)
        let black = try players.decode(OGSUser.self, forKey: .black)
        let white = try players.decode(OGSUser.self, forKey: .white)
        guard gameID > 0, width > 0, height > 0,
              black.id > 0, white.id > 0, black.id != white.id,
              !black.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !white.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "A history summary requires valid game dimensions and players."
            )
        }
        blackPlayerID = black.id
        whitePlayerID = white.id
        outcome = try? container.decodeIfPresent(String.self, forKey: .outcome)
        blackLost = try? container.decodeIfPresent(Bool.self, forKey: .blackLost)
        whiteLost = try? container.decodeIfPresent(Bool.self, forKey: .whiteLost)
        annulled = try? container.decodeIfPresent(Bool.self, forKey: .annulled)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        ended = (try? container.decodeIfPresent(String.self, forKey: .ended)).flatMap(Self.date(from:))
        handicap = (try? container.decodeIfPresent(Int.self, forKey: .handicap)).flatMap { $0 >= 0 ? $0 : nil }
        if let number = try? container.decode(Double.self, forKey: .komi), number.isFinite {
            komi = number
        } else if let text = try? container.decode(String.self, forKey: .komi),
                  let number = Double(text), number.isFinite {
            komi = number
        } else {
            komi = nil
        }
        rules = try? container.decodeIfPresent(OGSRule.self, forKey: .rules)
        rengo = try? container.decodeIfPresent(Bool.self, forKey: .rengo)
        rengoBlackTeamIDs = Self.validTeam(try? container.decodeIfPresent([Int].self, forKey: .rengoBlackTeam))
        rengoWhiteTeamIDs = Self.validTeam(try? container.decodeIfPresent([Int].self, forKey: .rengoWhiteTeam))
        ranked = try? container.decodeIfPresent(Bool.self, forKey: .ranked)
    }

    var winnerColor: StoneColor? {
        guard annulled != true, !isCancellation,
              let blackLost, let whiteLost, blackLost != whiteLost else {
            return nil
        }
        return blackLost ? .white : .black
    }

    var isDraw: Bool {
        guard annulled != true, blackLost == false, whiteLost == false,
              let outcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        if ["draw", "jigo", "tie"].contains(outcome) { return true }
        let parts = outcome.split(separator: " ")
        return parts.count == 2 && ["point", "points"].contains(String(parts[1]))
            && Double(parts[0]) == 0
    }

    func stoneColor(ofPlayerWithID playerID: Int) -> StoneColor? {
        if rengo == true {
            let blackMember = rengoBlackTeamIDs?.contains(playerID) == true
            let whiteMember = rengoWhiteTeamIDs?.contains(playerID) == true
            if blackMember && whiteMember { return nil }
            if blackMember { return .black }
            if whiteMember { return .white }
        }
        if playerID == blackPlayerID { return .black }
        if playerID == whitePlayerID { return .white }
        return nil
    }

    func result(for playerID: Int) -> Result {
        if annulled == true { return .annulled }
        if isCancellation { return .unknown }
        guard let color = stoneColor(ofPlayerWithID: playerID) else { return .unknown }
        if let winnerColor { return winnerColor == color ? .win : .loss }
        return isDraw ? .draw : .unknown
    }

    private var isCancellation: Bool {
        outcome?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cancellation"
    }

    private static func validTeam(_ team: [Int]?) -> [Int]? {
        guard let team, team.allSatisfy({ $0 > 0 }), Set(team).count == team.count else {
            return nil
        }
        return team
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum FinishedGameDetailState: Equatable {
    case notRequested, loading, ready, unavailable
}
