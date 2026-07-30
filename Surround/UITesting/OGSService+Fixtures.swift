//
//  OGSService+Fixtures.swift
//  Surround
//
//  Preview and deterministic UI-test fixtures for OGSService.
//

import Foundation

#if DEBUG && MAIN_APP
import WidgetKit

private struct AppStoreScreenshotPublicClockFixture {
    let timeControl: TimeControlSystem
    let currentPlayerTime: ThinkingTime
    let opponentTime: ThinkingTime

    private init(
        timeControl: TimeControlSystem,
        currentPlayerTime: ThinkingTime,
        opponentTime: ThinkingTime
    ) {
        precondition(
            (currentPlayerTime.timeLeft ?? 0) > 0
                && (opponentTime.timeLeft ?? 0) > 0,
            "Public-game screenshot clocks must show playable time remaining."
        )
        self.timeControl = timeControl
        self.currentPlayerTime = currentPlayerTime
        self.opponentTime = opponentTime
    }

    static func byoYomi(
        mainTime: Int,
        periods: Int,
        periodTime: Int,
        currentMainTimeLeft: Int,
        currentPeriodsLeft: Int,
        currentPeriodTimeLeft: Int,
        opponentMainTimeLeft: Int,
        opponentPeriodsLeft: Int,
        opponentPeriodTimeLeft: Int
    ) -> Self {
        precondition(mainTime >= 0 && periods > 0 && periodTime > 0)

        func thinkingTime(
            mainTimeLeft: Int,
            periodsLeft: Int,
            periodTimeLeft: Int
        ) -> ThinkingTime {
            precondition(
                mainTimeLeft >= 0
                    && mainTimeLeft <= mainTime
                    && periodsLeft > 0
                    && periodsLeft <= periods
                    && periodTimeLeft > 0
                    && periodTimeLeft <= periodTime
            )
            return ThinkingTime(
                thinkingTime: Double(mainTimeLeft),
                thinkingTimeLeft: Double(mainTimeLeft),
                periods: mainTimeLeft > 0 ? periods : periodsLeft,
                periodsLeft: periodsLeft,
                periodTime: Double(periodTime),
                periodTimeLeft: Double(periodTimeLeft)
            )
        }

        return Self(
            timeControl: .ByoYomi(
                mainTime: mainTime,
                periods: periods,
                periodTime: periodTime
            ),
            currentPlayerTime: thinkingTime(
                mainTimeLeft: currentMainTimeLeft,
                periodsLeft: currentPeriodsLeft,
                periodTimeLeft: currentPeriodTimeLeft
            ),
            opponentTime: thinkingTime(
                mainTimeLeft: opponentMainTimeLeft,
                periodsLeft: opponentPeriodsLeft,
                periodTimeLeft: opponentPeriodTimeLeft
            )
        )
    }

    static func fischer(
        initialTime: Int,
        timeIncrement: Int,
        maxTime: Int,
        currentTimeLeft: Int,
        opponentTimeLeft: Int
    ) -> Self {
        precondition(
            initialTime > 0
                && timeIncrement > 0
                && maxTime >= initialTime
                && currentTimeLeft > 0
                && currentTimeLeft <= maxTime
                && opponentTimeLeft > 0
                && opponentTimeLeft <= maxTime
        )
        return Self(
            timeControl: .Fischer(
                initialTime: initialTime,
                timeIncrement: timeIncrement,
                maxTime: maxTime
            ),
            currentPlayerTime: ThinkingTime(
                thinkingTime: Double(currentTimeLeft),
                thinkingTimeLeft: Double(currentTimeLeft)
            ),
            opponentTime: ThinkingTime(
                thinkingTime: Double(opponentTimeLeft),
                thinkingTimeLeft: Double(opponentTimeLeft)
            )
        )
    }

    static func canadian(
        mainTime: Int,
        periodTime: Int,
        stonesPerPeriod: Int,
        currentMainTimeLeft: Int,
        currentBlockTimeLeft: Int,
        currentMovesLeft: Int,
        opponentMainTimeLeft: Int,
        opponentBlockTimeLeft: Int,
        opponentMovesLeft: Int
    ) -> Self {
        precondition(mainTime >= 0 && periodTime > 0 && stonesPerPeriod > 0)

        func thinkingTime(
            mainTimeLeft: Int,
            blockTimeLeft: Int,
            movesLeft: Int
        ) -> ThinkingTime {
            precondition(
                mainTimeLeft >= 0
                    && mainTimeLeft <= mainTime
                    && blockTimeLeft > 0
                    && blockTimeLeft <= periodTime
                    && movesLeft > 0
                    && movesLeft <= stonesPerPeriod
            )
            return ThinkingTime(
                thinkingTime: Double(mainTimeLeft),
                thinkingTimeLeft: Double(mainTimeLeft),
                movesLeft: movesLeft,
                blockTime: Double(blockTimeLeft),
                blockTimeLeft: Double(blockTimeLeft)
            )
        }

        return Self(
            timeControl: .Canadian(
                mainTime: mainTime,
                periodTime: periodTime,
                stonesPerPeriod: stonesPerPeriod
            ),
            currentPlayerTime: thinkingTime(
                mainTimeLeft: currentMainTimeLeft,
                blockTimeLeft: currentBlockTimeLeft,
                movesLeft: currentMovesLeft
            ),
            opponentTime: thinkingTime(
                mainTimeLeft: opponentMainTimeLeft,
                blockTimeLeft: opponentBlockTimeLeft,
                movesLeft: opponentMovesLeft
            )
        )
    }

    static func simple(
        perMove: Int,
        currentTimeLeft: Int
    ) -> Self {
        precondition(
            perMove > 0
                && currentTimeLeft > 0
                && currentTimeLeft <= perMove
        )
        return Self(
            timeControl: .Simple(perMove: perMove),
            currentPlayerTime: ThinkingTime(
                thinkingTime: Double(currentTimeLeft),
                thinkingTimeLeft: Double(currentTimeLeft)
            ),
            opponentTime: ThinkingTime(
                thinkingTime: Double(perMove),
                thinkingTimeLeft: Double(perMove)
            )
        )
    }

    static func absolute(
        totalTime: Int,
        currentTimeLeft: Int,
        opponentTimeLeft: Int
    ) -> Self {
        precondition(
            totalTime > 0
                && currentTimeLeft > 0
                && currentTimeLeft <= totalTime
                && opponentTimeLeft > 0
                && opponentTimeLeft <= totalTime
        )
        return Self(
            timeControl: .Absolute(totalTime: totalTime),
            currentPlayerTime: ThinkingTime(
                thinkingTime: Double(currentTimeLeft),
                thinkingTimeLeft: Double(currentTimeLeft)
            ),
            opponentTime: ThinkingTime(
                thinkingTime: Double(opponentTimeLeft),
                thinkingTimeLeft: Double(opponentTimeLeft)
            )
        )
    }
}

private struct AppStoreScreenshotActiveClockFixture {
    let daysPerMove: Int
    let blackTimeRemaining: Int
    let whiteTimeRemaining: Int

    var secondsPerMove: Int {
        daysPerMove * 86_400
    }

    init(
        daysPerMove: Int,
        blackTimeRemaining: Int,
        whiteTimeRemaining: Int
    ) {
        precondition(daysPerMove > 0)
        let secondsPerMove = daysPerMove * 86_400
        precondition(
            (1..<secondsPerMove).contains(blackTimeRemaining)
                && (1..<secondsPerMove).contains(whiteTimeRemaining),
            "Active-game clocks must have believable partial time remaining."
        )
        precondition(
            blackTimeRemaining != whiteTimeRemaining
                && !blackTimeRemaining.isMultiple(of: 3_600)
                && !whiteTimeRemaining.isMultiple(of: 3_600),
            "Active-game screenshot clocks must use distinct, non-round times."
        )
        self.daysPerMove = daysPerMove
        self.blackTimeRemaining = blackTimeRemaining
        self.whiteTimeRemaining = whiteTimeRemaining
    }

    func timeRemaining(for color: StoneColor) -> Int {
        color == .black ? blackTimeRemaining : whiteTimeRemaining
    }
}

/// Public OGS game data used only by the deterministic App Store screenshot
/// journey. The coordinate sequences come from `/api/v1/games/{id}/`; keeping
/// them in the app bundle makes screenshot capture fully offline and stable.
private struct AppStoreScreenshotProfileGame {
    let id: Int
    let sourceMoveCount: Int
    let gameName: String
    let blackPlayer: OGSUser
    let whitePlayer: OGSUser
    let outcome: String
    let winnerID: Int
    let rules: OGSRule
    let komi: Double
    let handicap: Int
    private let movesJSON: String

    init(
        id: Int,
        sourceMoveCount: Int,
        gameName: String,
        blackPlayer: OGSUser,
        whitePlayer: OGSUser,
        outcome: String,
        winnerID: Int,
        rules: OGSRule = .japanese,
        komi: Double = 6.5,
        handicap: Int = 0,
        movesJSON: String
    ) {
        self.id = id
        self.sourceMoveCount = sourceMoveCount
        self.gameName = gameName
        self.blackPlayer = blackPlayer
        self.whitePlayer = whitePlayer
        self.outcome = outcome
        self.winnerID = winnerID
        self.rules = rules
        self.komi = komi
        self.handicap = handicap
        self.movesJSON = movesJSON

        if gameName.contains(" vs ") {
            precondition(
                gameName.hasSuffix(
                    "(\(whitePlayer.username) vs \(blackPlayer.username))"
                ),
                "Fixture matchup titles must use their generated player usernames."
            )
        }
    }

    var moves: [OGSMove] {
        let moves = try! JSONDecoder().decode(
            [OGSMove].self,
            from: Data(movesJSON.utf8)
        )
        precondition(
            sourceMoveCount > 100 && moves.count <= sourceMoveCount,
            "App Store fixtures must come from profile games with more than 100 moves."
        )
        return moves
    }

    func widgetGameJSON(
        clock: AppStoreScreenshotActiveClockFixture,
        currentPlayerID: Int,
        now: Date
    ) -> [String: Any] {
        precondition(
            currentPlayerID == blackPlayer.id
                || currentPlayerID == whitePlayer.id
        )

        guard let templateURL = Bundle.main.url(
            forResource: "game-26268404",
            withExtension: "json"
        ),
        let templateData = try? Data(contentsOf: templateURL),
        var gameJSON = try? JSONSerialization.jsonObject(
            with: templateData
        ) as? [String: Any] else {
            preconditionFailure(
                "The bundled widget screenshot template could not be loaded."
            )
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        func jsonObject<Value: Encodable>(
            _ value: Value
        ) -> Any {
            let data = try! encoder.encode(value)
            return try! JSONSerialization.jsonObject(with: data)
        }

        gameJSON["game_id"] = id
        gameJSON["game_name"] = gameName
        gameJSON["black_player_id"] = blackPlayer.id
        gameJSON["white_player_id"] = whitePlayer.id
        gameJSON["players"] = jsonObject(
            OGSGame.Players(
                black: blackPlayer,
                white: whitePlayer
            )
        )
        gameJSON["width"] = 19
        gameJSON["height"] = 19
        gameJSON["handicap"] = handicap
        gameJSON["initial_player"] = "black"
        gameJSON["initial_state"] = [
            "black": "",
            "white": "",
        ]
        gameJSON["komi"] = komi
        gameJSON["ranked"] = true
        gameJSON["rules"] = rules.rawValue
        gameJSON["moves"] = try! JSONSerialization.jsonObject(
            with: Data(movesJSON.utf8)
        )
        gameJSON["phase"] = "play"
        gameJSON.removeValue(forKey: "outcome")
        gameJSON.removeValue(forKey: "winner")
        gameJSON.removeValue(forKey: "removed")
        gameJSON.removeValue(forKey: "score")
        gameJSON.removeValue(forKey: "undo_requested")
        gameJSON.removeValue(forKey: "auto_scoring_done")

        gameJSON["time_control"] = jsonObject(
            TimeControlSystem
                .Simple(perMove: clock.secondsPerMove)
                .timeControlObject
        )

        let nowMilliseconds = now.timeIntervalSince1970 * 1_000
        let currentPlayerColor: StoneColor =
            currentPlayerID == blackPlayer.id ? .black : .white
        let currentPlayerTimeRemaining = clock.timeRemaining(
            for: currentPlayerColor
        )
        gameJSON["clock"] = [
            "game_id": id,
            "current_player": currentPlayerID,
            "black_player_id": blackPlayer.id,
            "white_player_id": whitePlayer.id,
            "last_move": nowMilliseconds,
            "expiration": nowMilliseconds
                + Double(currentPlayerTimeRemaining) * 1_000,
            "black_time": [
                "thinking_time": Double(clock.blackTimeRemaining),
            ],
            "white_time": [
                "thinking_time": Double(clock.whiteTimeRemaining),
            ],
            "start_mode": false,
        ]

        let validationData = try! JSONSerialization.data(
            withJSONObject: gameJSON
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        _ = try! decoder.decode(OGSGame.self, from: validationData)

        return gameJSON
    }
}

private enum AppStoreScreenshotProfileData {
    static let profileOwner = OGSUser(
        username: "JuniperStone",
        id: 314_459,
        ranking: 28.232_738_093_057_69,
        uiClass: "supporter",
        country: "un",
        professional: false
    )

    private static let copperKoi = OGSUser(
        username: "CopperKoi",
        id: 429_553,
        ranking: 26.913_257_538_591_022,
        country: "zz",
        professional: false
    )

    private static let cobaltFox = OGSUser(
        username: "CobaltFox",
        id: 884_985,
        ranking: 31.788_511_974_807_587,
        country: "us",
        professional: false
    )

    private static let indigoCrane = OGSUser(
        username: "IndigoCrane",
        id: 851_011,
        ranking: 28.105_412_404_704_705,
        country: "un",
        professional: false
    )

    private static let cedarWave = OGSUser(
        username: "CedarWave",
        id: 851_001,
        ranking: 25.629_229_229_465_31,
        country: "un",
        professional: false
    )

    private static let jadeLantern = OGSUser(
        username: "JadeLantern",
        id: 851_002,
        ranking: 30.959_438_736_382_154,
        country: "un",
        professional: false
    )

    private static let harborMist = OGSUser(
        username: "HarborMist",
        id: 851_003,
        ranking: 30.953_150_119_443_812,
        country: "un",
        professional: false
    )

    private static let cloudGarden = OGSUser(
        username: "CloudGarden",
        id: 851_004,
        ranking: 23.576_388_538_391_73,
        country: "un",
        professional: false
    )

    private static let silverBamboo = OGSUser(
        username: "SilverBamboo",
        id: 851_005,
        ranking: 17.849_721_836_292_12,
        country: "un",
        professional: false
    )

    private static let quietPine = OGSUser(
        username: "QuietPine",
        id: 851_006,
        ranking: 25.887_438_469_018_903,
        country: "un",
        professional: false
    )

    private static let moonBridge = OGSUser(
        username: "MoonBridge",
        id: 851_007,
        ranking: 27.627_465_096_090_138,
        country: "un",
        professional: false
    )

    private static let autumnPath = OGSUser(
        username: "AutumnPath",
        id: 851_008,
        ranking: 28.713_405_218_456_16,
        country: "un",
        professional: false
    )

    private static let amberKite = OGSUser(
        username: "AmberKite",
        id: 851_009,
        ranking: 30.809_786_803_592_292,
        country: "un",
        professional: false
    )

    private static let riverStone = OGSUser(
        username: "RiverStone",
        id: 851_010,
        ranking: 28.780_294_961_695_336,
        country: "un",
        professional: false
    )

    private static func matchupTitle(
        _ title: String,
        whitePlayer: OGSUser,
        blackPlayer: OGSUser
    ) -> String {
        "\(title) (\(whitePlayer.username) vs \(blackPlayer.username))"
    }

    /// Game 68301595 has 145 moves. The active fixture intentionally keeps
    /// only its first 48 moves.
    static let copperKoiOpening = AppStoreScreenshotProfileGame(
        id: 68_301_595,
        sourceMoveCount: 145,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:2",
            whitePlayer: copperKoi,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: copperKoi,
        outcome: "Resignation",
        winnerID: profileOwner.id,
        movesJSON: #"""
        [
          [15,3],[3,15],[16,15],[3,3],[13,16],[16,2],[16,3],[15,2],
          [14,2],[14,1],[13,2],[13,1],[12,2],[12,1],[11,2],[15,9],
          [15,7],[15,15],[15,16],[16,14],[17,15],[15,14],[16,11],[15,11],
          [16,10],[15,10],[16,9],[15,8],[16,8],[14,7],[14,6],[15,6],
          [16,7],[13,6],[14,5],[13,8],[2,13],[2,14],[3,13],[5,15],
          [3,9],[1,11],[1,12],[3,11],[5,12],[5,11],[6,11],[5,10]
        ]
        """#
    )

    /// Game 62050416 has 215 moves. The active fixture intentionally keeps
    /// only its first 60 moves.
    static let cobaltFoxOpening = AppStoreScreenshotProfileGame(
        id: 62_050_416,
        sourceMoveCount: 215,
        gameName: matchupTitle(
            "Tournament Game: Correspondence 19x19 RoundRobin 2024-02-29 19:00 (113340) R:1",
            whitePlayer: profileOwner,
            blackPlayer: cobaltFox
        ),
        blackPlayer: cobaltFox,
        whitePlayer: profileOwner,
        outcome: "Resignation",
        winnerID: cobaltFox.id,
        movesJSON: #"""
        [
          [16,3],[3,3],[16,15],[3,16],[3,14],[2,14],[2,13],[2,15],
          [3,13],[5,16],[3,9],[14,15],[14,16],[13,16],[15,16],[13,15],
          [16,13],[9,15],[2,5],[5,2],[13,2],[16,8],[16,6],[16,11],
          [1,3],[2,2],[4,5],[9,3],[9,1],[11,2],[11,1],[12,1],
          [10,2],[12,2],[10,3],[15,2],[15,3],[14,2],[14,3],[13,1],
          [13,3],[16,2],[17,2],[17,1],[17,3],[18,1],[1,2],[1,1],
          [2,3],[3,2],[0,1],[3,4],[3,5],[3,11],[2,11],[2,10],
          [3,10],[2,12],[1,11],[1,12]
        ]
        """#
    )

    /// Game 18759438 has 257 moves. The active fixture intentionally keeps
    /// only its first 61 moves.
    static let indigoCraneOpening = AppStoreScreenshotProfileGame(
        id: 18_759_438,
        sourceMoveCount: 257,
        gameName: matchupTitle(
            "Tournament Game: 1st 3 Kyu to 3 Dan Tournament (50283) R:1",
            whitePlayer: profileOwner,
            blackPlayer: indigoCrane
        ),
        blackPlayer: indigoCrane,
        whitePlayer: profileOwner,
        outcome: "56.5 points",
        winnerID: profileOwner.id,
        rules: .korean,
        movesJSON: #"""
        [
          [15,3],[15,15],[2,3],[3,15],[4,2],[3,9],[16,9],[16,2],
          [16,3],[15,2],[14,2],[14,1],[13,1],[13,2],[14,3],[12,1],
          [15,1],[13,0],[16,1],[9,2],[9,15],[5,16],[13,16],[16,13],
          [16,16],[15,16],[15,17],[14,17],[16,17],[13,17],[12,16],[12,17],
          [11,16],[14,16],[17,14],[12,14],[11,17],[15,8],[16,8],[15,6],
          [16,7],[15,7],[16,6],[8,17],[11,13],[11,14],[10,14],[10,13],
          [9,13],[10,12],[9,12],[10,11],[9,11],[12,12],[10,10],[10,15],
          [9,16],[9,14],[8,14],[10,14],[7,15]
        ]
        """#
    )

    /// Complete 221-move scored win from profile game 68301601.
    static let cedarWaveFinished = AppStoreScreenshotProfileGame(
        id: 68_301_601,
        sourceMoveCount: 221,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:2",
            whitePlayer: profileOwner,
            blackPlayer: cedarWave
        ),
        blackPlayer: cedarWave,
        whitePlayer: profileOwner,
        outcome: "8.5 points",
        winnerID: profileOwner.id,
        movesJSON: #"""
        [
          [15,3],[3,3],[2,16],[15,15],[16,13],[13,16],[5,2],[2,5],
          [9,9],[7,2],[5,4],[13,2],[16,5],[10,2],[3,1],[2,2],
          [5,6],[16,11],[14,13],[14,11],[12,13],[16,8],[15,1],[9,15],
          [7,15],[9,13],[11,16],[3,14],[4,15],[4,14],[1,14],[5,15],
          [6,16],[5,16],[7,13],[8,16],[6,15],[6,14],[7,14],[11,15],
          [12,15],[12,16],[10,14],[10,15],[9,14],[3,16],[2,15],[3,15],
          [2,12],[2,8],[2,10],[2,17],[1,17],[2,1],[4,2],[16,14],
          [16,12],[14,1],[16,2],[17,11],[17,14],[17,15],[15,14],[16,15],
          [14,15],[14,16],[13,15],[7,17],[6,17],[5,17],[6,18],[3,17],
          [1,18],[2,18],[11,14],[12,11],[9,3],[9,2],[7,3],[8,3],
          [8,4],[8,2],[9,4],[11,4],[11,5],[12,5],[11,6],[12,6],
          [11,7],[13,8],[12,7],[13,7],[13,6],[13,5],[14,6],[15,7],
          [14,5],[12,4],[4,8],[3,9],[5,10],[5,12],[6,12],[8,11],
          [10,11],[11,9],[10,8],[11,12],[10,12],[10,13],[11,13],[10,10],
          [9,10],[9,11],[11,10],[12,10],[10,9],[10,4],[10,5],[6,3],
          [7,4],[6,2],[4,4],[6,4],[6,5],[15,12],[14,12],[15,11],
          [15,13],[1,9],[1,10],[4,9],[5,9],[17,13],[17,12],[18,14],
          [9,17],[8,17],[8,18],[7,18],[9,16],[8,15],[10,16],[11,17],
          [2,9],[3,8],[4,7],[3,6],[17,7],[17,8],[16,6],[5,1],
          [4,1],[6,1],[14,2],[13,1],[13,3],[12,3],[13,4],[11,8],
          [9,7],[2,13],[1,13],[3,12],[3,11],[6,13],[5,11],[4,12],
          [3,10],[9,18],[8,14],[1,8],[3,4],[2,4],[3,7],[2,7],
          [4,6],[11,11],[10,10],[18,12],[2,0],[1,0],[3,0],[1,1],
          [3,5],[2,6],[10,3],[11,3],[14,0],[11,2],[13,0],[12,0],
          [15,0],[12,1],[14,7],[14,8],[12,8],[12,9],[5,18],[4,18],
          [16,7],[2,14],[15,6],[15,8],[0,9],[0,8],[0,10],[18,7],
          [18,6],[18,8],[13,12],[13,11],[5,0],[6,0],[4,0],[3,2],
          [12,12],[10,17],[4,11],[-1,-1],[-1,-1]
        ]
        """#
    )

    /// Complete 245-move scored loss from profile game 25089254.
    static let jadeLanternFinished = AppStoreScreenshotProfileGame(
        id: 25_089_254,
        sourceMoveCount: 245,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:1",
            whitePlayer: jadeLantern,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: jadeLantern,
        outcome: "4.5 points",
        winnerID: jadeLantern.id,
        movesJSON: #"""
        [
          [15,3],[3,15],[15,16],[3,3],[5,16],[2,13],[9,15],[16,14],
          [15,11],[17,16],[16,16],[17,17],[14,14],[17,11],[3,12],[2,12],
          [2,2],[2,3],[3,2],[4,2],[4,1],[5,2],[5,1],[6,2],
          [1,3],[1,4],[1,2],[2,4],[3,9],[3,11],[4,12],[4,11],
          [5,12],[5,11],[4,4],[3,7],[4,7],[4,8],[5,7],[3,8],
          [6,11],[6,10],[7,11],[7,10],[5,8],[5,9],[9,7],[8,11],
          [7,13],[9,9],[4,3],[6,4],[3,6],[2,6],[2,7],[2,8],
          [2,5],[1,6],[3,5],[1,5],[9,3],[5,5],[4,6],[7,7],
          [7,8],[8,8],[8,7],[6,6],[10,9],[9,10],[13,2],[16,9],
          [2,16],[2,15],[3,16],[5,15],[4,15],[4,14],[4,16],[6,14],
          [6,15],[5,14],[6,12],[7,14],[8,14],[7,15],[6,16],[17,3],
          [16,2],[17,2],[17,1],[16,3],[16,1],[15,4],[14,4],[14,3],
          [15,2],[14,5],[13,4],[15,5],[17,12],[17,13],[16,12],[18,12],
          [16,13],[17,14],[15,7],[16,7],[16,6],[15,6],[16,8],[17,7],
          [15,8],[17,8],[16,10],[17,10],[15,9],[17,9],[1,15],[2,14],
          [9,8],[8,9],[11,11],[10,11],[10,12],[9,12],[9,13],[11,12],
          [10,13],[11,10],[12,11],[11,9],[10,8],[10,10],[8,12],[8,6],
          [9,6],[8,5],[9,5],[8,4],[8,2],[6,1],[12,6],[14,18],
          [14,17],[15,18],[13,18],[16,17],[13,17],[5,0],[3,0],[9,4],
          [10,4],[13,5],[12,5],[14,7],[1,14],[1,13],[7,1],[7,2],
          [15,14],[7,16],[9,17],[0,14],[0,16],[8,3],[9,2],[11,8],
          [11,7],[7,17],[6,17],[16,15],[15,17],[16,18],[13,9],[14,8],
          [14,9],[8,1],[9,1],[7,0],[18,2],[18,3],[18,1],[16,4],
          [13,6],[14,6],[9,0],[15,15],[14,15],[12,10],[13,10],[12,7],
          [13,7],[12,8],[11,6],[6,18],[5,18],[7,18],[8,0],[6,0],
          [1,1],[4,0],[3,1],[9,18],[10,18],[8,18],[8,16],[0,3],
          [0,2],[0,4],[16,11],[6,13],[9,11],[8,10],[9,12],[10,17],
          [11,18],[8,17],[9,16],[0,13],[7,1],[0,15],[1,16],[8,1],
          [3,13],[3,14],[7,1],[11,17],[12,18],[8,1],[18,13],[18,14],
          [7,1],[12,4],[13,3],[8,1],[18,11],[18,10],[7,1],[2,11],
          [8,1],[13,8],[7,12],[-1,-1],[-1,-1]
        ]
        """#
    )

    static let harborMistFinished = AppStoreScreenshotProfileGame(
        id: 68_301_602,
        sourceMoveCount: 226,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:2",
            whitePlayer: harborMist,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: harborMist,
        outcome: "Resignation",
        winnerID: harborMist.id,
        movesJSON: #"""
        [[15,3],[3,15],[16,15],[3,2],[3,4],[2,4],[2,5],[2,3],[3,5],[5,2],[3,9],[14,16],[15,16],[14,15],[15,13],[10,15],[5,16],[4,16],[5,15],[2,13],[16,5],[16,11],[16,12],[15,11],[16,8],[14,13],[14,12],[15,14],[16,14],[15,12],[16,13],[13,12],[10,2],[7,15],[5,13],[2,11],[2,10],[3,11],[7,17],[5,17],[8,16],[8,15],[10,17],[9,16],[6,17],[4,17],[9,17],[6,12],[5,12],[5,11],[6,11],[4,11],[7,16],[7,12],[14,2],[2,8],[1,10],[3,8],[4,9],[5,7],[6,4],[5,5],[5,4],[7,3],[7,4],[7,6],[8,3],[7,2],[6,9],[8,9],[8,10],[7,10],[7,9],[8,8],[7,11],[9,10],[8,11],[5,10],[6,10],[5,9],[4,8],[4,7],[3,7],[2,7],[3,6],[5,8],[1,6],[2,9],[3,10],[1,9],[0,9],[0,8],[0,10],[1,7],[0,6],[1,11],[0,7],[0,11],[1,8],[15,17],[2,6],[16,17],[17,11],[17,10],[17,12],[16,9],[15,8],[17,16],[17,15],[18,13],[13,8],[17,8],[17,7],[18,7],[18,6],[18,8],[17,6],[13,10],[9,11],[10,10],[9,14],[9,15],[8,13],[6,14],[5,14],[6,15],[13,17],[12,16],[12,17],[14,17],[13,13],[14,11],[6,16],[11,16],[13,14],[14,14],[11,14],[11,17],[8,18],[10,18],[6,18],[10,13],[8,12],[6,13],[10,14],[10,11],[10,8],[9,6],[10,6],[9,5],[10,5],[9,4],[1,2],[1,3],[2,2],[3,3],[3,1],[4,1],[1,1],[2,0],[3,0],[0,2],[0,1],[1,0],[0,3],[0,4],[4,3],[4,2],[8,1],[7,1],[6,1],[5,3],[4,4],[4,0],[2,1],[0,2],[11,15],[10,16],[0,3],[8,2],[9,1],[9,3],[8,4],[9,2],[6,6],[6,5],[7,5],[6,7],[8,6],[7,7],[9,7],[8,7],[8,5],[9,8],[10,7],[11,4],[11,3],[10,4],[12,4],[12,5],[13,4],[11,5],[12,7],[0,2],[11,12],[10,12],[0,3],[12,15],[7,0],[0,2],[18,14],[17,13],[0,3],[11,18],[9,18],[0,2],[18,10],[17,9],[0,3],[6,0],[5,0],[0,2],[13,15],[13,16],[0,3],[6,2]]
        """#
    )

    static let friendlyFinished = AppStoreScreenshotProfileGame(
        id: 67_811_158,
        sourceMoveCount: 151,
        gameName: "Friendly Match",
        blackPlayer: cloudGarden,
        whitePlayer: profileOwner,
        outcome: "Resignation",
        winnerID: profileOwner.id,
        movesJSON: #"""
        [[13,2],[16,5],[5,2],[8,2],[2,2],[2,3],[3,2],[5,3],[4,3],[4,4],[4,2],[5,4],[3,9],[2,13],[2,5],[1,3],[3,6],[3,4],[1,2],[11,2],[16,16],[16,15],[15,16],[14,15],[13,17],[15,11],[16,2],[15,2],[15,1],[14,1],[16,1],[14,2],[17,4],[17,5],[16,4],[15,5],[9,15],[6,16],[12,15],[13,3],[15,8],[14,9],[14,8],[13,8],[13,7],[12,8],[12,7],[11,8],[9,3],[11,7],[12,5],[11,6],[12,3],[12,2],[13,4],[13,1],[15,4],[14,4],[14,5],[17,3],[16,3],[17,8],[16,9],[14,6],[13,5],[14,7],[15,6],[15,7],[16,7],[11,3],[8,3],[9,2],[7,3],[7,2],[7,6],[5,6],[7,8],[5,8],[7,10],[4,9],[2,10],[4,10],[3,12],[2,12],[4,7],[5,7],[4,8],[3,10],[2,9],[7,9],[6,9],[8,9],[6,8],[5,9],[6,10],[4,12],[7,14],[17,10],[17,7],[17,9],[13,6],[13,16],[12,16],[14,17],[14,16],[13,15],[15,17],[12,14],[17,15],[17,14],[17,16],[11,14],[11,17],[9,13],[2,16],[3,16],[3,17],[4,17],[1,17],[3,18],[2,18],[2,17],[14,10],[15,9],[3,17],[1,1],[0,3],[2,17],[15,10],[13,9],[3,17],[18,7],[18,6],[2,17],[6,5],[4,6],[3,17],[8,7],[7,7],[2,17],[17,13],[16,13],[3,17],[17,6],[18,8],[2,17],[18,14],[1,18],[16,14],[15,13],[16,10]]
        """#
    )

    static let silverBambooFinished = AppStoreScreenshotProfileGame(
        id: 62_050_423,
        sourceMoveCount: 193,
        gameName: matchupTitle(
            "Tournament Game: Correspondence 19x19 RoundRobin 2024-02-29 19:00 (113340) R:1",
            whitePlayer: silverBamboo,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: silverBamboo,
        outcome: "154.5 points",
        winnerID: profileOwner.id,
        movesJSON: #"""
        [[15,3],[3,15],[16,15],[3,2],[14,16],[2,4],[2,13],[5,16],[2,9],[13,2],[16,5],[15,1],[16,2],[9,2],[15,9],[9,15],[12,3],[12,2],[11,3],[10,2],[16,1],[15,0],[1,15],[2,16],[1,16],[2,17],[11,9],[16,13],[16,11],[14,13],[11,15],[12,12],[10,13],[13,10],[13,9],[14,10],[14,9],[15,11],[15,10],[15,12],[7,16],[7,15],[9,16],[10,15],[10,16],[10,12],[8,15],[10,14],[11,14],[9,14],[8,14],[9,13],[11,13],[11,11],[9,12],[8,13],[7,14],[8,12],[9,11],[8,11],[9,10],[8,10],[8,9],[7,9],[8,8],[7,8],[7,10],[6,11],[6,10],[6,13],[5,11],[6,14],[6,15],[5,15],[6,12],[7,12],[7,11],[7,13],[5,14],[6,16],[5,13],[7,17],[8,17],[7,18],[8,18],[5,17],[12,10],[12,11],[13,13],[13,12],[14,11],[13,11],[15,14],[15,13],[17,12],[17,13],[7,7],[6,8],[6,7],[2,7],[4,8],[4,6],[6,3],[6,2],[7,2],[6,1],[7,1],[9,1],[5,3],[5,2],[4,2],[4,1],[4,3],[3,3],[6,0],[5,1],[1,8],[1,7],[1,17],[2,18],[9,4],[14,4],[14,3],[13,3],[13,4],[8,3],[7,3],[8,4],[8,5],[7,4],[5,5],[5,6],[6,5],[5,7],[5,8],[6,6],[7,5],[7,6],[6,9],[12,4],[13,5],[11,4],[11,5],[10,4],[10,5],[9,3],[9,5],[8,6],[9,6],[8,7],[9,7],[4,5],[12,5],[10,3],[14,2],[14,1],[3,7],[3,6],[2,8],[4,7],[3,8],[5,0],[7,0],[2,1],[3,14],[4,15],[16,0],[5,4],[6,4],[4,4],[0,7],[0,6],[1,6],[2,6],[0,5],[1,5],[0,6],[0,4],[0,8],[8,0],[8,1],[9,0],[15,2],[12,1],[1,18],[4,14],[4,13],[2,14],[3,13],[2,15],[1,14],[-1,-1],[-1,-1]]
        """#
    )

    static let quietPineFinished = AppStoreScreenshotProfileGame(
        id: 25_089_220,
        sourceMoveCount: 231,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:1",
            whitePlayer: profileOwner,
            blackPlayer: quietPine
        ),
        blackPlayer: quietPine,
        whitePlayer: profileOwner,
        outcome: "Resignation",
        winnerID: profileOwner.id,
        movesJSON: #"""
        [[15,3],[3,3],[14,16],[3,15],[5,16],[2,13],[9,15],[16,5],[13,2],[16,9],[17,3],[16,15],[16,13],[15,14],[17,16],[16,16],[17,15],[15,13],[16,17],[16,12],[17,14],[15,17],[17,17],[14,17],[2,16],[3,16],[3,17],[4,17],[2,17],[4,16],[1,14],[1,13],[2,14],[3,14],[2,15],[7,16],[7,15],[8,16],[9,16],[8,15],[8,14],[6,15],[7,14],[9,14],[6,16],[6,17],[5,15],[9,17],[4,13],[10,15],[5,17],[7,17],[3,13],[5,18],[6,14],[2,10],[2,5],[2,7],[2,2],[2,3],[3,2],[4,3],[1,3],[1,4],[1,2],[2,4],[5,2],[6,4],[6,2],[12,3],[13,3],[12,4],[4,10],[3,10],[4,9],[3,8],[16,7],[17,7],[17,6],[16,6],[17,8],[15,7],[16,8],[15,8],[17,9],[16,10],[17,5],[16,4],[17,4],[9,13],[8,11],[10,10],[10,11],[11,11],[10,12],[8,12],[9,10],[11,12],[10,13],[11,14],[10,9],[11,10],[7,12],[6,7],[9,8],[6,9],[5,8],[6,8],[11,13],[12,13],[5,7],[5,6],[4,6],[6,6],[4,7],[4,11],[5,11],[5,10],[3,11],[6,11],[5,12],[7,11],[6,12],[8,9],[9,9],[2,11],[3,12],[9,3],[12,8],[11,6],[10,6],[11,7],[11,9],[14,6],[8,8],[7,9],[12,10],[12,12],[8,5],[8,4],[10,5],[12,2],[11,5],[12,5],[14,9],[14,11],[10,3],[10,2],[9,4],[8,3],[7,5],[6,3],[13,7],[13,6],[10,7],[11,8],[14,8],[13,9],[13,11],[14,10],[13,10],[12,9],[13,12],[13,13],[14,12],[15,12],[9,6],[8,7],[6,5],[5,5],[5,4],[5,3],[4,5],[4,4],[15,10],[15,11],[15,9],[17,10],[14,13],[14,14],[13,8],[12,9],[7,7],[7,6],[9,11],[10,16],[8,13],[9,12],[10,14],[9,15],[12,14],[13,14],[11,15],[13,16],[12,16],[13,17],[17,12],[13,1],[17,11],[16,11],[16,14],[12,17],[14,1],[12,1],[15,2],[4,2],[4,1],[7,2],[7,1],[8,1],[6,1],[1,5],[2,6],[1,6],[1,12],[2,12],[0,13],[1,11],[0,12],[0,11],[0,14],[7,0],[5,0],[8,0],[6,0],[18,9],[18,7],[16,3],[16,2],[4,14],[5,14]]
        """#
    )

    static let moonBridgeFinished = AppStoreScreenshotProfileGame(
        id: 25_089_241,
        sourceMoveCount: 228,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:1",
            whitePlayer: moonBridge,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: moonBridge,
        outcome: "Resignation",
        winnerID: moonBridge.id,
        movesJSON: #"""
        [[15,3],[2,16],[15,15],[3,2],[3,15],[3,16],[4,15],[2,15],[3,13],[2,14],[5,12],[6,16],[9,15],[4,16],[6,15],[7,15],[6,14],[8,16],[2,5],[13,2],[16,5],[9,2],[13,16],[16,13],[16,14],[16,7],[14,2],[13,3],[16,9],[14,7],[14,9],[14,11],[12,9],[12,11],[13,5],[12,7],[10,9],[10,11],[11,6],[11,7],[10,6],[10,7],[9,7],[14,5],[13,6],[13,7],[14,6],[15,6],[15,5],[14,4],[11,4],[9,8],[10,8],[9,6],[8,7],[9,5],[11,2],[11,1],[9,4],[8,4],[9,3],[8,3],[10,2],[10,1],[8,5],[12,6],[12,5],[10,5],[11,5],[8,6],[7,5],[7,6],[8,2],[9,1],[7,3],[9,9],[7,7],[6,5],[7,4],[6,7],[7,8],[10,10],[11,10],[13,9],[13,10],[13,8],[9,10],[11,9],[8,9],[11,8],[15,12],[15,11],[16,11],[15,13],[14,12],[13,11],[13,13],[16,12],[17,11],[14,13],[13,12],[13,14],[12,13],[12,14],[11,13],[14,15],[14,16],[11,14],[10,13],[17,14],[17,15],[10,14],[9,14],[9,13],[9,12],[8,13],[10,12],[8,12],[9,11],[10,16],[11,11],[12,10],[10,9],[14,1],[15,1],[7,1],[12,1],[13,1],[12,2],[12,0],[8,1],[8,0],[5,2],[6,2],[5,3],[5,1],[3,3],[2,3],[2,2],[4,3],[4,1],[6,3],[3,4],[5,4],[4,2],[15,4],[16,4],[6,4],[10,4],[6,6],[7,2],[5,11],[5,9],[4,12],[6,12],[6,11],[7,11],[3,11],[8,14],[7,14],[7,13],[9,16],[7,12],[5,8],[4,10],[3,1],[4,4],[4,0],[4,3],[2,1],[1,2],[2,6],[1,1],[1,0],[1,3],[1,6],[4,6],[3,6],[6,0],[6,1],[5,0],[7,0],[5,0],[6,0],[4,7],[4,5],[3,5],[1,5],[5,5],[1,4],[2,4],[4,8],[3,7],[2,8],[2,7],[1,7],[1,8],[2,9],[1,9],[1,10],[0,1],[5,0],[3,8],[3,9],[4,9],[6,9],[6,10],[4,11],[6,8],[5,7],[3,0],[2,0],[0,0],[3,0],[9,0],[10,0],[0,3],[16,2],[15,2],[16,3],[16,1],[17,1],[17,0],[17,4],[17,5],[17,3],[18,1],[17,6]]
        """#
    )

    static let autumnPathFinished = AppStoreScreenshotProfileGame(
        id: 25_089_253,
        sourceMoveCount: 192,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:1",
            whitePlayer: autumnPath,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: autumnPath,
        outcome: "Resignation",
        winnerID: autumnPath.id,
        movesJSON: #"""
        [[15,3],[3,15],[15,16],[3,3],[16,10],[3,9],[5,16],[5,15],[6,15],[5,14],[4,16],[3,16],[6,14],[4,15],[9,15],[6,13],[5,2],[4,2],[5,3],[2,5],[9,3],[5,9],[9,9],[7,13],[15,14],[16,2],[16,3],[15,2],[14,2],[14,1],[13,2],[13,1],[12,2],[16,8],[15,7],[15,8],[14,10],[14,8],[14,7],[13,8],[12,6],[13,10],[13,11],[13,7],[13,6],[14,11],[15,10],[16,6],[16,7],[17,7],[14,6],[17,9],[17,10],[17,5],[17,2],[17,1],[17,3],[12,1],[11,2],[12,11],[13,12],[12,9],[11,13],[11,8],[3,6],[2,6],[3,7],[5,5],[4,3],[3,4],[5,7],[7,5],[7,7],[9,5],[4,5],[4,4],[5,4],[6,5],[10,7],[4,6],[4,7],[3,5],[7,10],[4,1],[6,11],[6,16],[7,16],[6,17],[7,15],[7,17],[8,17],[5,12],[4,10],[3,10],[4,11],[3,11],[4,12],[3,12],[4,13],[5,13],[3,13],[2,13],[2,8],[4,9],[18,1],[16,1],[11,10],[12,7],[12,10],[11,7],[11,6],[5,1],[6,1],[6,2],[6,3],[7,2],[7,3],[8,2],[8,3],[8,14],[8,15],[6,10],[9,2],[7,1],[8,1],[6,0],[8,12],[5,11],[8,13],[18,10],[18,11],[18,9],[17,12],[15,5],[14,4],[14,5],[13,5],[10,4],[8,5],[8,6],[8,4],[8,7],[8,8],[7,6],[6,8],[10,6],[10,8],[7,14],[9,14],[7,11],[8,11],[7,9],[7,12],[7,8],[6,9],[6,7],[5,10],[5,8],[2,14],[3,14],[1,11],[1,13],[1,7],[1,9],[2,9],[1,10],[2,10],[2,11],[6,10],[12,4],[13,4],[11,1],[10,1],[10,3],[10,2],[8,0],[9,0],[7,0],[11,5],[10,5],[11,4],[15,4],[17,0],[15,0],[17,4],[16,9],[18,5],[17,6],[18,4],[18,2],[18,7],[18,6]]
        """#
    )

    static let amberKiteFinished = AppStoreScreenshotProfileGame(
        id: 25_089_251,
        sourceMoveCount: 160,
        gameName: matchupTitle(
            "Tournament Game: Through the Years: Long Correspondence (59567) R:1",
            whitePlayer: amberKite,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: amberKite,
        outcome: "Resignation",
        winnerID: amberKite.id,
        movesJSON: #"""
        [[15,3],[3,2],[15,15],[2,15],[4,16],[3,14],[7,15],[16,2],[16,3],[15,2],[14,2],[14,1],[13,2],[13,1],[12,2],[12,1],[11,2],[16,13],[15,9],[13,16],[15,13],[15,12],[14,13],[16,16],[16,14],[15,16],[17,13],[3,5],[2,9],[2,11],[2,7],[2,5],[4,8],[6,5],[7,2],[3,16],[4,15],[6,8],[4,10],[5,13],[3,12],[3,11],[4,13],[4,14],[4,11],[2,12],[3,17],[2,17],[5,14],[3,13],[4,12],[4,17],[5,17],[3,18],[5,15],[10,15],[6,13],[17,2],[17,3],[18,3],[18,4],[18,2],[17,4],[14,4],[12,5],[14,8],[15,8],[14,6],[15,6],[14,7],[15,5],[14,5],[13,10],[12,7],[9,5],[10,7],[8,7],[15,7],[16,7],[11,10],[11,13],[16,8],[17,8],[16,6],[17,7],[15,4],[16,5],[8,6],[9,6],[9,7],[8,8],[7,6],[8,10],[9,9],[8,9],[9,10],[9,11],[10,11],[9,12],[13,9],[14,9],[12,10],[13,11],[11,12],[12,12],[10,12],[10,9],[10,10],[11,16],[11,15],[10,16],[12,16],[9,16],[9,15],[8,15],[5,2],[6,7],[7,7],[5,6],[5,5],[4,6],[7,8],[4,5],[4,4],[6,3],[5,3],[12,15],[10,13],[13,15],[14,15],[14,14],[14,16],[12,13],[8,11],[7,11],[8,12],[7,12],[9,13],[6,4],[5,4],[12,6],[7,10],[11,7],[11,8],[11,6],[12,8],[17,16],[17,15],[17,17],[16,15],[17,14],[18,16],[18,17],[18,15],[16,17],[15,17],[12,17],[13,17],[13,18],[14,18]]
        """#
    )

    static let riverStoneFinished = AppStoreScreenshotProfileGame(
        id: 35_505_493,
        sourceMoveCount: 244,
        gameName: matchupTitle(
            "Tournament Game: 1st 3 Kyu to 3 Dan Tournament (50283) R:3",
            whitePlayer: riverStone,
            blackPlayer: profileOwner
        ),
        blackPlayer: profileOwner,
        whitePlayer: riverStone,
        outcome: "0.5 points",
        winnerID: riverStone.id,
        rules: .korean,
        movesJSON: #"""
        [[15,3],[3,15],[15,16],[3,3],[15,13],[13,2],[16,5],[10,3],[2,2],[2,3],[3,2],[4,3],[5,1],[5,16],[2,9],[2,7],[2,13],[16,11],[16,12],[15,11],[16,8],[13,15],[13,12],[10,15],[14,9],[2,11],[1,11],[1,12],[2,12],[1,10],[3,11],[2,10],[3,10],[1,9],[2,8],[1,8],[3,7],[3,6],[2,6],[1,7],[4,7],[4,6],[5,7],[13,11],[12,11],[13,10],[12,10],[13,9],[12,9],[14,12],[14,13],[12,12],[13,13],[13,8],[11,13],[15,7],[16,7],[12,8],[10,10],[10,8],[9,9],[16,2],[15,2],[15,1],[16,3],[17,1],[17,2],[16,1],[1,13],[14,16],[15,15],[5,2],[6,1],[1,2],[4,1],[2,1],[7,3],[8,1],[8,2],[9,2],[6,2],[6,13],[2,16],[2,15],[1,15],[3,16],[1,17],[9,13],[12,16],[12,15],[11,16],[10,16],[11,15],[11,14],[12,14],[10,14],[14,17],[13,17],[13,16],[11,17],[14,15],[12,17],[13,14],[6,6],[5,6],[5,5],[6,5],[5,4],[7,6],[6,4],[6,7],[9,8],[7,4],[8,5],[7,5],[17,3],[17,4],[18,2],[3,17],[4,17],[12,4],[12,3],[11,7],[11,8],[10,6],[13,6],[13,4],[11,5],[11,4],[10,5],[9,6],[9,5],[8,6],[11,6],[10,7],[12,7],[7,12],[7,13],[8,12],[6,12],[6,11],[5,11],[5,10],[8,9],[8,8],[7,11],[6,10],[7,8],[8,7],[9,10],[10,9],[9,12],[9,11],[8,11],[8,10],[8,13],[10,12],[3,18],[2,17],[7,10],[7,9],[4,11],[4,10],[0,11],[4,13],[5,14],[5,12],[8,3],[7,2],[17,10],[17,9],[17,12],[17,13],[18,13],[18,14],[18,12],[17,14],[5,13],[4,12],[15,9],[15,8],[14,8],[15,6],[16,9],[17,8],[10,13],[18,10],[17,11],[11,12],[15,12],[16,13],[11,3],[1,3],[1,4],[1,1],[0,3],[0,1],[4,2],[3,1],[6,3],[14,2],[14,1],[8,4],[9,3],[14,6],[14,7],[2,18],[14,18],[4,18],[5,18],[15,18],[13,18],[4,14],[4,15],[13,5],[13,3],[14,3],[11,9],[2,14],[11,10],[11,11],[12,5],[0,2],[1,3],[7,1],[9,1],[0,13],[7,0],[6,0],[8,0],[0,12],[18,4],[18,5],[18,3],[1,11],[0,10],[3,14],[18,11],[18,9],[3,18],[1,12],[4,18],[-1,-1],[-1,-1]]
        """#
    )
}
#endif

extension OGSService {
    static func previewInstance(
        user: OGSUser? = nil,
        activeGames: [Game] = [],
        publicGames: [Game] = [],
        friends: [OGSUser] = [],
        socketStatus: OGSWebsocketStatus = .connected,
        eligibleOpenChallenges: [OGSSeekgraphChallenge] = [],
        openChallengesSent: [OGSSeekgraphChallenge] = [],
        challengesReceived: [OGSDirectChallenge] = [],
        automatchEntries: [OGSAutomatchEntry] = [],
        cachedUsers: [OGSUser] = [],
        preferredGameSettings: [OGSChallengeTemplate] = []
    ) -> OGSService {
        var state = BootstrapState()
        state.user = user
        state.isLoggedIn = user != nil

        for game in activeGames {
            state.activeGames[game.ogsID!] = game
        }
        state.sortedPublicGames = publicGames
        state.friends = friends
        state.socketStatus = socketStatus

        for challenge in eligibleOpenChallenges {
            state.eligibleOpenChallengeById[challenge.id] = challenge
        }
        for challenge in openChallengesSent {
            state.openChallengeSentById[challenge.id] = challenge
        }
        for automatchEntry in automatchEntries {
            state.autoMatchEntryById[automatchEntry.uuid] = automatchEntry
        }
        state.challengesReceived = challengesReceived
        state.privateMessages = OGSPrivateMessage.sampleData

        if let user = user {
            state.cachedUsersById[user.id] = user
        }
        for user in cachedUsers {
            state.cachedUsersById[user.id] = user
        }

        state.preferredGameSettings = Set(preferredGameSettings)

        return OGSService(forPreview: true, initialState: state)
    }

    #if DEBUG && MAIN_APP
    /// A deterministic, signed-in OGS service for app-driven UI tests.
    ///
    /// Both transports are incapable of reaching OGS. The fixture is loaded
    /// synchronously from the app bundle, and observers, timers, automatic
    /// connection, companion-service access, and app-global side effects are
    /// all disabled.
    @discardableResult
    static func clearAppStoreScreenshotWidgetFixture() -> Bool {
        guard let sharedWidgetDefaults = UserDefaults(
            suiteName: userDefaultsSuite
        ) else {
            return false
        }
        sharedWidgetDefaults[.appStoreScreenshotWidgetFixture] = nil
        let synchronized = sharedWidgetDefaults.synchronize()
        WidgetCenter.shared.reloadTimelines(
            ofKind: SurroundWidgetContract.correspondenceGamesKind
        )
        return synchronized
    }

    static func offlineUITestInstance() -> OGSService {
        func makeService(from state: BootstrapState) -> OGSService {
            OGSService(
                environment: .current,
                httpClient: SurroundUITestRejectingHTTPClient(),
                preferences: userDefaults,
                ogsWebsocket: SurroundUITestNoOpWebsocket(),
                connectsAutomatically: false,
                usesSurroundOverviewService: false,
                enablesAppSideEffects: false,
                startsTimers: false,
                installsObservers: false,
                remoteSettings: OGSRemoteSetting(preferences: userDefaults),
                initialState: state
            )
        }

        var state = BootstrapState()

        if !SurroundUITestContract.isCapturingAppStoreScreenshots {
            if !SurroundUITestContract
                .isClearingAppStoreScreenshotWidgetFixture
            {
                clearAppStoreScreenshotWidgetFixture()
            }

            func makeGeneratedGame(
                from source: Game,
                blackUsername: String,
                whiteUsername: String
            ) -> Game {
                guard var gameData = source.gameData else {
                    preconditionFailure("The bundled UI-test fixture must contain game data.")
                }

                gameData.players.black.username = blackUsername
                gameData.players.white.username = whiteUsername
                if var playerPool = gameData.playerPool {
                    playerPool[gameData.players.black.id] = gameData.players.black
                    playerPool[gameData.players.white.id] = gameData.players.white
                    gameData.playerPool = playerPool
                }

                let game = Game(ogsGame: gameData)
                game.ogsRawData = [:]
                return game
            }

            let fixtureGame = makeGeneratedGame(
                from: TestData.Ongoing19x19wBot2,
                blackUsername: "OrbitFox",
                whiteUsername: "PuzzleHeron"
            )
            precondition(fixtureGame.ogsID == SurroundUITestContract.fixtureGameID)

            guard let fixtureUser = fixtureGame.whitePlayer else {
                preconditionFailure("The bundled UI-test fixture must contain a white player.")
            }
            state.user = fixtureUser
            state.isLoggedIn = true
            state.socketStatus = .connected
            state.isLoadingOverview = false

            state.activeGames[SurroundUITestContract.fixtureGameID] = fixtureGame

            let publicGame = makeGeneratedGame(
                from: TestData.Ongoing19x19HandicappedWithNoInitialState,
                blackUsername: "WillowKnight",
                whiteUsername: "EmberRook"
            )
            state.publicGames[publicGame.ogsID!] = publicGame
            state.sortedPublicGames = [publicGame]
            for player in [
                fixtureGame.blackPlayer,
                fixtureGame.whitePlayer,
                publicGame.blackPlayer,
                publicGame.whitePlayer,
            ].compactMap({ $0 }) {
                state.cachedUsersById[player.id] = player
            }

            state.finishedGamesSnapshot = []
            return makeService(from: state)
        }

        let fixtureUser = AppStoreScreenshotProfileData.profileOwner
        state.user = fixtureUser
        state.isLoggedIn = true
        state.cachedUsersById[fixtureUser.id] = fixtureUser
        state.socketStatus = .connected
        state.isLoadingOverview = false

        var correspondenceTimeControl =
            TimeControlSpeed.correspondence.defaultTimeOptions[0]
                .timeControlObject
        correspondenceTimeControl.pauseOnWeekends = true
        let preferredSettings = [
            OGSChallengeTemplate(
                game: OGSChallengeTemplate.GameDetail(
                    width: 9,
                    height: 9,
                    ranked: true,
                    handicap: -1,
                    disableAnalysis: false,
                    name: "Live 9×9",
                    rules: .japanese,
                    timeControl:
                        TimeControlSpeed.live.defaultTimeOptions[0]
                            .timeControlObject
                )
            ),
            OGSChallengeTemplate(
                game: OGSChallengeTemplate.GameDetail(
                    width: 19,
                    height: 19,
                    ranked: true,
                    handicap: -1,
                    disableAnalysis: false,
                    name: "Correspondence 19×19",
                    rules: .japanese,
                    timeControl: correspondenceTimeControl
                )
            ),
        ]
        precondition(
            preferredSettings.count == 2
                && preferredSettings.map { $0.game.timeControl.speed }
                    == [.live, .correspondence],
            "The App Store fixture must contain one live and one correspondence preferred setting."
        )
        state.preferredGameSettings = Set(preferredSettings)

        let preferredSettingsEncoder = JSONEncoder()
        preferredSettingsEncoder.keyEncodingStrategy = .convertToSnakeCase
        let preferredSettingsData = try! preferredSettingsEncoder.encode(
            preferredSettings
        )
        guard let preferredSettingsJSON = try! JSONSerialization.jsonObject(
            with: preferredSettingsData
        ) as? [[String: Any]] else {
            preconditionFailure(
                "The App Store preferred settings could not be encoded."
            )
        }
        precondition(
            OGSRemoteSettingKey<[OGSChallengeTemplate]>
                .preferredGameSettings
                .saveIfValid(
                    settings: preferredSettingsJSON,
                    replication: .RemoteOverwritesLocal,
                    modified: Date(timeIntervalSince1970: 1_720_000_000),
                    preferences: userDefaults
                ),
            "The App Store preferred settings could not be persisted."
        )

        func applyProfileData(
            _ fixture: AppStoreScreenshotProfileGame,
            to gameData: inout OGSGame
        ) {
            gameData.gameId = fixture.id
            gameData.gameName = fixture.gameName
            gameData.players = OGSGame.Players(
                black: fixture.blackPlayer,
                white: fixture.whitePlayer
            )
            gameData.blackPlayerId = fixture.blackPlayer.id
            gameData.whitePlayerId = fixture.whitePlayer.id
            gameData.width = 19
            gameData.height = 19
            gameData.handicap = fixture.handicap
            gameData.initialPlayer = .black
            gameData.initialState = OGSGame.InitialState(black: "", white: "")
            gameData.komi = fixture.komi
            gameData.ranked = true
            gameData.rules = fixture.rules
            gameData.moves = fixture.moves

            gameData.playerPool = nil
            gameData.rengo = false
            gameData.rengoTeams = nil
            gameData.rengoCasualMode = nil
            gameData.tournamentId = nil
            gameData.ladderId = nil
            gameData.pauseControl = nil
            gameData.undoRequested = nil
            gameData.removed = nil
            gameData.score = nil
            gameData.autoScoringDone = nil
            for moveIndex in gameData.moves.indices {
                gameData.moves[moveIndex].extra = nil
            }

            gameData.clock.blackPlayerId = fixture.blackPlayer.id
            gameData.clock.whitePlayerId = fixture.whitePlayer.id
            gameData.clock.pausedTime = nil
            gameData.clock.pauseControl = nil
            gameData.clock.blackTimeUntilAutoResign = nil
            gameData.clock.whiteTimeUntilAutoResign = nil
            gameData.clock.autoResignTime = [:]

            for player in [fixture.blackPlayer, fixture.whitePlayer] {
                state.cachedUsersById[player.id] = player
            }
        }

        func makeFixtureGame(
            from fixture: AppStoreScreenshotProfileGame,
            clock: AppStoreScreenshotActiveClockFixture
        ) -> Game {
            guard var gameData = TestData.Ongoing19x19wBot2.gameData else {
                preconditionFailure("The bundled UI-test game fixture must contain game data.")
            }

            applyProfileData(fixture, to: &gameData)
            precondition(
                gameData.moves.count < fixture.sourceMoveCount,
                "Active App Store fixtures must use an early position from a finished profile game."
            )
            gameData.phase = .play
            gameData.outcome = nil
            gameData.winner = nil

            gameData.timeControl = TimeControlSystem
                .Simple(perMove: clock.secondsPerMove)
                .timeControlObject

            let currentPlayerColor: StoneColor = gameData.moves.count.isMultiple(of: 2)
                ? .black
                : .white
            gameData.clock.currentPlayerColor = currentPlayerColor
            gameData.clock.currentPlayerId = currentPlayerColor == .black
                ? gameData.players.black.id
                : gameData.players.white.id
            gameData.clock.blackPlayerId = gameData.players.black.id
            gameData.clock.whitePlayerId = gameData.players.white.id

            gameData.clock.blackTime = ThinkingTime(
                thinkingTime: Double(clock.blackTimeRemaining),
                thinkingTimeLeft: Double(clock.blackTimeRemaining)
            )
            gameData.clock.whiteTime = ThinkingTime(
                thinkingTime: Double(clock.whiteTimeRemaining),
                thinkingTimeLeft: Double(clock.whiteTimeRemaining)
            )
            let currentPlayerTimeRemaining = Double(
                clock.timeRemaining(for: currentPlayerColor)
            )
            let now = Date().timeIntervalSince1970 * 1_000
            gameData.clock.lastMoveTime = now
            gameData.clock.expiration =
                now + currentPlayerTimeRemaining * 1_000
            gameData.clock.timeUntilExpiration = currentPlayerTimeRemaining
            gameData.clock.pausedTime = nil
            gameData.clock.pauseControl = nil
            gameData.clock.started = true

            let game = Game(ogsGame: gameData)
            game.ogsRawData = [:]
            return game
        }

        func move(
            fromGoCoordinate coordinate: String,
            boardSize: Int = 19
        ) -> Move {
            let columns = Array("ABCDEFGHJKLMNOPQRST")
            let normalizedCoordinate = coordinate.uppercased()
            guard
                let columnLabel = normalizedCoordinate.first,
                let column = columns.firstIndex(of: columnLabel),
                let rowNumber = Int(normalizedCoordinate.dropFirst()),
                column < boardSize,
                (1...boardSize).contains(rowNumber)
            else {
                preconditionFailure(
                    "Invalid \(boardSize)x\(boardSize) Go coordinate: \(coordinate)"
                )
            }
            return .placeStone(boardSize - rowNumber, column)
        }

        @discardableResult
        func addAnalysisVariation(
            to game: Game,
            fromMoveNumber: Int,
            coordinates: [String]
        ) -> BoardPosition {
            guard var position = game.positionByLastMoveNumber[fromMoveNumber] else {
                preconditionFailure(
                    "Missing analysis base position at move \(fromMoveNumber)."
                )
            }
            for coordinate in coordinates {
                do {
                    position = try game.makeMove(
                        move: move(fromGoCoordinate: coordinate),
                        fromAnalyticsPosition: position
                    )
                } catch {
                    preconditionFailure(
                        "Illegal analysis move \(coordinate): \(error)"
                    )
                }
            }
            return position
        }

        func makeChatLine(
            id: String,
            moveNumber: Int,
            body: String,
            user: OGSUser
        ) -> OGSChatLine {
            let payload: [String: Any] = [
                "channel": "main",
                "line": [
                    "body": body,
                    "chat_id": id,
                    "date": 1_720_000_000,
                    "move_number": moveNumber,
                    "player_id": user.id,
                    "professional": false,
                    "ranking": user.ranking ?? 30,
                    "ui_class": "",
                    "username": user.username,
                ],
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try! decoder.decode(OGSChatLine.self, from: data)
        }

        let copperKoiClock = AppStoreScreenshotActiveClockFixture(
            daysPerMove: 2,
            blackTimeRemaining: 38_820,  // 10h 47m
            whiteTimeRemaining: 112_320  // 31h 12m
        )
        let cobaltFoxClock = AppStoreScreenshotActiveClockFixture(
            daysPerMove: 3,
            blackTimeRemaining: 66_360,  // 18h 26m
            whiteTimeRemaining: 184_080  // 51h 08m
        )
        let indigoCraneClock = AppStoreScreenshotActiveClockFixture(
            daysPerMove: 3,
            blackTimeRemaining: 207_780,  // 57h 43m
            whiteTimeRemaining: 80_340  // 22h 19m
        )
        let fixtureGame = makeFixtureGame(
            from: AppStoreScreenshotProfileData.copperKoiOpening,
            clock: copperKoiClock
        )
        precondition(
            fixtureGame.ogsID == SurroundUITestContract.screenshotPrimaryGameID
        )
        let analysisBaseMoveNumber =
            SurroundUITestContract.screenshotAnalysisBaseMoveNumber
        addAnalysisVariation(
            to: fixtureGame,
            fromMoveNumber: analysisBaseMoveNumber,
            coordinates: ["C14", "C12"]
        )
        addAnalysisVariation(
            to: fixtureGame,
            fromMoveNumber: analysisBaseMoveNumber,
            coordinates: ["B6", "B7", "B5", "C8"]
        )
        let selectedAnalysisPosition = addAnalysisVariation(
            to: fixtureGame,
            fromMoveNumber: analysisBaseMoveNumber,
            coordinates: ["B6", "B7", "B5", "C14", "F17"]
        )
        precondition(
            selectedAnalysisPosition.lastMoveNumber
                == SurroundUITestContract.screenshotAnalysisSelectedMoveNumber
        )
        precondition(
            selectedAnalysisPosition.lastMove == .placeStone(
                SurroundUITestContract.screenshotAnalysisSelectedRow,
                SurroundUITestContract.screenshotAnalysisSelectedColumn
            )
        )
        fixtureGame.chatLog = [
            makeChatLine(
                id: "app-store-chat-1",
                moveNumber: 42,
                body: "Good luck — have a great game!",
                user: fixtureGame.whitePlayer!
            ),
            makeChatLine(
                id: "app-store-chat-2",
                moveNumber: 45,
                body: "Thanks, you too.",
                user: fixtureUser
            ),
        ]

        let waitingGame1 = makeFixtureGame(
            from: AppStoreScreenshotProfileData.cobaltFoxOpening,
            clock: cobaltFoxClock
        )
        let additionalYourMoveGame = makeFixtureGame(
            from: AppStoreScreenshotProfileData.indigoCraneOpening,
            clock: indigoCraneClock
        )
        precondition(
            additionalYourMoveGame.clock?.currentPlayerId == fixtureUser.id
                && additionalYourMoveGame.gameData?.timeControl.speed
                    == .correspondence
        )
        for game in [
            fixtureGame,
            additionalYourMoveGame,
            waitingGame1,
        ] {
            state.activeGames[game.ogsID!] = game
        }
        precondition(
            state.activeGames.count == 3
                && state.activeGames.values.filter {
                    $0.clock?.currentPlayerId == fixtureUser.id
                }.count == 2,
            "The App Store fixture must contain two games in Your move and one waiting game."
        )

        let widgetNow = Date()
        let widgetActiveGames: [[String: Any]] = [
            [
                "id": AppStoreScreenshotProfileData.copperKoiOpening.id,
                "json": AppStoreScreenshotProfileData.copperKoiOpening
                    .widgetGameJSON(
                        clock: copperKoiClock,
                        currentPlayerID: fixtureGame.clock!.currentPlayerId,
                        now: widgetNow
                    ),
            ],
            [
                "id": AppStoreScreenshotProfileData.indigoCraneOpening.id,
                "json": AppStoreScreenshotProfileData.indigoCraneOpening
                    .widgetGameJSON(
                        clock: indigoCraneClock,
                        currentPlayerID:
                            additionalYourMoveGame.clock!.currentPlayerId,
                        now: widgetNow
                    ),
            ],
            [
                "id": AppStoreScreenshotProfileData.cobaltFoxOpening.id,
                "json": AppStoreScreenshotProfileData.cobaltFoxOpening
                    .widgetGameJSON(
                        clock: cobaltFoxClock,
                        currentPlayerID: waitingGame1.clock!.currentPlayerId,
                        now: widgetNow
                    ),
            ],
        ]
        let widgetOverviewData = try! JSONSerialization.data(
            withJSONObject: [
                "active_games": widgetActiveGames,
            ]
        )
        let widgetFixture = AppStoreScreenshotWidgetFixture(
            schemaVersion: AppStoreScreenshotWidgetFixture
                .currentSchemaVersion,
            validUntil: widgetNow.addingTimeInterval(6 * 60 * 60),
            userID: fixtureUser.id,
            localeIdentifier: Locale.current.identifier,
            overviewData: widgetOverviewData
        )
        guard let sharedWidgetDefaults = UserDefaults(
            suiteName: userDefaultsSuite
        ) else {
            preconditionFailure(
                "The widget screenshot app-group preferences are unavailable."
            )
        }
        sharedWidgetDefaults[.appStoreScreenshotWidgetFixture] = widgetFixture
        WidgetCenter.shared.reloadTimelines(
            ofKind: SurroundWidgetContract.correspondenceGamesKind
        )

        func makeHistoryGame(
            from fixture: AppStoreScreenshotProfileGame
        ) -> Game {
            guard var gameData = TestData.Scored19x19Korean.gameData else {
                preconditionFailure("The bundled history fixture must contain game data.")
            }

            applyProfileData(fixture, to: &gameData)
            precondition(
                gameData.moves.count == fixture.sourceMoveCount,
                "Finished App Store fixtures must retain the complete profile game."
            )
            gameData.phase = .finished
            gameData.outcome = fixture.outcome
            gameData.winner = fixture.winnerID

            let nextPlayerColor: StoneColor = gameData.moves.count.isMultiple(of: 2)
                ? .black
                : .white
            gameData.clock.currentPlayerColor = nextPlayerColor
            gameData.clock.currentPlayerId = nextPlayerColor == .black
                ? gameData.players.black.id
                : gameData.players.white.id

            let game = Game(ogsGame: gameData)
            game.ogsRawData = [:]
            return game
        }

        let finishedGames = [
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.cedarWaveFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.harborMistFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.friendlyFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.silverBambooFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.jadeLanternFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.quietPineFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.moonBridgeFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.autumnPathFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.amberKiteFinished
            ),
            makeHistoryGame(
                from: AppStoreScreenshotProfileData.riverStoneFinished
            ),
        ]
        precondition(
            finishedGames.count == 10,
            "The App Store home fixture must contain ten finished games."
        )
        state.finishedGamesSnapshot = finishedGames

        func makeOpenChallenge(
            id: Int,
            playerID: Int,
            username: String,
            rank: Double,
            gameName: String,
            daysPerMove: Int,
            rengo: Bool = false
        ) -> OGSSeekgraphChallenge {
            var challenge = rengo
                ? OGSChallengeSampleData.sampleRengoChallenge
                : OGSChallengeSampleData.sampleOpenChallenge
            challenge.id = id
            challenge.challenger = OGSUser(
                username: username,
                id: playerID,
                ranking: rank
            )
            challenge.game.id = id + 10_000
            challenge.game.name = gameName
            challenge.game.timeControl = TimeControlSystem
                .Simple(perMove: daysPerMove * 86_400)
                .timeControlObject
            challenge.game.rengo = rengo
            challenge.game.ranked = !rengo
            challenge.game.minRank = 0
            challenge.game.maxRank = 40
            if rengo {
                challenge.game.rengoCasualMode = true
                challenge.game.rengoAutoStart = 6
                challenge.game.rengoBlackTeam = [playerID]
                challenge.game.rengoWhiteTeam = []
                challenge.game.rengoNominees = []
                challenge.game.rengoParticipants = [playerID]
            }
            return challenge
        }

        let standardChallengePlayers = [
            "BambooPath", "MistyMountain", "QuietPond", "GoldenReed",
            "PineNeedle", "RainyGrove", "StoneHarbor", "MapleTrail",
            "CloudValley", "WillowBrook",
        ]
        let rengoChallengePlayers = [
            "TeamKoi", "FourCorners", "SharedLiberty", "TwinDragons",
            "RiverTeam", "MoonAlliance", "BambooCircle", "CloudPartners",
            "StoneChorus", "GardenRengo", "FriendlyTeam", "KoCollaborative",
            "TeaHouseTeam", "LanternCircle", "PineCollective", "JadePartners",
            "HarborRengo", "MountainTeam", "AutumnCircle", "QuietAlliance",
        ]

        let standardChallenges = standardChallengePlayers.enumerated().map {
            index, username in
            makeOpenChallenge(
                id: 91_001 + index,
                playerID: 801_001 + index,
                username: username,
                rank: Double(23 + index),
                gameName: [
                    "Relaxed 19×19", "Friendly Match", "Thoughtful 19×19",
                    "Evening Game", "Long Correspondence",
                ][index % 5],
                daysPerMove: 2 + index % 4
            )
        }
        let rengoChallenges = rengoChallengePlayers.enumerated().map {
            index, username in
            makeOpenChallenge(
                id: 92_001 + index,
                playerID: 802_001 + index,
                username: username,
                rank: Double(20 + index % 13),
                gameName: [
                    "Casual Rengo", "Team 19×19", "Rengo Gathering",
                    "Friendly Team Game", "Correspondence Rengo",
                ][index % 5],
                daysPerMove: 1 + index % 5,
                rengo: true
            )
        }
        let openChallenges = standardChallenges + rengoChallenges
        precondition(
            standardChallenges.count == 10
                && rengoChallenges.count == 20
                && openChallenges.count == 30,
            "The App Store fixture must resemble the OGS waiting-game pool."
        )
        for challenge in openChallenges {
            state.eligibleOpenChallengeById[challenge.id] = challenge
            if let challenger = challenge.challenger {
                state.cachedUsersById[challenger.id] = challenger
            }
        }

        func makePublicGame(
            from source: Game,
            prefixMoveCount: Int,
            gameID: Int,
            gameName: String,
            blackName: String,
            blackRank: Double,
            whiteName: String,
            whiteRank: Double,
            playerIDBase: Int,
            clock: AppStoreScreenshotPublicClockFixture
        ) -> Game {
            guard var gameData = source.gameData else {
                preconditionFailure("The bundled public-game fixture must contain game data.")
            }
            precondition(
                source.width == 19
                    && source.height == 19
                    && gameData.handicap == 0
                    && gameData.initialPlayer == .black
                    && prefixMoveCount > 0
                    && prefixMoveCount < gameData.moves.count,
                "Public games must use an early position from a standard 19×19 profile game."
            )
            gameData.gameId = gameID
            gameData.moves = Array(gameData.moves.prefix(prefixMoveCount))
            while gameData.moves.last?.move == .pass {
                gameData.moves.removeLast()
            }
            let currentPlayerColor: StoneColor = gameData.moves.count.isMultiple(of: 2)
                ? .black
                : .white

            let blackPlayer = OGSUser(
                username: blackName,
                id: playerIDBase,
                ranking: blackRank
            )
            let whitePlayer = OGSUser(
                username: whiteName,
                id: playerIDBase + 1,
                ranking: whiteRank
            )
            gameData.players = OGSGame.Players(
                black: blackPlayer,
                white: whitePlayer
            )
            gameData.blackPlayerId = blackPlayer.id
            gameData.whitePlayerId = whitePlayer.id
            gameData.gameName = gameName
            gameData.playerPool = nil
            gameData.rengo = false
            gameData.rengoTeams = nil
            gameData.rengoCasualMode = nil
            for moveIndex in gameData.moves.indices {
                gameData.moves[moveIndex].extra = nil
            }

            gameData.phase = .play
            gameData.outcome = nil
            gameData.winner = nil
            gameData.removed = nil
            gameData.score = nil
            gameData.autoScoringDone = nil
            gameData.undoRequested = nil
            gameData.pauseControl = nil

            gameData.timeControl = clock.timeControl.timeControlObject
            let currentPlayerID = currentPlayerColor == .black
                ? blackPlayer.id
                : whitePlayer.id
            if currentPlayerColor == .black {
                gameData.clock.blackTime = clock.currentPlayerTime
                gameData.clock.whiteTime = clock.opponentTime
            } else {
                gameData.clock.blackTime = clock.opponentTime
                gameData.clock.whiteTime = clock.currentPlayerTime
            }
            let now = Date().timeIntervalSince1970 * 1_000
            gameData.clock.currentPlayerColor = currentPlayerColor
            gameData.clock.currentPlayerId = currentPlayerID
            gameData.clock.blackPlayerId = blackPlayer.id
            gameData.clock.whitePlayerId = whitePlayer.id
            gameData.clock.lastMoveTime = now
            gameData.clock.pausedTime = nil
            gameData.clock.started = true
            gameData.clock.pauseControl = nil
            let currentTimeLeft = clock.currentPlayerTime.timeLeft!
            gameData.clock.expiration = now + currentTimeLeft * 1_000
            gameData.clock.timeUntilExpiration = currentTimeLeft
            gameData.clock.blackTimeUntilAutoResign = nil
            gameData.clock.whiteTimeUntilAutoResign = nil
            gameData.clock.autoResignTime = [:]

            state.cachedUsersById[blackPlayer.id] = blackPlayer
            state.cachedUsersById[whitePlayer.id] = whitePlayer

            let game = Game(ogsGame: gameData)
            precondition(game.currentPosition.nextToMove == currentPlayerColor)
            game.ogsRawData = [:]
            return game
        }

        let publicGames = [
            makePublicGame(
                from: finishedGames[0],
                prefixMoveCount: 47,
                gameID: SurroundUITestContract.screenshotPublicGameID,
                gameName: "Friendly 19×19",
                blackName: "MapleLeaf",
                blackRank: 31,
                whiteName: "SilverPine",
                whiteRank: 25,
                playerIDBase: 901_001,
                clock: .byoYomi(
                    mainTime: 10 * 60,
                    periods: 5,
                    periodTime: 30,
                    currentMainTimeLeft: 6 * 60 + 47,
                    currentPeriodsLeft: 5,
                    currentPeriodTimeLeft: 30,
                    opponentMainTimeLeft: 8 * 60 + 12,
                    opponentPeriodsLeft: 5,
                    opponentPeriodTimeLeft: 30
                )
            ),
            makePublicGame(
                from: finishedGames[1],
                prefixMoveCount: 62,
                gameID: 95_100_002,
                gameName: "Creative 19×19",
                blackName: "DuskBridge",
                blackRank: 27,
                whiteName: "QuietHarbor",
                whiteRank: 29,
                playerIDBase: 901_003,
                clock: .fischer(
                    initialTime: 2 * 60,
                    timeIncrement: 30,
                    maxTime: 5 * 60,
                    currentTimeLeft: 3 * 60 + 42,
                    opponentTimeLeft: 2 * 60 + 7
                )
            ),
            makePublicGame(
                from: finishedGames[2],
                prefixMoveCount: 75,
                gameID: 95_100_003,
                gameName: "Fast 19×19",
                blackName: "StoneLantern",
                blackRank: 23,
                whiteName: "CloudPath",
                whiteRank: 26,
                playerIDBase: 901_005,
                clock: .byoYomi(
                    mainTime: 5 * 60,
                    periods: 3,
                    periodTime: 20,
                    currentMainTimeLeft: 0,
                    currentPeriodsLeft: 2,
                    currentPeriodTimeLeft: 13,
                    opponentMainTimeLeft: 0,
                    opponentPeriodsLeft: 1,
                    opponentPeriodTimeLeft: 7
                )
            ),
            makePublicGame(
                from: finishedGames[3],
                prefixMoveCount: 88,
                gameID: 95_100_004,
                gameName: "Life & Death 19×19",
                blackName: "JadeGarden",
                blackRank: 30,
                whiteName: "BlueHeron",
                whiteRank: 28,
                playerIDBase: 901_007,
                clock: .canadian(
                    mainTime: 10 * 60,
                    periodTime: 3 * 60,
                    stonesPerPeriod: 10,
                    currentMainTimeLeft: 0,
                    currentBlockTimeLeft: 2 * 60 + 11,
                    currentMovesLeft: 7,
                    opponentMainTimeLeft: 1 * 60 + 34,
                    opponentBlockTimeLeft: 3 * 60,
                    opponentMovesLeft: 10
                )
            ),
            makePublicGame(
                from: finishedGames[4],
                prefixMoveCount: 101,
                gameID: 95_100_005,
                gameName: "Evening 19×19",
                blackName: "CedarGate",
                blackRank: 26,
                whiteName: "MorningStar",
                whiteRank: 30,
                playerIDBase: 901_009,
                clock: .absolute(
                    totalTime: 15 * 60,
                    currentTimeLeft: 4 * 60 + 53,
                    opponentTimeLeft: 7 * 60 + 28
                )
            ),
            makePublicGame(
                from: finishedGames[5],
                prefixMoveCount: 114,
                gameID: 95_100_006,
                gameName: "Open Board",
                blackName: "RiverPebble",
                blackRank: 24,
                whiteName: "PineShadow",
                whiteRank: 27,
                playerIDBase: 901_011,
                clock: .fischer(
                    initialTime: 5 * 60,
                    timeIncrement: 10,
                    maxTime: 10 * 60,
                    currentTimeLeft: 6 * 60 + 14,
                    opponentTimeLeft: 4 * 60 + 39
                )
            ),
            makePublicGame(
                from: finishedGames[6],
                prefixMoveCount: 127,
                gameID: 95_100_007,
                gameName: "Quick Lunch Game",
                blackName: "TeaGarden",
                blackRank: 20,
                whiteName: "KoiPond",
                whiteRank: 22,
                playerIDBase: 901_013,
                clock: .simple(
                    perMove: 60,
                    currentTimeLeft: 23
                )
            ),
            makePublicGame(
                from: finishedGames[7],
                prefixMoveCount: 140,
                gameID: 95_100_008,
                gameName: "Serious 19×19",
                blackName: "GranitePeak",
                blackRank: 32,
                whiteName: "WhiteCrane",
                whiteRank: 31,
                playerIDBase: 901_015,
                clock: .canadian(
                    mainTime: 5 * 60,
                    periodTime: 2 * 60,
                    stonesPerPeriod: 10,
                    currentMainTimeLeft: 0,
                    currentBlockTimeLeft: 1 * 60 + 6,
                    currentMovesLeft: 4,
                    opponentMainTimeLeft: 0,
                    opponentBlockTimeLeft: 38,
                    opponentMovesLeft: 2
                )
            ),
            makePublicGame(
                from: finishedGames[8],
                prefixMoveCount: 149,
                gameID: 95_100_009,
                gameName: "Tesuji Practice",
                blackName: "LotusStone",
                blackRank: 25,
                whiteName: "NorthWind",
                whiteRank: 29,
                playerIDBase: 901_017,
                clock: .byoYomi(
                    mainTime: 30,
                    periods: 5,
                    periodTime: 5,
                    currentMainTimeLeft: 18,
                    currentPeriodsLeft: 5,
                    currentPeriodTimeLeft: 5,
                    opponentMainTimeLeft: 0,
                    opponentPeriodsLeft: 3,
                    opponentPeriodTimeLeft: 3
                )
            ),
            makePublicGame(
                from: finishedGames[9],
                prefixMoveCount: 163,
                gameID: 95_100_010,
                gameName: "Weekend Match",
                blackName: "BlueSpruce",
                blackRank: 28,
                whiteName: "RedMaple",
                whiteRank: 27,
                playerIDBase: 901_019,
                clock: .absolute(
                    totalTime: 10 * 60,
                    currentTimeLeft: 1 * 60 + 41,
                    opponentTimeLeft: 3 * 60 + 16
                )
            ),
        ]
        let publicTimeControls = publicGames.compactMap {
            $0.gameData?.timeControl
        }
        precondition(
            publicGames.count == 10
                && Set(publicGames.compactMap(\.ogsID)).count == 10
                && publicGames.allSatisfy {
                    $0.width == 19 && $0.height == 19
                }
                && Set(publicTimeControls).count == 10
                && Set(publicTimeControls.map { $0.timeControl }).count == 5
                && publicTimeControls.allSatisfy {
                    $0.speed != .correspondence
                }
                && publicTimeControls.contains {
                    $0.speed == .blitz
                },
            "The App Store fixture must contain ten unique public games with varied clocks."
        )
        precondition(
            publicGames.first?.ogsID == SurroundUITestContract.screenshotPublicGameID
        )
        for publicGame in publicGames {
            state.publicGames[publicGame.ogsID!] = publicGame
        }
        state.sortedPublicGames = publicGames

        return makeService(from: state)
    }
    #endif
}
