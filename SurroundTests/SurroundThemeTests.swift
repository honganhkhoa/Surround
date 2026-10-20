import XCTest
import SwiftUI

final class SurroundThemeTests: XCTestCase {
    func testStandardThemeKeepsTheOriginalBoard() {
        let board = SurroundTheme.standard.board
        XCTAssertEqual(board, BoardAppearance.standard)
        XCTAssertEqual(board.boardColor, Color(red: 0.86, green: 0.69, blue: 0.42))
        XCTAssertEqual(board.gridColor, .black)
        XCTAssertEqual(board.black.flat, .black)
        XCTAssertEqual(board.white.flat, .white)
        XCTAssertEqual(board.black.lastMove, .white)
        XCTAssertEqual(board.white.lastMove, .gray)
        XCTAssertNil(board.boardEdge)
    }

    func testStandardThemeFollowsTheSystemAppearance() {
        XCTAssertNil(SurroundTheme.standard.colorScheme)
        XCTAssertFalse(SurroundTheme.standard.hasScene)
        XCTAssertEqual(SurroundTheme.nebulaPearl.colorScheme, .dark)
        XCTAssertTrue(SurroundTheme.nebulaPearl.hasScene)
    }

    func testAnUnknownStoredThemeFallsBackToStandard() {
        XCTAssertEqual(SurroundTheme.current(storedID: "unknown"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: ""), .standard)
        #if DEBUG
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        #else
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .standard)
        #endif
    }

    /// The concept warns about violet on indigo: glass stones need a clear
    /// lightness gap from the board, and the two players a larger one.
    func testNebulaStonesStandApartFromTheBoardAndEachOther() {
        let board = SurroundTheme.nebulaPearl.board
        XCTAssertGreaterThan(contrast(board.black.flat, board.boardColor), 2)
        XCTAssertGreaterThan(contrast(board.white.flat, board.boardColor), 7)
        XCTAssertGreaterThan(contrast(board.white.flat, board.black.flat), 3)
        XCTAssertGreaterThan(contrast(board.white.lastMove, board.white.flat), 4.5)
        XCTAssertGreaterThan(contrast(board.black.territoryMark, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.white.territoryMark, board.black.territoryMark), 2)
    }

    /// Small marks keep the 3:1 a non-text indicator needs: tree marks on
    /// the panel and their keyline, the turn mark against an idle game, and
    /// removal marks and the crosshair on the board.
    func testNebulaMarksStayReadable() throws {
        let theme = SurroundTheme.nebulaPearl, board = theme.board
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        XCTAssertGreaterThan(contrast(theme.selectionMark, theme.panel), 3)
        XCTAssertGreaterThan(contrast(theme.selectionMark, keyline), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(theme.conditionalMark), keyline), 3)
        XCTAssertGreaterThan(contrast(theme.userTurnMark, theme.idleGameMark(scheme: .dark)), 3)
        XCTAssertGreaterThan(contrast(board.removeMark, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.restoreMark, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.crosshair.valid, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.crosshair.invalid, board.boardColor), 3)
        XCTAssertNotNil(board.removalMarkCasing)
        XCTAssertNotNil(board.removedStoneOutline)
    }

    func testStandardThemeKeepsItsMarks() {
        let theme = SurroundTheme.standard
        XCTAssertNil(theme.treeMarkKeyline)
        XCTAssertNil(theme.conditionalMark)
        XCTAssertNil(theme.userTurnGlow)
        XCTAssertEqual(theme.selectionMark, Color(uiColor: .systemTeal))
        XCTAssertEqual(theme.userTurnMark, Color(uiColor: .systemTeal))
        XCTAssertEqual(theme.stoneRemovalMark, Color(uiColor: .systemOrange))
    }

    private func contrast(_ first: Color, _ second: Color) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG relative luminance from the color's sRGB components.
    private func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let linear = { (value: CGFloat) -> Double in
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
