import AVFAudio
import UIKit
import XCTest

final class StonePlacementSoundTests: XCTestCase {
    func testEveryAvailableThemeHasDistinctDecodablePlacementSounds() throws {
        let bundle = Bundle(for: Self.self)
        var sounds = Set<Data>()
        for theme in SurroundTheme.available {
            for color: StoneColor in [.black, .white] {
                for variation in StonePlacementSoundPlayer.variations {
                    let name = StonePlacementSoundPlayer.assetName(theme: theme, color: color, variation: variation)
                    let asset = try XCTUnwrap(NSDataAsset(name: name, bundle: bundle), name)
                    let player = try AVAudioPlayer(data: asset.data)
                    XCTAssertEqual(player.numberOfChannels, 1, name)
                    XCTAssertEqual(player.format.sampleRate, 44_100, name)
                    XCTAssertGreaterThan(player.duration, 0.03, name)
                    XCTAssertLessThan(player.duration, 1, name)
                    XCTAssertTrue(sounds.insert(asset.data).inserted, "Duplicate sound: \(name)")
                }
            }
        }
        let fallback = try XCTUnwrap(NSDataAsset(name: "stonePlacing", bundle: bundle))
        XCTAssertGreaterThan(try AVAudioPlayer(data: fallback.data).duration, 0)
    }

    func testOnlyTheNextStonePlacementProducesAColor() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let black = try initial.makeMove(move: .placeStone(0, 0))
        let white = try black.makeMove(move: .placeStone(1, 1))
        let pass = try white.makeMove(move: .pass)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: black), .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: black, in: white), .white)
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: white, in: pass))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: initial))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: black, in: black))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: white), "Catch-up skips audio")
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: white, in: black), "Undo skips audio")

        let otherBranch = try initial.makeMove(move: .placeStone(2, 2))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: otherBranch, in: white))
    }

    func testHandicapStonesUseTheirPlacedColorEvenWhenTheNextPlayerDoesNotChange() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let first = try initial.makeHandicapPlacement(move: .placeStone(2, 2))
        let second = try first.makeHandicapPlacement(move: .placeStone(6, 6))
        XCTAssertEqual(first.nextToMove, .black)
        XCTAssertEqual(second.nextToMove, .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: first), .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: first, in: second), .black)
    }
}
