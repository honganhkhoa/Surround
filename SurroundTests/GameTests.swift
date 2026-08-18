//
//  GameTests.swift
//  SurroundTests
//
//  Created by Anh Khoa Hong on 21/05/2021.
//

import XCTest
import DictionaryCoding

class GameTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParsingOngoingGameWithFreeHandicapPlacement() throws {
        let game = GameTests.sampleGame(ogsId: 26268396)
        
        XCTAssertNil(game.gameData?.outcome)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 81)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(13, 13))
        XCTAssertEqual(game.currentPosition.nextToMove, .black)

        XCTAssertEqual(game.positionByLastMoveNumber[2]?.nextToMove, .black)
        XCTAssertEqual(game.positionByLastMoveNumber[3]?.nextToMove, .black)
        XCTAssertEqual(game.positionByLastMoveNumber[8]?.nextToMove, .white)
        
        BoardPositionTests.assertPositionEqual(position: game.currentPosition, visualStrings: [
            "-------------------",
            "-------------------",
            "------b-----b------",
            "-b-b-b-b-b---b-b---",
            "-wb---b---------bb-",
            "-------------b-ww--",
            "-------------------",
            "-bb-----------b-w--",
            "-wb----------------",
            "-w-b-----b---bbb-w-",
            "--w----------bwbw--",
            "--wbbbb---bbbw-bbw-",
            "---wwbwb--bwww-bw--",
            "--w--wwb-ww--wbbw--",
            "-------ww-----ww---",
            "---b-----b----wb---",
            "--w----w-------ww--",
            "-------------------",
            "-------------------"
        ])
    }

    func testGameDeallocatesWhenOnlyPlayerCacheSubscriptionRemains() {
        let service = OGSService.previewInstance()
        weak var weakGame: Game?

        withExtendedLifetime(service) {
            var game: Game? = Game(
                width: 5,
                height: 5,
                blackName: "black",
                whiteName: "white",
                gameId: .OGS(1)
            )
            weakGame = game
            game?.ogs = service

            XCTAssertNotNil(game?.playerCacheObservingCancellable)
            game = nil
            XCTAssertNil(weakGame)

            // Break the historical cycle if this assertion is run against a
            // regressed implementation, so the failed test cleans up after itself.
            weakGame?.ogs = nil
        }
    }

    func testAnalysisAvailabilityRespectsDisabledSettingUntilGameFinishes() throws {
        let game = GameTests.sampleGame(ogsId: 26_268_396)
        game.gameData?.disableAnalysis = true

        let participant = try XCTUnwrap(game.blackPlayer)
        let participantService = OGSService.previewInstance(user: participant)
        withExtendedLifetime(participantService) {
            game.ogs = participantService

            game.gamePhase = .play
            XCTAssertTrue(game.isUserPlaying)
            XCTAssertFalse(game.analysisAvailable)

            game.autoScoringDone = true
            game.gamePhase = .stoneRemoval
            XCTAssertFalse(game.analysisAvailable)

            game.gamePhase = .finished
            XCTAssertTrue(game.analysisAvailable)
        }

        let spectatorService = OGSService.previewInstance(
            user: OGSUser(username: "Spectator", id: -1)
        )
        withExtendedLifetime(spectatorService) {
            game.ogs = spectatorService
            game.gamePhase = .play
            XCTAssertFalse(game.isUserPlaying)
            XCTAssertTrue(game.analysisAvailable)
        }
    }
    
    static func sampleGame(ogsId: Int) -> Game {
        let fileURL = Bundle(for: GameTests.self).url(forResource: "game-\(ogsId)", withExtension: "json")!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try! decoder.decode(OGSGame.self, from: Data(contentsOf: fileURL))
        let game = Game(ogsGame: ogsGame)
        if let chatURL = Bundle.main.url(forResource: "chat-\(ogsId)", withExtension: "json") {
            if let chatLines = try? JSONSerialization.jsonObject(with: Data(contentsOf: chatURL)) as? [[String: Any]] {
                let dictDecoder = DictionaryDecoder()
                dictDecoder.keyDecodingStrategy = .convertFromSnakeCase
                for chatLine in chatLines {
                    if let line = try? dictDecoder.decode(OGSChatLine.self, from: chatLine) {
                        game.addChatLine(line)
                    }
                }
            }
        }
        return game
    }
}
