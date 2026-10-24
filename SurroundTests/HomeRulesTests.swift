import XCTest

/// Home's layout and wording rules (canvas "Home Redesign", Direction C).
final class HomeRulesTests: XCTestCase {
    func testCompactSectionsBecomeBandsOnceTwoCellsFit() {
        let twoCells = 2 * HomeLayout.compactCellWidth + HomeLayout.columnSpacing + 2 * HomeLayout.bandMargin
        XCTAssertEqual(HomeLayout.compactColumns(for: 390), 1, "iPhone keeps one grouped list")
        XCTAssertEqual(HomeLayout.compactColumns(for: 500), 1, "iPad portrait beside the sidebar keeps one list")
        XCTAssertEqual(HomeLayout.compactColumns(for: twoCells - 1), 1)
        XCTAssertEqual(HomeLayout.compactColumns(for: twoCells), 2)
        XCTAssertEqual(HomeLayout.compactColumns(for: twoCells + HomeLayout.compactCellWidth + HomeLayout.columnSpacing), 3)
        XCTAssertEqual(HomeLayout.compactColumns(for: 4000), 3, "Bands never run past three columns")
    }

    func testLargeTilesAddColumnsInsteadOfShrinkingBoards() {
        let margin = HomeLayout.listMargin
        let twoTiles = 2 * HomeLayout.largeTileWidth + HomeLayout.columnSpacing + 2 * margin
        XCTAssertEqual(HomeLayout.largeColumns(for: 390, margin: margin), 1)
        XCTAssertEqual(HomeLayout.largeColumns(for: twoTiles - 1, margin: margin), 1)
        XCTAssertEqual(HomeLayout.largeColumns(for: twoTiles, margin: margin), 2)
        for width in stride(from: CGFloat(320), through: 2000, by: 7) {
            let columns = CGFloat(HomeLayout.largeColumns(for: width, margin: margin))
            guard columns > 1 else { continue }
            let tile = (width - 2 * margin - (columns - 1) * HomeLayout.columnSpacing) / columns
            XCTAssertGreaterThanOrEqual(tile - 2 * HomeLayout.largeTilePadding, HomeLayout.largeBoardSize,
                                        "A \(width) pt Home keeps boards at the detailed size")
        }
    }

    func testTimeControlLineSaysWhatEachMoveAdds() {
        // Counts above one: here a count of one read "1 days", while the
        // app shows "+ 1 day per move", so singular forms are checked by eye.
        XCTAssertEqual(TimeControlSystem.Fischer(initialTime: 259_200, timeIncrement: 172_800, maxTime: 604_800)
            .homeAddedTime, "+ 2 days per move")
        XCTAssertEqual(TimeControlSystem.ByoYomi(mainTime: 600, periods: 5, periodTime: 30).homeAddedTime,
                       "+ 5× 30 seconds")
        XCTAssertEqual(TimeControlSystem.Canadian(mainTime: 600, periodTime: 600, stonesPerPeriod: 25).homeAddedTime,
                       "+ 10 minutes for 25 stones")
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 259_200).homeAddedTime, "3 days per move")
        XCTAssertEqual(TimeControlSystem.Absolute(totalTime: 3_600).homeAddedTime, "No time added")
        XCTAssertEqual(TimeControlSystem.None.homeAddedTime, "No time limits")
        XCTAssertNil(TimeControlSystem.Unknown("future-clock").homeAddedTime)
    }
}
