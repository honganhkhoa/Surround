import XCTest
import SwiftUI
import CoreGraphics

final class SurroundThemeTests: XCTestCase {
    func testBoardDepthKeepsThePlayingSurfaceStableAcrossAppearance() throws {
        for theme: SurroundTheme in [.standard, .rakedGarden, .feltMeadow] {
            for scheme: ColorScheme in [.light, .dark] {
                XCTAssertNil(theme.board(for: scheme).boardDepth)
            }
        }
        let nebula = try XCTUnwrap(SurroundTheme.nebulaPearl.board.boardDepth)
        let day = try XCTUnwrap(SurroundTheme.surroundStudio.board(for: .light).boardDepth)
        let night = try XCTUnwrap(SurroundTheme.surroundStudio.board(for: .dark).boardDepth)
        let frostDay = try XCTUnwrap(SurroundTheme.frostPine.board(for: .light).boardDepth)
        let frostNight = try XCTUnwrap(SurroundTheme.frostPine.board(for: .dark).boardDepth)
        for depth in [nebula, day, night, frostDay, frostNight] {
            XCTAssertGreaterThan(depth.thicknessRatio, 0)
            XCTAssertGreaterThan(depth.maximumThickness, 0)
        }
        XCTAssertEqual(day.thicknessRatio, night.thicknessRatio,
                       "Changing appearance must not move the playing surface")
        XCTAssertEqual(day.maximumThickness, night.maximumThickness)
        XCTAssertNotEqual(day.upperFace, night.upperFace)
        XCTAssertNotEqual(day.lowerFace, night.lowerFace)
        XCTAssertEqual(frostDay.thicknessRatio, frostNight.thicknessRatio)
        XCTAssertEqual(frostDay.maximumThickness, frostNight.maximumThickness)
    }

    /// What lines up with a board follows what BoardView draws in its frame:
    /// the face and the sidewall below it, never the shadow's fade.
    func testBoardDepthPlacementReportsTheDrawnFaceAndSidewall() throws {
        let depth = try XCTUnwrap(SurroundTheme.surroundStudio.board(for: .light).boardDepth)
        let frame = CGRect(x: 30, y: 120, width: 700, height: 700)
        let placement = BoardDepthPlacement(boardWidth: 19, boardHeight: 19, showsCoordinates: true,
                                            displayScale: 2, depth: depth)
        let geometry = BoardDepthGeometry(containerSize: frame.size, boardWidth: 19, boardHeight: 19,
                                          showsCoordinates: true, displayScale: 2, depth: depth)
        let drawn = placement.visibleBoard(in: frame)
        XCTAssertGreaterThan(geometry.thickness, 0)
        XCTAssertEqual(drawn.minX, frame.minX + geometry.faceRect.minX, accuracy: 0.001)
        XCTAssertEqual(drawn.width, geometry.faceRect.width, accuracy: 0.001)
        XCTAssertEqual(drawn.minY, frame.minY + geometry.faceRect.minY, accuracy: 0.001)
        XCTAssertEqual(drawn.maxY, frame.minY + geometry.faceRect.maxY + geometry.thickness, accuracy: 0.001)
        XCTAssertLessThan(drawn.maxY, frame.maxY, "The shadow fades below the sidewall")

        var flat = placement
        flat.depth = nil
        XCTAssertEqual(flat.visibleBoard(in: frame), frame)
        // 10 pt cells are below the detail threshold, where boards have no depth.
        let compact = CGRect(x: 4, y: 4, width: 200, height: 200)
        XCTAssertEqual(placement.visibleBoard(in: compact), compact)
        XCTAssertEqual(placement.visibleBoard(in: .zero), .zero)
    }

    /// Public games' cards and Home's Large tiles: the players' rows above and
    /// below a board that spans the column run edge to edge with it as drawn.
    func testBoardColumnRowsMeetTheDrawnBoard() throws {
        let depth = try XCTUnwrap(SurroundTheme.surroundStudio.board(for: .light).boardDepth)
        let board = BoardDepthPlacement(boardWidth: 19, boardHeight: 19, showsCoordinates: false,
                                        displayScale: 3, depth: depth)
        // A 337 pt card on an iPhone, with nothing limiting its height.
        let column = BoardColumnLayout.Column(width: 337, height: nil, rows: 60, board: board)
        let drawn = board.visibleBoard(in: CGRect(x: 0, y: 0, width: 337, height: 337))
        XCTAssertEqual(column.side, 337)
        XCTAssertEqual(column.rowWidth, drawn.width, accuracy: 0.001)
        XCTAssertLessThan(column.rowWidth, 337 - 8, "Studio insets each side by about 5 pt")
        XCTAssertEqual(BoardColumnLayout.Column(width: 337, height: 600, rows: 60, board: board), column)
        XCTAssertEqual(BoardColumnLayout.Column(width: 337, height: .infinity, rows: 60, board: board), column)

        // A board shorter than the column's width leaves the rows at that width.
        let short = BoardColumnLayout.Column(width: 337, height: 300, rows: 60, board: board)
        XCTAssertEqual(short.side, 240)
        XCTAssertEqual(short.rowWidth, 337)

        // Flat themes keep the rows a VStack gives them.
        var flat = board
        flat.depth = nil
        let flatColumn = BoardColumnLayout.Column(width: 337, height: nil, rows: 60, board: flat)
        XCTAssertEqual(flatColumn.side, 337)
        XCTAssertEqual(flatColumn.rowWidth, 337)
    }

    /// Compact boards keep their exact slot, including rectangular previews;
    /// disabling depth for a widget must preserve that footprint at any size.
    func testBoardDepthKeepsCompactAndDisabledFootprintsUnchanged() {
        let depths: [BoardDepth?] = [nil, SurroundTheme.nebulaPearl.board.boardDepth,
                                    SurroundTheme.surroundStudio.board(for: .light).boardDepth,
                                    SurroundTheme.surroundStudio.board(for: .dark).boardDepth,
                                    SurroundTheme.frostPine.board(for: .light).boardDepth,
                                    SurroundTheme.frostPine.board(for: .dark).boardDepth]
        for depth in depths {
            for boardSize in [9, 13, 19] {
                for coordinates in [false, true] {
                    let count = boardSize + (coordinates ? 1 : 0)
                    for scale: CGFloat in [2, 3] {
                        let cells: [CGFloat] = depth == nil ? [0, 7, 13, 14, 20, 40, 64]
                            : [0, 7, 13, 14 - 1 / scale, 14]
                        for cell in cells {
                            let side = cell * CGFloat(count)
                            for size in [CGSize(width: side, height: side),
                                         CGSize(width: side, height: side + 28)] {
                                let layout = BoardDepthGeometry(containerSize: size, boardWidth: boardSize,
                                                                boardHeight: boardSize, showsCoordinates: coordinates,
                                                                displayScale: scale, depth: depth)
                                XCTAssertEqual(layout.thickness, 0)
                                XCTAssertEqual(layout.cornerRadius, 0)
                                XCTAssertEqual(layout.shadowRadius, 0)
                                XCTAssertEqual(layout.shadowOffset, 0)
                                XCTAssertEqual(layout.faceRect, CGRect(origin: .zero, size: size),
                                               "A flat board must not shrink or shift its grid")
                                let flat = BoardDepthGeometry(containerSize: size, boardWidth: boardSize,
                                                              boardHeight: boardSize, showsCoordinates: coordinates,
                                                              displayScale: scale, depth: nil)
                                XCTAssertEqual(layout.cellSize, flat.cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The wall and its shadow fade stay inside the board's clipped slot.
    /// Corner rounding must preserve the stones at outer intersections.
    /// Check every native-pixel step, coordinate margin and detail cutoff.
    func testBoardDepthFitsPhoneAndTabletSlotsWithoutLosingDetailedCells() throws {
        let depths = try [XCTUnwrap(SurroundTheme.nebulaPearl.board.boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board(for: .dark).boardDepth),
                          XCTUnwrap(SurroundTheme.frostPine.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.frostPine.board(for: .dark).boardDepth)]
        for depth in depths {
            for boardSize in [9, 13, 19] {
                for coordinates in [false, true] {
                    let count = boardSize + (coordinates ? 1 : 0)
                    for scale: CGFloat in [2, 3] {
                        for pixels in Int(7 * scale)...Int(64 * scale) {
                            let side = CGFloat(pixels) / scale * CGFloat(count)
                            let layout = BoardDepthGeometry(containerSize: CGSize(width: side, height: side),
                                                            boardWidth: boardSize, boardHeight: boardSize,
                                                            showsCoordinates: coordinates, displayScale: scale, depth: depth)
                            let detail = "board=\(boardSize), coordinates=\(coordinates), pixels=\(pixels), scale=\(scale)"
                            let face = layout.faceRect
                            for value in [face.minX, face.minY, face.width, face.height,
                                          layout.thickness, layout.cellSize, layout.cornerRadius,
                                          layout.shadowRadius, layout.shadowOffset] {
                                XCTAssertTrue(value.isFinite, detail)
                                XCTAssertGreaterThanOrEqual(value, 0, detail)
                            }
                            XCTAssertEqual(face.width, face.height, accuracy: 0.000001, detail)
                            XCTAssertEqual(face.midX, side / 2, accuracy: 0.000001, detail)
                            XCTAssertLessThanOrEqual(face.maxX, side + 0.000001, detail)
                            XCTAssertLessThanOrEqual(face.maxY + layout.thickness, side + 0.000001, detail)
                            XCTAssertLessThanOrEqual(layout.thickness, depth.maximumThickness, detail)
                            XCTAssertLessThanOrEqual(layout.cornerRadius, layout.cellSize / 2,
                                                    "Keep an edge stone's complete silhouette: \(detail)")
                            assertBoardShadowFits(layout, in: CGSize(width: side, height: side), detail: detail)
                            XCTAssertEqual(layout.cellSize * scale, (layout.cellSize * scale).rounded(),
                                           accuracy: 0.000001, detail)
                            if layout.thickness > 0 {
                                XCTAssertGreaterThanOrEqual(layout.cellSize, 14,
                                                            "Depth must not turn detailed stones flat: \(detail)")
                                XCTAssertGreaterThan(layout.cornerRadius, 0, detail)
                                XCTAssertGreaterThan(layout.shadowRadius, 0, detail)
                            }
                            if CGFloat(pixels) / scale >= 20 {
                                XCTAssertGreaterThan(layout.thickness, 0, detail)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Depth grows continuously out of the flat board rather than inserting
    /// a fixed inset on the frame where detailed rendering becomes active.
    func testBoardDepthStartsContinuouslyAtTheDetailThreshold() throws {
        let depths = try [XCTUnwrap(SurroundTheme.nebulaPearl.board.boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board.boardDepth)]
        let epsilon: CGFloat = 0.0001
        for depth in depths {
            for count in [9, 10, 13, 14, 19, 20] {
                for scale: CGFloat in [2, 3] {
                    let side = CGFloat(count) * 14
                    let before = BoardDepthGeometry(containerSize: CGSize(width: side - epsilon, height: side - epsilon),
                                                    boardWidth: count, boardHeight: count, showsCoordinates: false,
                                                    displayScale: scale, depth: depth)
                    let at = BoardDepthGeometry(containerSize: CGSize(width: side, height: side),
                                                boardWidth: count, boardHeight: count, showsCoordinates: false,
                                                displayScale: scale, depth: depth)
                    let after = BoardDepthGeometry(containerSize: CGSize(width: side + epsilon, height: side + epsilon),
                                                   boardWidth: count, boardHeight: count, showsCoordinates: false,
                                                   displayScale: scale, depth: depth)
                    XCTAssertEqual(before.thickness, 0)
                    XCTAssertEqual(at.thickness, 0)
                    XCTAssertGreaterThan(after.thickness, 0)
                    XCTAssertLessThan(after.thickness, epsilon)
                    for (beforeValue, atValue, afterValue) in [
                        (before.cornerRadius, at.cornerRadius, after.cornerRadius),
                        (before.shadowRadius, at.shadowRadius, after.shadowRadius),
                        (before.shadowOffset, at.shadowOffset, after.shadowOffset)
                    ] {
                        XCTAssertEqual(beforeValue, 0)
                        XCTAssertEqual(atValue, 0)
                        XCTAssertGreaterThan(afterValue, 0)
                        XCTAssertLessThan(afterValue, epsilon,
                                          "Rounding and shadow must grow continuously with depth")
                    }
                    XCTAssertLessThan(abs(after.faceRect.width - at.faceRect.width), epsilon * 2)
                    XCTAssertLessThan(abs(after.faceRect.minX - at.faceRect.minX), epsilon)
                    XCTAssertLessThan(abs(after.faceRect.minY - at.faceRect.minY), epsilon)
                    XCTAssertGreaterThanOrEqual(after.cellSize, 14)
                }
            }
        }
    }

    /// A rectangular board's shorter coordinate gutter can make its cells
    /// compact even when dividing the slot by the longer dimension suggests
    /// detail. Such boards must not shrink to reserve an invisible sidewall.
    func testRectangularCoordinateBoardsKeepTheirCompactFootprint() throws {
        let depths = try [XCTUnwrap(SurroundTheme.nebulaPearl.board.boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board.boardDepth)]
        let cases: [(Int, Int, CGFloat)] = [(9, 19, 285), (9, 19, 290),
                                          (19, 9, 285), (19, 9, 290), (13, 19, 285)]
        for depth in depths {
            for (width, height, side) in cases {
                for scale: CGFloat in [2, 3] {
                    let size = CGSize(width: side, height: side)
                    let layout = BoardDepthGeometry(containerSize: size, boardWidth: width, boardHeight: height,
                                                    showsCoordinates: true, displayScale: scale, depth: depth)
                    let grid = boardGridSize(containerSize: layout.faceRect.size, boardWidth: width,
                                             boardHeight: height, showsCoordinates: true)
                    let renderedCell = floor(min(grid.width, grid.height) / CGFloat(max(width, height)) * scale) / scale
                    XCTAssertLessThan(renderedCell, 14)
                    XCTAssertEqual(layout.cellSize, renderedCell)
                    XCTAssertEqual(layout.thickness, 0)
                    XCTAssertEqual(layout.cornerRadius, 0)
                    XCTAssertEqual(layout.shadowRadius, 0)
                    XCTAssertEqual(layout.shadowOffset, 0)
                    XCTAssertEqual(layout.faceRect, CGRect(origin: .zero, size: size),
                                   "Compact \(width)×\(height) coordinates must retain their original grid")
                }
            }
        }
    }

    /// Match the grid the renderer actually receives, including rectangular
    /// boards and nonsquare layout proposals, before deciding to show depth.
    func testBoardDepthCellSizeMatchesTheRenderedGridForRectangularBoards() throws {
        let depths = try [XCTUnwrap(SurroundTheme.nebulaPearl.board.boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.surroundStudio.board(for: .dark).boardDepth)]
        let sizes = [CGSize(width: 290, height: 290), CGSize(width: 400, height: 400),
                     CGSize(width: 600, height: 600), CGSize(width: 390, height: 844),
                     CGSize(width: 844, height: 390)]
        for depth in depths {
            for (width, height) in [(9, 19), (19, 9), (13, 19), (19, 13)] {
                for size in sizes {
                    for coordinates in [false, true] {
                        for scale: CGFloat in [2, 3] {
                            let layout = BoardDepthGeometry(containerSize: size, boardWidth: width, boardHeight: height,
                                                            showsCoordinates: coordinates, displayScale: scale, depth: depth)
                            let grid = boardGridSize(containerSize: layout.faceRect.size, boardWidth: width,
                                                     boardHeight: height, showsCoordinates: coordinates)
                            let renderedCell = floor(min(grid.width, grid.height) / CGFloat(max(width, height)) * scale) / scale
                            XCTAssertEqual(layout.cellSize, renderedCell,
                                           "\(width)×\(height), slot=\(size), coordinates=\(coordinates), scale=\(scale)")
                            if layout.thickness > 0 {
                                XCTAssertGreaterThanOrEqual(renderedCell, 14,
                                                            "Depth must never reserve space for a compact rendered grid")
                            }
                            XCTAssertGreaterThanOrEqual(layout.faceRect.minX, 0)
                            XCTAssertGreaterThanOrEqual(layout.faceRect.minY, 0)
                            XCTAssertLessThanOrEqual(layout.faceRect.maxX, size.width + 0.000001)
                            XCTAssertLessThanOrEqual(layout.faceRect.maxY + layout.thickness, size.height + 0.000001)
                            XCTAssertLessThanOrEqual(layout.cornerRadius, renderedCell / 2)
                            assertBoardShadowFits(layout, in: size,
                                                  detail: "\(width)×\(height), slot=\(size), coordinates=\(coordinates)")
                        }
                    }
                }
            }
        }
    }

    /// The board slot clips its contents. Reserve the visible shadow fade
    /// around the entire slab, including its downward offset, rather than
    /// checking only that the solid face fits.
    private func assertBoardShadowFits(_ layout: BoardDepthGeometry, in size: CGSize, detail: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let slab = CGRect(x: layout.faceRect.minX, y: layout.faceRect.minY,
                          width: layout.faceRect.width, height: layout.faceRect.height + layout.thickness)
        let shadowBounds = slab.offsetBy(dx: 0, dy: layout.shadowOffset)
            .insetBy(dx: -3 * layout.shadowRadius, dy: -3 * layout.shadowRadius)
        XCTAssertGreaterThanOrEqual(shadowBounds.minX, -0.000001, detail, file: file, line: line)
        XCTAssertGreaterThanOrEqual(shadowBounds.minY, -0.000001, detail, file: file, line: line)
        XCTAssertLessThanOrEqual(shadowBounds.maxX, size.width + 0.000001, detail, file: file, line: line)
        XCTAssertLessThanOrEqual(shadowBounds.maxY, size.height + 0.000001, detail, file: file, line: line)
    }

    /// A last-move ring must leave the stone's color and an open center
    /// visible at phone sizes, including either side of the former 20 pt jump.
    func testPhoneLastMoveRingsPreserveTheStoneFace() {
        for cellSize: CGFloat in [14, 17, 19.667, 20, 20.333, 24, 30] {
            let marker = StoneMarkerGeometry(cellSize: cellSize)
            let outerDiameter = marker.ringDiameter + marker.lineWidth
            let innerDiameter = marker.ringDiameter - marker.lineWidth
            let ringAreaFraction = (outerDiameter * outerDiameter - innerDiameter * innerDiameter)
                / (marker.stoneDiameter * marker.stoneDiameter)
            XCTAssertLessThan(ringAreaFraction, 0.15, "cell=\(cellSize): the ring must not wash out the stone")
            XCTAssertGreaterThan(innerDiameter, marker.stoneDiameter * 0.2,
                                 "cell=\(cellSize): retain a clearly open center")
            XCTAssertLessThan(outerDiameter, marker.stoneDiameter,
                              "cell=\(cellSize): keep the ring separate from the stone's rim")
        }
        let before = StoneMarkerGeometry(cellSize: 19.667)
        let atThreshold = StoneMarkerGeometry(cellSize: 20)
        let after = StoneMarkerGeometry(cellSize: 20.333)
        XCTAssertLessThan(abs(atThreshold.lineWidth - before.lineWidth), 0.03,
                          "Resizing through 20 pt must not visibly change the marker weight")
        XCTAssertLessThan(abs(after.lineWidth - atThreshold.lineWidth), 0.03,
                          "Resizing through 20 pt must not visibly change the marker weight")
    }

    /// Cover each native-pixel cell step, not just whole point sizes. All
    /// centered marks must leave part of the stone face and its rim exposed;
    /// diagonal removal strokes and square corners are the widest cases.
    func testMarkerGeometryFitsPhoneAndTabletStoneFacesAtBothDisplayScales() {
        for scale: CGFloat in [2, 3] {
            for pixels in Int(7 * scale)...Int(64 * scale) {
                let cell = CGFloat(pixels) / scale
                let marker = StoneMarkerGeometry(cellSize: cell)
                let shapeCasing = usesDetailedStoneRendering(at: cell) ? marker.casingWidth : 0
                let restoreWidth = marker.restoreLineWidth(displayScale: scale)
                let restoreCasing = marker.restoreCasingWidth(displayScale: scale)
                let availableRadius = marker.stoneDiameter / 2 - 0.5 / scale
                let samples: [(String, CGFloat)] = [
                    ("last move", marker.ringDiameter / 2 + marker.lineWidth / 2 + shapeCasing),
                    ("pending", marker.pendingDiameter / 2 + marker.lineWidth / 2 + shapeCasing),
                    ("square", marker.shapeDiameter / sqrt(2) + marker.lineWidth / 2 + shapeCasing),
                    ("removal", marker.actionDiameter / sqrt(2) + marker.actionLineWidth / 2 + marker.casingWidth),
                    ("restore", marker.actionDiameter / 2 + restoreWidth / 2 + restoreCasing),
                ]
                for (name, radius) in samples {
                    XCTAssertLessThanOrEqual(radius, availableRadius,
                                            "\(name), cell=\(cell), scale=\(scale): keep the rim visible")
                }
                XCTAssertGreaterThanOrEqual((marker.ringDiameter - marker.lineWidth) * scale, 2,
                                            "cell=\(cell), scale=\(scale): preserve an open ring center")
                // An axis-aligned plus centered between pixels needs a
                // two-pixel core and a separate casing pixel on either side.
                // A thinner core blends with its casing at 7 pt on 2x screens.
                XCTAssertGreaterThanOrEqual(restoreWidth * scale, 2,
                                            "cell=\(cell), scale=\(scale): restore core must survive pixel phase")
                XCTAssertGreaterThanOrEqual(restoreCasing * scale, 1,
                                            "cell=\(cell), scale=\(scale): restore casing must remain distinct")
                for width in [marker.lineWidth,
                              marker.actionLineWidth, marker.scoreLineWidth] {
                    XCTAssertGreaterThanOrEqual(width * scale, 1,
                                                "cell=\(cell), scale=\(scale): marks need at least a native pixel")
                }
            }
        }
    }

    /// Crossing a rendering or historical stroke breakpoint must not make
    /// an interaction mark suddenly bold while a board is being resized.
    func testMarkerStrokeWeightsDoNotJumpAtSizeThresholds() {
        for scale: CGFloat in [2, 3] {
            for threshold: CGFloat in [10, 14, 20, 30] {
                let before = StoneMarkerGeometry(cellSize: threshold - 1 / scale)
                let after = StoneMarkerGeometry(cellSize: threshold)
                let samples = [
                    ("last move", before.lineWidth, after.lineWidth),
                    ("action", before.actionLineWidth, after.actionLineWidth),
                    ("restore", before.restoreLineWidth(displayScale: scale), after.restoreLineWidth(displayScale: scale)),
                    ("restore casing", before.restoreCasingWidth(displayScale: scale), after.restoreCasingWidth(displayScale: scale)),
                    ("casing", before.casingWidth, after.casingWidth),
                    ("score", before.scoreLineWidth, after.scoreLineWidth),
                ]
                for (name, first, second) in samples {
                    XCTAssertLessThan(abs(second - first) * scale, 0.1,
                                      "\(name), threshold=\(threshold), scale=\(scale): avoid a visible stroke step")
                }
            }
        }
    }

    /// Markers are centered on intersections, so every image variant must
    /// put its opaque stone silhouette at that same center, excluding shadows.
    func testThemeStoneArtworkStaysCenteredUnderMarkers() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        let families = ["NebulaPearlGlass", "NebulaPearlPearl", "RakedGardenBasalt",
                        "RakedGardenJade", "SurroundStudioSlate", "SurroundStudioClamshell",
                        "FrostPineMidnight", "FrostPinePale"]
        let names = families.flatMap { family in (0..<4).map { "\(family)\($0)" } }
            + ["FeltMeadowBlackStone", "FeltMeadowWhiteStone",
               "NightGardenBlackStone", "NightGardenWhiteStone"]
        let side = 128
        for name in names {
            let image = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
            let source = try XCTUnwrap(image.cgImage, name)
            let pixels = try rgbaPixels(for: source, side: side)
            var alphaSum = 0.0, weightedX = 0.0, weightedY = 0.0
            var minX = side, minY = side, maxX = -1, maxY = -1
            for y in 0..<side {
                for x in 0..<side {
                    let alpha = Double(pixels[(y * side + x) * 4 + 3])
                    alphaSum += alpha
                    weightedX += (Double(x) + 0.5) * alpha
                    weightedY += (Double(y) + 0.5) * alpha
                    if alpha > 127 {
                        minX = min(minX, x)
                        minY = min(minY, y)
                        maxX = max(maxX, x)
                        maxY = max(maxY, y)
                    }
                }
            }
            XCTAssertGreaterThan(alphaSum, 0, name)
            guard alphaSum > 0 else { continue }
            XCTAssertEqual(weightedX / alphaSum, Double(side) / 2, accuracy: 0.25, name)
            XCTAssertEqual(weightedY / alphaSum, Double(side) / 2, accuracy: 0.25, name)
            // Handmade wool tufts may extend farther on one side while the
            // stone's visible mass stays centered under its markers.
            let marginTolerance = name.hasPrefix("FeltMeadow") ? 3 : 1
            XCTAssertLessThanOrEqual(abs(minX - (side - 1 - maxX)), marginTolerance, name)
            XCTAssertLessThanOrEqual(abs(minY - (side - 1 - maxY)), marginTolerance, name)
        }
    }

    func testFrostPineSceneFitsEveryViewportWithoutMovingForPanels() {
        let sizes = [CGSize(width: 375, height: 548), CGSize(width: 375, height: 667),
                     CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
                     CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820),
                     CGSize(width: 2500, height: 1500)]
        for size in sizes {
            let layout = FrostPineDecorationLayout(size: size)
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
            for rect in [layout.pine, layout.pinecone, layout.twig] {
                XCTAssertTrue(bounds.contains(rect), "Keep accents in their viewport, beneath game UI")
                XCTAssertEqual(rect.width, rect.height)
            }
            let resized = FrostPineDecorationLayout(size: CGSize(width: size.width + 1, height: size.height))
            for (before, after) in zip([layout.pine, layout.pinecone, layout.twig],
                                       [resized.pine, resized.pinecone, resized.twig]) {
                XCTAssertLessThanOrEqual(abs(before.minX - after.minX), 1.5)
                XCTAssertLessThanOrEqual(abs(before.minY - after.minY), 1.5)
                XCTAssertLessThanOrEqual(abs(before.width - after.width), 1.5)
            }
        }
        for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 500),
                     CGSize(width: 400, height: CGFloat.nan), CGSize(width: -1, height: 500)] {
            let layout = FrostPineDecorationLayout(size: size)
            for rect in [layout.pine, layout.pinecone, layout.twig] {
                XCTAssertTrue([rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite })
                XCTAssertGreaterThanOrEqual(rect.width, 0)
            }
        }
    }

    func testFrostPineAppearanceAndAnalysisStayReadable() throws {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.frostPine)
        try assertNightAnalysisMarksRemainReadable(.frostPine)
    }

    func testFrostedBoardRimDoesNotMoveThePlayingSurface() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let frost = try XCTUnwrap(SurroundTheme.frostPine.board(for: scheme).boardDepth)
            var cut = frost
            cut.edgeStyle = .cut
            for cell: CGFloat in [7, 13, 14, 15, 18, 20, 32, 48] {
                for coordinates in [false, true] {
                    let side = cell * (coordinates ? 20 : 19)
                    func geometry(_ depth: BoardDepth) -> BoardDepthGeometry {
                        BoardDepthGeometry(containerSize: CGSize(width: side, height: side),
                                           boardWidth: 19, boardHeight: 19, showsCoordinates: coordinates,
                                           displayScale: 3, depth: depth)
                    }
                    let soft = geometry(frost)
                    let original = geometry(cut)
                    XCTAssertEqual(soft.faceRect, original.faceRect)
                    XCTAssertEqual(soft.cellSize, original.cellSize)
                    XCTAssertEqual(soft.thickness, original.thickness)
                    XCTAssertLessThanOrEqual(soft.cornerRadius, soft.cellSize / 2)
                    if cell > 14 {
                        XCTAssertGreaterThan(soft.cornerRadius, original.cornerRadius)
                    } else {
                        XCTAssertEqual(soft.cornerRadius, 0)
                    }
                }
            }
        }
    }

    func testFrostPineControlsAndRolesStayReadableInBothAppearances() throws {
        let theme = SurroundTheme.frostPine
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true),
                       OGSUser(username: "bot", id: 5, isBot: true)]
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let scheme: ColorScheme = style == .dark ? .dark : .light
            for surface in [theme.pageBackground, theme.panel, theme.chatBubble] {
                XCTAssertGreaterThanOrEqual(contrast(theme.foreground, surface, style: style), 4.5)
            }
            for color: StoneColor in [.black, .white] {
                let surfaces = [theme.clockSolidSurface(color)]
                    + theme.clockSurfaceStops(color, scheme: scheme).map(\.color)
                for surface in surfaces {
                    for text in [theme.clockForeground(color, scheme: scheme), theme.clockAccent(color),
                                 theme.clockSuddenDeathAccent(color, scheme: scheme),
                                 theme.clockAgreementAccent(color, scheme: scheme),
                                 theme.clockDisconnectedAccent(color, scheme: scheme),
                                 theme.clockUndoAccent(color, scheme: scheme)] {
                        XCTAssertGreaterThanOrEqual(contrast(text, surface, style: style), 4.5)
                    }
                }
                for surface in theme.identityChipColors(color) {
                    for text in [theme.identityForeground(color), theme.identitySecondary(color)] {
                        XCTAssertGreaterThanOrEqual(contrast(text, surface, style: style), 4.5)
                    }
                    for player in players {
                        let role = try XCTUnwrap(theme.identityRoleColor(for: player, on: color))
                        XCTAssertGreaterThanOrEqual(contrast(role, surface, style: style), 4.5,
                                                   "Frost & Pine role: \(player.username)")
                    }
                }
            }
            for fill in [try XCTUnwrap(theme.actionTint), theme.statusBadge,
                         theme.clockUndoBadge(scheme: scheme), theme.clockSuddenDeathBadge(scheme: scheme)] {
                XCTAssertGreaterThanOrEqual(contrast(.white, fill, style: style), 4.5)
            }
        }
    }

    /// Home wears the theme Game Detail shows: its ink and names on panels,
    /// its clock chips with the low-time red, and New game's white on the
    /// action color. Names and clock times are 14 pt or larger and semibold,
    /// so they need 3:1, as icons do; smaller labels need 4.5:1. Chip text
    /// sits at the chip's middle, so it is checked against that blend.
    func testHomeSurfacesStayReadableInEveryTheme() {
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true),
                       OGSUser(username: "bot", id: 5, isBot: true)]
        for theme in SurroundTheme.allCases {
            let styles: [UIUserInterfaceStyle] = theme.colorScheme == .dark ? [.dark] : [.light, .dark]
            for style in styles {
                let scheme: ColorScheme = style == .dark ? .dark : .light
                let panelSurface: StoneColor = style == .dark ? .black : .white
                XCTAssertGreaterThanOrEqual(contrast(theme.foreground, theme.panel, style: style), 4.5,
                                            "\(theme) ink on its panel")
                for player in players {
                    XCTAssertGreaterThanOrEqual(
                        contrast(theme.roleColor(for: player, on: panelSurface), theme.panel, style: style), 3,
                        "\(theme) \(player.username) on its \(style == .dark ? "night" : "day") panel")
                }
                for color: StoneColor in [.black, .white] {
                    let stops = theme.identityChipColors(color)
                    let chip = midpoint(stops[0], stops[stops.count - 1], style: style)
                    let name = "\(theme) \(color) chip, \(style == .dark ? "night" : "day")"
                    XCTAssertGreaterThanOrEqual(contrast(theme.identityForeground(color), chip, style: style), 4.5, name)
                    XCTAssertGreaterThanOrEqual(contrast(theme.identitySecondary(color), chip, style: style), 4.5, name)
                    XCTAssertGreaterThanOrEqual(
                        contrast(theme.clockSuddenDeathAccent(color, scheme: scheme), chip, style: style), 3,
                        "\(name): low time")
                    XCTAssertGreaterThanOrEqual(contrast(theme.homeChipAccent(color), chip, style: style), 3,
                                                "\(name): hourglass")
                    // Standard and Nebula keep OGS's role hues on chips, as
                    // Game Detail does; the scene themes bring their own.
                    if theme.usesLightSceneSurfaces {
                        for player in players {
                            XCTAssertGreaterThanOrEqual(
                                contrast(theme.roleColor(for: player, on: color), chip, style: style), 3,
                                "\(name): \(player.username)")
                        }
                    }
                }
                XCTAssertGreaterThanOrEqual(contrast(.white, theme.homeActionFill, style: style), 4.5,
                                            "\(theme) New game")
            }
        }
    }

    private func midpoint(_ first: Color, _ second: Color, style: UIUserInterfaceStyle) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(first).resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(second).resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB, red: Double(r1 + r2) / 2, green: Double(g1 + g2) / 2, blue: Double(b1 + b2) / 2)
    }

    func testFrostPineAssetsPreserveIceSilhouettesAndSeparateSceneLayers() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        func image(_ name: String) throws -> CGImage {
            let image = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
            return try XCTUnwrap(image.cgImage, name)
        }
        for name in ["FrostPineSnow", "FrostPineBoard"] {
            let pixels = try rgbaPixels(for: image(name), side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 }, name)
        }
        for name in ["FrostPinePine", "FrostPinePinecone", "FrostPineTwig"] {
            let pixels = try rgbaPixels(for: image(name), side: 128)
            let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            XCTAssertTrue(alpha.contains(0), "\(name) keeps a transparent exterior")
            XCTAssertTrue(alpha.contains { $0 > 250 }, "\(name) retains its subject")
        }
        var diameters: [Int] = []
        for family in ["FrostPineMidnight", "FrostPinePale"] {
            for variant in 0..<4 {
                let pixels = try rgbaPixels(for: image("\(family)\(variant)"), side: 128)
                let alpha = { (x: Int, y: Int) in pixels[(y * 128 + x) * 4 + 3] }
                XCTAssertEqual(alpha(0, 0), 0)
                XCTAssertEqual(alpha(127, 64), 0)
                XCTAssertEqual(alpha(64, 64), 255, "Ice translucency must not reveal the grid through a stone")
                let diameter = (0..<128).filter { alpha($0, 64) > 127 }.count
                XCTAssertEqual(Double(diameter) / 128, 0.94, accuracy: 0.02)
                diameters.append(diameter)
            }
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(diameters.max()) - XCTUnwrap(diameters.min()), 1)
    }

    func testFrostPineSurfaceFrostKeepsThePlayingAreaClear() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        let image = try XCTUnwrap(UIImage(named: "FrostPineBoardFrost", in: bundle, compatibleWith: nil))
        let source = try XCTUnwrap(image.cgImage)
        let side = 128
        let pixels = try rgbaPixels(for: source, side: side)
        var center: [Double] = [], perimeter: [Double] = []
        for y in 0..<side {
            for x in 0..<side {
                let alpha = Double(pixels[(y * side + x) * 4 + 3]) / 255
                if (38..<90).contains(x), (38..<90).contains(y) {
                    center.append(alpha)
                } else if x < 26 || x >= 102 || y < 26 || y >= 102 {
                    perimeter.append(alpha)
                }
            }
        }
        let centerCoverage = center.reduce(0, +) / Double(center.count)
        let perimeterCoverage = perimeter.reduce(0, +) / Double(perimeter.count)
        XCTAssertLessThan(centerCoverage, 0.05, "Surface frost must leave a clear central playing area")
        XCTAssertGreaterThan(perimeterCoverage, max(0.02, centerCoverage * 2),
                             "Frost must visibly collect around the perimeter rather than wash over the face")
        XCTAssertTrue(perimeter.contains { $0 > 0.5 }, "Preserve some distinct frost crystals")
        XCTAssertTrue(center.contains(0), "The overlay must have transparent clear space")
    }

    @MainActor
    func testSurfaceFrostIsInvisibleBelowTheDetailThreshold() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let frost = BoardSurfaceOverlay(image: image)

        func pixels(_ surface: BoardSurfaceOverlay?, cell: CGFloat) throws -> [UInt8] {
            // Render the production layer on a solid face; this target
            // intentionally does not compile the full interactive board.
            let board = Color.black
                .overlay {
                    if let surface {
                        BoardSurfaceOverlayView(surface: surface, cellSize: cell)
                    }
                }
                .frame(width: cell * 9, height: cell * 9)
            let renderer = ImageRenderer(content: board)
            renderer.scale = 3
            let rendered = try XCTUnwrap(renderer.uiImage?.cgImage)
            return try rgbaPixels(for: rendered, side: 128)
        }

        for cell: CGFloat in [7, 13.99, 14] {
            let plain = try pixels(nil, cell: cell)
            let overlay = try pixels(frost, cell: cell)
            if cell < 14 {
                XCTAssertTrue(overlay == plain, "Compact boards must render identically with frost configured")
            } else {
                XCTAssertFalse(overlay == plain, "A visible detailed overlay is the positive control")
            }
        }
    }

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
        XCTAssertNil(SurroundTheme.surroundStudio.colorScheme)
        XCTAssertTrue(SurroundTheme.surroundStudio.hasScene)
        XCTAssertNil(SurroundTheme.frostPine.colorScheme)
        XCTAssertTrue(SurroundTheme.frostPine.hasScene)
        XCTAssertNil(SurroundTheme.feltMeadow.colorScheme)
        XCTAssertTrue(SurroundTheme.feltMeadow.hasScene)
    }

    func testAnUnknownStoredThemeFallsBackToStandard() {
        XCTAssertEqual(SurroundTheme.current(storedID: "unknown"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: ""), .standard)
        #if DEBUG
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .surroundStudio)
        XCTAssertEqual(SurroundTheme.current(storedID: "frostPine"), .frostPine)
        XCTAssertEqual(SurroundTheme.current(storedID: "feltMeadow"), .feltMeadow)
        XCTAssertEqual(SurroundTheme.current(storedID: "nightGarden"), .nightGarden)
        #else
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .surroundStudio)
        XCTAssertEqual(SurroundTheme.current(storedID: "frostPine"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "feltMeadow"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "nightGarden"), .standard)
        #endif
    }

    /// Classic and three scenes ship, in the pickers' order; Debug builds
    /// append the unreleased themes.
    func testPickersOfferTheReleasedThemesFirst() {
        XCTAssertEqual(SurroundTheme.released, [.standard, .surroundStudio, .rakedGarden, .nebulaPearl])
        XCTAssertEqual(SurroundTheme.allCases.filter(\.isDebugOnly), [.frostPine, .feltMeadow, .nightGarden])
        #if DEBUG
        XCTAssertEqual(SurroundTheme.available, SurroundTheme.released + [.frostPine, .feltMeadow, .nightGarden])
        #else
        XCTAssertEqual(SurroundTheme.available, SurroundTheme.released)
        #endif
        XCTAssertEqual(SurroundTheme.standard.title, "Classic")
    }

    /// Pickers show exported thumbnails rather than drawing every scene live.
    /// Each theme needs one, with its own Dark variant unless always dark.
    func testEveryThemeHasPickerThumbnails() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        for theme in SurroundTheme.allCases {
            let light = try XCTUnwrap(UIImage(named: theme.previewImageName, in: bundle,
                                              compatibleWith: UITraitCollection(userInterfaceStyle: .light)),
                                      "\(theme) has no picker thumbnail")
            let dark = try XCTUnwrap(UIImage(named: theme.previewImageName, in: bundle,
                                             compatibleWith: UITraitCollection(userInterfaceStyle: .dark)))
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(light.cgImage).width, 384, "\(theme) thumbnail stays sharp at 3×")
            if theme.colorScheme == nil {
                XCTAssertNotEqual(light.pngData(), dark.pngData(), "\(theme) needs a Dark thumbnail")
            }
        }
    }

    /// Release and Beta Release leave out `DebugThemes.xcassets`, so a
    /// Debug-only theme's art and thumbnail live there and a released
    /// theme's never do. Releasing a theme moves its folder and thumbnail
    /// into `Assets.xcassets`.
    func testOnlyReleasedThemesShipTheirArt() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Surround")
        let shippingCatalog = app.appendingPathComponent("Assets.xcassets")
        let debugCatalog = app.appendingPathComponent("DebugThemes.xcassets")
        guard FileManager.default.isReadableFile(atPath: #filePath) else {
            throw XCTSkip("The source tree is not readable from this test run.")
        }
        XCTAssert(FileManager.default.fileExists(atPath: shippingCatalog.path), "No catalog at \(shippingCatalog.path)")
        func imagesets(in catalog: URL) -> [String] {
            let items = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []
            return items.filter { $0.pathExtension == "imageset" }.map { $0.deletingPathExtension().lastPathComponent }
        }
        // Theme art is named after its theme: frostPine's is FrostPine….
        func theme(of asset: String) -> SurroundTheme? {
            SurroundTheme.allCases.first { theme in
                asset == theme.previewImageName
                    || asset.hasPrefix(theme.rawValue.prefix(1).uppercased() + theme.rawValue.dropFirst())
            }
        }
        let shipping = imagesets(in: shippingCatalog)
        let debug = imagesets(in: debugCatalog)
        for asset in shipping {
            XCTAssertFalse(theme(of: asset)?.isDebugOnly ?? false, "\(asset) belongs in DebugThemes.xcassets")
        }
        for asset in debug {
            XCTAssertTrue(theme(of: asset)?.isDebugOnly ?? false, "\(asset) belongs in Assets.xcassets")
        }
        for theme in SurroundTheme.allCases {
            XCTAssert((theme.isDebugOnly ? debug : shipping).contains(theme.previewImageName),
                      "\(theme)'s thumbnail is in the wrong catalog")
        }
    }

    /// Games always wear the theme; other screens only with Whole app.
    func testGamesOnlyKeepsOtherScreensClassic() {
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden", appliesToWholeApp: true), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden", appliesToWholeApp: false), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "unknown", appliesToWholeApp: true), .standard)
    }

    /// A dark-only theme turns the whole app dark only when it applies to the
    /// whole app; with Games only, the rest of the app keeps the system's look.
    func testDarkOnlyThemesDarkenTheWholeAppOnlyThere() {
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl", appliesToWholeApp: true).colorScheme, .dark)
        XCTAssertNil(SurroundTheme.current(storedID: "nebulaPearl", appliesToWholeApp: false).colorScheme)
        XCTAssertNil(SurroundTheme.current(storedID: "rakedGarden", appliesToWholeApp: true).colorScheme)
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
        for other: SurroundTheme in [.standard, .nebulaPearl] {
            for scheme: ColorScheme in [.light, .dark] {
                XCTAssertEqual(other.board(for: scheme), other.board)
            }
        }
    }

    /// These are nominal opaque palette checks. Native captures separately
    /// verify the graded texture, rendered stones and translucent controls.
    func testGardenNightStonesGridAndMarksRemainReadable() throws {
        try assertNightStonesGridAndMarksRemainReadable(.rakedGarden)
    }

    func testStudioNightStonesGridAndMarksRemainReadable() throws {
        try assertNightStonesGridAndMarksRemainReadable(.surroundStudio)
    }

    private func assertNightStonesGridAndMarksRemainReadable(_ theme: SurroundTheme) throws {
        let board = theme.board(for: .dark)
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
        try assertNightAnalysisMarksRemainReadable(.rakedGarden)
    }

    func testStudioNightAnalysisMarksRemainReadable() throws {
        try assertNightAnalysisMarksRemainReadable(.surroundStudio)
    }

    func testFeltMeadowNightAnalysisMarksRemainReadable() throws {
        try assertNightAnalysisMarksRemainReadable(.feltMeadow)
    }

    func testNightGardenPaletteAndFacetedMarkersAdaptToAppearance() throws {
        let theme = SurroundTheme.nightGarden
        XCTAssertNil(theme.colorScheme, "Night Garden follows the system appearance")
        assertAdaptiveColorsFollowRepeatedTraitChanges(theme)
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            try assertNightAnalysisMarksRemainReadable(theme, scheme: scheme)
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
            let board = theme.board(for: scheme)
            for stone in [board.black, board.white] {
                let casing = try XCTUnwrap(stone.detailedMarkerCasing)
                XCTAssertGreaterThanOrEqual(contrast(stone.lastMove, casing, style: style), 3,
                                           "The last-move ring must survive crystal facets in both appearances")
                XCTAssertGreaterThanOrEqual(contrast(stone.label, casing, style: style), 4.5,
                                           "Variation labels need legible casing over crystal highlights")
            }
            for surface in [theme.pageBackground, theme.panel, theme.chatBubble] {
                XCTAssertGreaterThanOrEqual(contrast(theme.foreground, surface, style: style), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, surface, style: style), 4.5)
            }
            for surface in [theme.pageBackground, theme.panel] {
                XCTAssertGreaterThanOrEqual(contrast(theme.homeActionForeground, surface, style: style), 4.5)
            }
            for surface in [theme.panel, theme.chatBubble] {
                XCTAssertGreaterThanOrEqual(contrast(theme.chatCoordinateForeground, surface, style: style), 4.5)
            }
            XCTAssertGreaterThanOrEqual(contrast(board.emptyPointMarker, board.boardColor, style: style), 4.5,
                                       "The analysis root icon uses the board's contrasting marker pigment")
        }
    }

    func testNightGardenGradesTheBoardWithoutChangingItsGeometry() throws {
        let day = SurroundTheme.nightGarden.board(for: .light)
        let night = SurroundTheme.nightGarden.board(for: .dark)
        XCTAssertEqual(SurroundTheme.nightGarden.board, day)
        XCTAssertLessThan(luminance(night.boardColor), luminance(day.boardColor))
        XCTAssertLessThan(luminance(try XCTUnwrap(night.compactBoardColor)),
                          luminance(try XCTUnwrap(day.compactBoardColor)))
        XCTAssertLessThan(luminance(night.black.flat), luminance(day.black.flat))
        XCTAssertLessThan(luminance(night.white.flat), luminance(day.white.flat))
        // The unhosted unit target loads assets from its test bundle, while
        // the app's cached image wrappers use the main bundle. Asset integrity
        // is checked separately below; native marker audits verify image grading.
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        for board in [day, night] {
            XCTAssertNil(board.boardDepth, "The concept has a thin bronze edge, not a raised slab")
            XCTAssertFalse(board.boardBevel)
        }
    }

    @MainActor
    func testNightGardenSceneDimsWithSystemAppearance() throws {
        func brightness(_ scheme: ColorScheme) throws -> Double {
            let rendered = try nativeMaterialPixels(GameDetailBackdrop()
                .environment(\.surroundTheme, .nightGarden)
                .environment(\.colorScheme, scheme)
                .frame(width: 200, height: 360))
            // The middle band is clear of the top and bottom chrome ledges.
            let rowBytes = rendered.width * 4
            let rows = (rendered.height / 2 - 30)..<(rendered.height / 2 + 30)
            var sum = 0.0
            for y in rows {
                for x in 0..<rendered.width {
                    let i = y * rowBytes + x * 4
                    sum += (0.2126 * Double(rendered.pixels[i])
                            + 0.7152 * Double(rendered.pixels[i + 1])
                            + 0.0722 * Double(rendered.pixels[i + 2])) / 255
                }
            }
            return sum / Double(rows.count * rendered.width)
        }
        let day = try brightness(.light), night = try brightness(.dark)
        XCTAssertGreaterThan(day, 0.1, "The native backdrop must contain the garden artwork")
        XCTAssertLessThan(night, day * 0.8, "Dark Mode subdues the same garden artwork")
    }

    func testFeltMeadowDayAnalysisMarksRemainReadable() throws {
        let theme = SurroundTheme.feltMeadow
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        XCTAssertGreaterThanOrEqual(contrast(theme.selectionMark, theme.panel), 3)
        XCTAssertGreaterThanOrEqual(contrast(theme.selectionMark, keyline), 3)
        XCTAssertGreaterThanOrEqual(contrast(try XCTUnwrap(theme.conditionalMark), keyline), 3)
        XCTAssertGreaterThanOrEqual(contrast(theme.userTurnMark, theme.idleGameMark(scheme: .light)), 3)
    }

    private func assertNightAnalysisMarksRemainReadable(_ theme: SurroundTheme, scheme: ColorScheme = .dark) throws {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let keyline = try XCTUnwrap(theme.treeMarkKeyline)
        XCTAssertGreaterThan(contrast(theme.selectionMark, theme.panel, style: style), 3)
        XCTAssertGreaterThan(contrast(theme.selectionMark, keyline, style: style), 3)
        XCTAssertGreaterThan(contrast(try XCTUnwrap(theme.conditionalMark), keyline, style: style), 3)
        XCTAssertGreaterThan(contrast(theme.userTurnMark, theme.idleGameMark(scheme: scheme), style: style), 3)
    }

    func testGardenNightControlFallbacksKeepReadableTextAndRoles() throws {
        try assertNightControlFallbacksKeepReadableTextAndRoles(.rakedGarden)
    }

    func testStudioNightControlFallbacksKeepReadableTextAndRoles() throws {
        try assertNightControlFallbacksKeepReadableTextAndRoles(.surroundStudio)
    }

    func testFeltMeadowNightControlFallbacksKeepReadableTextAndRoles() throws {
        try assertNightControlFallbacksKeepReadableTextAndRoles(.feltMeadow)
    }

    private func assertNightControlFallbacksKeepReadableTextAndRoles(_ theme: SurroundTheme, scheme: ColorScheme = .dark) throws {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        XCTAssertGreaterThan(contrast(theme.foreground, theme.pageBackground, style: style), 4.5)
        XCTAssertGreaterThan(contrast(theme.foreground, theme.panel, style: style), 4.5)
        let players = [
            OGSUser(username: "ordinary", id: 1),
            OGSUser(username: "moderator", id: 2, isModerator: true),
            OGSUser(username: "admin", id: 3, isSuperuser: true),
            OGSUser(username: "professional", id: 4, professional: true),
            OGSUser(username: "supporter", id: 5, supporter: true),
            OGSUser(username: "bot", id: 6, isBot: true),
        ]
        for color: StoneColor in [.black, .white] {
            let foreground = theme.clockForeground(color, scheme: scheme)
            let surfaces = [theme.clockSolidSurface(color)]
                + theme.clockSurfaceStops(color, scheme: scheme).map(\.color)
            for surface in surfaces {
                XCTAssertGreaterThan(contrast(foreground, surface, style: style), 4.5)
                XCTAssertGreaterThan(contrast(theme.clockAccent(color), surface, style: style), 4.5)
                XCTAssertGreaterThanOrEqual(
                    contrast(theme.clockSuddenDeathAccent(color, scheme: scheme), surface, style: style), 4.5)
                if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden {
                    for (state, accent) in [
                        ("Accepted", theme.clockAgreementAccent(color, scheme: scheme)),
                        ("Disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                        ("Undo", theme.clockUndoAccent(color, scheme: scheme)),
                    ] {
                        XCTAssertGreaterThanOrEqual(contrast(accent, surface, style: style), 4.5,
                                                   "\(state) text must read on every \(color) clock surface")
                    }
                }
            }
            for surface in theme.identityChipColors(color) {
                XCTAssertGreaterThan(contrast(theme.identityForeground(color), surface, style: style), 4.5)
                XCTAssertGreaterThan(contrast(theme.identitySecondary(color), surface, style: style), 4.5)
                for player in players {
                    let roleColor = try XCTUnwrap(theme.identityRoleColor(for: player, on: color))
                    XCTAssertGreaterThan(contrast(roleColor, surface, style: style), 4.5,
                                         "\(player.username) must read on the \(color) identity")
                }
            }
        }
        XCTAssertGreaterThan(contrast(.white, try XCTUnwrap(theme.actionTint), style: style), 4.5)
        XCTAssertGreaterThan(contrast(.white, theme.statusBadge, style: style), 4.5)
        if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden {
            XCTAssertGreaterThanOrEqual(contrast(.white, theme.clockUndoBadge(scheme: scheme), style: style), 4.5,
                                       "The Undo badge keeps its white text readable")
            XCTAssertGreaterThanOrEqual(contrast(.white, theme.clockSuddenDeathBadge(scheme: scheme), style: style), 4.5,
                                       "The urgent clock badge keeps its white text readable")
        }
    }

    func testGardenAdaptiveColorsFollowRepeatedTraitChanges() {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.rakedGarden)
    }

    func testFeltMeadowAdaptiveColorsFollowRepeatedTraitChanges() {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.feltMeadow)
    }

    func testStudioAdaptiveColorsFollowRepeatedTraitChanges() {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.surroundStudio)
        let theme = SurroundTheme.surroundStudio
        // The same cached UIKit providers back clocks and player chips when
        // the mounted game changes appearance; resolve them without rebuilding.
        let surfaces = [theme.clockSolidSurface(.white)] + theme.identityChipColors(.white)
        for surface in surfaces {
            let provider = UIColor(surface)
            let day = luminance(surface, style: .light)
            let night = luminance(surface, style: .dark)
            XCTAssertLessThan(night, day, "Night subdues the pale controls")
            for style: UIUserInterfaceStyle in [.dark, .light, .dark, .light] {
                let resolved = provider.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                XCTAssertEqual(luminance(Color(uiColor: resolved)), style == .dark ? night : day,
                               accuracy: 0.000001)
            }
        }
    }

    private func assertAdaptiveColorsFollowRepeatedTraitChanges(_ theme: SurroundTheme) {
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
        for theme: SurroundTheme in [.rakedGarden, .surroundStudio, .feltMeadow] {
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

    func testStudioNightModePreservesTheDayBoardAndGeometry() {
        let theme = SurroundTheme.surroundStudio
        let day = theme.board(for: .light)
        let night = theme.board(for: .dark)
        XCTAssertEqual(theme.board, day)
        XCTAssertEqual(day.boardColor, Color(themeHex: 0xD8B27A), "Daytime keeps its balanced honey kaya palette")
        XCTAssertNotEqual(day.boardColor, night.boardColor)
        XCTAssertLessThan(luminance(night.boardColor, style: .dark), luminance(day.boardColor))
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        XCTAssertEqual(night.boardBevel, day.boardBevel)
    }

    func testFeltMeadowKeepsBoardGeometryAcrossAppearances() {
        let theme = SurroundTheme.feltMeadow
        let day = theme.board(for: .light), night = theme.board(for: .dark)
        XCTAssertEqual(theme.board, day)
        XCTAssertEqual(day.gridStyle, .stitched)
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        XCTAssertEqual(night.boardBevel, day.boardBevel)
        XCTAssertNil(day.boardDepth)
        XCTAssertNil(night.boardDepth)
        XCTAssertNotEqual(day.boardColor, night.boardColor)
        XCTAssertLessThan(luminance(night.boardColor, style: .dark), luminance(day.boardColor))
    }

    func testFeltMeadowControlFallbacksKeepReadableText() throws {
        let theme = SurroundTheme.feltMeadow
        XCTAssertGreaterThanOrEqual(contrast(theme.foreground, theme.pageBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(theme.foreground, theme.panel), 4.5)
        for style: UIUserInterfaceStyle in [.light, .dark] {
            XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, theme.panel, style: style), 4.5,
                                       "Secondary details remain readable on the themed panel in both appearances")
        }
        for color: StoneColor in [.black, .white] {
            let foreground = theme.clockForeground(color, scheme: .light)
            for surface in [theme.clockSolidSurface(color)] + theme.clockSurfaceStops(color, scheme: .light).map(\.color) {
                XCTAssertGreaterThanOrEqual(contrast(foreground, surface), 4.5)
                for accent in [theme.clockAccent(color), theme.clockSuddenDeathAccent(color, scheme: .light),
                               theme.clockAgreementAccent(color, scheme: .light),
                               theme.clockDisconnectedAccent(color, scheme: .light),
                               theme.clockUndoAccent(color, scheme: .light)] {
                    XCTAssertGreaterThanOrEqual(contrast(accent, surface), 4.5)
                }
            }
            for surface in theme.identityChipColors(color) {
                XCTAssertGreaterThanOrEqual(contrast(theme.identityForeground(color), surface), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(theme.identitySecondary(color), surface), 4.5)
            }
        }
        for surface in [try XCTUnwrap(theme.actionTint), theme.statusBadge,
                        theme.clockUndoBadge(scheme: .light), theme.clockSuddenDeathBadge(scheme: .light)] {
            XCTAssertGreaterThanOrEqual(contrast(.white, surface), 4.5)
        }
    }

    @MainActor
    func testFeltControlMaterialKeepsTextReadableAcrossSizesAndAppearances() throws {
        let theme = SurroundTheme.feltMeadow
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true)]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let foregrounds = [theme.clockForeground(color, scheme: scheme), theme.identitySecondary(color),
                                   theme.clockAccent(color), theme.clockSuddenDeathAccent(color, scheme: scheme),
                                   theme.clockAgreementAccent(color, scheme: scheme),
                                   theme.clockDisconnectedAccent(color, scheme: scheme),
                                   theme.clockUndoAccent(color, scheme: scheme)]
                    + players.map { theme.roleColor(for: $0, on: color) }
                for size in [CGSize(width: 140, height: 28), CGSize(width: 320, height: 34),
                             CGSize(width: 190, height: 96), CGSize(width: 126, height: 140)] {
                    for fallback in [false, true] {
                        let view = FeltControlMaterial(color: color, shape: RoundedRectangle(cornerRadius: 9),
                                                       colorScheme: scheme, showsTexture: !fallback)
                            .frame(width: size.width, height: size.height)
                            .environment(\.colorScheme, scheme)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 3
                        let rendered = try XCTUnwrap(renderer.cgImage)
                        // Text is inset by at least 8 pt. Include every fiber
                        // beneath it; the rounded padded edge contains no text.
                        let interior = try XCTUnwrap(rendered.cropping(to: CGRect(
                            x: 18, y: 18, width: rendered.width - 36, height: rendered.height - 36)))
                        var pixels = [UInt8](repeating: 0, count: interior.width * interior.height * 4)
                        try pixels.withUnsafeMutableBytes { bytes in
                            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,
                                width: interior.width, height: interior.height, bitsPerComponent: 8,
                                bytesPerRow: interior.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                            context.draw(interior, in: CGRect(x: 0, y: 0, width: interior.width, height: interior.height))
                        }
                        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                                      "Cloth must remain opaque")
                        var minimum = Double.infinity, maximum = 0.0
                        var luminances = [Double]()
                        luminances.reserveCapacity(pixels.count / 4)
                        for offset in stride(from: 0, to: pixels.count, by: 4) {
                            let value = 0.2126 * linear[Int(pixels[offset])]
                                + 0.7152 * linear[Int(pixels[offset + 1])]
                                + 0.0722 * linear[Int(pixels[offset + 2])]
                            minimum = min(minimum, value)
                            maximum = max(maximum, value)
                            luminances.append(value)
                        }
                        let description = "\(scheme) \(color) \(size), fallback=\(fallback)"
                        for ink in foregrounds {
                            let value = luminance(ink, style: style)
                            for surface in [minimum, maximum] {
                                XCTAssertGreaterThanOrEqual((max(value, surface) + 0.05)
                                    / (min(value, surface) + 0.05), 4.5, description)
                            }
                        }
                        if !fallback {
                            XCTAssertGreaterThan(maximum - minimum, 0.003,
                                                 "The wool must remain visible: \(description)")
                            // A few isolated pixels can satisfy the full range
                            // while most of the material still looks flat.
                            // Compare broad light/dark fiber populations instead.
                            luminances.sort()
                            let tenth = luminances[(luminances.count - 1) / 10]
                            let ninetieth = luminances[(luminances.count - 1) * 9 / 10]
                            XCTAssertGreaterThanOrEqual((ninetieth + 0.05) / (tenth + 0.05), 1.12,
                                                        "The wool needs visible fiber contrast: \(description)")
                        } else {
                            XCTAssertLessThan(maximum - minimum, 0.001,
                                              "Accessibility fallback stays solid: \(description)")
                        }
                    }
                }
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
        _ = try image(named: "SurroundStudioBoard")
        _ = try image(named: "SurroundStudioScene")
        for name in ["SurroundStudioFoliage", "SurroundStudioTree", "SurroundStudioVase"] {
            let source = try XCTUnwrap(image(named: name).cgImage, name)
            let pixels = try rgbaPixels(for: source, side: side)
            let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            XCTAssertTrue(alpha.contains(0), "\(name) leaves the room visible around its artwork")
            XCTAssertTrue(alpha.contains { $0 > 250 }, "\(name) contains visible artwork")
        }
        let stones = try StoneImages(
            black: (0..<4).map { try image(named: "SurroundStudioSlate\($0)") },
            white: (0..<4).map { try image(named: "SurroundStudioClamshell\($0)") }
        )
        try assertEqualAlphaStoneFootprints(stones)
    }

    func testFeltMeadowAssetsKeepSeparateBoardAndEqualAlphaStoneFootprints() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        func image(named name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        _ = try image(named: "FeltMeadowScene")
        _ = try image(named: "FeltMeadowBoard")
        // The processor holds the longest opaque extent at 0.94; natural
        // tufts can leave the center-line body slightly narrower. Preserve
        // that silhouette rather than stretch or mask it into a circle.
        try assertEqualAlphaStoneFootprints(StoneImages(
            black: [try image(named: "FeltMeadowBlackStone")],
            white: [try image(named: "FeltMeadowWhiteStone")]
        ), diameterTolerance: 0.04, maximumDiameterDifference: 5, minimumExtentRatio: 0.92)
    }

    func testFeltStoneFibersFollowSourceAlphaAndStayStableWhileResizing() throws {
        for name in ["FeltMeadowBlackStone", "FeltMeadowWhiteStone"] {
            let image = try XCTUnwrap(UIImage(named: name, in: Bundle(for: Self.self), compatibleWith: nil))
            let contour = try XCTUnwrap(FeltFiberContour.stone(image: image))
            XCTAssertEqual(contour, FeltFiberContour.stone(image: image))
            XCTAssertGreaterThan(contour.points.count, 32)
            let source = try XCTUnwrap(image.cgImage)
            let pixels = try rgbaPixels(for: source, side: source.width)
            var opaqueInside = 0, transparentOutside = 0
            for point in contour.points {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(point))
                let radius = hypot(point.x - 0.5, point.y - 0.5)
                XCTAssertGreaterThan(radius, 0.4, "The contour follows the stone body, not an interior fiber")
                XCTAssertLessThan(radius, 0.5)
                func alpha(radialScale: CGFloat) -> UInt8 {
                    let x = min(source.width - 1, max(0, Int((0.5 + (point.x - 0.5) * radialScale) * CGFloat(source.width))))
                    let y = min(source.height - 1, max(0, Int((0.5 + (point.y - 0.5) * radialScale) * CGFloat(source.height))))
                    return pixels[(y * source.width + x) * 4 + 3]
                }
                opaqueInside += alpha(radialScale: 0.95) >= 128 ? 1 : 0
                transparentOutside += alpha(radialScale: 1.05) < 128 ? 1 : 0
            }
            // Allow isolated original wool flecks, but require the sampled
            // silhouette to separate the connected body from its padding.
            XCTAssertGreaterThan(Double(opaqueInside) / Double(contour.points.count), 0.9, name)
            XCTAssertGreaterThan(Double(transparentOutside) / Double(contour.points.count), 0.9, name)

            let reference = FeltEdgeFibers.stone(contour: contour, in: CGRect(x: 3, y: 5, width: 20, height: 20), seed: 71)
            for diameter: CGFloat in [14, 20, 40] {
                let rect = CGRect(x: 3, y: 5, width: diameter, height: diameter)
                let fibers = FeltEdgeFibers.stone(contour: contour, in: rect, seed: 71)
                let repeated = FeltEdgeFibers.stone(contour: contour, in: rect, seed: 71)
                let other = FeltEdgeFibers.stone(contour: contour, in: rect, seed: 72)
                XCTAssertEqual(fibers.body, repeated.body)
                XCTAssertEqual(fibers.wisps, repeated.wisps)
                XCTAssertNotEqual(fibers.body, other.body)
                for (path, original) in [(fibers.body, reference.body), (fibers.wisps, reference.wisps)] {
                    XCTAssertFalse(path.isEmpty)
                    XCTAssertTrue(rect.insetBy(dx: -1.21, dy: -1.21).contains(path.boundingRect),
                                  "Loose fibers stay within the stone's reserved fringe")
                    let coordinates = normalizedPathCoordinates(path, cellSize: 1)
                    XCTAssertTrue(coordinates.allSatisfy(\.isFinite))
                    XCTAssertEqual(coordinates.count, normalizedPathCoordinates(original, cellSize: 1).count,
                                   "Resizing preserves each stone's tufts")
                }
            }
        }
        let empty = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        XCTAssertNil(FeltFiberContour.stone(image: empty), "Transparent artwork has no attached stone body")
    }

    func testFeltControlFibersFollowTheProvidedRoundedOutline() {
        for size in [CGSize(width: 140, height: 28), CGSize(width: 190, height: 96)] {
            let rect = CGRect(origin: CGPoint(x: 3, y: 5), size: size)
            for style: RoundedCornerStyle in [.circular, .continuous] {
                let outline = RoundedRectangle(cornerRadius: 12, style: style).path(in: rect)
                let fibers = FeltEdgeFibers.roundedRectangle(outline: outline, in: rect, seed: 31)
                let repeated = FeltEdgeFibers.roundedRectangle(outline: outline, in: rect, seed: 31)
                XCTAssertEqual(fibers.body, repeated.body)
                XCTAssertEqual(fibers.wisps, repeated.wisps)
                XCTAssertNotEqual(fibers.body,
                    FeltEdgeFibers.roundedRectangle(outline: outline, in: rect, seed: 32).body)
                let otherOutline = RoundedRectangle(cornerRadius: 3, style: style).path(in: rect)
                XCTAssertNotEqual(fibers.body,
                    FeltEdgeFibers.roundedRectangle(outline: otherOutline, in: rect, seed: 31).body)
                for path in [fibers.body, fibers.wisps] {
                    XCTAssertFalse(path.isEmpty)
                    XCTAssertTrue(rect.insetBy(dx: -1.61, dy: -1.61).contains(path.boundingRect))
                    XCTAssertTrue(normalizedPathCoordinates(path, cellSize: 1).allSatisfy(\.isFinite))
                    path.forEach { element in
                        switch element {
                        case .move(to: let root):
                            XCTAssertTrue(outline.contains(root), "Every fiber starts inside the supplied control shape")
                        case .curve(to: let tip, control1: _, control2: _):
                            XCTAssertFalse(outline.contains(tip), "Every fiber extends beyond that same shape")
                        default: break
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testFeltControlFringeIsVisibleOutsideTheBodyAndAbsentInFallback() throws {
        let scale = 3
        let padding = 3 * scale
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for size in [CGSize(width: 140, height: 28), CGSize(width: 190, height: 96)] {
                    for textured in [false, true] {
                        let view = FeltControlMaterial(color: color, shape: RoundedRectangle(cornerRadius: 9),
                                                       colorScheme: scheme, showsTexture: textured)
                            .frame(width: size.width, height: size.height)
                            .padding(3)
                            .environment(\.colorScheme, scheme)
                        let raster = try nativeMaterialPixels(view)
                        var outsideAlpha = [UInt8]()
                        // Only straight mid-edges: rounded-corner antialiasing
                        // cannot impersonate strands beyond the body.
                        for x in (padding + 12 * scale)..<(raster.width - padding - 12 * scale) {
                            for y in Array(0..<padding) + Array((raster.height - padding)..<raster.height) {
                                outsideAlpha.append(raster.pixels[(y * raster.width + x) * 4 + 3])
                            }
                        }
                        let message = "\(scheme) \(color) \(size), textured=\(textured)"
                        if textured {
                            XCTAssertGreaterThan(outsideAlpha.filter { $0 >= 16 }.count, 10,
                                                 "Native pixels must show attached fibers: \(message)")
                        } else {
                            XCTAssertTrue(outsideAlpha.allSatisfy { $0 == 0 },
                                          "Accessibility fallback has no fringe: \(message)")
                        }
                        for x in 0..<raster.width {
                            XCTAssertEqual(raster.pixels[x * 4 + 3], 0, message)
                            XCTAssertEqual(raster.pixels[((raster.height - 1) * raster.width + x) * 4 + 3], 0, message)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testFeltStoneFringeDisappearsBelowDetailThresholdAndWithoutShadows() throws {
        let bundle = Bundle(for: Self.self)
        let black = try XCTUnwrap(UIImage(named: "FeltMeadowBlackStone", in: bundle, compatibleWith: nil))
        let white = try XCTUnwrap(UIImage(named: "FeltMeadowWhiteStone", in: bundle, compatibleWith: nil))
        let blackContour = try XCTUnwrap(FeltFiberContour.stone(image: black))
        let whiteContour = try XCTUnwrap(FeltFiberContour.stone(image: white))
        var withFibers = SurroundTheme.feltMeadow.board
        withFibers.stoneImages = StoneImages(black: [black], white: [white],
                                           blackFiberContours: [blackContour], whiteFiberContours: [whiteContour])
        var withoutFibers = withFibers
        withoutFibers.stoneImages = StoneImages(black: [black], white: [white])
        for color: StoneColor in [.black, .white] {
            for (diameter, shadow): (CGFloat, CGFloat) in [(13, 1), (20, 0), (20, 1)] {
                func render(_ board: BoardAppearance) throws -> [UInt8] {
                    try nativeMaterialPixels(Stone(color: color, shadowRadius: shadow)
                        .frame(width: diameter, height: diameter).padding(3)
                        .environment(\.boardAppearance, board)
                        .environment(\.colorScheme, .light)).pixels
                }
                let actual = try render(withFibers), plain = try render(withoutFibers)
                let differences = zip(actual, plain).filter { $0 != $1 }.count
                if diameter < 14 || shadow == 0 {
                    XCTAssertEqual(differences, 0, "Flat stones have no added fiber pixels anywhere, including their padding")
                } else {
                    XCTAssertGreaterThan(differences, 10, "A detailed 20 pt stone visibly draws its edge fibers")
                }
            }
        }
    }

    @MainActor
    private func nativeMaterialPixels<Content: View>(_ content: Content) throws
        -> (pixels: [UInt8], width: Int, height: Int) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (pixels, image.width, image.height)
    }

    func testNightGardenAssetsKeepSeparateBoardAndEqualAlphaStoneFootprints() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        func image(named name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        for name in ["NightGardenScene", "NightGardenBoard"] {
            let source = try XCTUnwrap(image(named: name).cgImage, name)
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "The board and garden are continuous opaque surfaces")
        }
        try assertEqualAlphaStoneFootprints(StoneImages(
            black: [try image(named: "NightGardenBlackStone")],
            white: [try image(named: "NightGardenWhiteStone")]
        ))
    }

    private func assertEqualAlphaStoneFootprints(_ stones: StoneImages,
                                                diameterTolerance: CGFloat = 0.02,
                                                maximumDiameterDifference: Int = 1,
                                                minimumExtentRatio: CGFloat? = nil) throws {
        let side = 128
        var footprints: [Int] = []
        for image in stones.black + stones.white {
            let source = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(source.width, source.height)
            XCTAssertGreaterThanOrEqual(source.width, 256)
            let pixels = try rgbaPixels(for: source, side: side)
            func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * side + x) * 4 + 3] }
            XCTAssertEqual(alpha(0, 0), 0)
            XCTAssertEqual(alpha(side - 1, side - 1), 0)
            XCTAssertEqual(alpha(0, side / 2), 0)
            XCTAssertEqual(alpha(side - 1, side / 2), 0)
            XCTAssertGreaterThan(alpha(side / 2, side / 2), 250)
            let diameter = (0..<side).filter { alpha($0, side / 2) > 127 }.count
            XCTAssertEqual(CGFloat(diameter) / CGFloat(side), stones.footprint, accuracy: diameterTolerance)
            footprints.append(diameter)
            if let minimumExtentRatio {
                var minX = side, minY = side, maxX = -1, maxY = -1
                for y in 0..<side {
                    for x in 0..<side where alpha(x, y) > 127 {
                        minX = min(minX, x); minY = min(minY, y)
                        maxX = max(maxX, x); maxY = max(maxY, y)
                    }
                }
                let width = CGFloat(maxX - minX + 1), height = CGFloat(maxY - minY + 1)
                let longest = max(width, height)
                XCTAssertGreaterThan(longest, 0)
                if longest > 0 {
                    // Natural edge variation must still fit the intended
                    // cell silhouette without becoming an elongated stone.
                    XCTAssertEqual(longest / CGFloat(side), stones.footprint, accuracy: 0.02)
                    XCTAssertGreaterThanOrEqual(min(width, height) / longest, minimumExtentRatio)
                }
            }
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(footprints.max()) - XCTUnwrap(footprints.min()),
                                 maximumDiameterDifference,
                                 "Both stone colors keep comparable diameters across every variant")
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
            XCTAssertEqual(layout.tree, folded.tree)
            XCTAssertEqual(layout.tree, legacy.tree,
                           "The background tree stays fixed as the clock and chrome layout changes")
            XCTAssertEqual(layout.tree.width, layout.tree.height)
            XCTAssertLessThan(layout.tree.minX, 0)
            XCTAssertGreaterThan(layout.tree.maxY, size.height,
                                 "The tree enters from beyond the lower-left viewport edge")
            let visibleTree = layout.tree.intersection(CGRect(origin: .zero, size: size))
            XCTAssertGreaterThan(visibleTree.width, 0)
            XCTAssertGreaterThan(visibleTree.height, 0)
            XCTAssertLessThanOrEqual(visibleTree.height, size.height * 0.45,
                                    "Shallow windows leave the upper scene clear")
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

    func testStudioTreeKeepsNaturalPhoneScaleAndShrinksForThumbnails() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)] {
            let tree = SurroundStudioDecorationLayout(size: size).tree
            let visible = tree.intersection(CGRect(origin: .zero, size: size))
            XCTAssertGreaterThanOrEqual(visible.width, 170)
            XCTAssertLessThanOrEqual(visible.width, 220)
            XCTAssertGreaterThanOrEqual(visible.height, 200)
            XCTAssertLessThanOrEqual(visible.height, 260)
        }
        for side: CGFloat in [64, 128, 176] {
            let tree = SurroundStudioDecorationLayout(size: CGSize(width: side, height: side)).tree
            XCTAssertLessThan(tree.width, side,
                              "The native thumbnail must show leaves without filling the whole room")
            XCTAssertGreaterThan(tree.maxX, 0)
            XCTAssertGreaterThan(tree.minY, side / 2)
        }
    }

    func testStudioDecorationsStayFiniteForInvalidLayoutSlots() {
        for size in [CGSize.zero, CGSize(width: 0, height: 320), CGSize(width: 320, height: 0),
                     CGSize(width: -10, height: 400), CGSize(width: CGFloat.infinity, height: 400),
                     CGSize(width: 400, height: CGFloat.nan)] {
            let layout = SurroundStudioDecorationLayout(size: size)
            for rect in [layout.foliage, layout.tree] {
                XCTAssertTrue([rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite })
                XCTAssertGreaterThanOrEqual(rect.width, 0)
                XCTAssertGreaterThanOrEqual(rect.height, 0)
            }
            XCTAssertEqual(layout.tree.size, .zero,
                           "An absent viewport must not reserve a background tree")
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
        for theme in SurroundTheme.allCases where theme != .rakedGarden {
            XCTAssertFalse(theme.board.gridStyle.usesRaggedEdges(at: 48))
        }
        // Small boards are solid: the scratched grid starts at the detail threshold.
        let style = SurroundTheme.rakedGarden.board.gridStyle
        XCTAssertFalse(style.usesRaggedEdges(at: 13.99))
        XCTAssertTrue(style.usesRaggedEdges(at: 14))
        XCTAssertTrue(style.usesRaggedEdges(at: 48))
        XCTAssertTrue(RaggedGridGeometry(width: 19, height: 19, cellSize: 9.99, lineScale: 1.6).path.isEmpty)
    }

    func testStitchedGridIsMeadowOnlyAndFallsBackOnSmallBoards() {
        for theme in SurroundTheme.allCases {
            for scheme: ColorScheme in [.light, .dark] {
                let style = theme.board(for: scheme).gridStyle
                for cell: CGFloat in [0, 7, 13, 13.99] {
                    XCTAssertFalse(style.usesStitches(at: cell), "Small boards retain only their straight grid")
                    XCTAssertFalse(style.usesPaddedCells(at: cell), "Small boards never draw padded-cell shading")
                }
                for cell: CGFloat in [14, 20, 48] {
                    XCTAssertEqual(style.usesStitches(at: cell), theme == .feltMeadow)
                    XCTAssertEqual(style.usesPaddedCells(at: cell), theme == .feltMeadow)
                }
            }
        }
    }

    func testFeltPaddedCellsLeaveEveryPlayingIntersectionAndSeamClear() {
        for (width, height) in [(2, 3), (3, 2), (9, 9), (13, 13), (19, 19), (25, 25), (9, 19), (19, 9)] {
            // Compact geometry remains valid while its detail layer is hidden;
            // crossing 14 pt must not reconstruct or shift the playing grid.
            for cell: CGFloat in [7, 13.99, 14, 20, 30, 48, 64] {
                let geometry = FeltGridGeometry(width: width, height: height, cellSize: cell)
                let cells = geometry.cellRects, path = geometry.path
                // Hit-test with Core Graphics. On iOS 26 and earlier, SwiftUI's
                // Path.contains counts a seam point as inside when it lies on
                // the line through the cells' subpath start points.
                let shape = path.cgPath
                let gridRect = CGRect(x: cell / 2, y: cell / 2,
                                      width: CGFloat(width - 1) * cell, height: CGFloat(height - 1) * cell)
                XCTAssertEqual(geometry.gridRect, gridRect)
                XCTAssertEqual(cells.count, (width - 1) * (height - 1))
                XCTAssertGreaterThan(geometry.seamWidth, 0)
                XCTAssertLessThan(geometry.seamWidth, cell / 4)
                XCTAssertGreaterThan(geometry.cellCornerRadius, 0)
                var cellCenters = Set<[Int]>()
                for rect in cells {
                    XCTAssertTrue(gridRect.contains(rect), "Padding stays within the original grid footprint")
                    XCTAssertGreaterThan(rect.width, 0)
                    XCTAssertGreaterThan(rect.height, 0)
                    XCTAssertEqual(rect.width + geometry.seamWidth, cell, accuracy: 0.000001)
                    XCTAssertEqual(rect.height + geometry.seamWidth, cell, accuracy: 0.000001)
                    XCTAssertLessThanOrEqual(geometry.cellCornerRadius, min(rect.width, rect.height) / 2)
                    let column = rect.midX / cell, row = rect.midY / cell
                    XCTAssertEqual(column, column.rounded(), accuracy: 0.000001)
                    XCTAssertEqual(row, row.rounded(), accuracy: 0.000001)
                    XCTAssertTrue((1..<width).contains(Int(column.rounded())))
                    XCTAssertTrue((1..<height).contains(Int(row.rounded())))
                    cellCenters.insert([Int(row.rounded()), Int(column.rounded())])
                    XCTAssertTrue(shape.contains(CGPoint(x: rect.midX, y: rect.midY)),
                                  "Every interval contains its padded center")
                }
                XCTAssertEqual(cellCenters.count, (width - 1) * (height - 1), "No interval is missing or duplicated")
                XCTAssertTrue(gridRect.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingRect))
                for row in 0..<height {
                    for column in 0..<width {
                        let intersection = CGPoint(x: (CGFloat(column) + 0.5) * cell,
                                                   y: (CGFloat(row) + 0.5) * cell)
                        XCTAssertFalse(shape.contains(intersection),
                                       "A padded face must not cover a move's intersection")
                        if column < width - 1 {
                            XCTAssertFalse(shape.contains(CGPoint(x: intersection.x + cell / 2,
                                                                  y: intersection.y)))
                        }
                        if row < height - 1 {
                            XCTAssertFalse(shape.contains(CGPoint(x: intersection.x,
                                                                  y: intersection.y + cell / 2)))
                        }
                    }
                }
            }
        }
    }

    func testFeltPaddedCellsCoverEverySupportedBoardDimension() {
        let cell: CGFloat = 20
        for width in 2...25 {
            for height in 2...25 {
                let geometry = FeltGridGeometry(width: width, height: height, cellSize: cell)
                let cells = geometry.cellRects
                let expectedGrid = CGRect(x: cell / 2, y: cell / 2,
                                          width: CGFloat(width - 1) * cell, height: CGFloat(height - 1) * cell)
                XCTAssertEqual(geometry.gridRect, expectedGrid, "\(width)×\(height)")
                XCTAssertEqual(cells.count, (width - 1) * (height - 1), "\(width)×\(height)")
                XCTAssertTrue(cells.allSatisfy(expectedGrid.contains), "Every \(width)×\(height) padded cell fits")
                let stitches = StitchedGridGeometry(width: width, height: height, cellSize: cell).path
                let board = CGRect(x: 0, y: 0, width: CGFloat(width) * cell, height: CGFloat(height) * cell)
                XCTAssertFalse(stitches.isEmpty)
                XCTAssertTrue(board.contains(stitches.boundingRect), "\(width)×\(height) thread fits the board")
            }
        }
    }

    func testFeltPaddedCellsResizeContinuouslyWithoutChangingNormalizedGeometry() {
        for (width, height) in [(2, 3), (3, 2), (9, 9), (19, 13), (13, 19), (25, 25)] {
            let reference = FeltGridGeometry(width: width, height: height, cellSize: 20)
            let referencePath = normalizedPathCoordinates(reference.path, cellSize: 20)
            for cell: CGFloat in [7, 13.99, 14, 14.01, 20, 30, 48, 64] {
                let geometry = FeltGridGeometry(width: width, height: height, cellSize: cell)
                XCTAssertEqual(geometry.seamWidth / cell, reference.seamWidth / 20, accuracy: 0.000001)
                XCTAssertEqual(geometry.cellCornerRadius / cell, reference.cellCornerRadius / 20, accuracy: 0.000001)
                let coordinates = normalizedPathCoordinates(geometry.path, cellSize: cell)
                XCTAssertEqual(coordinates.count, referencePath.count, "Resizing retains the same mounted padded cells")
                for (actual, expected) in zip(coordinates, referencePath) {
                    XCTAssertEqual(actual, expected, accuracy: 0.00001)
                }
            }
        }
    }

    func testFeltPaddedCellsHaveSafeGeometryForInvalidLayoutSlots() {
        let invalid = [(0, 19, CGFloat(20)), (1, 19, 20), (19, 0, 20), (19, 1, 20),
                       (-1, 19, 20), (19, -1, 20), (19, 19, 0), (19, 19, -1),
                       (19, 19, .infinity), (19, 19, .nan)]
        for (width, height, cell) in invalid {
            let geometry = FeltGridGeometry(width: width, height: height, cellSize: cell)
            XCTAssertEqual(geometry.gridRect, .zero)
            XCTAssertTrue(geometry.cellRects.isEmpty)
            XCTAssertTrue(geometry.path.isEmpty)
            XCTAssertEqual(geometry.cellCornerRadius, 0)
            XCTAssertEqual(geometry.seamWidth, 0)
        }
    }

    func testStitchedGridStaysWithinSeamsWithoutMovingPlayingIntersections() {
        for (width, height) in [(2, 3), (3, 2), (9, 19), (19, 9), (13, 13), (19, 19), (25, 25)] {
            for cell: CGFloat in [7, 13.99, 14, 20, 48] {
                let path = StitchedGridGeometry(width: width, height: height, cellSize: cell).path
                let geometry = FeltGridGeometry(width: width, height: height, cellSize: cell)
                let playingArea = CGRect(x: 0, y: 0, width: CGFloat(width) * cell, height: CGFloat(height) * cell)
                XCTAssertFalse(path.isEmpty)
                // Path stores coordinates at float precision on Simulator.
                // This remains far below a native display pixel at fractional sizes.
                XCTAssertTrue(playingArea.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingRect),
                              "Thread must not extend into coordinate gutters or alter the board footprint")
                var previous: CGPoint?
                var curves = 0
                func checkSegment(to end: CGPoint, controls: [CGPoint] = []) {
                    guard let start = previous else { return XCTFail("A stitch has a starting point") }
                    let points = [start, end] + controls
                    let horizontal = abs(end.x - start.x) >= abs(end.y - start.y)
                    let across = points.map { horizontal ? $0.y : $0.x }
                    let along = points.map { horizontal ? $0.x : $0.y }
                    let axisIndex = ((horizontal ? start.y : start.x) / cell - 0.5).rounded()
                    XCTAssertTrue((0..<(horizontal ? height : width)).contains(Int(axisIndex)))
                    let axis = (axisIndex + 0.5) * cell
                    for coordinate in across {
                        XCTAssertLessThanOrEqual(abs(coordinate - axis), geometry.seamWidth / 2 + 0.001,
                                                 "Curved thread stays inside a seam on the original grid axis")
                    }
                    let midpoint = ((horizontal ? start.x + end.x : start.y + end.y) / 2) / cell
                    let interval = floor(midpoint - 0.5)
                    XCTAssertTrue((0..<(horizontal ? width - 1 : height - 1)).contains(Int(interval)))
                    for coordinate in along {
                        XCTAssertGreaterThanOrEqual(coordinate, (interval + 0.5) * cell - 0.001)
                        XCTAssertLessThanOrEqual(coordinate, (interval + 1.5) * cell + 0.001)
                    }
                    XCTAssertLessThan(hypot(end.x - start.x, end.y - start.y), cell,
                                      "Each stitch leaves room around both adjacent playing intersections")
                    previous = end
                }
                path.forEach { element in
                    switch element {
                    case .move(to: let point): previous = point
                    case .line(to: let point): checkSegment(to: point)
                    case .quadCurve(to: let point, control: let control):
                        curves += 1
                        checkSegment(to: point, controls: [control])
                    case .curve(to: let point, control1: let first, control2: let second):
                        curves += 1
                        checkSegment(to: point, controls: [first, second])
                    default: XCTFail("A thread is an open segment within one grid interval")
                    }
                }
                XCTAssertGreaterThan(curves, 0, "The soft running thread retains its gentle curvature")
            }
        }
        for size in [0, 1] {
            XCTAssertTrue(StitchedGridGeometry(width: size, height: 19, cellSize: 20).path.isEmpty)
            XCTAssertTrue(StitchedGridGeometry(width: 19, height: size, cellSize: 20).path.isEmpty)
        }
        for cell: CGFloat in [0, -1, .infinity, .nan] {
            XCTAssertTrue(StitchedGridGeometry(width: 19, height: 19, cellSize: cell).path.isEmpty)
        }
    }

    func testFeltStitchesKeepTheirShapeDuringContinuousResizing() {
        for (width, height) in [(2, 3), (3, 2), (9, 9), (19, 13), (13, 19), (25, 25)] {
            let reference = normalizedPathCoordinates(
                StitchedGridGeometry(width: width, height: height, cellSize: 20).path, cellSize: 20)
            for cell: CGFloat in [7, 13.99, 14, 14.01, 20, 30, 48, 64] {
                let coordinates = normalizedPathCoordinates(
                    StitchedGridGeometry(width: width, height: height, cellSize: cell).path, cellSize: cell)
                XCTAssertEqual(coordinates.count, reference.count)
                for (actual, expected) in zip(coordinates, reference) {
                    XCTAssertEqual(actual, expected, accuracy: 0.00001,
                                   "Changing size cannot reseed the stitch variation or move its grid interval")
                }
            }
        }
    }

    private func normalizedPathCoordinates(_ path: Path, cellSize: CGFloat) -> [CGFloat] {
        var coordinates = [CGFloat]()
        func append(_ point: CGPoint) { coordinates += [point.x / cellSize, point.y / cellSize] }
        path.forEach { element in
            switch element {
            case .move(to: let point): coordinates.append(0); append(point)
            case .line(to: let point): coordinates.append(1); append(point)
            case .quadCurve(to: let point, control: let control):
                coordinates.append(2); append(point); append(control)
            case .curve(to: let point, control1: let first, control2: let second):
                coordinates.append(3); append(point); append(first); append(second)
            case .closeSubpath: coordinates.append(4)
            }
        }
        return coordinates
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
        // Typed, separate sweeps: this three-sweep literal of untyped map
        // closures is too complex for the Xcode 26.6 type checker.
        let widths: [CGSize] = (300...1600).map { (width: Int) in
            CGSize(width: CGFloat(width), height: 600)
        }
        let heights: [CGSize] = (300...1600).map { (height: Int) in
            CGSize(width: 900, height: CGFloat(height))
        }
        let squares: [CGSize] = (250...1000).map { (side: Int) in
            CGSize(width: CGFloat(side), height: CGFloat(side))
        }
        for sizes in [widths, heights, squares] {
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
        let cases: [(String, SurroundTheme, UIUserInterfaceStyle)] = SurroundTheme.allCases.flatMap { theme in
            [UIUserInterfaceStyle.light, .dark].map { style in
                ("\(theme.rawValue) \(style == .dark ? "dark" : "light")", theme, style)
            }
        }
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

    /// Crosshairs run over the board between stones. Resolve both system
    /// appearances explicitly: UIKit's bright semantic colors can disappear
    /// against the Standard board even when they read on a black stone.
    func testCrosshairsRemainReadableInEveryThemeAndAppearance() {
        for theme in SurroundTheme.allCases {
            for style: UIUserInterfaceStyle in [.light, .dark] {
                let board = theme.board(for: style == .dark ? .dark : .light)
                let surface = board.surfaceColor(detailed: false)
                for (state, color) in [("legal", board.crosshair.valid),
                                       ("illegal", board.crosshair.invalid),
                                       ("removal", board.crosshair.removal)] {
                    XCTAssertGreaterThanOrEqual(
                        contrast(over(color, surface, style), surface, style: style), 3,
                        "\(theme.rawValue) \(style): \(state) crosshair on board"
                    )
                }
            }
        }
    }

    /// Restore marks sit on half-faded stones. Test their composited colors,
    /// including translucent casings, instead of comparing unblended RGBs.
    /// Both actions must stay distinct on either stone while a group changes
    /// between living and removed states.
    func testRemovalAndRestoreMarksRemainReadableOnLivingAndFadedStones() {
        for theme in SurroundTheme.allCases {
            for style: UIUserInterfaceStyle in [.light, .dark] {
                let board = theme.board(for: style == .dark ? .dark : .light)
                let surface = board.surfaceColor(detailed: false)
                for stoneColor: StoneColor in [.black, .white] {
                    let stone = board.stones(stoneColor)
                    let fadedStone = over(stone.flat.opacity(0.5), surface, style)
                    for (state, background) in [("living", stone.flat), ("removed", fadedStone)] {
                        for (action, color) in [("remove", board.removeMark), ("restore", board.restoreMark)] {
                            let sample = "\(theme.rawValue) \(style): \(action) on \(state) \(stoneColor)"
                            let bareMark = over(color, background, style)
                            if let casing = board.removalMarkCasing {
                                let visibleCasing = over(casing, background, style)
                                let visibleMark = over(color, visibleCasing, style)
                                XCTAssertGreaterThanOrEqual(
                                    max(contrast(visibleMark, background, style: style),
                                        contrast(visibleCasing, background, style: style)), 3,
                                    "\(sample): mark or casing must separate from the stone"
                                )
                                XCTAssertGreaterThanOrEqual(
                                    contrast(visibleMark, visibleCasing, style: style), 3,
                                    "\(sample): preserve the colored action inside its casing"
                                )
                            } else {
                                XCTAssertGreaterThanOrEqual(
                                    contrast(bareMark, background, style: style), 3, sample
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// An estimate may assign either owner to an empty point or to either
    /// player's stone. A common board-colored outline is not sufficient on
    /// black stones, where the black ownership fill can also disappear.
    func testScoreAndEstimateSquaresRemainReadableOnEveryUnderlyingPoint() {
        for theme in SurroundTheme.allCases {
            for style: UIUserInterfaceStyle in [.light, .dark] {
                let board = theme.board(for: style == .dark ? .dark : .light)
                let surface = board.surfaceColor(detailed: false)
                let backgrounds: [(String, StoneColor?, Color)] = [
                    ("empty", nil, surface),
                    ("black", .black, board.black.flat),
                    ("white", .white, board.white.flat),
                    ("removed black", .black, over(board.black.flat.opacity(0.5), surface, style)),
                    ("removed white", .white, over(board.white.flat.opacity(0.5), surface, style)),
                ]
                for owner: StoneColor in [.black, .white] {
                    for (point, stoneColor, background) in backgrounds {
                        let fill = over(board.stones(owner).territoryMark, background, style)
                        let outline = over(board.scoreMarkOutline(on: stoneColor), background, style)
                        XCTAssertGreaterThanOrEqual(
                            max(contrast(fill, background, style: style),
                                contrast(outline, background, style: style)), 3,
                            "\(theme.rawValue) \(style): \(owner) ownership on \(point)"
                        )
                    }
                }
            }
        }
    }

    private func rgbaPixels(for source: CGImage, side: Int) throws -> [UInt8] {
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
