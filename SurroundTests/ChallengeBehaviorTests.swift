//
//  ChallengeBehaviorTests.swift
//  SurroundTests
//

import XCTest
import DictionaryCoding

final class ChallengeBehaviorTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    func testChallengeTemplateEncodesExactCreationContract() throws {
        var challenge = OGSChallengeTemplate(game: .init(
            width: 5,
            height: 5,
            ranked: false,
            isPrivate: true,
            komi: 5.5,
            handicap: 0,
            disableAnalysis: true,
            name: "surround-e2e-contract",
            rules: .japanese,
            timeControl: TimeControlSystem.Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300).timeControlObject,
            minRank: 10,
            maxRank: 30,
            rengo: true,
            rengoCasualMode: false
        ))
        challenge.challengerColor = .black
        challenge.rengoAutoStart = 4

        let data = try encoder.encode(challenge)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let game = try XCTUnwrap(object["game"] as? [String: Any])
        let parameters = try XCTUnwrap(game["time_control_parameters"] as? [String: Any])

        XCTAssertEqual(object["challenger_color"] as? String, "black")
        XCTAssertEqual(object["min_ranking"] as? Int, 10)
        XCTAssertEqual(object["max_ranking"] as? Int, 30)
        XCTAssertEqual(object["initialized"] as? Bool, false)
        XCTAssertEqual(object["aga_ranked"] as? Bool, false)
        XCTAssertEqual(object["rengo_auto_start"] as? Int, 4)

        XCTAssertEqual(game["name"] as? String, "surround-e2e-contract")
        XCTAssertEqual(game["rules"] as? String, "japanese")
        XCTAssertEqual(game["width"] as? Int, 5)
        XCTAssertEqual(game["height"] as? Int, 5)
        XCTAssertEqual(game["private"] as? Bool, true)
        XCTAssertEqual(game["ranked"] as? Bool, false)
        XCTAssertEqual(game["disable_analysis"] as? Bool, true)
        XCTAssertEqual(game["komi"] as? Double, 5.5)
        XCTAssertEqual(game["komi_auto"] as? String, "custom")
        XCTAssertEqual(game["rengo"] as? Bool, true)
        XCTAssertEqual(game["rengo_casual_mode"] as? Bool, false)
        XCTAssertEqual(game["time_control"] as? String, "fischer")
        XCTAssertEqual(game["pause_on_weekends"] as? Bool, true)

        XCTAssertEqual(parameters["time_control"] as? String, "fischer")
        XCTAssertEqual(parameters["system"] as? String, "fischer")
        XCTAssertEqual(parameters["initial_time"] as? Int, 120)
        XCTAssertEqual(parameters["time_increment"] as? Int, 30)
        XCTAssertEqual(parameters["max_time"] as? Int, 300)
        XCTAssertEqual(parameters["speed"] as? String, "live")
    }

    func testDefaultKomiEncodesAsAutomatic() throws {
        let challenge = OGSChallengeTemplate(game: .init(
            width: 9,
            height: 9,
            ranked: false,
            komi: OGSRule.chinese.defaultKomi,
            handicap: 0,
            disableAnalysis: false,
            name: "automatic-komi",
            rules: .chinese,
            timeControl: TimeControlSystem.Simple(perMove: 60).timeControlObject
        ))

        let data = try encoder.encode(challenge)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let game = try XCTUnwrap(object["game"] as? [String: Any])

        XCTAssertTrue(game["komi"] is NSNull)
        XCTAssertEqual(game["komi_auto"] as? String, "automatic")
        XCTAssertEqual(object["min_ranking"] as? Int, -1000)
        XCTAssertEqual(object["max_ranking"] as? Int, 1000)
        XCTAssertEqual(object["challenger_color"] as? String, "automatic")
    }

    func testEligibilityRejectsCreatorRengoParticipantsAndRanksOutsideLimits() {
        var challenge = OGSChallengeTemplate(game: .init(
            width: 19,
            height: 19,
            ranked: false,
            handicap: 0,
            disableAnalysis: false,
            name: "eligibility",
            rules: .japanese,
            timeControl: TimeControlSystem.Simple(perMove: 60).timeControlObject,
            minRank: 20,
            maxRank: 30,
            rengo: true,
            rengoParticipants: [3]
        ))
        challenge.challenger = ratedUser(id: 1, rank: 25, explicitRank: 25)

        XCTAssertFalse(challenge.isUserEligible(user: ratedUser(id: 1, rank: 25)))
        XCTAssertFalse(challenge.isUserEligible(user: ratedUser(id: 3, rank: 25)))
        XCTAssertFalse(challenge.isUserEligible(user: ratedUser(id: 4, rank: 19)))
        XCTAssertFalse(challenge.isUserEligible(user: ratedUser(id: 5, rank: 31)))
        XCTAssertTrue(challenge.isUserEligible(user: ratedUser(id: 6, rank: 25)))

        challenge.game.ranked = true
        XCTAssertFalse(challenge.isUserEligible(user: ratedUser(id: 7, rank: 15)))
    }

    func testRengoReadinessRequiresBothColorsAndAtLeastThreePlayers() {
        var detail = OGSChallengeTemplate.GameDetail(
            width: 19,
            height: 19,
            ranked: false,
            handicap: 0,
            disableAnalysis: false,
            name: "rengo",
            rules: .japanese,
            timeControl: TimeControlSystem.Simple(perMove: 60).timeControlObject,
            rengo: true,
            rengoBlackTeam: [1],
            rengoWhiteTeam: [2]
        )

        XCTAssertFalse(detail.rengoReadyToStart)

        detail.rengoBlackTeam = [1, 3]
        XCTAssertTrue(detail.rengoReadyToStart)

        detail.rengoWhiteTeam = []
        XCTAssertFalse(detail.rengoReadyToStart)

        detail.rengo = false
        detail.rengoWhiteTeam = [2, 4]
        XCTAssertFalse(detail.rengoReadyToStart)
    }

    func testUnusualChallengeFlagsEachRiskFactor() {
        var challenge = OGSChallengeTemplate(game: .init(
            width: 19,
            height: 19,
            ranked: false,
            komi: OGSRule.japanese.defaultKomi,
            handicap: 0,
            disableAnalysis: false,
            name: "standard",
            rules: .japanese,
            timeControl: TimeControlSystem.Simple(perMove: 60).timeControlObject
        ))

        XCTAssertFalse(challenge.hasHandicap)
        XCTAssertFalse(challenge.useCustomKomi)
        XCTAssertFalse(challenge.unusualBoardSize)
        XCTAssertFalse(challenge.isUnusual)

        challenge.game.handicap = 2
        XCTAssertTrue(challenge.hasHandicap)
        XCTAssertTrue(challenge.isUnusual)

        challenge.game.handicap = 0
        challenge.game.komi = 5.5
        XCTAssertTrue(challenge.useCustomKomi)

        challenge.game.komi = OGSRule.japanese.defaultKomi
        challenge.game.width = 5
        challenge.game.height = 5
        XCTAssertTrue(challenge.unusualBoardSize)

        challenge.game.width = 19
        challenge.game.height = 19
        challenge.game.timeControl = TimeControlSystem.Simple(perMove: 3).timeControlObject
        XCTAssertTrue(challenge.isUnusual)
    }

    func testRematchCopiesFinishedGameSettingsAndOpponent() throws {
        let game = try makeRematchGame(isPrivate: true)
        let user = try XCTUnwrap(game.whitePlayer)
        let service = OGSService.previewInstance(user: user)
        game.ogs = service

        let rematch = try XCTUnwrap(OGSChallengeTemplate.rematch(for: game))
        let gameData = try XCTUnwrap(game.gameData)

        XCTAssertEqual(rematch.challenger?.id, user.id)
        XCTAssertEqual(rematch.challenged?.id, game.blackPlayer?.id)
        XCTAssertEqual(rematch.challengerColor, .white)
        XCTAssertEqual(rematch.game.width, gameData.width)
        XCTAssertEqual(rematch.game.height, gameData.height)
        XCTAssertEqual(rematch.game.ranked, gameData.ranked)
        XCTAssertEqual(rematch.game.isPrivate, true)
        XCTAssertEqual(rematch.game.handicap, gameData.handicap)
        XCTAssertEqual(rematch.game.disableAnalysis, gameData.disableAnalysis)
        XCTAssertEqual(rematch.game.rules, gameData.rules)
        XCTAssertEqual(rematch.game.komi, gameData.komi)
        XCTAssertEqual(rematch.game.timeControl, gameData.timeControl)
        XCTAssertNil(rematch.game.initialState)
        XCTAssertEqual(rematch.game.rengo, false)
        XCTAssertEqual(rematch.game.name, defaultGameName)
    }

    func testRematchRequiresFinishedNonRengoParticipantGame() throws {
        let game = try makeRematchGame()
        let participant = try XCTUnwrap(game.whitePlayer)
        var service = OGSService.previewInstance(user: participant)
        game.ogs = service

        XCTAssertNotNil(OGSChallengeTemplate.rematch(for: game))

        game.gamePhase = .play
        XCTAssertNil(OGSChallengeTemplate.rematch(for: game))

        game.gamePhase = .finished
        game.gameData?.rengo = true
        XCTAssertNil(OGSChallengeTemplate.rematch(for: game))

        game.gameData?.rengo = false
        service = OGSService.previewInstance(
            user: OGSUser(username: "spectator", id: -1)
        )
        game.ogs = service
        XCTAssertNil(OGSChallengeTemplate.rematch(for: game))

        game.gameData = nil
        XCTAssertNil(OGSChallengeTemplate.rematch(for: game))
    }

    /// Game payloads may omit `private`; the official client treats absence as
    /// public, so a missing key must still offer a rematch rather than
    /// suppressing the action.
    func testRematchTreatsMissingGamePrivacyAsPublic() throws {
        let game = try makeRematchGame()
        let participant = try XCTUnwrap(game.whitePlayer)
        game.ogs = OGSService.previewInstance(user: participant)

        XCTAssertNil(game.gameData?.private)
        XCTAssertEqual(
            OGSChallengeTemplate.rematch(for: game)?.game.isPrivate,
            false
        )

        let publicGame = try makeRematchGame(isPrivate: false)
        publicGame.ogs = OGSService.previewInstance(
            user: try XCTUnwrap(publicGame.whitePlayer)
        )
        XCTAssertEqual(
            OGSChallengeTemplate.rematch(for: publicGame)?.game.isPrivate,
            false
        )
    }

    /// Passing `nil` for `isPrivate` omits the key entirely, matching the
    /// payload OGS sends for a public game.
    private func makeRematchGame(isPrivate: Bool? = nil) throws -> Game {
        var object: [String: Any] = [
            "allow_ko": false,
            "allow_self_capture": false,
            "allow_superko": true,
            "automatic_stone_removal": false,
            "white_must_pass_last": false,
            "black_player_id": 1,
            "white_player_id": 2,
            "disable_analysis": true,
            "free_handicap_placement": false,
            "width": 13,
            "height": 13,
            "game_id": 42,
            "game_name": "Original game name",
            "handicap": 2,
            "ranked": false,
            "rules": "chinese",
            "initial_player": "black",
            "initial_state": ["black": "aa", "white": ""],
            "komi": 5.5,
            "moves": [[Int]](),
            "players": [
                "black": ["id": 1, "username": "black-player"],
                "white": ["id": 2, "username": "white-player"],
            ],
            "time_control": [
                "system": "fischer",
                "time_control": "fischer",
                "initial_time": 120,
                "time_increment": 30,
                "max_time": 300,
                "speed": "live",
                "pause_on_weekends": false,
            ],
            "clock": [
                "black_player_id": 1,
                "white_player_id": 2,
                "current_player": 1,
                "last_move": 0,
                "black_time": ["thinking_time": 120],
                "white_time": ["thinking_time": 120],
            ],
            "outcome": "Resignation",
            "winner": 1,
            "score_handicap": false,
            "score_passes": true,
            "score_prisoners": true,
            "score_stones": false,
            "score_territory": true,
            "score_territory_in_seki": false,
            "strict_seki_mode": false,
            "aga_handicap_scoring": false,
            "phase": "finished",
            "rengo": false,
        ]
        if let isPrivate {
            object["private"] = isPrivate
        }
        // Both production paths (the `gamedata` socket event and the REST game
        // detail) decode through DictionaryDecoder, so decode the same way.
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Game(ogsGame: try decoder.decode(OGSGame.self, from: object))
    }

    private func ratedUser(id: Int, rank: Double, explicitRank: Double? = nil) -> OGSUser {
        OGSUser(
            username: "player-\(id)",
            id: id,
            rank: explicitRank,
            ratings: OGSRating(ratingByCategory: [
                .overall: OGSCategoryRating(
                    rating: RankUtils.rating(fromRank: rank),
                    deviation: 100,
                    volatility: 0.06
                )
            ])
        )
    }
}
