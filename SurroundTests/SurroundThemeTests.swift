import XCTest
import SwiftUI
import CoreGraphics

final class SurroundThemeTests: XCTestCase {
    func testStandardThemeKeepsTheOriginalBoard() {
        let board = SurroundTheme.standard.board
        XCTAssertEqual(board, BoardAppearance.standard)
        XCTAssertEqual(board.boardColor, Color(red: 0.86, green: 0.69, blue: 0.42))
        XCTAssertEqual(board.gridColor, .black)
        XCTAssertEqual(board.black.flat, .black)
        XCTAssertEqual(board.white.flat, .white)
        XCTAssertEqual(board.black.lastMove, .white)
        XCTAssertEqual(board.white.lastMove, Color(white: 0.3))
        XCTAssertNil(board.boardEdge)
        XCTAssertEqual(board.stoneLightDirection.shadowXSign, 1)
    }

    func testStandardThemeFollowsTheSystemAppearance() {
        XCTAssertNil(SurroundTheme.standard.colorScheme)
        XCTAssertFalse(SurroundTheme.standard.hasScene)
        XCTAssertEqual(SurroundTheme.nebulaPearl.colorScheme, .dark)
        XCTAssertTrue(SurroundTheme.nebulaPearl.hasScene)
        XCTAssertNil(SurroundTheme.rakedGarden.colorScheme)
        XCTAssertTrue(SurroundTheme.rakedGarden.hasScene)
        XCTAssertEqual(SurroundTheme.surroundStudio.colorScheme, .light)
        XCTAssertTrue(SurroundTheme.surroundStudio.hasScene)
    }

    func testAnUnknownStoredThemeFallsBackToStandard() {
        XCTAssertEqual(SurroundTheme.current(storedID: "unknown"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: ""), .standard)
        #if DEBUG
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .surroundStudio)
        #else
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .standard)
        #endif
    }

    /// The concept warns about violet on indigo: glass stones need a clear
    /// lightness gap from the board, and the two players a larger one.
    func testNebulaStonesStandApartFromTheBoardAndEachOther() {
        let board = SurroundTheme.nebulaPearl.board
        XCTAssertEqual(board.stoneLightDirection.shadowXSign, 1)
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

    /// Pale jade needs a dark contour on pale sand. This also guards the
    /// flat fallback used below the rendered-stone detail threshold.
    func testGardenStonesAndGridStayDistinctAtSmallSizes() throws {
        let board = SurroundTheme.rakedGarden.board
        // Both raster contacts and shaded fallbacks must cast down-left,
        // matching the garden canopy; existing themes retain down-right.
        XCTAssertEqual(board.stoneLightDirection.shadowXSign, -1)
        XCTAssertGreaterThan(contrast(board.black.flat, board.boardColor), 7)
        XCTAssertGreaterThan(contrast(board.white.flat, board.black.flat), 7)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.white.outline), board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.gridColor, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.coordinateColor, board.boardColor), 4.5)
        for stone in [board.black, board.white] {
            XCTAssertGreaterThan(contrast(stone.lastMove, stone.flat), 4.5)
            XCTAssertGreaterThan(contrast(stone.label, stone.flat), 4.5)
            XCTAssertGreaterThan(contrast(stone.territoryMark, board.boardColor), 3)
        }
        XCTAssertGreaterThan(contrast(board.black.territoryMark, board.white.territoryMark), 2)
    }

    func testGardenMarksStayReadableOnSandAndInAnalysis() throws {
        let theme = SurroundTheme.rakedGarden, board = theme.board
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        let casing = try XCTUnwrap(board.removalMarkCasing)
        XCTAssertGreaterThan(contrast(theme.selectionMark, theme.panel), 3)
        XCTAssertGreaterThan(contrast(theme.selectionMark, keyline), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(theme.conditionalMark), keyline), 3)
        XCTAssertGreaterThan(contrast(theme.userTurnMark, theme.idleGameMark(scheme: .light)), 3)
        for mark in [board.removeMark, board.restoreMark, board.crosshair.valid,
                     board.crosshair.invalid, board.crosshair.removal] {
            XCTAssertGreaterThan(contrast(mark, board.boardColor), 3)
        }
        XCTAssertGreaterThan(contrast(board.removeMark, casing), 3)
        XCTAssertGreaterThan(contrast(board.restoreMark, casing), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.removedStoneOutline), board.boardColor), 3)
    }

    /// The opaque accessibility/older-OS paths must carry the same readable
    /// player identities when native glass cannot be used.
    func testGardenControlFallbacksKeepReadableText() throws {
        let theme = SurroundTheme.rakedGarden
        XCTAssertGreaterThan(contrast(theme.foreground, theme.pageBackground), 7)
        XCTAssertGreaterThan(contrast(theme.foreground, theme.panel), 7)
        for color: StoneColor in [.black, .white] {
            let foreground = theme.clockForeground(color, scheme: .light)
            XCTAssertGreaterThan(contrast(foreground, theme.clockSolidSurface(color)), 4.5)
            for stop in theme.clockSurfaceStops(color, scheme: .light) {
                XCTAssertGreaterThan(contrast(foreground, stop.color), 4.5)
                XCTAssertGreaterThan(contrast(theme.clockAccent(color), stop.color), 4.5)
            }
            for surface in theme.identityChipColors(color) {
                XCTAssertGreaterThan(contrast(theme.identityForeground(color), surface), 4.5)
                XCTAssertGreaterThan(contrast(theme.identitySecondary(color), surface), 4.5)
            }
        }
        XCTAssertGreaterThan(contrast(.white, try XCTUnwrap(theme.actionTint)), 4.5)
        XCTAssertGreaterThan(contrast(.white, theme.statusBadge), 4.5)
    }

    func testGardenNightModePreservesTheDayBoardAndOtherThemes() {
        let theme = SurroundTheme.rakedGarden
        XCTAssertEqual(theme.board, theme.board(for: .light))
        XCTAssertNotEqual(theme.board.boardColor, theme.board(for: .dark).boardColor)
        XCTAssertEqual(StoneImages(black: [], white: []).tint, .white,
                       "Existing rendered-stone callers must keep their original colors")
        for other: SurroundTheme in [.standard, .nebulaPearl, .surroundStudio] {
            for scheme: ColorScheme in [.light, .dark] {
                XCTAssertEqual(other.board(for: scheme), other.board)
            }
        }
    }

    /// These are nominal opaque palette checks. Native captures separately
    /// verify the graded texture, rendered stones and translucent controls.
    func testGardenNightStonesGridAndMarksRemainReadable() throws {
        let board = SurroundTheme.rakedGarden.board(for: .dark)
        XCTAssertGreaterThan(contrast(board.black.flat, board.boardColor, style: .dark), 3)
        XCTAssertGreaterThan(contrast(board.white.flat, board.black.flat, style: .dark), 4.5)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.white.outline), board.boardColor, style: .dark), 3)
        XCTAssertGreaterThan(contrast(board.gridColor, board.boardColor, style: .dark), 3)
        XCTAssertGreaterThan(contrast(board.coordinateColor, board.boardColor, style: .dark), 4.5)
        XCTAssertGreaterThan(contrast(board.emptyPointMarker, board.boardColor, style: .dark), 4.5)
        let highlightCasing = try XCTUnwrap(board.highlightCasing)
        XCTAssertGreaterThan(contrast(highlightCasing, board.black.flat, style: .dark), 3)
        for surface in [board.boardColor, board.white.flat, highlightCasing] {
            XCTAssertGreaterThan(contrast(board.highlightColor, surface, style: .dark), 3)
        }
        for stone in [board.black, board.white] {
            XCTAssertGreaterThan(contrast(stone.lastMove, stone.flat, style: .dark), 4.5)
            XCTAssertGreaterThan(contrast(stone.label, stone.flat, style: .dark), 4.5)
            XCTAssertGreaterThan(contrast(stone.territoryMark, board.boardColor, style: .dark), 3)
        }
        XCTAssertGreaterThan(contrast(board.black.territoryMark, board.white.territoryMark, style: .dark), 3)
        for mark in [board.removeMark, board.restoreMark, board.crosshair.valid,
                     board.crosshair.invalid, board.crosshair.removal] {
            XCTAssertGreaterThan(contrast(mark, board.boardColor, style: .dark), 3)
        }
        let casing = try XCTUnwrap(board.removalMarkCasing)
        XCTAssertGreaterThan(contrast(board.removeMark, casing, style: .dark), 3)
        XCTAssertGreaterThan(contrast(board.restoreMark, casing, style: .dark), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.removedStoneOutline), board.boardColor, style: .dark), 3)
    }

    func testGardenNightAnalysisMarksRemainReadable() throws {
        let theme = SurroundTheme.rakedGarden
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        XCTAssertGreaterThan(contrast(theme.selectionMark, theme.panel, style: .dark), 3)
        XCTAssertGreaterThan(contrast(theme.selectionMark, keyline, style: .dark), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(theme.conditionalMark), keyline, style: .dark), 3)
        XCTAssertGreaterThan(contrast(theme.userTurnMark, theme.idleGameMark(scheme: .dark), style: .dark), 3)
    }

    func testGardenNightControlFallbacksKeepReadableTextAndRoles() throws {
        let theme = SurroundTheme.rakedGarden
        XCTAssertGreaterThan(contrast(theme.foreground, theme.pageBackground, style: .dark), 4.5)
        XCTAssertGreaterThan(contrast(theme.foreground, theme.panel, style: .dark), 4.5)
        let players = [
            OGSUser(username: "ordinary", id: 1),
            OGSUser(username: "moderator", id: 2, isModerator: true),
            OGSUser(username: "admin", id: 3, isSuperuser: true),
            OGSUser(username: "professional", id: 4, professional: true),
            OGSUser(username: "supporter", id: 5, supporter: true),
            OGSUser(username: "bot", id: 6, isBot: true),
        ]
        for color: StoneColor in [.black, .white] {
            let foreground = theme.clockForeground(color, scheme: .dark)
            let surfaces = [theme.clockSolidSurface(color)]
                + theme.clockSurfaceStops(color, scheme: .dark).map(\.color)
            for surface in surfaces {
                XCTAssertGreaterThan(contrast(foreground, surface, style: .dark), 4.5)
                XCTAssertGreaterThan(contrast(theme.clockAccent(color), surface, style: .dark), 4.5)
                XCTAssertGreaterThanOrEqual(
                    contrast(theme.clockSuddenDeathAccent(color, scheme: .dark), surface, style: .dark), 4.5)
            }
            for surface in theme.identityChipColors(color) {
                XCTAssertGreaterThan(contrast(theme.identityForeground(color), surface, style: .dark), 4.5)
                XCTAssertGreaterThan(contrast(theme.identitySecondary(color), surface, style: .dark), 4.5)
                for player in players {
                    let roleColor = try XCTUnwrap(theme.identityRoleColor(for: player, on: color))
                    XCTAssertGreaterThan(contrast(roleColor, surface, style: .dark), 4.5,
                                         "\(player.username) must read on the \(color) night identity")
                }
            }
        }
        XCTAssertGreaterThan(contrast(.white, try XCTUnwrap(theme.actionTint), style: .dark), 4.5)
        XCTAssertGreaterThan(contrast(.white, theme.statusBadge, style: .dark), 4.5)
    }

    func testGardenAdaptiveColorsFollowRepeatedTraitChanges() {
        let theme = SurroundTheme.rakedGarden
        // Keep the same Color values alive while resolving both directions;
        // dynamic providers must not freeze the first trait collection seen.
        for color in [theme.pageBackground, theme.panel, theme.foreground] {
            let day = luminance(color, style: .light)
            let night = luminance(color, style: .dark)
            XCTAssertGreaterThan(abs(day - night), 0.1)
            for style: UIUserInterfaceStyle in [.dark, .light, .dark, .light] {
                XCTAssertEqual(luminance(color, style: style), style == .dark ? night : day,
                               accuracy: 0.000001)
            }
        }
        XCTAssertLessThan(luminance(theme.pageBackground, style: .dark),
                          luminance(theme.pageBackground, style: .light))
    }

    func testGardenNightModeKeepsRaggedGridGeometryAndStoneLighting() {
        let day = SurroundTheme.rakedGarden.board(for: .light)
        let night = SurroundTheme.rakedGarden.board(for: .dark)
        XCTAssertEqual(day.gridStyle, .ragged)
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        for cell: CGFloat in [9.99, 19.5, 21, 48] {
            XCTAssertEqual(night.gridStyle.usesRaggedEdges(at: cell),
                           day.gridStyle.usesRaggedEdges(at: cell))
            let dayPath = RaggedGridGeometry(width: 19, height: 13, cellSize: cell,
                                            lineScale: day.gridLineScale).path
            let nightPath = RaggedGridGeometry(width: 19, height: 13, cellSize: cell,
                                              lineScale: night.gridLineScale).path
            XCTAssertEqual(polygons(in: nightPath), polygons(in: dayPath))
        }
    }

    /// Role names and avatar outlines use OGS colors rather than the
    /// ordinary identity foreground, so each role needs its own contrast.
    func testLightSceneIdentityRoleColorsRemainReadable() throws {
        let players = [
            OGSUser(username: "ordinary", id: 1),
            OGSUser(username: "moderator", id: 2, isModerator: true),
            OGSUser(username: "admin", id: 3, isSuperuser: true),
            OGSUser(username: "professional", id: 4, professional: true),
            OGSUser(username: "supporter", id: 5, supporter: true),
            OGSUser(username: "bot", id: 6, isBot: true),
        ]
        for theme: SurroundTheme in [.rakedGarden, .surroundStudio] {
            for player in players {
                for color: StoneColor in [.black, .white] {
                    let foreground = try XCTUnwrap(theme.identityRoleColor(for: player, on: color))
                    for surface in theme.identityChipColors(color) {
                        XCTAssertGreaterThan(contrast(foreground, surface), 4.5,
                                             "\(player.username) must read on the \(color) \(theme) identity")
                    }
                }
            }
        }
    }

    func testGardenIdentityRolesKeepOGSPriorityAndLightweightPayloadSupport() {
        let theme = SurroundTheme.rakedGarden
        let cases: [(String, OGSUser)] = [
            ("admin professional supporter bot", OGSUser(username: "admin", id: 1, isSuperuser: true)),
            ("moderator professional supporter bot", OGSUser(username: "moderator", id: 2, isModerator: true)),
            ("professional supporter bot", OGSUser(username: "professional", id: 3, professional: true)),
            ("supporter bot", OGSUser(username: "supporter", id: 4, supporter: true)),
            ("bot", OGSUser(username: "bot", id: 5, isBot: true)),
        ]
        for (classes, expectedPlayer) in cases {
            let lightweightPlayer = OGSUser(username: "lightweight", id: 6, uiClass: classes)
            for color: StoneColor in [.black, .white] {
                XCTAssertEqual(theme.identityRoleColor(for: lightweightPlayer, on: color),
                               theme.identityRoleColor(for: expectedPlayer, on: color))
            }
        }
        let bot = OGSUser(username: "bot", id: 7, isBot: true)
        for color: StoneColor in [.black, .white] {
            XCTAssertEqual(theme.identityRoleColor(for: bot, on: color), theme.identitySecondary(color))
        }
    }

    func testExistingThemesKeepTheirIdentityRoleColorPath() {
        let player = OGSUser(username: "moderator", id: 1, isModerator: true)
        for theme: SurroundTheme in [.standard, .nebulaPearl] {
            for color: StoneColor in [.black, .white] {
                XCTAssertNil(theme.identityRoleColor(for: player, on: color))
            }
        }
    }

    /// Cream clamshell needs a contour against golden kaya in thumbnails;
    /// actual moves and scoring marks must remain stronger than the texture.
    func testStudioStonesAndNativeMarksRemainReadable() throws {
        let theme = SurroundTheme.surroundStudio, board = theme.board
        XCTAssertEqual(board.stoneLightDirection, .upperLeft)
        XCTAssertEqual(board.gridStyle, .straight)
        XCTAssertTrue(board.boardBevel)
        XCTAssertGreaterThan(contrast(board.black.flat, board.boardColor), 7)
        XCTAssertGreaterThan(contrast(board.white.flat, board.black.flat), 7)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.white.outline), board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.gridColor, board.boardColor), 3)
        XCTAssertGreaterThan(contrast(board.coordinateColor, board.boardColor), 4.5)
        for stone in [board.black, board.white] {
            XCTAssertGreaterThan(contrast(stone.lastMove, stone.flat), 4.5)
            XCTAssertGreaterThan(contrast(stone.label, stone.flat), 4.5)
            XCTAssertGreaterThan(contrast(stone.territoryMark, board.boardColor), 3)
        }
        XCTAssertGreaterThan(contrast(board.black.territoryMark, board.white.territoryMark), 2)
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        XCTAssertGreaterThan(contrast(theme.selectionMark, theme.panel), 3)
        XCTAssertGreaterThan(contrast(theme.selectionMark, keyline), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(theme.conditionalMark), keyline), 3)
        XCTAssertGreaterThan(contrast(theme.userTurnMark, theme.idleGameMark(scheme: .light)), 3)
        for mark in [board.removeMark, board.restoreMark, board.crosshair.valid,
                     board.crosshair.invalid, board.crosshair.removal] {
            XCTAssertGreaterThan(contrast(mark, board.boardColor), 3)
        }
        let casing = try XCTUnwrap(board.removalMarkCasing)
        XCTAssertGreaterThan(contrast(board.removeMark, casing), 3)
        XCTAssertGreaterThan(contrast(board.restoreMark, casing), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(board.removedStoneOutline), board.boardColor), 3)
    }

    func testStudioControlFallbacksKeepReadableText() throws {
        let theme = SurroundTheme.surroundStudio
        XCTAssertGreaterThan(contrast(theme.foreground, theme.pageBackground), 7)
        XCTAssertGreaterThan(contrast(theme.foreground, theme.panel), 7)
        for color: StoneColor in [.black, .white] {
            let foreground = theme.clockForeground(color, scheme: .light)
            XCTAssertGreaterThan(contrast(foreground, theme.clockSolidSurface(color)), 4.5)
            for stop in theme.clockSurfaceStops(color, scheme: .light) {
                XCTAssertGreaterThan(contrast(foreground, stop.color), 4.5)
                XCTAssertGreaterThan(contrast(theme.clockAccent(color), stop.color), 4.5)
            }
            for surface in theme.identityChipColors(color) {
                XCTAssertGreaterThan(contrast(theme.identityForeground(color), surface), 4.5)
                XCTAssertGreaterThan(contrast(theme.identitySecondary(color), surface), 4.5)
            }
        }
        XCTAssertGreaterThan(contrast(.white, try XCTUnwrap(theme.actionTint)), 4.5)
        XCTAssertGreaterThan(contrast(.white, theme.statusBadge), 4.5)
    }

    /// Catch a missing catalog entry, flattened decoration transparency,
    /// opaque stone padding or mismatched stone diameter.
    func testStudioAssetsKeepSeparateBoardAndEqualAlphaStoneFootprints() throws {
        // This target runs in xctest, with the catalog in the test bundle;
        // the runtime theme correctly loads its images from the app bundle.
        let bundle = Bundle(for: SurroundThemeTests.self)
        func image(named name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        let side = 128
        func rgbaPixels(for source: CGImage) throws -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                    width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            return pixels
        }
        _ = try image(named: "SurroundStudioBoard")
        _ = try image(named: "SurroundStudioScene")
        for name in ["SurroundStudioFoliage", "SurroundStudioVase"] {
            let source = try XCTUnwrap(image(named: name).cgImage, name)
            let pixels = try rgbaPixels(for: source)
            let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            XCTAssertTrue(alpha.contains(0), "\(name) leaves the room visible around its artwork")
            XCTAssertTrue(alpha.contains { $0 > 250 }, "\(name) contains visible artwork")
        }
        let stones = try StoneImages(
            black: (0..<4).map { try image(named: "SurroundStudioSlate\($0)") },
            white: (0..<4).map { try image(named: "SurroundStudioClamshell\($0)") }
        )
        var footprints: [Int] = []
        for image in stones.black + stones.white {
            let source = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(source.width, source.height)
            XCTAssertGreaterThanOrEqual(source.width, 256)
            let pixels = try rgbaPixels(for: source)
            func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * side + x) * 4 + 3] }
            XCTAssertEqual(alpha(0, 0), 0)
            XCTAssertEqual(alpha(side - 1, side - 1), 0)
            XCTAssertEqual(alpha(0, side / 2), 0)
            XCTAssertEqual(alpha(side - 1, side / 2), 0)
            XCTAssertGreaterThan(alpha(side / 2, side / 2), 250)
            let diameter = (0..<side).filter { alpha($0, side / 2) > 127 }.count
            XCTAssertEqual(CGFloat(diameter) / CGFloat(side), stones.footprint, accuracy: 0.02)
            footprints.append(diameter)
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(footprints.max()) - XCTUnwrap(footprints.min()), 1,
                                 "Slate and shell use equal diameters across every variant")
    }

    func testStudioFoliageKeepsNaturalScaleAndReservesChrome() {
        for size in [CGSize(width: 375, height: 548), CGSize(width: 375, height: 667),
                     CGSize(width: 402, height: 874),
                     CGSize(width: 874, height: 402), CGSize(width: 820, height: 1180),
                     CGSize(width: 1180, height: 820)] {
            let layout = SurroundStudioDecorationLayout(size: size)
            let folded = SurroundStudioDecorationLayout(size: size, hasTopEdgeClocks: true)
            let legacy = SurroundStudioDecorationLayout(size: size, usesLegacyChrome: true)
            XCTAssertEqual(layout.foliage.size, folded.foliage.size)
            XCTAssertEqual(layout.foliage.size, legacy.foliage.size,
                           "Chrome clearance must not miniaturize the leaves")
            XCTAssertLessThanOrEqual(layout.foliage.maxY, 128)
            XCTAssertLessThanOrEqual(folded.foliage.maxY, 88)
            XCTAssertLessThanOrEqual(legacy.foliage.maxY, 80,
                                    "Legacy Analyze move numbers begin just below the shorter navigation bar")
            if size.width > size.height && size.height < 430 {
                XCTAssertLessThanOrEqual(layout.foliage.maxY, 84,
                                        "The fixed canopy clears the landscape Chat board's upper grid")
            }
            if size.width < size.height && size.height < 600 {
                XCTAssertLessThanOrEqual(layout.foliage.maxY, 75,
                                        "Small floating windows keep their upper clock cards clear")
            }
        }
    }

    func testTiledBoardTextureKeepsItsPointSizeAsTheBoardResizes() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in }
        let texture = BoardTexture(image: image, tileSize: 320)
        XCTAssertEqual(texture.tint, .white, "Existing board textures must remain ungraded by default")
        for size in [CGSize(width: 150, height: 150), CGSize(width: 1024, height: 1024)] {
            XCTAssertEqual(texture.paintScale(in: size), 1.6, accuracy: 0.0001)
        }
    }

    func testBoardWideTextureCoversEachAspectRatioWithoutRepeating() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in }
        let texture = BoardTexture(image: image, mapping: .board)
        let sizes = [CGSize(width: 90, height: 90), CGSize(width: 600, height: 300),
                     CGSize(width: 150, height: 500)]
        for size in sizes {
            let scale = texture.paintScale(in: size)
            let coverage = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            XCTAssertGreaterThanOrEqual(coverage.width, size.width)
            XCTAssertGreaterThanOrEqual(coverage.height, size.height)
            XCTAssertEqual(min(coverage.width / size.width, coverage.height / size.height),
                           1, accuracy: 0.0001, "One edge fits while the other covers the board")
        }
    }

    func testBoardWideTextureHasSafeScaleForEmptyLayoutSlots() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in }
        for texture in [BoardTexture(image: image, mapping: .board),
                        BoardTexture(image: UIImage(), mapping: .board)] {
            for size in [CGSize.zero, CGSize(width: 0, height: 300), CGSize(width: 300, height: 0)] {
                let scale = texture.paintScale(in: size)
                XCTAssertTrue(scale.isFinite)
                XCTAssertGreaterThan(scale, 0)
            }
        }
    }

    func testRaggedGridIsGardenOnlyAndFallsBackOnSmallBoards() {
        for theme: SurroundTheme in [.standard, .nebulaPearl, .surroundStudio] {
            XCTAssertFalse(theme.board.gridStyle.usesRaggedEdges(at: 48))
        }
        // Small boards are solid: the scratched grid starts at the detail threshold.
        let style = SurroundTheme.rakedGarden.board.gridStyle
        XCTAssertFalse(style.usesRaggedEdges(at: 13.99))
        XCTAssertTrue(style.usesRaggedEdges(at: 14))
        XCTAssertTrue(style.usesRaggedEdges(at: 48))
        XCTAssertTrue(RaggedGridGeometry(width: 19, height: 19, cellSize: 9.99, lineScale: 1.6).path.isEmpty)
    }

    func testRaggedGridKeepsEveryIntersectionAndContinuousStraightSpines() {
        for size: CGFloat in [10, 36] {
            let path = RaggedGridGeometry(width: 19, height: 13, cellSize: size, lineScale: 1.6).path
            // Quarter-cell samples include every intersection and every
            // span between them, on both axes and all four borders.
            for row in 0..<13 {
                for sample in 0...(18 * 4) {
                    XCTAssertTrue(path.contains(CGPoint(x: (0.5 + CGFloat(sample) / 4) * size,
                                                        y: (CGFloat(row) + 0.5) * size)))
                }
            }
            for column in 0..<19 {
                for sample in 0...(12 * 4) {
                    XCTAssertTrue(path.contains(CGPoint(x: (CGFloat(column) + 0.5) * size,
                                                        y: (0.5 + CGFloat(sample) / 4) * size)))
                }
            }
            // The spine has width, not just a mathematical centerline;
            // the inside of an empty cell must remain unpainted.
            XCTAssertTrue(path.contains(CGPoint(x: size, y: 6.5 * size - 0.2)))
            XCTAssertTrue(path.contains(CGPoint(x: 6.5 * size + 0.2, y: size)))
            XCTAssertFalse(path.contains(CGPoint(x: size, y: size)))
            for x in [0.5 * size, 18.5 * size] {
                for y in [0.5 * size, 12.5 * size] {
                    for offset: CGFloat in [-0.2, 0.2] {
                        XCTAssertTrue(path.contains(CGPoint(x: x + offset, y: y + offset)))
                    }
                }
            }
        }
    }

    func testRaggedGridEdgesAreBoundedAndStableWhenResized() {
        let small = RaggedGridGeometry(width: 9, height: 13, cellSize: 20, lineScale: 1.6)
        let large = RaggedGridGeometry(width: 9, height: 13, cellSize: 48, lineScale: 1.6)
        let first = polygons(in: small.path)
        XCTAssertEqual(first, polygons(in: small.path), "Redrawing must not reseed the edge pattern")
        let resized = polygons(in: large.path)
        XCTAssertEqual(first.count, resized.count)
        for (original, enlarged) in zip(first, resized) where original.count > 4 {
            // Ignore the rectangular spine; inspect the actual filled
            // edge outline without reproducing its sampling algorithm.
            let spanX = original.map(\.x).max()! - original.map(\.x).min()!
            let spanY = original.map(\.y).max()! - original.map(\.y).min()!
            let horizontal = spanX > spanY
            let across = original.map { horizontal ? $0.y : $0.x }
            let center = (across.min()! + across.max()!) / 2
            let line = Int((center / small.cellSize - 0.5).rounded())
            XCTAssertEqual(center, (CGFloat(line) + 0.5) * small.cellSize, accuracy: 0.000001)
            let outer = line == 0 || line == (horizontal ? small.height : small.width) - 1
            let nominalHalfWidth: CGFloat = outer ? 0.8 : 0.4
            let distances = across.map { abs($0 - center) }
            XCTAssertLessThanOrEqual(distances.max()!, nominalHalfWidth + 0.380001)
            XCTAssertGreaterThanOrEqual(distances.min()!, 0.249999)
            XCTAssertGreaterThan(distances.max()! - distances.min()!, 0.1,
                                 "Edges should vary visibly while retaining a solid center")
            for index in 0..<(original.count / 2) {
                let opposite = original[original.count - 1 - index]
                XCTAssertEqual(horizontal ? original[index].x : original[index].y,
                               horizontal ? opposite.x : opposite.y, accuracy: 0.000001)
                XCTAssertEqual((horizontal ? original[index].y : original[index].x)
                               + (horizontal ? opposite.y : opposite.x),
                               2 * center, accuracy: 0.000001, "Edge variation must not bend the centerline")
            }
            XCTAssertEqual(original.count, enlarged.count)
            for (point, scaledPoint) in zip(original, enlarged) {
                let along = horizontal ? point.x : point.y
                let scaledAlong = horizontal ? scaledPoint.x : scaledPoint.y
                let offset = (horizontal ? point.y : point.x) - center
                let scaledOffset = (horizontal ? scaledPoint.y : scaledPoint.x)
                    - center / small.cellSize * large.cellSize
                XCTAssertEqual(along / small.cellSize, scaledAlong / large.cellSize, accuracy: 0.000001)
                // Path stores quantized points; subtracting a larger board's
                // center can differ by a few hundred-thousandths of a point.
                XCTAssertEqual(offset, scaledOffset, accuracy: 0.0001)
            }
        }
    }

    func testGardenSceneAccentsStayAtTheEdgesAcrossWindowShapes() {
        let sizes = [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844),
                     CGSize(width: 844, height: 390), CGSize(width: 1024, height: 1366),
                     CGSize(width: 1366, height: 1024), CGSize(width: 420, height: 900),
                     CGSize(width: 1800, height: 700), CGSize(width: 2500, height: 1500)]
        for size in sizes {
            let layout = RakedGardenSceneLayout(size: size)
            let viewport = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            XCTAssertLessThan(layout.rocks.minX, 0)
            XCTAssertGreaterThan(layout.rocks.maxY, size.height)
            XCTAssertLessThan(layout.upperRocks.minX, 0)
            XCTAssertLessThan(layout.upperRocks.minY, 0)
            XCTAssertLessThan(layout.maple.minY, 0)
            XCTAssertGreaterThan(layout.maple.maxX, size.width)
            XCTAssertLessThanOrEqual(layout.rocks.width, 440)
            XCTAssertLessThanOrEqual(layout.upperRocks.width, 240)
            XCTAssertLessThanOrEqual(layout.upperRocks.maxY, 106)
            XCTAssertLessThanOrEqual(layout.maple.width, 300)
            XCTAssertLessThanOrEqual(layout.maple.maxY, 160)
            let accents: [(CGRect, CGFloat)] = [(layout.rocks, 0.4), (layout.upperRocks, 0.3),
                                                (layout.maple, 0.25)]
            for (accent, minimumVisibleFraction) in accents {
                let visible = accent.intersection(viewport)
                XCTAssertFalse(visible.isNull)
                let visibleFraction = visible.width * visible.height / (accent.width * accent.height)
                XCTAssertGreaterThan(visibleFraction, minimumVisibleFraction,
                                     "Keep a recognizable silhouette inside the scene")
                XCTAssertLessThan(visibleFraction, 0.85, "The artwork should enter from outside the scene")
                XCTAssertFalse(accent.contains(center), "The garden's center stays clear")
            }
            XCTAssertLessThanOrEqual(layout.topFadeHeight, 92)
            XCTAssertLessThanOrEqual(layout.bottomFadeHeight, 96)
            XCTAssertLessThan(layout.topFadeHeight + layout.bottomFadeHeight, size.height * 0.35)
        }
        let portrait = RakedGardenSceneLayout(size: CGSize(width: 390, height: 844))
        let landscape = RakedGardenSceneLayout(size: CGSize(width: 844, height: 390))
        XCTAssertLessThan(landscape.rocks.height, portrait.rocks.height)
        XCTAssertLessThan(landscape.upperRocks.height, portrait.upperRocks.height)
        XCTAssertLessThan(landscape.maple.height, portrait.maple.height)
        let legacyPhone = RakedGardenSceneLayout(size: CGSize(width: 375, height: 667), usesLegacyChrome: true)
        XCTAssertGreaterThan(legacyPhone.maple.maxY, 72, "Allow leaves to overlap the clock's upper edge")
        XCTAssertLessThanOrEqual(legacyPhone.maple.maxY, 100, "Bound the canopy to the legacy clock's upper edge")
        let divided = RakedGardenSceneLayout(size: CGSize(width: 951, height: 669), hasTopEdgeClocks: true)
        XCTAssertLessThanOrEqual(divided.maple.maxY, 100,
                                 "The divided wide layout puts clock text near the top edge")
    }

    func testGardenSceneCompositionDoesNotJumpDuringContinuousResizing() {
        let sweeps = [
            (300...1600).map { CGSize(width: CGFloat($0), height: 600) },
            (300...1600).map { CGSize(width: 900, height: CGFloat($0)) },
            (250...1000).map { CGSize(width: CGFloat($0), height: CGFloat($0)) },
        ]
        for sizes in sweeps {
            let layouts = sizes.map { RakedGardenSceneLayout(size: $0) }
            for (before, after) in zip(layouts, layouts.dropFirst()) {
                for (a, b) in zip(sceneMetrics(before), sceneMetrics(after)) {
                    XCTAssertLessThanOrEqual(abs(b - a), 1.5,
                                             "A one-point resize must not swap or jump the composition")
                }
            }
        }
    }

    func testGardenSceneHasFiniteGeometryForEmptyAndInvalidLayoutSlots() {
        let sizes = [CGSize.zero, CGSize(width: 0, height: 320), CGSize(width: 320, height: 0),
                     CGSize(width: -10, height: 400), CGSize(width: CGFloat.infinity, height: 400),
                     CGSize(width: 400, height: CGFloat.nan)]
        for size in sizes {
            let layout = RakedGardenSceneLayout(size: size)
            XCTAssertTrue(sceneMetrics(layout).allSatisfy { $0.isFinite })
            XCTAssertGreaterThanOrEqual(layout.size.width, 0)
            XCTAssertGreaterThanOrEqual(layout.size.height, 0)
            XCTAssertEqual(layout.rocks.size, CGSize.zero)
            XCTAssertEqual(layout.upperRocks.size, CGSize.zero)
            XCTAssertEqual(layout.maple.size, CGSize.zero)
        }
    }

    func testGardenShadowReachesGameplayAndKeepsABoundedProjection() {
        let sizes = [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844),
                     CGSize(width: 844, height: 390), CGSize(width: 1024, height: 1366),
                     CGSize(width: 1366, height: 1024), CGSize(width: 2500, height: 1500)]
        for size in sizes {
            let shadow = RakedGardenShadowLayout(size: size)
            let scene = RakedGardenSceneLayout(size: size)
            XCTAssertGreaterThan(shadow.canopy.width, scene.maple.width)
            XCTAssertLessThan(shadow.canopy.midX, scene.maple.midX)
            XCTAssertGreaterThan(shadow.canopy.midY, scene.maple.midY)
            XCTAssertGreaterThan(shadow.canopy.maxX, size.width)
            XCTAssertFalse(shadow.canopy.intersection(CGRect(origin: .zero, size: size)).isNull)
            XCTAssertLessThanOrEqual(shadow.canopy.width, 840)
            XCTAssertGreaterThan(shadow.blurRadius, 0)
            XCTAssertLessThanOrEqual(shadow.blurRadius, 5)
        }
        let phone = RakedGardenShadowLayout(size: CGSize(width: 390, height: 844))
        // Phone Play's upper board and Analyze's upper panel both need to
        // receive the cast; a shadow sized only to the ornament misses them.
        XCTAssertTrue(phone.canopy.contains(CGPoint(x: 250, y: 350)))
        XCTAssertTrue(phone.canopy.contains(CGPoint(x: 250, y: 200)))
        let tablet = RakedGardenShadowLayout(size: CGSize(width: 1366, height: 1024))
        XCTAssertTrue(tablet.canopy.contains(CGPoint(x: 1050, y: 350)))
    }

    func testGardenShadowResizesContinuouslyAndHandlesEmptyLayoutSlots() {
        let sweeps = [
            (300...1600).map { CGSize(width: CGFloat($0), height: 600) },
            (300...1600).map { CGSize(width: 900, height: CGFloat($0)) },
        ]
        for sizes in sweeps {
            let layouts = sizes.map { RakedGardenShadowLayout(size: $0) }
            for (before, after) in zip(layouts, layouts.dropFirst()) {
                for (a, b) in zip(shadowMetrics(before), shadowMetrics(after)) {
                    XCTAssertLessThanOrEqual(abs(b - a), 1.5,
                                             "Shadow placement must not jump when the window resizes")
                }
            }
        }
        let invalidSizes = [CGSize.zero, CGSize(width: 0, height: 320),
                            CGSize(width: -10, height: 400),
                            CGSize(width: CGFloat.infinity, height: 400),
                            CGSize(width: 400, height: CGFloat.nan)]
        for size in invalidSizes {
            let layout = RakedGardenShadowLayout(size: size)
            XCTAssertTrue(shadowMetrics(layout).allSatisfy { $0.isFinite })
            XCTAssertEqual(layout.canopy.size, CGSize.zero)
            XCTAssertEqual(layout.blurRadius, 0)
        }
    }

    private func shadowMetrics(_ layout: RakedGardenShadowLayout) -> [CGFloat] {
        [layout.size.width, layout.size.height, layout.canopy.minX, layout.canopy.minY,
         layout.canopy.width, layout.canopy.height, layout.blurRadius]
    }

    private func sceneMetrics(_ layout: RakedGardenSceneLayout) -> [CGFloat] {
        [layout.size.width, layout.size.height,
         layout.rocks.minX, layout.rocks.minY, layout.rocks.width, layout.rocks.height,
         layout.upperRocks.minX, layout.upperRocks.minY, layout.upperRocks.width, layout.upperRocks.height,
         layout.maple.minX, layout.maple.minY, layout.maple.width, layout.maple.height,
         layout.topFadeHeight, layout.bottomFadeHeight]
    }

    private func polygons(in path: Path) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(to: let point): points = [point]
            case .line(to: let point): points.append(point)
            case .closeSubpath: result.append(points)
            default: XCTFail("A scratched grid should contain only straight-edged polygons")
            }
        }
        return result
    }

    /// Every theme and appearance, as small boards draw them: solid colors
    /// only. Stones stand out by fill or by outline; markers read on the
    /// flat stone or board beneath them, or carry a contrasting casing.
    func testSmallBoardsStaySolidAndTheirMarkersReadable() throws {
        let cases: [(String, SurroundTheme, UIUserInterfaceStyle)] = [
            ("standard light", .standard, .light), ("standard dark", .standard, .dark),
            ("nebula", .nebulaPearl, .dark), ("garden day", .rakedGarden, .light),
            ("garden night", .rakedGarden, .dark), ("studio", .surroundStudio, .light),
        ]
        for (name, theme, style) in cases {
            let board = theme.board(for: style == .dark ? .dark : .light)
            let surface = board.surfaceColor(detailed: false)
            func ratio(_ a: Color, _ b: Color) -> Double { contrast(over(a, b, style), b, style: style) }
            var report = [String]()
            func check(_ label: String, _ value: Double, _ minimum: Double) {
                report.append(String(format: "%@ %.1f", label, value))
                XCTAssertGreaterThanOrEqual(value, minimum, "\(name): \(label)")
            }
            for (color, stone) in [("black", board.black), ("white", board.white)] {
                let fill = ratio(stone.flat, surface)
                let outline = stone.outline.map { max(ratio($0, surface), ratio($0, stone.flat)) } ?? 0
                check("\(color) stone", max(fill, outline), 3)
                check("\(color) last move", ratio(stone.lastMove, stone.flat), 3)
                check("\(color) label", ratio(stone.label, stone.flat), 4.5)
                check("\(color) territory", max(ratio(stone.territoryMark, surface), ratio(board.markOutline, surface)), 3)
            }
            check("empty-point mark", ratio(board.emptyPointMarker, surface), 4.5)
            check("dame", ratio(board.dameColor, surface), 3)
            check("grid", ratio(board.gridColor, surface), 3)
            check("coordinates", ratio(board.coordinateColor, surface), 4.5)
            check("highlight on board", ratio(board.highlightColor, surface), 3)
            for (color, stone) in [("black", board.black), ("white", board.white)] {
                let bare = ratio(board.highlightColor, stone.flat)
                let cased = board.highlightCasing.map { ratio($0, stone.flat) } ?? 0
                check("highlight on \(color)", max(bare, cased), 3)
            }
            if let outline = board.removedStoneOutline { check("dead outline", ratio(outline, surface), 3) }
            print("[SmallBoardAudit] \(name): " + report.joined(separator: ", "))
        }
    }

    /// A translucent color as it appears over an opaque one.
    private func over(_ top: Color, _ bottom: Color, _ style: UIUserInterfaceStyle) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(top).resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(bottom).resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB, red: Double(r1 * a1 + r2 * (1 - a1)), green: Double(g1 * a1 + g2 * (1 - a1)),
                     blue: Double(b1 * a1 + b2 * (1 - a1)), opacity: 1)
    }

    private func contrast(_ first: Color, _ second: Color, style: UIUserInterfaceStyle = .light) -> Double {
        let a = luminance(first, style: style), b = luminance(second, style: style)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Resolve explicitly so existing daytime tests never depend on the
    /// simulator's appearance or whichever dynamic color was used first.
    private func luminance(_ color: Color, style: UIUserInterfaceStyle = .light) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let linear = { (value: CGFloat) -> Double in
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

extension SurroundThemeTests {
    func testGardenRaggedEdgesSurviveNativeRasterization() throws {
        let cases: [(cell: CGFloat, scale: CGFloat)] = [(19.5, 2), (21, 3), (48, 2)]
        for (cell, scale) in cases {
            let geometry = RaggedGridGeometry(width: 9, height: 9, cellSize: cell,
                                              lineScale: SurroundTheme.rakedGarden.board.gridLineScale)
            // Constant-width strips prove that antialiasing and pixel phase
            // alone cannot satisfy the visible-variation requirement.
            var straight = Path()
            for line in [2, 6] {
                let center = (CGFloat(line) + 0.5) * cell
                straight.addRect(CGRect(x: cell / 2, y: center - 0.4,
                                        width: 8 * cell, height: 0.8))
                straight.addRect(CGRect(x: center - 0.4, y: cell / 2,
                                        width: 0.8, height: 8 * cell))
            }
            for phase: CGFloat in [0, 0.25] {
                let actual = try gridRaster(geometry.path, cell: cell, scale: scale, phase: phase)
                let control = try gridRaster(straight, cell: cell, scale: scale, phase: phase)
                for vertical in [false, true] {
                    for line in [2, 6] {
                        let widths = gridInkWidths(actual, cell: cell, scale: scale, phase: phase,
                                                   line: line, vertical: vertical)
                        let controlWidths = gridInkWidths(control, cell: cell, scale: scale, phase: phase,
                                                          line: line, vertical: vertical)
                        XCTAssertGreaterThan(widths.count, 100)
                        let spread = gridWidthSpread(widths) / Double(scale)
                        let controlSpread = gridWidthSpread(controlWidths) / Double(scale)
                        let sample = "cell=\(cell), scale=\(scale), phase=\(phase), "
                            + "\(vertical ? "vertical" : "horizontal") line=\(line), spread=\(spread) pt"
                        print("Ragged grid raster: \(sample)")
                        // At least 1 native pixel at 2x / 1.5 pixels at 3x
                        // between ordinary thin and thick portions, not an
                        // isolated extremum. Expectation is an output contract,
                        // independent of the generator's amplitude or hash.
                        XCTAssertGreaterThanOrEqual(spread, 0.5, sample)
                        XCTAssertLessThanOrEqual(controlSpread, 0.02,
                                                 "Straight control must stay straight: \(sample)")
                    }
                }
            }
        }
    }

    private func gridRaster(_ path: Path, cell: CGFloat, scale: CGFloat, phase: CGFloat) throws
        -> (pixels: [UInt8], side: Int) {
        let side = Int(ceil((9 * cell + 1) * scale))
        var pixels = [UInt8](repeating: 255, count: side * side)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
                                                 bitsPerComponent: 8, bytesPerRow: side,
                                                 space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: phase, y: phase)
            context.setFillColor(gray: 0, alpha: 1)
            context.addPath(path.cgPath)
            context.fillPath() // Nonzero fill, as in the production Path.fill.
        }
        return (pixels, side)
    }

    private func gridInkWidths(_ raster: (pixels: [UInt8], side: Int), cell: CGFloat,
                               scale: CGFloat, phase: CGFloat, line: Int, vertical: Bool) -> [Double] {
        let center = (CGFloat(line) + 0.5) * cell + phase
        let across = Int(floor((center - 2) * scale))..<Int(ceil((center + 2) * scale))
        return (0..<raster.side).compactMap { along in
            let position = (CGFloat(along) + 0.5) / scale - phase
            guard position > cell / 2 + 2, position < 8.5 * cell - 2 else { return nil }
            let nearestCrossing = ((position / cell - 0.5).rounded() + 0.5) * cell
            guard abs(position - nearestCrossing) > 2 else { return nil }
            // Integrated coverage counts antialiased edge pixels fractionally;
            // thresholding to black/white would hide subpixel edge differences.
            return across.reduce(0.0) { coverage, perpendicular in
                let x = vertical ? perpendicular : along
                let y = vertical ? along : perpendicular
                return coverage + Double(255 - Int(raster.pixels[y * raster.side + x])) / 255
            }
        }
    }

    private func gridWidthSpread(_ widths: [Double]) -> Double {
        guard !widths.isEmpty else { return 0 }
        let sorted = widths.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.9)]
            - sorted[Int(Double(sorted.count - 1) * 0.1)]
    }
}
