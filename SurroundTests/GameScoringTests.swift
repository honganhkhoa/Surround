//
//  GameScoringTests.swift
//  SurroundTests
//

import XCTest
import Combine

final class GameScoringTests: XCTestCase {
    private struct ScoringRules {
        var scoreTerritory = true
        var scoreStones = false
        var scorePrisoners = true
        var scoreHandicap = false
        var agaHandicapScoring = false

        // Territory rules (Japanese/Korean): territory + prisoners, handicap stones are free.
        static let territory = ScoringRules()
        // Area rules (Chinese/AGA): stones + territory, prisoners ignored, handicap compensates white.
        static let area = ScoringRules(scoreStones: true, scorePrisoners: false, scoreHandicap: true)
    }

    func testScoringWorksOnRectangularBoards() throws {
        let wideBoard = [
            "-b---w-",
            "-b---w-",
            "-b---w-",
            "-b---w-",
            "-b---w-"
        ]
        let wide = try makeGame(visualStrings: wideBoard, rules: .territory, komi: 6.5)
        BoardPositionTests.assertPositionEqual(position: wide.currentPosition, visualStrings: wideBoard)

        let wideScore = try XCTUnwrap(wide.computeScore())
        XCTAssertEqual(wideScore.black.territory, 5)
        XCTAssertEqual(wideScore.white.territory, 5)
        XCTAssertEqual(wideScore.black.total, 5)
        XCTAssertEqual(wideScore.white.total, 11.5)

        let tall = try makeGame(
            visualStrings: [
                "-----",
                "bbbbb",
                "-----",
                "-----",
                "-----",
                "wwwww",
                "-----"
            ],
            rules: .territory,
            komi: 6.5
        )
        let tallScore = try XCTUnwrap(tall.computeScore())
        XCTAssertEqual(tallScore.black.territory, 5)
        XCTAssertEqual(tallScore.white.territory, 5)
        XCTAssertEqual(tallScore.black.total, 5)
        XCTAssertEqual(tallScore.white.total, 11.5)
    }

    func testTerritoryScoringCountsTerritoryPrisonersAndDeadStones() throws {
        let game = try makeGame(
            visualStrings: [
                "--bw-",
                "--bw-",
                "--bwb",
                "--bw-",
                "--bw-"
            ],
            rules: .territory,
            komi: 6.5,
            removed: "ec" // the dead black stone at row 2, column 4
        )
        game.currentPosition.captures[.black] = 2

        let score = try XCTUnwrap(game.computeScore())

        XCTAssertEqual(score.black.territory, 10)
        XCTAssertEqual(score.black.prisoners, 2)
        XCTAssertEqual(score.black.stones, 0)
        XCTAssertEqual(score.black.scoringPositions.count, 10)
        XCTAssertEqual(score.black.total, 12)

        XCTAssertEqual(score.white.territory, 5)
        XCTAssertEqual(score.white.prisoners, 1)
        XCTAssertEqual(score.white.stones, 0)
        XCTAssertTrue(score.white.scoringPositions.contains([2, 4]))
        XCTAssertEqual(score.white.total, 12.5)
    }

    func testAreaScoringCountsStonesAndIgnoresCaptures() throws {
        let game = try makeGame(
            visualStrings: [
                "--bw-",
                "--bw-",
                "--bw-",
                "--bw-",
                "--bw-"
            ],
            rules: .area,
            komi: 7.5
        )
        game.currentPosition.captures[.black] = 3
        game.currentPosition.captures[.white] = 4

        let score = try XCTUnwrap(game.computeScore())

        XCTAssertEqual(score.black.territory, 10)
        XCTAssertEqual(score.black.stones, 5)
        XCTAssertEqual(score.black.prisoners, 0)
        XCTAssertEqual(score.black.scoringPositions.count, 15)
        XCTAssertEqual(score.black.total, 15)

        XCTAssertEqual(score.white.territory, 5)
        XCTAssertEqual(score.white.stones, 5)
        XCTAssertEqual(score.white.prisoners, 0)
        XCTAssertEqual(score.white.scoringPositions.count, 10)
        XCTAssertEqual(score.white.total, 17.5)
    }

    func testHandicapScoring() throws {
        let board = [
            "--bw-",
            "--bw-",
            "--bw-",
            "--bw-",
            "--bw-"
        ]

        let area = try makeGame(visualStrings: board, rules: .area, komi: 0.5, handicap: 3)
        let areaScore = try XCTUnwrap(area.computeScore())
        XCTAssertEqual(areaScore.white.handicap, 3)
        XCTAssertEqual(areaScore.black.handicap, 0)
        XCTAssertEqual(areaScore.white.total, 13.5)
        XCTAssertEqual(areaScore.black.total, 15)

        var agaRules = ScoringRules.area
        agaRules.agaHandicapScoring = true
        let aga = try makeGame(visualStrings: board, rules: agaRules, komi: 0.5, handicap: 3)
        let agaScore = try XCTUnwrap(aga.computeScore())
        XCTAssertEqual(agaScore.white.handicap, 2)
        XCTAssertEqual(agaScore.white.total, 12.5)

        let agaEven = try makeGame(visualStrings: board, rules: agaRules, komi: 7.5, handicap: 0)
        let agaEvenScore = try XCTUnwrap(agaEven.computeScore())
        XCTAssertEqual(agaEvenScore.white.handicap, 0)
        XCTAssertEqual(agaEvenScore.white.total, 17.5)

        // Territory rules never add the handicap to the total.
        let territory = try makeGame(visualStrings: board, rules: .territory, komi: 6.5, handicap: 3)
        let territoryScore = try XCTUnwrap(territory.computeScore())
        XCTAssertEqual(territoryScore.white.handicap, 3)
        XCTAssertEqual(territoryScore.white.total, 11.5)
    }

    func testMutualLibertiesBetweenLiveGroupsScoreNothing() throws {
        let game = try makeGame(
            visualStrings: [
                "-b-w-",
                "-b-w-",
                "-b-w-",
                "-b-w-",
                "-b-w-"
            ],
            rules: .territory,
            komi: 6.5
        )

        let score = try XCTUnwrap(game.computeScore())

        XCTAssertEqual(score.black.territory, 5)
        XCTAssertEqual(score.white.territory, 5)
        XCTAssertFalse(score.black.scoringPositions.contains([2, 2]))
        XCTAssertFalse(score.white.scoringPositions.contains([2, 2]))
        XCTAssertEqual(score.black.total, 5)
        XCTAssertEqual(score.white.total, 11.5)
    }

    func testMarkedDamePointsAddNoTerritory() throws {
        let game = try makeGame(
            visualStrings: [
                "--bw-",
                "--bw-",
                "--bw-",
                "--bw-",
                "--bw-"
            ],
            rules: .territory,
            komi: 6.5,
            removed: "aa" // the empty point at row 0, column 0 is marked as dame
        )

        let score = try XCTUnwrap(game.computeScore())

        XCTAssertEqual(score.black.territory, 9)
        XCTAssertFalse(score.black.scoringPositions.contains([0, 0]))
        XCTAssertEqual(score.white.territory, 5)
        XCTAssertEqual(score.black.total, 9)
        XCTAssertEqual(score.white.total, 11.5)
    }

    func testComputeScoreRequiresGameData() {
        let game = Game(width: 5, height: 5, blackName: "black", whiteName: "white", gameId: .OGS(123))
        XCTAssertNil(game.computeScore())
    }

    func testScoringSnapshotOwnsBoardRemovalsAndCaptures() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        let position = game.currentPosition
        position.removedStones = [[0, 0]]
        position.captures[.black] = 2
        let snapshot = position.scoringSnapshot()

        position[0, 0] = .empty
        position.removedStones?.remove([0, 0])
        position.captures[.black] = 9

        let workerPosition = snapshot.makePosition()
        XCTAssertFalse(workerPosition === position)
        XCTAssertEqual(workerPosition[0, 0], .hasStone(.black))
        XCTAssertEqual(workerPosition.removedStones, [[0, 0]])
        XCTAssertEqual(workerPosition.captures[.black], 2)
    }

    func testQueuedScoringPublishesOnMainThreadWithUnchangedMath() throws {
        let game = try makeGame(
            visualStrings: ["--bw-", "--bw-", "--bwb", "--bw-", "--bw-"],
            rules: .territory, komi: 6.5, removed: "ec"
        )
        game.currentPosition.captures[.black] = 2
        var publicationWasOnMainThread = false
        let observation = game.currentPosition.$gameScores.dropFirst().sink { _ in
            publicationWasOnMainThread = Thread.isMainThread
        }
        defer { observation.cancel() }

        game.computeScoresAndUpdate()
        drainScoring(for: game)

        let score = try XCTUnwrap(game.currentPosition.gameScores)
        XCTAssertTrue(publicationWasOnMainThread)
        XCTAssertEqual(score.black.total, 12)
        XCTAssertEqual(score.white.total, 12.5)
        XCTAssertEqual(score.white.prisoners, 1)
    }

    func testQueuedScoringRejectsChangedRemovedStonesEvenWhenRestored() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        game.currentPosition.removedStones = []
        game.computeQueue.suspend()
        game.computeScoresAndUpdate()
        game.currentPosition.removedStones?.insert([0, 0])
        game.currentPosition.removedStones?.remove([0, 0])
        game.computeQueue.resume()
        drainScoring(for: game)

        XCTAssertNil(game.currentPosition.gameScores)
    }

    func testQueuedScoringRejectsChangedCapturesAndBoard() throws {
        for changesCaptures in [false, true] {
            let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
            game.computeQueue.suspend()
            game.computeScoresAndUpdate()
            if changesCaptures {
                game.currentPosition.captures[.black] = 2
            } else {
                game.currentPosition[0, 0] = .empty
            }
            game.computeQueue.resume()
            drainScoring(for: game)

            XCTAssertNil(game.currentPosition.gameScores)
        }
    }

    func testQueuedScoringNeverWritesToReplacementPosition() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        let original = game.currentPosition
        game.computeQueue.suspend()
        game.computeScoresAndUpdate()
        game.currentPosition = original.scoringSnapshot().makePosition()
        game.computeQueue.resume()
        drainScoring(for: game)

        XCTAssertNil(original.gameScores)
        XCTAssertNil(game.currentPosition.gameScores)
    }

    func testQueuedScoringCannotOverwriteRefreshedAuthoritativeScore() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        var authoritativeScore = try XCTUnwrap(game.computeScore())
        authoritativeScore.black.total = 42
        game.computeQueue.suspend()
        game.computeScoresAndUpdate()
        game.gameData?.score = authoritativeScore
        game.computeQueue.resume()
        drainScoring(for: game)

        XCTAssertEqual(game.currentPosition.gameScores?.black.total, 42)
    }

    func testQueuedScoringAndPlayCleanupCannotOverwriteNewPhase() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        var authoritativeScore = try XCTUnwrap(game.computeScore())
        authoritativeScore.black.total = 42
        game.computeQueue.suspend()
        game.computeScoresAndUpdate()
        game.gamePhase = .play
        game.gamePhase = .finished
        game.currentPosition.gameScores = authoritativeScore
        game.computeQueue.resume()
        drainScoring(for: game)

        XCTAssertEqual(game.currentPosition.gameScores?.black.total, 42)
    }

    func testResumingPlayResetsAutoScoringBeforePositionReplacement() throws {
        let game = try makeGame(visualStrings: ["bw", "--"], rules: .territory, komi: 6.5)
        game.autoScoringDone = true
        game.gamePhase = .play
        game.currentPosition = try game.currentPosition.makeMove(move: .pass)
        drainScoring(for: game)

        XCTAssertNil(game.autoScoringDone)
    }

    func testOnlyLatestRemovedStoneRequestPublishes() throws {
        let game = try makeGame(
            visualStrings: ["--bw-", "--bw-", "--bwb", "--bw-", "--bw-"],
            rules: .territory, komi: 6.5
        )
        var publications = 0
        let observation = game.currentPosition.$gameScores.dropFirst().sink { _ in
            publications += 1
        }
        defer { observation.cancel() }

        game.computeQueue.suspend()
        game.gamePhase = .stoneRemoval
        game.setRemovedStones(removedString: "ec")
        game.computeQueue.resume()
        drainScoring(for: game)

        XCTAssertEqual(publications, 1)
        XCTAssertEqual(game.currentPosition.gameScores?.white.prisoners, 1)
        XCTAssertEqual(game.currentPosition.gameScores?.white.total, 12.5)
    }

    func testScoringWhileObservedRemovedStonesChangeKeepsLatestResult() throws {
        let game = try makeGame(
            visualStrings: ["--bw-", "--bw-", "--bwb", "--bw-", "--bw-"],
            rules: .territory, komi: 6.5
        )
        var removalPublications = 0
        let observation = game.currentPosition.$removedStones.dropFirst().sink { _ in
            removalPublications += 1
            XCTAssertTrue(Thread.isMainThread)
        }
        defer { observation.cancel() }
        game.gamePhase = .stoneRemoval
        for index in 0..<50 {
            game.setRemovedStones(removedString: index.isMultiple(of: 2) ? "" : "ec")
        }
        drainScoring(for: game)

        XCTAssertEqual(removalPublications, 50)
        XCTAssertEqual(game.currentPosition.gameScores?.white.prisoners, 1)
        XCTAssertEqual(game.currentPosition.gameScores?.white.total, 12.5)
    }

    private func drainScoring(for game: Game) {
        // All workers have enqueued their main-thread completions before this
        // sentinel. No sleeps or assumptions about the worker's speed.
        game.computeQueue.sync {}
        let drained = expectation(description: "Scoring completions drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func makeGame(
        visualStrings: [String],
        rules: ScoringRules,
        komi: Double,
        handicap: Int = 0,
        removed: String? = nil,
        // Scoring happens on a finished (or stone-removal) game. Using "finished"
        // also avoids the "play"-phase didSet that asynchronously clears
        // removedStones, which would otherwise race the synchronous assertions.
        phase: String = "finished"
    ) throws -> Game {
        let height = visualStrings.count
        let width = visualStrings[0].count
        var blackPoints = Set<[Int]>()
        var whitePoints = Set<[Int]>()
        for (row, rowString) in visualStrings.enumerated() {
            for (column, character) in rowString.enumerated() {
                switch character {
                case "b":
                    blackPoints.insert([row, column])
                case "w":
                    whitePoints.insert([row, column])
                default:
                    break
                }
            }
        }

        var object: [String: Any] = [
            "allow_ko": false,
            "allow_self_capture": false,
            "allow_superko": true,
            "automatic_stone_removal": false,
            "white_must_pass_last": false,
            "black_player_id": 1,
            "white_player_id": 2,
            "disable_analysis": false,
            "free_handicap_placement": false,
            "width": width,
            "height": height,
            "game_id": 1,
            "game_name": "scoring-test",
            "handicap": handicap,
            "ranked": false,
            "rules": "japanese",
            "initial_player": "black",
            "initial_state": [
                "black": BoardPosition.positionString(fromPoints: blackPoints),
                "white": BoardPosition.positionString(fromPoints: whitePoints)
            ],
            "komi": komi,
            "moves": [[Int]](),
            "players": [
                "black": ["id": 1, "username": "black"],
                "white": ["id": 2, "username": "white"]
            ],
            "time_control": [
                "system": "simple",
                "time_control": "simple",
                "per_move": 86400,
                "speed": "correspondence",
                "pause_on_weekends": false
            ],
            "clock": [
                "black_player_id": 1,
                "white_player_id": 2,
                "current_player": 1,
                "last_move": 0,
                "black_time": ["thinking_time": 86400],
                "white_time": ["thinking_time": 86400]
            ],
            "score_handicap": rules.scoreHandicap,
            "score_passes": true,
            "score_prisoners": rules.scorePrisoners,
            "score_stones": rules.scoreStones,
            "score_territory": rules.scoreTerritory,
            "score_territory_in_seki": false,
            "strict_seki_mode": false,
            "aga_handicap_scoring": rules.agaHandicapScoring,
            "phase": phase
        ]
        if let removed = removed {
            object["removed"] = removed
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Game(ogsGame: try decoder.decode(OGSGame.self, from: data))
    }
}
