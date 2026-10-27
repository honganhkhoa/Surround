import XCTest

final class GameDetailClockStateTests: XCTestCase {
    private func game(_ system: TimeControlSystem = .ByoYomi(mainTime: 600, periods: 3, periodTime: 30)) throws -> Game {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-27053412", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.phase = .play
        data.outcome = nil
        data.winner = nil
        data.moves = []
        data.pauseControl = nil
        data.timeControl = system.timeControlObject
        data.clock.started = true
        data.clock.expiration = nil
        data.clock.timeUntilExpiration = nil
        data.clock.currentPlayerColor = .black
        data.clock.currentPlayerId = data.players.black.id
        data.clock.lastMoveTime = Date().timeIntervalSince1970 * 1_000
        data.clock.blackTime = ThinkingTime(thinkingTime: 272, thinkingTimeLeft: 272,
            periods: 3, periodsLeft: 3, periodTime: 30, periodTimeLeft: 30)
        data.clock.whiteTime = data.clock.blackTime
        let game = Game(ogsGame: data)
        game.clock = data.clock
        return game
    }

    /// v149: Duo Closed landscape's 126 pt column cards keep a detail line
    /// on one line while it fits at the 75% minimum scale; otherwise it takes
    /// a second line, broken at " · " when both parts fit. Only White's card
    /// (komi on its own line) needs the cards to grow; Black's has a spare line.
    func testColumnDetailLinesWrapOnlyWhenTheyDoNotFitAtTheMinimumScale() throws {
        let game = try game()
        let state = GameDetailClockState(game: game, color: .white)
        XCTAssertEqual(state.cardDetail(full: true)?.text, "+ 3× " + timeString(timeLeft: 30))
        XCTAssertTrue(state.showsColumnKomiLine)
        XCTAssertFalse(GameDetailClockState(game: game, color: .black).showsColumnKomiLine)
        // English "+ 3× 00:30 · 0 captures" fits the 126 pt card (scaled).
        let english = GameDetailColumnDetailLayouts(game: game, fullCards: true, cardWidth: 126, scale: 1)
        XCTAssertEqual(english, GameDetailColumnDetailLayouts())
        XCTAssertFalse(english.needsGrowth)
        // A narrower card stands in for a longer translation.
        let narrow = GameDetailColumnDetailLayouts(game: game, fullCards: true, cardWidth: 100, scale: 1)
        XCTAssertEqual(narrow.black, .splitAtSeparator)
        XCTAssertEqual(narrow.white, .splitAtSeparator)
        XCTAssertTrue(narrow.needsGrowth, "White's wrap needs the cards to grow")
        // A finished card has no komi line, so its wrap fits without growth.
        game.gamePhase = .finished
        XCTAssertFalse(GameDetailClockState(game: game, color: .white).showsColumnKomiLine)
        // Scoring has no detail line: its breakdown wraps by itself.
        game.gamePhase = .stoneRemoval
        XCTAssertNil(GameDetailClockState(game: game, color: .white).cardDetail(full: true))
        XCTAssertEqual(GameDetailColumnDetailLayouts(game: game, fullCards: true, cardWidth: 100, scale: 1),
                       GameDetailColumnDetailLayouts())
    }

    func testByoYomiUsesCurrentPeriodAndCountsOnlyFollowingPeriods() throws {
        let game = try game()
        game.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0, periods: 3, periodsLeft: 3,
            periodTime: 30, periodTimeLeft: 21)
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertTrue(state.canShowTimer)
        XCTAssertTrue(state.running)
        XCTAssertEqual(state.valueClock?.blackTime.thinkingTimeLeft, 21)
        XCTAssertEqual(state.inlineTimeDetail, "+2×")
        XCTAssertTrue(state.timeDetail.contains("2×"))
        XCTAssertFalse(state.suddenDeath)
    }

    func testSuddenDeathAppliesOnlyToFinalPeriodNotFinishedResult() throws {
        let game = try game()
        game.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0, periods: 1, periodsLeft: 1,
            periodTime: 30, periodTimeLeft: 8)
        var state = GameDetailClockState(game: game, color: .black)
        XCTAssertTrue(state.suddenDeath)
        XCTAssertEqual(state.inlineTimeDetail, "SD")
        XCTAssertTrue(state.accessibilityValue.contains("Sudden death"))
        game.gamePhase = .finished
        state = GameDetailClockState(game: game, color: .black)
        XCTAssertFalse(state.suddenDeath)
        XCTAssertFalse(state.running)
    }

    func testCanadianOvertimeSeparatesBlockTimeFromStonesRemaining() throws {
        let game = try game(.Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10))
        game.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0, movesLeft: 7, blockTimeLeft: 102)
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertTrue(state.canShowTimer)
        XCTAssertEqual(state.valueClock?.blackTime.thinkingTimeLeft, 102)
        XCTAssertEqual(state.timeDetail, "7 of 10 stones left")
        XCTAssertEqual(state.inlineTimeDetail, "7 stones")
        XCTAssertTrue(state.accessibilityValue.contains("7 of 10 stones left"))
    }

    func testFischerSimpleAndAbsoluteKeepTimeSystemMetadata() throws {
        for (system, detail) in [
            (TimeControlSystem.Fischer(initialTime: 600, timeIncrement: 30, maxTime: 600), "+ " + timeString(timeLeft: 30)),
            (.Simple(perMove: 30), "per move"),
            (.Absolute(totalTime: 600), "total")
        ] {
            let state = GameDetailClockState(game: try game(system), color: .black)
            XCTAssertTrue(state.canShowTimer)
            XCTAssertEqual(state.timeDetail, detail)
            XCTAssertTrue(state.accessibilityValue.contains(detail))
        }
    }

    func testDaySizedFischerIncrementsStayReadableInEveryClockSize() throws {
        for (increment, detail) in [(86_400, "+ 1d"), (172_800, "+ 2d"), (129_600, "+ 1d 12h")] {
            let state = GameDetailClockState(game: try game(.Fischer(
                initialTime: 259_200, timeIncrement: increment, maxTime: 604_800
            )), color: .black)
            XCTAssertEqual(state.timeDetail, detail)
            XCTAssertEqual(state.fullTimeDetail, detail)
            XCTAssertEqual(state.inlineTimeDetail, detail)
            XCTAssertTrue(state.accessibilityValue.contains(detail))
            XCTAssertEqual(state.valueClock?.blackTime.thinkingTimeLeft, 272,
                           "Formatting an increment must not alter the remaining clock value.")
        }
        let live = GameDetailClockState(game: try game(.Fischer(
            initialTime: 600, timeIncrement: 30, maxTime: 600
        )), color: .white)
        XCTAssertEqual(live.fullTimeDetail, "+ " + timeString(timeLeft: 30) + " per move")
    }

    func testUntimedKeepsCardsWithoutRunningIndicator() throws {
        let state = GameDetailClockState(game: try game(.None), color: .white)
        XCTAssertFalse(state.running)
        XCTAssertFalse(state.canShowTimer)
        XCTAssertEqual(state.unavailableTimeText, "No time limit")
        XCTAssertTrue(state.accessibilityValue.contains("komi"))
    }

    func testMissingClockFieldsProducePlaceholderRatherThanUnsafeTimer() throws {
        let game = try game()
        game.clock?.blackTime = ThinkingTime(thinkingTimeLeft: 0)
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertFalse(state.canShowTimer)
        XCTAssertEqual(state.unavailableTimeText, "—")
    }

    func testPreStartWithoutDeadlineUsesInertStartingValues() throws {
        let game = try game()
        game.clock?.started = false
        game.clock?.blackTime = ThinkingTime()
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertTrue(state.canShowTimer)
        XCTAssertFalse(state.running)
        XCTAssertFalse(state.firstMoveDeadline)
        XCTAssertEqual(state.valueClock?.blackTime.thinkingTimeLeft, 600)
        XCTAssertEqual(state.valueClock?.currentPlayerColor, .white)
        XCTAssertEqual(state.fullTimeDetail, state.timeDetail)
        XCTAssertTrue(state.fullTimeDetail.contains("3×"), "An unstarted clock still explains its starting overtime periods.")
        XCTAssertTrue(state.accessibilityValue.contains("Clock not started"))
        XCTAssertFalse(try XCTUnwrap(game.clock).started, "Displaying a starting value must not start the model clock.")
        XCTAssertNil(game.clock?.blackTime.thinkingTimeLeft)
    }

    func testPreStartKeepsEachTimeSystemsStartingMetadata() throws {
        let systems: [(TimeControlSystem, String)] = [
            (.Fischer(initialTime: 600, timeIncrement: 30, maxTime: 600), "+ " + timeString(timeLeft: 30) + " per move"),
            (.Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10), "+ " + timeString(timeLeft: 180) + " for 10 stones"),
            (.Simple(perMove: 30), "per move"),
            (.Absolute(totalTime: 600), "total")
        ]
        for (system, expectedDetail) in systems {
            let game = try game(system)
            game.clock?.started = false
            game.clock?.blackTime = ThinkingTime()
            game.clock?.whiteTime = ThinkingTime()
            for color in [StoneColor.black, .white] {
                let state = GameDetailClockState(game: game, color: color)
                XCTAssertTrue(state.canShowTimer)
                XCTAssertFalse(state.running)
                XCTAssertEqual(state.fullTimeDetail, expectedDetail)
            }
            XCTAssertNil(game.clock?.blackTime.thinkingTimeLeft)
            XCTAssertNil(game.clock?.whiteTime.thinkingTimeLeft)
        }
    }

    func testFirstMoveDeadlineHasMetadataOnlyForPlayerToMove() throws {
        let game = try game()
        game.clock?.started = false
        game.clock?.timeUntilExpiration = 45
        let black = GameDetailClockState(game: game, color: .black)
        let white = GameDetailClockState(game: game, color: .white)
        XCTAssertTrue(black.running)
        XCTAssertEqual(black.inlineTimeDetail, "first move")
        XCTAssertTrue(black.accessibilityValue.contains("first move"))
        XCTAssertFalse(white.running)
        XCTAssertEqual(white.inlineTimeDetail, "")
        XCTAssertTrue(white.accessibilityValue.contains("Waiting"))
    }

    func testPauseKeepsTimeButRetiresGlowAndExplainsReason() throws {
        let game = try game(.Fischer(initialTime: 259200, timeIncrement: 86400, maxTime: 604800))
        game.pauseControl = try JSONDecoder().decode(OGSPauseControl.self, from: Data(#"{"weekend":true}"#.utf8))
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertTrue(state.paused)
        XCTAssertFalse(state.running)
        XCTAssertEqual(state.pauseReason, "Weekend")
        XCTAssertTrue(state.accessibilityValue.contains("Weekend"))
    }

    func testPausedClockKeepsTheTurnBadgeOnTheSideToMove() throws {
        // Clock table states 5 and 10 (rule 18): the badge stays on the side
        // to move while paused; the clock does not run, so no glow.
        let game = try game(.Fischer(initialTime: 259200, timeIncrement: 86400, maxTime: 604800))
        game.pauseControl = try JSONDecoder().decode(OGSPauseControl.self, from: Data(#"{"weekend":true}"#.utf8))
        let service = OGSService(previewState: .init(user: game.blackPlayer, isLoggedIn: true))
        game.ogs = service
        let black = GameDetailClockState(game: game, color: .black)
        let white = GameDetailClockState(game: game, color: .white)
        XCTAssertEqual(black.badgeTitle(), "Your move")
        XCTAssertEqual(black.badgeTitle(narrow: true), "To move")
        XCTAssertEqual(white.badgeTitle(), "")
        XCTAssertFalse(black.running)
        XCTAssertTrue(black.accessibilityValue.hasPrefix("Your move"))
        XCTAssertTrue(black.accessibilityValue.contains("Weekend"))
        game.clock?.currentPlayerColor = .white
        game.clock?.currentPlayerId = game.whitePlayer?.id ?? 0
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).badgeTitle(), "Their move")
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "")
        XCTAssertFalse(GameDetailClockState(game: game, color: .white).running)
    }

    func testSingleTitleChipShowsTheViewerOrTheWinnerWhenNoOneIsToMove() throws {
        // Rule 14: with no one to move, the single title chip is the
        // viewer's own; spectators see the winner's, Black's without one.
        let game = try game()
        game.clock?.currentPlayerColor = .black
        XCTAssertEqual(GameDetailClockState.singleChipColor(game: game, clock: nil), .black)
        game.gamePhase = .finished
        game.gameData?.outcome = "resignation"
        game.gameData?.winner = game.whitePlayer?.id
        XCTAssertEqual(GameDetailClockState.singleChipColor(game: game, clock: nil), .white, "Spectator: the winner")
        let service = OGSService(previewState: .init(user: game.blackPlayer, isLoggedIn: true))
        game.ogs = service
        XCTAssertEqual(GameDetailClockState.singleChipColor(game: game, clock: nil), .black, "The viewer's own result")
        game.gameData?.winner = 0
        game.ogs = nil
        XCTAssertEqual(GameDetailClockState.singleChipColor(game: game, clock: nil), .black, "No winner: Black")
    }

    func testDisconnectionDeadlineReplacesGameClockAndGlow() throws {
        let game = try game()
        game.clock?.blackTimeUntilAutoResign = 291
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertEqual(state.autoResign, 291)
        XCTAssertFalse(state.running)
        XCTAssertTrue(state.accessibilityValue.contains("Disconnected"))
        XCTAssertTrue(state.accessibilityValue.contains(timeString(timeLeft: 291)))
    }

    func testScoringUsesCurrentScoreAndAcceptedRemovalSet() throws {
        let game = try game()
        game.autoScoringDone = true
        game.gamePhase = .stoneRemoval
        game.currentPosition.removedStones = [[0, 0]]
        game.removedStonesAccepted[.black] = [[0, 0]]
        game.removedStonesAccepted[.white] = []
        game.currentPosition.gameScores = scores(black: 60, white: 56.5)
        let black = GameDetailClockState(game: game, color: .black)
        let white = GameDetailClockState(game: game, color: .white)
        XCTAssertTrue(black.isScoring)
        XCTAssertFalse(black.running)
        XCTAssertTrue(black.accepted)
        XCTAssertFalse(white.accepted)
        XCTAssertEqual(white.score?.total, 56.5)
        game.currentPosition.removedStones = []
        XCTAssertFalse(GameDetailClockState(game: game, color: .black).accepted)
    }

    func testPointResultUsesServerFinalScoreRatherThanEstimate() throws {
        let game = try game()
        game.gameData?.phase = .finished
        game.gameData?.winner = game.blackPlayer?.id
        game.gameData?.outcome = "6.5 points"
        game.gameData?.score = scores(black: 63, white: 56.5)
        game.currentPosition.gameScores = scores(black: 90, white: 20)
        let black = GameDetailClockState(game: game, color: .black)
        let white = GameDetailClockState(game: game, color: .white)
        XCTAssertEqual(black.resultTitle, "Won")
        XCTAssertEqual(black.resultDetail, "63 points")
        XCTAssertEqual(white.resultTitle, "Lost")
        XCTAssertEqual(white.resultDetail, "56.5 points")
    }

    func testCanceledAndAnnulledOverrideServerWinner() throws {
        let game = try game()
        game.gameData?.phase = .finished
        game.gameData?.winner = game.blackPlayer?.id
        game.gameData?.outcome = "Cancellation"
        game.currentPosition.lastMoveNumber = 2
        for color in [StoneColor.black, .white] {
            let state = GameDetailClockState(game: game, color: color)
            XCTAssertEqual(state.resultTitle, "Canceled")
            XCTAssertEqual(state.resultDetail, "before move 3")
            XCTAssertTrue(state.accessibilityValue.contains("before move 3"))
        }
        game.historyAnnulled = true
        for color in [StoneColor.black, .white] {
            let state = GameDetailClockState(game: game, color: color)
            XCTAssertEqual(state.resultTitle, "Annulled")
            XCTAssertEqual(state.resultDetail, "no winner")
        }
    }

    func testDrawResignationAndTimeoutTitles() throws {
        let game = try game()
        game.gameData?.phase = .finished
        game.gameData?.winner = 0
        game.gameData?.outcome = "0 points"
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).resultTitle, "Draw")
        game.gameData?.winner = game.blackPlayer?.id
        game.gameData?.outcome = "Resignation"
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).resultTitle, "Resigned")
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).resultDetail, "by resignation")
        game.gameData?.outcome = "Timeout"
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).resultTitle, "Out of time")
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).resultDetail, "on time")
    }

    func testDisconnectedDisplaySnapshotStaysFrozenWithoutChangingSharedClock() throws {
        let game = try game()
        let snapshot = try XCTUnwrap(game.clock)
        game.clock?.blackTime.thinkingTimeLeft = 100
        let frozen = GameDetailClockState(game: game, color: .black,
            clockOverride: snapshot, isConnected: false)
        XCTAssertEqual(frozen.valueClock?.blackTime.thinkingTimeLeft, 272)
        XCTAssertFalse(frozen.running)
        XCTAssertEqual(game.clock?.blackTime.thinkingTimeLeft, 100)
        let reconnected = GameDetailClockState(game: game, color: .black)
        XCTAssertEqual(reconnected.valueClock?.blackTime.thinkingTimeLeft, 100)
        XCTAssertTrue(reconnected.running)
    }

    func testTurnBadgeBelongsOnlyToPlayerToMoveAndUsesPerspective() throws {
        let game = try game()
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "To move")
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).badgeTitle(), "")
        let service = OGSService(previewState: .init(user: game.blackPlayer, isLoggedIn: true))
        game.ogs = service
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "Your move")
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(narrow: true), "To move")
        game.clock?.currentPlayerColor = .white
        game.clock?.currentPlayerId = game.whitePlayer?.id ?? 0
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).badgeTitle(), "Their move")
    }

    func testPassedBadgeStaysOnPasserWhileTurnBadgeMovesToOpponent() throws {
        let game = try game()
        try game.makeMove(move: .pass)
        game.clock?.currentPlayerColor = .white
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "Passed")
        XCTAssertEqual(GameDetailClockState(game: game, color: .white).badgeTitle(), "To move")
        game.gamePhase = .stoneRemoval
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "")
    }

    func testRengoBadgeNamesTeammateInsteadOfClaimingUsersTurn() throws {
        let game = try game()
        let black = try XCTUnwrap(game.blackPlayer)
        let white = try XCTUnwrap(game.whitePlayer)
        let teammate = OGSUser(username: "Teammate", id: 999_999)
        let service = OGSService(previewState: .init(user: black, isLoggedIn: true))
        game.gameData?.rengo = true
        game.gameData?.rengoTeams = .init(black: [black, teammate], white: [white])
        game.ogs = service
        game.clock?.currentPlayerColor = .black
        game.clock?.currentPlayerId = teammate.id
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(), "Teammate")
        XCTAssertEqual(GameDetailClockState(game: game, color: .black).badgeTitle(narrow: true), "Teammate")
    }

    func testUndoBadgeAndActionsFollowRequesterRatherThanCurrentTurn() throws {
        let game = try game()
        let service = OGSService(previewState: .init(user: game.blackPlayer, isLoggedIn: true))
        game.ogs = service
        game.undoRequest = OGSUndoRequest(moveNumber: game.currentPosition.lastMoveNumber,
                                          requestedBy: game.whitePlayer?.id)
        let opponent = GameDetailClockState(game: game, color: .white)
        XCTAssertEqual(opponent.badgeTitle(), "Undo?")
        XCTAssertTrue(opponent.canAnswerUndo)
        XCTAssertFalse(GameDetailClockState(game: game, color: .black).ownsUndoRequest)

        game.undoRequest = OGSUndoRequest(moveNumber: game.currentPosition.lastMoveNumber,
                                          requestedBy: game.blackPlayer?.id)
        let own = GameDetailClockState(game: game, color: .black)
        XCTAssertEqual(own.badgeTitle(), "Undo asked")
        XCTAssertTrue(own.canWithdrawUndo)
        XCTAssertFalse(own.canAnswerUndo)

        game.undoRequest = OGSUndoRequest(moveNumber: game.currentPosition.lastMoveNumber - 1,
                                          requestedBy: game.blackPlayer?.id)
        XCTAssertFalse(GameDetailClockState(game: game, color: .black).ownsUndoRequest)
    }

    func testReconnectBadgeReplacesTurnOnlyOnFrozenActiveClock() throws {
        let game = try game()
        let snapshot = try XCTUnwrap(game.clock)
        let black = GameDetailClockState(game: game, color: .black,
                                         clockOverride: snapshot, isConnected: false)
        let white = GameDetailClockState(game: game, color: .white,
                                         clockOverride: snapshot, isConnected: false)
        XCTAssertEqual(black.badgeTitle(), "Reconnecting…")
        XCTAssertTrue(black.accessibilityValue.contains("Reconnecting"))
        XCTAssertEqual(white.badgeTitle(), "")
        XCTAssertFalse(black.running)
    }

    /// Before the app's first connection (launch, sign-in) there is nothing
    /// to reconnect, so the badge reads as the app's banner does.
    func testFirstConnectionBadgeReadsConnecting() throws {
        let game = try game()
        let snapshot = try XCTUnwrap(game.clock)
        let black = GameDetailClockState(game: game, color: .black, clockOverride: snapshot,
                                         isConnected: false, recoversConnection: false)
        XCTAssertEqual(black.badgeTitle(), "Connecting…")
        XCTAssertTrue(black.accessibilityValue.contains("Connecting"))
    }

    /// OGS sends a disconnection deadline only as an `auto_resign` event, so
    /// the next clock or gamedata payload must keep it until
    /// `clear_auto_resign`. A finished game drops it.
    func testAutoResignDeadlineSurvivesClockAndGamedataReplacement() throws {
        let game = try game()
        var data = try XCTUnwrap(game.gameData)
        game.gameData = data
        let whiteID = data.players.white.id
        let deadline = Date().timeIntervalSince1970 * 1_000 + 120_000
        game.setAutoResign(playerId: whiteID, time: deadline)
        XCTAssertEqual(game.clock?.autoResignTime[.white], deadline)

        var replacement = data.clock
        replacement.keepAutoResign(from: game.clock)
        game.clock = replacement
        XCTAssertEqual(game.clock?.autoResignTime[.white], deadline, "A replacement clock keeps the deadline")

        game.gameData = data
        XCTAssertEqual(game.clock?.autoResignTime[.white], deadline, "A gamedata update keeps the deadline")
        game.clock?.calculateTimeLeft(with: data.timeControl.system, pauseControl: nil)
        XCTAssertNotNil(GameDetailClockState(game: game, color: .white).autoResign)

        game.clearAutoResign(playerId: whiteID)
        XCTAssertNil(game.clock?.autoResignTime[.white])

        game.setAutoResign(playerId: whiteID, time: deadline)
        data.phase = .finished
        game.gameData = data
        XCTAssertNil(game.clock?.autoResignTime[.white], "A finished game drops the deadline")
    }

    func testEstimatesNeverReplaceClockStatusOrAuthoritativeScore() throws {
        let game = try game()
        game.currentPosition.estimatedScores = Array(repeating: Array(repeating: .hasStone(.white), count: game.width), count: game.height)
        let state = GameDetailClockState(game: game, color: .black)
        XCTAssertFalse(state.isScoring)
        XCTAssertTrue(state.canShowTimer)
        XCTAssertEqual(state.badgeTitle(), "To move")
        XCTAssertEqual(state.valueClock?.blackTime.thinkingTimeLeft, 272)
    }

    private func scores(black: Double, white: Double) -> GameScores {
        GameScores(
            black: PlayerScore(handicap: 0, komi: 0, scoringPositions: [], stones: 0, territory: 58, prisoners: 2, total: black),
            white: PlayerScore(handicap: 0, komi: 6.5, scoringPositions: [], stones: 0, territory: 49, prisoners: 1, total: white))
    }

    /// v148: the app's connection banner gives way only to a Reconnecting…
    /// badge a visible Game Detail is rendering. A retained, hidden game's
    /// registration does not count.
    func testConnectionBannerGivesWayOnlyToAVisibleGamesBadge() {
        let nav = NavigationService()
        let context = UUID()
        let badge = UUID()
        nav.setGameDetailReconnectingBadge(badge, context: context, shown: true)
        XCTAssertFalse(nav.visibleGameDetailShowsReconnectingBadge, "A game that is not visible keeps the banner")
        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext()
        XCTAssertTrue(nav.visibleGameDetailShowsReconnectingBadge, "A visible game's badge stands in for the banner")
        nav.gameDetailNotificationContexts.removeValue(forKey: context)
        XCTAssertFalse(nav.visibleGameDetailShowsReconnectingBadge)
        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext(
            ownLiveGame: .OGS(1), listsLiveGames: true)
        nav.setGameDetailReconnectingBadge(badge, context: context, shown: false)
        XCTAssertFalse(nav.visibleGameDetailShowsReconnectingBadge, "Without a rendered badge the banner shows")
        XCTAssertTrue(nav.gameDetailReconnectingBadges.isEmpty)
    }

    /// The live-game notice offers only live games that no visible Game Detail
    /// shows or lists: never the one on screen (a profile route has no
    /// picker), and nothing while a picker lists them. A finished game on
    /// screen, even one Home opened, keeps both the notice and challenges.
    func testLiveGameNoticeOffersOnlyGamesNotOnScreen() throws {
        let current = try game()
        var data = try XCTUnwrap(current.gameData)
        data.gameId += 1
        let other = Game(ogsGame: data)
        data.gameId += 1
        data.outcome = "Resignation"
        let finished = Game(ogsGame: data)
        let liveGames = [current, other, finished]

        let nav = NavigationService()
        XCTAssertEqual(nav.liveGamesNeedingNotice(among: liveGames).map(\.ID), [current.ID, other.ID])
        XCTAssertFalse(nav.visibleGameDetailPlaysLiveGame)

        let context = UUID()
        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext()
        XCTAssertEqual(nav.liveGamesNeedingNotice(among: liveGames).map(\.ID), [current.ID, other.ID],
                       "A finished or spectated game on screen keeps the notice")
        XCTAssertFalse(nav.visibleGameDetailPlaysLiveGame, "and lets challenge notices show")

        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext(ownLiveGame: current.ID)
        XCTAssertEqual(nav.liveGamesNeedingNotice(among: liveGames).map(\.ID), [other.ID],
                       "Without a picker the notice offers the other live game, never this one")
        XCTAssertTrue(nav.visibleGameDetailPlaysLiveGame)

        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext(
            ownLiveGame: current.ID, listsLiveGames: true)
        XCTAssertTrue(nav.liveGamesNeedingNotice(among: liveGames).isEmpty, "The picker lists them instead")

        nav.gameDetailNotificationContexts.removeValue(forKey: context)
        XCTAssertEqual(nav.liveGamesNeedingNotice(among: liveGames).count, 2)
    }

    /// A Game Detail keeps its window awake while it shows a live game that
    /// has not ended, played or watched, and lets it sleep once the game ends.
    func testWatchedLiveGameKeepsTheWindowAwakeUntilItEnds() throws {
        let live = try game()
        let context = GameDetailNotificationContext(showing: live, allowsActiveGamesCarousel: true)
        XCTAssertTrue(context.showsLiveGameInPlay, "A spectated live game in play keeps the display awake")
        XCTAssertNil(context.ownLiveGame, "Watching is not playing")
        XCTAssertFalse(context.listsLiveGames)

        let nav = NavigationService()
        let contextID = UUID()
        nav.gameDetailNotificationContexts[contextID] = context
        XCTAssertTrue(nav.visibleGameDetailShowsLiveGameInPlay)

        live.gamePhase = .stoneRemoval
        XCTAssertTrue(GameDetailNotificationContext(showing: live, allowsActiveGamesCarousel: true)
            .showsLiveGameInPlay, "Stone removal is still part of the game")
        live.gamePhase = .finished
        let ended = GameDetailNotificationContext(showing: live, allowsActiveGamesCarousel: true)
        XCTAssertFalse(ended.showsLiveGameInPlay, "A finished game lets the display sleep")
        nav.gameDetailNotificationContexts[contextID] = ended
        XCTAssertFalse(nav.visibleGameDetailShowsLiveGameInPlay)

        let resigned = try game()
        resigned.gameData?.outcome = "Resignation"
        XCTAssertFalse(GameDetailNotificationContext(showing: resigned, allowsActiveGamesCarousel: true)
            .showsLiveGameInPlay, "A result ends the game before its phase does")

        let correspondence = try game(.Simple(perMove: 86_400))
        XCTAssertFalse(GameDetailNotificationContext(showing: correspondence, allowsActiveGamesCarousel: true)
            .showsLiveGameInPlay, "A correspondence game never keeps the display awake")
    }

    /// Only the foreground counts; a finished live game stops counting before
    /// the service's live list drops it.
    func testWindowKeepsTheDisplayAwakeForLiveGamesInPlay() throws {
        let live = try game()
        let nav = NavigationService()
        func keepsAwake(isActive: Bool = true, liveGames: [Game] = [], waiting: Int = 0) -> Bool {
            nav.keepsDisplayAwake(isActive: isActive, liveGames: liveGames, waitingLiveGames: waiting)
        }
        XCTAssertFalse(keepsAwake())
        XCTAssertTrue(keepsAwake(liveGames: [live]))
        XCTAssertTrue(keepsAwake(waiting: 1), "Waiting for a live game to start")
        nav.gameDetailNotificationContexts[UUID()] = GameDetailNotificationContext(
            showing: live, allowsActiveGamesCarousel: false)
        XCTAssertTrue(keepsAwake(), "Watching a live game in play")
        XCTAssertFalse(keepsAwake(isActive: false, liveGames: [live], waiting: 1))
        live.gamePhase = .finished
        nav.gameDetailNotificationContexts.removeAll()
        XCTAssertFalse(keepsAwake(liveGames: [live]))
    }

    /// Each window asks for itself. The app-wide switch turns off only once
    /// no window asks, so one window leaving the foreground cannot let
    /// another window's live game sleep.
    func testDisplayStaysAwakeWhileAnyWindowAsks() {
        var requests = DisplaySleepRequests()
        let first = UUID(), second = UUID()
        XCTAssertEqual(requests.set(true, for: first), true)
        XCTAssertNil(requests.set(true, for: second), "Already awake")
        XCTAssertNil(requests.set(true, for: first), "Repeating a request changes nothing")
        XCTAssertNil(requests.set(false, for: first), "The second window still asks")
        XCTAssertTrue(requests.keepsAwake)
        XCTAssertEqual(requests.set(false, for: second), false)
        XCTAssertNil(requests.set(false, for: second))
        XCTAssertFalse(requests.keepsAwake)
    }

    /// A Game Detail torn down without onDisappear (a background scene the
    /// system disconnects, whose NavigationService returns with the window)
    /// still withdraws its registration, so a finished game cannot keep the
    /// restored window awake or hide notices.
    func testRegistrationOutlivingItsViewsIsWithdrawn() {
        let nav = NavigationService()
        let context = UUID()
        nav.gameDetailNotificationContexts[context] = GameDetailNotificationContext(showsLiveGameInPlay: true)
        nav.setGameDetailReconnectingBadge(UUID(), context: context, shown: true)
        var lifetime: ViewLifetime? = ViewLifetime()
        lifetime?.release = { nav.removeGameDetailNotificationContext(context) }
        XCTAssertTrue(nav.keepsDisplayAwake(isActive: true, liveGames: [], waitingLiveGames: 0))

        let released = expectation(description: "Released after the view state goes")
        lifetime = nil
        DispatchQueue.main.async { released.fulfill() }
        wait(for: [released], timeout: 1)
        XCTAssertFalse(nav.keepsDisplayAwake(isActive: true, liveGames: [], waitingLiveGames: 0))
        XCTAssertTrue(nav.gameDetailNotificationContexts.isEmpty)
        XCTAssertTrue(nav.gameDetailReconnectingBadges.isEmpty)
    }

    func testWidestCountdownSamplesIncludeTheDayAndHourForm() {
        // A 30-day clock shows "30 days" at its maximum, but "29 days 23h"
        // one second under it: the samples must include the wider form.
        let maximum = 2_592_000
        let samples = GameDetailClockState.widestCountdownSamples(maximumTime: maximum)
        XCTAssertTrue(samples.contains(maximum - 1))
        XCTAssertGreaterThan(timeString(timeLeft: maximum - 1).count, timeString(timeLeft: maximum).count)
    }
}
