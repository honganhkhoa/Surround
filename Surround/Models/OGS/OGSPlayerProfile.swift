//
//  OGSPlayerProfile.swift
//  Surround
//

import Foundation

/// Profile-only fields stay separate from the lightweight users shared by games.
struct OGSPlayerProfile: Decodable, Identifiable {
    let user: OGSUser
    let about: String?
    let registrationDate: Date?
    /// Missing or malformed sections stay unavailable instead of appearing empty.
    let activeGames: [OGSProfileActiveGame]?
    let versus: OGSProfileVersus?

    var id: Int { user.id }

    init(
        user: OGSUser,
        about: String? = nil,
        registrationDate: Date? = nil,
        activeGames: [OGSProfileActiveGame]? = nil,
        versus: OGSProfileVersus? = nil
    ) {
        self.user = user
        self.about = about
        self.registrationDate = registrationDate
        self.activeGames = activeGames
        self.versus = versus
    }

    private enum CodingKeys: String, CodingKey {
        case user, activeGames, vs
    }

    private enum UserDetailsKeys: String, CodingKey {
        case about, registrationDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(OGSUser.self, forKey: .user)
        guard user.id > 0,
              !user.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .user,
                in: container,
                debugDescription: "A player profile must have a positive ID and a username."
            )
        }

        let details = try container.nestedContainer(
            keyedBy: UserDetailsKeys.self,
            forKey: .user
        )
        about = try? details.decodeIfPresent(String.self, forKey: .about)
        registrationDate = (try? details.decodeIfPresent(String.self, forKey: .registrationDate))
            .flatMap(Self.date(from:))
        activeGames = try? container.decodeIfPresent([OGSProfileActiveGame].self, forKey: .activeGames)
        versus = try? container.decodeIfPresent(OGSProfileVersus.self, forKey: .vs)
    }

    fileprivate static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// A profile's active-game wrapper contains the same full game data as an overview.
struct OGSProfileActiveGame: Decodable, Identifiable {
    let id: Int
    let gameData: OGSGame

    init(id: Int, gameData: OGSGame) {
        self.id = id
        self.gameData = gameData
    }

    init(gameData: OGSGame) {
        self.init(id: gameData.gameId, gameData: gameData)
    }

    private enum CodingKeys: String, CodingKey {
        case id, json
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        gameData = try container.decode(OGSGame.self, forKey: .json)
        guard id > 0, gameData.gameId == id else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "An active game must identify the game in its payload."
            )
        }
    }
}

/// OGS supplies these totals and outcomes from the authenticated viewer's perspective.
struct OGSProfileVersus: Decodable, Equatable {
    let wins: Int
    let losses: Int
    let draws: Int
    let history: [OGSProfileVersusGame]

    var totalGames: Int { wins + losses + draws }

    init(wins: Int, losses: Int, draws: Int, history: [OGSProfileVersusGame] = []) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case wins, losses, draws, history
    }

    private struct RecordKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private struct HistoryEntry: Decodable {
        let game: OGSProfileVersusGame?

        init(from decoder: Decoder) {
            game = try? OGSProfileVersusGame(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        // OGS can represent an empty matchup with {}. Only a truly empty
        // object means zero; unknown-only objects and partial totals stay invalid.
        if try decoder.container(keyedBy: RecordKey.self).allKeys.isEmpty {
            wins = 0
            losses = 0
            draws = 0
            history = []
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wins = try container.decode(Int.self, forKey: .wins)
        losses = try container.decode(Int.self, forKey: .losses)
        draws = try container.decode(Int.self, forKey: .draws)
        let subtotal = wins.addingReportingOverflow(losses)
        guard wins >= 0, losses >= 0, draws >= 0,
              !subtotal.overflow,
              !subtotal.partialValue.addingReportingOverflow(draws).overflow else {
            throw DecodingError.dataCorruptedError(
                forKey: .wins,
                in: container,
                debugDescription: "Head-to-head totals must be nonnegative counts."
            )
        }
        // A damaged recent-history item must not discard valid server totals.
        history = (try? container.decode([HistoryEntry].self, forKey: .history))?
            .compactMap(\.game) ?? []
    }
}

struct OGSProfileVersusGame: Decodable, Equatable {
    enum Result: Equatable {
        case win, loss, draw, unknown
    }

    let gameID: Int
    let result: Result
    let date: Date?

    init(gameID: Int, result: Result, date: Date? = nil) {
        self.gameID = gameID
        self.result = result
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case game, state, date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decode(Int.self, forKey: .game)
        guard gameID > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .game,
                in: container,
                debugDescription: "A head-to-head game must have a positive ID."
            )
        }
        switch try? container.decode(String.self, forKey: .state) {
        case "W": result = .win
        case "L": result = .loss
        case "D": result = .draw
        default: result = .unknown
        }
        date = (try? container.decode(String.self, forKey: .date))
            .flatMap(OGSPlayerProfile.date(from:))
    }
}
