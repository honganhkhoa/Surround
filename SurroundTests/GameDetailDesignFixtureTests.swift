import XCTest

@MainActor
final class GameDetailDesignFixtureTests: XCTestCase {
    func testDesignArtboardRequiresExplicitOfflineCompatibilityOptIn() {
        let flag = SurroundUITestContract.gameDetailDesignArtboardLaunchArgument
        let enabled = [SurroundUITestContract.launchArgument,
                       SurroundUITestContract.compatibilityScreenshotLaunchArgument, flag, "64"]
        XCTAssertEqual(SurroundUITestContract.gameDetailDesignArtboard(in: enabled), 64)
        XCTAssertNil(SurroundUITestContract.gameDetailDesignArtboard(in: [flag, "64"]))
        XCTAssertNil(SurroundUITestContract.gameDetailDesignArtboard(in: enabled + [SurroundUITestContract.screenshotLaunchArgument]))
        for invalid in ["0", "92", "play", ""] {
            XCTAssertNil(SurroundUITestContract.gameDetailDesignArtboard(in: Array(enabled.dropLast()) + [invalid]))
        }
    }

    func testPrimarySnapshotMatchesStonesPlayersClocksAndUnreadChat() throws {
        let fixture = OGSService.gameDetailDesignFixture(artboard: 1)
        let game = fixture.game
        XCTAssertEqual(game.ogsID, SurroundUITestContract.screenshotPrimaryGameID)
        XCTAssertEqual(game.blackPlayer?.username, "tenuki_tom")
        XCTAssertEqual(game.blackPlayer?.ranking, 32)
        XCTAssertEqual(game.whitePlayer?.username, "kosumi")
        XCTAssertEqual(game.whitePlayer?.ranking, 31)
        XCTAssertEqual(game.whitePlayer?.isOGSSupporter, true)
        XCTAssertNotEqual(game.whitePlayer?.professional, true)
        XCTAssertEqual(game.stoneColor(of: fixture.user), .white)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 38)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(9, 10))
        var black = 0
        var white = 0
        for row in 0..<19 {
            for column in 0..<19 {
                if game.currentPosition[row, column] == .hasStone(.black) { black += 1 }
                if game.currentPosition[row, column] == .hasStone(.white) { white += 1 }
            }
        }
        XCTAssertEqual(black, 20)
        XCTAssertEqual(white, 19)
        XCTAssertEqual(game.clock?.blackTime.thinkingTimeLeft, 272)
        XCTAssertEqual(game.clock?.whiteTime.thinkingTimeLeft, 375)
        XCTAssertEqual(game.clock?.blackTime.periodsLeft, 3)
        XCTAssertEqual(game.clock?.whiteTime.periodsLeft, 5)
        XCTAssertEqual(game.currentPosition.captures, [.black: 2, .white: 1])
        XCTAssertEqual(game.chatUnreadCount, 3)
        XCTAssertEqual(game.chatLog.map(\.body), ["Good luck, have fun!", "You too!", "is the 3-3 invasion still alive?"])
        XCTAssertTrue(game.chatLog.allSatisfy { $0.channel == .main })
        XCTAssertNotNil(try XCTUnwrap(game.chatLog.last).variation)
        XCTAssertEqual(game.conditionalMoveBranches.count, 2)
    }

    func testSourceSnapshotHasContinuousLegalHistoryWithoutInventedCaptures() throws {
        let game = OGSService.gameDetailDesignFixture(artboard: 25).game
        XCTAssertEqual(game.initialPosition.lastMoveNumber, 21)
        XCTAssertEqual(game.gameData?.moves.count, 17)
        XCTAssertEqual(game.moveTree.moveNumberRange, 21..<46)
        for number in 21...38 {
            let position = try XCTUnwrap(game.positionByLastMoveNumber[number])
            XCTAssertEqual(position.lastMoveNumber, number)
            XCTAssertEqual(position.captures, [.black: 2, .white: 1], "No capture is introduced at move \(number).")
            if number > 21 {
                XCTAssertTrue(position.previousPosition === game.positionByLastMoveNumber[number - 1])
                XCTAssertEqual(position.lastMoveColor, number.isMultiple(of: 2) ? .white : .black)
            }
        }
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(9, 10))
    }

    func testAnalysisSelectionIsLegalSourceVariationWithAlternativeBranches() throws {
        let game = OGSService.gameDetailDesignFixture(artboard: 22).game
        let base = try XCTUnwrap(game.positionByLastMoveNumber[38])
        let positions = try XCTUnwrap(game.moveTree.positionsByLastMoveNumber[41])
        let selected = try XCTUnwrap(positions.compactMap { $0 }.first { $0.lastMove == .placeStone(10, 12) })
        XCTAssertEqual(selected[9, 11], .hasStone(.black))
        XCTAssertEqual(selected[10, 11], .hasStone(.white))
        XCTAssertEqual(selected[10, 12], .hasStone(.black))
        XCTAssertEqual(base[9, 11], .empty)
        XCTAssertGreaterThanOrEqual(game.moveTree.nextPositionsByPosition[ObjectIdentifier(base)]?.count ?? 0, 2)
        XCTAssertTrue(game.currentPosition === base, "Entering Analyze must not change the live game position.")
        XCTAssertTrue(game.moveTree.nextPositionsByPosition[ObjectIdentifier(selected)]?.isEmpty ?? true,
                      "The selected source variation ends after its third move, so Next is disabled.")
        XCTAssertNotNil(game.moveTree.adjacentBranch(from: selected, direction: .previous))
        XCTAssertNotNil(game.moveTree.adjacentBranch(from: selected, direction: .next))
    }

    func testPerArtboardRolesProvideRealPassAndTwoEligibleNextGames() {
        for number in [1, 2, 3, 11, 17, 36, 53, 56, 57, 67, 81, 84] {
            let fixture = OGSService.gameDetailDesignFixture(artboard: number)
            XCTAssertEqual(fixture.game.stoneColor(of: fixture.user), .white, "artboard \(number)")
            XCTAssertFalse(fixture.game.requiresUserAction(forPlayerWithId: fixture.user.id), "artboard \(number)")
            XCTAssertEqual(fixture.readyGames.filter { $0.requiresUserAction(forPlayerWithId: fixture.user.id) }.count, 2)
            XCTAssertTrue(fixture.readyGames.allSatisfy { $0.gameData?.timeControl.speed == fixture.game.gameData?.timeControl.speed })
        }
        for number in [4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 18, 20, 21, 39, 40, 41, 44, 54, 55, 58, 59, 62, 63, 70, 71] {
            let fixture = OGSService.gameDetailDesignFixture(artboard: number)
            XCTAssertEqual(fixture.game.stoneColor(of: fixture.user), .black, "artboard \(number)")
            XCTAssertTrue(fixture.game.requiresUserAction(forPlayerWithId: fixture.user.id), "artboard \(number)")
        }
    }

    func testRengoUsesSourceTeamOrderAndWaitsForTeammate() {
        let fixture = OGSService.gameDetailDesignFixture(artboard: 52)
        XCTAssertTrue(fixture.game.rengo)
        XCTAssertEqual(fixture.game.orderedRengoTeam[.white]?.map(\.username), ["bob_k", "carol", "kosumi"])
        XCTAssertEqual(fixture.game.orderedRengoTeam[.white]?.map(\.ranking), [29, 27, 31])
        XCTAssertEqual(fixture.game.orderedRengoTeam[.white]?.map(\.isOGSSupporter), [false, true, true])
        XCTAssertEqual(fixture.game.stoneColor(of: fixture.user), .white)
        XCTAssertEqual(fixture.game.clock?.currentPlayerId, fixture.game.whitePlayer?.id)
        XCTAssertFalse(fixture.game.requiresUserAction(forPlayerWithId: fixture.user.id))
    }

    func testSpectatorAndLongNamesAreSourceSpecific() {
        let spectator = OGSService.gameDetailDesignFixture(artboard: 46)
        XCTAssertNil(spectator.game.stoneColor(of: spectator.user))
        XCTAssertEqual(spectator.game.blackPlayer?.username, "shusaku_fan")
        XCTAssertEqual(spectator.game.whitePlayer?.username, "honinbo_jr")
        XCTAssertEqual(spectator.game.blackPlayer?.isOGSModerator, true)
        XCTAssertEqual(spectator.game.whitePlayer?.isOGSProfessional, true)
        XCTAssertEqual(spectator.game.blackPlayer?.ranking, 33)
        XCTAssertEqual(spectator.game.whitePlayer?.ranking, 34)
        XCTAssertNotEqual(spectator.game.blackPlayer?.professional, true)
        XCTAssertNotEqual(spectator.game.whitePlayer?.professional, true,
                          "The source's professional name style must retain its amateur 5d rank.")
        XCTAssertEqual(spectator.game.clock?.currentPlayerColor, .white)
        XCTAssertEqual(spectator.game.clock?.blackTime.thinkingTimeLeft, 728)
        XCTAssertEqual(spectator.game.clock?.whiteTime.thinkingTimeLeft, 591)
        let long = OGSService.gameDetailDesignFixture(artboard: 53)
        XCTAssertEqual(long.game.blackPlayer?.username, "the_extremely_patient_kibitzer")
        XCTAssertEqual(long.user.username, "sabaki_and_shinogi_forever")
        XCTAssertEqual(long.game.blackPlayer?.ranking, 18)
        XCTAssertEqual(long.user.ranking, 30)
        XCTAssertTrue(long.user.isOGSSupporter)
        XCTAssertNotEqual(long.user.professional, true)
    }

    func testScoringSnapshotSurvivesQueuedEstimateAndRequiresLocalAcceptance() async throws {
        let fixture = OGSService.gameDetailDesignFixture(artboard: 64)
        let game = fixture.game
        game.computeQueue.sync {}
        await Task.yield()
        XCTAssertEqual(game.gamePhase, .stoneRemoval)
        XCTAssertEqual(game.currentPosition.removedStones, [[4, 12], [3, 9]])
        XCTAssertEqual(game.currentPosition.gameScores?.black.total, 60)
        XCTAssertEqual(game.currentPosition.gameScores?.white.total, 56.5)
        XCTAssertEqual(game.currentPosition.gameScores?.black.scoringPositions.count, 7)
        XCTAssertEqual(game.currentPosition.gameScores?.white.scoringPositions.count, 9)
        XCTAssertTrue(GameDetailClockState(game: game, color: .black).accepted)
        XCTAssertFalse(GameDetailClockState(game: game, color: .white).accepted)
        XCTAssertTrue(game.requiresUserAction(forPlayerWithId: fixture.user.id))
        XCTAssertEqual(game.clock?.timeUntilExpiration, 48)
    }

    func testReferenceClocksUseSourceColorValuesAndResults() {
        let overtime = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "byoyomi-overtime").game
        XCTAssertEqual(overtime.clock?.currentPlayerColor, .black)
        XCTAssertEqual(overtime.clock?.blackTime.periodTimeLeft, 21)
        let canadian = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "canadian-overtime").game
        XCTAssertEqual(canadian.clock?.blackTime.blockTimeLeft, 102)
        XCTAssertEqual(canadian.clock?.blackTime.movesLeft, 7)
        let fischer = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "fischer").game
        XCTAssertEqual(fischer.clock?.whiteTime.thinkingTimeLeft, 375)
        let timeout = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "finished-timeout").game
        XCTAssertEqual(timeout.gameData?.winner, timeout.whitePlayer?.id)
        XCTAssertEqual(timeout.currentPosition.lastMoveNumber, 87)
        let resigned = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "finished-resignation").game
        XCTAssertEqual(resigned.currentPosition.lastMoveNumber, 142)
        let draw = OGSService.gameDetailDesignFixture(artboard: 78, clockState: "draw").game
        XCTAssertEqual(draw.gameData?.score?.black.total, 60)
        XCTAssertEqual(draw.gameData?.score?.white.total, 60)
    }

    func testPreStartAndPausedReferencesHaveExactCapturesAndStartingPeriods() {
        let preStart = OGSService.gameDetailDesignFixture(artboard: 79, clockState: "not-started").game
        XCTAssertFalse(preStart.clock?.started ?? true)
        XCTAssertEqual(preStart.currentPosition.lastMoveNumber, 0)
        XCTAssertEqual(preStart.currentPosition.captures, [.black: 0, .white: 0])
        XCTAssertEqual(GameDetailClockState(game: preStart, color: .white).valueClock?.whiteTime.thinkingTimeLeft, 600)
        let paused = OGSService.gameDetailDesignFixture(artboard: 79, clockState: "paused").game
        XCTAssertEqual(paused.currentPosition.captures, [.black: 12, .white: 9])
        XCTAssertEqual(paused.clock?.blackTime.thinkingTimeLeft, 187_200)
        XCTAssertEqual(paused.clock?.whiteTime.thinkingTimeLeft, 298_800)
        XCTAssertTrue(paused.pauseControl?.isPaused() ?? false)
    }
}
